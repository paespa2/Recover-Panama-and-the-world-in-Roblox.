--!strict
-- InGameHudView.luau
-- HUD completo activo en partida:
--  1. Barra superior izquierda (6 botones circulares: Música, Ayuda ?, Leaderboard, Mapa/Globo, Config ⚙, Salir)
--  2. Píldora superior central (IA Defensa/Manual + Tiempo de batalla | WORLD CONTROL + Goal 65%/55% + comparativa Tú vs Líder)
--  3. Esquina superior derecha (Rank #Pos • % + tarjeta colapsable ATTACKS con retirada ↩)
--  4. Dock de comandos inferior (Identidad, TROOPS, ATTACK 10%-100%, GOLD, 12 slots reales 1-0,-,=, botón TIENDA)
--  5. Toast inferior izquierdo, píldora de frente activo bajo cabecera y tooltips contextuales siguiendo el cursor con UIScale.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local InGameHudView = {}
InGameHudView.__index = InGameHudView

export type AttackEntry = {
	id: string,
	targetId: number?,
	targetName: string,
	troops: number,
}

export type HoverContext = {
	kind: "UNCLAIMED" | "OWN" | "OTHER",
	name: string?,
	tag: string?,
	biome: string,
	troops: number?,
	landPct: number?,
	gold: number?,
	color: Color3?,
}

export type InGameStatsUpdate = {
	troops: number?,
	maxTroops: number?,
	troopRate: number?,
	troopsInWar: number?,
	gold: number?,
	goldRate: number?,
	landPct: number?,
	rank: number?,
	leaderName: string?,
	leaderPct: number?,
	goalPct: number?,
	defenseAI: boolean?,
	playerColor: Color3?,
	attacks: { AttackEntry }?,
	weaponCooldowns: { [string]: number }?,
}

export type InGameHudCallbacks = {
	OnToggleMusic: ((isMuted: boolean) -> ())?,
	OnOpenHelp: (() -> ())?,
	OnToggleLeaderboard: (() -> ())?,
	OnCenterMap: (() -> ())?,
	OnOpenSettings: (() -> ())?,
	OnExitToMenu: (() -> ())?,
	OnAttackPercentChanged: ((pct: number) -> ())?,
	OnSelectBuildSlot: ((slotIndex: number, actionMode: string) -> ())?,
	OnToggleDefenseAI: ((enabled: boolean) -> ())?,
	OnRetreatAttack: ((attackId: string) -> ())?,
	OnOpenInGameShop: (() -> ())?,
}

type BuildSlotDef = {
	keyLabel: string,
	id: string,
	actionMode: string,
	name: string,
	icon: string,
	cost: number,
	costText: string,
	hint: string,
}

type BuildSlotRef = {
	def: BuildSlotDef,
	btn: TextButton,
	stroke: UIStroke,
	costLbl: TextLabel,
	cdLbl: TextLabel,
}

type AttackPercentButtonRef = {
	pct: number,
	btn: TextButton,
	stroke: UIStroke,
}

export type InGameHudViewInstance = {
	root: Frame,
	isMuted: boolean,
	attackPercent: number,
	selectedSlotIndex: number?,
	attacksCollapsed: boolean,
	running: boolean,
	cleanups: { () -> () },
	Show: (self: InGameHudViewInstance) -> (),
	Hide: (self: InGameHudViewInstance) -> (),
	SetMusicMuted: (self: InGameHudViewInstance, muted: boolean) -> (),
	SetAttackPercent: (self: InGameHudViewInstance, pct: number) -> (),
	CycleAttackPercent: (self: InGameHudViewInstance, delta: number) -> (),
	SelectBuildSlot: (self: InGameHudViewInstance, slotIndex: number) -> (),
	ClearBuildSlot: (self: InGameHudViewInstance) -> (),
	RetreatLatestAttack: (self: InGameHudViewInstance) -> (),
	ShowToast: (self: InGameHudViewInstance, text: string, duration: number?) -> (),
	UpdateStats: (self: InGameHudViewInstance, stats: InGameStatsUpdate) -> (),
	SetHoverContext: (self: InGameHudViewInstance, ctx: HoverContext?) -> (),
	IsPointOverHud: (self: InGameHudViewInstance, guiPos: Vector2) -> boolean,
	Destroy: (self: InGameHudViewInstance) -> (),
}

local ATTACK_PERCENTS: { number } = { 10, 20, 50, 75, 100 }

local BUILD_SLOTS: { BuildSlotDef } = {
	{ keyLabel = "1", id = "City", actionMode = "BUILD_City", name = "Ciudad", icon = "🏙️", cost = 500, costText = "$500", hint = "Clic en tu territorio (+Capacidad tropas)" },
	{ keyLabel = "2", id = "Port", actionMode = "BUILD_Port", name = "Puerto", icon = "⚓", cost = 400, costText = "$400", hint = "Clic en tu costa (+Oro marítimo y desembarcos)" },
	{ keyLabel = "3", id = "Factory", actionMode = "BUILD_Factory", name = "Fábrica", icon = "🏭", cost = 600, costText = "$600", hint = "Clic en tu territorio (+Ingresos de oro)" },
	{ keyLabel = "4", id = "Post", actionMode = "BUILD_Post", name = "Puesto Def.", icon = "🛡️", cost = 350, costText = "$350", hint = "Clic en frontera propia (Defensa x2.5)" },
	{ keyLabel = "5", id = "SAM", actionMode = "BUILD_SAM", name = "Lanzador SAM", icon = "📡", cost = 750, costText = "$750", hint = "Clic en tu territorio (Intercepta misiles)" },
	{ keyLabel = "6", id = "Silo", actionMode = "BUILD_Silo", name = "Silo Misil", icon = "🚀", cost = 1200, costText = "$1.2K", hint = "Clic en tu territorio (Habilita misiles nucleares)" },
	{ keyLabel = "7", id = "Warship", actionMode = "BUILD_Warship", name = "Navío Guerra", icon = "🚢", cost = 500, costText = "$500", hint = "Clic en tu territorio costero (Patrulla naval)" },
	{ keyLabel = "8", id = "BOMB", actionMode = "WEAPON_BOMB", name = "Bomba", icon = "💣", cost = 250, costText = "$250", hint = "Clic en objetivo terrestre (Radio 5)" },
	{ keyLabel = "9", id = "ATOM_BOMB", actionMode = "WEAPON_ATOM_BOMB", name = "Bomba Atómica", icon = "☢️", cost = 600, costText = "$600", hint = "Clic en objetivo enemigo (Radio 9)" },
	{ keyLabel = "0", id = "HYDROGEN_BOMB", actionMode = "WEAPON_HYDROGEN_BOMB", name = "Bomba H", icon = "💥", cost = 1200, costText = "$1.2K", hint = "Clic en objetivo enemigo (Radio 18, destruye edificios)" },
	{ keyLabel = "-", id = "MIRV", actionMode = "WEAPON_MIRV", name = "Misil MIRV", icon = "☄️", cost = 2200, costText = "$2.2K", hint = "Clic en imperio enemigo (5 ojivas, Radio 26)" },
	{ keyLabel = "=", id = "DEMOLISH", actionMode = "DEMOLISH", name = "Demoler", icon = "🏚️", cost = 0, costText = "+60%", hint = "Clic sobre un edificio propio para recuperar 60% de oro" },
}

local function formatCompact(n: number): string
	local absN = math.abs(n)
	if absN >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif absN >= 10000 then
		return string.format("%.1fK", n / 1000)
	elseif absN >= 1000 then
		return string.format("%.2fK", n / 1000)
	end
	return tostring(math.floor(n + 0.5))
end

local function isPointInsideGui(guiObj: GuiObject, pos: Vector2): boolean
	if not guiObj.Visible then
		return false
	end
	local ap = guiObj.AbsolutePosition
	local as = guiObj.AbsoluteSize
	return pos.X >= ap.X and pos.X <= ap.X + as.X and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
end

local function createHudCircleButton(
	parent: Instance,
	name: string,
	symbol: string,
	order: number
): (TextButton, UIStroke)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.LayoutOrder = order
	btn.Size = UDim2.fromOffset(34, 34)
	btn.BackgroundColor3 = MenuTheme.Colors.UtilityBtnBg
	btn.BackgroundTransparency = 0.08
	btn.AutoButtonColor = false
	btn.Font = MenuTheme.Fonts.Heading
	btn.Text = symbol
	btn.TextColor3 = MenuTheme.Colors.White
	btn.TextSize = 15
	btn.ZIndex = 18
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = MenuTheme.Corners.Pill
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = MenuTheme.Colors.CardStroke
	stroke.Thickness = 1
	stroke.Parent = btn

	return btn, stroke
end

function InGameHudView.new(parent: Instance, callbacks: InGameHudCallbacks?): InGameHudViewInstance
	local cb: InGameHudCallbacks = callbacks or {}
	local cleanups: { () -> () } = {}

	local localPlayer = Players.LocalPlayer
	local displayName = if localPlayer and localPlayer.DisplayName ~= "" then localPlayer.DisplayName else "Comandante"

	local root = Instance.new("Frame")
	root.Name = "InGameHudView"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.Visible = false
	root.ZIndex = 16
	root.Parent = parent

	-- =========================================================================
	-- 1. BARRA SUPERIOR IZQUIERDA (6 botones circulares)
	-- =========================================================================
	local topLeftInset, _ = GuiService:GetGuiInset()
	local leftOffset = math.max(155, topLeftInset.X + 145)

	local hudBar = Instance.new("Frame")
	hudBar.Name = "InGameTopHudBar"
	hudBar.Position = UDim2.fromOffset(leftOffset, 14)
	hudBar.Size = UDim2.fromOffset(238, 38)
	hudBar.BackgroundTransparency = 1
	hudBar.ZIndex = 17
	hudBar.Parent = root

	local hudLayout = Instance.new("UIListLayout")
	hudLayout.FillDirection = Enum.FillDirection.Horizontal
	hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	hudLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hudLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hudLayout.Padding = UDim.new(0, 6)
	hudLayout.Parent = hudBar

	local musicBtn, musicStroke = createHudCircleButton(hudBar, "BtnInGameMusic", "♪", 1)
	local helpBtn, helpStroke = createHudCircleButton(hudBar, "BtnInGameHelp", "?", 2)
	local lbBtn, lbStroke = createHudCircleButton(hudBar, "BtnInGameLeaderboard", "📊", 3)
	local globeBtn, globeStroke = createHudCircleButton(hudBar, "BtnInGameGlobe", "🌐", 4)
	local settingsBtn, settingsStroke = createHudCircleButton(hudBar, "BtnInGameSettings", "⚙", 5)
	local exitBtn, exitStroke = createHudCircleButton(hudBar, "BtnInGameExit", "🚪", 6)

	for _, pair in ipairs({
		{ btn = musicBtn, stroke = musicStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = helpBtn, stroke = helpStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = lbBtn, stroke = lbStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = globeBtn, stroke = globeStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = settingsBtn, stroke = settingsStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = exitBtn, stroke = exitStroke, hover = MenuTheme.Colors.AccentRed },
	}) do
		table.insert(
			cleanups,
			MenuTheme.applyButtonFX(pair.btn, {
				stroke = pair.stroke,
				hoverStrokeColor = pair.hover,
			})
		)
	end

	-- =========================================================================
	-- 2. PÍLDORA SUPERIOR CENTRAL (IA DEFENSA/TIEMPO + WORLD CONTROL)
	-- =========================================================================
	local topCenterPill = Instance.new("Frame")
	topCenterPill.Name = "WorldControlPill"
	topCenterPill.AnchorPoint = Vector2.new(0.5, 0)
	topCenterPill.Position = UDim2.new(0.5, 0, 0, 12)
	topCenterPill.Size = UDim2.fromOffset(440, 58)
	topCenterPill.BackgroundColor3 = MenuTheme.Colors.ModalBg
	topCenterPill.BackgroundTransparency = 0.06
	topCenterPill.BorderSizePixel = 0
	topCenterPill.Active = true
	topCenterPill.ZIndex = 17
	topCenterPill.Parent = root

	local tcpCorner = Instance.new("UICorner")
	tcpCorner.CornerRadius = MenuTheme.Corners.Card
	tcpCorner.Parent = topCenterPill

	local tcpStroke = Instance.new("UIStroke")
	tcpStroke.Color = MenuTheme.Colors.CardStroke
	tcpStroke.Thickness = 1
	tcpStroke.Parent = topCenterPill

	-- Bloque izquierdo clickable: estado IA Defensa + cronómetro de batalla real
	local protBlock = Instance.new("TextButton")
	protBlock.Name = "ProtectedBlock"
	protBlock.Position = UDim2.fromOffset(10, 6)
	protBlock.Size = UDim2.fromOffset(134, 46)
	protBlock.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	protBlock.BackgroundTransparency = 0.45
	protBlock.AutoButtonColor = false
	protBlock.Text = ""
	protBlock.ZIndex = 18
	protBlock.Parent = topCenterPill

	local pbCorner = Instance.new("UICorner")
	pbCorner.CornerRadius = UDim.new(0, 8)
	pbCorner.Parent = protBlock

	local protTitle = Instance.new("TextLabel")
	protTitle.Name = "ProtectedTitle"
	protTitle.Size = UDim2.new(1, -8, 0, 18)
	protTitle.Position = UDim2.fromOffset(6, 3)
	protTitle.BackgroundTransparency = 1
	protTitle.Font = MenuTheme.Fonts.Heading
	protTitle.Text = "🛡️ IA DEF: ON"
	protTitle.TextColor3 = MenuTheme.Colors.BadgeGreen
	protTitle.TextSize = 11
	protTitle.TextXAlignment = Enum.TextXAlignment.Left
	protTitle.TextTruncate = Enum.TextTruncate.AtEnd
	protTitle.ZIndex = 19
	protTitle.Parent = protBlock

	local protTimerLbl = Instance.new("TextLabel")
	protTimerLbl.Name = "ProtectedTimer"
	protTimerLbl.Size = UDim2.new(1, -8, 0, 22)
	protTimerLbl.Position = UDim2.fromOffset(6, 21)
	protTimerLbl.BackgroundTransparency = 1
	protTimerLbl.Font = MenuTheme.Fonts.Heading
	protTimerLbl.Text = "0:00"
	protTimerLbl.TextColor3 = MenuTheme.Colors.White
	protTimerLbl.TextSize = 15
	protTimerLbl.TextXAlignment = Enum.TextXAlignment.Left
	protTimerLbl.ZIndex = 19
	protTimerLbl.Parent = protBlock

	local sepVert = Instance.new("Frame")
	sepVert.Name = "Divider"
	sepVert.Position = UDim2.fromOffset(150, 10)
	sepVert.Size = UDim2.new(0, 1, 1, -20)
	sepVert.BackgroundColor3 = MenuTheme.Colors.CardStroke
	sepVert.BorderSizePixel = 0
	sepVert.ZIndex = 18
	sepVert.Parent = topCenterPill

	-- Bloque derecho: WORLD CONTROL + Goal 65% + barra de progreso + comparativa
	local wcBlock = Instance.new("Frame")
	wcBlock.Name = "WorldControlBlock"
	wcBlock.Position = UDim2.fromOffset(160, 7)
	wcBlock.Size = UDim2.new(1, -172, 1, -14)
	wcBlock.BackgroundTransparency = 1
	wcBlock.ZIndex = 18
	wcBlock.Parent = topCenterPill

	local wcHeader = Instance.new("TextLabel")
	wcHeader.Name = "WCTitle"
	wcHeader.Size = UDim2.new(0.65, 0, 0, 14)
	wcHeader.BackgroundTransparency = 1
	wcHeader.Font = MenuTheme.Fonts.Heading
	wcHeader.Text = "WORLD CONTROL"
	wcHeader.TextColor3 = MenuTheme.Colors.SubtleText
	wcHeader.TextSize = 10
	wcHeader.TextXAlignment = Enum.TextXAlignment.Left
	wcHeader.ZIndex = 18
	wcHeader.Parent = wcBlock

	local wcGoal = Instance.new("TextLabel")
	wcGoal.Name = "GoalLabel"
	wcGoal.AnchorPoint = Vector2.new(1, 0)
	wcGoal.Position = UDim2.fromScale(1, 0)
	wcGoal.Size = UDim2.new(0.35, 0, 0, 14)
	wcGoal.BackgroundTransparency = 1
	wcGoal.Font = MenuTheme.Fonts.Heading
	wcGoal.Text = "Goal 65%"
	wcGoal.TextColor3 = MenuTheme.Colors.MonthlyBadge
	wcGoal.TextSize = 10
	wcGoal.TextXAlignment = Enum.TextXAlignment.Right
	wcGoal.ZIndex = 18
	wcGoal.Parent = wcBlock

	local wcBarBg = Instance.new("Frame")
	wcBarBg.Name = "ControlBarBg"
	wcBarBg.Position = UDim2.fromOffset(0, 18)
	wcBarBg.Size = UDim2.new(1, 0, 0, 8)
	wcBarBg.BackgroundColor3 = Color3.fromHex("#1A263D")
	wcBarBg.BorderSizePixel = 0
	wcBarBg.ZIndex = 18
	wcBarBg.Parent = wcBlock

	local wcBarCorner = Instance.new("UICorner")
	wcBarCorner.CornerRadius = MenuTheme.Corners.Pill
	wcBarCorner.Parent = wcBarBg

	local wcBarFill = Instance.new("Frame")
	wcBarFill.Name = "PlayerFill"
	wcBarFill.Size = UDim2.fromScale(0.01, 1)
	wcBarFill.BackgroundColor3 = MenuTheme.Colors.CyanAccent
	wcBarFill.BorderSizePixel = 0
	wcBarFill.ZIndex = 19
	wcBarFill.Parent = wcBarBg

	local wcFillCorner = Instance.new("UICorner")
	wcFillCorner.CornerRadius = MenuTheme.Corners.Pill
	wcFillCorner.Parent = wcBarFill

	local wcGoalMarker = Instance.new("Frame")
	wcGoalMarker.Name = "GoalMarker"
	wcGoalMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	wcGoalMarker.Position = UDim2.fromScale(0.65, 0.5)
	wcGoalMarker.Size = UDim2.fromOffset(2, 12)
	wcGoalMarker.BackgroundColor3 = MenuTheme.Colors.MonthlyBadge
	wcGoalMarker.BorderSizePixel = 0
	wcGoalMarker.ZIndex = 20
	wcGoalMarker.Parent = wcBarBg

	local wcCompLbl = Instance.new("TextLabel")
	wcCompLbl.Name = "ComparisonText"
	wcCompLbl.Position = UDim2.fromOffset(0, 31)
	wcCompLbl.Size = UDim2.new(1, 0, 0, 16)
	wcCompLbl.BackgroundTransparency = 1
	wcCompLbl.Font = MenuTheme.Fonts.Medium
	wcCompLbl.Text = "■ Tú 0.0%   vs   👑 --- 0.00%"
	wcCompLbl.TextColor3 = MenuTheme.Colors.SubtleText
	wcCompLbl.TextSize = 10
	wcCompLbl.TextXAlignment = Enum.TextXAlignment.Left
	wcCompLbl.TextTruncate = Enum.TextTruncate.AtEnd
	wcCompLbl.ZIndex = 18
	wcCompLbl.Parent = wcBlock

	-- =========================================================================
	-- 3. ESQUINA SUPERIOR DERECHA (Rank Pill + ATTACKS colapsable)
	-- =========================================================================
	local topRightStack = Instance.new("Frame")
	topRightStack.Name = "TopRightStack"
	topRightStack.AnchorPoint = Vector2.new(1, 0)
	topRightStack.Position = UDim2.new(1, -16, 0, 14)
	topRightStack.Size = UDim2.fromOffset(230, 220)
	topRightStack.BackgroundTransparency = 1
	topRightStack.ZIndex = 17
	topRightStack.Parent = root

	local trLayout = Instance.new("UIListLayout")
	trLayout.FillDirection = Enum.FillDirection.Vertical
	trLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	trLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trLayout.Padding = UDim.new(0, 8)
	trLayout.Parent = topRightStack

	local rankPill = Instance.new("TextButton")
	rankPill.Name = "RankPill"
	rankPill.LayoutOrder = 1
	rankPill.Size = UDim2.fromOffset(162, 34)
	rankPill.BackgroundColor3 = MenuTheme.Colors.ModalBg
	rankPill.BackgroundTransparency = 0.06
	rankPill.AutoButtonColor = false
	rankPill.Font = MenuTheme.Fonts.Heading
	rankPill.Text = "🏆  #1 • 0.00%"
	rankPill.TextColor3 = MenuTheme.Colors.MonthlyBadge
	rankPill.TextSize = 13
	rankPill.ZIndex = 18
	rankPill.Parent = topRightStack

	local rpCorner = Instance.new("UICorner")
	rpCorner.CornerRadius = MenuTheme.Corners.Pill
	rpCorner.Parent = rankPill

	local rpStroke = Instance.new("UIStroke")
	rpStroke.Color = MenuTheme.Colors.CardStroke
	rpStroke.Thickness = 1
	rpStroke.Parent = rankPill

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(rankPill, {
			stroke = rpStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanAccent,
		})
	)

	-- Tarjeta colapsable ATTACKS
	local attacksCard = Instance.new("Frame")
	attacksCard.Name = "AttacksCard"
	attacksCard.LayoutOrder = 2
	attacksCard.AutomaticSize = Enum.AutomaticSize.Y
	attacksCard.Size = UDim2.fromOffset(224, 34)
	attacksCard.BackgroundColor3 = MenuTheme.Colors.ModalBg
	attacksCard.BackgroundTransparency = 0.08
	attacksCard.BorderSizePixel = 0
	attacksCard.Active = true
	attacksCard.ZIndex = 17
	attacksCard.Parent = topRightStack

	local acCorner = Instance.new("UICorner")
	acCorner.CornerRadius = UDim.new(0, 10)
	acCorner.Parent = attacksCard

	local acStroke = Instance.new("UIStroke")
	acStroke.Color = MenuTheme.Colors.CardStroke
	acStroke.Thickness = 1
	acStroke.Parent = attacksCard

	local acLayout = Instance.new("UIListLayout")
	acLayout.FillDirection = Enum.FillDirection.Vertical
	acLayout.SortOrder = Enum.SortOrder.LayoutOrder
	acLayout.Padding = UDim.new(0, 4)
	acLayout.Parent = attacksCard

	local acPad = Instance.new("UIPadding")
	acPad.PaddingTop = UDim.new(0, 6)
	acPad.PaddingBottom = UDim.new(0, 6)
	acPad.PaddingLeft = UDim.new(0, 10)
	acPad.PaddingRight = UDim.new(0, 10)
	acPad.Parent = attacksCard

	local attacksHeaderBtn = Instance.new("TextButton")
	attacksHeaderBtn.Name = "AttacksHeader"
	attacksHeaderBtn.LayoutOrder = 1
	attacksHeaderBtn.Size = UDim2.new(1, 0, 0, 22)
	attacksHeaderBtn.BackgroundTransparency = 1
	attacksHeaderBtn.AutoButtonColor = false
	attacksHeaderBtn.Font = MenuTheme.Fonts.Heading
	attacksHeaderBtn.Text = ""
	attacksHeaderBtn.ZIndex = 18
	attacksHeaderBtn.Parent = attacksCard

	local attacksTitleLbl = Instance.new("TextLabel")
	attacksTitleLbl.Name = "AttacksTitle"
	attacksTitleLbl.Size = UDim2.new(0.55, 0, 1, 0)
	attacksTitleLbl.BackgroundTransparency = 1
	attacksTitleLbl.Font = MenuTheme.Fonts.Heading
	attacksTitleLbl.Text = "⚔ ATTACKS"
	attacksTitleLbl.TextColor3 = MenuTheme.Colors.White
	attacksTitleLbl.TextSize = 11
	attacksTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	attacksTitleLbl.ZIndex = 19
	attacksTitleLbl.Parent = attacksHeaderBtn

	local attacksCountLbl = Instance.new("TextLabel")
	attacksCountLbl.Name = "AttacksCount"
	attacksCountLbl.AnchorPoint = Vector2.new(1, 0)
	attacksCountLbl.Position = UDim2.fromScale(1, 0)
	attacksCountLbl.Size = UDim2.new(0.45, 0, 1, 0)
	attacksCountLbl.BackgroundTransparency = 1
	attacksCountLbl.Font = MenuTheme.Fonts.Medium
	attacksCountLbl.Text = "0 fuera v"
	attacksCountLbl.TextColor3 = MenuTheme.Colors.MutedText
	attacksCountLbl.TextSize = 10
	attacksCountLbl.TextXAlignment = Enum.TextXAlignment.Right
	attacksCountLbl.ZIndex = 19
	attacksCountLbl.Parent = attacksHeaderBtn

	local attacksList = Instance.new("Frame")
	attacksList.Name = "AttacksList"
	attacksList.LayoutOrder = 2
	attacksList.AutomaticSize = Enum.AutomaticSize.Y
	attacksList.Size = UDim2.new(1, 0, 0, 0)
	attacksList.BackgroundTransparency = 1
	attacksList.Visible = false
	attacksList.ZIndex = 18
	attacksList.Parent = attacksCard

	local alLayout = Instance.new("UIListLayout")
	alLayout.FillDirection = Enum.FillDirection.Vertical
	alLayout.SortOrder = Enum.SortOrder.LayoutOrder
	alLayout.Padding = UDim.new(0, 4)
	alLayout.Parent = attacksList

	-- =========================================================================
	-- 4. DOCK DE COMANDOS INFERIOR
	-- =========================================================================
	local bottomDock = Instance.new("Frame")
	bottomDock.Name = "BottomCommandDock"
	bottomDock.AnchorPoint = Vector2.new(0.5, 1)
	bottomDock.Position = UDim2.new(0.5, 0, 1, -12)
	bottomDock.Size = UDim2.fromOffset(1252, 92)
	bottomDock.BackgroundColor3 = MenuTheme.Colors.ModalBg
	bottomDock.BackgroundTransparency = 0.06
	bottomDock.BorderSizePixel = 0
	bottomDock.Active = true
	bottomDock.ZIndex = 18
	bottomDock.Parent = root

	local bdCorner = Instance.new("UICorner")
	bdCorner.CornerRadius = MenuTheme.Corners.Card
	bdCorner.Parent = bottomDock

	local bdStroke = Instance.new("UIStroke")
	bdStroke.Color = MenuTheme.Colors.CardStroke
	bdStroke.Thickness = 1
	bdStroke.Parent = bottomDock

	local bdPad = Instance.new("UIPadding")
	bdPad.PaddingTop = UDim.new(0, 8)
	bdPad.PaddingBottom = UDim.new(0, 8)
	bdPad.PaddingLeft = UDim.new(0, 12)
	bdPad.PaddingRight = UDim.new(0, 12)
	bdPad.Parent = bottomDock

	local bdLayout = Instance.new("UIListLayout")
	bdLayout.FillDirection = Enum.FillDirection.Horizontal
	bdLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	bdLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bdLayout.Padding = UDim.new(0, 10)
	bdLayout.Parent = bottomDock

	-- 4.1 Bloque Identidad
	local idBlock = Instance.new("Frame")
	idBlock.Name = "IdentityBlock"
	idBlock.LayoutOrder = 1
	idBlock.Size = UDim2.fromOffset(124, 74)
	idBlock.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	idBlock.BackgroundTransparency = 0.25
	idBlock.BorderSizePixel = 0
	idBlock.ZIndex = 19
	idBlock.Parent = bottomDock

	local idCorner = Instance.new("UICorner")
	idCorner.CornerRadius = UDim.new(0, 8)
	idCorner.Parent = idBlock

	local idSwatch = Instance.new("Frame")
	idSwatch.Name = "PlayerSwatch"
	idSwatch.Position = UDim2.fromOffset(8, 12)
	idSwatch.Size = UDim2.fromOffset(14, 14)
	idSwatch.BackgroundColor3 = MenuTheme.Colors.CyanAccent
	idSwatch.BorderSizePixel = 0
	idSwatch.ZIndex = 20
	idSwatch.Parent = idBlock

	local swCorner = Instance.new("UICorner")
	swCorner.CornerRadius = UDim.new(0, 4)
	swCorner.Parent = idSwatch

	local idNameLbl = Instance.new("TextLabel")
	idNameLbl.Name = "PlayerName"
	idNameLbl.Position = UDim2.fromOffset(26, 10)
	idNameLbl.Size = UDim2.new(1, -32, 0, 18)
	idNameLbl.BackgroundTransparency = 1
	idNameLbl.Font = MenuTheme.Fonts.Heading
	idNameLbl.Text = displayName
	idNameLbl.TextColor3 = MenuTheme.Colors.White
	idNameLbl.TextSize = 12
	idNameLbl.TextXAlignment = Enum.TextXAlignment.Left
	idNameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	idNameLbl.ZIndex = 20
	idNameLbl.Parent = idBlock

	local idNameConstraint = Instance.new("UITextSizeConstraint")
	idNameConstraint.MaxTextSize = 13
	idNameConstraint.MinTextSize = 9
	idNameConstraint.Parent = idNameLbl

	local idWorldPctLbl = Instance.new("TextLabel")
	idWorldPctLbl.Name = "WorldPct"
	idWorldPctLbl.Position = UDim2.fromOffset(8, 36)
	idWorldPctLbl.Size = UDim2.new(1, -14, 0, 24)
	idWorldPctLbl.BackgroundTransparency = 1
	idWorldPctLbl.Font = MenuTheme.Fonts.Medium
	idWorldPctLbl.Text = "0.00% del mundo"
	idWorldPctLbl.TextColor3 = MenuTheme.Colors.SubtleText
	idWorldPctLbl.TextSize = 11
	idWorldPctLbl.TextXAlignment = Enum.TextXAlignment.Left
	idWorldPctLbl.TextTruncate = Enum.TextTruncate.AtEnd
	idWorldPctLbl.ZIndex = 20
	idWorldPctLbl.Parent = idBlock

	-- 4.2 Bloque TROOPS
	local troopsBlock = Instance.new("Frame")
	troopsBlock.Name = "TroopsBlock"
	troopsBlock.LayoutOrder = 2
	troopsBlock.Size = UDim2.fromOffset(150, 74)
	troopsBlock.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	troopsBlock.BackgroundTransparency = 0.25
	troopsBlock.BorderSizePixel = 0
	troopsBlock.ZIndex = 19
	troopsBlock.Parent = bottomDock

	local tbCorner = Instance.new("UICorner")
	tbCorner.CornerRadius = UDim.new(0, 8)
	tbCorner.Parent = troopsBlock

	local tbTitle = Instance.new("TextLabel")
	tbTitle.Position = UDim2.fromOffset(8, 4)
	tbTitle.Size = UDim2.fromOffset(60, 14)
	tbTitle.BackgroundTransparency = 1
	tbTitle.Font = MenuTheme.Fonts.Heading
	tbTitle.Text = "TROOPS"
	tbTitle.TextColor3 = MenuTheme.Colors.MutedText
	tbTitle.TextSize = 9
	tbTitle.TextXAlignment = Enum.TextXAlignment.Left
	tbTitle.ZIndex = 20
	tbTitle.Parent = troopsBlock

	local tbRateLbl = Instance.new("TextLabel")
	tbRateLbl.Name = "TroopRate"
	tbRateLbl.AnchorPoint = Vector2.new(1, 0)
	tbRateLbl.Position = UDim2.new(1, -8, 0, 4)
	tbRateLbl.Size = UDim2.fromOffset(68, 14)
	tbRateLbl.BackgroundTransparency = 1
	tbRateLbl.Font = MenuTheme.Fonts.Heading
	tbRateLbl.Text = "+0/s"
	tbRateLbl.TextColor3 = MenuTheme.Colors.BadgeGreen
	tbRateLbl.TextSize = 10
	tbRateLbl.TextXAlignment = Enum.TextXAlignment.Right
	tbRateLbl.ZIndex = 20
	tbRateLbl.Parent = troopsBlock

	local tbValueLbl = Instance.new("TextLabel")
	tbValueLbl.Name = "TroopValue"
	tbValueLbl.Position = UDim2.fromOffset(8, 20)
	tbValueLbl.Size = UDim2.new(1, -16, 0, 18)
	tbValueLbl.BackgroundTransparency = 1
	tbValueLbl.Font = MenuTheme.Fonts.Heading
	tbValueLbl.Text = "3.00K / 10.0K"
	tbValueLbl.TextColor3 = MenuTheme.Colors.White
	tbValueLbl.TextSize = 13
	tbValueLbl.TextXAlignment = Enum.TextXAlignment.Left
	tbValueLbl.TextTruncate = Enum.TextTruncate.AtEnd
	tbValueLbl.ZIndex = 20
	tbValueLbl.Parent = troopsBlock

	local tbBarBg = Instance.new("Frame")
	tbBarBg.Position = UDim2.fromOffset(8, 42)
	tbBarBg.Size = UDim2.new(1, -16, 0, 6)
	tbBarBg.BackgroundColor3 = Color3.fromHex("#1E293B")
	tbBarBg.BorderSizePixel = 0
	tbBarBg.ZIndex = 20
	tbBarBg.Parent = troopsBlock

	local tbbCorner = Instance.new("UICorner")
	tbbCorner.CornerRadius = MenuTheme.Corners.Pill
	tbbCorner.Parent = tbBarBg

	local tbBarFill = Instance.new("Frame")
	tbBarFill.Size = UDim2.fromScale(0.30, 1)
	tbBarFill.BackgroundColor3 = MenuTheme.Colors.CyanAccent
	tbBarFill.BorderSizePixel = 0
	tbBarFill.ZIndex = 21
	tbBarFill.Parent = tbBarBg

	local tbfCorner = Instance.new("UICorner")
	tbfCorner.CornerRadius = MenuTheme.Corners.Pill
	tbfCorner.Parent = tbBarFill

	local tbWarLbl = Instance.new("TextLabel")
	tbWarLbl.Name = "TroopsInWar"
	tbWarLbl.Position = UDim2.fromOffset(8, 52)
	tbWarLbl.Size = UDim2.new(1, -16, 0, 16)
	tbWarLbl.BackgroundTransparency = 1
	tbWarLbl.Font = MenuTheme.Fonts.Bold
	tbWarLbl.Text = "0 en guerra"
	tbWarLbl.TextColor3 = MenuTheme.Colors.MutedText
	tbWarLbl.TextSize = 10
	tbWarLbl.TextXAlignment = Enum.TextXAlignment.Left
	tbWarLbl.ZIndex = 20
	tbWarLbl.Parent = troopsBlock

	-- 4.3 Bloque ATTACK (10%..100%)
	local attackBlock = Instance.new("Frame")
	attackBlock.Name = "AttackBlock"
	attackBlock.LayoutOrder = 3
	attackBlock.Size = UDim2.fromOffset(204, 74)
	attackBlock.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	attackBlock.BackgroundTransparency = 0.25
	attackBlock.BorderSizePixel = 0
	attackBlock.ZIndex = 19
	attackBlock.Parent = bottomDock

	local abCorner = Instance.new("UICorner")
	abCorner.CornerRadius = UDim.new(0, 8)
	abCorner.Parent = attackBlock

	local abTitle = Instance.new("TextLabel")
	abTitle.Position = UDim2.fromOffset(8, 4)
	abTitle.Size = UDim2.fromOffset(80, 14)
	abTitle.BackgroundTransparency = 1
	abTitle.Font = MenuTheme.Fonts.Heading
	abTitle.Text = "ATTACK"
	abTitle.TextColor3 = MenuTheme.Colors.MutedText
	abTitle.TextSize = 9
	abTitle.TextXAlignment = Enum.TextXAlignment.Left
	abTitle.ZIndex = 20
	abTitle.Parent = attackBlock

	local abActivePctLbl = Instance.new("TextLabel")
	abActivePctLbl.Name = "ActivePercentLabel"
	abActivePctLbl.AnchorPoint = Vector2.new(1, 0)
	abActivePctLbl.Position = UDim2.new(1, -8, 0, 4)
	abActivePctLbl.Size = UDim2.fromOffset(60, 14)
	abActivePctLbl.BackgroundTransparency = 1
	abActivePctLbl.Font = MenuTheme.Fonts.Heading
	abActivePctLbl.Text = "20%"
	abActivePctLbl.TextColor3 = MenuTheme.Colors.PlaySoloBg
	abActivePctLbl.TextSize = 11
	abActivePctLbl.TextXAlignment = Enum.TextXAlignment.Right
	abActivePctLbl.ZIndex = 20
	abActivePctLbl.Parent = attackBlock

	local pctRow = Instance.new("Frame")
	pctRow.Name = "PctButtons"
	pctRow.Position = UDim2.fromOffset(6, 22)
	pctRow.Size = UDim2.new(1, -12, 0, 28)
	pctRow.BackgroundTransparency = 1
	pctRow.ZIndex = 20
	pctRow.Parent = attackBlock

	local pctLayout = Instance.new("UIListLayout")
	pctLayout.FillDirection = Enum.FillDirection.Horizontal
	pctLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pctLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pctLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pctLayout.Padding = UDim.new(0, 4)
	pctLayout.Parent = pctRow

	local abSendLbl = Instance.new("TextLabel")
	abSendLbl.Name = "SendTroopsLabel"
	abSendLbl.Position = UDim2.fromOffset(8, 53)
	abSendLbl.Size = UDim2.new(1, -16, 0, 16)
	abSendLbl.BackgroundTransparency = 1
	abSendLbl.Font = MenuTheme.Fonts.Regular
	abSendLbl.Text = "Envía 600 tropas"
	abSendLbl.TextColor3 = MenuTheme.Colors.SubtleText
	abSendLbl.TextSize = 10
	abSendLbl.TextXAlignment = Enum.TextXAlignment.Center
	abSendLbl.ZIndex = 20
	abSendLbl.Parent = attackBlock

	-- 4.4 Bloque GOLD
	local goldBlock = Instance.new("Frame")
	goldBlock.Name = "GoldBlock"
	goldBlock.LayoutOrder = 4
	goldBlock.Size = UDim2.fromOffset(102, 74)
	goldBlock.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	goldBlock.BackgroundTransparency = 0.25
	goldBlock.BorderSizePixel = 0
	goldBlock.ZIndex = 19
	goldBlock.Parent = bottomDock

	local gbCorner = Instance.new("UICorner")
	gbCorner.CornerRadius = UDim.new(0, 8)
	gbCorner.Parent = goldBlock

	local gbTitle = Instance.new("TextLabel")
	gbTitle.Position = UDim2.fromOffset(8, 4)
	gbTitle.Size = UDim2.new(1, -16, 0, 14)
	gbTitle.BackgroundTransparency = 1
	gbTitle.Font = MenuTheme.Fonts.Heading
	gbTitle.Text = "GOLD"
	gbTitle.TextColor3 = MenuTheme.Colors.MutedText
	gbTitle.TextSize = 9
	gbTitle.TextXAlignment = Enum.TextXAlignment.Left
	gbTitle.ZIndex = 20
	gbTitle.Parent = goldBlock

	local gbValueLbl = Instance.new("TextLabel")
	gbValueLbl.Name = "GoldValue"
	gbValueLbl.Position = UDim2.fromOffset(8, 22)
	gbValueLbl.Size = UDim2.new(1, -16, 0, 22)
	gbValueLbl.BackgroundTransparency = 1
	gbValueLbl.Font = MenuTheme.Fonts.Heading
	gbValueLbl.Text = "◉ 700"
	gbValueLbl.TextColor3 = MenuTheme.Colors.MonthlyBadge
	gbValueLbl.TextSize = 14
	gbValueLbl.TextXAlignment = Enum.TextXAlignment.Left
	gbValueLbl.TextTruncate = Enum.TextTruncate.AtEnd
	gbValueLbl.ZIndex = 20
	gbValueLbl.Parent = goldBlock

	local gbRateLbl = Instance.new("TextLabel")
	gbRateLbl.Name = "GoldRate"
	gbRateLbl.Position = UDim2.fromOffset(8, 48)
	gbRateLbl.Size = UDim2.new(1, -16, 0, 16)
	gbRateLbl.BackgroundTransparency = 1
	gbRateLbl.Font = MenuTheme.Fonts.Heading
	gbRateLbl.Text = "+0/s"
	gbRateLbl.TextColor3 = MenuTheme.Colors.BadgeGreen
	gbRateLbl.TextSize = 11
	gbRateLbl.TextXAlignment = Enum.TextXAlignment.Left
	gbRateLbl.ZIndex = 20
	gbRateLbl.Parent = goldBlock

	-- 4.5 Barra de 12 slots de construcción/armas
	local slotsFrame = Instance.new("Frame")
	slotsFrame.Name = "BuildSlotsFrame"
	slotsFrame.LayoutOrder = 5
	slotsFrame.Size = UDim2.fromOffset(536, 74)
	slotsFrame.BackgroundTransparency = 1
	slotsFrame.ZIndex = 19
	slotsFrame.Parent = bottomDock

	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.FillDirection = Enum.FillDirection.Horizontal
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	slotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotsLayout.Padding = UDim.new(0, 4)
	slotsLayout.Parent = slotsFrame

	-- 4.6 Botón TIENDA / TÁCTICA en el extremo derecho
	local shopBtn = Instance.new("TextButton")
	shopBtn.Name = "BtnInGameShop"
	shopBtn.LayoutOrder = 6
	shopBtn.Size = UDim2.fromOffset(66, 74)
	shopBtn.BackgroundColor3 = MenuTheme.Colors.PlaySoloBg
	shopBtn.AutoButtonColor = false
	shopBtn.Text = ""
	shopBtn.ZIndex = 19
	shopBtn.Parent = bottomDock

	local sbCorner = Instance.new("UICorner")
	sbCorner.CornerRadius = UDim.new(0, 10)
	sbCorner.Parent = shopBtn

	local shopIcon = Instance.new("TextLabel")
	shopIcon.Position = UDim2.fromOffset(0, 8)
	shopIcon.Size = UDim2.new(1, 0, 0, 32)
	shopIcon.BackgroundTransparency = 1
	shopIcon.Font = MenuTheme.Fonts.Title
	shopIcon.Text = "🛒"
	shopIcon.TextColor3 = MenuTheme.Colors.DarkText
	shopIcon.TextSize = 24
	shopIcon.ZIndex = 20
	shopIcon.Parent = shopBtn

	local shopLbl = Instance.new("TextLabel")
	shopLbl.Position = UDim2.fromOffset(0, 44)
	shopLbl.Size = UDim2.new(1, 0, 0, 20)
	shopLbl.BackgroundTransparency = 1
	shopLbl.Font = MenuTheme.Fonts.Heading
	shopLbl.Text = "TIENDA"
	shopLbl.TextColor3 = MenuTheme.Colors.DarkText
	shopLbl.TextSize = 10
	shopLbl.ZIndex = 20
	shopLbl.Parent = shopBtn

	local shopBadge = Instance.new("Frame")
	shopBadge.Name = "ShopBadge"
	shopBadge.AnchorPoint = Vector2.new(1, 0)
	shopBadge.Position = UDim2.new(1, 4, 0, -4)
	shopBadge.Size = UDim2.fromOffset(20, 20)
	shopBadge.BackgroundColor3 = Color3.fromHex("#EF4444")
	shopBadge.BorderSizePixel = 0
	shopBadge.ZIndex = 21
	shopBadge.Parent = shopBtn

	local sbgCorner = Instance.new("UICorner")
	sbgCorner.CornerRadius = MenuTheme.Corners.Pill
	sbgCorner.Parent = shopBadge

	local shopBadgeText = Instance.new("TextLabel")
	shopBadgeText.Size = UDim2.fromScale(1, 1)
	shopBadgeText.BackgroundTransparency = 1
	shopBadgeText.Font = MenuTheme.Fonts.Heading
	shopBadgeText.Text = "6"
	shopBadgeText.TextColor3 = MenuTheme.Colors.White
	shopBadgeText.TextSize = 11
	shopBadgeText.ZIndex = 22
	shopBadgeText.Parent = shopBadge

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(shopBtn, {
			baseColor = MenuTheme.Colors.PlaySoloBg,
			hoverColor = MenuTheme.Colors.PlaySoloHover,
		})
	)

	-- =========================================================================
	-- 5. TOAST INFERIOR IZQUIERDO Y PÍLDORA DE FRENTE ACTIVO BAJO CABECERA
	-- =========================================================================
	local toastFrame = Instance.new("Frame")
	toastFrame.Name = "MatchToast"
	toastFrame.AnchorPoint = Vector2.new(0, 1)
	toastFrame.Position = UDim2.new(0, 16, 1, -114)
	toastFrame.Size = UDim2.fromOffset(330, 36)
	toastFrame.BackgroundColor3 = MenuTheme.Colors.ModalBg
	toastFrame.BackgroundTransparency = 0.08
	toastFrame.BorderSizePixel = 0
	toastFrame.Visible = false
	toastFrame.ZIndex = 19
	toastFrame.Parent = root

	local tfCorner = Instance.new("UICorner")
	tfCorner.CornerRadius = UDim.new(0, 8)
	tfCorner.Parent = toastFrame

	local tfStroke = Instance.new("UIStroke")
	tfStroke.Color = MenuTheme.Colors.CyanBorder
	tfStroke.Thickness = 1
	tfStroke.Parent = toastFrame

	local toastLbl = Instance.new("TextLabel")
	toastLbl.Name = "ToastText"
	toastLbl.Position = UDim2.fromOffset(10, 0)
	toastLbl.Size = UDim2.new(1, -20, 1, 0)
	toastLbl.BackgroundTransparency = 1
	toastLbl.Font = MenuTheme.Fonts.Bold
	toastLbl.Text = "The match has begun. Expand!"
	toastLbl.TextColor3 = MenuTheme.Colors.White
	toastLbl.TextSize = 12
	toastLbl.TextXAlignment = Enum.TextXAlignment.Left
	toastLbl.TextTruncate = Enum.TextTruncate.AtEnd
	toastLbl.ZIndex = 20
	toastLbl.Parent = toastFrame

	-- Píldora centrada justo debajo de WorldControlPill cuando hay ataques reales activos
	local frontPill = Instance.new("Frame")
	frontPill.Name = "ActiveFrontPill"
	frontPill.AnchorPoint = Vector2.new(0.5, 0)
	frontPill.Position = UDim2.new(0.5, 0, 0, 76)
	frontPill.Size = UDim2.fromOffset(240, 26)
	frontPill.BackgroundColor3 = MenuTheme.Colors.ModalBg
	frontPill.BackgroundTransparency = 0.10
	frontPill.BorderSizePixel = 0
	frontPill.Visible = false
	frontPill.ZIndex = 17
	frontPill.Parent = root

	local fpCorner = Instance.new("UICorner")
	fpCorner.CornerRadius = MenuTheme.Corners.Pill
	fpCorner.Parent = frontPill

	local fpStroke = Instance.new("UIStroke")
	fpStroke.Color = MenuTheme.Colors.PlaySoloBg
	fpStroke.Thickness = 1
	fpStroke.Parent = frontPill

	local frontPillLbl = Instance.new("TextLabel")
	frontPillLbl.Name = "FrontText"
	frontPillLbl.Size = UDim2.new(1, -16, 1, 0)
	frontPillLbl.Position = UDim2.fromOffset(8, 0)
	frontPillLbl.BackgroundTransparency = 1
	frontPillLbl.Font = MenuTheme.Fonts.Bold
	frontPillLbl.Text = ""
	frontPillLbl.TextColor3 = MenuTheme.Colors.White
	frontPillLbl.TextSize = 11
	frontPillLbl.TextTruncate = Enum.TextTruncate.AtEnd
	frontPillLbl.ZIndex = 18
	frontPillLbl.Parent = frontPill

	-- =========================================================================
	-- 6. TOOLTIPS CONTEXTUALES FLOTANTES (Cursor con compensación UIScale/GuiInset)
	-- =========================================================================
	local tooltip = Instance.new("Frame")
	tooltip.Name = "ContextTooltip"
	tooltip.Size = UDim2.fromOffset(266, 66)
	tooltip.Position = UDim2.fromOffset(0, 0)
	tooltip.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	tooltip.BackgroundTransparency = 0.12
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 21
	tooltip.Parent = root

	local ttCorner = Instance.new("UICorner")
	ttCorner.CornerRadius = UDim.new(0, 8)
	ttCorner.Parent = tooltip

	local ttStroke = Instance.new("UIStroke")
	ttStroke.Color = MenuTheme.Colors.CardStroke
	ttStroke.Thickness = 1
	ttStroke.Parent = tooltip

	local ttHeaderRow = Instance.new("Frame")
	ttHeaderRow.Position = UDim2.fromOffset(10, 6)
	ttHeaderRow.Size = UDim2.new(1, -20, 0, 18)
	ttHeaderRow.BackgroundTransparency = 1
	ttHeaderRow.ZIndex = 22
	ttHeaderRow.Parent = tooltip

	local ttSwatch = Instance.new("Frame")
	ttSwatch.Position = UDim2.fromOffset(0, 3)
	ttSwatch.Size = UDim2.fromOffset(10, 10)
	ttSwatch.BackgroundColor3 = MenuTheme.Colors.CyanAccent
	ttSwatch.BorderSizePixel = 0
	ttSwatch.Visible = false
	ttSwatch.ZIndex = 22
	ttSwatch.Parent = ttHeaderRow

	local ttsCorner = Instance.new("UICorner")
	ttsCorner.CornerRadius = UDim.new(0, 3)
	ttsCorner.Parent = ttSwatch

	local ttTitleLbl = Instance.new("TextLabel")
	ttTitleLbl.Position = UDim2.fromOffset(0, 0)
	ttTitleLbl.Size = UDim2.new(1, -56, 1, 0)
	ttTitleLbl.BackgroundTransparency = 1
	ttTitleLbl.Font = MenuTheme.Fonts.Bold
	ttTitleLbl.Text = "Terreno neutral · Llanuras"
	ttTitleLbl.TextColor3 = MenuTheme.Colors.White
	ttTitleLbl.TextSize = 11
	ttTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	ttTitleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	ttTitleLbl.ZIndex = 22
	ttTitleLbl.Parent = ttHeaderRow

	local ttTagPill = Instance.new("TextLabel")
	ttTagPill.AnchorPoint = Vector2.new(1, 0.5)
	ttTagPill.Position = UDim2.new(1, 0, 0.5, 0)
	ttTagPill.Size = UDim2.fromOffset(52, 15)
	ttTagPill.BackgroundColor3 = MenuTheme.Colors.CyanBorder
	ttTagPill.Font = MenuTheme.Fonts.Heading
	ttTagPill.Text = "TÚ"
	ttTagPill.TextColor3 = MenuTheme.Colors.DarkText
	ttTagPill.TextSize = 9
	ttTagPill.Visible = false
	ttTagPill.ZIndex = 23
	ttTagPill.Parent = ttHeaderRow

	local ttpCorner = Instance.new("UICorner")
	ttpCorner.CornerRadius = MenuTheme.Corners.Pill
	ttpCorner.Parent = ttTagPill

	local ttMidLbl = Instance.new("TextLabel")
	ttMidLbl.Position = UDim2.fromOffset(10, 26)
	ttMidLbl.Size = UDim2.new(1, -20, 0, 16)
	ttMidLbl.BackgroundTransparency = 1
	ttMidLbl.Font = MenuTheme.Fonts.Bold
	ttMidLbl.Text = "⚔ Clic: expandir"
	ttMidLbl.TextColor3 = MenuTheme.Colors.BadgeGreen
	ttMidLbl.TextSize = 11
	ttMidLbl.TextXAlignment = Enum.TextXAlignment.Left
	ttMidLbl.TextTruncate = Enum.TextTruncate.AtEnd
	ttMidLbl.ZIndex = 22
	ttMidLbl.Parent = tooltip

	local ttFootLbl = Instance.new("TextLabel")
	ttFootLbl.Position = UDim2.fromOffset(10, 44)
	ttFootLbl.Size = UDim2.new(1, -20, 0, 14)
	ttFootLbl.BackgroundTransparency = 1
	ttFootLbl.Font = MenuTheme.Fonts.Regular
	ttFootLbl.Text = "Clic derecho: acciones rápidas"
	ttFootLbl.TextColor3 = MenuTheme.Colors.MutedText
	ttFootLbl.TextSize = 9
	ttFootLbl.TextXAlignment = Enum.TextXAlignment.Left
	ttFootLbl.TextTruncate = Enum.TextTruncate.AtEnd
	ttFootLbl.ZIndex = 22
	ttFootLbl.Parent = tooltip

	-- Estado interno real (sin ataques ficticios)
	local pctButtonRefs: { AttackPercentButtonRef } = {}
	local slotRefs: { BuildSlotRef } = {}
	local activeAttacks: { AttackEntry } = {}
	local stateData = {
		troops = 3000,
		maxTroops = 10000,
		troopRate = 0,
		troopsInWar = 0,
		gold = 700,
		goldRate = 0,
		landPct = 0,
		rank = 1,
		leaderName = "---",
		leaderPct = 0,
		goalPct = 65,
		elapsedSeconds = 0,
		defenseAI = true,
		weaponCooldowns = {} :: { [string]: number },
	}
	local hoverCtxOverride: HoverContext? = nil

	local self = setmetatable({
		root = root,
		isMuted = false,
		attackPercent = 20,
		selectedSlotIndex = nil :: number?,
		attacksCollapsed = false,
		running = false,
		cleanups = cleanups,
		hudBar = hudBar,
		topCenterPill = topCenterPill,
		topRightStack = topRightStack,
		rankPill = rankPill,
		attacksCard = attacksCard,
		bottomDock = bottomDock,
		musicBtn = musicBtn,
		musicStroke = musicStroke,
		protTimerLbl = protTimerLbl,
		protTitle = protTitle,
		wcGoal = wcGoal,
		wcGoalMarker = wcGoalMarker,
		wcBarFill = wcBarFill,
		wcCompLbl = wcCompLbl,
		attacksHeaderBtn = attacksHeaderBtn,
		attacksList = attacksList,
		idSwatch = idSwatch,
		idNameLbl = idNameLbl,
		idWorldPctLbl = idWorldPctLbl,
		tbRateLbl = tbRateLbl,
		tbValueLbl = tbValueLbl,
		tbBarFill = tbBarFill,
		tbWarLbl = tbWarLbl,
		abActivePctLbl = abActivePctLbl,
		abSendLbl = abSendLbl,
		gbValueLbl = gbValueLbl,
		gbRateLbl = gbRateLbl,
		toastFrame = toastFrame,
		toastLbl = toastLbl,
		frontPill = frontPill,
		frontPillLbl = frontPillLbl,
		tooltip = tooltip,
		pctButtonRefs = pctButtonRefs,
		slotRefs = slotRefs,
		activeAttacks = activeAttacks,
		stateData = stateData,
		cb = cb,
	}, InGameHudView)

	local function refreshAttackPercentUI()
		abActivePctLbl.Text = string.format("%d%%", self.attackPercent)
		local sendAmount = math.floor(self.stateData.troops * (self.attackPercent / 100))
		abSendLbl.Text = string.format("Envía %s tropas", MenuTheme.formatNumber(sendAmount))
		for _, ref in ipairs(pctButtonRefs) do
			local active = ref.pct == self.attackPercent
			if active then
				ref.btn.BackgroundColor3 = MenuTheme.Colors.PlaySoloBg
				ref.btn.TextColor3 = MenuTheme.Colors.DarkText
				ref.stroke.Color = MenuTheme.Colors.PlaySoloBg
			else
				ref.btn.BackgroundColor3 = MenuTheme.Colors.CardRowBg
				ref.btn.TextColor3 = MenuTheme.Colors.SubtleText
				ref.stroke.Color = MenuTheme.Colors.CardStroke
			end
		end
	end

	local function refreshBuildSlotsUI()
		local cooldowns = self.stateData.weaponCooldowns
		for idx, ref in ipairs(slotRefs) do
			local canAfford = self.stateData.gold >= ref.def.cost
			if ref.def.id == "DEMOLISH" then
				ref.costLbl.TextColor3 = MenuTheme.Colors.CyanAccent
			else
				ref.costLbl.TextColor3 = if canAfford then MenuTheme.Colors.BadgeGreen else MenuTheme.Colors.AccentRed
			end
			local secs = if cooldowns then cooldowns[ref.def.id] else nil
			if secs and secs > 0.05 then
				ref.cdLbl.Text = tostring(math.ceil(secs)) .. "s"
				ref.cdLbl.Visible = true
			else
				ref.cdLbl.Visible = false
			end
			if self.selectedSlotIndex == idx then
				ref.stroke.Color = MenuTheme.Colors.PlaySoloBg
				ref.stroke.Thickness = 2
				ref.btn.BackgroundColor3 = Color3.fromHex("#2A2418")
			else
				ref.stroke.Color = MenuTheme.Colors.CardStroke
				ref.stroke.Thickness = 1
				ref.btn.BackgroundColor3 = MenuTheme.Colors.SideCardBg
			end
		end
	end

	local function rebuildAttacksList()
		for _, child in ipairs(attacksList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local count = #self.activeAttacks
		local arrow = if self.attacksCollapsed then ">" else "v"
		attacksCountLbl.Text = string.format("%d fuera %s", count, arrow)
		attacksList.Visible = not self.attacksCollapsed and count > 0

		local warSum = 0
		for idx, atk in ipairs(self.activeAttacks) do
			warSum += atk.troops
			local row = Instance.new("Frame")
			row.Name = "AttackRow_" .. atk.id
			row.LayoutOrder = idx
			row.Size = UDim2.new(1, 0, 0, 26)
			row.BackgroundColor3 = MenuTheme.Colors.SideCardBg
			row.BorderSizePixel = 0
			row.ZIndex = 18
			row.Parent = attacksList

			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 6)
			rc.Parent = row

			local atkDot = Instance.new("Frame")
			atkDot.Name = "ActiveDot"
			atkDot.AnchorPoint = Vector2.new(0, 0.5)
			atkDot.Position = UDim2.new(0, 8, 0.5, 0)
			atkDot.Size = UDim2.fromOffset(7, 7)
			atkDot.BackgroundColor3 = MenuTheme.Colors.BadgeGreen
			atkDot.BorderSizePixel = 0
			atkDot.ZIndex = 19
			atkDot.Parent = row

			local adCorner = Instance.new("UICorner")
			adCorner.CornerRadius = MenuTheme.Corners.Pill
			adCorner.Parent = atkDot

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Position = UDim2.fromOffset(20, 0)
			nameLbl.Size = UDim2.new(1, -98, 1, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = MenuTheme.Fonts.Medium
			nameLbl.Text = atk.targetName
			nameLbl.TextColor3 = MenuTheme.Colors.White
			nameLbl.TextSize = 11
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.ZIndex = 19
			nameLbl.Parent = row

			local trLbl = Instance.new("TextLabel")
			trLbl.AnchorPoint = Vector2.new(1, 0)
			trLbl.Position = UDim2.new(1, -28, 0, 0)
			trLbl.Size = UDim2.fromOffset(48, 26)
			trLbl.BackgroundTransparency = 1
			trLbl.Font = MenuTheme.Fonts.Bold
			trLbl.Text = formatCompact(atk.troops)
			trLbl.TextColor3 = MenuTheme.Colors.PlaySoloBg
			trLbl.TextSize = 11
			trLbl.TextXAlignment = Enum.TextXAlignment.Right
			trLbl.ZIndex = 19
			trLbl.Parent = row

			local retBtn = Instance.new("TextButton")
			retBtn.Name = "BtnRetreat"
			retBtn.AnchorPoint = Vector2.new(1, 0.5)
			retBtn.Position = UDim2.new(1, -4, 0.5, 0)
			retBtn.Size = UDim2.fromOffset(20, 20)
			retBtn.BackgroundColor3 = Color3.fromHex("#281722")
			retBtn.AutoButtonColor = false
			retBtn.Font = MenuTheme.Fonts.Heading
			retBtn.Text = "↩"
			retBtn.TextColor3 = MenuTheme.Colors.AccentRed
			retBtn.TextSize = 11
			retBtn.ZIndex = 20
			retBtn.Parent = row

			local rbc = Instance.new("UICorner")
			rbc.CornerRadius = UDim.new(0, 5)
			rbc.Parent = retBtn

			local capturedId = atk.id
			retBtn.MouseButton1Click:Connect(function()
				for i, entry in ipairs(self.activeAttacks) do
					if entry.id == capturedId then
						table.remove(self.activeAttacks, i)
						break
					end
				end
				rebuildAttacksList()
				if cb.OnRetreatAttack then
					cb.OnRetreatAttack(capturedId)
				end
			end)
		end

		self.stateData.troopsInWar = warSum
		tbWarLbl.Text = string.format("%s en guerra", formatCompact(warSum))
		tbWarLbl.TextColor3 = if warSum > 0 then MenuTheme.Colors.AccentRed else MenuTheme.Colors.MutedText
		frontPill.Visible = count > 0
		if count > 0 then
			local first = self.activeAttacks[1]
			frontPillLbl.Text = string.format("⚔ Atacando %s (%s)", first.targetName, formatCompact(first.troops))
		end
	end

	-- Construir los 5 botones rápidos de ATTACK
	for idx, pct in ipairs(ATTACK_PERCENTS) do
		local pBtn = Instance.new("TextButton")
		pBtn.Name = "BtnPct_" .. tostring(pct)
		pBtn.LayoutOrder = idx
		pBtn.Size = UDim2.fromOffset(35, 24)
		pBtn.BackgroundColor3 = MenuTheme.Colors.CardRowBg
		pBtn.AutoButtonColor = false
		pBtn.Font = MenuTheme.Fonts.Heading
		pBtn.Text = tostring(pct) .. "%"
		pBtn.TextColor3 = MenuTheme.Colors.SubtleText
		pBtn.TextSize = 9
		pBtn.ZIndex = 20
		pBtn.Parent = pctRow

		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(0, 6)
		pc.Parent = pBtn

		local ps = Instance.new("UIStroke")
		ps.Color = MenuTheme.Colors.CardStroke
		ps.Thickness = 1
		ps.Parent = pBtn

		local capturedPct = pct
		pBtn.MouseButton1Click:Connect(function()
			self:SetAttackPercent(capturedPct)
		end)

		table.insert(pctButtonRefs, { pct = pct, btn = pBtn, stroke = ps })
	end

	-- Construir los 12 slots reales de construcción/armas (separador vertical entre slot 7 y 8)
	for idx, def in ipairs(BUILD_SLOTS) do
		if idx == 8 then
			local slotDivider = Instance.new("Frame")
			slotDivider.Name = "WeaponsDivider"
			slotDivider.LayoutOrder = 8
			slotDivider.Size = UDim2.fromOffset(1, 54)
			slotDivider.BackgroundColor3 = MenuTheme.Colors.CardStroke
			slotDivider.BorderSizePixel = 0
			slotDivider.ZIndex = 20
			slotDivider.Parent = slotsFrame
		end

		local slotBtn = Instance.new("TextButton")
		slotBtn.Name = "Slot_" .. def.id
		slotBtn.LayoutOrder = if idx <= 7 then idx else idx + 1
		slotBtn.Size = UDim2.fromOffset(40, 68)
		slotBtn.BackgroundColor3 = MenuTheme.Colors.SideCardBg
		slotBtn.AutoButtonColor = false
		slotBtn.Text = ""
		slotBtn.ZIndex = 20
		slotBtn.Parent = slotsFrame

		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0, 7)
		sc.Parent = slotBtn

		local ss = Instance.new("UIStroke")
		ss.Color = MenuTheme.Colors.CardStroke
		ss.Thickness = 1
		ss.Parent = slotBtn

		local keyLbl = Instance.new("TextLabel")
		keyLbl.Position = UDim2.fromOffset(3, 2)
		keyLbl.Size = UDim2.fromOffset(14, 12)
		keyLbl.BackgroundTransparency = 1
		keyLbl.Font = MenuTheme.Fonts.Bold
		keyLbl.Text = def.keyLabel
		keyLbl.TextColor3 = MenuTheme.Colors.MutedText
		keyLbl.TextSize = 8
		keyLbl.TextXAlignment = Enum.TextXAlignment.Left
		keyLbl.ZIndex = 21
		keyLbl.Parent = slotBtn

		local iconLbl = Instance.new("TextLabel")
		iconLbl.Position = UDim2.fromOffset(0, 14)
		iconLbl.Size = UDim2.new(1, 0, 0, 26)
		iconLbl.BackgroundTransparency = 1
		iconLbl.Font = MenuTheme.Fonts.Title
		iconLbl.Text = def.icon
		iconLbl.TextSize = 18
		iconLbl.ZIndex = 21
		iconLbl.Parent = slotBtn

		local costLbl = Instance.new("TextLabel")
		costLbl.Position = UDim2.fromOffset(1, 46)
		costLbl.Size = UDim2.new(1, -2, 0, 16)
		costLbl.BackgroundTransparency = 1
		costLbl.Font = MenuTheme.Fonts.Heading
		costLbl.Text = def.costText
		costLbl.TextColor3 = MenuTheme.Colors.AccentRed
		costLbl.TextSize = 9
		costLbl.TextTruncate = Enum.TextTruncate.AtEnd
		costLbl.ZIndex = 21
		costLbl.Parent = slotBtn

		local cdLbl = Instance.new("TextLabel")
		cdLbl.Name = "CooldownOverlay"
		cdLbl.Size = UDim2.fromScale(1, 1)
		cdLbl.BackgroundColor3 = Color3.fromHex("#050811")
		cdLbl.BackgroundTransparency = 0.3
		cdLbl.Font = MenuTheme.Fonts.Heading
		cdLbl.Text = ""
		cdLbl.TextColor3 = MenuTheme.Colors.White
		cdLbl.TextSize = 12
		cdLbl.Visible = false
		cdLbl.ZIndex = 22
		cdLbl.Parent = slotBtn

		local cdCorner = Instance.new("UICorner")
		cdCorner.CornerRadius = UDim.new(0, 7)
		cdCorner.Parent = cdLbl

		local scaleObj = Instance.new("UIScale")
		scaleObj.Scale = 1
		scaleObj.Parent = slotBtn

		local cEnter = slotBtn.MouseEnter:Connect(function()
			TweenService:Create(scaleObj, MenuTheme.Tweens.Hover, { Scale = 1.04 }):Play()
		end)
		local cLeave = slotBtn.MouseLeave:Connect(function()
			TweenService:Create(scaleObj, MenuTheme.Tweens.Hover, { Scale = 1 }):Play()
		end)
		local cDown = slotBtn.MouseButton1Down:Connect(function()
			TweenService:Create(scaleObj, MenuTheme.Tweens.Press, { Scale = 0.96 }):Play()
		end)
		local cUp = slotBtn.MouseButton1Up:Connect(function()
			TweenService:Create(scaleObj, MenuTheme.Tweens.Hover, { Scale = 1.04 }):Play()
		end)
		table.insert(cleanups, function()
			cEnter:Disconnect()
			cLeave:Disconnect()
			cDown:Disconnect()
			cUp:Disconnect()
		end)

		local capturedIdx = idx
		slotBtn.MouseButton1Click:Connect(function()
			self:SelectBuildSlot(capturedIdx)
		end)

		table.insert(slotRefs, {
			def = def,
			btn = slotBtn,
			stroke = ss,
			costLbl = costLbl,
			cdLbl = cdLbl,
		})
	end

	-- Helper interno para actualizar toda la vista
	local function applyVisualState()
		local s = self.stateData
		protTimerLbl.Text = MenuTheme.formatMMSS(s.elapsedSeconds)
		if s.defenseAI then
			protTitle.Text = "🛡️ IA DEF: ON"
			protTitle.TextColor3 = MenuTheme.Colors.BadgeGreen
		else
			protTitle.Text = "⚔️ MANUAL"
			protTitle.TextColor3 = MenuTheme.Colors.PlaySoloBg
		end

		wcGoal.Text = string.format("Goal %d%%", s.goalPct)
		wcGoalMarker.Position = UDim2.fromScale(math.clamp(s.goalPct / 100, 0.05, 0.99), 0.5)
		wcBarFill.Size = UDim2.fromScale(math.clamp(s.landPct / 100, 0.01, 1), 1)
		if s.rank == 1 and s.landPct > 0 then
			idNameLbl.Text = "👑 " .. displayName
			idNameLbl.TextColor3 = MenuTheme.Colors.MonthlyBadge
			wcCompLbl.Text = if s.leaderName ~= "" and s.leaderName ~= displayName
				then string.format("👑 Tú lideras • %.1f%%   vs   %s %.2f%%", s.landPct, s.leaderName, s.leaderPct)
				else string.format("👑 Tú lideras • %.2f%% del mundo", s.landPct)
			rankPill.Text = string.format("👑  #1 • %.2f%%", s.landPct)
		else
			idNameLbl.Text = displayName
			idNameLbl.TextColor3 = MenuTheme.Colors.White
			wcCompLbl.Text = string.format("■ Tú %.1f%%   vs   👑 %s %.2f%%", s.landPct, s.leaderName, s.leaderPct)
			rankPill.Text = string.format("🏆  #%d • %.2f%%", s.rank, s.landPct)
		end
		idWorldPctLbl.Text = string.format("%.2f%% del mundo", s.landPct)

		tbValueLbl.Text = string.format("%s / %s", formatCompact(s.troops), formatCompact(s.maxTroops))
		tbRateLbl.Text = string.format("+%s/s", formatCompact(s.troopRate))
		tbBarFill.Size = UDim2.fromScale(math.clamp(s.troops / math.max(1, s.maxTroops), 0.02, 1), 1)

		gbValueLbl.Text = "◉ " .. formatCompact(s.gold)
		gbRateLbl.Text = string.format("+%s/s", formatCompact(s.goldRate))

		refreshAttackPercentUI()
		refreshBuildSlotsUI()
	end

	self._refreshVisualState = applyVisualState
	self._rebuildAttacksList = rebuildAttacksList

	applyVisualState()
	rebuildAttacksList()

	-- Tooltip contextual siguiendo el cursor con compensación de GuiInset y UIScale
	local renderConn = RunService.RenderStepped:Connect(function()
		if not self.root.Visible then
			tooltip.Visible = false
			return
		end
		local howTo = parent:FindFirstChild("HowToPlayBackdrop")
		if howTo and howTo:IsA("GuiObject") and howTo.Visible then
			tooltip.Visible = false
			return
		end
		local modal = parent:FindFirstChild("ModalBackdrop")
		if modal and modal:IsA("GuiObject") and modal.Visible then
			tooltip.Visible = false
			return
		end

		local mousePos = UserInputService:GetMouseLocation()
		local inset, _ = GuiService:GetGuiInset()
		local guiPos = mousePos - inset

		local overHud = isPointInsideGui(hudBar, guiPos)
			or isPointInsideGui(topCenterPill, guiPos)
			or isPointInsideGui(rankPill, guiPos)
			or isPointInsideGui(attacksCard, guiPos)
			or isPointInsideGui(bottomDock, guiPos)
		if overHud then
			tooltip.Visible = false
			return
		end

		local cam = Workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		local uiScaleObj = parent:FindFirstChildOfClass("UIScale")
		local scale = if uiScaleObj then math.max(0.01, uiScaleObj.Scale) else 1
		local x = math.clamp((mousePos.X + 16) / scale, 8, math.max(8, vp.X / scale - 274))
		local y = math.clamp((mousePos.Y + 18) / scale, 8, math.max(8, vp.Y / scale - 74))

		local ctx = hoverCtxOverride
		if ctx then
			if ctx.kind == "OWN" then
				ttSwatch.Visible = true
				ttSwatch.BackgroundColor3 = ctx.color or MenuTheme.Colors.CyanAccent
				ttTitleLbl.Position = UDim2.fromOffset(16, 0)
				ttTitleLbl.Text = ctx.name or displayName
				ttTagPill.Visible = true
				ttTagPill.Text = ctx.tag or "TÚ"
				ttTagPill.BackgroundColor3 = MenuTheme.Colors.CyanBorder
				ttMidLbl.Text = string.format(
					"Tu territorio · %s · %s tropas · %.2f%%",
					ctx.biome,
					formatCompact(ctx.troops or self.stateData.troops),
					ctx.landPct or self.stateData.landPct
				)
				ttMidLbl.TextColor3 = MenuTheme.Colors.SubtleText
				ttFootLbl.Text = string.format("Oro: %s · Selecciona [1-7] para construir", formatCompact(ctx.gold or self.stateData.gold))
			elseif ctx.kind == "OTHER" then
				ttSwatch.Visible = true
				ttSwatch.BackgroundColor3 = ctx.color or MenuTheme.Colors.AccentRed
				ttTitleLbl.Position = UDim2.fromOffset(16, 0)
				ttTitleLbl.Text = ctx.name or "Nación"
				ttTagPill.Visible = true
				ttTagPill.Text = ctx.tag or "BOT"
				ttTagPill.BackgroundColor3 = MenuTheme.Colors.MonthlyBadge
				ttMidLbl.Text = string.format(
					"%s · %s tropas · %.2f%%",
					ctx.biome,
					formatCompact(ctx.troops or 0),
					ctx.landPct or 0
				)
				ttMidLbl.TextColor3 = MenuTheme.Colors.AccentRed
				ttFootLbl.Text = "Clic derecho: proponer alianza / acciones"
			else
				ttSwatch.Visible = false
				ttTitleLbl.Position = UDim2.fromOffset(0, 0)
				ttTagPill.Visible = false
				ttTitleLbl.Text = "Terreno neutral · " .. ctx.biome
				local sendN = math.floor(self.stateData.troops * (self.attackPercent / 100))
				ttMidLbl.Text = string.format("⚔ Clic: expandir con %s tropas", formatCompact(sendN))
				ttMidLbl.TextColor3 = MenuTheme.Colors.BadgeGreen
				ttFootLbl.Text = "Clic derecho: acciones rápidas"
			end
			tooltip.Position = UDim2.fromOffset(x, y)
			tooltip.Visible = true
			return
		end

		local bridge = (_G :: any).WorldClientBridge
		if not bridge or not bridge.inspectGuiPos then
			tooltip.Visible = false
			return
		end
		local info = bridge.inspectGuiPos(guiPos)
		if not info or not info.valid then
			tooltip.Visible = false
			return
		end

		local activeSlot = if self.selectedSlotIndex then self.slotRefs[self.selectedSlotIndex] else nil
		if activeSlot then
			local def = activeSlot.def
			ttSwatch.Visible = false
			ttTitleLbl.Position = UDim2.fromOffset(0, 0)
			ttTagPill.Visible = true
			ttTagPill.Text = def.costText
			ttTagPill.BackgroundColor3 = MenuTheme.Colors.PlaySoloBg
			ttTitleLbl.Text = string.format("%s %s · %s", def.icon, def.name, tostring(info.biome or ""))
			if def.id == "DEMOLISH" then
				if info.isMe and info.hasOwnBuilding then
					ttMidLbl.Text = "🏚️ Clic: demoler edificio (+60% oro)"
					ttMidLbl.TextColor3 = MenuTheme.Colors.PlaySoloBg
				else
					ttMidLbl.Text = "Apunta a un edificio propio para demoler"
					ttMidLbl.TextColor3 = MenuTheme.Colors.AccentRed
				end
			elseif string.sub(def.actionMode, 1, 7) == "WEAPON_" then
				if info.isLand then
					ttMidLbl.Text = string.format("🎯 Clic: lanzar %s (%s)", def.name, def.costText)
					ttMidLbl.TextColor3 = MenuTheme.Colors.PlaySoloBg
				else
					ttMidLbl.Text = "Apunta a tierra firme"
					ttMidLbl.TextColor3 = MenuTheme.Colors.AccentRed
				end
			elseif def.id == "Port" then
				if info.isMe and info.isCoastal and not info.hasOwnBuilding then
					ttMidLbl.Text = "⚓ Clic: construir Puerto en costa"
					ttMidLbl.TextColor3 = MenuTheme.Colors.BadgeGreen
				elseif not info.isMe then
					ttMidLbl.Text = "Solo puedes construir en tu territorio"
					ttMidLbl.TextColor3 = MenuTheme.Colors.AccentRed
				elseif not info.isCoastal then
					ttMidLbl.Text = "El Puerto requiere una celda costera"
					ttMidLbl.TextColor3 = MenuTheme.Colors.AccentRed
				else
					ttMidLbl.Text = "Ya existe un edificio en esta celda"
					ttMidLbl.TextColor3 = MenuTheme.Colors.AccentRed
				end
			else
				if info.isMe and not info.hasOwnBuilding then
					ttMidLbl.Text = string.format("🔧 Clic: construir %s (%s)", def.name, def.costText)
					ttMidLbl.TextColor3 = MenuTheme.Colors.BadgeGreen
				elseif not info.isMe then
					ttMidLbl.Text = "Solo puedes construir en tu territorio"
					ttMidLbl.TextColor3 = MenuTheme.Colors.AccentRed
				else
					ttMidLbl.Text = "Ya existe un edificio en esta celda"
					ttMidLbl.TextColor3 = MenuTheme.Colors.AccentRed
				end
			end
			ttFootLbl.Text = "Clic derecho o Esc: volver a modo Ataque"
			tooltip.Position = UDim2.fromOffset(x, y)
			tooltip.Visible = true
			return
		end

		if not info.isLand then
			if info.hasPortInRange then
				ttSwatch.Visible = false
				ttTitleLbl.Position = UDim2.fromOffset(0, 0)
				ttTagPill.Visible = false
				ttTitleLbl.Text = "🌊 Océano · Ruta anfibia activa"
				ttMidLbl.Text = "⚓ Clic en costa cercana para desembarcar"
				ttMidLbl.TextColor3 = MenuTheme.Colors.CyanAccent
				ttFootLbl.Text = "Clic derecho: acciones rápidas"
				tooltip.Position = UDim2.fromOffset(x, y)
				tooltip.Visible = true
			else
				tooltip.Visible = false
			end
			return
		end

		local sendN = math.floor(self.stateData.troops * (self.attackPercent / 100))
		if info.ownerId == 0 then
			ttSwatch.Visible = false
			ttTitleLbl.Position = UDim2.fromOffset(0, 0)
			ttTagPill.Visible = true
			ttTagPill.Text = "NEUTRAL"
			ttTagPill.BackgroundColor3 = MenuTheme.Colors.CardRowBg
			ttTagPill.TextColor3 = MenuTheme.Colors.SubtleText
			ttTitleLbl.Text = "Terreno neutral · " .. tostring(info.biome or "Llanuras")
			ttMidLbl.Text = string.format("⚔ Clic: expandir con %s tropas", formatCompact(sendN))
			ttMidLbl.TextColor3 = MenuTheme.Colors.BadgeGreen
			ttFootLbl.Text = "Clic derecho: acciones rápidas"
		elseif info.isMe then
			ttSwatch.Visible = true
			ttSwatch.BackgroundColor3 = info.color or MenuTheme.Colors.CyanAccent
			ttTitleLbl.Position = UDim2.fromOffset(16, 0)
			ttTitleLbl.Text = tostring(info.name or displayName)
			ttTagPill.Visible = true
			ttTagPill.Text = "TÚ"
			ttTagPill.BackgroundColor3 = MenuTheme.Colors.CyanBorder
			ttTagPill.TextColor3 = MenuTheme.Colors.DarkText
			ttMidLbl.Text = string.format(
				"👑 Tu territorio · %s tropas · %.2f%%",
				formatCompact(self.stateData.troops),
				self.stateData.landPct
			)
			ttMidLbl.TextColor3 = MenuTheme.Colors.SubtleText
			ttFootLbl.Text = "Selecciona [1-7] para construir · Clic der.: menú"
		else
			local isAtWar = false
			for _, atk in ipairs(self.activeAttacks) do
				if atk.targetId ~= nil and atk.targetId == info.ownerId then
					isAtWar = true
					break
				elseif atk.id == tostring(info.ownerId) then
					isAtWar = true
					break
				end
			end

			ttSwatch.Visible = true
			ttSwatch.BackgroundColor3 = info.color or MenuTheme.Colors.AccentRed
			ttTitleLbl.Position = UDim2.fromOffset(16, 0)
			ttTitleLbl.Text = tostring(info.name or ("Nación #" .. tostring(info.ownerId)))
			ttTagPill.Visible = true
			if isAtWar then
				ttTagPill.Text = "AT WAR"
				ttTagPill.BackgroundColor3 = MenuTheme.Colors.PlaySoloBg
				ttTagPill.TextColor3 = MenuTheme.Colors.DarkText
				ttMidLbl.Text = string.format("⚔ Click: attack with %s", formatCompact(sendN))
				ttMidLbl.TextColor3 = MenuTheme.Colors.MonthlyBadge
			elseif info.isAlly then
				ttTagPill.Text = "ALIADO"
				ttTagPill.BackgroundColor3 = MenuTheme.Colors.BadgeGreen
				ttTagPill.TextColor3 = MenuTheme.Colors.DarkText
				ttMidLbl.Text = string.format(
					"🤝 Aliado · %s (Def: %s)",
					tostring(info.biome or ""),
					formatCompact(info.troops or 0)
				)
				ttMidLbl.TextColor3 = MenuTheme.Colors.BadgeGreen
			else
				ttTagPill.Text = "NEUTRAL"
				ttTagPill.BackgroundColor3 = MenuTheme.Colors.CardRowBg
				ttTagPill.TextColor3 = MenuTheme.Colors.SubtleText
				ttMidLbl.Text = string.format(
					"⚔ Click: attack with %s (Def: %s)",
					formatCompact(sendN),
					formatCompact(info.troops or 0)
				)
				ttMidLbl.TextColor3 = MenuTheme.Colors.PlaySoloBg
			end
			ttFootLbl.Text = "Clic derecho: proponer alianza / acciones"
		end

		tooltip.Position = UDim2.fromOffset(x, y)
		tooltip.Visible = true
	end)
	table.insert(cleanups, function()
		renderConn:Disconnect()
	end)

	-- Conexión de botones
	protBlock.MouseButton1Click:Connect(function()
		local nextVal = not self.stateData.defenseAI
		self.stateData.defenseAI = nextVal
		self._refreshVisualState()
		if cb.OnToggleDefenseAI then
			cb.OnToggleDefenseAI(nextVal)
		end
	end)

	attacksHeaderBtn.MouseButton1Click:Connect(function()
		self.attacksCollapsed = not self.attacksCollapsed
		rebuildAttacksList()
	end)

	musicBtn.MouseButton1Click:Connect(function()
		self:SetMusicMuted(not self.isMuted)
		for _, desc in ipairs(SoundService:GetDescendants()) do
			if desc:IsA("Sound") then
				desc.Playing = not self.isMuted
			end
		end
		if cb.OnToggleMusic then
			cb.OnToggleMusic(self.isMuted)
		end
	end)

	helpBtn.MouseButton1Click:Connect(function()
		if cb.OnOpenHelp then
			cb.OnOpenHelp()
		end
	end)

	local function openLb()
		if cb.OnToggleLeaderboard then
			cb.OnToggleLeaderboard()
		end
	end
	lbBtn.MouseButton1Click:Connect(openLb)
	rankPill.MouseButton1Click:Connect(openLb)

	globeBtn.MouseButton1Click:Connect(function()
		if cb.OnCenterMap then
			cb.OnCenterMap()
		end
	end)

	settingsBtn.MouseButton1Click:Connect(function()
		if cb.OnOpenSettings then
			cb.OnOpenSettings()
		end
	end)

	exitBtn.MouseButton1Click:Connect(function()
		if cb.OnExitToMenu then
			cb.OnExitToMenu()
		end
	end)

	shopBtn.MouseButton1Click:Connect(function()
		if cb.OnOpenInGameShop then
			cb.OnOpenInGameShop()
		end
	end)

	self._setHoverOverride = function(ctx: HoverContext?)
		hoverCtxOverride = ctx
	end

	return (self :: any) :: InGameHudViewInstance
end

function InGameHudView:SetMusicMuted(muted: boolean)
	self.isMuted = muted
	if muted then
		self.musicBtn.Text = "🔇"
		self.musicBtn.TextColor3 = MenuTheme.Colors.MutedText
		self.musicStroke.Color = Color3.fromHex("#EF4444")
	else
		self.musicBtn.Text = "♪"
		self.musicBtn.TextColor3 = MenuTheme.Colors.White
		self.musicStroke.Color = MenuTheme.Colors.CardStroke
	end
end

function InGameHudView:SetAttackPercent(pct: number)
	self.attackPercent = pct
	self._refreshVisualState()
	if self.cb.OnAttackPercentChanged then
		self.cb.OnAttackPercentChanged(pct)
	end
end

function InGameHudView:CycleAttackPercent(delta: number)
	local idx = 2
	for i, v in ipairs(ATTACK_PERCENTS) do
		if v == self.attackPercent then
			idx = i
			break
		end
	end
	local nextIdx = math.clamp(idx + delta, 1, #ATTACK_PERCENTS)
	self:SetAttackPercent(ATTACK_PERCENTS[nextIdx])
end

function InGameHudView:SelectBuildSlot(slotIndex: number)
	local ref = self.slotRefs[slotIndex]
	if not ref then
		return
	end
	if self.selectedSlotIndex == slotIndex then
		self.selectedSlotIndex = nil
		self._refreshVisualState()
		self:ShowToast("⚔️ Modo expansión / ataque activo", 2.0)
		if self.cb.OnSelectBuildSlot then
			self.cb.OnSelectBuildSlot(0, "ATTACK")
		end
		return
	end
	self.selectedSlotIndex = slotIndex
	self._refreshVisualState()
	self:ShowToast(string.format("🔧 %s (%s) — %s", ref.def.name, ref.def.costText, ref.def.hint), 3.0)
	if self.cb.OnSelectBuildSlot then
		self.cb.OnSelectBuildSlot(slotIndex, ref.def.actionMode)
	end
end

function InGameHudView:ClearBuildSlot()
	if self.selectedSlotIndex ~= nil then
		self.selectedSlotIndex = nil
		self._refreshVisualState()
	end
end

function InGameHudView:RetreatLatestAttack()
	local n = #self.activeAttacks
	if n == 0 then
		return
	end
	local removed = table.remove(self.activeAttacks, n)
	self._rebuildAttacksList()
	if removed and self.cb.OnRetreatAttack then
		self.cb.OnRetreatAttack(removed.id)
	end
end

function InGameHudView:ShowToast(text: string, duration: number?)
	self.toastLbl.Text = text
	self.toastFrame.Visible = true
	local waitSec = duration or 3.5
	task.delay(waitSec, function()
		if self.toastLbl.Text == text then
			self.toastFrame.Visible = false
		end
	end)
end

function InGameHudView:UpdateStats(stats: InGameStatsUpdate)
	local s = self.stateData
	if stats.troops ~= nil then s.troops = stats.troops end
	if stats.maxTroops ~= nil then s.maxTroops = stats.maxTroops end
	if stats.troopRate ~= nil then s.troopRate = stats.troopRate end
	if stats.troopsInWar ~= nil then s.troopsInWar = stats.troopsInWar end
	if stats.gold ~= nil then s.gold = stats.gold end
	if stats.goldRate ~= nil then s.goldRate = stats.goldRate end
	if stats.landPct ~= nil then s.landPct = stats.landPct end
	if stats.rank ~= nil then s.rank = stats.rank end
	if stats.leaderName ~= nil then s.leaderName = stats.leaderName end
	if stats.leaderPct ~= nil then s.leaderPct = stats.leaderPct end
	if stats.goalPct ~= nil then s.goalPct = stats.goalPct end
	if stats.defenseAI ~= nil then s.defenseAI = stats.defenseAI end
	if stats.weaponCooldowns ~= nil then s.weaponCooldowns = stats.weaponCooldowns end
	if stats.playerColor ~= nil then self.idSwatch.BackgroundColor3 = stats.playerColor end
	if stats.attacks ~= nil then
		self.activeAttacks = stats.attacks
		self._rebuildAttacksList()
	end
	self._refreshVisualState()
end

function InGameHudView:SetHoverContext(ctx: HoverContext?)
	self._setHoverOverride(ctx)
end

function InGameHudView:IsPointOverHud(guiPos: Vector2): boolean
	if not self.root.Visible then
		return false
	end
	return isPointInsideGui(self.hudBar, guiPos)
		or isPointInsideGui(self.topCenterPill, guiPos)
		or isPointInsideGui(self.rankPill, guiPos)
		or isPointInsideGui(self.attacksCard, guiPos)
		or isPointInsideGui(self.bottomDock, guiPos)
end

function InGameHudView:Show()
	self.root.Visible = true
	self.running = true
	self.stateData.elapsedSeconds = 0
	self:ShowToast("⚔️ ¡La conquista mundial ha comenzado! Expande tu territorio.", 4.0)
	self._refreshVisualState()
	self._rebuildAttacksList()

	task.spawn(function()
		while self.running and self.root.Visible do
			task.wait(1)
			if not self.running or not self.root.Visible then
				break
			end
			self.stateData.elapsedSeconds += 1
			self._refreshVisualState()
		end
	end)
end

function InGameHudView:Hide()
	self.running = false
	self.selectedSlotIndex = nil
	self.tooltip.Visible = false
	self.toastFrame.Visible = false
	self.root.Visible = false
end

function InGameHudView:Destroy()
	self:Hide()
	for _, fn in ipairs(self.cleanups) do
		fn()
	end
	table.clear(self.cleanups)
	if self.root then
		self.root:Destroy()
	end
end

return InGameHudView
