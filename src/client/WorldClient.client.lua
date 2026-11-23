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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldGrid = require(Shared:WaitForChild("WorldGrid"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Oculta lo que el juego no usa de la interfaz por defecto de Roblox (el logo y el menú de Roblox no se pueden quitar)
task.spawn(function()
	local StarterGui = game:GetService("StarterGui")
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			break
		end
		task.wait(0.5) -- los CoreGui pueden tardar en registrarse
	end
end)

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
	mode = "FREE", -- FREE o COUNTRIES (Países vs Países)
	difficulty = "NORMAL",
	myId = -1,
	land = nil,
	owner = nil,
	baseBuffer = nil,
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
	-- Respaldo por bloques cuando EditableImage no está disponible en la experiencia
	blockMode = false,
	blocks = nil,
	blockLayer = nil,
	blockW = 0,
	blockH = 0,
	dirtyBlocks = {},
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
-- Deja libre la esquina superior izquierda: ahí Roblox dibuja su logo, menú y botones por defecto
titleLabel.Position = UDim2.fromOffset(276, 0)
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
btnLobby.Text = "⚙️ Menú y Modos"
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
leaderFrame.BackgroundTransparency = 0.04 -- casi opaco: los rótulos del mapa no deben transparentarse
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

local leaderScale = Instance.new("UIScale")
leaderScale.Parent = leaderFrame

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
-- 7 botones de 132 px + separación (140 px de paso) + márgenes: 10 + 6*140 + 132 + 10 = 992 px
bottomHUD.Size = UDim2.fromOffset(1000, 104)
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

-- Los paneles de tamaño fijo se reescalan según la pantalla (ver fitUI) para no deformarse ni salirse
local hudScale = Instance.new("UIScale")
hudScale.Parent = bottomHUD

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

local btnRetreat = createActionButton("RETREAT", "RETIRADA", "Recuperar tropas", Color3.fromRGB(130, 40, 40), "🏳️")
btnRetreat.Position = UDim2.fromOffset(840, 2)

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
btnRetreat.MouseButton1Click:Connect(function()
	WorldCommand:FireServer({ a = "RETREAT" })
	showToast("🏳️ Retirada ordenada: tropas devueltas al territorio", Color3.fromRGB(255, 180, 50))
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
-- PANTALLA DE LOBBY: modo de juego, mapa y dificultad.
-- Se muestra al entrar y se reabre desde "☰ Menú". El anfitrión (primer jugador) crea la partida;
-- los demás jugadores del servidor entran a la partida en curso.
-- ============================================================================
local selPlanet = "EARTH"
local selBots = 40
local selDiff = "NORMAL"
local selMode = "COUNTRIES"

local COLOR_CARD = Color3.fromRGB(26, 36, 56)
local COLOR_CARD_SEL = Color3.fromRGB(24, 70, 96)
local COLOR_CHIP = Color3.fromRGB(30, 42, 64)
local COLOR_ACCENT = Color3.fromRGB(0, 200, 255)

local lobbyScreen = Instance.new("Frame")
lobbyScreen.Name = "LobbyScreen"
lobbyScreen.Size = UDim2.fromScale(1, 1)
lobbyScreen.BackgroundColor3 = Color3.fromRGB(6, 10, 18)
lobbyScreen.BackgroundTransparency = 0.1
lobbyScreen.BorderSizePixel = 0
lobbyScreen.Active = true -- bloquea los clics hacia el mapa
lobbyScreen.ZIndex = 60
lobbyScreen.Parent = root

local lobbyCard = Instance.new("Frame")
lobbyCard.Name = "LobbyCard"
lobbyCard.AnchorPoint = Vector2.new(0.5, 0.5)
lobbyCard.Position = UDim2.fromScale(0.5, 0.5)
lobbyCard.Size = UDim2.fromOffset(920, 600)
lobbyCard.BackgroundColor3 = Color3.fromRGB(14, 20, 34)
lobbyCard.BorderSizePixel = 0
lobbyCard.ZIndex = 61
lobbyCard.Parent = lobbyScreen

local lobbyCardCorner = Instance.new("UICorner")
lobbyCardCorner.CornerRadius = UDim.new(0, 16)
lobbyCardCorner.Parent = lobbyCard

local lobbyCardStroke = Instance.new("UIStroke")
lobbyCardStroke.Color = COLOR_ACCENT
lobbyCardStroke.Thickness = 2
lobbyCardStroke.Parent = lobbyCard

-- Escala la tarjeta para que quepa en pantallas pequeñas (móviles, ventanas reducidas)
local lobbyScale = Instance.new("UIScale")
lobbyScale.Parent = lobbyCard
local function fitLobby()
	local vs = root.AbsoluteSize
	if vs.X > 0 and vs.Y > 0 then
		lobbyScale.Scale = math.clamp(math.min(vs.X / 960, vs.Y / 640), 0.45, 1.25)
	end
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitLobby)
fitLobby()

local function lobbyLabel(text, pos, size, font, color, textSize, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Position = pos
	l.Size = size
	l.Font = font
	l.TextColor3 = color
	l.TextSize = textSize
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.ZIndex = 62
	l.Parent = lobbyCard
	return l
end

local function roundCorners(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = obj
end

lobbyLabel(
	"🌍 RECUPERAR PANAMÁ Y EL MUNDO",
	UDim2.fromOffset(28, 18),
	UDim2.fromOffset(700, 38),
	Enum.Font.GothamBlack,
	Color3.fromRGB(255, 215, 0),
	26
)
lobbyLabel(
	"Conquista el mundo país por país. Hasta 20 jugadores por servidor.",
	UDim2.fromOffset(28, 56),
	UDim2.fromOffset(700, 20),
	Enum.Font.Gotham,
	Color3.fromRGB(150, 170, 200),
	13
)

local btnLobbyClose = Instance.new("TextButton")
btnLobbyClose.AnchorPoint = Vector2.new(1, 0)
btnLobbyClose.Position = UDim2.new(1, -20, 0, 20)
btnLobbyClose.Size = UDim2.fromOffset(34, 34)
btnLobbyClose.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
btnLobbyClose.BorderSizePixel = 0
btnLobbyClose.Font = Enum.Font.GothamBlack
btnLobbyClose.Text = "✕"
btnLobbyClose.TextColor3 = Color3.fromRGB(255, 255, 255)
btnLobbyClose.TextSize = 15
btnLobbyClose.Visible = false
btnLobbyClose.ZIndex = 63
btnLobbyClose.Parent = lobbyCard
roundCorners(btnLobbyClose, 8)

-- ---- Columna izquierda: modos de juego ----
lobbyLabel("MODO DE JUEGO", UDim2.fromOffset(28, 96), UDim2.fromOffset(440, 18), Enum.Font.GothamBold, COLOR_ACCENT, 12)

local MODES = {
	{
		id = "COUNTRIES",
		icon = "🏳️",
		name = "PAÍSES VS PAÍSES",
		desc = "Elige un país real y conquista el mundo. Ideal para jugar con amigos.",
		tag = "RECOMENDADO",
	},
	{
		id = "FREE",
		icon = "🌐",
		name = "LIBRE",
		desc = "Aparece donde quieras en el mapa y expándete desde cero.",
	},
	{
		id = "CONTINENTS",
		icon = "🧭",
		name = "CONTINENTES",
		desc = "Un equipo por continente. Próximamente.",
		disabled = true,
	},
}

local modeCards = {}
for i, m in ipairs(MODES) do
	local card = Instance.new("TextButton")
	card.Name = "Mode_" .. m.id
	card.Position = UDim2.fromOffset(28, 120 + (i - 1) * 108)
	card.Size = UDim2.fromOffset(440, 98)
	card.BackgroundColor3 = COLOR_CARD
	card.BorderSizePixel = 0
	card.AutoButtonColor = not m.disabled
	card.Text = ""
	card.ZIndex = 62
	card.Parent = lobbyCard
	roundCorners(card, 12)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(50, 66, 96)
	stroke.Parent = card

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(12, 0)
	icon.Size = UDim2.fromOffset(58, 98)
	icon.Font = Enum.Font.GothamBold
	icon.Text = m.icon
	icon.TextSize = 36
	icon.TextColor3 = Color3.fromRGB(255, 255, 255)
	icon.ZIndex = 63
	icon.Parent = card

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(76, 14)
	name.Size = UDim2.new(1, -90, 0, 22)
	name.Font = Enum.Font.GothamBlack
	name.Text = m.name
	name.TextSize = 16
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = if m.disabled then Color3.fromRGB(120, 130, 150) else Color3.fromRGB(240, 246, 255)
	name.ZIndex = 63
	name.Parent = card

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromOffset(76, 40)
	desc.Size = UDim2.new(1, -92, 0, 48)
	desc.Font = Enum.Font.Gotham
	desc.Text = m.desc
	desc.TextSize = 12
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextColor3 = Color3.fromRGB(150, 168, 196)
	desc.ZIndex = 63
	desc.Parent = card

	if m.tag then
		local tag = Instance.new("TextLabel")
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -10, 0, 10)
		tag.Size = UDim2.fromOffset(104, 18)
		tag.BackgroundColor3 = Color3.fromRGB(0, 150, 110)
		tag.Font = Enum.Font.GothamBlack
		tag.Text = m.tag
		tag.TextSize = 10
		tag.TextColor3 = Color3.fromRGB(255, 255, 255)
		tag.ZIndex = 64
		tag.Parent = card
		roundCorners(tag, 9)
	end

	modeCards[m.id] = { card = card, stroke = stroke, disabled = m.disabled }
end

-- ---- Columna derecha: mapa, dificultad, bots ----
local rightX = 496
lobbyLabel("MAPA", UDim2.fromOffset(rightX, 96), UDim2.fromOffset(396, 18), Enum.Font.GothamBold, COLOR_ACCENT, 12)

local planetNote = lobbyLabel(
	"",
	UDim2.fromOffset(rightX, 118),
	UDim2.fromOffset(396, 30),
	Enum.Font.Gotham,
	Color3.fromRGB(150, 168, 196),
	11
)
planetNote.TextYAlignment = Enum.TextYAlignment.Top

local PLANETS = {
	{ id = "EARTH", name = "🌍 Tierra" },
	{ id = "PANGEA", name = "🦕 Pangea" },
	{ id = "MARS", name = "🔴 Marte" },
	{ id = "MOON", name = "🌕 Luna" },
	{ id = "VENUS", name = "🪐 Venus" },
	{ id = "ANDROMEDA", name = "🌌 Andrómeda" },
}
local planetChips = {}
for i, p in ipairs(PLANETS) do
	local col = (i - 1) % 3
	local row = (i - 1) // 3
	local chip = Instance.new("TextButton")
	chip.Position = UDim2.fromOffset(rightX + col * 134, 152 + row * 40)
	chip.Size = UDim2.fromOffset(128, 34)
	chip.BackgroundColor3 = COLOR_CHIP
	chip.BorderSizePixel = 0
	chip.Font = Enum.Font.GothamBold
	chip.Text = p.name
	chip.TextColor3 = Color3.fromRGB(255, 255, 255)
	chip.TextSize = 12
	chip.ZIndex = 62
	chip.Parent = lobbyCard
	roundCorners(chip, 8)
	planetChips[p.id] = chip
end

lobbyLabel(
	"DIFICULTAD DE LOS BOTS",
	UDim2.fromOffset(rightX, 246),
	UDim2.fromOffset(396, 18),
	Enum.Font.GothamBold,
	COLOR_ACCENT,
	12
)
local DIFFS = {
	{ id = "EASY", name = "🟢 Fácil" },
	{ id = "NORMAL", name = "🟡 Normal" },
	{ id = "HARD", name = "🟠 Difícil" },
	{ id = "EXTREME", name = "🔴 Extrema" },
}
local diffChips = {}
for i, d in ipairs(DIFFS) do
	local chip = Instance.new("TextButton")
	chip.Position = UDim2.fromOffset(rightX + (i - 1) * 100, 270)
	chip.Size = UDim2.fromOffset(94, 34)
	chip.BackgroundColor3 = COLOR_CHIP
	chip.BorderSizePixel = 0
	chip.Font = Enum.Font.GothamBold
	chip.Text = d.name
	chip.TextColor3 = Color3.fromRGB(255, 255, 255)
	chip.TextSize = 12
	chip.ZIndex = 62
	chip.Parent = lobbyCard
	roundCorners(chip, 8)
	diffChips[d.id] = chip
end

local botsLabel = lobbyLabel(
	"NÚMERO DE BOTS (modo Libre)",
	UDim2.fromOffset(rightX, 316),
	UDim2.fromOffset(396, 18),
	Enum.Font.GothamBold,
	COLOR_ACCENT,
	12
)
local BOT_COUNTS = { 20, 40, 60, 90 }
local botChips = {}
for i, n in ipairs(BOT_COUNTS) do
	local chip = Instance.new("TextButton")
	chip.Position = UDim2.fromOffset(rightX + (i - 1) * 100, 340)
	chip.Size = UDim2.fromOffset(94, 34)
	chip.BackgroundColor3 = COLOR_CHIP
	chip.BorderSizePixel = 0
	chip.Font = Enum.Font.GothamBold
	chip.Text = "🤖 " .. n
	chip.TextColor3 = Color3.fromRGB(255, 255, 255)
	chip.TextSize = 12
	chip.ZIndex = 62
	chip.Parent = lobbyCard
	roundCorners(chip, 8)
	botChips[n] = chip
end

-- Consejos de juego
local tips = lobbyLabel(
	"🖱 Clic en una frontera: atacar   ·   Clic derecho + arrastrar: mover el mapa   ·   Rueda: zoom\n🛡 La IA de Defensa protege tus fronteras; tú decides dónde construir y a quién atacar.",
	UDim2.fromOffset(rightX, 398),
	UDim2.fromOffset(396, 70),
	Enum.Font.Gotham,
	Color3.fromRGB(130, 148, 176),
	11
)
tips.TextYAlignment = Enum.TextYAlignment.Top

-- ---- Barra inferior: estado del servidor y botón JUGAR ----
local lobbyDivider = Instance.new("Frame")
lobbyDivider.Position = UDim2.fromOffset(28, 478)
lobbyDivider.Size = UDim2.fromOffset(864, 1)
lobbyDivider.BackgroundColor3 = Color3.fromRGB(40, 54, 80)
lobbyDivider.BorderSizePixel = 0
lobbyDivider.ZIndex = 62
lobbyDivider.Parent = lobbyCard

local lobbyStatus = lobbyLabel(
	"Conectando con el servidor...",
	UDim2.fromOffset(28, 492),
	UDim2.fromOffset(540, 22),
	Enum.Font.GothamBold,
	Color3.fromRGB(220, 232, 250),
	13
)
local lobbyHint = lobbyLabel(
	"",
	UDim2.fromOffset(28, 516),
	UDim2.fromOffset(540, 44),
	Enum.Font.Gotham,
	Color3.fromRGB(255, 190, 90),
	12
)
lobbyHint.TextYAlignment = Enum.TextYAlignment.Top

local btnPlay = Instance.new("TextButton")
btnPlay.AnchorPoint = Vector2.new(1, 0)
btnPlay.Position = UDim2.new(1, -28, 0, 494)
btnPlay.Size = UDim2.fromOffset(290, 62)
btnPlay.BackgroundColor3 = Color3.fromRGB(0, 190, 120)
btnPlay.BorderSizePixel = 0
btnPlay.Font = Enum.Font.GothamBlack
btnPlay.Text = "▶  JUGAR"
btnPlay.TextColor3 = Color3.fromRGB(255, 255, 255)
btnPlay.TextSize = 22
btnPlay.ZIndex = 63
btnPlay.Parent = lobbyCard
roundCorners(btnPlay, 12)

-- ---- Lógica de selección ----
local function refreshLobby()
	if selMode == "COUNTRIES" then
		selPlanet = "EARTH"
	end
	for id, c in pairs(modeCards) do
		local selected = id == selMode
		c.card.BackgroundColor3 = if selected then COLOR_CARD_SEL else COLOR_CARD
		c.stroke.Color = if selected then COLOR_ACCENT else Color3.fromRGB(50, 66, 96)
		c.card.BackgroundTransparency = if c.disabled then 0.5 else 0
	end
	local freeMode = selMode == "FREE"
	planetNote.Text = if freeMode
		then "Elige el mundo donde jugar."
		else "Mapa: la Tierra real, con sus 164 países y sus fronteras."
	for id, chip in pairs(planetChips) do
		local selected = id == selPlanet
		chip.BackgroundColor3 = if selected then Color3.fromRGB(0, 140, 210) else COLOR_CHIP
		chip.BackgroundTransparency = if freeMode or id == "EARTH" then 0 else 0.6
		chip.TextTransparency = if freeMode or id == "EARTH" then 0 else 0.5
	end
	for id, chip in pairs(diffChips) do
		chip.BackgroundColor3 = if id == selDiff then Color3.fromRGB(0, 170, 115) else COLOR_CHIP
	end
	botsLabel.TextTransparency = if freeMode then 0 else 0.6
	for n, chip in pairs(botChips) do
		chip.BackgroundColor3 = if n == selBots and freeMode then Color3.fromRGB(150, 90, 220) else COLOR_CHIP
		chip.BackgroundTransparency = if freeMode then 0 else 0.6
		chip.TextTransparency = if freeMode then 0 else 0.5
	end
end

for _, m in ipairs(MODES) do
	if not m.disabled then
		modeCards[m.id].card.MouseButton1Click:Connect(function()
			selMode = m.id
			refreshLobby()
		end)
	else
		modeCards[m.id].card.MouseButton1Click:Connect(function()
			showToast("🧭 El modo Continentes llegará pronto", Color3.fromRGB(255, 200, 80))
		end)
	end
end
for _, p in ipairs(PLANETS) do
	planetChips[p.id].MouseButton1Click:Connect(function()
		if selMode == "FREE" then
			selPlanet = p.id
			refreshLobby()
		else
			showToast("Para elegir otros mundos usa el modo Libre", Color3.fromRGB(255, 200, 80))
		end
	end)
end
for _, d in ipairs(DIFFS) do
	diffChips[d.id].MouseButton1Click:Connect(function()
		selDiff = d.id
		refreshLobby()
	end)
end
for _, n in ipairs(BOT_COUNTS) do
	botChips[n].MouseButton1Click:Connect(function()
		if selMode == "FREE" then
			selBots = n
			refreshLobby()
		end
	end)
end

local MODE_NAMES = { COUNTRIES = "Países vs Países", FREE = "Libre" }
local PHASE_NAMES = { SPAWN = "fase de aparición", BATTLE = "en guerra", RUNNING = "en guerra", ENDED = "terminada" }

local function updateLobbyStatus()
	local s = state.stats
	if not s then
		lobbyStatus.Text = "Conectando con el servidor..."
		lobbyHint.Text = ""
		return
	end
	local players = s.players or 1
	lobbyStatus.Text = string.format(
		"👥 %d/%d jugadores   ·   Partida: %s (%s)",
		players,
		s.maxPlayers or 20,
		MODE_NAMES[s.mode or "FREE"] or "Libre",
		PHASE_NAMES[s.phase or ""] or "..."
	)
	local isHost = s.hostId == player.UserId
	if players > 1 and not isHost and s.phase ~= "ENDED" then
		lobbyHint.Text = "Solo el anfitrión puede cambiar el modo: entrarás a la partida en curso."
		btnPlay.Text = "▶  ENTRAR"
	else
		lobbyHint.Text = ""
		btnPlay.Text = "▶  JUGAR"
	end
end

local function showLobby(visible)
	lobbyScreen.Visible = visible
	btnLobbyClose.Visible = visible and state.initialized
	if visible then
		refreshLobby()
		updateLobbyStatus()
	end
end

btnPlay.MouseButton1Click:Connect(function()
	showLobby(false)
	WorldCommand:FireServer({
		a = "PLAY",
		planet = selPlanet,
		bots = selBots,
		difficulty = selDiff,
		mode = selMode,
	})
	showToast("Cargando partida...", Color3.fromRGB(255, 215, 0))
end)
btnLobbyClose.MouseButton1Click:Connect(function()
	showLobby(false)
end)
btnLobby.MouseButton1Click:Connect(function()
	showLobby(not lobbyScreen.Visible)
end)

showLobby(true)

-- ============================================================================
-- RENDERIZADO DEL MAPA CON EDITABLEIMAGE
-- ============================================================================
-- ----------------------------------------------------------------------------
-- RESPALDO: mapa por bloques de color (no requiere el permiso EditableImage).
-- Cada bloque agrupa BLOCK x BLOCK celdas: color medio de la foto satelital + tinte del país dominante.
-- BLOCK debe dividir a 960 y 400 (4, 5, 8, 10, 16). Menor = más detalle y más rectángulos en pantalla.
-- ----------------------------------------------------------------------------
local BLOCK = 5

-- Mapa de la Tierra en alta resolución (2x2 px por celda), generado con
-- `python tools/generate_relief_style.py --tiles` y subido a Roblox. Si cambias el mapa, sube de nuevo las
-- teselas y actualiza estos ids. Los otros mundos (Marte, Luna...) no tienen teselas y usan solo bloques.
local EARTH_TILES = { "rbxassetid://122231731451803", "rbxassetid://115442226521313" }
-- Fronteras entre países (PNG transparente de 2x2 px por celda), de `python tools/build_countries.py --borders`
local BORDER_TILES = { "rbxassetid://77774919074501", "rbxassetid://120746897652823" }
local tileLayer = nil
local borderLayer = nil

local function makeTileLayer(name, ids, zIndex)
	local layer = Instance.new("Frame")
	layer.Name = name
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ZIndex = zIndex
	for i, id in ipairs(ids) do
		local img = Instance.new("ImageLabel")
		img.Name = "Tile" .. i
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Image = id
		img.ResampleMode = Enum.ResamplerMode.Pixelated -- píxeles nítidos, celda por celda
		img.Position = UDim2.fromScale((i - 1) / #ids, 0)
		img.Size = UDim2.fromScale(1 / #ids + 0.002, 1) -- solape para tapar la costura entre teselas
		img.Parent = layer
	end
	layer.Parent = mapCanvas
	return layer
end

local function setTilesVisible(visible)
	if visible and not tileLayer then
		tileLayer = makeTileLayer("TileLayer", EARTH_TILES, -8) -- debajo de los bloques de color de los países
		borderLayer = makeTileLayer("BorderLayer", BORDER_TILES, -3) -- encima del tinte, debajo de marcadores
	end
	if tileLayer then
		tileLayer.Visible = visible
	end
	if borderLayer then
		borderLayer.Visible = visible
	end
end

local function initBlocks(w, h)
	mapImage.Visible = false
	state.blockMode = true
	state.useTiles = state.planet == "EARTH"
	setTilesVisible(state.useTiles)
	local bw, bh = w // BLOCK, h // BLOCK
	if state.blocks and state.blockW == bw and state.blockH == bh then
		if state.blockLayer then
			state.blockLayer.Visible = true
		end
		return
	end
	if state.blockLayer then
		state.blockLayer:Destroy()
	end

	local layer = Instance.new("Frame")
	layer.Name = "BlockLayer"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ZIndex = -5 -- siempre por debajo de marcadores, efectos y cursor

	local blocks = table.create(bw * bh)
	for by = 0, bh - 1 do
		for bx = 0, bw - 1 do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = OCEAN_COLOR
			f.Position = UDim2.fromScale(bx / bw, by / bh)
			-- Opacos: ligero solape para evitar costuras. Semitransparentes (sobre las teselas): sin solape,
			-- porque donde dos bloques se superponen el color se oscurece y dibuja una rejilla.
			if state.useTiles then
				f.Size = UDim2.fromScale(1 / bw, 1 / bh)
			else
				f.Size = UDim2.fromScale(1 / bw + 0.0005, 1 / bh + 0.0008)
			end
			f.Parent = layer
			blocks[by * bw + bx + 1] = { frame = f, r = 14, g = 28, b = 52 }
		end
	end
	layer.Parent = mapCanvas

	state.blocks = blocks
	state.blockLayer = layer
	state.blockW = bw
	state.blockH = bh
	state.dirtyBlocks = {}
	warn(
		"[WorldClient] EditableImage no disponible: usando mapa por bloques de " .. BLOCK .. "x" .. BLOCK .. " celdas."
	)
end

-- Animación de propagación: bloques recién conquistados destellan y se asientan en 0,9 s
local flashing = {}
local flashCount = 0
local FLASH_TIME = 0.9
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for b, t0 in pairs(flashing) do
		local a = (now - t0) / FLASH_TIME
		if a >= 1 then
			b.frame.BackgroundColor3 = b.finalColor
			b.frame.BackgroundTransparency = b.finalTransp
			flashing[b] = nil
			flashCount -= 1
		else
			b.frame.BackgroundColor3 = b.finalColor:Lerp(Color3.new(1, 1, 1), 0.65 * (1 - a))
			b.frame.BackgroundTransparency = 0.05 + (b.finalTransp - 0.05) * a
		end
	end
end)

local function recolorBlock(bi)
	local b = state.blocks[bi]
	if not b then
		return
	end
	local bx = (bi - 1) % state.blockW
	local by = (bi - 1) // state.blockW
	local w = state.w
	local owner = state.owner
	local counts = {}
	local bestId, bestCount = 0, 0
	local x0, y0 = bx * BLOCK, by * BLOCK
	for y = y0, y0 + BLOCK - 1 do
		local row = y * w
		for x = x0, x0 + BLOCK - 1 do
			local o = buffer.readu8(owner, row + x)
			if o ~= 0 then
				local c = (counts[o] or 0) + 1
				counts[o] = c
				if c > bestCount then
					bestCount = c
					bestId = o
				end
			end
		end
	end

	local r, g, bl = b.r, b.g, b.b
	local n = if bestId ~= 0 then state.rosterById[bestId] else nil
	-- Con las teselas de fondo, el bloque solo se tiñe (semitransparente) donde un país domina la celda
	if state.useTiles and n and bestCount < 8 then
		n = nil
	end
	local transparency = 0
	if n then
		local isMe = bestId == state.myId
		if state.useTiles then
			r, g, bl = n.r or 200, n.g or 200, n.b or 200
			-- Tú y los jugadores humanos se ven con más fuerza que los bots
			transparency = if isMe then 0.4 elseif n.bot == false then 0.45 else 0.58
		else
			local alpha = math.min(if isMe then 0.8 else 0.64, bestCount / (BLOCK * BLOCK) * 1.6)
			r = r * (1 - alpha) + (n.r or 200) * alpha
			g = g * (1 - alpha) + (n.g or 200) * alpha
			bl = bl * (1 - alpha) + (n.b or 200) * alpha
		end
		if isMe then
			r, g, bl = r * 1.12, g * 1.12, bl * 1.12
		end
	elseif state.useTiles then
		transparency = 1
	end
	local finalColor = Color3.fromRGB(
		math.clamp(math.floor(r), 0, 255),
		math.clamp(math.floor(g), 0, 255),
		math.clamp(math.floor(bl), 0, 255)
	)
	-- Propagación: al cambiar de dueño, el bloque "destella" claro y se asienta en su color (ver Heartbeat arriba)
	local ownerNow = if n then bestId else 0
	if state.animReady and n and b.owner ~= ownerNow and flashCount < 900 then
		b.finalColor, b.finalTransp = finalColor, transparency
		b.frame.BackgroundColor3 = finalColor:Lerp(Color3.new(1, 1, 1), 0.65)
		b.frame.BackgroundTransparency = 0.05
		if not flashing[b] then
			flashCount += 1
		end
		flashing[b] = os.clock()
	else
		if flashing[b] then
			flashing[b] = nil
			flashCount -= 1
		end
		b.frame.BackgroundColor3 = finalColor
		b.frame.BackgroundTransparency = transparency
	end
	b.owner = ownerNow
end

local function markBlockDirty(idx)
	local w = state.w
	local bi = ((idx // w) // BLOCK) * state.blockW + ((idx % w) // BLOCK) + 1
	state.dirtyBlocks[bi] = true
end

local function initEditableImage(w, h)
	state.w = w
	state.h = h

	if not state.editableImage then
		local ok, img = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
		end)
		-- Crear el objeto no basta: sin el permiso de la experiencia, escribir/dibujar falla. Se prueba una escritura.
		local usable = false
		if ok and img then
			local okWrite, errWrite = pcall(function()
				img:WritePixelsBuffer(Vector2.zero, Vector2.new(1, 1), buffer.create(4))
			end)
			usable = okWrite
			if not okWrite then
				warn("EditableImage sin permiso de escritura:", errWrite)
			end
		end
		if usable then
			state.editableImage = img
			mapImage.ImageContent = Content.fromObject(img)
		else
			warn("Fallo al crear EditableImage:", img)
			initBlocks(w, h)
			return
		end
	end
	state.blockMode = false
	mapImage.Visible = true
	setTilesVisible(false)
	if state.blockLayer then
		state.blockLayer.Visible = false
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
	if state.blockMode then
		markBlockDirty(idx)
		return
	end
	if not state.editableImage or not state.pixelBuffer or not state.baseBuffer then
		return
	end

	local offset4 = idx * 4
	local offset3 = idx * 3

	local baseR = buffer.readu8(state.baseBuffer, offset3)
	local baseG = buffer.readu8(state.baseBuffer, offset3 + 1)
	local baseB = buffer.readu8(state.baseBuffer, offset3 + 2)

	local r, g, b = baseR, baseG, baseB

	if ownerId > 0 then
		local n = state.rosterById[ownerId]
		if n then
			local nr = n.r or 200
			local ng = n.g or 200
			local nb = n.b or 200

			-- Detectar si es celda fronteriza
			local w, h = state.w, state.h
			local x = idx % w
			local y = idx // w
			local isBorder = false

			local leftIdx = y * w + (if x == 0 then w - 1 else x - 1)
			local rightIdx = y * w + (if x == w - 1 then 0 else x + 1)
			if buffer.readu8(state.owner, leftIdx) ~= ownerId or buffer.readu8(state.owner, rightIdx) ~= ownerId then
				isBorder = true
			elseif y > 0 and buffer.readu8(state.owner, (y - 1) * w + x) ~= ownerId then
				isBorder = true
			elseif y < h - 1 and buffer.readu8(state.owner, (y + 1) * w + x) ~= ownerId then
				isBorder = true
			end

			local isMe = (ownerId == state.myId)

			if isBorder then
				-- Fronteras marcadas con color nítido y saturado
				if isMe then
					-- Borde dorado neón resplandeciente para el jugador
					r = 255
					g = 235
					b = 40
				else
					r = math.min(255, math.floor(nr * 1.35))
					g = math.min(255, math.floor(ng * 1.35))
					b = math.min(255, math.floor(nb * 1.35))
				end
			else
				-- Interior: Mezcla armoniosa que permite ver el terreno y la geografía
				local alpha = isMe and 0.68 or 0.55
				r = math.floor(nr * alpha + baseR * (1 - alpha))
				g = math.floor(ng * alpha + baseG * (1 - alpha))
				b = math.floor(nb * alpha + baseB * (1 - alpha))

				if isMe then
					r = math.min(255, math.floor(r * 1.15))
					g = math.min(255, math.floor(g * 1.15))
					b = math.min(255, math.floor(b * 1.15))
				end
			end
		end
	end

	buffer.writeu8(state.pixelBuffer, offset4, r)
	buffer.writeu8(state.pixelBuffer, offset4 + 1, g)
	buffer.writeu8(state.pixelBuffer, offset4 + 2, b)
	buffer.writeu8(state.pixelBuffer, offset4 + 3, 255)
end

local fullRedraw -- declarada aquí porque flushImage la usa al cambiar al modo por bloques

local function flushImage()
	if state.blockMode then
		for bi in pairs(state.dirtyBlocks) do
			recolorBlock(bi)
			state.dirtyBlocks[bi] = nil
		end
		return
	end
	if state.editableImage and state.pixelBuffer then
		local ok, err = pcall(function()
			state.editableImage:WritePixelsBuffer(Vector2.zero, Vector2.new(state.w, state.h), state.pixelBuffer)
		end)
		if not ok then
			warn("[WorldClient] EditableImage falló al dibujar (" .. tostring(err) .. "): usando mapa por bloques")
			state.editableImage = nil
			initBlocks(state.w, state.h)
			fullRedraw()
		end
	end
end

function fullRedraw()
	if state.blockMode then
		if not state.blocks or not state.owner or not state.baseBuffer then
			return
		end
		state.animReady = false -- el primer dibujado no debe animarse
		-- Color base de cada bloque = media de la foto satelital (incluye mar y costas)
		local w, base = state.w, state.baseBuffer
		local area = BLOCK * BLOCK
		for bi = 1, state.blockW * state.blockH do
			local bx = (bi - 1) % state.blockW
			local by = (bi - 1) // state.blockW
			local sr, sg, sb = 0, 0, 0
			for y = by * BLOCK, by * BLOCK + BLOCK - 1 do
				for x = bx * BLOCK, bx * BLOCK + BLOCK - 1 do
					local o = (y * w + x) * 3
					sr += buffer.readu8(base, o)
					sg += buffer.readu8(base, o + 1)
					sb += buffer.readu8(base, o + 2)
				end
			end
			local b = state.blocks[bi]
			b.r, b.g, b.b = sr / area, sg / area, sb / area
			state.dirtyBlocks[bi] = true
		end
		flushImage()
		state.animReady = true -- a partir de aquí, las conquistas se animan
		return
	end
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
local markerLabels = {}

local function clearMarkers()
	for _, m in pairs(markerPool) do
		m:Destroy()
	end
	table.clear(markerPool)
	table.clear(markerLabels)
end

-- Con zoom bajo solo se rotulan tú, los jugadores y los países más grandes; al acercar se ven todos
local function applyLabelZoom()
	for _, m in ipairs(markerLabels) do
		m.label.Visible = m.always or state.zoom >= 1.3
	end
end

local function updateMarkers()
	clearMarkers()
	if not state.roster then
		return
	end

	-- Los 25 países con más territorio siempre llevan rótulo
	local bySize = {}
	for _, n in ipairs(state.roster) do
		table.insert(bySize, n)
	end
	table.sort(bySize, function(a, b)
		return (a.cells or 0) > (b.cells or 0)
	end)
	local bigIds = {}
	for i = 1, math.min(25, #bySize) do
		bigIds[bySize[i].id] = true
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
			local isHuman = n.bot == false
			nameLbl.Font = if isMe or isHuman then Enum.Font.GothamBlack else Enum.Font.GothamBold
			nameLbl.Text = (if isMe then "👑 " elseif isHuman then "👤 " else "") .. n.name
			-- El rótulo toma el color del país (aclarado) y lleva contorno oscuro para leerse sobre cualquier fondo
			nameLbl.TextColor3 = if isMe
				then Color3.fromRGB(255, 230, 50)
				else n.color:Lerp(Color3.new(1, 1, 1), if isHuman then 0.25 else 0.55)
			nameLbl.TextStrokeTransparency = 0.35
			nameLbl.TextStrokeColor3 = Color3.fromRGB(8, 10, 16)
			nameLbl.TextSize = if isMe or isHuman then 12 else 9
			nameLbl.ZIndex = 11
			nameLbl.Parent = marker

			table.insert(markerPool, marker)
			table.insert(markerLabels, { label = nameLbl, always = isMe or isHuman or bigIds[n.id] == true })
		end
	end
	applyLabelZoom()
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

	-- Fase de Spawn (o, en modo Países, quien todavía no tiene país)
	local needsSpawn = state.stats ~= nil and state.stats.phase == "SPAWN"
	if state.mode == "COUNTRIES" and not state.me.alive and not (state.stats and state.stats.phase == "ENDED") then
		needsSpawn = true
	end
	if needsSpawn then
		WorldCommand:FireServer({ a = "SPAWN", cell = cell })
		if state.mode == "COUNTRIES" then
			showToast("🌍 Intentando tomar ese país...", Color3.fromRGB(0, 220, 255))
		else
			showToast("📍 Capital establecida en la celda " .. cell, Color3.fromRGB(0, 220, 255))
		end
		return
	end

	-- Fase de Batalla
	if state.actionMode == "ATTACK" then
		WorldCommand:FireServer({ a = "ATTACK", cell = cell, ratio = state.attackRatio })
		-- Feedback visual inmediato: efecto onda de ataque en el cursor
		local cx = cell % state.w
		local cy = math.floor(cell / state.w)
		local ripple = Instance.new("Frame")
		ripple.AnchorPoint = Vector2.new(0.5, 0.5)
		ripple.Position = UDim2.fromScale((cx + 0.5) / state.w, (cy + 0.5) / state.h)
		ripple.Size = UDim2.fromScale(6 / state.w, 6 / state.h)
		ripple.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		ripple.BackgroundTransparency = 0.2
		ripple.BorderSizePixel = 0
		ripple.ZIndex = 25
		ripple.Parent = mapCanvas

		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = ripple

		local tw = TweenService:Create(ripple, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(28 / state.w, 28 / state.h),
			BackgroundTransparency = 1,
		})
		tw:Play()
		tw.Completed:Connect(function()
			ripple:Destroy()
		end)
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
	applyLabelZoom()
end

-- Controles del mapa (como en los juegos de conquista):
--   · Arrastrar con el botón izquierdo (o un dedo) mueve el mapa; un clic corto ataca / construye / elige.
--   · Botón derecho o central: arrastrar también mueve el mapa.
--   · Rueda del ratón o pellizco: zoom hacia el cursor.   · WASD o flechas: mover.   · Q / E: zoom.
local PAN_THRESHOLD = 6 -- píxeles de arrastre a partir de los cuales deja de ser un clic
local drag =
	{ active = false, kind = "click", start = Vector2.zero, startPan = Vector2.zero, moved = false, input = nil }

-- Evita perder el mapa fuera de la pantalla
local function clampPan()
	local vs = mapContainer.AbsoluteSize
	local maxX = BASE_WIDTH * state.zoom / 2 + vs.X / 2 - 140
	local maxY = BASE_HEIGHT * state.zoom / 2 + vs.Y / 2 - 140
	state.pan = Vector2.new(math.clamp(state.pan.X, -maxX, maxX), math.clamp(state.pan.Y, -maxY, maxY))
end

-- Zoom manteniendo fijo el punto del mapa que hay bajo el cursor
local function zoomAt(screenPos, factor)
	local newZoom = math.clamp(state.zoom * factor, 0.25, 8.0)
	local f = newZoom / state.zoom
	local center = mapCanvas.AbsolutePosition + mapCanvas.AbsoluteSize / 2
	state.pan = state.pan + (screenPos - center) * (1 - f)
	state.zoom = newZoom
	clampPan()
	updateMapTransform()
end

mapContainer.InputBegan:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
		drag.active, drag.kind, drag.moved, drag.input = true, "pan", true, input
	elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		drag.active, drag.kind, drag.moved, drag.input = true, "click", false, input
	else
		return
	end
	drag.start = Vector2.new(input.Position.X, input.Position.Y)
	drag.startPan = state.pan
end)

UserInputService.InputEnded:Connect(function(input)
	if not drag.active then
		return
	end
	local t = input.UserInputType
	local pressesPan = drag.kind == "pan"
		and (t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3)
	local pressesClick = drag.kind == "click"
		and (t == Enum.UserInputType.MouseButton1 or (t == Enum.UserInputType.Touch and input == drag.input))
	if not (pressesPan or pressesClick) then
		return
	end
	if pressesClick and not drag.moved then
		local cell = screenToCell(Vector2.new(input.Position.X, input.Position.Y))
		if cell >= 0 then
			handleMapClick(cell)
		end
	end
	drag.active = false
end)

UserInputService.InputChanged:Connect(function(input)
	local t = input.UserInputType
	if
		drag.active
		and (t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == drag.input))
	then
		local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.start
		if not drag.moved and delta.Magnitude >= PAN_THRESHOLD then
			drag.moved = true
		end
		if drag.moved then
			state.pan = drag.startPan + delta
			clampPan()
			updateMapTransform()
		end
	elseif t == Enum.UserInputType.MouseWheel then
		zoomAt(UserInputService:GetMouseLocation(), if input.Position.Z > 0 then 1.15 else 0.87)
	end
end)

-- Pellizco con dos dedos: zoom (cancela el clic del primer dedo)
local pinchStartZoom = 1
UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, inputState)
	drag.moved = true
	if inputState == Enum.UserInputState.Begin then
		pinchStartZoom = state.zoom
	else
		local target = math.clamp(pinchStartZoom * scale, 0.25, 8.0)
		zoomAt(mapContainer.AbsoluteSize / 2, target / state.zoom)
	end
end)

-- Teclado: WASD / flechas mueven la vista; Q / E acercan y alejan
RunService.RenderStepped:Connect(function(dt)
	if UserInputService:GetFocusedTextBox() or lobbyScreen.Visible then
		return
	end
	local function down(a, b)
		return UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b)
	end
	local dx = (if down(Enum.KeyCode.A, Enum.KeyCode.Left) then 1 else 0)
		- (if down(Enum.KeyCode.D, Enum.KeyCode.Right) then 1 else 0)
	local dy = (if down(Enum.KeyCode.W, Enum.KeyCode.Up) then 1 else 0)
		- (if down(Enum.KeyCode.S, Enum.KeyCode.Down) then 1 else 0)
	if dx ~= 0 or dy ~= 0 then
		state.pan = state.pan + Vector2.new(dx, dy) * 800 * dt
		clampPan()
		updateMapTransform()
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then
		zoomAt(mapContainer.AbsoluteSize / 2, 1 + 1.5 * dt)
	elseif UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		zoomAt(mapContainer.AbsoluteSize / 2, 1 / (1 + 1.5 * dt))
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

-- ============================================================================
-- TOOLTIP DE TERRITORIO: al pasar el ratón por el mapa muestra de quién es esa tierra
-- ============================================================================
local PERSONA_LABELS = {
	CONQUEROR = "⚔️ Conquistador",
	MERCHANT = "💰 Mercader",
	TURTLE = "🛡️ Defensor",
	OPPORTUNIST = "🦊 Oportunista",
	ADMIRAL = "⚓ Navegante",
	NUKER = "☢️ Estratega Nuclear",
}

local hoverTip = Instance.new("Frame")
hoverTip.Name = "HoverTip"
hoverTip.Size = UDim2.fromOffset(210, 92)
hoverTip.BackgroundColor3 = Color3.fromRGB(12, 18, 30)
hoverTip.BackgroundTransparency = 0.05
hoverTip.BorderSizePixel = 0
hoverTip.Visible = false
hoverTip.ZIndex = 50
hoverTip.Parent = root

local hoverTipCorner = Instance.new("UICorner")
hoverTipCorner.CornerRadius = UDim.new(0, 8)
hoverTipCorner.Parent = hoverTip

local hoverTipStroke = Instance.new("UIStroke")
hoverTipStroke.Thickness = 2
hoverTipStroke.Parent = hoverTip

local hoverSwatch = Instance.new("Frame")
hoverSwatch.Position = UDim2.fromOffset(10, 11)
hoverSwatch.Size = UDim2.fromOffset(14, 14)
hoverSwatch.BorderSizePixel = 0
hoverSwatch.ZIndex = 51
hoverSwatch.Parent = hoverTip
local hoverSwatchStroke = Instance.new("UIStroke")
hoverSwatchStroke.Color = Color3.fromRGB(240, 245, 255)
hoverSwatchStroke.Parent = hoverSwatch

local function tipLabel(y, size, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(30, y)
	l.Size = UDim2.new(1, -38, 0, size + 4)
	l.Font = font
	l.TextSize = size
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.TextColor3 = Color3.fromRGB(235, 242, 255)
	l.ZIndex = 51
	l.Parent = hoverTip
	return l
end
local tipName = tipLabel(8, 14, Enum.Font.GothamBlack)
local tipKind = tipLabel(30, 12, Enum.Font.GothamBold)
local tipCountry = tipLabel(48, 11, Enum.Font.Gotham)
local tipStats = tipLabel(66, 11, Enum.Font.Gotham)
tipCountry.TextColor3 = Color3.fromRGB(160, 180, 210)
tipStats.TextColor3 = Color3.fromRGB(200, 215, 240)

local tipOwner, tipStamp = -1, 0
local function describeNation(ownerId)
	local n = state.rosterById[ownerId]
	local human = state.humanById and state.humanById[ownerId]
	local isMe = ownerId == state.myId
	local color = if n and n.color then n.color else Color3.fromRGB(150, 150, 150)
	local name = if human then human.name elseif n then n.name else "Nación " .. ownerId
	local kind, kindColor
	if isMe then
		kind, kindColor = "👑 Tú", Color3.fromRGB(255, 225, 60)
	elseif human or (n and n.bot == false) then
		kind, kindColor = "👤 Jugador", Color3.fromRGB(120, 235, 160)
	else
		kind = "🤖 Bot · " .. (PERSONA_LABELS[n and n.persona or ""] or "IA")
		kindColor = Color3.fromRGB(255, 170, 130)
	end
	-- País del que gobierna (modo Países): el del bot original, o el que eligió el jugador
	local country = nil
	local cid = if human then human.cid elseif n then n.countryId else nil
	if cid then
		for _, r in ipairs(state.roster) do
			if r.countryId == cid and r.bot ~= false then
				country = r.name
				break
			end
		end
	end
	local st = state.statById and state.statById[ownerId]
	local stats = if st
		then string.format("⚔️ %s tropas · %d celdas", tostring(st.troops or 0), st.cells or 0)
		else ""
	return name, color, kind, kindColor, country, stats
end

RunService.RenderStepped:Connect(function()
	if not state.initialized or lobbyScreen.Visible or not state.owner then
		hoverTip.Visible = false
		return
	end
	local mp = Vector2.new(mouse.X, mouse.Y)
	local cell = screenToCell(mp)
	if cell < 0 or cell >= state.w * state.h then
		hoverTip.Visible = false
		return
	end
	local ownerId = buffer.readu8(state.owner, cell)
	if ownerId == 0 then
		hoverTip.Visible = false
		return
	end
	-- El texto solo se recalcula al cambiar de dueño o cada medio segundo
	local now = os.clock()
	if ownerId ~= tipOwner or now - tipStamp > 0.5 then
		tipOwner, tipStamp = ownerId, now
		local name, color, kind, kindColor, country, stats = describeNation(ownerId)
		tipName.Text = name
		tipKind.Text = kind
		tipKind.TextColor3 = kindColor
		tipCountry.Text = if country and country ~= name then "🏳️ " .. country else ""
		tipStats.Text = stats
		hoverSwatch.BackgroundColor3 = color
		hoverTipStroke.Color = color
	end
	local vs = root.AbsoluteSize
	local x = math.min(mp.X + 18, vs.X - 220)
	local y = math.min(mp.Y + 18, vs.Y - 100)
	hoverTip.Position = UDim2.fromOffset(x, y)
	hoverTip.Visible = true
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
-- LISTA DE PAÍSES POR CONTINENTE (modo Países vs Países)
-- Permite elegir país con buscador, ver quién ya eligió cada uno y coordinarse con amigos.
-- ============================================================================
local function centerOnCell(cell)
	local cx = cell % state.w
	local cy = math.floor(cell / state.w)
	local normX = (cx + 0.5) / state.w - 0.5
	local normY = (cy + 0.5) / state.h - 0.5
	state.pan = Vector2.new(-normX * BASE_WIDTH * state.zoom, -normY * BASE_HEIGHT * state.zoom)
	updateMapTransform()
end

local CONTINENT_NAMES = {
	[1] = "🌍 África",
	[2] = "🧊 Antártida",
	[3] = "🌏 Asia",
	[4] = "🏰 Europa",
	[5] = "🌎 Norteamérica",
	[6] = "🏝️ Oceanía",
	[7] = "🌎 Sudamérica",
}
local CONTINENT_ORDER = { 5, 7, 4, 1, 3, 6, 2 }

local ACCENTS = {
	["á"] = "a",
	["é"] = "e",
	["í"] = "i",
	["ó"] = "o",
	["ú"] = "u",
	["ü"] = "u",
	["ñ"] = "n",
	["Á"] = "a",
	["É"] = "e",
	["Í"] = "i",
	["Ó"] = "o",
	["Ú"] = "u",
	["Ñ"] = "n",
}
local function fold(s)
	s = string.lower(s)
	for from, to in pairs(ACCENTS) do
		s = string.gsub(s, from, to)
	end
	return s
end

local btnCountries = Instance.new("TextButton")
btnCountries.Name = "BtnCountries"
btnCountries.AnchorPoint = Vector2.new(1, 0.5)
btnCountries.Position = UDim2.new(1, -266, 0.5, 0)
btnCountries.Size = UDim2.fromOffset(110, 34)
btnCountries.BackgroundColor3 = Color3.fromRGB(30, 90, 70)
btnCountries.Font = Enum.Font.GothamBold
btnCountries.Text = "🌍 Países"
btnCountries.TextColor3 = Color3.fromRGB(255, 255, 255)
btnCountries.TextSize = 12
btnCountries.BorderSizePixel = 0
btnCountries.Visible = false
btnCountries.ZIndex = 21
btnCountries.Parent = topBar

local btnCountriesCorner = Instance.new("UICorner")
btnCountriesCorner.CornerRadius = UDim.new(0, 6)
btnCountriesCorner.Parent = btnCountries

local countryPanel = Instance.new("Frame")
countryPanel.Name = "CountryPanel"
countryPanel.Position = UDim2.fromOffset(12, 80)
countryPanel.Size = UDim2.new(0, 290, 1, -210)
countryPanel.BackgroundColor3 = Color3.fromRGB(14, 20, 34)
countryPanel.BackgroundTransparency = 0.04
countryPanel.BorderSizePixel = 0
countryPanel.Visible = false
countryPanel.ZIndex = 30
countryPanel.Parent = root

local countryPanelCorner = Instance.new("UICorner")
countryPanelCorner.CornerRadius = UDim.new(0, 10)
countryPanelCorner.Parent = countryPanel

local countryPanelStroke = Instance.new("UIStroke")
countryPanelStroke.Color = Color3.fromRGB(60, 140, 120)
countryPanelStroke.Thickness = 1.5
countryPanelStroke.Parent = countryPanel

local countryTitle = Instance.new("TextLabel")
countryTitle.Size = UDim2.new(1, -16, 0, 26)
countryTitle.Position = UDim2.fromOffset(8, 6)
countryTitle.BackgroundTransparency = 1
countryTitle.Font = Enum.Font.GothamBlack
countryTitle.Text = "🌍 ELIGE TU PAÍS"
countryTitle.TextColor3 = Color3.fromRGB(120, 230, 190)
countryTitle.TextSize = 14
countryTitle.TextXAlignment = Enum.TextXAlignment.Left
countryTitle.ZIndex = 31
countryTitle.Parent = countryPanel

local countrySearch = Instance.new("TextBox")
countrySearch.Size = UDim2.new(1, -16, 0, 28)
countrySearch.Position = UDim2.fromOffset(8, 34)
countrySearch.BackgroundColor3 = Color3.fromRGB(26, 36, 56)
countrySearch.BorderSizePixel = 0
countrySearch.Font = Enum.Font.Gotham
countrySearch.PlaceholderText = "🔍 Buscar país..."
countrySearch.PlaceholderColor3 = Color3.fromRGB(130, 145, 170)
countrySearch.Text = ""
countrySearch.TextColor3 = Color3.fromRGB(240, 245, 255)
countrySearch.TextSize = 12
countrySearch.TextXAlignment = Enum.TextXAlignment.Left
countrySearch.ClearTextOnFocus = false
countrySearch.ZIndex = 31
countrySearch.Parent = countryPanel

local countrySearchCorner = Instance.new("UICorner")
countrySearchCorner.CornerRadius = UDim.new(0, 6)
countrySearchCorner.Parent = countrySearch

local countrySearchPad = Instance.new("UIPadding")
countrySearchPad.PaddingLeft = UDim.new(0, 8)
countrySearchPad.Parent = countrySearch

local countryScroll = Instance.new("ScrollingFrame")
countryScroll.Position = UDim2.fromOffset(6, 68)
countryScroll.Size = UDim2.new(1, -12, 1, -68 - 56)
countryScroll.BackgroundTransparency = 1
countryScroll.BorderSizePixel = 0
countryScroll.ScrollBarThickness = 6
countryScroll.CanvasSize = UDim2.new()
countryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
countryScroll.ZIndex = 31
countryScroll.Parent = countryPanel

local countryList = Instance.new("UIListLayout")
countryList.SortOrder = Enum.SortOrder.LayoutOrder
countryList.Padding = UDim.new(0, 2)
countryList.Parent = countryScroll

local countryConfirm = Instance.new("TextButton")
countryConfirm.AnchorPoint = Vector2.new(0.5, 1)
countryConfirm.Position = UDim2.new(0.5, 0, 1, -8)
countryConfirm.Size = UDim2.new(1, -16, 0, 40)
countryConfirm.BackgroundColor3 = Color3.fromRGB(40, 52, 76)
countryConfirm.BorderSizePixel = 0
countryConfirm.Font = Enum.Font.GothamBlack
countryConfirm.Text = "Selecciona un país de la lista"
countryConfirm.TextColor3 = Color3.fromRGB(200, 210, 230)
countryConfirm.TextSize = 12
countryConfirm.TextWrapped = true
countryConfirm.ZIndex = 32
countryConfirm.Parent = countryPanel

local countryConfirmCorner = Instance.new("UICorner")
countryConfirmCorner.CornerRadius = UDim.new(0, 8)
countryConfirmCorner.Parent = countryConfirm

-- Adaptación a la pantalla: escala los paneles fijos (HUD, ranking, lista de países) y oculta lo que no cabe
local countryScale = Instance.new("UIScale")
countryScale.Parent = countryPanel

local function fitUI()
	local vs = root.AbsoluteSize
	if vs.X <= 0 or vs.Y <= 0 then
		return
	end
	local s = math.clamp(math.min(vs.X / 1100, vs.Y / 700), 0.5, 1.1)
	hudScale.Scale = s
	leaderScale.Scale = s
	countryScale.Scale = s
	-- La altura se calcula en píxeles "sin escala" para que el panel llene el espacio libre sin desbordar
	countryPanel.Size = UDim2.fromOffset(290, math.max(220, (vs.Y - 210) / s))
	titleLabel.Visible = vs.X >= 1180 -- en pantallas estrechas el título chocaría con los botones
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitUI)
fitUI()

-- Estado de la lista
local cp = { rows = {}, headers = {}, collapsed = {}, selected = nil, taken = {}, built = false }

local function applyCountryFilter()
	local query = fold(countrySearch.Text)
	local anyInCont = {}
	for _, r in ipairs(cp.rows) do
		local show
		if query ~= "" then
			show = string.find(r.folded, query, 1, true) ~= nil
		else
			show = not cp.collapsed[r.cont]
		end
		r.btn.Visible = show
		if show then
			anyInCont[r.cont] = true
		end
	end
	for cont, h in pairs(cp.headers) do
		local searching = query ~= ""
		h.btn.Visible = (not searching) or anyInCont[cont] == true
		local open = searching or not cp.collapsed[cont]
		h.btn.Text = (if open then "▼ " else "▶ ") .. h.label
	end
end

local function updateCountryPanel()
	if not cp.built then
		return
	end
	local taken = {}
	if state.stats and state.stats.taken then
		for _, t in ipairs(state.stats.taken) do
			taken[t.cid] = t
		end
	end
	cp.taken = taken

	for _, r in ipairs(cp.rows) do
		local t = taken[r.n.countryId]
		if t then
			local mine = t.nid == state.myId
			r.status.Text = if mine then "⭐ TÚ" else "🔒 " .. t.name
			r.status.TextColor3 = if mine then Color3.fromRGB(255, 220, 0) else Color3.fromRGB(255, 150, 120)
			r.btn.BackgroundColor3 = if mine then Color3.fromRGB(72, 60, 10) else Color3.fromRGB(24, 28, 40)
		else
			r.status.Text = tostring(r.n.cells or 0) .. " celdas"
			r.status.TextColor3 = Color3.fromRGB(140, 160, 190)
			r.btn.BackgroundColor3 = if cp.selected == r.n
				then Color3.fromRGB(0, 110, 170)
				else Color3.fromRGB(30, 42, 64)
		end
	end

	local alive = state.me and state.me.alive
	if alive then
		-- Al conseguir país, la lista se cierra sola una vez (se reabre con el botón "🌍 Países")
		if not cp.autoHidden then
			cp.autoHidden = true
			countryPanel.Visible = false
		end
		countryConfirm.Text = "✅ Ya gobiernas tu país"
		countryConfirm.BackgroundColor3 = Color3.fromRGB(30, 80, 60)
	elseif cp.selected then
		countryConfirm.Text = "✅ Elegir " .. cp.selected.name
		countryConfirm.BackgroundColor3 = Color3.fromRGB(0, 150, 110)
	else
		countryConfirm.Text = "Selecciona un país de la lista"
		countryConfirm.BackgroundColor3 = Color3.fromRGB(40, 52, 76)
	end
end

local function makeCountryButton(order, height)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -4, 0, height)
	b.LayoutOrder = order
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = true
	b.ZIndex = 32
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = b
	b.Parent = countryScroll
	return b
end

local function buildCountryPanel()
	for _, ch in ipairs(countryScroll:GetChildren()) do
		if ch:IsA("GuiButton") then
			ch:Destroy()
		end
	end
	cp.rows, cp.headers, cp.collapsed, cp.selected, cp.taken = {}, {}, {}, nil, {}
	cp.built = false
	cp.autoHidden = false
	countrySearch.Text = ""

	local byCont = {}
	for _, n in ipairs(state.roster) do
		if n.countryId then
			local cont = n.continent or 6
			byCont[cont] = byCont[cont] or {}
			table.insert(byCont[cont], n)
		end
	end

	for order, cont in ipairs(CONTINENT_ORDER) do
		local list = byCont[cont]
		if list then
			table.sort(list, function(a, b)
				return (a.cells or 0) > (b.cells or 0)
			end)
			cp.collapsed[cont] = true

			local header = makeCountryButton(order * 1000, 28)
			header.BackgroundColor3 = Color3.fromRGB(34, 60, 84)
			header.Font = Enum.Font.GothamBlack
			header.TextColor3 = Color3.fromRGB(190, 225, 255)
			header.TextSize = 12
			header.TextXAlignment = Enum.TextXAlignment.Left
			local hp = Instance.new("UIPadding")
			hp.PaddingLeft = UDim.new(0, 10)
			hp.Parent = header
			local label = (CONTINENT_NAMES[cont] or "Mundo") .. " · " .. #list
			cp.headers[cont] = { btn = header, label = label }
			header.MouseButton1Click:Connect(function()
				cp.collapsed[cont] = not cp.collapsed[cont]
				applyCountryFilter()
			end)

			for rank, n in ipairs(list) do
				local btn = makeCountryButton(order * 1000 + rank, 26)
				local nameLabel = Instance.new("TextLabel")
				nameLabel.Size = UDim2.new(0.58, -10, 1, 0)
				nameLabel.Position = UDim2.fromOffset(10, 0)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Font = Enum.Font.GothamMedium
				nameLabel.Text = n.name
				nameLabel.TextColor3 = Color3.fromRGB(232, 240, 252)
				nameLabel.TextSize = 12
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
				nameLabel.ZIndex = 33
				nameLabel.Parent = btn

				local status = Instance.new("TextLabel")
				status.Size = UDim2.new(0.42, -8, 1, 0)
				status.Position = UDim2.new(0.58, 0, 0, 0)
				status.BackgroundTransparency = 1
				status.Font = Enum.Font.Gotham
				status.Text = ""
				status.TextSize = 11
				status.TextXAlignment = Enum.TextXAlignment.Right
				status.TextTruncate = Enum.TextTruncate.AtEnd
				status.ZIndex = 33
				status.Parent = btn

				table.insert(cp.rows, { btn = btn, status = status, n = n, cont = cont, folded = fold(n.name) })

				btn.MouseButton1Click:Connect(function()
					local t = cp.taken[n.countryId]
					if t and t.nid ~= state.myId then
						showToast("🔒 " .. n.name .. " ya lo eligió " .. t.name, Color3.fromRGB(255, 150, 120))
						return
					end
					cp.selected = n
					if n.capital and n.capital >= 0 then
						centerOnCell(n.capital)
					end
					updateCountryPanel()
				end)
			end
		end
	end

	cp.built = true
	applyCountryFilter()
	updateCountryPanel()
end

countrySearch:GetPropertyChangedSignal("Text"):Connect(applyCountryFilter)

countryConfirm.MouseButton1Click:Connect(function()
	if state.me and state.me.alive then
		return
	end
	local n = cp.selected
	if not n then
		showToast("Elige un país de la lista", Color3.fromRGB(255, 200, 80))
		return
	end
	WorldCommand:FireServer({ a = "SPAWN", cell = n.capital })
	showToast("🌍 Eligiendo " .. n.name .. "...", Color3.fromRGB(0, 220, 255))
end)

btnCountries.MouseButton1Click:Connect(function()
	countryPanel.Visible = not countryPanel.Visible
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
	state.baseBuffer = WorldGrid.BuildBase(state.planet, state.land)
	fullRedraw()
	updateMarkers()
	updateMapTransform()

	-- Modo Países vs Países: lista de selección por continente
	state.mode = data.mode or "FREE"
	btnCountries.Visible = state.mode == "COUNTRIES"
	if state.mode == "COUNTRIES" then
		buildCountryPanel()
		countryPanel.Visible = true
	else
		countryPanel.Visible = false
	end

	state.initialized = true
	showToast("¡Bienvenido al mapa de " .. state.planet .. "!", Color3.fromRGB(0, 210, 255))
end)

WorldDiff.OnClientEvent:Connect(function(diffBuf)
	if not state.owner or (not state.editableImage and not state.blockMode) then
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
	-- Búsquedas rápidas para el tooltip y el ranking
	state.statById = {}
	for _, e in ipairs(stats.nations or {}) do
		state.statById[e.id] = e
	end
	state.humanById = {}
	for _, t in ipairs(stats.taken or {}) do
		state.humanById[t.nid] = t
	end
	if state.mode == "COUNTRIES" then
		updateCountryPanel()
	end
	if lobbyScreen.Visible then
		updateLobbyStatus()
	end

	-- Actualizar fase
	if stats.phase == "SPAWN" then
		local what = if state.mode == "COUNTRIES" then "Elige tu país" else "Elige tu capital"
		phaseText.Text = "📍 FASE DE SPAWN: " .. what .. " (" .. math.ceil(stats.spawnTimer or 0) .. "s)"
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
				entry.isMe = entry.id == state.myId -- el servidor no envía esta marca
				local rosterEntry = state.rosterById[entry.id]
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

				-- Muestra del color del país en el mapa + icono de jugador (👤) o bot (🤖)
				local swatch = Instance.new("Frame")
				swatch.Size = UDim2.fromOffset(10, 10)
				swatch.Position = UDim2.fromOffset(24, 6)
				swatch.BackgroundColor3 = if rosterEntry and rosterEntry.color
					then rosterEntry.color
					else Color3.fromRGB(150, 150, 150)
				swatch.BorderSizePixel = 0
				swatch.Parent = row
				local swatchStroke = Instance.new("UIStroke")
				swatchStroke.Color = Color3.fromRGB(240, 245, 255)
				swatchStroke.Thickness = 1
				swatchStroke.Parent = swatch

				local kindIcon = if entry.isMe then "👑 [TÚ] " elseif entry.isBot == false then "👤 " else ""
				local nameLbl = Instance.new("TextLabel")
				nameLbl.Size = UDim2.new(1, -86, 1, 0)
				nameLbl.Position = UDim2.fromOffset(40, 0)
				nameLbl.BackgroundTransparency = 1
				nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
				nameLbl.Font = entry.isMe and Enum.Font.GothamBlack or Enum.Font.GothamBold
				nameLbl.Text = kindIcon .. entry.name
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

-- La partida empieza cuando el jugador pulsa JUGAR en la pantalla de lobby (ver LobbyScreen).

updateMapTransform()
