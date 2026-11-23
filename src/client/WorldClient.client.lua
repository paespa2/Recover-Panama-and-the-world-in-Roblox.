--!nonstrict
-- WorldClient.client.lua
-- Cliente de conquista territorial estilo RoWorld / OpenFront con mapa mundial real por celdas (240x100).
-- Renderizado mediante EditableImage de ultra-alto rendimiento (60 FPS).
-- Diferenciación visual destacada para el jugador humano (corona dorada, aura neón, tag [TÚ]).
-- HUD completo: tropas, oro, slider de ratio, construcción (Ciudad, Puerto, Puesto, Silo), nuke, IA Defensa.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local AssetService = game:GetService("AssetService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local folder = ReplicatedStorage:WaitForChild("WorldRemotes", 15)
if not folder then
	warn("WorldRemotes no encontrado")
	return
end

local WorldInit = folder:WaitForChild("WorldInit")
local WorldDiff = folder:WaitForChild("WorldDiff")
local WorldStats = folder:WaitForChild("WorldStats")
local WorldMe = folder:WaitForChild("WorldMe")
local WorldNotice = folder:WaitForChild("WorldNotice")
local WorldCommand = folder:WaitForChild("WorldCommand")

-- ============================================================================
-- PALETAS Y CONSTANTES
-- ============================================================================
local OCEAN_COLOR = Color3.fromRGB(15, 32, 58)
local DEEP_OCEAN_COLOR = Color3.fromRGB(10, 22, 42)
local UNCLAIMED_LAND = Color3.fromRGB(72, 85, 78)
local UNCLAIMED_BORDER = Color3.fromRGB(52, 65, 58)
local HUMAN_AURA_COLOR = Color3.fromRGB(255, 220, 0)

-- ============================================================================
-- ESTADO DEL CLIENTE
-- ============================================================================
local state = {
	w = 960,
	h = 400,
	planet = "EARTH",
	difficulty = "NORMAL",
	myId = -1,
	land = nil,
	owner = nil,
	roster = {},
	rosterById = {},
	stats = nil,
	me = {
		troops = 1500,
		gold = 700,
		income = 15,
		cells = 0,
		cities = 0,
		ports = 0,
		posts = 0,
		silos = 0,
		activeAttacks = 0,
		defenseAI = true,
		capital = nil,
		alive = false,
		spawned = false,
	},
	attackRatio = 0.5,
	actionMode = "ATTACK", -- ATTACK, BUILD_City, BUILD_Port, BUILD_Post, BUILD_Silo, NUKE
	hoverCell = -1,
	selectedCell = -1,
	zoom = 1.0,
	pan = Vector2.zero,
	isDragging = false,
	dragStartMouse = Vector2.zero,
	dragStartPan = Vector2.zero,
	editableImage = nil,
	pixelBuffer = nil,
	initialized = false,
}

-- ============================================================================
-- CREACIÓN DE INTERFAZ DE USUARIO
-- ============================================================================
local playerGui = player:WaitForChild("PlayerGui")
local existingGui = playerGui:FindFirstChild("WorldConquestGui")
if existingGui then
	existingGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "WorldConquestGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Contenedor principal de pantalla completa
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
root.BorderSizePixel = 0
root.Parent = gui

-- Área de visualización del mapa (con soporte de Pan & Zoom)
local mapContainer = Instance.new("Frame")
mapContainer.Name = "MapContainer"
mapContainer.Size = UDim2.fromScale(1, 1)
mapContainer.BackgroundColor3 = Color3.fromRGB(8, 12, 20)
mapContainer.ClipsDescendants = true
mapContainer.Parent = root

local mapCanvas = Instance.new("Frame")
mapCanvas.Name = "MapCanvas"
mapCanvas.AnchorPoint = Vector2.new(0.5, 0.5)
mapCanvas.Position = UDim2.fromScale(0.5, 0.5)
mapCanvas.Size = UDim2.fromOffset(1200, 500)
mapCanvas.BackgroundColor3 = Color3.fromRGB(14, 25, 45)
mapCanvas.BorderSizePixel = 0
mapCanvas.Parent = mapContainer

-- Imagen donde se dibuja el mapa editable (EditableImage)
local mapImage = Instance.new("ImageLabel")
mapImage.Name = "MapImage"
mapImage.Size = UDim2.fromScale(1, 1)
mapImage.BackgroundTransparency = 1
mapImage.ResampleMode = Enum.ResamplerMode.Pixelated
mapImage.Parent = mapCanvas

-- Capa de marcadores (Capitales, coronas, ciudades, iconos sobre el mapa)
local markersLayer = Instance.new("Folder")
markersLayer.Name = "MarkersLayer"
markersLayer.Parent = mapCanvas

-- Capa de efectos (animaciones de misiles, rayos láser de defensa)
local fxLayer = Instance.new("Folder")
fxLayer.Name = "FXLayer"
fxLayer.Parent = mapCanvas

-- Selector / Cursor sobre la celda
local cellCursor = Instance.new("Frame")
cellCursor.Name = "CellCursor"
cellCursor.Size = UDim2.fromOffset(5, 5)
cellCursor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
cellCursor.BackgroundTransparency = 0.6
cellCursor.BorderSizePixel = 1
cellCursor.BorderColor3 = Color3.fromRGB(255, 220, 0)
cellCursor.Visible = false
cellCursor.ZIndex = 5
cellCursor.Parent = mapCanvas

-- ============================================================================
-- TOP BAR (Estado, Fase, Marcador, Menú)
-- ============================================================================
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 54)
topBar.Position = UDim2.fromOffset(0, 0)
topBar.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
topBar.BackgroundTransparency = 0.15
topBar.BorderSizePixel = 0
topBar.ZIndex = 20
topBar.Parent = root

local topStroke = Instance.new("UIStroke")
topStroke.Color = Color3.fromRGB(45, 60, 90)
topStroke.Thickness = 1
topStroke.Parent = topBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(0, 280, 1, 0)
titleLabel.Position = UDim2.fromOffset(16, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.Text = "🌍 RECUPERAR PANAMÁ Y EL MUNDO"
titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
titleLabel.TextSize = 15
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 21
titleLabel.Parent = topBar

-- Indicador de fase central
local phaseBadge = Instance.new("Frame")
phaseBadge.Name = "PhaseBadge"
phaseBadge.AnchorPoint = Vector2.new(0.5, 0.5)
phaseBadge.Position = UDim2.fromScale(0.5, 0.5)
phaseBadge.Size = UDim2.fromOffset(360, 36)
phaseBadge.BackgroundColor3 = Color3.fromRGB(25, 35, 55)
phaseBadge.BorderSizePixel = 0
phaseBadge.ZIndex = 21
phaseBadge.Parent = topBar

local phaseCorner = Instance.new("UICorner")
phaseCorner.CornerRadius = UDim.new(0, 8)
phaseCorner.Parent = phaseBadge

local phaseStroke = Instance.new("UIStroke")
phaseStroke.Color = Color3.fromRGB(0, 210, 255)
phaseStroke.Thickness = 1.5
phaseStroke.Parent = phaseBadge

local phaseText = Instance.new("TextLabel")
phaseText.Name = "PhaseText"
phaseText.Size = UDim2.fromScale(1, 1)
phaseText.BackgroundTransparency = 1
phaseText.Font = Enum.Font.GothamBold
phaseText.Text = "📍 FASE DE SPAWN: Haz clic en el mapa para colocar tu capital"
phaseText.TextColor3 = Color3.fromRGB(240, 245, 255)
phaseText.TextSize = 13
phaseText.ZIndex = 22
phaseText.Parent = phaseBadge

-- Botón Menú / Mapas
local btnLobby = Instance.new("TextButton")
btnLobby.Name = "BtnLobby"
btnLobby.AnchorPoint = Vector2.new(1, 0.5)
btnLobby.Position = UDim2.new(1, -16, 0.5, 0)
btnLobby.Size = UDim2.fromOffset(130, 34)
btnLobby.BackgroundColor3 = Color3.fromRGB(40, 70, 120)
btnLobby.Font = Enum.Font.GothamBold
btnLobby.Text = "⚙️ Mapas & Modos"
btnLobby.TextColor3 = Color3.fromRGB(255, 255, 255)
btnLobby.TextSize = 12
btnLobby.BorderSizePixel = 0
btnLobby.ZIndex = 21
btnLobby.Parent = topBar

local btnLobbyCorner = Instance.new("UICorner")
btnLobbyCorner.CornerRadius = UDim.new(0, 6)
btnLobbyCorner.Parent = btnLobby

-- Botón Centrar Cámara
local btnCenter = Instance.new("TextButton")
btnCenter.Name = "BtnCenter"
btnCenter.AnchorPoint = Vector2.new(1, 0.5)
btnCenter.Position = UDim2.new(1, -154, 0.5, 0)
btnCenter.Size = UDim2.fromOffset(100, 34)
btnCenter.BackgroundColor3 = Color3.fromRGB(25, 45, 75)
btnCenter.Font = Enum.Font.GothamBold
btnCenter.Text = "🎯 Mi Capital"
btnCenter.TextColor3 = Color3.fromRGB(255, 220, 0)
btnCenter.TextSize = 12
btnCenter.BorderSizePixel = 0
btnCenter.ZIndex = 21
btnCenter.Parent = topBar

local btnCenterCorner = Instance.new("UICorner")
btnCenterCorner.CornerRadius = UDim.new(0, 6)
btnCenterCorner.Parent = btnCenter

-- ============================================================================
-- LEADERBOARD (Top Naciones + Tu posición destacada en Neón/Oro)
-- ============================================================================
local leaderFrame = Instance.new("Frame")
leaderFrame.Name = "Leaderboard"
leaderFrame.AnchorPoint = Vector2.new(1, 0)
leaderFrame.Position = UDim2.new(1, -16, 0, 62)
leaderFrame.Size = UDim2.fromOffset(230, 250)
leaderFrame.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
leaderFrame.BackgroundTransparency = 0.2
leaderFrame.BorderSizePixel = 0
leaderFrame.ZIndex = 20
leaderFrame.Parent = root

local leaderCorner = Instance.new("UICorner")
leaderCorner.CornerRadius = UDim.new(0, 8)
leaderCorner.Parent = leaderFrame

local leaderStroke = Instance.new("UIStroke")
leaderStroke.Color = Color3.fromRGB(45, 60, 90)
leaderStroke.Thickness = 1
leaderStroke.Parent = leaderFrame

local leaderTitle = Instance.new("TextLabel")
leaderTitle.Size = UDim2.new(1, 0, 0, 26)
leaderTitle.BackgroundTransparency = 1
leaderTitle.Font = Enum.Font.GothamBlack
leaderTitle.Text = "🏆 CLASIFICACIÓN MUNDIAL"
leaderTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
leaderTitle.TextSize = 11
leaderTitle.ZIndex = 21
leaderTitle.Parent = leaderFrame

local leaderList = Instance.new("Frame")
leaderList.Name = "List"
leaderList.Position = UDim2.fromOffset(8, 28)
leaderList.Size = UDim2.new(1, -16, 1, -36)
leaderList.BackgroundTransparency = 1
leaderList.ZIndex = 21
leaderList.Parent = leaderFrame

local leaderLayout = Instance.new("UIListLayout")
leaderLayout.SortOrder = Enum.SortOrder.LayoutOrder
leaderLayout.Padding = UDim.new(0, 3)
leaderLayout.Parent = leaderList

-- ============================================================================
-- BOTTOM HUD (Estilo RoWorld: Recursos, Sliders, Acciones de Construcción y Nuke)
-- ============================================================================
local bottomHUD = Instance.new("Frame")
bottomHUD.Name = "BottomHUD"
bottomHUD.AnchorPoint = Vector2.new(0.5, 1)
bottomHUD.Position = UDim2.new(0.5, 0, 1, -12)
bottomHUD.Size = UDim2.fromOffset(860, 100)
bottomHUD.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
bottomHUD.BackgroundTransparency = 0.12
bottomHUD.BorderSizePixel = 0
bottomHUD.ZIndex = 20
bottomHUD.Parent = root

local bottomCorner = Instance.new("UICorner")
bottomCorner.CornerRadius = UDim.new(0, 10)
bottomCorner.Parent = bottomHUD

local bottomStroke = Instance.new("UIStroke")
bottomStroke.Color = Color3.fromRGB(50, 70, 110)
bottomStroke.Thickness = 1.5
bottomStroke.Parent = bottomHUD

-- Fila Superior del HUD: Estadísticas del jugador
local statsRow = Instance.new("Frame")
statsRow.Name = "StatsRow"
statsRow.Size = UDim2.new(1, -20, 0, 34)
statsRow.Position = UDim2.fromOffset(10, 6)
statsRow.BackgroundTransparency = 1
statsRow.ZIndex = 21
statsRow.Parent = bottomHUD

local troopsCard = Instance.new("TextLabel")
troopsCard.Name = "TroopsCard"
troopsCard.Size = UDim2.fromOffset(170, 30)
troopsCard.Position = UDim2.fromOffset(0, 2)
troopsCard.BackgroundColor3 = Color3.fromRGB(24, 34, 52)
troopsCard.BorderSizePixel = 0
troopsCard.Font = Enum.Font.GothamBlack
troopsCard.Text = "⚔️ Tropas: 1,500 (+25/s)"
troopsCard.TextColor3 = Color3.fromRGB(0, 230, 150)
troopsCard.TextSize = 12
troopsCard.ZIndex = 22
troopsCard.Parent = statsRow

local troopsCorner = Instance.new("UICorner")
troopsCorner.CornerRadius = UDim.new(0, 6)
troopsCorner.Parent = troopsCard

local goldCard = Instance.new("TextLabel")
goldCard.Name = "GoldCard"
goldCard.Size = UDim2.fromOffset(170, 30)
goldCard.Position = UDim2.fromOffset(178, 2)
goldCard.BackgroundColor3 = Color3.fromRGB(24, 34, 52)
goldCard.BorderSizePixel = 0
goldCard.Font = Enum.Font.GothamBlack
goldCard.Text = "💰 Oro: 700 (+15/s)"
goldCard.TextColor3 = Color3.fromRGB(255, 215, 0)
goldCard.TextSize = 12
goldCard.ZIndex = 22
goldCard.Parent = statsRow

local goldCorner = Instance.new("UICorner")
goldCorner.CornerRadius = UDim.new(0, 6)
goldCorner.Parent = goldCard

-- Selector de Ratio de Ataque [20% | 40% | 60% | 80% | 100%]
local ratioLabel = Instance.new("TextLabel")
ratioLabel.Size = UDim2.fromOffset(90, 30)
ratioLabel.Position = UDim2.fromOffset(356, 2)
ratioLabel.BackgroundTransparency = 1
ratioLabel.Font = Enum.Font.GothamBold
ratioLabel.Text = "Envío Ataque:"
ratioLabel.TextColor3 = Color3.fromRGB(180, 200, 230)
ratioLabel.TextSize = 11
ratioLabel.ZIndex = 22
ratioLabel.Parent = statsRow

local ratioButtons = {}
local ratios = { 0.2, 0.4, 0.6, 0.8, 1.0 }
for idx, r in ipairs(ratios) do
	local btn = Instance.new("TextButton")
	btn.Name = "Ratio_" .. math.floor(r * 100)
	btn.Size = UDim2.fromOffset(40, 26)
	btn.Position = UDim2.fromOffset(448 + (idx - 1) * 44, 4)
	btn.BackgroundColor3 = (r == 0.5 or r == 0.6) and Color3.fromRGB(0, 180, 220) or Color3.fromRGB(30, 42, 64)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBlack
	btn.Text = math.floor(r * 100) .. "%"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 11
	btn.ZIndex = 22
	btn.Parent = statsRow

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = btn

	ratioButtons[r] = btn

	btn.MouseButton1Click:Connect(function()
		state.attackRatio = r
		for rat, b in pairs(ratioButtons) do
			b.BackgroundColor3 = (rat == r) and Color3.fromRGB(0, 200, 240) or Color3.fromRGB(30, 42, 64)
			b.TextColor3 = (rat == r) and Color3.fromRGB(10, 15, 25) or Color3.fromRGB(220, 230, 245)
		end
	end)
end

-- Botón IA Defensa (Toggle)
local btnAI = Instance.new("TextButton")
btnAI.Name = "BtnAI"
btnAI.AnchorPoint = Vector2.new(1, 0)
btnAI.Position = UDim2.new(1, 0, 0, 2)
btnAI.Size = UDim2.fromOffset(140, 30)
btnAI.BackgroundColor3 = Color3.fromRGB(0, 150, 90)
btnAI.BorderSizePixel = 0
btnAI.Font = Enum.Font.GothamBold
btnAI.Text = "🛡️ IA Defensa: ON"
btnAI.TextColor3 = Color3.fromRGB(255, 255, 255)
btnAI.TextSize = 11
btnAI.ZIndex = 22
btnAI.Parent = statsRow

local btnAICorner = Instance.new("UICorner")
btnAICorner.CornerRadius = UDim.new(0, 6)
btnAICorner.Parent = btnAI

btnAI.MouseButton1Click:Connect(function()
	state.me.defenseAI = not state.me.defenseAI
	WorldCommand:FireServer({ a = "DEFENSE_AI", on = state.me.defenseAI })
	btnAI.BackgroundColor3 = state.me.defenseAI and Color3.fromRGB(0, 150, 90) or Color3.fromRGB(140, 40, 40)
	btnAI.Text = state.me.defenseAI and "🛡️ IA Defensa: ON" or "⚠️ IA Defensa: OFF"
end)

-- Fila Inferior del HUD: Barra de Acciones de Construcción y Combate
local actionsRow = Instance.new("Frame")
actionsRow.Name = "ActionsRow"
actionsRow.Size = UDim2.new(1, -20, 0, 48)
actionsRow.Position = UDim2.fromOffset(10, 44)
actionsRow.BackgroundTransparency = 1
actionsRow.ZIndex = 21
actionsRow.Parent = bottomHUD

local actionButtons = {}

local function createActionButton(id, text, subtext, color, icon)
	local btn = Instance.new("TextButton")
	btn.Name = "Action_" .. id
	btn.Size = UDim2.fromOffset(132, 42)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.Text = ""
	btn.ZIndex = 22
	btn.Parent = actionsRow

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 0
	stroke.Parent = btn

	local t1 = Instance.new("TextLabel")
	t1.Size = UDim2.new(1, 0, 0, 20)
	t1.Position = UDim2.fromOffset(0, 4)
	t1.BackgroundTransparency = 1
	t1.Font = Enum.Font.GothamBlack
	t1.Text = icon .. " " .. text
	t1.TextColor3 = Color3.fromRGB(255, 255, 255)
	t1.TextSize = 11
	t1.ZIndex = 23
	t1.Parent = btn

	local t2 = Instance.new("TextLabel")
	t2.Size = UDim2.new(1, 0, 0, 16)
	t2.Position = UDim2.fromOffset(0, 22)
	t2.BackgroundTransparency = 1
	t2.Font = Enum.Font.Gotham
	t2.Text = subtext
	t2.TextColor3 = Color3.fromRGB(230, 240, 255)
	t2.TextSize = 10
	t2.ZIndex = 23
	t2.Parent = btn

	actionButtons[id] = { button = btn, stroke = stroke, baseColor = color }
	return btn
end

local btnAttack = createActionButton("ATTACK", "ATACAR", "Clic en frontera", Color3.fromRGB(200, 40, 40), "⚔️")
btnAttack.Position = UDim2.fromOffset(0, 2)

local btnCity = createActionButton("BUILD_City", "CIUDAD", "$500 Oro (+Oro)", Color3.fromRGB(40, 110, 180), "🏢")
btnCity.Position = UDim2.fromOffset(140, 2)

local btnPort = createActionButton("BUILD_Port", "PUERTO", "$400 Oro (Mar)", Color3.fromRGB(30, 130, 150), "⚓")
btnPort.Position = UDim2.fromOffset(280, 2)

local btnPost =
	createActionButton("BUILD_Post", "PUESTO DEF.", "$350 Oro (Torre)", Color3.fromRGB(150, 110, 20), "🛡️")
btnPost.Position = UDim2.fromOffset(420, 2)

local btnSilo = createActionButton("BUILD_Silo", "SILO MISIL", "$1200 Oro", Color3.fromRGB(100, 50, 140), "🚀")
btnSilo.Position = UDim2.fromOffset(560, 2)

local btnNuke = createActionButton("NUKE", "MISIL NUCLEAR", "900 Tropas", Color3.fromRGB(180, 70, 0), "☢️")
btnNuke.Position = UDim2.fromOffset(700, 2)

local function setActionMode(mode)
	state.actionMode = mode
	for id, item in pairs(actionButtons) do
		if id == mode then
			item.stroke.Thickness = 2
			item.stroke.Color = Color3.fromRGB(255, 230, 0)
			item.button.BackgroundColor3 = Color3.fromRGB(
				math.min(255, item.baseColor.R * 255 + 40),
				math.min(255, item.baseColor.G * 255 + 40),
				math.min(255, item.baseColor.B * 255 + 40)
			)
		else
			item.stroke.Thickness = 0
			item.button.BackgroundColor3 = item.baseColor
		end
	end
end

btnAttack.MouseButton1Click:Connect(function()
	setActionMode("ATTACK")
end)
btnCity.MouseButton1Click:Connect(function()
	setActionMode("BUILD_City")
end)
btnPort.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Port")
end)
btnPost.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Post")
end)
btnSilo.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Silo")
end)
btnNuke.MouseButton1Click:Connect(function()
	setActionMode("NUKE")
end)

setActionMode("ATTACK")

-- ============================================================================
-- TOAST / NOTIFICACIONES FLOTANTES
-- ============================================================================
local toastFrame = Instance.new("Frame")
toastFrame.Name = "ToastFrame"
toastFrame.AnchorPoint = Vector2.new(0.5, 0)
toastFrame.Position = UDim2.new(0.5, 0, 0, 62)
toastFrame.Size = UDim2.fromOffset(440, 32)
toastFrame.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
toastFrame.BorderSizePixel = 0
toastFrame.Visible = false
toastFrame.ZIndex = 30
toastFrame.Parent = root

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 6)
toastCorner.Parent = toastFrame

local toastText = Instance.new("TextLabel")
toastText.Size = UDim2.fromScale(1, 1)
toastText.BackgroundTransparency = 1
toastText.Font = Enum.Font.GothamBold
toastText.Text = ""
toastText.TextColor3 = Color3.fromRGB(255, 255, 255)
toastText.TextSize = 12
toastText.ZIndex = 31
toastText.Parent = toastFrame

local toastThread = nil
local function showToast(text, color)
	toastText.Text = text
	toastText.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	toastFrame.Visible = true
	if toastThread then
		task.cancel(toastThread)
	end
	toastThread = task.delay(3.5, function()
		toastFrame.Visible = false
	end)
end

-- ============================================================================
-- MODAL DE LOBBY (Mapas de la Tierra, Planetas, Andrómeda, Dificultad, Bots)
-- ============================================================================
local modalLobby = Instance.new("Frame")
modalLobby.Name = "ModalLobby"
modalLobby.AnchorPoint = Vector2.new(0.5, 0.5)
modalLobby.Position = UDim2.fromScale(0.5, 0.5)
modalLobby.Size = UDim2.fromOffset(600, 420)
modalLobby.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
modalLobby.BorderSizePixel = 0
modalLobby.Visible = false
modalLobby.ZIndex = 40
modalLobby.Parent = root

local modalCorner = Instance.new("UICorner")
modalCorner.CornerRadius = UDim.new(0, 10)
modalCorner.Parent = modalLobby

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = Color3.fromRGB(0, 200, 255)
modalStroke.Thickness = 2
modalStroke.Parent = modalLobby

local modalTitle = Instance.new("TextLabel")
modalTitle.Size = UDim2.new(1, -40, 0, 40)
modalTitle.Position = UDim2.fromOffset(20, 10)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.GothamBlack
modalTitle.Text = "⚙️ CONFIGURACIÓN DE PARTIDA Y MAPAS"
modalTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
modalTitle.TextSize = 16
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.ZIndex = 41
modalTitle.Parent = modalLobby

local btnCloseModal = Instance.new("TextButton")
btnCloseModal.AnchorPoint = Vector2.new(1, 0)
btnCloseModal.Position = UDim2.new(1, -16, 0, 14)
btnCloseModal.Size = UDim2.fromOffset(30, 30)
btnCloseModal.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
btnCloseModal.Font = Enum.Font.GothamBlack
btnCloseModal.Text = "✕"
btnCloseModal.TextColor3 = Color3.fromRGB(255, 255, 255)
btnCloseModal.TextSize = 14
btnCloseModal.ZIndex = 42
btnCloseModal.Parent = modalLobby

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = btnCloseModal

btnCloseModal.MouseButton1Click:Connect(function()
	modalLobby.Visible = false
end)
btnLobby.MouseButton1Click:Connect(function()
	modalLobby.Visible = not modalLobby.Visible
end)

-- Selector de Planetas / Mapas
local selPlanet = "EARTH"
local selBots = 40
local selDiff = "NORMAL"

local planetLabel = Instance.new("TextLabel")
planetLabel.Size = UDim2.new(1, -40, 0, 24)
planetLabel.Position = UDim2.fromOffset(20, 60)
planetLabel.BackgroundTransparency = 1
planetLabel.Font = Enum.Font.GothamBold
planetLabel.Text = "Selecciona Mapa o Mundo:"
planetLabel.TextColor3 = Color3.fromRGB(200, 220, 245)
planetLabel.TextSize = 13
planetLabel.TextXAlignment = Enum.TextXAlignment.Left
planetLabel.ZIndex = 41
planetLabel.Parent = modalLobby

local planetButtons = {}
local planetList = {
	{ id = "EARTH", name = "🌍 Tierra (Continentes Reales)" },
	{ id = "PANGEA", name = "🦕 Pangea (Era Dinosaurios)" },
	{ id = "MARS", name = "🔴 Marte (Colonias)" },
	{ id = "MOON", name = "🌕 Luna (Bases Lunares)" },
	{ id = "VENUS", name = "🪐 Venus (Volcánico)" },
	{ id = "ANDROMEDA", name = "🌌 Galaxia Andrómeda" },
}

for i, pInfo in ipairs(planetList) do
	local col = (i - 1) % 2
	local row = math.floor((i - 1) / 2)
	local btn = Instance.new("TextButton")
	btn.Name = "Planet_" .. pInfo.id
	btn.Size = UDim2.fromOffset(270, 36)
	btn.Position = UDim2.fromOffset(20 + col * 285, 90 + row * 44)
	btn.BackgroundColor3 = (pInfo.id == selPlanet) and Color3.fromRGB(0, 150, 220) or Color3.fromRGB(30, 40, 60)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.Text = pInfo.name
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 12
	btn.ZIndex = 42
	btn.Parent = modalLobby

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn

	planetButtons[pInfo.id] = btn

	btn.MouseButton1Click:Connect(function()
		selPlanet = pInfo.id
		for pid, b in pairs(planetButtons) do
			b.BackgroundColor3 = (pid == selPlanet) and Color3.fromRGB(0, 150, 220) or Color3.fromRGB(30, 40, 60)
		end
	end)
end

-- Selector de Dificultad
local diffLabel = Instance.new("TextLabel")
diffLabel.Size = UDim2.new(1, -40, 0, 24)
diffLabel.Position = UDim2.fromOffset(20, 235)
diffLabel.BackgroundTransparency = 1
diffLabel.Font = Enum.Font.GothamBold
diffLabel.Text = "Dificultad de los Bots:"
diffLabel.TextColor3 = Color3.fromRGB(200, 220, 245)
diffLabel.TextSize = 13
diffLabel.TextXAlignment = Enum.TextXAlignment.Left
diffLabel.ZIndex = 41
diffLabel.Parent = modalLobby

local diffButtons = {}
local diffs = {
	{ id = "EASY", name = "🟢 Fácil" },
	{ id = "NORMAL", name = "🟡 Normal" },
	{ id = "HARD", name = "🟠 Difícil" },
	{ id = "EXTREME", name = "🔴 Extrema" },
}

for i, d in ipairs(diffs) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(130, 32)
	btn.Position = UDim2.fromOffset(20 + (i - 1) * 142, 265)
	btn.BackgroundColor3 = (d.id == selDiff) and Color3.fromRGB(0, 180, 120) or Color3.fromRGB(30, 40, 60)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.Text = d.name
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 12
	btn.ZIndex = 42
	btn.Parent = modalLobby

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn

	diffButtons[d.id] = btn

	btn.MouseButton1Click:Connect(function()
		selDiff = d.id
		for did, b in pairs(diffButtons) do
			b.BackgroundColor3 = (did == selDiff) and Color3.fromRGB(0, 180, 120) or Color3.fromRGB(30, 40, 60)
		end
	end)
end

-- Botón Iniciar Partida
local btnStartMatch = Instance.new("TextButton")
btnStartMatch.Size = UDim2.fromOffset(360, 46)
btnStartMatch.AnchorPoint = Vector2.new(0.5, 1)
btnStartMatch.Position = UDim2.new(0.5, 0, 1, -20)
btnStartMatch.BackgroundColor3 = Color3.fromRGB(255, 160, 0)
btnStartMatch.BorderSizePixel = 0
btnStartMatch.Font = Enum.Font.GothamBlack
btnStartMatch.Text = "🚀 ¡INICIAR NUEVA PARTIDA!"
btnStartMatch.TextColor3 = Color3.fromRGB(15, 20, 30)
btnStartMatch.TextSize = 14
btnStartMatch.ZIndex = 42
btnStartMatch.Parent = modalLobby

local startCorner = Instance.new("UICorner")
startCorner.CornerRadius = UDim.new(0, 8)
startCorner.Parent = btnStartMatch

btnStartMatch.MouseButton1Click:Connect(function()
	modalLobby.Visible = false
	WorldCommand:FireServer({
		a = "PLAY",
		planet = selPlanet,
		bots = selBots,
		difficulty = selDiff,
	})
	showToast("Reiniciando mundo en modo " .. selPlanet .. "...", Color3.fromRGB(255, 215, 0))
end)

-- ============================================================================
-- RENDERIZADO DEL MAPA CON EDITABLEIMAGE
-- ============================================================================
local function initEditableImage(w, h)
	state.w = w
	state.h = h

	if not state.editableImage then
		local ok, img = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
		end)
		if ok and img then
			state.editableImage = img
			mapImage.ImageContent = Content.fromObject(img)
		else
			warn("Fallo al crear EditableImage:", img)
			return
		end
	end

	state.pixelBuffer = buffer.create(w * h * 4)
	-- Inicializar buffer con agua profunda
	for idx = 0, (w * h) - 1 do
		local offset = idx * 4
		buffer.writeu8(state.pixelBuffer, offset, 14)
		buffer.writeu8(state.pixelBuffer, offset + 1, 28)
		buffer.writeu8(state.pixelBuffer, offset + 2, 52)
		buffer.writeu8(state.pixelBuffer, offset + 3, 255)
	end
end

local function drawCell(idx, ownerId)
	if not state.editableImage or not state.pixelBuffer then
		return
	end

	local isLand = buffer.readu8(state.land, idx) == 1
	local offset = idx * 4

	local r, g, b = 15, 32, 58
	if not isLand then
		r, g, b = 12, 24, 46
	elseif ownerId == 0 then
		r, g, b = 75, 88, 80
	else
		local n = state.rosterById[ownerId]
		if n then
			r = n.r or (n.color and math.floor(n.color.R * 255)) or 200
			g = n.g or (n.color and math.floor(n.color.G * 255)) or 200
			b = n.b or (n.color and math.floor(n.color.B * 255)) or 200

			-- Si es la nación del jugador humano, aumentamos el brillo
			if ownerId == state.myId then
				r = math.min(255, r + 45)
				g = math.min(255, g + 45)
				b = math.min(255, b + 45)
			end
		end
	end

	buffer.writeu8(state.pixelBuffer, offset, r)
	buffer.writeu8(state.pixelBuffer, offset + 1, g)
	buffer.writeu8(state.pixelBuffer, offset + 2, b)
	buffer.writeu8(state.pixelBuffer, offset + 3, 255)
end

local function flushImage()
	if state.editableImage and state.pixelBuffer then
		pcall(function()
			state.editableImage:WritePixelsBuffer(Vector2.zero, Vector2.new(state.w, state.h), state.pixelBuffer)
		end)
	end
end

local function fullRedraw()
	if not state.editableImage or not state.pixelBuffer or not state.land or not state.owner then
		return
	end
	for idx = 0, (state.w * state.h) - 1 do
		local ownerId = buffer.readu8(state.owner, idx)
		drawCell(idx, ownerId)
	end
	flushImage()
end

-- ============================================================================
-- MARCADORES VISUALES (Capitales con Corona Dorada [TÚ], Iconos de Ciudades)
-- ============================================================================
local markerPool = {}

local function clearMarkers()
	for _, m in pairs(markerPool) do
		m:Destroy()
	end
	table.clear(markerPool)
end

local function updateMarkers()
	clearMarkers()
	if not state.roster then
		return
	end

	for _, n in ipairs(state.roster) do
		if n.capital and n.capital >= 0 then
			local capCell = n.capital
			local capX = capCell % state.w
			local capY = math.floor(capCell / state.w)

			local marker = Instance.new("Frame")
			marker.Name = "CapMarker_" .. n.id
			marker.AnchorPoint = Vector2.new(0.5, 0.5)
			marker.Position = UDim2.fromScale((capX + 0.5) / state.w, (capY + 0.5) / state.h)
			marker.Size = UDim2.fromOffset(24, 24)
			marker.BackgroundTransparency = 1
			marker.ZIndex = 10
			marker.Parent = markersLayer

			local isMe = (n.id == state.myId)

			-- Si es el jugador humano, añadimos la CORONA DORADA y AURA NEÓN resplandeciente
			if isMe then
				local aura = Instance.new("Frame")
				aura.Name = "Aura"
				aura.AnchorPoint = Vector2.new(0.5, 0.5)
				aura.Position = UDim2.fromScale(0.5, 0.5)
				aura.Size = UDim2.fromOffset(34, 34)
				aura.BackgroundColor3 = Color3.fromRGB(255, 220, 0)
				aura.BackgroundTransparency = 0.6
				aura.BorderSizePixel = 0
				aura.Parent = marker

				local auraCorner = Instance.new("UICorner")
				auraCorner.CornerRadius = UDim.new(1, 0)
				auraCorner.Parent = aura

				local crownLabel = Instance.new("TextLabel")
				crownLabel.Name = "Crown"
				crownLabel.Size = UDim2.fromOffset(22, 20)
				crownLabel.Position = UDim2.fromOffset(1, -16)
				crownLabel.BackgroundTransparency = 1
				crownLabel.Font = Enum.Font.GothamBlack
				crownLabel.Text = "👑 [TÚ]"
				crownLabel.TextColor3 = Color3.fromRGB(255, 230, 0)
				crownLabel.TextSize = 11
				crownLabel.Parent = marker
			end

			-- Punto de la capital
			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(0.5, 0.5)
			dot.Size = isMe and UDim2.fromOffset(14, 14) or UDim2.fromOffset(8, 8)
			dot.BackgroundColor3 = isMe and Color3.fromRGB(255, 240, 50) or n.color
			dot.BorderSizePixel = 1
			dot.BorderColor3 = isMe and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(10, 10, 15)
			dot.Parent = marker

			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot

			-- Etiqueta con el nombre
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "Name"
			nameLbl.Size = UDim2.fromOffset(100, 16)
			nameLbl.Position = UDim2.fromOffset(-38, isMe and 14 or 8)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = isMe and Enum.Font.GothamBlack or Enum.Font.GothamBold
			nameLbl.Text = (isMe and "👑 " or "") .. n.name
			nameLbl.TextColor3 = isMe and Color3.fromRGB(255, 230, 50) or Color3.fromRGB(230, 235, 245)
			nameLbl.TextSize = isMe and 11 or 9
			nameLbl.Parent = marker

			table.insert(markerPool, marker)
		end
	end
end

-- ============================================================================
-- INTERACCIÓN CON EL MAPA (Clic para Atacar, Construir, Nuke o Spawn)
-- ============================================================================
local function screenToCell(screenPos)
	local canvasPos = mapCanvas.AbsolutePosition
	local canvasSize = mapCanvas.AbsoluteSize

	local relX = (screenPos.X - canvasPos.X) / canvasSize.X
	local relY = (screenPos.Y - canvasPos.Y) / canvasSize.Y

	if relX < 0 or relX >= 1 or relY < 0 or relY >= 1 then
		return -1
	end

	local cellX = math.floor(relX * state.w)
	local cellY = math.floor(relY * state.h)
	return cellY * state.w + cellX
end

local function cellToScreen(cellIdx)
	local canvasPos = mapCanvas.AbsolutePosition
	local canvasSize = mapCanvas.AbsoluteSize

	local cellX = cellIdx % state.w
	local cellY = math.floor(cellIdx / state.w)

	local scrX = canvasPos.X + (cellX + 0.5) / state.w * canvasSize.X
	local scrY = canvasPos.Y + (cellY + 0.5) / state.h * canvasSize.Y
	return Vector2.new(scrX, scrY)
end

local function handleMapClick(cell)
	if cell < 0 or cell >= (state.w * state.h) then
		return
	end

	-- Fase de Spawn
	if state.stats and state.stats.phase == "SPAWN" then
		WorldCommand:FireServer({ a = "SPAWN", cell = cell })
		showToast("📍 Capital establecida en la celda " .. cell, Color3.fromRGB(0, 220, 255))
		return
	end

	-- Fase de Batalla
	if state.actionMode == "ATTACK" then
		WorldCommand:FireServer({ a = "ATTACK", cell = cell, ratio = state.attackRatio })
	elseif state.actionMode:sub(1, 6) == "BUILD_" then
		local kind = state.actionMode:sub(7)
		WorldCommand:FireServer({ a = "BUILD", kind = kind, cell = cell })
	elseif state.actionMode == "NUKE" then
		WorldCommand:FireServer({ a = "NUKE", cell = cell })
		setActionMode("ATTACK")
	end
end

-- ============================================================================
-- PAN & ZOOM (Navegación fluida por el mapa)
-- ============================================================================
local BASE_WIDTH = 2400
local BASE_HEIGHT = 1000

local function updateMapTransform()
	local viewportSize = mapContainer.AbsoluteSize
	local scaledW = BASE_WIDTH * state.zoom
	local scaledH = BASE_HEIGHT * state.zoom

	mapCanvas.Size = UDim2.fromOffset(scaledW, scaledH)
	mapCanvas.Position = UDim2.fromOffset(viewportSize.X / 2 + state.pan.X, viewportSize.Y / 2 + state.pan.Y)
end

mapContainer.InputBegan:Connect(function(input)
	if
		input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.MouseButton3
	then
		state.isDragging = true
		state.dragStartMouse = Vector2.new(input.Position.X, input.Position.Y)
		state.dragStartPan = state.pan
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local cell = screenToCell(Vector2.new(input.Position.X, input.Position.Y))
		if cell >= 0 then
			handleMapClick(cell)
		end
	end
end)

mapContainer.InputEnded:Connect(function(input)
	if
		input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.MouseButton3
	then
		state.isDragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if state.isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local current = Vector2.new(input.Position.X, input.Position.Y)
		local delta = current - state.dragStartMouse
		state.pan = state.dragStartPan + delta
		updateMapTransform()
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		local factor = if input.Position.Z > 0 then 1.15 else 0.85
		state.zoom = math.clamp(state.zoom * factor, 0.25, 8.0)
		updateMapTransform()
	end
end)

-- Hover sobre celdas para cursor
RunService.RenderStepped:Connect(function()
	local cell = screenToCell(Vector2.new(mouse.X, mouse.Y))
	if cell >= 0 and cell ~= state.hoverCell then
		state.hoverCell = cell
		local cellX = cell % state.w
		local cellY = math.floor(cell / state.w)

		cellCursor.Position = UDim2.fromScale(cellX / state.w, cellY / state.h)
		cellCursor.Size = UDim2.fromScale(1 / state.w, 1 / state.h)
		cellCursor.Visible = true
	elseif cell < 0 then
		cellCursor.Visible = false
	end
end)

-- Botón centrar en capital
btnCenter.MouseButton1Click:Connect(function()
	if state.myId > 0 and state.rosterById[state.myId] then
		local me = state.rosterById[state.myId]
		if me.capital and me.capital >= 0 then
			local capCell = me.capital
			local capX = capCell % state.w
			local capY = math.floor(capCell / state.w)

			local normX = (capX + 0.5) / state.w - 0.5
			local normY = (capY + 0.5) / state.h - 0.5

			state.pan = Vector2.new(-normX * BASE_WIDTH * state.zoom, -normY * BASE_HEIGHT * state.zoom)
			updateMapTransform()
			showToast("🎯 Centrado en tu capital", Color3.fromRGB(255, 220, 0))
		end
	end
end)

-- ============================================================================
-- GESTIÓN DE EVENTOS DE RED (WorldRemotes)
-- ============================================================================
WorldInit.OnClientEvent:Connect(function(data)
	state.planet = data.planet or "EARTH"
	state.w = data.w
	state.h = data.h
	state.land = data.land
	state.owner = data.owner
	state.roster = data.roster or {}
	state.myId = data.myId or -1
	state.stats = data.stats
	state.difficulty = data.difficulty or "NORMAL"

	state.rosterById = {}
	for _, n in ipairs(state.roster) do
		n.color = Color3.fromRGB(n.r or 200, n.g or 200, n.b or 200)
		state.rosterById[n.id] = n
	end

	initEditableImage(state.w, state.h)
	fullRedraw()
	updateMarkers()
	updateMapTransform()

	state.initialized = true
	showToast("¡Bienvenido al mapa de " .. state.planet .. "!", Color3.fromRGB(0, 210, 255))
end)

WorldDiff.OnClientEvent:Connect(function(diffBuf)
	if not state.owner or not state.editableImage then
		return
	end

	local count = math.floor(buffer.len(diffBuf) / 4)
	for i = 0, count - 1 do
		local packed = buffer.readu32(diffBuf, i * 4)
		local cell = math.floor(packed / 256)
		local ownerId = packed % 256

		if cell < (state.w * state.h) then
			buffer.writeu8(state.owner, cell, ownerId)
			drawCell(cell, ownerId)
		end
	end

	flushImage()
end)

WorldStats.OnClientEvent:Connect(function(stats)
	state.stats = stats

	-- Actualizar fase
	if stats.phase == "SPAWN" then
		phaseText.Text = "📍 FASE DE SPAWN: Elige tu capital (" .. math.ceil(stats.spawnTimer or 0) .. "s)"
		phaseStroke.Color = Color3.fromRGB(0, 220, 255)
	elseif stats.phase == "BATTLE" or stats.phase == "RUNNING" then
		phaseText.Text = "⚔️ ¡GUERRA MUNDIAL! Conquista los continentes"
		phaseStroke.Color = Color3.fromRGB(255, 60, 60)
	elseif stats.phase == "ENDED" then
		phaseText.Text = "🏆 ¡PARTIDA FINALIZADA!"
		phaseStroke.Color = Color3.fromRGB(255, 215, 0)
	end

	-- Actualizar Leaderboard
	for _, child in ipairs(leaderList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if stats.top then
		for rank, entry in ipairs(stats.top) do
			if rank <= 7 then
				local row = Instance.new("Frame")
				row.Name = "Row_" .. rank
				row.Size = UDim2.new(1, 0, 0, 22)
				row.BackgroundColor3 = entry.isMe and Color3.fromRGB(60, 50, 10) or Color3.fromRGB(20, 28, 42)
				row.BorderSizePixel = 0
				row.Parent = leaderList

				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, 4)
				c.Parent = row

				if entry.isMe then
					local s = Instance.new("UIStroke")
					s.Color = Color3.fromRGB(255, 215, 0)
					s.Thickness = 1
					s.Parent = row
				end

				local rankLbl = Instance.new("TextLabel")
				rankLbl.Size = UDim2.fromOffset(20, 22)
				rankLbl.BackgroundTransparency = 1
				rankLbl.Font = Enum.Font.GothamBlack
				rankLbl.Text = tostring(rank)
				rankLbl.TextColor3 = entry.isMe and Color3.fromRGB(255, 220, 0) or Color3.fromRGB(150, 170, 195)
				rankLbl.TextSize = 10
				rankLbl.Parent = row

				local nameLbl = Instance.new("TextLabel")
				nameLbl.Size = UDim2.new(1, -70, 1, 0)
				nameLbl.Position = UDim2.fromOffset(24, 0)
				nameLbl.BackgroundTransparency = 1
				nameLbl.Font = entry.isMe and Enum.Font.GothamBlack or Enum.Font.GothamBold
				nameLbl.Text = (entry.isMe and "👑 [TÚ] " or "") .. entry.name
				nameLbl.TextColor3 = entry.isMe and Color3.fromRGB(255, 230, 50) or Color3.fromRGB(220, 230, 245)
				nameLbl.TextSize = 10
				nameLbl.TextXAlignment = Enum.TextXAlignment.Left
				nameLbl.Parent = row

				local pctLbl = Instance.new("TextLabel")
				pctLbl.AnchorPoint = Vector2.new(1, 0)
				pctLbl.Position = UDim2.new(1, -6, 0, 0)
				pctLbl.Size = UDim2.fromOffset(45, 22)
				pctLbl.BackgroundTransparency = 1
				pctLbl.Font = Enum.Font.GothamBold
				pctLbl.Text = string.format("%.1f%%", entry.pct or 0)
				pctLbl.TextColor3 = entry.isMe and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(180, 200, 220)
				pctLbl.TextSize = 10
				pctLbl.TextXAlignment = Enum.TextXAlignment.Right
				pctLbl.Parent = row
			end
		end
	end
end)

WorldMe.OnClientEvent:Connect(function(meData)
	state.me = meData
	if meData.capital and meData.capital >= 0 then
		local myRoster = state.rosterById[state.myId]
		if myRoster and myRoster.capital ~= meData.capital then
			myRoster.capital = meData.capital
			updateMarkers()
		end
	end
	troopsCard.Text = string.format("⚔️ Tropas: %d (+%d/s)", meData.troops or 0, (meData.cities or 0) * 10 + 20)
	goldCard.Text = string.format("💰 Oro: %d (+%d/s)", meData.gold or 0, meData.income or 10)
end)

WorldNotice.OnClientEvent:Connect(function(msg)
	showToast(msg, Color3.fromRGB(255, 220, 50))
end)

-- Solicitar inicio de partida o unirse automáticamente
task.spawn(function()
	task.wait(0.5)
	WorldCommand:FireServer({ a = "PLAY", planet = "EARTH", bots = 40, difficulty = "NORMAL" })
end)

updateMapTransform()
