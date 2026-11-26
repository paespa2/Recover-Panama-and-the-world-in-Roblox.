--!strict
-- MainMenuController.luau
-- Orquestador principal del menú táctico CONQUER THE WORLD.
-- Gestiona el ciclo de vida del ScreenGui, escalado responsivo UIScale, modales interactivos,
-- integración bidireccional con WorldClientBridge y WorldRemotes, y API desacoplada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MenuFolder = script.Parent
local MenuTheme = require(MenuFolder:WaitForChild("MenuTheme"))
local BackgroundMapView = require(MenuFolder:WaitForChild("BackgroundMapView"))
local TopUtilityBar = require(MenuFolder:WaitForChild("TopUtilityBar"))
local BrandHeader = require(MenuFolder:WaitForChild("BrandHeader"))
local PartyPanel = require(MenuFolder:WaitForChild("PartyPanel"))
local PlayMatchmakingPanel = require(MenuFolder:WaitForChild("PlayMatchmakingPanel"))
local RightRailShop = require(MenuFolder:WaitForChild("RightRailShop"))
local HowToPlayModal = require(MenuFolder:WaitForChild("HowToPlayModal"))
local DeploymentHudOverlay = require(MenuFolder:WaitForChild("DeploymentHudOverlay"))
local InGameHudView = require(MenuFolder:WaitForChild("InGameHudView"))
local FooterBar = require(MenuFolder:WaitForChild("FooterBar"))

local ClientFolder = MenuFolder.Parent and MenuFolder.Parent.Parent
local MapFolder = if ClientFolder then ClientFolder:FindFirstChild("Map") else nil
local MapOverlayModule = if MapFolder then MapFolder:FindFirstChild("MapOverlayRenderer") else nil
local MapOverlayRenderer: any = if MapOverlayModule and MapOverlayModule:IsA("ModuleScript")
	then require(MapOverlayModule)
	else nil

export type MenuCallbacks = {
	OnPlaySoloClicked: (() -> ())?,
	OnStartSoloGame: ((mapId: string, difficulty: string) -> ())?,
	OnJoinMatchClicked: ((matchId: string) -> ())?,
	OnSelectCapitalTile: ((tileCoords: Vector2) -> ())?,
	OnLaunchAttack: ((targetId: number, percentage: number) -> ())?,
	OnAttackPercentChanged: ((pct: number) -> ())?,
	OnSelectBuildSlot: ((slotIndex: number, slotId: string) -> ())?,
	OnRetreatAttack: ((attackId: string) -> ())?,
	OnOpenInGameShop: (() -> ())?,
	OnExitToMenu: (() -> ())?,
	OnOpenArsenal: (() -> ())?,
	OnOpenCrates: (() -> ())?,
	OnOpenFlagShop: (() -> ())?,
	OnOpenPass: (() -> ())?,
	OnInviteParty: (() -> ())?,
	OnOpenSettings: (() -> ())?,
	OnToggleMusic: ((isMuted: boolean) -> ())?,
	OnOpenHowToPlay: (() -> ())?,
	OnCloseHowToPlay: (() -> ())?,
}

local localPlayer = Players.LocalPlayer
if not localPlayer then
	return
end
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

-- Limpiar instancia previa si se recarga en caliente
local oldGui = playerGui:FindFirstChild("ConquerMainMenuGui")
if oldGui then
	oldGui:Destroy()
end

-- ============================================================================
-- 1. CONFIGURACIÓN DEL SCREENGUI RAÍZ Y ESCALADO RESPONSIVO (UIScale)
-- ============================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ConquerMainMenuGui"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 25
screenGui.Enabled = true
screenGui.Parent = playerGui

local rootScale = Instance.new("UIScale")
rootScale.Name = "ResponsiveScale"
rootScale.Scale = 1
rootScale.Parent = screenGui

local function updateResponsiveScale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then
		return
	end
	local scaleX = vp.X / 1366
	local scaleY = vp.Y / 740
	rootScale.Scale = math.clamp(math.min(scaleX, scaleY), 0.50, 1.15)
end

updateResponsiveScale()
local camConn: RBXScriptConnection? = nil
local function bindCameraViewport()
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	local cam = Workspace.CurrentCamera
	if cam then
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
		updateResponsiveScale()
	end
end
bindCameraViewport()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)

-- ============================================================================
-- 2. API DE SEÑALES (BindableEvents) Y CALLBACKS EXTERNOS
-- ============================================================================
local signalsFolder = Instance.new("Folder")
signalsFolder.Name = "Signals"
signalsFolder.Parent = screenGui

local function createSignal(name: string): BindableEvent
	local ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = signalsFolder
	return ev
end

local Signals = {
	OnPlaySoloClicked = createSignal("OnPlaySoloClicked"),
	OnStartSoloGame = createSignal("OnStartSoloGame"),
	OnJoinMatchClicked = createSignal("OnJoinMatchClicked"),
	OnSelectCapitalTile = createSignal("OnSelectCapitalTile"),
	OnLaunchAttack = createSignal("OnLaunchAttack"),
	OnAttackPercentChanged = createSignal("OnAttackPercentChanged"),
	OnSelectBuildSlot = createSignal("OnSelectBuildSlot"),
	OnRetreatAttack = createSignal("OnRetreatAttack"),
	OnOpenInGameShop = createSignal("OnOpenInGameShop"),
	OnExitToMenu = createSignal("OnExitToMenu"),
	OnOpenArsenal = createSignal("OnOpenArsenal"),
	OnOpenCrates = createSignal("OnOpenCrates"),
	OnOpenFlagShop = createSignal("OnOpenFlagShop"),
	OnOpenPass = createSignal("OnOpenPass"),
	OnInviteParty = createSignal("OnInviteParty"),
	OnOpenSettings = createSignal("OnOpenSettings"),
	OnToggleMusic = createSignal("OnToggleMusic"),
	OnOpenHowToPlay = createSignal("OnOpenHowToPlay"),
	OnCloseHowToPlay = createSignal("OnCloseHowToPlay"),
}

local RegisteredCallbacks: MenuCallbacks = {}

local lobbyContainer = Instance.new("Frame")
lobbyContainer.Name = "LobbyContainer"
lobbyContainer.Size = UDim2.fromScale(1, 1)
lobbyContainer.BackgroundTransparency = 1
lobbyContainer.Visible = true
lobbyContainer.ZIndex = 1
lobbyContainer.Parent = screenGui

-- ============================================================================
-- 3. SISTEMA DE MODAL TÁCTICO Y PANEL INTERACTIVO DE TIENDA
-- ============================================================================
local modalBackdrop = Instance.new("Frame")
modalBackdrop.Name = "ModalBackdrop"
modalBackdrop.Size = UDim2.fromScale(1, 1)
modalBackdrop.BackgroundColor3 = Color3.fromHex("#050811")
modalBackdrop.BackgroundTransparency = 0.35
modalBackdrop.BorderSizePixel = 0
modalBackdrop.Active = true
modalBackdrop.Visible = false
modalBackdrop.ZIndex = 30
modalBackdrop.Parent = screenGui

local modalCard = Instance.new("Frame")
modalCard.Name = "ModalCard"
modalCard.AnchorPoint = Vector2.new(0.5, 0.5)
modalCard.Position = UDim2.fromScale(0.5, 0.5)
modalCard.Size = UDim2.fromOffset(440, 270)
modalCard.BackgroundColor3 = MenuTheme.Colors.CenterCardBg
modalCard.BackgroundTransparency = 0.04
modalCard.BorderSizePixel = 0
modalCard.ZIndex = 31
modalCard.Parent = modalBackdrop

local modalCorner = Instance.new("UICorner")
modalCorner.CornerRadius = MenuTheme.Corners.Card
modalCorner.Parent = modalCard

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = MenuTheme.Colors.CyanBorder
modalStroke.Thickness = 1.5
modalStroke.Parent = modalCard

local modalScale = Instance.new("UIScale")
modalScale.Scale = 1
modalScale.Parent = modalCard

local modalTitle = Instance.new("TextLabel")
modalTitle.Name = "ModalTitle"
modalTitle.Position = UDim2.fromOffset(22, 16)
modalTitle.Size = UDim2.new(1, -44, 0, 26)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = MenuTheme.Fonts.Heading
modalTitle.Text = "INFORMACIÓN TÁCTICA"
modalTitle.TextColor3 = MenuTheme.Colors.White
modalTitle.TextSize = 18
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.ZIndex = 32
modalTitle.Parent = modalCard

local modalSubtitle = Instance.new("TextLabel")
modalSubtitle.Name = "ModalSubtitle"
modalSubtitle.Position = UDim2.fromOffset(22, 42)
modalSubtitle.Size = UDim2.new(1, -44, 0, 16)
modalSubtitle.BackgroundTransparency = 1
modalSubtitle.Font = MenuTheme.Fonts.Bold
modalSubtitle.Text = "CONQUER THE WORLD"
modalSubtitle.TextColor3 = MenuTheme.Colors.CyanAccent
modalSubtitle.TextSize = 11
modalSubtitle.TextXAlignment = Enum.TextXAlignment.Left
modalSubtitle.ZIndex = 32
modalSubtitle.Parent = modalCard

local modalBody = Instance.new("TextLabel")
modalBody.Name = "ModalBody"
modalBody.Position = UDim2.fromOffset(22, 66)
modalBody.Size = UDim2.new(1, -44, 0, 142)
modalBody.BackgroundTransparency = 1
modalBody.Font = MenuTheme.Fonts.Regular
modalBody.Text = ""
modalBody.TextColor3 = MenuTheme.Colors.SubtleText
modalBody.TextSize = 12
modalBody.TextWrapped = true
modalBody.TextXAlignment = Enum.TextXAlignment.Left
modalBody.TextYAlignment = Enum.TextYAlignment.Top
modalBody.ZIndex = 32
modalBody.Parent = modalCard

local shopPanel = Instance.new("Frame")
shopPanel.Name = "TacticalShopPanel"
shopPanel.Position = UDim2.fromOffset(22, 66)
shopPanel.Size = UDim2.new(1, -44, 0, 206)
shopPanel.BackgroundTransparency = 1
shopPanel.Visible = false
shopPanel.ZIndex = 32
shopPanel.Parent = modalCard

local shopGrid = Instance.new("UIGridLayout")
shopGrid.CellSize = UDim2.fromOffset(210, 58)
shopGrid.CellPadding = UDim2.fromOffset(12, 10)
shopGrid.SortOrder = Enum.SortOrder.LayoutOrder
shopGrid.Parent = shopPanel

local modalCloseBtn = Instance.new("TextButton")
modalCloseBtn.Name = "BtnCloseModal"
modalCloseBtn.AnchorPoint = Vector2.new(0.5, 1)
modalCloseBtn.Position = UDim2.new(0.5, 0, 1, -16)
modalCloseBtn.Size = UDim2.fromOffset(148, 36)
modalCloseBtn.BackgroundColor3 = MenuTheme.Colors.PlaySoloBg
modalCloseBtn.AutoButtonColor = false
modalCloseBtn.Font = MenuTheme.Fonts.Heading
modalCloseBtn.Text = "ENTENDIDO"
modalCloseBtn.TextColor3 = MenuTheme.Colors.DarkText
modalCloseBtn.TextSize = 13
modalCloseBtn.ZIndex = 32
modalCloseBtn.Parent = modalCard

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = MenuTheme.Corners.Pill
closeCorner.Parent = modalCloseBtn

MenuTheme.applyButtonFX(modalCloseBtn, {
	baseColor = MenuTheme.Colors.PlaySoloBg,
	hoverColor = MenuTheme.Colors.PlaySoloHover,
})

local function closeModal()
	shopPanel.Visible = false
	modalBody.Visible = true
	modalCard.Size = UDim2.fromOffset(440, 270)
	modalBackdrop.Visible = false
end

local function showModal(title: string, subtitle: string, body: string, accent: Color3?)
	shopPanel.Visible = false
	modalBody.Visible = true
	modalCard.Size = UDim2.fromOffset(440, 270)
	modalTitle.Text = title
	modalSubtitle.Text = subtitle
	modalSubtitle.TextColor3 = accent or MenuTheme.Colors.CyanAccent
	modalStroke.Color = accent or MenuTheme.Colors.CyanBorder
	modalBody.Text = body
	modalScale.Scale = 0.92
	modalBackdrop.Visible = true
	TweenService:Create(modalScale, MenuTheme.Tweens.Hover, { Scale = 1 }):Play()
end

modalCloseBtn.MouseButton1Click:Connect(closeModal)

-- ============================================================================
-- 4. INTEGRACIÓN CON EL MOTOR DEL JUEGO (WorldConquestGui, WorldClientBridge & Remotes)
-- ============================================================================
local SUPPRESSED_LEGACY_PANELS: { [string]: boolean } = {
	LobbyScreen = true,
	TopBar = true,
	BottomHUD = true,
	Leaderboard = true,
	SpawnBanner = true,
	HoverTip = true,
	AttackPill = true,
	RadarFrame = true,
	TacticalConfigModal = true,
	CountryPanel = true,
	ToastFrame = true,
}

local function setLegacyLobbySuppressed(suppress: boolean)
	local worldGui = playerGui:FindFirstChild("WorldConquestGui")
	if worldGui and worldGui:IsA("ScreenGui") then
		local lobbyFrame = worldGui:FindFirstChild("LobbyScreen", true)
		if lobbyFrame and lobbyFrame:IsA("GuiObject") then
			lobbyFrame.Visible = false
		end
		if suppress and lobbyContainer.Visible then
			worldGui.Enabled = false
		else
			worldGui.Enabled = true
		end
	end
end

local _playMatchmakingPanel: PlayMatchmakingPanel.PlayMatchmakingPanelInstance
local _deploymentHud: DeploymentHudOverlay.DeploymentHudOverlayInstance
local _inGameHud: InGameHudView.InGameHudViewInstance
local _mapOverlay: any = if MapOverlayRenderer then MapOverlayRenderer.new() else nil
local _knownAttackKeys: { [string]: boolean } = {}

local latestStats: any = nil
local latestMe: any = nil
local myServerId: number? = nil
local currentMode: string = "FREE"
local currentGoalPct: number = 65
local endedShownForMatch = false

local function getBridge(): any
	return (_G :: any).WorldClientBridge
end

local function getWorldCommand(): RemoteEvent?
	local remotesFolder = ReplicatedStorage:FindFirstChild("WorldRemotes")
	local cmdRemote = if remotesFolder then remotesFolder:FindFirstChild("WorldCommand") else nil
	if cmdRemote and cmdRemote:IsA("RemoteEvent") then
		return cmdRemote
	end
	return nil
end

local function mapDifficultyToServer(diff: string): string
	if diff == "Relaxed" then
		return "EASY"
	elseif diff == "Brutal" then
		return "HARD"
	end
	return "NORMAL"
end

local function enterMapDeploymentView()
	closeModal()
	endedShownForMatch = false
	lobbyContainer.Visible = false
	if _inGameHud then
		_inGameHud:Hide()
	end
	setLegacyLobbySuppressed(false)
	if _deploymentHud then
		_deploymentHud:EnterDeployment()
	end
end

local function enterInGameHudView()
	closeModal()
	lobbyContainer.Visible = false
	if _deploymentHud then
		_deploymentHud:Hide()
	end
	setLegacyLobbySuppressed(false)
	local bridge = getBridge()
	if _inGameHud then
		if bridge then
			if bridge.setAttackRatio then
				bridge.setAttackRatio(_inGameHud.attackPercent / 100)
			end
			if bridge.setActionMode then
				bridge.setActionMode("ATTACK")
			end
		end
		_inGameHud:ClearBuildSlot()
		_inGameHud:Show()
	end
end

local function returnToLobbyView()
	closeModal()
	table.clear(_knownAttackKeys)
	if _mapOverlay and _mapOverlay.Clear then
		_mapOverlay:Clear()
	end
	if _deploymentHud then
		_deploymentHud:Hide()
	end
	if _inGameHud then
		_inGameHud:Hide()
	end
	if _playMatchmakingPanel then
		_playMatchmakingPanel:ShowLobbyContent()
	end
	lobbyContainer.Visible = true
	setLegacyLobbySuppressed(true)
end

local function firePlayRemote(planetId: string, bots: number, serverDiff: string, mode: string)
	currentMode = mode
	currentGoalPct = if mode == "CONTINENTS" or mode == "TEAMS_2" then 55 else 65
	endedShownForMatch = false
	local cmdRemote = getWorldCommand()
	if cmdRemote then
		cmdRemote:FireServer({
			a = "PLAY",
			planet = planetId,
			bots = bots,
			difficulty = serverDiff,
			mode = mode,
		})
	end
end

local function launchSoloSession(mapId: string, difficulty: string)
	Signals.OnStartSoloGame:Fire(mapId, difficulty)
	if RegisteredCallbacks.OnStartSoloGame then
		RegisteredCallbacks.OnStartSoloGame(mapId, difficulty)
	end
	local serverDiff = mapDifficultyToServer(difficulty)
	if _playMatchmakingPanel then
		_playMatchmakingPanel:ShowDeploying(function()
			firePlayRemote(mapId, 40, serverDiff, "FREE")
			enterMapDeploymentView()
		end)
	else
		firePlayRemote(mapId, 40, serverDiff, "FREE")
		enterMapDeploymentView()
	end
end

local function launchGameSession(matchKey: string)
	local mode = "COUNTRIES"
	local bots = 40
	if matchKey == "WORLD" then
		mode = "FREE"
		bots = 50
	elseif matchKey == "NORTH_AMERICA" then
		mode = "CONTINENTS"
		bots = 40
	elseif matchKey == "PUBLIC_MATCH" then
		mode = "COUNTRIES"
		bots = 45
	end

	if _playMatchmakingPanel then
		_playMatchmakingPanel:ShowDeploying(function()
			firePlayRemote("EARTH", bots, "NORMAL", mode)
			enterMapDeploymentView()
		end)
	else
		firePlayRemote("EARTH", bots, "NORMAL", mode)
		enterMapDeploymentView()
	end
end

-- Sincronizar con WorldConquestGui: suprimir únicamente paneles heredados duplicados
local function hookWorldConquestGui(worldGui: ScreenGui)
	local legacyRoot = worldGui:WaitForChild("Root", 10)
	local function suppressLegacyChild(child: Instance)
		if not SUPPRESSED_LEGACY_PANELS[child.Name] or not child:IsA("GuiObject") then
			return
		end
		if child.Name == "LobbyScreen" then
			child.Visible = false
			child:GetPropertyChangedSignal("Visible"):Connect(function()
				if child.Visible then
					child.Visible = false
					returnToLobbyView()
				end
			end)
			return
		end
		child.Visible = false
		child:GetPropertyChangedSignal("Visible"):Connect(function()
			if child.Visible then
				child.Visible = false
			end
		end)
	end

	if legacyRoot then
		for _, child in ipairs(legacyRoot:GetChildren()) do
			suppressLegacyChild(child)
		end
		legacyRoot.ChildAdded:Connect(suppressLegacyChild)
	end

	if lobbyContainer.Visible then
		worldGui.Enabled = false
	end

	local btnLobby = worldGui:FindFirstChild("BtnLobby", true)
	if btnLobby and btnLobby:IsA("GuiButton") then
		btnLobby.MouseButton1Click:Connect(function()
			returnToLobbyView()
		end)
	end
end

task.spawn(function()
	local existing = playerGui:FindFirstChild("WorldConquestGui")
	if existing and existing:IsA("ScreenGui") then
		hookWorldConquestGui(existing)
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "WorldConquestGui" and child:IsA("ScreenGui") then
			hookWorldConquestGui(child)
		end
	end)
end)

-- ============================================================================
-- 5. INSTANCIACIÓN DE LAS ZONAS MODULARES, MODAL HOW TO PLAY Y HUD DE DESPLIEGUE
-- ============================================================================
local _backgroundView = BackgroundMapView.new(lobbyContainer)
local _brandHeader = BrandHeader.new(lobbyContainer)

local _howToPlayModal = HowToPlayModal.new(screenGui, {
	OnClose = function()
		Signals.OnCloseHowToPlay:Fire()
		if RegisteredCallbacks.OnCloseHowToPlay then
			RegisteredCallbacks.OnCloseHowToPlay()
		end
	end,
})

local function openHowToPlay()
	Signals.OnOpenHowToPlay:Fire()
	if RegisteredCallbacks.OnOpenHowToPlay then
		RegisteredCallbacks.OnOpenHowToPlay()
	end
	_howToPlayModal:Show()
end

local function openSettingsModal()
	Signals.OnOpenSettings:Fire()
	if RegisteredCallbacks.OnOpenSettings then
		RegisteredCallbacks.OnOpenSettings()
	end
	showModal(
		"CONFIGURACIÓN TÁCTICA",
		"CONTROLES Y RENDIMIENTO",
		"• H: Abrir/cerrar How to Play   |   M: Silenciar audio   |   Tab: Clasificación\n"
			.. "• WASD / Flechas / Clic derecho arrastrar: Mover cámara   |   Rueda o Z/C: Zoom   |   F: Ver mundo\n"
			.. "• Q / E: Reducir / aumentar % ataque   |   1-0, -, =: Edificios y armas   |   R: Retirada\n"
			.. "• Clic derecho en mapa: Menú rápido (o cancelar construcción seleccionada)",
		MenuTheme.Colors.PillGold
	)
end

local syncingMusic = false
local _topUtilityBar: TopUtilityBar.TopUtilityBarInstance
_topUtilityBar = TopUtilityBar.new(lobbyContainer, {
	OnToggleMusic = function(isMuted: boolean)
		if syncingMusic then
			return
		end
		syncingMusic = true
		if _deploymentHud then
			_deploymentHud:SetMusicMuted(isMuted)
		end
		if _inGameHud then
			_inGameHud:SetMusicMuted(isMuted)
		end
		syncingMusic = false
		Signals.OnToggleMusic:Fire(isMuted)
		if RegisteredCallbacks.OnToggleMusic then
			RegisteredCallbacks.OnToggleMusic(isMuted)
		end
	end,
	OnOpenHelp = function()
		openHowToPlay()
	end,
	OnOpenSettings = openSettingsModal,
})

local function openLeaderboardModal()
	local lines: { string } = {}
	local s = latestStats
	if s and type(s.teams) == "table" and #s.teams > 0 then
		for idx, t in ipairs(s.teams) do
			if idx > 7 then
				break
			end
			table.insert(lines, string.format("#%d Equipo #%s — %.2f%%", idx, tostring(t.id), tonumber(t.pct) or 0))
		end
	elseif s and type(s.top) == "table" and #s.top > 0 then
		for idx, entry in ipairs(s.top) do
			if idx > 8 then
				break
			end
			local mark = if myServerId ~= nil and entry.id == myServerId then " 👑 [TÚ]" else ""
			table.insert(
				lines,
				string.format("#%d %s%s — %.2f%%", idx, tostring(entry.name or "Nación"), mark, tonumber(entry.pct) or 0)
			)
		end
	else
		table.insert(lines, "Aún no hay clasificación disponible. Inicia o entra a una partida.")
	end

	if latestMe and s and s.landCount and s.landCount > 0 then
		local myCells = tonumber(latestMe.cells) or 0
		local myPct = (myCells / s.landCount) * 100
		local myRank = 1
		for _, n in ipairs(s.nations or {}) do
			if (tonumber(n.cells) or 0) > myCells then
				myRank += 1
			end
		end
		table.insert(
			lines,
			string.format(
				"\nTu imperio: Puesto #%d • %.2f%% • Tropas: %s • Oro: %s",
				myRank,
				myPct,
				MenuTheme.formatNumber(tonumber(latestMe.troops) or 0),
				MenuTheme.formatNumber(tonumber(latestMe.gold) or 0)
			)
		)
	end

	showModal(
		"CLASIFICACIÓN MUNDIAL",
		string.format("META DE VICTORIA: %d%% DEL TERRITORIO", currentGoalPct),
		table.concat(lines, "\n"),
		MenuTheme.Colors.CyanAccent
	)
end

local function centerMapCamera()
	local bridge = getBridge()
	if bridge and bridge.centerMap then
		bridge.centerMap()
	end
	if _deploymentHud and _deploymentHud.root.Visible then
		_deploymentHud:ShowToast("🎯 Vista centrada en tu posición", 2.0)
	elseif _inGameHud and _inGameHud.root.Visible then
		_inGameHud:ShowToast("🎯 Vista centrada en tu capital", 2.0)
	end
end

-- Construcción de los 6 botones interactivos del Panel Táctico (TIENDA)
local function createShopActionButton(
	order: number,
	titleText: string,
	subText: string,
	accentColor: Color3,
	onClick: (btnTitle: TextLabel, btnSub: TextLabel) -> ()
): (TextButton, TextLabel, TextLabel)
	local btn = Instance.new("TextButton")
	btn.Name = "ShopAction_" .. tostring(order)
	btn.LayoutOrder = order
	btn.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = 33
	btn.Parent = shopPanel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = accentColor
	stroke.Thickness = 1.2
	stroke.Parent = btn

	local tLbl = Instance.new("TextLabel")
	tLbl.Position = UDim2.fromOffset(10, 6)
	tLbl.Size = UDim2.new(1, -20, 0, 20)
	tLbl.BackgroundTransparency = 1
	tLbl.Font = MenuTheme.Fonts.Heading
	tLbl.Text = titleText
	tLbl.TextColor3 = MenuTheme.Colors.White
	tLbl.TextSize = 12
	tLbl.TextXAlignment = Enum.TextXAlignment.Left
	tLbl.TextTruncate = Enum.TextTruncate.AtEnd
	tLbl.ZIndex = 34
	tLbl.Parent = btn

	local sLbl = Instance.new("TextLabel")
	sLbl.Position = UDim2.fromOffset(10, 28)
	sLbl.Size = UDim2.new(1, -20, 0, 22)
	sLbl.BackgroundTransparency = 1
	sLbl.Font = MenuTheme.Fonts.Regular
	sLbl.Text = subText
	sLbl.TextColor3 = MenuTheme.Colors.SubtleText
	sLbl.TextSize = 10
	sLbl.TextXAlignment = Enum.TextXAlignment.Left
	sLbl.TextTruncate = Enum.TextTruncate.AtEnd
	sLbl.ZIndex = 34
	sLbl.Parent = btn

	MenuTheme.applyButtonFX(btn, {
		baseColor = MenuTheme.Colors.SideCardBg,
		hoverColor = MenuTheme.Colors.CardRowHoverBg,
		stroke = stroke,
		baseStrokeColor = accentColor,
		hoverStrokeColor = MenuTheme.Colors.White,
	})

	btn.MouseButton1Click:Connect(function()
		onClick(tLbl, sLbl)
	end)

	return btn, tLbl, sLbl
end

local AUTO_LABELS: { [string]: string } = {
	OFF = "APAGADO",
	EXPAND = "EXPANDIR",
	CONQUER = "CONQUISTAR",
}

local _, shopDefTitle, shopDefSub = createShopActionButton(
	1,
	"🛡️ IA Defensa: ON",
	"Contraataca automáticamente agresiones",
	MenuTheme.Colors.BadgeGreen,
	function(tLbl, sLbl)
		local current = if latestMe and latestMe.defenseAI ~= nil then (latestMe.defenseAI == true) else true
		local nextVal = not current
		if latestMe then
			latestMe.defenseAI = nextVal
		end
		local cmd = getWorldCommand()
		if cmd then
			cmd:FireServer({ a = "DEFENSE_AI", on = nextVal })
		end
		if _inGameHud then
			_inGameHud:UpdateStats({ defenseAI = nextVal })
			_inGameHud:ShowToast(
				if nextVal then "🛡️ IA Defensa ACTIVADA" else "⚔️ Modo defensivo MANUAL",
				2.5
			)
		end
		tLbl.Text = if nextVal then "🛡️ IA Defensa: ON" else "⚔️ IA Defensa: OFF"
		sLbl.Text = if nextVal then "Contraataque automático activo" else "Control manual total"
	end
)

local _, shopAutoTitle, _ = createShopActionButton(
	2,
	"🤖 Autojuego: EXPANDIR",
	"Alternar OFF / EXPANDIR / CONQUISTAR",
	MenuTheme.Colors.CyanBorder,
	function(tLbl)
		local bridge = getBridge()
		local st = if bridge and bridge.getState then bridge.getState() else nil
		local cur = if st and st.autoMode then st.autoMode else "EXPAND"
		local nextMode = if cur == "OFF" then "EXPAND" elseif cur == "EXPAND" then "CONQUER" else "OFF"
		if st then
			st.autoMode = nextMode
			if st.refreshAuto then
				st.refreshAuto()
			end
		end
		local pct = if _inGameHud then _inGameHud.attackPercent / 100 else 0.2
		local cmd = getWorldCommand()
		if cmd then
			cmd:FireServer({ a = "AUTO", mode = nextMode, ratio = pct })
		end
		tLbl.Text = "🤖 Autojuego: " .. (AUTO_LABELS[nextMode] or nextMode)
		if _inGameHud then
			_inGameHud:ShowToast("🤖 Autojuego: " .. (AUTO_LABELS[nextMode] or nextMode), 2.5)
		end
	end
)

createShopActionButton(
	3,
	"🎯 Artillería ($300)",
	"Ataque de precisión · Radio 3",
	MenuTheme.Colors.PlaySoloBg,
	function()
		local bridge = getBridge()
		if bridge and bridge.setActionMode then
			bridge.setActionMode("WEAPON_ARTILLERY")
		end
		if _inGameHud then
			_inGameHud:ClearBuildSlot()
			_inGameHud:ShowToast("🎯 Artillería apuntada: haz clic en el objetivo terrestre", 3.5)
		end
		closeModal()
	end
)

createShopActionButton(
	4,
	"🌋 Terremoto ($550)",
	"Destruye edificios y tropas · Radio 13",
	Color3.fromHex("#EA580C"),
	function()
		local bridge = getBridge()
		if bridge and bridge.setActionMode then
			bridge.setActionMode("WEAPON_QUAKE")
		end
		if _inGameHud then
			_inGameHud:ClearBuildSlot()
			_inGameHud:ShowToast("🌋 Terremoto apuntado: haz clic en la región objetivo", 3.5)
		end
		closeModal()
	end
)

createShopActionButton(
	5,
	"☄️ Meteorito ($650)",
	"3 impactos orbitales · Radio 7",
	MenuTheme.Colors.AccentRed,
	function()
		local bridge = getBridge()
		if bridge and bridge.setActionMode then
			bridge.setActionMode("WEAPON_METEOR")
		end
		if _inGameHud then
			_inGameHud:ClearBuildSlot()
			_inGameHud:ShowToast("☄️ Meteorito apuntado: haz clic sobre territorio enemigo", 3.5)
		end
		closeModal()
	end
)

createShopActionButton(
	6,
	"☢️ Misil de Silo ($900)",
	"Requiere Silo · Devastación Radio 16",
	Color3.fromHex("#A855F7"),
	function()
		local bridge = getBridge()
		if bridge and bridge.setActionMode then
			bridge.setActionMode("NUKE")
		end
		if _inGameHud then
			_inGameHud:ClearBuildSlot()
			_inGameHud:ShowToast("☢️ Misil de Silo apuntado: haz clic en el objetivo", 3.5)
		end
		closeModal()
	end
)

local function openTacticalShopModal()
	local defOn = if latestMe and latestMe.defenseAI ~= nil then (latestMe.defenseAI == true) else true
	shopDefTitle.Text = if defOn then "🛡️ IA Defensa: ON" else "⚔️ IA Defensa: OFF"
	shopDefSub.Text = if defOn then "Contraataque automático activo" else "Control manual total"

	local bridge = getBridge()
	local st = if bridge and bridge.getState then bridge.getState() else nil
	local autoM = if st and st.autoMode then st.autoMode else "EXPAND"
	shopAutoTitle.Text = "🤖 Autojuego: " .. (AUTO_LABELS[autoM] or autoM)

	modalBody.Visible = false
	shopPanel.Visible = true
	modalCard.Size = UDim2.fromOffset(476, 336)
	modalTitle.Text = "CENTRO DE MANDO TÁCTICO"
	modalSubtitle.Text = string.format(
		"ORO DISPONIBLE: %s • AUTOMATIZACIÓN Y ARMAMENTO ESPECIAL",
		MenuTheme.formatNumber(if latestMe and latestMe.gold then tonumber(latestMe.gold) or 0 else 0)
	)
	modalSubtitle.TextColor3 = MenuTheme.Colors.PlaySoloBg
	modalStroke.Color = MenuTheme.Colors.PlaySoloBg
	modalScale.Scale = 0.92
	modalBackdrop.Visible = true
	TweenService:Create(modalScale, MenuTheme.Tweens.Hover, { Scale = 1 }):Play()
end

local function syncMusicFromHud(isMuted: boolean)
	if syncingMusic then
		return
	end
	syncingMusic = true
	if _topUtilityBar and _topUtilityBar.isMuted ~= isMuted then
		_topUtilityBar:ToggleMusic()
	end
	if _deploymentHud and _deploymentHud.isMuted ~= isMuted then
		_deploymentHud:SetMusicMuted(isMuted)
	end
	if _inGameHud and _inGameHud.isMuted ~= isMuted then
		_inGameHud:SetMusicMuted(isMuted)
	end
	syncingMusic = false
	Signals.OnToggleMusic:Fire(isMuted)
	if RegisteredCallbacks.OnToggleMusic then
		RegisteredCallbacks.OnToggleMusic(isMuted)
	end
end

_deploymentHud = DeploymentHudOverlay.new(screenGui, {
	OnToggleMusic = syncMusicFromHud,
	OnOpenHelp = function()
		openHowToPlay()
	end,
	OnToggleLeaderboard = openLeaderboardModal,
	OnCenterMap = centerMapCamera,
	OnOpenSettings = openSettingsModal,
	OnExitToMenu = function()
		Signals.OnExitToMenu:Fire()
		if RegisteredCallbacks.OnExitToMenu then
			RegisteredCallbacks.OnExitToMenu()
		end
		returnToLobbyView()
	end,
	OnSelectCapitalTile = function(tileCoords: Vector2)
		Signals.OnSelectCapitalTile:Fire(tileCoords)
		if RegisteredCallbacks.OnSelectCapitalTile then
			RegisteredCallbacks.OnSelectCapitalTile(tileCoords)
		end
	end,
	OnDeploymentComplete = function()
		local cmd = getWorldCommand()
		if cmd then
			cmd:FireServer({ a = "START_NOW" })
		end
		enterInGameHudView()
	end,
})

_inGameHud = InGameHudView.new(screenGui, {
	OnToggleMusic = syncMusicFromHud,
	OnOpenHelp = function()
		openHowToPlay()
	end,
	OnToggleLeaderboard = openLeaderboardModal,
	OnCenterMap = centerMapCamera,
	OnOpenSettings = openSettingsModal,
	OnExitToMenu = function()
		Signals.OnExitToMenu:Fire()
		if RegisteredCallbacks.OnExitToMenu then
			RegisteredCallbacks.OnExitToMenu()
		end
		returnToLobbyView()
	end,
	OnAttackPercentChanged = function(pct: number)
		local bridge = getBridge()
		if bridge and bridge.setAttackRatio then
			bridge.setAttackRatio(pct / 100)
		end
		Signals.OnAttackPercentChanged:Fire(pct)
		if RegisteredCallbacks.OnAttackPercentChanged then
			RegisteredCallbacks.OnAttackPercentChanged(pct)
		end
	end,
	OnSelectBuildSlot = function(slotIndex: number, actionMode: string)
		local bridge = getBridge()
		if bridge and bridge.setActionMode then
			bridge.setActionMode(actionMode)
		end
		Signals.OnSelectBuildSlot:Fire(slotIndex, actionMode)
		if RegisteredCallbacks.OnSelectBuildSlot then
			RegisteredCallbacks.OnSelectBuildSlot(slotIndex, actionMode)
		end
	end,
	OnToggleDefenseAI = function(enabled: boolean)
		if latestMe then
			latestMe.defenseAI = enabled
		end
		local cmd = getWorldCommand()
		if cmd then
			cmd:FireServer({ a = "DEFENSE_AI", on = enabled })
		end
		if _inGameHud then
			_inGameHud:ShowToast(
				if enabled then "🛡️ IA Defensa ACTIVADA" else "⚔️ Modo defensivo MANUAL",
				2.5
			)
		end
	end,
	OnRetreatAttack = function(attackId: string)
		local cmd = getWorldCommand()
		if cmd then
			cmd:FireServer({ a = "RETREAT" })
		end
		Signals.OnRetreatAttack:Fire(attackId)
		if RegisteredCallbacks.OnRetreatAttack then
			RegisteredCallbacks.OnRetreatAttack(attackId)
		end
	end,
	OnOpenInGameShop = function()
		Signals.OnOpenInGameShop:Fire()
		if RegisteredCallbacks.OnOpenInGameShop then
			RegisteredCallbacks.OnOpenInGameShop()
		end
		openTacticalShopModal()
	end,
})

-- Conectar actualizaciones en vivo de WorldRemotes
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("WorldRemotes", 10)
	if not remotes then
		return
	end

	local worldInit = remotes:FindFirstChild("WorldInit")
	if worldInit and worldInit:IsA("RemoteEvent") then
		worldInit.OnClientEvent:Connect(function(data: any)
			if type(data) ~= "table" then
				return
			end
			if data.myId ~= nil then
				myServerId = tonumber(data.myId)
			end
			currentMode = tostring(data.mode or currentMode or "FREE")
			currentGoalPct = if data.teamMode then 55 else 65
			endedShownForMatch = false
			if type(data.stats) == "table" then
				latestStats = data.stats
			end
			if _inGameHud then
				_inGameHud:UpdateStats({ goalPct = currentGoalPct })
			end
			if _deploymentHud and _deploymentHud.isDeploying then
				local spawnT = if type(data.stats) == "table" then (tonumber(data.stats.spawnTimer) or 25) else 25
				_deploymentHud:SyncServerState(currentMode, spawnT, false, nil)
			end
		end)
	end

	local worldMe = remotes:FindFirstChild("WorldMe")
	if worldMe and worldMe:IsA("RemoteEvent") then
		worldMe.OnClientEvent:Connect(function(me: any)
			if type(me) ~= "table" then
				return
			end
			latestMe = me
			if me.id ~= nil then
				myServerId = tonumber(me.id)
			end

			if _deploymentHud and _deploymentHud.isDeploying then
				local spawnT = if latestStats then (tonumber(latestStats.spawnTimer) or 25) else 25
				_deploymentHud:SyncServerState(currentMode, spawnT, me.alive == true, me.capital)
			end

			if not _inGameHud or not _inGameHud.root.Visible then
				return
			end

			local bridge = getBridge()
			local bridgeState = if bridge and bridge.getState then bridge.getState() else nil
			local rosterById = if bridgeState then bridgeState.rosterById else nil

			local mappedAttacks: { InGameHudView.AttackEntry } = {}
			local currentKeys: { [string]: boolean } = {}
			if type(me.attacks) == "table" then
				for idx, a in ipairs(me.attacks) do
					local targetIdNum = if a.target ~= nil then tonumber(a.target) else nil
					local targetName = "Terreno neutral"
					if a.target and a.target ~= 0 then
						local entry = if rosterById then rosterById[a.target] else nil
						targetName = if entry and entry.name
							then tostring(entry.name)
							else ("Nación #" .. tostring(a.target))
					end
					local key = tostring(a.target or idx)
					currentKeys[key] = true
					if not _knownAttackKeys[key] then
						Signals.OnLaunchAttack:Fire(targetIdNum or 0, _inGameHud.attackPercent)
						if RegisteredCallbacks.OnLaunchAttack then
							RegisteredCallbacks.OnLaunchAttack(targetIdNum or 0, _inGameHud.attackPercent)
						end
					end
					table.insert(mappedAttacks, {
						id = key,
						targetId = targetIdNum,
						targetName = targetName,
						troops = tonumber(a.troops) or 0,
					})
				end
			end
			_knownAttackKeys = currentKeys

			local landCount = if latestStats and latestStats.landCount then tonumber(latestStats.landCount) or 1 else 1
			local myCells = tonumber(me.cells) or 0
			local myLandPct = (myCells / math.max(1, landCount)) * 100
			local myEntry = if rosterById and myServerId ~= nil then rosterById[myServerId] else nil

			_inGameHud:UpdateStats({
				troops = tonumber(me.troops),
				maxTroops = tonumber(me.maxTroops),
				troopRate = tonumber(me.troopRate),
				gold = tonumber(me.gold),
				goldRate = tonumber(me.goldRate or me.income or me.goldIncome) or 0,
				landPct = myLandPct,
				playerColor = if myEntry and myEntry.color then myEntry.color else nil,
				defenseAI = if me.defenseAI ~= nil then (me.defenseAI == true) else nil,
				attacks = mappedAttacks,
				weaponCooldowns = if type(me.weapons) == "table" then me.weapons else nil,
			})
		end)
	end

	local worldStats = remotes:FindFirstChild("WorldStats")
	if worldStats and worldStats:IsA("RemoteEvent") then
		worldStats.OnClientEvent:Connect(function(stats: any)
			if type(stats) ~= "table" then
				return
			end
			latestStats = stats
			currentMode = tostring(stats.mode or currentMode or "FREE")
			currentGoalPct = if stats.teamMode then 55 else 65

			if _deploymentHud and _deploymentHud.isDeploying then
				local isAlive = if latestMe then (latestMe.alive == true) else false
				local cap = if latestMe then latestMe.capital else nil
				_deploymentHud:SyncServerState(currentMode, tonumber(stats.spawnTimer) or 0, isAlive, cap)
				if stats.phase == "BATTLE" or stats.phase == "RUNNING" then
					_deploymentHud:FinishDeployment()
				end
			end

			if stats.phase == "ENDED" and not endedShownForMatch and not lobbyContainer.Visible then
				endedShownForMatch = true
				local bridge = getBridge()
				local bridgeState = if bridge and bridge.getState then bridge.getState() else nil
				local rosterById = if bridgeState then bridgeState.rosterById else nil
				local winnerEntry = if rosterById and stats.winner then rosterById[stats.winner] else nil
				local winnerName = if winnerEntry and winnerEntry.name then tostring(winnerEntry.name) else "Imperio Vencedor"
				local isMeWinner = myServerId ~= nil and stats.winner == myServerId
				showModal(
					if isMeWinner then "🏆 ¡HAS CONQUISTADO EL MUNDO!" else "🏆 PARTIDA FINALIZADA",
					"NUEVA RONDA AUTOMÁTICA EN 20 SEGUNDOS",
					string.format(
						"%s ha alcanzado el dominio territorial requerido (%d%%).\nPuedes seguir observando el mapa o salir al menú principal.",
						winnerName,
						currentGoalPct
					),
					MenuTheme.Colors.MonthlyBadge
				)
			end

			if not _inGameHud or not _inGameHud.root.Visible then
				return
			end

			local topList = if type(stats.top) == "table" then stats.top else stats.leaderboard
			local leaderName = "---"
			local leaderPct = 0
			if type(topList) == "table" and #topList > 0 then
				leaderName = tostring(topList[1].name or "Líder")
				leaderPct = tonumber(topList[1].pct) or 0
			end

			local myCells = if latestMe then (tonumber(latestMe.cells) or 0) else 0
			local landCount = tonumber(stats.landCount) or 1
			local myPct = (myCells / math.max(1, landCount)) * 100
			local myRank = 1
			if type(stats.nations) == "table" then
				for _, entry in ipairs(stats.nations) do
					if (tonumber(entry.cells) or 0) > myCells then
						myRank += 1
					end
				end
			elseif type(topList) == "table" then
				for idx, entry in ipairs(topList) do
					if (myServerId ~= nil and entry.id == myServerId) or entry.name == localPlayer.DisplayName then
						myRank = idx
						myPct = tonumber(entry.pct) or myPct
						break
					end
				end
			end

			_inGameHud:UpdateStats({
				rank = myRank,
				landPct = myPct,
				leaderName = leaderName,
				leaderPct = leaderPct,
				goalPct = currentGoalPct,
			})

			if _mapOverlay and stats.phase ~= "SPAWN" then
				local bridge = getBridge()
				local bridgeState = if bridge and bridge.getState then bridge.getState() else nil
				local rosterById = if bridgeState then bridgeState.rosterById else nil
				local mapW = if bridgeState and bridgeState.w then tonumber(bridgeState.w) or 960 else 960
				local mapH = if bridgeState and bridgeState.h then tonumber(bridgeState.h) or 400 else 400

				if type(stats.fronts) == "table" and _mapOverlay.UpdateFronts then
					local mappedFronts = {}
					for _, f in ipairs(stats.fronts) do
						local tId = tonumber(f.t) or 0
						local targetEntry = if rosterById and tId ~= 0 then rosterById[tId] else nil
						local targetName = if tId == 0
							then "Terreno neutral"
							elseif targetEntry and targetEntry.name then tostring(targetEntry.name)
							else ("Nación #" .. tostring(tId))
						local fCell = tonumber(f.c) or -1
						local fTroops = tonumber(f.k) or 0
						if fCell >= 0 and fTroops > 0 then
							table.insert(mappedFronts, {
								id = string.format("%d_%d", tonumber(f.a) or 0, tId),
								targetName = targetName,
								troops = fTroops,
								cell = fCell,
								isExpansion = (tId == 0),
								isMine = (myServerId ~= nil and tonumber(f.a) == myServerId),
							})
						end
					end
					_mapOverlay:UpdateFronts(mappedFronts, mapW, mapH)
				end

				if _mapOverlay.UpdateLeaderCrown and type(topList) == "table" and #topList > 0 then
					local leaderEntry = topList[1]
					local leaderId = tonumber(leaderEntry.id)
					local leaderRoster = if rosterById and leaderId then rosterById[leaderId] else nil
					local leaderCell = if leaderRoster and leaderRoster.capital then tonumber(leaderRoster.capital) else nil
					local isLocalLeader = (myServerId ~= nil and leaderId == myServerId)
					_mapOverlay:UpdateLeaderCrown(leaderCell, tostring(leaderEntry.name or leaderName), isLocalLeader, mapW, mapH)
				end
			end
		end)
	end

	local worldFx = remotes:FindFirstChild("WorldFx")
	if worldFx and worldFx:IsA("RemoteEvent") then
		worldFx.OnClientEvent:Connect(function(fx: any)
			if type(fx) ~= "table" or not _mapOverlay then
				return
			end
			if fx.kind == "GOLD_LOOT" then
				local bridge = getBridge()
				local bridgeState = if bridge and bridge.getState then bridge.getState() else nil
				local mapW = if bridgeState and bridgeState.w then tonumber(bridgeState.w) or 960 else 960
				local mapH = if bridgeState and bridgeState.h then tonumber(bridgeState.h) or 400 else 400
				local cellIdx = tonumber(fx.cell) or -1
				local amount = tonumber(fx.r) or 0
				if cellIdx >= 0 and amount > 0 and _mapOverlay.SpawnGoldLoot then
					_mapOverlay:SpawnGoldLoot(cellIdx, amount, mapW, mapH)
				end
			end
		end)
	end

	local worldNotice = remotes:FindFirstChild("WorldNotice")
	if worldNotice and worldNotice:IsA("RemoteEvent") then
		worldNotice.OnClientEvent:Connect(function(msg: any)
			local text = tostring(msg or "")
			if text == "" then
				return
			end
			if _deploymentHud and _deploymentHud.isDeploying then
				_deploymentHud:ShowToast(text, 3.5)
			elseif _inGameHud and _inGameHud.root.Visible then
				_inGameHud:ShowToast(text, 3.5)
			end
		end)
	end
end)

-- Conexión de atajos de teclado globales (H / Esc / M / Q-E / 1-0,-,= / Tab)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.H then
		if _howToPlayModal.isOpen then
			_howToPlayModal:Hide()
		else
			openHowToPlay()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		if _howToPlayModal.isOpen then
			_howToPlayModal:Hide()
		elseif modalBackdrop.Visible then
			closeModal()
		elseif _inGameHud and _inGameHud.root.Visible and _inGameHud.selectedSlotIndex ~= nil then
			_inGameHud:ClearBuildSlot()
			local bridge = getBridge()
			if bridge and bridge.setActionMode then
				bridge.setActionMode("ATTACK")
			end
			_inGameHud:ShowToast("⚔️ Modo ataque restaurado", 2.0)
		elseif lobbyContainer.Visible and _playMatchmakingPanel and _playMatchmakingPanel:IsSoloConfigOpen() then
			_playMatchmakingPanel:ShowLobbyContent()
		end
	elseif input.KeyCode == Enum.KeyCode.M then
		_topUtilityBar:ToggleMusic()
	elseif _inGameHud and _inGameHud.root.Visible then
		if input.KeyCode == Enum.KeyCode.Q then
			_inGameHud:CycleAttackPercent(-1)
		elseif input.KeyCode == Enum.KeyCode.E then
			_inGameHud:CycleAttackPercent(1)
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			_inGameHud:RetreatLatestAttack()
		elseif input.KeyCode == Enum.KeyCode.Tab then
			openLeaderboardModal()
		elseif input.KeyCode == Enum.KeyCode.G then
			_inGameHud:ClearBuildSlot()
			local bridge = getBridge()
			if bridge and bridge.setActionMode then
				bridge.setActionMode("ATTACK")
			end
			_inGameHud:ShowToast("⚔️ Modo ataque activo", 2.0)
		else
			local keyMap: { [Enum.KeyCode]: number } = {
				[Enum.KeyCode.One] = 1,
				[Enum.KeyCode.Two] = 2,
				[Enum.KeyCode.Three] = 3,
				[Enum.KeyCode.Four] = 4,
				[Enum.KeyCode.Five] = 5,
				[Enum.KeyCode.Six] = 6,
				[Enum.KeyCode.Seven] = 7,
				[Enum.KeyCode.Eight] = 8,
				[Enum.KeyCode.Nine] = 9,
				[Enum.KeyCode.Zero] = 10,
				[Enum.KeyCode.Minus] = 11,
				[Enum.KeyCode.Equals] = 12,
			}
			local slotIdx = keyMap[input.KeyCode]
			if slotIdx then
				_inGameHud:SelectBuildSlot(slotIdx)
			end
		end
	end
end)

local _partyPanel = PartyPanel.new(lobbyContainer, {
	OnInviteParty = function()
		Signals.OnInviteParty:Fire()
		if RegisteredCallbacks.OnInviteParty then
			RegisteredCallbacks.OnInviteParty()
		end
	end,
})

_playMatchmakingPanel = PlayMatchmakingPanel.new(lobbyContainer, {
	OnPlaySoloClicked = function()
		Signals.OnPlaySoloClicked:Fire()
		if RegisteredCallbacks.OnPlaySoloClicked then
			RegisteredCallbacks.OnPlaySoloClicked()
		end
	end,
	OnStartSoloGame = function(mapId: string, difficulty: string)
		launchSoloSession(mapId, difficulty)
	end,
	OnSoloHelpClicked = function()
		openHowToPlay()
	end,
	OnJoinMatchClicked = function(matchId: string, _entry: PlayMatchmakingPanel.MatchEntryData)
		Signals.OnJoinMatchClicked:Fire(matchId)
		if RegisteredCallbacks.OnJoinMatchClicked then
			RegisteredCallbacks.OnJoinMatchClicked(matchId)
		end
		launchGameSession(matchId)
	end,
})

local _rightRailShop = RightRailShop.new(lobbyContainer, {
	OnOpenArsenal = function()
		Signals.OnOpenArsenal:Fire()
		if RegisteredCallbacks.OnOpenArsenal then
			RegisteredCallbacks.OnOpenArsenal()
		end
		showModal(
			"ARSENAL MILITAR",
			"★ 148,510 ESTRELLAS DISPONIBLES",
			"Personaliza el aspecto visual de tus divisiones blindadas, flotas navales, fortificaciones ABM y efectos de impacto de misiles estratégicos.",
			MenuTheme.Colors.PillGold
		)
	end,
	OnOpenCrates = function()
		Signals.OnOpenCrates:Fire()
		if RegisteredCallbacks.OnOpenCrates then
			RegisteredCallbacks.OnOpenCrates()
		end
		showModal(
			"CAJAS DE SUMINISTRO",
			"◈ 15 TOKENS DE CAJA DISPONIBLES",
			"Abre cajas tácticas para desbloquear estandartes históricos, efectos de frontera luminosa y diseños exclusivos para tus capitales.",
			MenuTheme.Colors.BadgeGreen
		)
	end,
	OnOpenFlagShop = function()
		Signals.OnOpenFlagShop:Fire()
		if RegisteredCallbacks.OnOpenFlagShop then
			RegisteredCallbacks.OnOpenFlagShop()
		end
		showModal(
			"TIENDA DE BANDERAS",
			"ROTACIÓN DIARIA DE EMBLEMAS NACIONALES",
			"Equipa banderas personalizadas e históricas para tu imperio. La rotación diaria actualiza el catálogo automáticamente cada 24 horas.",
			MenuTheme.Colors.FlagGradEnd
		)
	end,
	OnOpenPass = function()
		Signals.OnOpenPass:Fire()
		if RegisteredCallbacks.OnOpenPass then
			RegisteredCallbacks.OnOpenPass()
		end
		showModal(
			"PASE MENSUAL: GENERAL",
			"VENTAJAS DE ALTO MANDO (★★★)",
			"• +50% Estrellas en cada partida completada.\n"
				.. "• Una nueva piel táctica exclusiva cada mes.\n"
				.. "• Insignia dorada de General en la tabla de clasificación y sala de espera.",
			MenuTheme.Colors.MonthlyBadge
		)
	end,
})

local _footerBar = FooterBar.new(lobbyContainer, {
	OnOpenCredits = function()
		openHowToPlay()
	end,
})

-- Exponer API global limpia para que otros scripts del cliente se comuniquen sin conflictos
local PublicAPI = {
	ScreenGui = screenGui,
	Signals = Signals,
	SetCallbacks = function(newCallbacks: MenuCallbacks)
		RegisteredCallbacks = newCallbacks
	end,
	SetCurrency = function(stars: number, crateTokens: number)
		_rightRailShop:SetCurrency(stars, crateTokens)
	end,
	UpdateMatchEntry = function(matchId: string, players: number?, maxPlayers: number?, secondsLeft: number?)
		_playMatchmakingPanel:UpdateMatchEntry(matchId, players, maxPlayers, secondsLeft)
	end,
	IsBlockingMap = function(): boolean
		return lobbyContainer.Visible or _howToPlayModal.isOpen or modalBackdrop.Visible
	end,
	IsPointOverHud = function(guiPos: Vector2): boolean
		if _deploymentHud and _deploymentHud.root.Visible then
			return _deploymentHud:IsPointOverHud(guiPos)
		end
		if _inGameHud and _inGameHud.root.Visible then
			return _inGameHud:IsPointOverHud(guiPos)
		end
		return false
	end,
	ClearSelectedSlot = function()
		if _inGameHud then
			_inGameHud:ClearBuildSlot()
		end
	end,
	Show = function()
		screenGui.Enabled = true
		returnToLobbyView()
	end,
	Hide = function()
		lobbyContainer.Visible = false
		_deploymentHud:Hide()
		_inGameHud:Hide()
		setLegacyLobbySuppressed(false)
	end,
	ShowSoloConfig = function()
		screenGui.Enabled = true
		lobbyContainer.Visible = true
		_deploymentHud:Hide()
		_inGameHud:Hide()
		_playMatchmakingPanel:ShowSoloConfig()
	end,
	EnterDeployment = function()
		screenGui.Enabled = true
		enterMapDeploymentView()
	end,
	EnterInGameHud = function()
		screenGui.Enabled = true
		enterInGameHudView()
	end,
	ExitToMenu = function()
		screenGui.Enabled = true
		returnToLobbyView()
	end,
	ShowHowToPlay = function()
		openHowToPlay()
	end,
	HideHowToPlay = function()
		_howToPlayModal:Hide()
	end,
	ToggleHowToPlay = function()
		_howToPlayModal:Toggle()
	end,
}

;(_G :: any).ConquerMainMenu = PublicAPI
return PublicAPI
