--!strict
-- ConquestClient.client.lua
-- Interfaz 2D Pixel Art completa para "Recuperar Panamá y el Mundo"
-- Combina:
-- 1) Mapa 2D Pixel de provincias y líneas de conexión (Wargame [Map Conquest] / OpenFront)
-- 2) Countryballs pixelados en cada región con indicadores de tropas, escudos y edificios
-- 3) Barra de Herramientas del Dedo Divino (WorldBox God Simulator)
-- 4) Panel de Construcción de Edificios del Jugador + Selector de Modo de IA de Defensa

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- Ocultar HUD 3D innecesario para priorizar la experiencia 2D Pixel
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Estado local del cliente
local currentMapId: string = "PANAMA"
local selectedRegionId: string? = nil
local activeToolId: string = "Conquer" -- "Conquer" | "DivineFinger" | "Meteor" | "DivineShield"
local sendTroopRatio: number = 0.50
local latestServerState: any = nil

-- Referencias a nodos visuales del mapa
local regionWidgets: {
	[string]: {
		root: TextButton,
		pixelBlocks: { Frame },
		troopLabel: TextLabel,
		nameLabel: TextLabel,
		buildingBadge: TextLabel,
		countryballContainer: Frame,
		currentOwner: string,
		selectionStroke: UIStroke,
	},
} =
	{}

-- Crear ScreenGui principal 2D Pixel
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PixelConquest2DGui"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Fondo Oceánico 2D con cuadrícula Pixel Art retro
local oceanCanvas = Instance.new("Frame")
oceanCanvas.Name = "OceanCanvas"
oceanCanvas.Size = UDim2.fromScale(1, 1)
oceanCanvas.BackgroundColor3 = Color3.fromRGB(18, 78, 137)
oceanCanvas.BorderSizePixel = 0
oceanCanvas.Parent = screenGui

-- Textura de cuadrícula 2D Pixel sutil en el océano
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

-- Capa de líneas de ruta y fronteras entre provincias/países
local routesLayer = Instance.new("Frame")
routesLayer.Name = "RoutesLayer"
routesLayer.Size = UDim2.fromScale(1, 1)
routesLayer.BackgroundTransparency = 1
routesLayer.ZIndex = 2
routesLayer.Parent = oceanCanvas

-- Capa de Provincias / Países 2D Pixel
local mapNodesLayer = Instance.new("Frame")
mapNodesLayer.Name = "MapNodesLayer"
mapNodesLayer.Size = UDim2.fromScale(1, 1)
mapNodesLayer.BackgroundTransparency = 1
mapNodesLayer.ZIndex = 5
mapNodesLayer.Parent = oceanCanvas

-- Capa de Efectos Visuales (Tropas marchando, Dedo de Dios, Meteoros, Fuego de Búnkeres IA)
local fxLayer = Instance.new("Frame")
fxLayer.Name = "FxLayer"
fxLayer.Size = UDim2.fromScale(1, 1)
fxLayer.BackgroundTransparency = 1
fxLayer.ZIndex = 12
fxLayer.Parent = oceanCanvas

-- ============================================================================
-- BARRA SUPERIOR (HUD ECONÓMICO, CAMBIO DE MAPA Y CONTROL DE IA DE DEFENSA)
-- ============================================================================
local topBar = Instance.new("Frame")
topBar.Name = "TopHudBar"
topBar.Size = UDim2.new(1, -24, 0, 66)
topBar.Position = UDim2.fromOffset(12, 10)
topBar.BackgroundColor3 = Color3.fromRGB(20, 26, 36)
topBar.BorderSizePixel = 2
topBar.BorderColor3 = Color3.fromRGB(241, 196, 15)
topBar.ZIndex = 20
topBar.Parent = screenGui

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(0.28, 0, 0, 30)
TitleLabel.Position = UDim2.fromOffset(12, 4)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.Arcade
TitleLabel.Text = "🇵🇦 RECUPERAR PANAMÁ Y EL MUNDO"
TitleLabel.TextColor3 = Color3.fromRGB(255, 235, 130)
TitleLabel.TextSize = 16
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = topBar

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.Size = UDim2.new(0.32, 0, 0, 24)
SubtitleLabel.Position = UDim2.fromOffset(12, 34)
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.Font = Enum.Font.Code
SubtitleLabel.Text = "Selecciona una provincia panameña para construir o expandirte"
SubtitleLabel.TextColor3 = Color3.fromRGB(190, 210, 230)
SubtitleLabel.TextSize = 13
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubtitleLabel.Parent = topBar

-- Indicadores de Recursos (Oro, Petróleo, Tropas, Dominio del Mapa)
local statsLabel = Instance.new("TextLabel")
statsLabel.Name = "StatsLabel"
statsLabel.Size = UDim2.new(0.36, 0, 1, -12)
statsLabel.Position = UDim2.new(0.31, 0, 0, 6)
statsLabel.BackgroundColor3 = Color3.fromRGB(12, 17, 24)
statsLabel.BorderSizePixel = 1
statsLabel.BorderColor3 = Color3.fromRGB(80, 110, 145)
statsLabel.Font = Enum.Font.Arcade
statsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statsLabel.TextSize = 14
statsLabel.Text = "💰 Oro: 320 (+25/s) | 🛢️ Petróleo: 60 (+5/s)\n⚔️ Tropas: 300/500 | 🌍 Mapa: 14%"
statsLabel.Parent = topBar

-- Botón Selector de Modo de IA de Defensa del País
local aiDefenseBtn = Instance.new("TextButton")
aiDefenseBtn.Name = "AiDefenseButton"
aiDefenseBtn.Size = UDim2.new(0.16, -8, 1, -14)
aiDefenseBtn.Position = UDim2.new(0.68, 4, 0, 7)
aiDefenseBtn.BackgroundColor3 = Color3.fromRGB(22, 115, 75)
aiDefenseBtn.BorderSizePixel = 2
aiDefenseBtn.BorderColor3 = Color3.fromRGB(46, 204, 113)
aiDefenseBtn.Font = Enum.Font.Arcade
aiDefenseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
aiDefenseBtn.TextSize = 12
aiDefenseBtn.TextWrapped = true
aiDefenseBtn.Text = "🤖 IA Defensa:\nINTELIGENTE"
aiDefenseBtn.Parent = topBar

local aiModeCycle = { "SMART", "FORTIFY", "MANUAL" }
local currentAiIndex = 1

aiDefenseBtn.MouseButton1Click:Connect(function()
	currentAiIndex = (currentAiIndex % #aiModeCycle) + 1
	local nextMode = aiModeCycle[currentAiIndex]
	PlayerCommandEvent:FireServer({
		action = "SET_AI_DEFENSE",
		mode = nextMode,
	})
end)

-- Botón para alternar entre Campaña 1 (Mapa de Panamá) y Campaña 2 (Mapa Mundial)
local switchMapBtn = Instance.new("TextButton")
switchMapBtn.Name = "SwitchMapButton"
switchMapBtn.Size = UDim2.new(0.15, -12, 1, -14)
switchMapBtn.Position = UDim2.new(0.85, 4, 0, 7)
switchMapBtn.BackgroundColor3 = Color3.fromRGB(0, 103, 198)
switchMapBtn.BorderSizePixel = 2
switchMapBtn.BorderColor3 = Color3.fromRGB(255, 255, 255)
switchMapBtn.Font = Enum.Font.Arcade
switchMapBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
switchMapBtn.TextSize = 12
switchMapBtn.TextWrapped = true
switchMapBtn.Text = "🌍 IR A MAPA:\nEL MUNDO"
switchMapBtn.Parent = topBar

switchMapBtn.MouseButton1Click:Connect(function()
	local targetMap = if currentMapId == "PANAMA" then "WORLD" else "PANAMA"
	selectedRegionId = nil
	PlayerCommandEvent:FireServer({
		action = "SWITCH_MAP",
		mapId = targetMap,
	})
end)

-- ============================================================================
-- PANEL IZQUIERDO: REGISTRO DE BATALLA E IA DEFENSIVA + RATIO DE ENVÍO
-- ============================================================================
local leftPanel = Instance.new("Frame")
leftPanel.Name = "LeftTacticalPanel"
leftPanel.Size = UDim2.fromOffset(290, 235)
leftPanel.Position = UDim2.new(0, 12, 1, -335)
leftPanel.BackgroundColor3 = Color3.fromRGB(16, 22, 30)
leftPanel.BackgroundTransparency = 0.1
leftPanel.BorderSizePixel = 2
leftPanel.BorderColor3 = Color3.fromRGB(70, 95, 130)
leftPanel.ZIndex = 20
leftPanel.Parent = screenGui

local ratioTitle = Instance.new("TextLabel")
ratioTitle.Size = UDim2.new(1, -12, 0, 22)
ratioTitle.Position = UDim2.fromOffset(6, 4)
ratioTitle.BackgroundTransparency = 1
ratioTitle.Font = Enum.Font.Arcade
ratioTitle.TextColor3 = Color3.fromRGB(241, 196, 15)
ratioTitle.TextSize = 12
ratioTitle.Text = "PORCENTAJE DE TROPAS AL MARCHAR:"
ratioTitle.Parent = leftPanel

local ratioButtonsFrame = Instance.new("Frame")
ratioButtonsFrame.Size = UDim2.new(1, -12, 0, 28)
ratioButtonsFrame.Position = UDim2.fromOffset(6, 28)
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
	rBtn.TextSize = 12
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
logHeader.Size = UDim2.new(1, -12, 0, 20)
logHeader.Position = UDim2.fromOffset(6, 62)
logHeader.BackgroundTransparency = 1
logHeader.Font = Enum.Font.Arcade
logHeader.TextColor3 = Color3.fromRGB(130, 200, 255)
logHeader.TextSize = 12
logHeader.TextXAlignment = Enum.TextXAlignment.Left
logHeader.Text = "📡 BITÁCORA TÁCTICA & IA DEFENSA:"
logHeader.Parent = leftPanel

local logTextLabel = Instance.new("TextLabel")
logTextLabel.Size = UDim2.new(1, -12, 1, -88)
logTextLabel.Position = UDim2.fromOffset(6, 84)
logTextLabel.BackgroundTransparency = 1
logTextLabel.Font = Enum.Font.Code
logTextLabel.TextColor3 = Color3.fromRGB(215, 225, 235)
logTextLabel.TextSize = 12
logTextLabel.TextXAlignment = Enum.TextXAlignment.Left
logTextLabel.TextYAlignment = Enum.TextYAlignment.Top
logTextLabel.TextWrapped = true
logTextLabel.Text = "Iniciando radar estratégico..."
logTextLabel.Parent = leftPanel

-- ============================================================================
-- BARRA INFERIOR: HERRAMIENTAS DEL DEDO DIVINO (WORLDBOX) + CONSTRUCCIÓN
-- ============================================================================
local bottomDock = Instance.new("Frame")
bottomDock.Name = "BottomDock"
bottomDock.Size = UDim2.new(1, -24, 0, 82)
bottomDock.Position = UDim2.new(0, 12, 1, -90)
bottomDock.BackgroundColor3 = Color3.fromRGB(20, 26, 36)
bottomDock.BorderSizePixel = 2
bottomDock.BorderColor3 = Color3.fromRGB(241, 196, 15)
bottomDock.ZIndex = 20
bottomDock.Parent = screenGui

-- Sección Izquierda de la barra inferior: Herramientas del Dedo Divino (WorldBox)
local godToolsContainer = Instance.new("Frame")
godToolsContainer.Size = UDim2.new(0.38, -10, 1, -12)
godToolsContainer.Position = UDim2.fromOffset(8, 6)
godToolsContainer.BackgroundTransparency = 1
godToolsContainer.Parent = bottomDock

local toolOrder = { "Conquer", "DivineFinger", "DivineShield", "Meteor" }
local toolButtons: { [string]: TextButton } = {}

for idx, toolId in ipairs(toolOrder) do
	local tDef = GameConfig.GOD_TOOLS[toolId]
	local btn = Instance.new("TextButton")
	btn.Name = "Tool_" .. toolId
	btn.Size = UDim2.new(0.25, -6, 1, 0)
	btn.Position = UDim2.new((idx - 1) * 0.25, 2, 0, 0)
	btn.BackgroundColor3 = if toolId == activeToolId then Color3.fromRGB(210, 16, 52) else Color3.fromRGB(34, 46, 64)
	btn.BorderSizePixel = 2
	btn.BorderColor3 = Color3.fromRGB(240, 200, 60)
	btn.Font = Enum.Font.Arcade
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 11
	btn.TextWrapped = true
	local costText = if tDef.costGold > 0
		then string.format("\n💰%d 🛢️%d", tDef.costGold, tDef.costOil)
		else "\n[GRATIS]"
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

-- Sección Derecha de la barra inferior: Construcción de Edificios por el Jugador
local buildingsContainer = Instance.new("Frame")
buildingsContainer.Size = UDim2.new(0.62, -12, 1, -12)
buildingsContainer.Position = UDim2.new(0.38, 4, 0, 6)
buildingsContainer.BackgroundTransparency = 1
buildingsContainer.Parent = bottomDock

for idx, bId in ipairs(GameConfig.BUILDING_ORDER) do
	local bDef = GameConfig.BUILDINGS[bId]
	local bBtn = Instance.new("TextButton")
	bBtn.Name = "Build_" .. bId
	bBtn.Size = UDim2.new(1 / #GameConfig.BUILDING_ORDER, -6, 1, 0)
	bBtn.Position = UDim2.new((idx - 1) / #GameConfig.BUILDING_ORDER, 3, 0, 0)
	bBtn.BackgroundColor3 = Color3.fromRGB(28, 38, 52)
	bBtn.BorderSizePixel = 2
	bBtn.BorderColor3 = bDef.color
	bBtn.Font = Enum.Font.Arcade
	bBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	bBtn.TextSize = 11
	bBtn.TextWrapped = true
	bBtn.Text = string.format("%s %s\n💰%d 🛢️%d", bDef.icon, bDef.name, bDef.costGold, bDef.costOil)
	bBtn.Parent = buildingsContainer

	bBtn.MouseButton1Click:Connect(function()
		if not selectedRegionId then
			SubtitleLabel.Text = "⚠️ Primero selecciona una provincia panameña tuya para construir " .. bDef.name
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
-- RENDERIZADOR DEL MAPA 2D PIXEL Y CONEXIONES ENTRE NODOS
-- ============================================================================
local function drawConnectionLine(x1: number, y1: number, x2: number, y2: number)
	local startPos = Vector2.new(x1, y1)
	local endPos = Vector2.new(x2, y2)
	local diff = endPos - startPos
	-- Crear línea punteada pixel art entre las dos regiones
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

	-- Si el jugador tiene activa una herramienta del Dedo Divino (WorldBox), aplicarla sobre la provincia tocada
	if activeToolId ~= "Conquer" then
		PlayerCommandEvent:FireServer({
			action = "GOD_TOOL",
			toolId = activeToolId,
			targetId = regionId,
		})
		return
	end

	-- Modo Mando Militar (Conquista y Expansión Territorial)
	if not selectedRegionId then
		if clickedReg.owner == playerFaction then
			selectedRegionId = regionId
			SubtitleLabel.Text = string.format(
				"✅ %s seleccionada (%d tropas). Haz clic en una provincia vecina para atacar/reforzar o construye abajo.",
				clickedReg.name,
				clickedReg.troops
			)
		else
			SubtitleLabel.Text = string.format(
				"🔍 %s pertenece a %s (%d tropas). Selecciona primero una provincia tuya para invadirla.",
				clickedReg.name,
				clickedReg.owner,
				clickedReg.troops
			)
		end
	else
		if selectedRegionId == regionId then
			-- Deseleccionar
			selectedRegionId = nil
			SubtitleLabel.Text = "Selección cancelada."
		else
			-- Enviar orden de marcha / conquista desde selectedRegionId hacia regionId
			PlayerCommandEvent:FireServer({
				action = "MARCH",
				fromId = selectedRegionId,
				toId = regionId,
				ratio = sendTroopRatio,
			})
			-- Si hizo clic en otra provincia propia, actualizar selección a la nueva
			if clickedReg.owner == playerFaction then
				selectedRegionId = regionId
			end
		end
	end

	-- Actualizar borde de selección visual
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
	TitleLabel.Text = "🇵🇦 " .. mapTemplate.title
	switchMapBtn.Text = if mapId == "PANAMA" then "🌍 IR A MAPA:\nEL MUNDO" else "🇵🇦 IR A MAPA:\nPANAMÁ"

	local nodeLookup: { [string]: any } = {}
	for _, node in ipairs(mapTemplate.regions) do
		nodeLookup[node.id] = node
	end

	-- Dibujar conexiones estratégicas entre territorios vecinos
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

	-- Dibujar cada territorio en 2D Pixel Art con bloques 5x5 + Countryball
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

		-- Construir la silueta 2D Pixel Art 5x5 del territorio
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

		-- Contenedor del Countryball en el centro de la provincia
		local cbHolder = Instance.new("Frame")
		cbHolder.Size = UDim2.fromOffset(26, 26)
		cbHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		cbHolder.Position = UDim2.fromScale(0.32, 0.42)
		cbHolder.BackgroundTransparency = 1
		cbHolder.ZIndex = 8
		cbHolder.Parent = rootBtn

		CountryballUI.CreateCountryball(cbHolder, node.initialOwner, 26)

		-- Insignia de Edificio construido
		local buildingBadge = Instance.new("TextLabel")
		buildingBadge.Size = UDim2.fromOffset(24, 24)
		buildingBadge.AnchorPoint = Vector2.new(0.5, 0.5)
		buildingBadge.Position = UDim2.fromScale(0.75, 0.35)
		buildingBadge.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
		buildingBadge.BackgroundTransparency = 0.2
		buildingBadge.BorderSizePixel = 1
		buildingBadge.BorderColor3 = Color3.fromRGB(241, 196, 15)
		buildingBadge.Font = Enum.Font.Arcade
		buildingBadge.TextSize = 14
		buildingBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		buildingBadge.Text = if node.initialBuilding and GameConfig.BUILDINGS[node.initialBuilding]
			then GameConfig.BUILDINGS[node.initialBuilding].icon
			else ""
		buildingBadge.Visible = (node.initialBuilding ~= nil)
		buildingBadge.ZIndex = 9
		buildingBadge.Parent = rootBtn

		-- Contador de Tropas Pixel
		local troopLabel = Instance.new("TextLabel")
		troopLabel.Size = UDim2.new(0.95, 0, 0, 18)
		troopLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		troopLabel.Position = UDim2.fromScale(0.5, 0.80)
		troopLabel.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
		troopLabel.BackgroundTransparency = 0.15
		troopLabel.BorderSizePixel = 1
		troopLabel.BorderColor3 = Color3.fromRGB(200, 210, 220)
		troopLabel.Font = Enum.Font.Arcade
		troopLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		troopLabel.TextSize = 12
		troopLabel.Text = "⚔️" .. tostring(node.initialTroops)
		troopLabel.ZIndex = 9
		troopLabel.Parent = rootBtn

		-- Nombre de la Provincia / País
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1.35, 0, 0, 15)
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
-- EFECTOS VISUALES 2D PIXEL (TROPAS MARCHANDO, BÚNKER IA, DEDO DE DIOS, METEORO)
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
		-- Crear un escuadrón Countryball o proyectil 2D Pixel marchando entre las dos provincias
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
			then "💥-"
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
		statsLabel.Text = string.format(
			"💰 Oro: %d (+%d/s) | 🛢️ Petróleo: %d (+%d/s)\n⚔️ Tropas: %d/%d | 🌍 Dominio Panamá: %d%% (Meta: 65%%)",
			math.floor(playerEcon.gold),
			math.floor(playerEcon.goldPerSec),
			math.floor(playerEcon.oil),
			math.floor(playerEcon.oilPerSec),
			math.floor(playerEcon.totalTroops),
			math.floor(playerEcon.popCap),
			domPct
		)

		local modeDef = GameConfig.DEFENSE_AI_MODES[playerEcon.aiDefenseMode] or GameConfig.DEFENSE_AI_MODES.SMART
		aiDefenseBtn.Text = "🤖 " .. modeDef.name
	end

	if state.logs then
		logTextLabel.Text = table.concat(state.logs, "\n")
	end
end)
