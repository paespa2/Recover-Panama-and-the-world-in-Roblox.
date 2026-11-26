--!strict
-- DeploymentHudOverlay.luau
-- HUD de fase de despliegue inicial en el mapa:
--  1. Barra superior izquierda de 6 botones circulares (Música, Ayuda ?, Leaderboard, Mapa/Globo, Config ⚙, Salir)
--  2. Banner superior centrado ("CHOOSE YOUR STARTING LOCATION" -> "DEPLOYING IN X" con anillo rojo animado #F43F5E + botón LISTO)
--  3. Tooltip flotante del cursor en tiempo real (#141E30) alineado con UIScale/GuiInset y datos reales del mapa.

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local DeploymentHudOverlay = {}
DeploymentHudOverlay.__index = DeploymentHudOverlay

export type DeploymentHudCallbacks = {
	OnToggleMusic: ((isMuted: boolean) -> ())?,
	OnOpenHelp: (() -> ())?,
	OnToggleLeaderboard: (() -> ())?,
	OnCenterMap: (() -> ())?,
	OnOpenSettings: (() -> ())?,
	OnExitToMenu: (() -> ())?,
	OnSelectCapitalTile: ((tileCoords: Vector2) -> ())?,
	OnDeploymentComplete: (() -> ())?,
}

export type DeploymentHudOverlayInstance = {
	root: Frame,
	isDeploying: boolean,
	hasSelectedCapital: boolean,
	isMuted: boolean,
	countdownToken: number,
	serverMode: string,
	lastCapitalCell: number?,
	cleanups: { () -> () },
	EnterDeployment: (self: DeploymentHudOverlayInstance) -> (),
	SelectCapital: (self: DeploymentHudOverlayInstance, tileCoords: Vector2) -> (),
	SyncServerState: (
		self: DeploymentHudOverlayInstance,
		mode: string,
		spawnTimer: number,
		isAlive: boolean,
		capitalCell: number?
	) -> (),
	ShowToast: (self: DeploymentHudOverlayInstance, text: string, duration: number?) -> (),
	IsPointOverHud: (self: DeploymentHudOverlayInstance, guiPos: Vector2) -> boolean,
	FinishDeployment: (self: DeploymentHudOverlayInstance) -> (),
	Hide: (self: DeploymentHudOverlayInstance) -> (),
	SetMusicMuted: (self: DeploymentHudOverlayInstance, muted: boolean) -> (),
	SetCursorBiome: (self: DeploymentHudOverlayInstance, statusText: string, biomeName: string) -> (),
	Destroy: (self: DeploymentHudOverlayInstance) -> (),
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
	btn.ZIndex = 17
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

function DeploymentHudOverlay.new(
	parent: Instance,
	callbacks: DeploymentHudCallbacks?
): DeploymentHudOverlayInstance
	local cb: DeploymentHudCallbacks = callbacks or {}
	local cleanups: { () -> () } = {}

	local root = Instance.new("Frame")
	root.Name = "DeploymentHudOverlay"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.Visible = false
	root.ZIndex = 15
	root.Parent = parent

	-- =========================================================================
	-- 1. BARRA HUD SUPERIOR IZQUIERDA (6 botones circulares)
	-- =========================================================================
	local topLeftInset, _ = GuiService:GetGuiInset()
	local leftOffset = math.max(155, topLeftInset.X + 145)

	local hudBar = Instance.new("Frame")
	hudBar.Name = "TopHudBar"
	hudBar.Position = UDim2.fromOffset(leftOffset, 14)
	hudBar.Size = UDim2.fromOffset(238, 38)
	hudBar.BackgroundTransparency = 1
	hudBar.ZIndex = 16
	hudBar.Parent = root

	local hudLayout = Instance.new("UIListLayout")
	hudLayout.FillDirection = Enum.FillDirection.Horizontal
	hudLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	hudLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hudLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hudLayout.Padding = UDim.new(0, 6)
	hudLayout.Parent = hudBar

	local musicBtn, musicStroke = createHudCircleButton(hudBar, "BtnHudMusic", "♪", 1)
	local helpBtn, helpStroke = createHudCircleButton(hudBar, "BtnHudHelp", "?", 2)
	local lbBtn, lbStroke = createHudCircleButton(hudBar, "BtnHudLeaderboard", "📊", 3)
	local globeBtn, globeStroke = createHudCircleButton(hudBar, "BtnHudGlobe", "🌐", 4)
	local settingsBtn, settingsStroke = createHudCircleButton(hudBar, "BtnHudSettings", "⚙", 5)
	local exitBtn, exitStroke = createHudCircleButton(hudBar, "BtnHudExit", "🚪", 6)

	local buttonStrokePairs = {
		{ btn = musicBtn, stroke = musicStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = helpBtn, stroke = helpStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = lbBtn, stroke = lbStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = globeBtn, stroke = globeStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = settingsBtn, stroke = settingsStroke, hover = MenuTheme.Colors.CyanAccent },
		{ btn = exitBtn, stroke = exitStroke, hover = MenuTheme.Colors.AccentRed },
	}
	for _, pair in ipairs(buttonStrokePairs) do
		table.insert(
			cleanups,
			MenuTheme.applyButtonFX(pair.btn, {
				stroke = pair.stroke,
				hoverStrokeColor = pair.hover,
			})
		)
	end

	-- =========================================================================
	-- 2. BANNER SUPERIOR CENTRADO (CHOOSE YOUR STARTING LOCATION / DEPLOYING IN X)
	-- =========================================================================
	local bannerShadow = Instance.new("Frame")
	bannerShadow.Name = "BannerShadow"
	bannerShadow.AnchorPoint = Vector2.new(0.5, 0)
	bannerShadow.Position = UDim2.new(0.5, 0, 0, 17)
	bannerShadow.Size = UDim2.fromOffset(524, 70)
	bannerShadow.BackgroundColor3 = Color3.fromHex("#000000")
	bannerShadow.BackgroundTransparency = 0.6
	bannerShadow.BorderSizePixel = 0
	bannerShadow.ZIndex = 15
	bannerShadow.Parent = root

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 12)
	shadowCorner.Parent = bannerShadow

	local banner = Instance.new("Frame")
	banner.Name = "DeploymentBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 14)
	banner.Size = UDim2.fromOffset(520, 68)
	banner.BackgroundColor3 = MenuTheme.Colors.ModalBg
	banner.BackgroundTransparency = 0.06
	banner.BorderSizePixel = 0
	banner.Active = true
	banner.ZIndex = 16
	banner.Parent = root

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 10)
	bannerCorner.Parent = banner

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = MenuTheme.Colors.CardStroke
	bannerStroke.Thickness = 1
	bannerStroke.Parent = banner

	local bannerTitle = Instance.new("TextLabel")
	bannerTitle.Name = "BannerTitle"
	bannerTitle.Position = UDim2.fromOffset(18, 12)
	bannerTitle.Size = UDim2.new(1, -172, 0, 22)
	bannerTitle.BackgroundTransparency = 1
	bannerTitle.Font = MenuTheme.Fonts.Heading
	bannerTitle.Text = "CHOOSE YOUR STARTING LOCATION"
	bannerTitle.TextColor3 = MenuTheme.Colors.White
	bannerTitle.TextSize = 15
	bannerTitle.TextXAlignment = Enum.TextXAlignment.Left
	bannerTitle.TextTruncate = Enum.TextTruncate.AtEnd
	bannerTitle.ZIndex = 17
	bannerTitle.Parent = banner

	local bannerSub = Instance.new("TextLabel")
	bannerSub.Name = "BannerSubtitle"
	bannerSub.Position = UDim2.fromOffset(18, 36)
	bannerSub.Size = UDim2.new(1, -172, 0, 18)
	bannerSub.BackgroundTransparency = 1
	bannerSub.Font = MenuTheme.Fonts.Regular
	bannerSub.Text = "Haz clic en tierra firme no reclamada para colocar tu capital."
	bannerSub.TextColor3 = MenuTheme.Colors.SubtleText
	bannerSub.TextSize = 11
	bannerSub.TextXAlignment = Enum.TextXAlignment.Left
	bannerSub.TextTruncate = Enum.TextTruncate.AtEnd
	bannerSub.ZIndex = 17
	bannerSub.Parent = banner

	local deployNowBtn = Instance.new("TextButton")
	deployNowBtn.Name = "BtnDeployNow"
	deployNowBtn.AnchorPoint = Vector2.new(1, 0.5)
	deployNowBtn.Position = UDim2.new(1, -66, 0.5, 0)
	deployNowBtn.Size = UDim2.fromOffset(92, 32)
	deployNowBtn.BackgroundColor3 = MenuTheme.Colors.BadgeGreen
	deployNowBtn.AutoButtonColor = false
	deployNowBtn.Font = MenuTheme.Fonts.Heading
	deployNowBtn.Text = "▶ LISTO"
	deployNowBtn.TextColor3 = MenuTheme.Colors.DarkText
	deployNowBtn.TextSize = 12
	deployNowBtn.Visible = false
	deployNowBtn.ZIndex = 18
	deployNowBtn.Parent = banner

	local dnbCorner = Instance.new("UICorner")
	dnbCorner.CornerRadius = MenuTheme.Corners.Pill
	dnbCorner.Parent = deployNowBtn

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(deployNowBtn, {
			baseColor = MenuTheme.Colors.BadgeGreen,
			hoverColor = Color3.fromHex("#34D399"),
		})
	)

	-- Anillo circular animado rojo/coral (#F43F5E) a la derecha del banner
	local countdownRing = Instance.new("Frame")
	countdownRing.Name = "CountdownRing"
	countdownRing.AnchorPoint = Vector2.new(1, 0.5)
	countdownRing.Position = UDim2.new(1, -14, 0.5, 0)
	countdownRing.Size = UDim2.fromOffset(42, 42)
	countdownRing.BackgroundColor3 = Color3.fromHex("#1F1220")
	countdownRing.BackgroundTransparency = 0.25
	countdownRing.Visible = false
	countdownRing.ZIndex = 17
	countdownRing.Parent = banner

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = MenuTheme.Corners.Pill
	ringCorner.Parent = countdownRing

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = MenuTheme.Colors.AccentRed
	ringStroke.Thickness = 3
	ringStroke.Parent = countdownRing

	local ringScale = Instance.new("UIScale")
	ringScale.Scale = 1
	ringScale.Parent = countdownRing

	local ringNumber = Instance.new("TextLabel")
	ringNumber.Name = "CountdownNumber"
	ringNumber.Size = UDim2.fromScale(1, 1)
	ringNumber.BackgroundTransparency = 1
	ringNumber.Font = MenuTheme.Fonts.Heading
	ringNumber.Text = "25"
	ringNumber.TextColor3 = MenuTheme.Colors.AccentRed
	ringNumber.TextSize = 16
	ringNumber.ZIndex = 18
	ringNumber.Parent = countdownRing

	-- Toast de despliegue bajo el banner
	local deployToast = Instance.new("Frame")
	deployToast.Name = "DeployToast"
	deployToast.AnchorPoint = Vector2.new(0.5, 0)
	deployToast.Position = UDim2.new(0.5, 0, 0, 90)
	deployToast.Size = UDim2.fromOffset(400, 32)
	deployToast.BackgroundColor3 = MenuTheme.Colors.ModalBg
	deployToast.BackgroundTransparency = 0.08
	deployToast.BorderSizePixel = 0
	deployToast.Visible = false
	deployToast.ZIndex = 18
	deployToast.Parent = root

	local dtCorner = Instance.new("UICorner")
	dtCorner.CornerRadius = UDim.new(0, 8)
	dtCorner.Parent = deployToast

	local dtStroke = Instance.new("UIStroke")
	dtStroke.Color = MenuTheme.Colors.CyanBorder
	dtStroke.Thickness = 1
	dtStroke.Parent = deployToast

	local deployToastLbl = Instance.new("TextLabel")
	deployToastLbl.Name = "ToastText"
	deployToastLbl.Position = UDim2.fromOffset(10, 0)
	deployToastLbl.Size = UDim2.new(1, -20, 1, 0)
	deployToastLbl.BackgroundTransparency = 1
	deployToastLbl.Font = MenuTheme.Fonts.Bold
	deployToastLbl.Text = ""
	deployToastLbl.TextColor3 = MenuTheme.Colors.White
	deployToastLbl.TextSize = 12
	deployToastLbl.TextTruncate = Enum.TextTruncate.AtEnd
	deployToastLbl.ZIndex = 19
	deployToastLbl.Parent = deployToast

	-- =========================================================================
	-- 3. TOOLTIP FLOTANTE DEL CURSOR
	-- =========================================================================
	local tooltip = Instance.new("Frame")
	tooltip.Name = "CursorTooltip"
	tooltip.Size = UDim2.fromOffset(252, 50)
	tooltip.Position = UDim2.fromOffset(0, 0)
	tooltip.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	tooltip.BackgroundTransparency = 0.12
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 18
	tooltip.Parent = root

	local ttCorner = Instance.new("UICorner")
	ttCorner.CornerRadius = UDim.new(0, 8)
	ttCorner.Parent = tooltip

	local ttStroke = Instance.new("UIStroke")
	ttStroke.Color = MenuTheme.Colors.CardStroke
	ttStroke.Thickness = 1
	ttStroke.Parent = tooltip

	local ttBiomeLbl = Instance.new("TextLabel")
	ttBiomeLbl.Name = "BiomeStatus"
	ttBiomeLbl.Position = UDim2.fromOffset(10, 6)
	ttBiomeLbl.Size = UDim2.new(1, -18, 0, 16)
	ttBiomeLbl.BackgroundTransparency = 1
	ttBiomeLbl.Font = MenuTheme.Fonts.Bold
	ttBiomeLbl.Text = "Terreno libre · Llanuras"
	ttBiomeLbl.TextColor3 = MenuTheme.Colors.White
	ttBiomeLbl.TextSize = 11
	ttBiomeLbl.TextXAlignment = Enum.TextXAlignment.Left
	ttBiomeLbl.TextTruncate = Enum.TextTruncate.AtEnd
	ttBiomeLbl.ZIndex = 19
	ttBiomeLbl.Parent = tooltip

	local ttDot = Instance.new("Frame")
	ttDot.Name = "GoldDot"
	ttDot.Position = UDim2.fromOffset(10, 30)
	ttDot.Size = UDim2.fromOffset(8, 8)
	ttDot.BackgroundColor3 = MenuTheme.Colors.AccentGold
	ttDot.BorderSizePixel = 0
	ttDot.ZIndex = 19
	ttDot.Parent = tooltip

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = MenuTheme.Corners.Pill
	dotCorner.Parent = ttDot

	local ttHintLbl = Instance.new("TextLabel")
	ttHintLbl.Name = "HintText"
	ttHintLbl.Position = UDim2.fromOffset(24, 25)
	ttHintLbl.Size = UDim2.new(1, -30, 0, 18)
	ttHintLbl.BackgroundTransparency = 1
	ttHintLbl.Font = MenuTheme.Fonts.Regular
	ttHintLbl.Text = "Haz clic para colocar tu capital aquí"
	ttHintLbl.TextColor3 = MenuTheme.Colors.SubtleText
	ttHintLbl.TextSize = 10
	ttHintLbl.TextXAlignment = Enum.TextXAlignment.Left
	ttHintLbl.TextTruncate = Enum.TextTruncate.AtEnd
	ttHintLbl.ZIndex = 19
	ttHintLbl.Parent = tooltip

	local customBiomeOverride: string? = nil

	local self = setmetatable({
		root = root,
		isDeploying = false,
		hasSelectedCapital = false,
		isMuted = false,
		countdownToken = 0,
		serverMode = "FREE",
		lastCapitalCell = nil :: number?,
		cleanups = cleanups,
		hudBar = hudBar,
		banner = banner,
		bannerShadow = bannerShadow,
		bannerTitle = bannerTitle,
		bannerSub = bannerSub,
		deployNowBtn = deployNowBtn,
		countdownRing = countdownRing,
		ringScale = ringScale,
		ringNumber = ringNumber,
		deployToast = deployToast,
		deployToastLbl = deployToastLbl,
		tooltip = tooltip,
		ttBiomeLbl = ttBiomeLbl,
		ttDot = ttDot,
		ttHintLbl = ttHintLbl,
		musicBtn = musicBtn,
		musicStroke = musicStroke,
		onDeploymentComplete = cb.OnDeploymentComplete,
		onSelectCapitalTile = cb.OnSelectCapitalTile,
		onToggleMusic = cb.OnToggleMusic,
	}, DeploymentHudOverlay)

	-- Seguir el puntero en tiempo real durante la fase de despliegue con compensación de UIScale y GuiInset
	local renderConn = RunService.RenderStepped:Connect(function()
		if not self.isDeploying or not self.root.Visible then
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
		local overUi = isPointInsideGui(hudBar, guiPos) or isPointInsideGui(banner, guiPos)
		if overUi then
			tooltip.Visible = false
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

		if not customBiomeOverride then
			if self.serverMode == "COUNTRIES" or self.serverMode == "CONTINENTS" then
				if info.isLand and info.ownerId ~= 0 and info.name then
					ttBiomeLbl.Text = string.format("🏳️ %s · %s tropas", tostring(info.name), formatCompact(info.troops or 0))
					ttDot.BackgroundColor3 = MenuTheme.Colors.BadgeGreen
					ttHintLbl.Text = "Haz clic para gobernar esta nación"
				else
					ttBiomeLbl.Text = "🌊 Océano"
					ttDot.BackgroundColor3 = MenuTheme.Colors.AccentRed
					ttHintLbl.Text = "Haz clic sobre un país del mapa"
				end
			else
				if not info.isLand then
					ttBiomeLbl.Text = "🌊 Océano · No habitable"
					ttDot.BackgroundColor3 = MenuTheme.Colors.AccentRed
					ttHintLbl.Text = "Elige tierra firme para tu capital"
				elseif not info.spawnValid then
					local blocker = if info.name then ("Ocupado / Cerca de " .. tostring(info.name)) else "Zona ocupada o muy cercana"
					ttBiomeLbl.Text = "⚠️ " .. blocker
					ttDot.BackgroundColor3 = MenuTheme.Colors.AccentRed
					ttHintLbl.Text = "Elige una zona libre más alejada"
				else
					ttBiomeLbl.Text = "Terreno libre · " .. tostring(info.biome or "Llanuras")
					ttDot.BackgroundColor3 = MenuTheme.Colors.BadgeGreen
					ttHintLbl.Text = if self.hasSelectedCapital
						then "Haz clic para reubicar tu capital aquí"
						else "Haz clic para fundar tu capital aquí"
				end
			end
		end

		local cam = Workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		local uiScaleObj = parent:FindFirstChildOfClass("UIScale")
		local scale = if uiScaleObj then math.max(0.01, uiScaleObj.Scale) else 1
		local x = math.clamp((mousePos.X + 16) / scale, 8, math.max(8, vp.X / scale - 260))
		local y = math.clamp((mousePos.Y + 18) / scale, 8, math.max(8, vp.Y / scale - 58))
		tooltip.Position = UDim2.fromOffset(x, y)
		tooltip.Visible = true
	end)
	table.insert(cleanups, function()
		renderConn:Disconnect()
	end)

	deployNowBtn.MouseButton1Click:Connect(function()
		if self.isDeploying and self.hasSelectedCapital then
			self:FinishDeployment()
		end
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

	lbBtn.MouseButton1Click:Connect(function()
		if cb.OnToggleLeaderboard then
			cb.OnToggleLeaderboard()
		end
	end)

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

	return (self :: any) :: DeploymentHudOverlayInstance
end

function DeploymentHudOverlay:SetMusicMuted(muted: boolean)
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

function DeploymentHudOverlay:SetCursorBiome(statusText: string, biomeName: string)
	self.ttBiomeLbl.Text = string.format("%s · %s", statusText, biomeName)
end

function DeploymentHudOverlay:ShowToast(text: string, duration: number?)
	self.deployToastLbl.Text = text
	self.deployToast.Visible = true
	local waitSec = duration or 3.5
	task.delay(waitSec, function()
		if self.deployToastLbl.Text == text then
			self.deployToast.Visible = false
		end
	end)
end

function DeploymentHudOverlay:IsPointOverHud(guiPos: Vector2): boolean
	if not self.root.Visible then
		return false
	end
	return isPointInsideGui(self.hudBar, guiPos) or isPointInsideGui(self.banner, guiPos)
end

function DeploymentHudOverlay:EnterDeployment()
	self.countdownToken += 1
	self.isDeploying = true
	self.hasSelectedCapital = false
	self.lastCapitalCell = nil
	self.deployNowBtn.Visible = false
	self.bannerTitle.Text = if self.serverMode == "COUNTRIES" or self.serverMode == "CONTINENTS"
		then "ELIGE TU PAÍS INICIAL"
		else "CHOOSE YOUR STARTING LOCATION"
	self.bannerSub.Text = if self.serverMode == "COUNTRIES" or self.serverMode == "CONTINENTS"
		then "Haz clic sobre cualquier país del mapa para tomar el mando."
		else "Haz clic en tierra firme no reclamada para colocar tu capital."
	self.countdownRing.Visible = true
	self.ringNumber.Text = "25"
	self.banner.Visible = true
	self.bannerShadow.Visible = true
	self.deployToast.Visible = false
	self.ttHintLbl.Text = "Haz clic para fundar tu capital aquí"
	self.root.Visible = true
end

function DeploymentHudOverlay:SyncServerState(
	mode: string,
	spawnTimer: number,
	isAlive: boolean,
	capitalCell: number?
)
	if type(mode) == "string" and mode ~= "" then
		self.serverMode = mode
	end
	if not self.isDeploying then
		return
	end
	if not isAlive then
		self.hasSelectedCapital = false
		self.lastCapitalCell = nil
		self.deployNowBtn.Visible = false
		self.countdownRing.Visible = true
		self.ringNumber.Text = tostring(math.max(0, math.floor(spawnTimer)))
		self.bannerTitle.Text = if self.serverMode == "COUNTRIES" or self.serverMode == "CONTINENTS"
			then "ELIGE TU PAÍS INICIAL"
			else "CHOOSE YOUR STARTING LOCATION"
		self.bannerSub.Text = if self.serverMode == "COUNTRIES" or self.serverMode == "CONTINENTS"
			then "Haz clic sobre cualquier país del mapa para tomar el mando."
			else "Haz clic en tierra firme no reclamada para colocar tu capital."
		return
	end

	self.deployNowBtn.Visible = true
	if not self.hasSelectedCapital or (capitalCell ~= nil and capitalCell ~= self.lastCapitalCell) then
		self.lastCapitalCell = capitalCell
		self:SelectCapital(Vector2.new(0, 0))
	end
end

function DeploymentHudOverlay:SelectCapital(tileCoords: Vector2)
	if not self.isDeploying then
		return
	end
	self.hasSelectedCapital = true
	self.deployNowBtn.Visible = true
	self.ttHintLbl.Text = "Haz clic en otro lugar para reubicar tu capital"
	self.bannerSub.Text = "Capital confirmada. Haz clic en otro lugar para reubicar o pulsa LISTO."
	self.countdownRing.Visible = true

	if self.onSelectCapitalTile then
		self.onSelectCapitalTile(tileCoords)
	end

	self.countdownToken += 1
	local myToken = self.countdownToken

	task.spawn(function()
		for sec = 4, 1, -1 do
			if not self.isDeploying or self.countdownToken ~= myToken then
				return
			end
			self.bannerTitle.Text = "DEPLOYING IN " .. tostring(sec)
			self.ringNumber.Text = tostring(sec)
			self.ringScale.Scale = 1.18
			TweenService:Create(
				self.ringScale,
				TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
			task.wait(1)
		end
		if self.isDeploying and self.countdownToken == myToken then
			self:FinishDeployment()
		end
	end)
end

function DeploymentHudOverlay:FinishDeployment()
	if not self.isDeploying then
		return
	end
	self.countdownToken += 1
	self.isDeploying = false
	self.deployNowBtn.Visible = false
	self.deployToast.Visible = false
	self.banner.Visible = false
	self.bannerShadow.Visible = false
	self.countdownRing.Visible = false
	self.tooltip.Visible = false
	if self.onDeploymentComplete then
		self.onDeploymentComplete()
	end
end

function DeploymentHudOverlay:Hide()
	self.countdownToken += 1
	self.isDeploying = false
	self.hasSelectedCapital = false
	self.lastCapitalCell = nil
	self.deployNowBtn.Visible = false
	self.deployToast.Visible = false
	self.tooltip.Visible = false
	self.root.Visible = false
end

function DeploymentHudOverlay:Destroy()
	self:Hide()
	for _, fn in ipairs(self.cleanups) do
		fn()
	end
	table.clear(self.cleanups)
	if self.root then
		self.root:Destroy()
	end
end

return DeploymentHudOverlay
