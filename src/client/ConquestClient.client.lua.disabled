--!strict
-- ConquestClient.client.lua
-- Cliente completo para "Recuperar Panamá, el Sistema Solar y Andrómeda":
-- 1) LOBBY MULTIJUGADOR INTERACTIVO:
--    - 4 Modos de Juego (Amigos vs Bots, Cooperativo Mundo vs Bots, Movimientos Históricos, Historia Evolutiva Dinosaurio->Homo Sapiens)
--    - 10 Comandantes Históricos (Torrijos, Nikola Tesla, Isaac Newton, Trump, Pablo Escobar, Simón Bolívar, Einstein, Napoleón, Gengis Kan, Darwin)
--    - Catálogo de 28 Mapas con filtro por categoría y estrellas de dificultad (Tierra, Historia, Sistema Solar, Galaxia Andrómeda, Evolución)
-- 2) VISTA DUAL:
--    - Tablero 2D Pixel Art interactivo con siluetas, Countryballs, edificios, tropas y crisis
--    - Vista del Globo Terráqueo / Planetario 3D en tiempo real (con rotación orbital)
-- 3) ÁRBOL DE EVOLUCIÓN E INVESTIGACIÓN + DESPLIEGUE DE ARMAMENTO BÉLICO Y TROPAS FICTICIAS
-- 4) BANNER DE CRISIS HUMANITARIAS + DEDO DIVINO + IA DE DEFENSA TERRITORIAL

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MapData = require(Shared:WaitForChild("MapData"))
local CountryballUI = require(script.Parent:WaitForChild("CountryballUI"))

local RemotesFolder = ReplicatedStorage:WaitForChild("ConquestRemotes")
local StateSyncEvent = RemotesFolder:WaitForChild("StateSyncEvent") :: RemoteEvent
local PlayerCommandEvent = RemotesFolder:WaitForChild("PlayerCommandEvent") :: RemoteEvent
local CombatFxEvent = RemotesFolder:WaitForChild("CombatFxEvent") :: RemoteEvent

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Estado local del cliente
local currentMapId: string = "PANAMA"
local selectedLobbyMode: string = "FRIENDS_VS_BOTS"
local selectedLobbyCommander: string = "TORRIJOS"
local selectedLobbyMap: string = "PANAMA"

local selectedRegionId: string? = nil
local activeToolId: string = "Conquer"
local sendTroopRatio: number = 0.50
local is3DGlobeView: boolean = false
local latestServerState: any = nil
local globeOrbitAngle: number = 0

local regionWidgets: {
	[string]: {
		root: TextButton,
		pixelBlocks: { Frame },
		troopLabel: TextLabel,
		nameLabel: TextLabel,
		buildingBadge: TextLabel,
		unitBadge: TextLabel,
		crisisBadge: TextLabel,
		countryballContainer: Frame,
		currentOwner: string,
		selectionStroke: UIStroke,
	},
} =
	{}

-- ScreenGui Principal
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PixelConquest2DGui"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ============================================================================
-- LIENZO 2D PIXEL DEL MAPA (OCULTO CUANDO EL JUGADOR ACTIVA LA VISTA GLOBO 3D)
-- ============================================================================
local oceanCanvas = Instance.new("Frame")
oceanCanvas.Name = "OceanCanvas"
oceanCanvas.Size = UDim2.fromScale(1, 1)
oceanCanvas.BackgroundColor3 = Color3.fromRGB(18, 78, 137)
oceanCanvas.BorderSizePixel = 0
oceanCanvas.Parent = screenGui

local gridOverlay = Instance.new("Frame")
gridOverlay.Name = "PixelGridOverlay"
gridOverlay.Size = UDim2.fromScale(1, 1)
gridOverlay.BackgroundTransparency = 1
gridOverlay.Parent = oceanCanvas

for i = 1, 18 do
	local hLine = Instance.new("Frame")
	hLine.Size = UDim2.new(1, 0, 0, 1)
	hLine.Position = UDim2.fromScale(0, i / 19)
	hLine.BackgroundColor3 = Color3.fromRGB(65, 155, 225)
	hLine.BackgroundTransparency = 0.86
	hLine.BorderSizePixel = 0
	hLine.Parent = gridOverlay

	local vLine = Instance.new("Frame")
	vLine.Size = UDim2.new(0, 1, 1, 0)
	vLine.Position = UDim2.fromScale(i / 19, 0)
	vLine.BackgroundColor3 = Color3.fromRGB(65, 155, 225)
	vLine.BackgroundTransparency = 0.86
	vLine.BorderSizePixel = 0
	vLine.Parent = gridOverlay
end

local routesLayer = Instance.new("Frame")
routesLayer.Name = "RoutesLayer"
routesLayer.Size = UDim2.fromScale(1, 1)
routesLayer.BackgroundTransparency = 1
routesLayer.ZIndex = 2
routesLayer.Parent = oceanCanvas

local mapNodesLayer = Instance.new("Frame")
mapNodesLayer.Name = "MapNodesLayer"
mapNodesLayer.Size = UDim2.fromScale(1, 1)
mapNodesLayer.BackgroundTransparency = 1
mapNodesLayer.ZIndex = 5
mapNodesLayer.Parent = oceanCanvas

local fxLayer = Instance.new("Frame")
fxLayer.Name = "FxLayer"
fxLayer.Size = UDim2.fromScale(1, 1)
fxLayer.BackgroundTransparency = 1
fxLayer.ZIndex = 12
fxLayer.Parent = oceanCanvas

-- ============================================================================
-- BARRA SUPERIOR (ECONOMÍA, CIENCIA, EVOLUCIÓN, VISTA GLOBO 3D Y LOBBY)
-- ============================================================================
local topBar = Instance.new("Frame")
topBar.Name = "TopHudBar"
topBar.Size = UDim2.new(1, -20, 0, 68)
topBar.Position = UDim2.fromOffset(10, 8)
topBar.BackgroundColor3 = Color3.fromRGB(16, 22, 32)
topBar.BorderSizePixel = 2
topBar.BorderColor3 = Color3.fromRGB(241, 196, 15)
topBar.ZIndex = 20
topBar.Parent = screenGui

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(0.27, 0, 0, 28)
TitleLabel.Position = UDim2.fromOffset(10, 4)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.Arcade
TitleLabel.Text = "🇵🇦 01. ISTMO DE PANAMÁ"
TitleLabel.TextColor3 = Color3.fromRGB(255, 235, 130)
TitleLabel.TextSize = 14
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = topBar

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.Size = UDim2.new(0.28, 0, 0, 32)
SubtitleLabel.Position = UDim2.fromOffset(10, 32)
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.Font = Enum.Font.Code
SubtitleLabel.Text = "Selecciona un territorio propio para construir, desplegar tropas o expandirte"
SubtitleLabel.TextColor3 = Color3.fromRGB(190, 215, 240)
SubtitleLabel.TextSize = 12
SubtitleLabel.TextWrapped = true
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubtitleLabel.Parent = topBar

local statsLabel = Instance.new("TextLabel")
statsLabel.Name = "StatsLabel"
statsLabel.Size = UDim2.new(0.32, 0, 1, -12)
statsLabel.Position = UDim2.new(0.28, 4, 0, 6)
statsLabel.BackgroundColor3 = Color3.fromRGB(10, 15, 22)
statsLabel.BorderSizePixel = 1
statsLabel.BorderColor3 = Color3.fromRGB(80, 115, 155)
statsLabel.Font = Enum.Font.Arcade
statsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statsLabel.TextSize = 12
statsLabel.Text = "💰Oro: 360 | 🛢️Pet: 75 | 🧬Ciencia: 60\n⚔️Tropas: 325/600 | 🌍Dominio: 14%"
statsLabel.Parent = topBar

-- Botón de Evolución Científica (Dinosaurio -> Homo Sapiens -> Tesla -> Andrómeda)
local evolveBtn = Instance.new("TextButton")
evolveBtn.Name = "EvolveButton"
evolveBtn.Size = UDim2.new(0.14, -6, 1, -12)
evolveBtn.Position = UDim2.new(0.60, 6, 0, 6)
evolveBtn.BackgroundColor3 = Color3.fromRGB(0, 135, 130)
evolveBtn.BorderSizePixel = 2
evolveBtn.BorderColor3 = Color3.fromRGB(0, 255, 230)
evolveBtn.Font = Enum.Font.Arcade
evolveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
evolveBtn.TextSize = 11
evolveBtn.TextWrapped = true
evolveBtn.Text = "🧬 EVOLUCIONAR\nSiguiente Era"
evolveBtn.Parent = topBar

evolveBtn.MouseButton1Click:Connect(function()
	PlayerCommandEvent:FireServer({
		action = "EVOLVE_ERA",
	})
end)

-- Botón de IA de Defensa Territorial
local aiDefenseBtn = Instance.new("TextButton")
aiDefenseBtn.Name = "AiDefenseButton"
aiDefenseBtn.Size = UDim2.new(0.10, -6, 1, -12)
aiDefenseBtn.Position = UDim2.new(0.74, 4, 0, 6)
aiDefenseBtn.BackgroundColor3 = Color3.fromRGB(22, 115, 75)
aiDefenseBtn.BorderSizePixel = 2
aiDefenseBtn.BorderColor3 = Color3.fromRGB(46, 204, 113)
aiDefenseBtn.Font = Enum.Font.Arcade
aiDefenseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
aiDefenseBtn.TextSize = 10
aiDefenseBtn.TextWrapped = true
aiDefenseBtn.Text = "🤖 IA Defensa:\nSMART"
aiDefenseBtn.Parent = topBar

local aiModeCycle = { "SMART", "FORTIFY", "MANUAL" }
local currentAiIndex = 1
aiDefenseBtn.MouseButton1Click:Connect(function()
	currentAiIndex = (currentAiIndex % #aiModeCycle) + 1
	PlayerCommandEvent:FireServer({
		action = "SET_AI_DEFENSE",
		mode = aiModeCycle[currentAiIndex],
	})
end)

-- Botón Vista Globo 3D vs Tablero 2D Pixel
local globeViewBtn = Instance.new("TextButton")
globeViewBtn.Name = "GlobeViewButton"
globeViewBtn.Size = UDim2.new(0.08, -6, 1, -12)
globeViewBtn.Position = UDim2.new(0.84, 4, 0, 6)
globeViewBtn.BackgroundColor3 = Color3.fromRGB(65, 50, 135)
globeViewBtn.BorderSizePixel = 2
globeViewBtn.BorderColor3 = Color3.fromRGB(175, 145, 255)
globeViewBtn.Font = Enum.Font.Arcade
globeViewBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
globeViewBtn.TextSize = 10
globeViewBtn.TextWrapped = true
globeViewBtn.Text = "🌐 VER:\nGLOBO 3D"
globeViewBtn.Parent = topBar

globeViewBtn.MouseButton1Click:Connect(function()
	is3DGlobeView = not is3DGlobeView
	oceanCanvas.Visible = not is3DGlobeView
	globeViewBtn.Text = if is3DGlobeView then "🗺️ VER:\nMAPA 2D" else "🌐 VER:\nGLOBO 3D"
	globeViewBtn.BackgroundColor3 = if is3DGlobeView then Color3.fromRGB(211, 84, 0) else Color3.fromRGB(65, 50, 135)
end)

-- Botón para abrir el Lobby Multijugador (28 Mapas, Modos, Líderes Históricos)
local openLobbyBtn = Instance.new("TextButton")
openLobbyBtn.Name = "OpenLobbyButton"
openLobbyBtn.Size = UDim2.new(0.08, -8, 1, -12)
openLobbyBtn.Position = UDim2.new(0.92, 4, 0, 6)
openLobbyBtn.BackgroundColor3 = Color3.fromRGB(210, 16, 52)
openLobbyBtn.BorderSizePixel = 2
openLobbyBtn.BorderColor3 = Color3.fromRGB(255, 235, 100)
openLobbyBtn.Font = Enum.Font.Arcade
openLobbyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
openLobbyBtn.TextSize = 11
openLobbyBtn.TextWrapped = true
openLobbyBtn.Text = "🏛️ LOBBY\n28 MAPAS"
openLobbyBtn.Parent = topBar

-- ============================================================================
-- BANNER DE ALERTA DE CRISIS HUMANITARIA
-- ============================================================================
local crisisBanner = Instance.new("TextLabel")
crisisBanner.Name = "CrisisAlertBanner"
crisisBanner.Size = UDim2.new(0.46, 0, 0, 26)
crisisBanner.AnchorPoint = Vector2.new(0.5, 0)
crisisBanner.Position = UDim2.new(0.5, 0, 0, 80)
crisisBanner.BackgroundColor3 = Color3.fromRGB(165, 28, 48)
crisisBanner.BorderSizePixel = 2
crisisBanner.BorderColor3 = Color3.fromRGB(255, 220, 90)
crisisBanner.Font = Enum.Font.Arcade
crisisBanner.TextColor3 = Color3.fromRGB(255, 255, 255)
crisisBanner.TextSize = 11
crisisBanner.Text = "☣️ SIN CRISIS HUMANITARIAS ACTIVAS"
crisisBanner.Visible = false
crisisBanner.ZIndex = 20
crisisBanner.Parent = screenGui

-- ============================================================================
-- PANEL IZQUIERDO: BITÁCORA + RATIO DE ENVÍO DE TROPAS
-- ============================================================================
local leftPanel = Instance.new("Frame")
leftPanel.Name = "LeftTacticalPanel"
leftPanel.Size = UDim2.fromOffset(275, 220)
leftPanel.Position = UDim2.new(0, 10, 1, -315)
leftPanel.BackgroundColor3 = Color3.fromRGB(16, 22, 30)
leftPanel.BackgroundTransparency = 0.1
leftPanel.BorderSizePixel = 2
leftPanel.BorderColor3 = Color3.fromRGB(70, 95, 130)
leftPanel.ZIndex = 20
leftPanel.Parent = screenGui

local ratioTitle = Instance.new("TextLabel")
ratioTitle.Size = UDim2.new(1, -12, 0, 20)
ratioTitle.Position = UDim2.fromOffset(6, 4)
ratioTitle.BackgroundTransparency = 1
ratioTitle.Font = Enum.Font.Arcade
ratioTitle.TextColor3 = Color3.fromRGB(241, 196, 15)
ratioTitle.TextSize = 11
ratioTitle.Text = "% TROPAS AL MARCHAR:"
ratioTitle.Parent = leftPanel

local ratioButtonsFrame = Instance.new("Frame")
ratioButtonsFrame.Size = UDim2.new(1, -12, 0, 26)
ratioButtonsFrame.Position = UDim2.fromOffset(6, 25)
ratioButtonsFrame.BackgroundTransparency = 1
ratioButtonsFrame.Parent = leftPanel

local ratios = {
	{ label = "25%", val = 0.25 },
	{ label = "50%", val = 0.50 },
	{ label = "75%", val = 0.75 },
	{ label = "85%", val = 0.85 },
}

local ratioBtns: { TextButton } = {}
for idx, rInfo in ipairs(ratios) do
	local rBtn = Instance.new("TextButton")
	rBtn.Size = UDim2.new(0.24, -2, 1, 0)
	rBtn.Position = UDim2.fromScale((idx - 1) * 0.25, 0)
	rBtn.BackgroundColor3 = if rInfo.val == sendTroopRatio
		then Color3.fromRGB(210, 16, 52)
		else Color3.fromRGB(40, 52, 70)
	rBtn.BorderSizePixel = 1
	rBtn.BorderColor3 = Color3.fromRGB(220, 220, 220)
	rBtn.Font = Enum.Font.Arcade
	rBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	rBtn.TextSize = 11
	rBtn.Text = rInfo.label
	rBtn.Parent = ratioButtonsFrame
	table.insert(ratioBtns, rBtn)

	rBtn.MouseButton1Click:Connect(function()
		sendTroopRatio = rInfo.val
		for _, b in ipairs(ratioBtns) do
			b.BackgroundColor3 = Color3.fromRGB(40, 52, 70)
		end
		rBtn.BackgroundColor3 = Color3.fromRGB(210, 16, 52)
	end)
end

local logHeader = Instance.new("TextLabel")
logHeader.Size = UDim2.new(1, -12, 0, 18)
logHeader.Position = UDim2.fromOffset(6, 55)
logHeader.BackgroundTransparency = 1
logHeader.Font = Enum.Font.Arcade
logHeader.TextColor3 = Color3.fromRGB(130, 200, 255)
logHeader.TextSize = 11
logHeader.TextXAlignment = Enum.TextXAlignment.Left
logHeader.Text = "📡 BITÁCORA DE GUERRA & EVOLUCIÓN:"
logHeader.Parent = leftPanel

local logTextLabel = Instance.new("TextLabel")
logTextLabel.Size = UDim2.new(1, -12, 1, -78)
logTextLabel.Position = UDim2.fromOffset(6, 74)
logTextLabel.BackgroundTransparency = 1
logTextLabel.Font = Enum.Font.Code
logTextLabel.TextColor3 = Color3.fromRGB(215, 225, 235)
logTextLabel.TextSize = 11
logTextLabel.TextXAlignment = Enum.TextXAlignment.Left
logTextLabel.TextYAlignment = Enum.TextYAlignment.Top
logTextLabel.TextWrapped = true
logTextLabel.Text = "Iniciando radar..."
logTextLabel.Parent = leftPanel

-- ============================================================================
-- PANEL DERECHO: DESPLIEGUE DE TROPAS FICTICIAS & ARMAMENTO BÉLICO HISTÓRICO
-- ============================================================================
local rightArmoryPanel = Instance.new("Frame")
rightArmoryPanel.Name = "RightArmoryPanel"
rightArmoryPanel.Size = UDim2.fromOffset(250, 235)
rightArmoryPanel.Position = UDim2.new(1, -260, 1, -330)
rightArmoryPanel.BackgroundColor3 = Color3.fromRGB(16, 22, 30)
rightArmoryPanel.BackgroundTransparency = 0.08
rightArmoryPanel.BorderSizePixel = 2
rightArmoryPanel.BorderColor3 = Color3.fromRGB(214, 69, 65)
rightArmoryPanel.ZIndex = 20
rightArmoryPanel.Parent = screenGui

local armoryHeader = Instance.new("TextLabel")
armoryHeader.Size = UDim2.new(1, -10, 0, 22)
armoryHeader.Position = UDim2.fromOffset(5, 4)
armoryHeader.BackgroundTransparency = 1
armoryHeader.Font = Enum.Font.Arcade
armoryHeader.TextColor3 = Color3.fromRGB(255, 195, 110)
armoryHeader.TextSize = 11
armoryHeader.Text = "🦖🚀 ARMAMENTO & TROPAS ÉLITE"
armoryHeader.Parent = rightArmoryPanel

local armoryScroll = Instance.new("ScrollingFrame")
armoryScroll.Size = UDim2.new(1, -10, 1, -32)
armoryScroll.Position = UDim2.fromOffset(5, 28)
armoryScroll.BackgroundTransparency = 1
armoryScroll.ScrollBarThickness = 5
armoryScroll.CanvasSize = UDim2.fromOffset(0, #GameConfig.UNIT_ORDER * 42)
armoryScroll.Parent = rightArmoryPanel

for idx, unitId in ipairs(GameConfig.UNIT_ORDER) do
	local uDef = GameConfig.MILITARY_UNITS[unitId]
	local uBtn = Instance.new("TextButton")
	uBtn.Name = "Deploy_" .. unitId
	uBtn.Size = UDim2.new(1, -8, 0, 38)
	uBtn.Position = UDim2.fromOffset(2, (idx - 1) * 41)
	uBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 56)
	uBtn.BorderSizePixel = 1
	uBtn.BorderColor3 = Color3.fromRGB(110, 145, 190)
	uBtn.Font = Enum.Font.Arcade
	uBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	uBtn.TextSize = 10
	uBtn.TextWrapped = true
	uBtn.TextXAlignment = Enum.TextXAlignment.Left
	uBtn.Text = string.format(
		" %s [Era %d] %s\n 💰%d 🛢️%d -> +%d Tropas",
		uDef.icon,
		uDef.minEra,
		uDef.name,
		uDef.costGold,
		uDef.costOil,
		uDef.troopBonus
	)
	uBtn.Parent = armoryScroll

	uBtn.MouseButton1Click:Connect(function()
		if not selectedRegionId then
			SubtitleLabel.Text = "⚠️ Selecciona primero un territorio tuyo para desplegar " .. uDef.name
			return
		end
		PlayerCommandEvent:FireServer({
			action = "DEPLOY_UNIT",
			regionId = selectedRegionId,
			unitId = unitId,
		})
	end)
end

-- ============================================================================
-- BARRA INFERIOR: DEDO DIVINO + AYUDA HUMANITARIA + CONSTRUCCIÓN DE EDIFICIOS
-- ============================================================================
local bottomDock = Instance.new("Frame")
bottomDock.Name = "BottomDock"
bottomDock.Size = UDim2.new(1, -20, 0, 82)
bottomDock.Position = UDim2.new(0, 10, 1, -88)
bottomDock.BackgroundColor3 = Color3.fromRGB(16, 22, 32)
bottomDock.BorderSizePixel = 2
bottomDock.BorderColor3 = Color3.fromRGB(241, 196, 15)
bottomDock.ZIndex = 20
bottomDock.Parent = screenGui

local godToolsContainer = Instance.new("Frame")
godToolsContainer.Size = UDim2.new(0.42, -8, 1, -12)
godToolsContainer.Position = UDim2.fromOffset(6, 6)
godToolsContainer.BackgroundTransparency = 1
godToolsContainer.Parent = bottomDock

local toolOrder = { "Conquer", "HumanitarianAid", "DivineFinger", "DivineShield", "Meteor" }
local toolButtons: { [string]: TextButton } = {}

for idx, toolId in ipairs(toolOrder) do
	local tDef = GameConfig.GOD_TOOLS[toolId]
	local btn = Instance.new("TextButton")
	btn.Name = "Tool_" .. toolId
	btn.Size = UDim2.new(1 / #toolOrder, -4, 1, 0)
	btn.Position = UDim2.new((idx - 1) / #toolOrder, 2, 0, 0)
	btn.BackgroundColor3 = if toolId == activeToolId then Color3.fromRGB(210, 16, 52) else Color3.fromRGB(34, 46, 64)
	btn.BorderSizePixel = 2
	btn.BorderColor3 = Color3.fromRGB(240, 200, 60)
	btn.Font = Enum.Font.Arcade
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 10
	btn.TextWrapped = true
	local costText = if tDef.costGold > 0
		then string.format("\n💰%d 🛢️%d", tDef.costGold, tDef.costOil)
		else "\n[ORDEN]"
	btn.Text = string.format("%s %s%s", tDef.icon, tDef.name, costText)
	btn.Parent = godToolsContainer
	toolButtons[toolId] = btn

	btn.MouseButton1Click:Connect(function()
		activeToolId = toolId
		for id, b in pairs(toolButtons) do
			b.BackgroundColor3 = if id == activeToolId then Color3.fromRGB(210, 16, 52) else Color3.fromRGB(34, 46, 64)
		end
		SubtitleLabel.Text = string.format("%s %s: %s", tDef.icon, tDef.name, tDef.description)
	end)
end

local buildingsContainer = Instance.new("Frame")
buildingsContainer.Size = UDim2.new(0.58, -10, 1, -12)
buildingsContainer.Position = UDim2.new(0.42, 4, 0, 6)
buildingsContainer.BackgroundTransparency = 1
buildingsContainer.Parent = bottomDock

for idx, bId in ipairs(GameConfig.BUILDING_ORDER) do
	local bDef = GameConfig.BUILDINGS[bId]
	local bBtn = Instance.new("TextButton")
	bBtn.Name = "Build_" .. bId
	bBtn.Size = UDim2.new(1 / #GameConfig.BUILDING_ORDER, -4, 1, 0)
	bBtn.Position = UDim2.new((idx - 1) / #GameConfig.BUILDING_ORDER, 2, 0, 0)
	bBtn.BackgroundColor3 = Color3.fromRGB(28, 38, 52)
	bBtn.BorderSizePixel = 2
	bBtn.BorderColor3 = bDef.color
	bBtn.Font = Enum.Font.Arcade
	bBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	bBtn.TextSize = 10
	bBtn.TextWrapped = true
	bBtn.Text = string.format("%s %s\n💰%d 🛢️%d", bDef.icon, bDef.name, bDef.costGold, bDef.costOil)
	bBtn.Parent = buildingsContainer

	bBtn.MouseButton1Click:Connect(function()
		if not selectedRegionId then
			SubtitleLabel.Text = "⚠️ Selecciona primero un territorio tuyo para construir " .. bDef.name
			return
		end
		PlayerCommandEvent:FireServer({
			action = "BUILD",
			regionId = selectedRegionId,
			buildingId = bId,
		})
	end)
end

-- ============================================================================
-- LOBBY MULTIJUGADOR MODAL (MODOS DE JUEGO, LÍDERES HISTÓRICOS Y 28 MAPAS)
-- ============================================================================
local lobbyOverlay = Instance.new("Frame")
lobbyOverlay.Name = "MultiplayerLobbyModal"
lobbyOverlay.Size = UDim2.fromScale(1, 1)
lobbyOverlay.BackgroundColor3 = Color3.fromRGB(8, 12, 20)
lobbyOverlay.BackgroundTransparency = 0.06
lobbyOverlay.ZIndex = 40
lobbyOverlay.Visible = true -- Empieza abierto para que el jugador elija modo, comandante y mapa
lobbyOverlay.Parent = screenGui

local lobbyTitle = Instance.new("TextLabel")
lobbyTitle.Size = UDim2.new(1, -40, 0, 42)
lobbyTitle.Position = UDim2.fromOffset(20, 12)
lobbyTitle.BackgroundTransparency = 1
lobbyTitle.Font = Enum.Font.Arcade
lobbyTitle.TextColor3 = Color3.fromRGB(255, 230, 100)
lobbyTitle.TextSize = 20
lobbyTitle.Text = "🌍🌌 LOBBY MULTIJUGADOR: TIERRA, SISTEMA SOLAR & ANDRÓMEDA (28 MAPAS)"
lobbyTitle.Parent = lobbyOverlay

local lobbySub = Instance.new("TextLabel")
lobbySub.Size = UDim2.new(1, -40, 0, 22)
lobbySub.Position = UDim2.fromOffset(20, 52)
lobbySub.BackgroundTransparency = 1
lobbySub.Font = Enum.Font.Code
lobbySub.TextColor3 = Color3.fromRGB(185, 215, 245)
lobbySub.TextSize = 14
lobbySub.Text =
	"Elige Modo de Juego (Amigos/Co-op/Guerras/Evolución), Personaje Histórico y cualquiera de los 28 Mapas:"
lobbySub.Parent = lobbyOverlay

-- COLUMNA 1 DEL LOBBY: 4 MODOS DE JUEGO
local modeCol = Instance.new("Frame")
modeCol.Size = UDim2.new(0.27, -16, 0.72, 0)
modeCol.Position = UDim2.new(0, 16, 0, 82)
modeCol.BackgroundColor3 = Color3.fromRGB(16, 24, 36)
modeCol.BorderSizePixel = 2
modeCol.BorderColor3 = Color3.fromRGB(52, 152, 219)
modeCol.ZIndex = 41
modeCol.Parent = lobbyOverlay

local modeHeader = Instance.new("TextLabel")
modeHeader.Size = UDim2.new(1, 0, 0, 28)
modeHeader.BackgroundColor3 = Color3.fromRGB(24, 36, 54)
modeHeader.Font = Enum.Font.Arcade
modeHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
modeHeader.TextSize = 13
modeHeader.Text = "1. MODO MULTIJUGADOR"
modeHeader.ZIndex = 42
modeHeader.Parent = modeCol

local modeButtons: { [string]: TextButton } = {}
for idx, mId in ipairs(GameConfig.GAME_MODE_ORDER) do
	local mDef = GameConfig.GAME_MODES[mId]
	local mBtn = Instance.new("TextButton")
	mBtn.Size = UDim2.new(1, -16, 0.22, -8)
	mBtn.Position = UDim2.new(0, 8, 0.08 + (idx - 1) * 0.225, 0)
	mBtn.BackgroundColor3 = if mId == selectedLobbyMode then Color3.fromRGB(0, 115, 195) else Color3.fromRGB(28, 38, 54)
	mBtn.BorderSizePixel = 2
	mBtn.BorderColor3 = Color3.fromRGB(241, 196, 15)
	mBtn.Font = Enum.Font.Arcade
	mBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	mBtn.TextSize = 11
	mBtn.TextWrapped = true
	mBtn.Text = string.format("%s\n%s", mDef.name, mDef.description)
	mBtn.ZIndex = 42
	mBtn.Parent = modeCol
	modeButtons[mId] = mBtn

	mBtn.MouseButton1Click:Connect(function()
		selectedLobbyMode = mId
		for id, b in pairs(modeButtons) do
			b.BackgroundColor3 = if id == selectedLobbyMode
				then Color3.fromRGB(0, 115, 195)
				else Color3.fromRGB(28, 38, 54)
		end
	end)
end

-- COLUMNA 2 DEL LOBBY: PERSONAJES IMPORTANTES DE LA HISTORIA / COMANDANTES
local cmdCol = Instance.new("Frame")
cmdCol.Size = UDim2.new(0.28, -12, 0.72, 0)
cmdCol.Position = UDim2.new(0.27, 8, 0, 82)
cmdCol.BackgroundColor3 = Color3.fromRGB(16, 24, 36)
cmdCol.BorderSizePixel = 2
cmdCol.BorderColor3 = Color3.fromRGB(241, 196, 15)
cmdCol.ZIndex = 41
cmdCol.Parent = lobbyOverlay

local cmdHeader = Instance.new("TextLabel")
cmdHeader.Size = UDim2.new(1, 0, 0, 28)
cmdHeader.BackgroundColor3 = Color3.fromRGB(24, 36, 54)
cmdHeader.Font = Enum.Font.Arcade
cmdHeader.TextColor3 = Color3.fromRGB(255, 230, 110)
cmdHeader.TextSize = 13
cmdHeader.Text = "2. LÍDER HISTÓRICO"
cmdHeader.ZIndex = 42
cmdHeader.Parent = cmdCol

local cmdScroll = Instance.new("ScrollingFrame")
cmdScroll.Size = UDim2.new(1, -10, 1, -36)
cmdScroll.Position = UDim2.fromOffset(5, 32)
cmdScroll.BackgroundTransparency = 1
cmdScroll.ScrollBarThickness = 6
cmdScroll.CanvasSize = UDim2.fromOffset(0, #GameConfig.COMMANDER_ORDER * 56)
cmdScroll.ZIndex = 42
cmdScroll.Parent = cmdCol

local cmdButtons: { [string]: TextButton } = {}
for idx, cId in ipairs(GameConfig.COMMANDER_ORDER) do
	local cDef = GameConfig.COMMANDERS[cId]
	local cBtn = Instance.new("TextButton")
	cBtn.Size = UDim2.new(1, -10, 0, 50)
	cBtn.Position = UDim2.fromOffset(2, (idx - 1) * 54)
	cBtn.BackgroundColor3 = if cId == selectedLobbyCommander
		then Color3.fromRGB(190, 50, 45)
		else Color3.fromRGB(28, 38, 54)
	cBtn.BorderSizePixel = 1
	cBtn.BorderColor3 = Color3.fromRGB(241, 196, 15)
	cBtn.Font = Enum.Font.Arcade
	cBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	cBtn.TextSize = 11
	cBtn.TextWrapped = true
	cBtn.TextXAlignment = Enum.TextXAlignment.Left
	cBtn.Text = string.format(" %s %s (%s)\n ⭐ %s", cDef.icon, cDef.name, cDef.title, cDef.specialty)
	cBtn.ZIndex = 43
	cBtn.Parent = cmdScroll
	cmdButtons[cId] = cBtn

	cBtn.MouseButton1Click:Connect(function()
		selectedLobbyCommander = cId
		for id, b in pairs(cmdButtons) do
			b.BackgroundColor3 = if id == selectedLobbyCommander
				then Color3.fromRGB(190, 50, 45)
				else Color3.fromRGB(28, 38, 54)
		end
	end)
end

-- COLUMNA 3 DEL LOBBY: CATÁLOGO DE 28 MAPAS (TIERRA, SISTEMA SOLAR, ANDRÓMEDA, HISTORIA, EVOLUCIÓN)
local mapCol = Instance.new("Frame")
mapCol.Size = UDim2.new(0.45, -20, 0.72, 0)
mapCol.Position = UDim2.new(0.55, 4, 0, 82)
mapCol.BackgroundColor3 = Color3.fromRGB(16, 24, 36)
mapCol.BorderSizePixel = 2
mapCol.BorderColor3 = Color3.fromRGB(46, 204, 113)
mapCol.ZIndex = 41
mapCol.Parent = lobbyOverlay

local mapHeader = Instance.new("TextLabel")
mapHeader.Size = UDim2.new(1, 0, 0, 28)
mapHeader.BackgroundColor3 = Color3.fromRGB(24, 36, 54)
mapHeader.Font = Enum.Font.Arcade
mapHeader.TextColor3 = Color3.fromRGB(120, 255, 175)
mapHeader.TextSize = 13
mapHeader.Text = "3. SELECCIONA MAPA / PLANETA / GALAXIA (28 MAPAS)"
mapHeader.ZIndex = 42
mapHeader.Parent = mapCol

local mapScroll = Instance.new("ScrollingFrame")
mapScroll.Size = UDim2.new(1, -10, 1, -36)
mapScroll.Position = UDim2.fromOffset(5, 32)
mapScroll.BackgroundTransparency = 1
mapScroll.ScrollBarThickness = 8
mapScroll.CanvasSize = UDim2.fromOffset(0, #MapData.MAP_ORDER * 58)
mapScroll.ZIndex = 42
mapScroll.Parent = mapCol

local mapButtons: { [string]: TextButton } = {}
for idx, mapId in ipairs(MapData.MAP_ORDER) do
	local mData = MapData.MAPS[mapId]
	local mBtn = Instance.new("TextButton")
	mBtn.Size = UDim2.new(1, -12, 0, 52)
	mBtn.Position = UDim2.fromOffset(2, (idx - 1) * 56)
	mBtn.BackgroundColor3 = if mapId == selectedLobbyMap
		then Color3.fromRGB(25, 130, 85)
		else Color3.fromRGB(28, 38, 54)
	mBtn.BorderSizePixel = 1
	mBtn.BorderColor3 = mData.landColor
	mBtn.Font = Enum.Font.Arcade
	mBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	mBtn.TextSize = 11
	mBtn.TextWrapped = true
	mBtn.TextXAlignment = Enum.TextXAlignment.Left
	mBtn.Text = string.format(" [%s] %s | %s\n %s", mData.category, mData.title, mData.difficulty, mData.subtitle)
	mBtn.ZIndex = 43
	mBtn.Parent = mapScroll
	mapButtons[mapId] = mBtn

	mBtn.MouseButton1Click:Connect(function()
		selectedLobbyMap = mapId
		for id, b in pairs(mapButtons) do
			b.BackgroundColor3 = if id == selectedLobbyMap
				then Color3.fromRGB(25, 130, 85)
				else Color3.fromRGB(28, 38, 54)
		end
	end)
end

-- BOTÓN INFERIOR DEL LOBBY: LANZAR CAMPAÑA / PARTIDA MULTIJUGADOR
local launchMatchBtn = Instance.new("TextButton")
launchMatchBtn.Size = UDim2.new(0.55, 0, 0, 52)
launchMatchBtn.AnchorPoint = Vector2.new(0.5, 0)
launchMatchBtn.Position = UDim2.new(0.5, 0, 0.85, 0)
launchMatchBtn.BackgroundColor3 = Color3.fromRGB(210, 16, 52)
launchMatchBtn.BorderSizePixel = 3
launchMatchBtn.BorderColor3 = Color3.fromRGB(255, 235, 100)
launchMatchBtn.Font = Enum.Font.Arcade
launchMatchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
launchMatchBtn.TextSize = 18
launchMatchBtn.Text = "🚀 DESPLEGAR EN EL MAPA SELECCIONADO (JUGAR)"
launchMatchBtn.ZIndex = 45
launchMatchBtn.Parent = lobbyOverlay

launchMatchBtn.MouseButton1Click:Connect(function()
	lobbyOverlay.Visible = false
	selectedRegionId = nil
	PlayerCommandEvent:FireServer({
		action = "START_LOBBY_MATCH",
		mapId = selectedLobbyMap,
		gameMode = selectedLobbyMode,
		commanderId = selectedLobbyCommander,
	})
end)

openLobbyBtn.MouseButton1Click:Connect(function()
	lobbyOverlay.Visible = not lobbyOverlay.Visible
end)

-- ============================================================================
-- RENDERIZADOR DEL MAPA 2D PIXEL
-- ============================================================================
local function drawConnectionLine(x1: number, y1: number, x2: number, y2: number)
	local startPos = Vector2.new(x1, y1)
	local endPos = Vector2.new(x2, y2)
	local diff = endPos - startPos
	local steps = 9
	for i = 1, steps - 1 do
		local t = i / steps
		local pt = startPos + diff * t
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(6, 6)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(pt.X, pt.Y)
		dot.BackgroundColor3 = Color3.fromRGB(215, 230, 245)
		dot.BackgroundTransparency = 0.55
		dot.BorderSizePixel = 1
		dot.BorderColor3 = Color3.fromRGB(15, 30, 50)
		dot.Parent = routesLayer
	end
end

local function handleRegionClicked(regionId: string)
	if not latestServerState or not latestServerState.regions then
		return
	end
	local clickedReg = latestServerState.regions[regionId]
	if not clickedReg then
		return
	end

	local playerFaction = latestServerState.playerFaction or "PANAMA"

	if activeToolId ~= "Conquer" then
		PlayerCommandEvent:FireServer({
			action = "GOD_TOOL",
			toolId = activeToolId,
			targetId = regionId,
		})
		return
	end

	if not selectedRegionId then
		if clickedReg.owner == playerFaction then
			selectedRegionId = regionId
			SubtitleLabel.Text = string.format(
				"✅ %s seleccionada (%d tropas). Haz clic en frontera para atacar o construye/despliega tropas.",
				clickedReg.name,
				clickedReg.troops
			)
		else
			local fDef = GameConfig.FACTIONS[clickedReg.owner]
			local cmdName = if fDef then fDef.commanderName else clickedReg.owner
			SubtitleLabel.Text = string.format(
				"🔍 %s controlada por %s (%d tropas). Selecciona un territorio tuyo para invadirla.",
				clickedReg.name,
				cmdName,
				clickedReg.troops
			)
		end
	else
		if selectedRegionId == regionId then
			selectedRegionId = nil
			SubtitleLabel.Text = "Selección cancelada."
		else
			PlayerCommandEvent:FireServer({
				action = "MARCH",
				fromId = selectedRegionId,
				toId = regionId,
				ratio = sendTroopRatio,
			})
			if clickedReg.owner == playerFaction then
				selectedRegionId = regionId
			end
		end
	end

	for id, widget in pairs(regionWidgets) do
		widget.selectionStroke.Thickness = if id == selectedRegionId then 4 else 1
		widget.selectionStroke.Color = if id == selectedRegionId
			then Color3.fromRGB(255, 255, 100)
			else Color3.fromRGB(15, 20, 28)
	end
end

local function buildMapCanvas(mapId: string)
	routesLayer:ClearAllChildren()
	mapNodesLayer:ClearAllChildren()
	regionWidgets = {}

	local mapTemplate = MapData.MAPS[mapId] or MapData.MAPS.PANAMA
	oceanCanvas.BackgroundColor3 = mapTemplate.oceanColor
	TitleLabel.Text = string.format("🇵🇦 %s (%s)", mapTemplate.title, mapTemplate.difficulty)

	local nodeLookup: { [string]: any } = {}
	for _, node in ipairs(mapTemplate.regions) do
		nodeLookup[node.id] = node
	end

	local drawnPairs: { [string]: boolean } = {}
	for _, node in ipairs(mapTemplate.regions) do
		for _, neighborId in ipairs(node.neighbors) do
			local pairKey = if node.id < neighborId then node.id .. "_" .. neighborId else neighborId .. "_" .. node.id
			if not drawnPairs[pairKey] and nodeLookup[neighborId] then
				drawnPairs[pairKey] = true
				drawConnectionLine(node.x, node.y, nodeLookup[neighborId].x, nodeLookup[neighborId].y)
			end
		end
	end

	for _, node in ipairs(mapTemplate.regions) do
		local faction = GameConfig.FACTIONS[node.initialOwner] or GameConfig.FACTIONS.NEUTRAL

		local rootBtn = Instance.new("TextButton")
		rootBtn.Name = "Region_" .. node.id
		rootBtn.Size = UDim2.fromOffset(node.width, node.height)
		rootBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		rootBtn.Position = UDim2.fromScale(node.x, node.y)
		rootBtn.BackgroundTransparency = 1
		rootBtn.Text = ""
		rootBtn.ZIndex = 6
		rootBtn.Parent = mapNodesLayer

		local selectionStroke = Instance.new("UIStroke")
		selectionStroke.Color = Color3.fromRGB(15, 20, 28)
		selectionStroke.Thickness = 1
		selectionStroke.Parent = rootBtn

		local pixelBlocks: { Frame } = {}
		local shape = node.pixelShape
		for row = 1, 5 do
			for col = 1, 5 do
				if shape[row] and shape[row][col] == 1 then
					local px = Instance.new("Frame")
					px.Size = UDim2.new(0.2, 1, 0.2, 1)
					px.Position = UDim2.fromScale((col - 1) * 0.2, (row - 1) * 0.2)
					px.BackgroundColor3 = faction.primaryColor
					px.BorderSizePixel = 1
					px.BorderColor3 = Color3.fromRGB(20, 25, 32)
					px.ZIndex = 6
					px.Parent = rootBtn
					table.insert(pixelBlocks, px)
				end
			end
		end

		local cbHolder = Instance.new("Frame")
		cbHolder.Size = UDim2.fromOffset(26, 26)
		cbHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		cbHolder.Position = UDim2.fromScale(0.28, 0.40)
		cbHolder.BackgroundTransparency = 1
		cbHolder.ZIndex = 8
		cbHolder.Parent = rootBtn

		CountryballUI.CreateCountryball(cbHolder, node.initialOwner, 26)

		local buildingBadge = Instance.new("TextLabel")
		buildingBadge.Size = UDim2.fromOffset(22, 22)
		buildingBadge.AnchorPoint = Vector2.new(0.5, 0.5)
		buildingBadge.Position = UDim2.fromScale(0.76, 0.30)
		buildingBadge.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
		buildingBadge.BackgroundTransparency = 0.15
		buildingBadge.BorderSizePixel = 1
		buildingBadge.BorderColor3 = Color3.fromRGB(241, 196, 15)
		buildingBadge.Font = Enum.Font.Arcade
		buildingBadge.TextSize = 13
		buildingBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		buildingBadge.Text = if node.initialBuilding and GameConfig.BUILDINGS[node.initialBuilding]
			then GameConfig.BUILDINGS[node.initialBuilding].icon
			else ""
		buildingBadge.Visible = (node.initialBuilding ~= nil)
		buildingBadge.ZIndex = 9
		buildingBadge.Parent = rootBtn

		local unitBadge = Instance.new("TextLabel")
		unitBadge.Size = UDim2.fromOffset(20, 20)
		unitBadge.AnchorPoint = Vector2.new(0.5, 0.5)
		unitBadge.Position = UDim2.fromScale(0.76, 0.56)
		unitBadge.BackgroundColor3 = Color3.fromRGB(25, 35, 50)
		unitBadge.BackgroundTransparency = 0.2
		unitBadge.BorderSizePixel = 1
		unitBadge.BorderColor3 = Color3.fromRGB(0, 230, 210)
		unitBadge.Font = Enum.Font.Arcade
		unitBadge.TextSize = 12
		unitBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		unitBadge.Text = "🦖"
		unitBadge.Visible = false
		unitBadge.ZIndex = 9
		unitBadge.Parent = rootBtn

		local crisisBadge = Instance.new("TextLabel")
		crisisBadge.Size = UDim2.fromOffset(24, 24)
		crisisBadge.AnchorPoint = Vector2.new(0.5, 0.5)
		crisisBadge.Position = UDim2.fromScale(0.5, 0.08)
		crisisBadge.BackgroundColor3 = Color3.fromRGB(190, 20, 40)
		crisisBadge.BorderSizePixel = 1
		crisisBadge.BorderColor3 = Color3.fromRGB(255, 235, 90)
		crisisBadge.Font = Enum.Font.Arcade
		crisisBadge.TextSize = 14
		crisisBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		crisisBadge.Text = "☣️"
		crisisBadge.Visible = false
		crisisBadge.ZIndex = 11
		crisisBadge.Parent = rootBtn

		local troopLabel = Instance.new("TextLabel")
		troopLabel.Size = UDim2.new(0.96, 0, 0, 18)
		troopLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		troopLabel.Position = UDim2.fromScale(0.5, 0.82)
		troopLabel.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
		troopLabel.BackgroundTransparency = 0.15
		troopLabel.BorderSizePixel = 1
		troopLabel.BorderColor3 = Color3.fromRGB(200, 210, 220)
		troopLabel.Font = Enum.Font.Arcade
		troopLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		troopLabel.TextSize = 11
		troopLabel.Text = "⚔️" .. tostring(node.initialTroops)
		troopLabel.ZIndex = 9
		troopLabel.Parent = rootBtn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1.4, 0, 0, 14)
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.Position = UDim2.new(0.5, 0, 1, 2)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.Code
		nameLabel.TextColor3 = Color3.fromRGB(245, 248, 255)
		nameLabel.TextStrokeTransparency = 0.2
		nameLabel.TextSize = 11
		nameLabel.Text = node.name
		nameLabel.ZIndex = 10
		nameLabel.Parent = rootBtn

		regionWidgets[node.id] = {
			root = rootBtn,
			pixelBlocks = pixelBlocks,
			troopLabel = troopLabel,
			nameLabel = nameLabel,
			buildingBadge = buildingBadge,
			unitBadge = unitBadge,
			crisisBadge = crisisBadge,
			countryballContainer = cbHolder,
			currentOwner = node.initialOwner,
			selectionStroke = selectionStroke,
		}

		rootBtn.MouseButton1Click:Connect(function()
			handleRegionClicked(node.id)
		end)
	end
end

-- ============================================================================
-- CÁMARA ORBITAL PARA VISTA DEL GLOBO TERRÁQUEO / PLANETARIO 3D
-- ============================================================================
RunService.RenderStepped:Connect(function(dt: number)
	if is3DGlobeView then
		globeOrbitAngle += dt * 0.35
		local cam = workspace.CurrentCamera
		if cam then
			local center = Vector3.new(0, 34, 0)
			local dist = 68
			local camPos = center + Vector3.new(math.sin(globeOrbitAngle) * dist, 18, math.cos(globeOrbitAngle) * dist)
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = CFrame.lookAt(camPos, center)
		end
	end
end)

-- ============================================================================
-- EFECTOS VISUALES 2D PIXEL
-- ============================================================================
CombatFxEvent.OnClientEvent:Connect(function(fx: { [string]: any })
	if not latestServerState or not latestServerState.regions then
		return
	end

	local toReg = if fx.toId then latestServerState.regions[fx.toId] else nil
	local fromReg = if fx.fromId then latestServerState.regions[fx.fromId] else nil

	if
		(fx.type == "ATTACK" or fx.type == "REINFORCE" or fx.type == "AI_REINFORCE" or fx.type == "AI_TURRET")
		and fromReg
		and toReg
	then
		local token = Instance.new("TextLabel")
		token.Size = UDim2.fromOffset(44, 20)
		token.AnchorPoint = Vector2.new(0.5, 0.5)
		token.Position = UDim2.fromScale(fromReg.x, fromReg.y)
		token.BackgroundColor3 = if fx.type == "AI_TURRET"
			then Color3.fromRGB(231, 76, 60)
			elseif fx.type == "ATTACK" then Color3.fromRGB(210, 16, 52)
			else Color3.fromRGB(46, 204, 113)
		token.BorderSizePixel = 1
		token.BorderColor3 = Color3.fromRGB(255, 255, 255)
		token.Font = Enum.Font.Arcade
		token.TextColor3 = Color3.fromRGB(255, 255, 255)
		token.TextSize = 11
		local icon = if fx.type == "AI_TURRET"
			then "⚡-"
			elseif fx.type == "AI_REINFORCE" then "🤖+"
			elseif fx.type == "ATTACK" then "⚔️"
			else "🚚+"
		token.Text = icon .. tostring(fx.amount or "")
		token.ZIndex = 15
		token.Parent = fxLayer

		local tween = TweenService:Create(
			token,
			TweenInfo.new(0.55, Enum.EasingStyle.Linear),
			{ Position = UDim2.fromScale(toReg.x, toReg.y) }
		)
		tween:Play()
		tween.Completed:Connect(function()
			token:Destroy()
		end)
	elseif (fx.type == "GOD_FINGER" or fx.type == "METEOR" or fx.type == "SHIELD") and toReg then
		local burst = Instance.new("TextLabel")
		burst.Size = UDim2.fromOffset(70, 36)
		burst.AnchorPoint = Vector2.new(0.5, 0.5)
		burst.Position = UDim2.fromScale(toReg.x, toReg.y - 0.06)
		burst.BackgroundTransparency = 1
		burst.Font = Enum.Font.Arcade
		burst.TextSize = 24
		burst.TextColor3 = Color3.fromRGB(255, 235, 90)
		burst.Text = if fx.type == "GOD_FINGER"
			then "👆⚡"
			elseif fx.type == "METEOR" then "☄️💥"
			else "✨🛡️"
		burst.ZIndex = 16
		burst.Parent = fxLayer

		local tween = TweenService:Create(
			burst,
			TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(toReg.x, toReg.y), TextTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Connect(function()
			burst:Destroy()
		end)
	end
end)

-- ============================================================================
-- SINCRONIZACIÓN DE ESTADO CON EL SERVIDOR
-- ============================================================================
buildMapCanvas(currentMapId)

StateSyncEvent.OnClientEvent:Connect(function(state: { [string]: any })
	latestServerState = state
	if state.mapId and state.mapId ~= currentMapId then
		currentMapId = state.mapId
		buildMapCanvas(currentMapId)
	end

	if state.activeCrisis then
		crisisBanner.Text = tostring(state.activeCrisis)
		crisisBanner.Visible = true
	else
		crisisBanner.Visible = false
	end

	local playerFaction = state.playerFaction or "PANAMA"
	local playerEcon = if state.economies then state.economies[playerFaction] else nil
	local totalRegions = 0

	if state.regions then
		for id, regData in pairs(state.regions) do
			totalRegions += 1
			local widget = regionWidgets[id]
			if widget then
				local faction = GameConfig.FACTIONS[regData.owner] or GameConfig.FACTIONS.NEUTRAL
				for _, px in ipairs(widget.pixelBlocks) do
					px.BackgroundColor3 = faction.primaryColor
				end

				local shieldTag = if regData.shieldUntil and regData.shieldUntil > (state.serverTime or 0)
					then "✨"
					else ""
				widget.troopLabel.Text =
					string.format("%s%s %d", faction.flagEmoji, shieldTag, math.floor(regData.troops))

				if regData.building and GameConfig.BUILDINGS[regData.building] then
					widget.buildingBadge.Text = GameConfig.BUILDINGS[regData.building].icon
					widget.buildingBadge.Visible = true
				else
					widget.buildingBadge.Visible = false
				end

				if regData.unitType and GameConfig.MILITARY_UNITS[regData.unitType] then
					widget.unitBadge.Text = GameConfig.MILITARY_UNITS[regData.unitType].icon
					widget.unitBadge.Visible = true
				else
					widget.unitBadge.Visible = false
				end

				widget.crisisBadge.Visible = (regData.crisisId ~= nil)

				if widget.currentOwner ~= regData.owner then
					widget.currentOwner = regData.owner
					widget.countryballContainer:ClearAllChildren()
					CountryballUI.CreateCountryball(widget.countryballContainer, regData.owner, 26)
				end
			end
		end
	end

	if playerEcon and totalRegions > 0 then
		local domPct = math.floor((playerEcon.regionCount / totalRegions) * 100)
		local eraDef = GameConfig.EVOLUTION_STAGES[playerEcon.evolutionLevel] or GameConfig.EVOLUTION_STAGES[1]
		local cmdDef = GameConfig.COMMANDERS[playerEcon.commanderId] or GameConfig.COMMANDERS.TORRIJOS

		statsLabel.Text = string.format(
			"💰%d (+%d) | 🛢️%d (+%d) | 🧬%d (+%d/s)\n%s %s | %s %s | 🌍%d%%",
			math.floor(playerEcon.gold),
			math.floor(playerEcon.goldPerSec),
			math.floor(playerEcon.oil),
			math.floor(playerEcon.oilPerSec),
			math.floor(playerEcon.science),
			math.floor(playerEcon.sciencePerSec),
			cmdDef.icon,
			cmdDef.name,
			eraDef.icon,
			eraDef.name,
			domPct
		)

		local nextStage = GameConfig.EVOLUTION_STAGES[playerEcon.evolutionLevel + 1]
		if nextStage then
			local mult = if playerEcon.commanderId == "DARWIN" then 0.70 else 1.0
			evolveBtn.Text = string.format(
				"🧬 EVOLUCIONAR A:\n%s %s\n(🧬%d 💰%d)",
				nextStage.icon,
				nextStage.name,
				math.floor(nextStage.costScience * mult),
				math.floor(nextStage.costGold * mult)
			)
		else
			evolveBtn.Text = "🌌 ERA 7 MÁXIMA\nANDRÓMEDA"
		end

		local modeDef = GameConfig.DEFENSE_AI_MODES[playerEcon.aiDefenseMode] or GameConfig.DEFENSE_AI_MODES.SMART
		aiDefenseBtn.Text = "🤖 " .. modeDef.name
	end

	if state.logs then
		logTextLabel.Text = table.concat(state.logs, "\n")
	end
end)
