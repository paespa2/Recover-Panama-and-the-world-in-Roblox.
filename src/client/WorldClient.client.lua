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
local WorldRoster = folder:WaitForChild("WorldRoster")
local WorldFx = folder:WaitForChild("WorldFx")

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
troopsCard.Size = UDim2.fromOffset(215, 30) -- cabe "Tropas: 123456/654321 (+1234/s)"
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
goldCard.Size = UDim2.fromOffset(150, 30)
goldCard.Position = UDim2.fromOffset(223, 2)
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
ratioLabel.Position = UDim2.fromOffset(381, 2)
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
	btn.Position = UDim2.fromOffset(473 + (idx - 1) * 44, 4)
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
		if state.sendAuto then
			state.sendAuto() -- el autojuego usa el mismo porcentaje de tropas que eliges para atacar
		end
		for rat, b in pairs(ratioButtons) do
			b.BackgroundColor3 = (rat == r) and Color3.fromRGB(0, 200, 240) or Color3.fromRGB(30, 42, 64)
			b.TextColor3 = (rat == r) and Color3.fromRGB(10, 15, 25) or Color3.fromRGB(220, 230, 245)
		end
	end)
end

-- Botón de autojuego: tras colocarte, tu nación se expande sola. Ciclo: Expandir → Conquistar → Apagado
local AUTO_STEPS = {
	EXPAND = { text = "🌱 Auto: EXPANDIR", color = Color3.fromRGB(30, 130, 70), next = "CONQUER" },
	CONQUER = { text = "⚔️ Auto: CONQUISTAR", color = Color3.fromRGB(170, 70, 30), next = "OFF" },
	OFF = { text = "✋ Auto: APAGADO", color = Color3.fromRGB(70, 80, 100), next = "EXPAND" },
}
state.autoMode = "EXPAND"

local btnAuto = Instance.new("TextButton")
btnAuto.Name = "BtnAuto"
btnAuto.Position = UDim2.fromOffset(697, 2)
btnAuto.Size = UDim2.fromOffset(136, 30)
btnAuto.BorderSizePixel = 0
btnAuto.Font = Enum.Font.GothamBold
btnAuto.TextColor3 = Color3.fromRGB(255, 255, 255)
btnAuto.TextSize = 11
btnAuto.ZIndex = 22
btnAuto.Parent = statsRow

local btnAutoCorner = Instance.new("UICorner")
btnAutoCorner.CornerRadius = UDim.new(0, 6)
btnAutoCorner.Parent = btnAuto

local function refreshAutoButton()
	local step = AUTO_STEPS[state.autoMode] or AUTO_STEPS.OFF
	btnAuto.Text = step.text
	btnAuto.BackgroundColor3 = step.color
end
refreshAutoButton()

function state.sendAuto()
	WorldCommand:FireServer({ a = "AUTO", mode = state.autoMode, ratio = state.attackRatio })
end
state.refreshAuto = refreshAutoButton

btnAuto.MouseButton1Click:Connect(function()
	state.autoMode = (AUTO_STEPS[state.autoMode] or AUTO_STEPS.OFF).next
	refreshAutoButton()
	state.sendAuto()
	state.showToast( -- showToast se declara más abajo en el archivo
		if state.autoMode == "OFF"
			then "✋ Autojuego apagado: tú decides cada ataque"
			elseif state.autoMode == "CONQUER" then "⚔️ Autojuego: expande y ataca al vecino más débil"
			else "🌱 Autojuego: tu nación se expande sola",
		Color3.fromRGB(180, 230, 255)
	)
end)

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

local btnNuke = createActionButton("NUKE", "MISIL NUCLEAR", "$900 Oro (Silo)", Color3.fromRGB(180, 70, 0), "☢️")
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
	state.showToast("🏳️ Retirada ordenada: tropas devueltas al territorio", Color3.fromRGB(255, 180, 50))
end)

setActionMode("ATTACK")

-- ============================================================================
-- TOAST / NOTIFICACIONES FLOTANTES
-- ============================================================================
local toastFrame = Instance.new("Frame")
toastFrame.Name = "ToastFrame"
toastFrame.AnchorPoint = Vector2.new(0.5, 0)
toastFrame.Position = UDim2.new(0.5, 0, 0, 156) -- bajo el cartel de la fase de aparición
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

state.showToast = showToast -- para el código que se declara antes que showToast

-- ============================================================================
-- ARMAS BÉLICAS: barra de poderes sobre el HUD (los datos de coste y radio deben coincidir con Engine.WEAPONS)
-- ============================================================================
local WEAPON_INFO = {
	BOMB = { name = "Bomba", icon = "💣", cost = 250, radius = 5, color = Color3.fromRGB(255, 150, 40) },
	ARTILLERY = { name = "Artillería", icon = "🎯", cost = 300, radius = 3, color = Color3.fromRGB(255, 230, 90) },
	METEOR = { name = "Meteorito", icon = "☄️", cost = 650, radius = 7, color = Color3.fromRGB(255, 90, 40) },
	QUAKE = { name = "Terremoto", icon = "🌋", cost = 550, radius = 13, color = Color3.fromRGB(200, 140, 80) },
	NUKE = { name = "Nuclear", icon = "☢️", cost = 900, radius = 16, color = Color3.fromRGB(255, 255, 255) },
}
local WEAPON_ORDER = { "BOMB", "ARTILLERY", "METEOR", "QUAKE" }

local weaponBar = Instance.new("Frame")
weaponBar.Name = "WeaponBar"
weaponBar.Position = UDim2.fromOffset(188, -52) -- justo encima del HUD (se escala con él)
weaponBar.Size = UDim2.fromOffset(624, 46)
weaponBar.BackgroundTransparency = 1
weaponBar.ZIndex = 22
weaponBar.Parent = bottomHUD

local weaponButtons = {}
for i, kind in ipairs(WEAPON_ORDER) do
	local info = WEAPON_INFO[kind]
	local b = Instance.new("TextButton")
	b.Name = "Weapon_" .. kind
	b.Position = UDim2.fromOffset((i - 1) * 158, 0)
	b.Size = UDim2.fromOffset(150, 46)
	b.BackgroundColor3 = Color3.fromRGB(26, 34, 52)
	b.BorderSizePixel = 0
	b.Text = ""
	b.ZIndex = 23
	b.Parent = weaponBar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Color = info.color
	stroke.Thickness = 1.5
	stroke.Parent = b

	local t1 = Instance.new("TextLabel")
	t1.BackgroundTransparency = 1
	t1.Position = UDim2.fromOffset(0, 5)
	t1.Size = UDim2.new(1, 0, 0, 20)
	t1.Font = Enum.Font.GothamBlack
	t1.Text = info.icon .. " " .. info.name
	t1.TextSize = 12
	t1.TextColor3 = Color3.fromRGB(245, 248, 255)
	t1.ZIndex = 24
	t1.Parent = b
	local t2 = Instance.new("TextLabel")
	t2.BackgroundTransparency = 1
	t2.Position = UDim2.fromOffset(0, 26)
	t2.Size = UDim2.new(1, 0, 0, 16)
	t2.Font = Enum.Font.Gotham
	t2.Text = string.format("$%d · radio %d", info.cost, info.radius)
	t2.TextSize = 10
	t2.TextColor3 = Color3.fromRGB(190, 205, 230)
	t2.ZIndex = 24
	t2.Parent = b

	-- Velo de recarga con los segundos que faltan
	local cd = Instance.new("TextLabel")
	cd.Size = UDim2.fromScale(1, 1)
	cd.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	cd.BackgroundTransparency = 0.4
	cd.Font = Enum.Font.GothamBlack
	cd.Text = ""
	cd.TextSize = 16
	cd.TextColor3 = Color3.fromRGB(255, 255, 255)
	cd.Visible = false
	cd.ZIndex = 26
	cd.Parent = b
	local cdCorner = Instance.new("UICorner")
	cdCorner.CornerRadius = UDim.new(0, 8)
	cdCorner.Parent = cd

	b.MouseButton1Click:Connect(function()
		setActionMode("WEAPON_" .. kind)
		showToast(
			string.format("%s %s apuntada: haz clic en el mapa (radio %d)", info.icon, info.name, info.radius),
			info.color
		)
	end)
	weaponButtons[kind] = { button = b, stroke = stroke, cd = cd }
end

-- Al cambiar de modo, la barra marca qué arma está apuntada (setActionMode se amplía para ello)
local baseSetActionMode = setActionMode
setActionMode = function(mode)
	baseSetActionMode(mode)
	for kind, w in pairs(weaponButtons) do
		local armed = mode == "WEAPON_" .. kind
		w.stroke.Thickness = if armed then 3 else 1.5
		w.stroke.Color = if armed then Color3.fromRGB(255, 255, 255) else WEAPON_INFO[kind].color
		w.button.BackgroundColor3 = if armed then Color3.fromRGB(64, 52, 40) else Color3.fromRGB(26, 34, 52)
	end
end

local function updateWeaponCooldowns(left)
	for kind, w in pairs(weaponButtons) do
		local secs = left and left[kind]
		if secs and secs > 0.05 then
			w.cd.Visible = true
			w.cd.Text = math.ceil(secs) .. "s"
		else
			w.cd.Visible = false
		end
	end
end

-- Efectos de armas: onda expansiva, destello y, en terremotos y misiles nucleares, temblor de pantalla
-- scar = tamaño relativo de la cicatriz (terreno quemado) que queda tras el impacto y se desvanece en ~40 s
local FX_STYLE = {
	BOMB = { color = Color3.fromRGB(255, 150, 40), time = 0.5, scar = 0.6 },
	ARTILLERY = { color = Color3.fromRGB(255, 230, 90), time = 0.4, scar = 0.5 },
	METEOR = { color = Color3.fromRGB(255, 90, 40), time = 0.7, scar = 0.7 },
	QUAKE = { color = Color3.fromRGB(200, 140, 80), time = 1.0, shake = 7 },
	NUKE = { color = Color3.fromRGB(255, 255, 255), time = 1.2, shake = 12, scar = 1.0 },
	VOLCANO = { color = Color3.fromRGB(255, 110, 30), time = 1.4, shake = 6, scar = 0.9 },
	TORNADO = { color = Color3.fromRGB(215, 225, 235), time = 0.6 },
	SANDSTORM = { color = Color3.fromRGB(225, 190, 120), time = 2.4 },
}

-- Cicatriz del terreno: mancha oscura bajo las fronteras que se va desvaneciendo
local function scarCircle(cell, diameterCells)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((cell % state.w + 0.5) / state.w, (cell // state.w + 0.5) / state.h)
	f.Size = UDim2.fromScale(diameterCells / state.w, diameterCells / state.h)
	f.BackgroundColor3 = Color3.fromRGB(28, 18, 12)
	f.BackgroundTransparency = 0.45
	f.BorderSizePixel = 0
	f.ZIndex = 4
	f.Parent = mapCanvas
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local tween = TweenService:Create(f, TweenInfo.new(40, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		f:Destroy()
	end)
end

local function fxCircle(cell, fromCells, toCells, color, transparency, seconds, z)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((cell % state.w + 0.5) / state.w, (cell // state.w + 0.5) / state.h)
	f.Size = UDim2.fromScale(fromCells / state.w, fromCells / state.h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = mapCanvas
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local tween = TweenService:Create(
		f,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(toCells / state.w, toCells / state.h), BackgroundTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		f:Destroy()
	end)
end

local function playWeaponFx(fx)
	if not state.initialized or type(fx) ~= "table" or not fx.cell or fx.cell >= state.w * state.h then
		return
	end
	if fx.kind == "WARN" then
		-- Aviso de desastre: anillo rojo que late 4 veces sobre la zona de peligro
		local d = (fx.r or 8) * 2 + 1
		for k = 0, 3 do
			task.delay(k * 1.2, function()
				fxCircle(fx.cell, d * 0.3, d, Color3.fromRGB(255, 70, 70), 0.6, 1.1, 14)
			end)
		end
		return
	end
	local style = FX_STYLE[fx.kind]
	if not style then
		return
	end
	local diameter = (fx.r or 5) * 2 + 1
	fxCircle(fx.cell, 1, diameter, style.color, 0.35, style.time, 14) -- onda expansiva
	fxCircle(fx.cell, 1, diameter * 0.55, Color3.new(1, 1, 1), 0.1, style.time * 0.6, 15) -- destello central
	-- Anillos escalonados (núcleo blanco → amarillo → naranja → humo gris), como las explosiones de pixel art
	local t = style.time
	task.delay(t * 0.15, function()
		fxCircle(fx.cell, 1, diameter * 0.8, Color3.fromRGB(255, 225, 90), 0.25, t * 0.8, 16)
	end)
	task.delay(t * 0.3, function()
		fxCircle(fx.cell, 1, diameter * 0.95, Color3.fromRGB(255, 130, 40), 0.35, t * 0.9, 15)
	end)
	task.delay(t * 0.5, function()
		fxCircle(fx.cell, diameter * 0.3, diameter * 1.15, Color3.fromRGB(90, 90, 100), 0.55, t * 1.3, 13)
	end)
	if style.scar then
		scarCircle(fx.cell, diameter * style.scar)
	end
	if style.shake then
		task.spawn(function()
			local base = state.pan
			for _ = 1, 12 do
				state.pan = base
					+ Vector2.new(math.random(-style.shake, style.shake), math.random(-style.shake, style.shake))
				state.updateMapTransform() -- se declara más abajo en el archivo
				task.wait(0.03)
			end
			state.pan = base
			state.updateMapTransform()
		end)
	end
end
WorldFx.OnClientEvent:Connect(playWeaponFx)

-- ----------------------------------------------------------------------------
-- FRENTES DE BATALLA (estilo RoWorld): flecha hacia el enemigo con las tropas del ataque + chispa blanca de choque
-- ----------------------------------------------------------------------------
local frontLabels = {}
local ARROWS = { "➡", "↗", "⬆", "↖", "⬅", "↙", "⬇", "↘" }

local function troopText(k)
	if k >= 1000000 then
		return string.format("%.1fM", k / 1000000)
	elseif k >= 1000 then
		return string.format("%dK", math.floor(k / 1000))
	end
	return tostring(k)
end

local function updateFronts(fronts)
	for _, l in ipairs(frontLabels) do
		l.Visible = false
	end
	if not state.initialized or not fronts then
		return
	end
	for i, f in ipairs(fronts) do
		local l = frontLabels[i]
		if not l then
			l = Instance.new("TextLabel")
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Size = UDim2.fromOffset(84, 22)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBlack
			l.TextSize = 14
			l.TextStrokeTransparency = 0
			l.TextStrokeColor3 = Color3.new(1, 1, 1)
			l.ZIndex = 18
			l.Parent = mapCanvas
			frontLabels[i] = l
		end
		local w = state.w
		local cx, cy = f.c % w, f.c // w
		local atk = state.rosterById[f.a]
		local dir = 1
		if atk and atk.capital and atk.capital >= 0 then
			local dx, dy = cx - atk.capital % w, cy - atk.capital // w
			local a = math.atan2(-dy, dx)
			dir = (math.floor(a / (math.pi / 4) + 0.5) % 8) + 1
		end
		l.Text = ARROWS[dir] .. " " .. troopText(f.k)
		l.TextColor3 = if f.a == state.myId
			then Color3.fromRGB(255, 200, 30)
			else (if atk and atk.color then state.vividColor(atk.color, f.a) else Color3.fromRGB(255, 90, 90))
		l.TextColor3 = l.TextColor3:Lerp(Color3.new(0, 0, 0), 0.35) -- oscuro: contrasta con el borde blanco
		l.Position = UDim2.fromScale((cx + 0.5) / w, (cy + 0.5) / state.h)
		l.Visible = true
		fxCircle(f.c, 1, 5, Color3.new(1, 1, 1), 0.2, 0.9, 17) -- chispa blanca del choque
	end
end
state.updateFronts = updateFronts

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
		desc = "Cada continente es un equipo: los aliados no se atacan. Gana el equipo con más del 55 % de la tierra.",
		tag = "NUEVO",
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
	if selMode ~= "FREE" then
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

local MODE_NAMES = { COUNTRIES = "Países vs Países", CONTINENTS = "Continentes", FREE = "Libre" }
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
		MODE_NAMES[if s.teamMode then "CONTINENTS" else (s.mode or "FREE")] or "Libre",
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
-- (versión con fronteras en gris neutro: `build_countries.py --borders`, color por defecto 150,158,172)
local BORDER_TILES = { "rbxassetid://128579188089815", "rbxassetid://96974628781335" }
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
		img.ZIndex = zIndex -- el ScreenGui usa capas globales: la capa de cada imagen decide qué queda encima
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
		-- Capas globales del mapa: teselas 1 < bloques 2 < detalle 3 < resalte 4 < fronteras 5 < anillos 8-9 < marcadores 10+
		tileLayer = makeTileLayer("TileLayer", EARTH_TILES, 1)
		borderLayer = makeTileLayer("BorderLayer", BORDER_TILES, 5)
	end
	if tileLayer then
		tileLayer.Visible = visible
	end
	if borderLayer then
		borderLayer.Visible = visible
	end
end

local function initBlocks(w, h)
	-- Otra carga ya está creando los bloques: se espera a que termine (luego bastará con reutilizarlos)
	while state.blockBuilding do
		task.wait()
	end
	mapImage.Visible = false
	state.useTiles = state.planet == "EARTH"
	setTilesVisible(state.useTiles)
	local bw, bh = w // BLOCK, h // BLOCK
	if state.blocks and state.blockW == bw and state.blockH == bh then
		state.blockMode = true
		if state.blockLayer then
			state.blockLayer.Visible = true
		end
		return
	end
	if state.blockLayer then
		state.blockLayer:Destroy()
	end
	state.blockBuilding = true

	local layer = Instance.new("Frame")
	layer.Name = "BlockLayer"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ZIndex = -5 -- siempre por debajo de marcadores, efectos y cursor
	layer.Parent = mapCanvas

	-- Son ~15.000 rectángulos: se crean por tandas cediendo el turno, o el script agota su tiempo de ejecución
	local blocks = table.create(bw * bh)
	for by = 0, bh - 1 do
		if by % 10 == 9 then
			task.wait()
		end
		for bx = 0, bw - 1 do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = 2
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

	state.blocks = blocks
	state.blockLayer = layer
	state.blockW = bw
	state.blockH = bh
	state.dirtyBlocks = {}
	state.blockMode = true -- hasta aquí los cambios del mapa se ignoran: aún no hay bloques que pintar
	state.blockBuilding = false
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

-- ----------------------------------------------------------------------------
-- CONTORNO DE COLOR DE CADA TERRITORIO (mapa de bloques)
-- Donde un bloque pertenece a una nación y su vecino a otra (o a nadie), el bloque dibuja una línea de una celda de
-- grosor con el color de su dueño, por dentro de su lado. El contorno crece y se redibuja solo al conquistar.
-- Tu contorno es dorado y late. Con mucho zoom se usa el borde celda por celda del nivel de detalle.
-- ----------------------------------------------------------------------------
local edgeLayer = Instance.new("Frame")
edgeLayer.Name = "EdgeLayer"
edgeLayer.Size = UDim2.fromScale(1, 1)
edgeLayer.BackgroundTransparency = 1
edgeLayer.BorderSizePixel = 0
edgeLayer.ZIndex = 6
edgeLayer.Parent = mapCanvas

local edgeFrames = {} -- [bi * 4 + lado] = Frame (0 derecha, 1 abajo, 2 izquierda, 3 arriba)
local edgeFree = {}
local myEdges = {} -- conjunto de líneas del jugador: laten

-- Color vivo para los contornos: conserva el tono de la nación pero con saturación y brillo altos, para que
-- cada territorio destaque sobre el relieve (los colores de los bots son apagados a propósito en el tinte)
local EDGE_THICK = 0.5 -- grosor de los contornos de territorio, en celdas (antes 1)

-- Modo equipos: dos dueños del mismo continente son aliados y no se dibuja contorno entre ellos
local function sameTeam(a, b)
	if not state.teamMode or a == 0 or b == 0 then
		return false
	end
	local ra, rb = state.rosterById[a], state.rosterById[b]
	return ra ~= nil and rb ~= nil and ra.continent ~= nil and ra.continent == rb.continent
end
state.sameTeam = sameTeam

-- Variedad suave: cada nación recibe una tonalidad ligeramente distinta (saturación/brillo/tono) derivada de su
-- id, para que países vecinos de colores parecidos no se confundan y la paleta no sea tan estridente
local function vividColor(c, id)
	local h, s = c:ToHSV()
	local k = ((id or 0) * 37) % 100 / 100 -- 0..1 repetible
	local sat = math.clamp(s * 1.4, 0.45, 0.78) + (k - 0.5) * 0.16
	local val = 0.86 + k * 0.14
	local hue = (h + (k - 0.5) * 0.05) % 1
	return Color3.fromHSV(hue, math.clamp(sat, 0.35, 0.85), math.clamp(val, 0.8, 1))
end
state.vividColor = vividColor

local function edgeColor(ownerId)
	if ownerId == state.myId then
		return Color3.fromRGB(255, 230, 70)
	end
	local n = state.rosterById[ownerId]
	if n and n.color then
		return vividColor(n.color, ownerId)
	end
	return Color3.new(1, 1, 1)
end

local function setEdge(bi, side, show, ownerId)
	local key = bi * 4 + side
	local f = edgeFrames[key]
	if not show then
		if f then
			f.Visible = false
			edgeFrames[key] = nil
			myEdges[f] = nil
			edgeFree[#edgeFree + 1] = f
		end
		return
	end
	if not f then
		f = table.remove(edgeFree)
		if not f then
			f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundTransparency = 0.12 -- casi pleno pero suave: contorno fino y natural
			f.ZIndex = 6
			f.Parent = edgeLayer
		end
		edgeFrames[key] = f
		local w, h = state.w, state.h
		local x0 = ((bi - 1) % state.blockW) * BLOCK
		local y0 = ((bi - 1) // state.blockW) * BLOCK
		local t = EDGE_THICK -- línea fina: la mitad de una celda, pegada al borde del bloque
		if side == 0 then
			f.Position = UDim2.fromScale((x0 + BLOCK - t) / w, y0 / h)
			f.Size = UDim2.fromScale(t / w, BLOCK / h)
		elseif side == 1 then
			f.Position = UDim2.fromScale(x0 / w, (y0 + BLOCK - t) / h)
			f.Size = UDim2.fromScale(BLOCK / w, t / h)
		elseif side == 2 then
			f.Position = UDim2.fromScale(x0 / w, y0 / h)
			f.Size = UDim2.fromScale(t / w, BLOCK / h)
		else
			f.Position = UDim2.fromScale(x0 / w, y0 / h)
			f.Size = UDim2.fromScale(BLOCK / w, t / h)
		end
		f.Visible = true
	end
	f.BackgroundColor3 = edgeColor(ownerId)
	myEdges[f] = if ownerId == state.myId then true else nil
end

-- Recalcula las 4 líneas de un bloque según el dueño de sus vecinos (el mundo da la vuelta en horizontal)
local function updateBlockEdges(bi)
	local blocks = state.blocks
	local b = blocks[bi]
	if not b then
		return
	end
	local bw, bh = state.blockW, state.blockH
	local bx, by = (bi - 1) % bw, (bi - 1) // bw
	local o = b.owner or 0
	local function neighbor(nbx, nby)
		if nby < 0 or nby >= bh then
			return nil -- por arriba y por abajo el mapa termina: no hay contorno
		end
		local nb = blocks[nby * bw + (nbx % bw) + 1]
		return if nb then (nb.owner or 0) else nil
	end
	local r, d, l, u = neighbor(bx + 1, by), neighbor(bx, by + 1), neighbor(bx - 1, by), neighbor(bx, by - 1)
	setEdge(bi, 0, o ~= 0 and r ~= nil and r ~= o and not sameTeam(r, o), o)
	setEdge(bi, 1, o ~= 0 and d ~= nil and d ~= o and not sameTeam(d, o), o)
	setEdge(bi, 2, o ~= 0 and l ~= nil and l ~= o and not sameTeam(l, o), o)
	setEdge(bi, 3, o ~= 0 and u ~= nil and u ~= o and not sameTeam(u, o), o)
end

-- Reconstruye todos los contornos (tras el primer dibujado). Por tandas para no agotar el tiempo del script.
local rebuildEdges
function rebuildEdges()
	state.rebuildEdges = rebuildEdges
	for key, f in pairs(edgeFrames) do
		f.Visible = false
		edgeFree[#edgeFree + 1] = f
		edgeFrames[key] = nil
	end
	table.clear(myEdges)
	for bi = 1, state.blockW * state.blockH do
		updateBlockEdges(bi)
		if bi % 1500 == 0 then
			task.wait()
		end
	end
end

-- El contorno del jugador late entre dorado y blanco (unas 8 veces por segundo basta)
local edgePulseAcc = 0
RunService.Heartbeat:Connect(function(dt)
	edgePulseAcc += dt
	if edgePulseAcc < 0.12 then
		return
	end
	edgePulseAcc = 0
	local k = (math.sin(os.clock() * 4) + 1) / 2
	local c = Color3.fromRGB(255, 215, 40):Lerp(Color3.fromRGB(255, 255, 235), k)
	for f in pairs(myEdges) do
		f.BackgroundColor3 = c
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
			transparency = if isMe then 0.5 elseif n.bot == false then 0.55 else 0.68 -- fills suaves: el relieve se transparenta
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
	local ownerChanged = b.owner ~= ownerNow
	b.owner = ownerNow
	-- Cambió el dueño del bloque: se redibujan sus contornos y los de sus 4 vecinos (comparten lado)
	if ownerChanged and state.animReady then
		local bw = state.blockW
		updateBlockEdges(bi)
		updateBlockEdges(bi - 1 + (if (bi - 1) % bw == 0 then bw else 0)) -- izquierda (con vuelta)
		updateBlockEdges(bi + 1 - (if bi % bw == 0 then bw else 0)) -- derecha (con vuelta)
		updateBlockEdges(bi - bw)
		updateBlockEdges(bi + bw)
	end
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

-- Rectángulo de píxeles modificados desde la última escritura a la imagen (EditableImage): solo se envía esa zona
local dirty = { x0 = math.huge, y0 = math.huge, x1 = -1, y1 = -1 }

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

	local px, py = idx % state.w, idx // state.w
	if px < dirty.x0 then
		dirty.x0 = px
	end
	if px > dirty.x1 then
		dirty.x1 = px
	end
	if py < dirty.y0 then
		dirty.y0 = py
	end
	if py > dirty.y1 then
		dirty.y1 = py
	end
end

local fullRedraw -- declarada aquí porque flushImage la usa al cambiar al modo por bloques

local function flushImage()
	if state.blockMode then
		for bi in pairs(state.dirtyBlocks) do
			recolorBlock(bi)
			state.dirtyBlocks[bi] = nil
		end
		state.detailDirty = true -- el nivel de detalle celda por celda se refresca con los cambios
		return
	end
	if state.editableImage and state.pixelBuffer then
		if dirty.x1 < 0 then
			return -- nada cambió desde la última escritura
		end
		local w, h = state.w, state.h
		local x0, y0, x1, y1 = dirty.x0, dirty.y0, dirty.x1, dirty.y1
		dirty.x0, dirty.y0, dirty.x1, dirty.y1 = math.huge, math.huge, -1, -1
		local rw, rh = x1 - x0 + 1, y1 - y0 + 1
		local ok, err = pcall(function()
			if rw * rh >= w * h * 0.5 then
				-- Cambió más de la mitad del mapa (p. ej. el primer dibujado): una sola escritura completa
				state.editableImage:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), state.pixelBuffer)
			else
				-- Solo se copia y se envía el rectángulo modificado, no los 1,46 MiB de la imagen completa
				local region = buffer.create(rw * rh * 4)
				for row = 0, rh - 1 do
					buffer.copy(region, row * rw * 4, state.pixelBuffer, ((y0 + row) * w + x0) * 4, rw * 4)
				end
				state.editableImage:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(rw, rh), region)
			end
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
		-- Contornos de color de todos los territorios (los cambios que lleguen mientras tanto solo anotan dueños)
		state.blockBuilding = true
		rebuildEdges()
		state.blockBuilding = false
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

-- Rótulos y puntos escalan con el zoom (rel = 1 es el mundo entero a pantalla).
-- Con zoom bajo solo se rotulan tú, los jugadores y los países más grandes; al acercar se ven todos.
local function applyLabelZoom()
	local rel = state.zoom / (state.fit or state.zoom)
	for _, m in ipairs(markerLabels) do
		local ds = math.clamp(math.floor((if m.isMe then 12 else 7) * (0.75 + 0.3 * rel)), 5, 24)
		m.dot.Size = UDim2.fromOffset(ds, ds)
		local show = m.always or rel >= 1.8
		m.label.Visible = show
		if m.troops then
			m.troops.Visible = show and m.troops.Text ~= ""
		end
		if show then
			local size = math.clamp(math.floor(7 + 3 * rel), 8, 17) + (if m.strong then 2 else 0)
			local width = math.max(100, size * 14)
			m.label.TextSize = size
			m.label.Size = UDim2.fromOffset(width, size + 6)
			m.label.Position = UDim2.fromOffset(12 - width / 2, 10 + ds / 2)
			if m.troops then
				m.troops.TextSize = math.max(8, size - 1)
				m.troops.Size = UDim2.fromOffset(width, size + 4)
				m.troops.Position = UDim2.fromOffset(12 - width / 2, 10 + ds / 2 + size + 4)
			end
		end
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

			-- Tropas debajo del nombre, como en RoWorld ("Guyana 21.1K")
			local troopsLbl = Instance.new("TextLabel")
			troopsLbl.Name = "Troops"
			troopsLbl.Size = UDim2.fromOffset(100, 14)
			troopsLbl.BackgroundTransparency = 1
			troopsLbl.Font = Enum.Font.GothamBlack
			troopsLbl.Text = ""
			troopsLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			troopsLbl.TextStrokeTransparency = 0.25
			troopsLbl.TextStrokeColor3 = Color3.fromRGB(8, 10, 16)
			troopsLbl.TextSize = 9
			troopsLbl.ZIndex = 11
			troopsLbl.Parent = marker

			table.insert(markerPool, marker)
			table.insert(markerLabels, {
				id = n.id,
				troops = troopsLbl,
				label = nameLbl,
				dot = dot,
				isMe = isMe,
				strong = isMe or isHuman,
				always = isMe or isHuman or bigIds[n.id] == true,
			})
		end
	end
	applyLabelZoom()
end

-- ============================================================================
-- INTERACCIÓN CON EL MAPA (Clic para Atacar, Construir, Nuke o Spawn)
-- ============================================================================
-- Actualiza las tropas bajo cada rótulo (llega cada segundo con las estadísticas)
local function updateLabelTroops()
	local byId = state.statById
	if not byId then
		return
	end
	for _, m in ipairs(markerLabels) do
		local e = byId[m.id]
		m.troops.Text = if e then troopText(e.troops) else ""
		m.troops.Visible = m.label.Visible and m.troops.Text ~= ""
	end
end
state.updateLabelTroops = updateLabelTroops

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

	if state.me and state.me.eliminated then
		showToast("💀 Estás eliminado: solo puedes observar la partida", Color3.fromRGB(255, 120, 120))
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
			showToast("📍 Fijando tu ubicación...", Color3.fromRGB(0, 220, 255))
		end
		return
	end

	-- Modo alianza: el clic propone (o rompe) una alianza con la nación dueña de esa celda
	if state.allyMode then
		state.allyMode = false
		local btn = gui:FindFirstChild("BtnAlly", true)
		if btn then
			btn.BackgroundColor3 = Color3.fromRGB(70, 60, 130)
		end
		local targetId = buffer.readu8(state.owner, cell)
		if targetId == 0 or targetId == state.myId then
			showToast("🤝 Haz clic sobre el territorio de otra nación", Color3.fromRGB(255, 200, 80))
			return
		end
		local isAlly = false
		for _, id in ipairs(state.me and state.me.ally and state.me.ally.allies or {}) do
			if id == targetId then
				isAlly = true
			end
		end
		WorldCommand:FireServer({ a = if isAlly then "ALLY_BREAK" else "ALLY_REQUEST", target = targetId })
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
	elseif state.actionMode:sub(1, 7) == "WEAPON_" then
		-- El arma sigue apuntada tras disparar (cada una tiene su enfriamiento y el servidor valida oro y recarga)
		WorldCommand:FireServer({ a = "WEAPON", kind = state.actionMode:sub(8), cell = cell })
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
	state.fit = math.min(viewportSize.X / BASE_WIDTH, viewportSize.Y / BASE_HEIGHT) -- zoom que muestra el mundo entero
	state.detailDirty = true
	applyLabelZoom()
end

state.updateMapTransform = updateMapTransform

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

-- Zoom suave: la rueda y las teclas fijan un objetivo y cada fotograma se acerca a él (ver más abajo)
local MAX_ZOOM = 8.0
local zoomTarget = state.zoom
local zoomAnchor = Vector2.zero
local requestZoom, fitToScreen, focusCell -- se definen tras los controles

-- Zoom que muestra el mundo entero; el mínimo permitido es algo menor para dejar un margen
local function fitZoom()
	local vs = mapContainer.AbsoluteSize
	return math.min(vs.X / BASE_WIDTH, vs.Y / BASE_HEIGHT)
end

-- Zoom inmediato manteniendo fijo el punto del mapa que hay bajo screenPos.
-- El centro se calcula con el estado (no con AbsolutePosition, que se actualiza un fotograma tarde).
local function applyZoom(screenPos, factor)
	local newZoom = math.clamp(state.zoom * factor, fitZoom() * 0.85, MAX_ZOOM)
	local f = newZoom / state.zoom
	local center = mapContainer.AbsolutePosition + mapContainer.AbsoluteSize / 2 + state.pan
	state.pan = state.pan + (screenPos - center) * (1 - f)
	state.zoom = newZoom
	clampPan()
	updateMapTransform()
end

-- Zoom inmediato (pellizco táctil): también fija el objetivo para que el suavizado no lo deshaga
local function zoomAt(screenPos, factor)
	applyZoom(screenPos, factor)
	zoomTarget = state.zoom
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
		requestZoom(UserInputService:GetMouseLocation(), if input.Position.Z > 0 then 1.2 else 1 / 1.2)
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
		requestZoom(mapContainer.AbsolutePosition + mapContainer.AbsoluteSize / 2, 1 + 2.5 * dt)
	elseif UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		requestZoom(mapContainer.AbsolutePosition + mapContainer.AbsoluteSize / 2, 1 / (1 + 2.5 * dt))
	elseif UserInputService:IsKeyDown(Enum.KeyCode.H) then
		fitToScreen()
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
-- ZOOM: suavizado, vista completa, botones y nivel de detalle celda por celda
-- ============================================================================
function requestZoom(screenPos, factor)
	zoomTarget = math.clamp(zoomTarget * factor, fitZoom() * 0.85, MAX_ZOOM)
	zoomAnchor = screenPos
end

-- Cada fotograma el zoom se acerca al objetivo (animación suave de acercar y alejar)
RunService.RenderStepped:Connect(function(dt)
	local diff = zoomTarget - state.zoom
	if math.abs(diff) > 0.0004 then
		applyZoom(zoomAnchor, (state.zoom + diff * math.min(1, dt * 14)) / state.zoom)
	end
end)

-- Muestra el mundo entero ajustado a la pantalla
function fitToScreen()
	state.zoom = fitZoom()
	zoomTarget = state.zoom
	state.pan = Vector2.zero
	updateMapTransform()
end

-- Centra la vista en una celda con el zoom indicado (sin animar)
function focusCell(cell, zoom)
	state.zoom = math.clamp(zoom or state.zoom, fitZoom() * 0.85, MAX_ZOOM)
	zoomTarget = state.zoom
	local normX = (cell % state.w + 0.5) / state.w - 0.5
	local normY = (cell // state.w + 0.5) / state.h - 0.5
	state.pan = Vector2.new(-normX * BASE_WIDTH * state.zoom, -normY * BASE_HEIGHT * state.zoom)
	clampPan()
	updateMapTransform()
end

-- Botones de zoom (útiles sobre todo en pantallas táctiles): acercar, alejar y ver todo el mundo
local zoomBar = Instance.new("Frame")
zoomBar.Name = "ZoomBar"
zoomBar.AnchorPoint = Vector2.new(1, 0.5)
zoomBar.Position = UDim2.new(1, -16, 0.56, 0)
zoomBar.Size = UDim2.fromOffset(40, 178) -- 4 botones de 40 px con 6 px de separación
zoomBar.BackgroundTransparency = 1
zoomBar.ZIndex = 25
zoomBar.Parent = root

local zoomBarLayout = Instance.new("UIListLayout")
zoomBarLayout.Padding = UDim.new(0, 6)
zoomBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
zoomBarLayout.Parent = zoomBar

local function zoomButton(order, text, action)
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(40, 40)
	b.BackgroundColor3 = Color3.fromRGB(26, 40, 66)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBlack
	b.Text = text
	b.TextColor3 = Color3.fromRGB(235, 242, 255)
	b.TextSize = 20
	b.ZIndex = 26
	b.Parent = zoomBar
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(60, 90, 140)
	s.Thickness = 1.5
	s.Parent = b
	b.MouseButton1Click:Connect(action)
end
local function viewCenter()
	return mapContainer.AbsolutePosition + mapContainer.AbsoluteSize / 2
end
zoomButton(1, "+", function()
	requestZoom(viewCenter(), 1.6)
end)
zoomButton(2, "−", function()
	requestZoom(viewCenter(), 1 / 1.6)
end)
zoomButton(3, "⌂", function()
	fitToScreen()
end)

-- ---- Nubes de píxeles: capa decorativa que se desplaza despacio, con sombra sobre el terreno ----
-- Cada nube son filas de rectángulos (aspecto pixelado) y su sombra. Solo se mueve el contenedor de cada una.
-- Se ocultan al acercar mucho (para no tapar el detalle) y se pueden apagar con el botón ☁.
local CLOUD_COUNT = 14
local CLOUD_ROWS = { 0.42, 0.72, 1.0, 0.86, 0.5 } -- anchura relativa de cada fila: da forma redondeada
local cloudsOn = true
local cloudLayer = Instance.new("Frame")
cloudLayer.Name = "CloudLayer"
cloudLayer.Size = UDim2.fromScale(1, 1)
cloudLayer.BackgroundTransparency = 1
cloudLayer.BorderSizePixel = 0
cloudLayer.ZIndex = 6 -- sobre las fronteras, bajo anillos y marcadores
cloudLayer.Parent = mapCanvas

local cloudRng = Random.new(7)
local clouds = {}
for _ = 1, CLOUD_COUNT do
	local c = {
		x = cloudRng:NextNumber(0, 960),
		y = cloudRng:NextNumber(20, 380),
		w = cloudRng:NextNumber(36, 90), -- tamaño en celdas
		h = cloudRng:NextNumber(10, 20),
		speed = cloudRng:NextNumber(1.2, 3.4), -- celdas por segundo
	}
	local rootFrame = Instance.new("Frame")
	rootFrame.BackgroundTransparency = 1
	rootFrame.BorderSizePixel = 0
	rootFrame.ZIndex = 6
	rootFrame.Size = UDim2.fromScale(c.w / 960, c.h / 400)
	rootFrame.Parent = cloudLayer
	for pass = 1, 2 do -- pasada 1: sombra (más abajo y a la derecha); pasada 2: cuerpo
		for i, f in ipairs(CLOUD_ROWS) do
			local row = Instance.new("Frame")
			row.BorderSizePixel = 0
			row.Size = UDim2.fromScale(f, 1 / #CLOUD_ROWS)
			if pass == 1 then
				row.Position = UDim2.fromScale(0.5 - f / 2 + 0.16, (i - 1) / #CLOUD_ROWS + 0.9)
				row.BackgroundColor3 = Color3.fromRGB(10, 22, 40)
				row.BackgroundTransparency = 0.86
				row.ZIndex = 5
			else
				row.Position = UDim2.fromScale(0.5 - f / 2, (i - 1) / #CLOUD_ROWS)
				row.BackgroundColor3 = Color3.fromRGB(246, 249, 255)
				row.BackgroundTransparency = 0.5
				row.ZIndex = 6
			end
			row.Parent = rootFrame
		end
	end
	c.frame = rootFrame
	clouds[#clouds + 1] = c
end

RunService.RenderStepped:Connect(function(dt)
	-- Con mucho zoom se ocultan: el detalle del terreno importa más que el adorno
	local rel = state.zoom / (state.fit or state.zoom)
	local show = cloudsOn and rel < 3.2
	cloudLayer.Visible = show
	if not show then
		return
	end
	for _, c in ipairs(clouds) do
		c.x += c.speed * dt
		if c.x > 960 + c.w then
			c.x = -c.w -- reaparece por el otro lado
		end
		c.frame.Position = UDim2.fromScale(c.x / 960, c.y / 400)
	end
end)

zoomButton(4, "☁", function()
	cloudsOn = not cloudsOn
	showToast(if cloudsOn then "☁️ Nubes activadas" else "☁️ Nubes apagadas", Color3.fromRGB(200, 225, 255))
end)

-- ---- Detalle celda por celda: al acercar mucho, cada celda conquistada se pinta como su propio cuadro ----
-- Solo se dibujan las celdas visibles. Cada celda usa siempre el mismo "hueco" de un reparto toroidal, así
-- al desplazarse solo se reasignan los cuadros que entran por el borde (no toda la pantalla).
local DETAIL_MIN_CELL_PX = 7 -- tamaño mínimo de celda en pantalla para activar el detalle
local DETAIL_MAX_CELLS = 12000 -- tope de cuadros visibles a la vez (rendimiento)
local detail = {
	layer = nil,
	frames = {},
	slotCell = {},
	slotOwner = {},
	cols = 0,
	rows = 0,
	active = false,
	last = 0,
	slotBorder = {},
	flashing = {},
	flashCount = 0,
}

-- ¿La celda toca a otra de distinto dueño (u océano/libre)? Entonces dibuja su borde de color
local function isBorderCell(cell, x, y, o)
	local w, h = state.w, state.h
	local owner = state.owner
	local function differs(v)
		return v ~= o and not sameTeam(v, o)
	end
	if differs(buffer.readu8(owner, y * w + (if x == 0 then w - 1 else x - 1))) then
		return true
	end
	if differs(buffer.readu8(owner, y * w + (if x == w - 1 then 0 else x + 1))) then
		return true
	end
	if y > 0 and differs(buffer.readu8(owner, cell - w)) then
		return true
	end
	return y < h - 1 and differs(buffer.readu8(owner, cell + w))
end

local function setDetailActive(on)
	if on and not detail.layer then
		local l = Instance.new("Frame")
		l.Name = "DetailLayer"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.ZIndex = -4 -- sobre los bloques de color (-5) y bajo las fronteras (-3)
		l.Parent = mapCanvas
		detail.layer = l
	end
	detail.active = on
	if detail.layer then
		detail.layer.Visible = on
	end
	edgeLayer.Visible = not on -- con detalle, cada celda dibuja su propio borde
	if state.blockLayer then
		state.blockLayer.Visible = not on
	end
end

local function refreshDetail()
	if not (state.blockMode and state.useTiles and state.owner and state.w > 0) then
		if detail.active then
			setDetailActive(false)
		end
		return
	end
	local w, h = state.w, state.h
	local cellW = BASE_WIDTH * state.zoom / w
	local cellH = BASE_HEIGHT * state.zoom / h
	local vs = mapContainer.AbsoluteSize
	local left = vs.X / 2 + state.pan.X - BASE_WIDTH * state.zoom / 2
	local top = vs.Y / 2 + state.pan.Y - BASE_HEIGHT * state.zoom / 2
	local x0 = math.max(0, math.floor(-left / cellW) - 1)
	local x1 = math.min(w - 1, math.ceil((vs.X - left) / cellW) + 1)
	local y0 = math.max(0, math.floor(-top / cellH) - 1)
	local y1 = math.min(h - 1, math.ceil((vs.Y - top) / cellH) + 1)
	local count = (x1 - x0 + 1) * (y1 - y0 + 1)
	if cellW < DETAIL_MIN_CELL_PX or count <= 0 or count > DETAIL_MAX_CELLS then
		if detail.active then
			setDetailActive(false)
		end
		return
	end
	if not detail.active then
		setDetailActive(true)
	elseif state.blockLayer and state.blockLayer.Visible then
		state.blockLayer.Visible = false -- initBlocks pudo volver a mostrarlo
	end

	-- Cuadrícula de huecos algo mayor que la ventana visible
	local cols, rows = (x1 - x0 + 1) + 2, (y1 - y0 + 1) + 2
	if cols ~= detail.cols or rows ~= detail.rows then
		for _, f in pairs(detail.frames) do
			f.Visible = false
		end
		table.clear(detail.slotCell)
		table.clear(detail.slotOwner)
		table.clear(detail.slotBorder)
		detail.cols, detail.rows = cols, rows
	end

	local owner = state.owner
	local frames, slotCell, slotOwner = detail.frames, detail.slotCell, detail.slotOwner
	for y = y0, y1 do
		local rowBase = (y % rows) * cols + 1
		for x = x0, x1 do
			local cell = y * w + x
			local slot = rowBase + (x % cols)
			local o = buffer.readu8(owner, cell)
			local prevCell, prevOwner = slotCell[slot], slotOwner[slot]
			local border = o ~= 0 and isBorderCell(cell, x, y, o)
			if prevCell ~= cell or prevOwner ~= o or detail.slotBorder[slot] ~= border then
				slotCell[slot], slotOwner[slot] = cell, o
				detail.slotBorder[slot] = border
				local n = if o ~= 0 then state.rosterById[o] else nil
				local f = frames[slot]
				if not n then
					if f then
						f.Visible = false
					end
				else
					if not f then
						f = Instance.new("Frame")
						f.BorderSizePixel = 0
						f.ZIndex = 3
						f.Size = UDim2.fromScale(1 / w, 1 / h)
						f.Parent = detail.layer
						frames[slot] = f
					end
					f.Position = UDim2.fromScale(x / w, y / h)
					-- Más opaco que los bloques: aquí cada celda es grande y el tinte debe distinguirse bien
					local transparency = if o == state.myId then 0.25 elseif n.bot == false then 0.33 else 0.45
					f.BackgroundColor3 = n.color
					f.BackgroundTransparency = transparency
					f.Visible = true
					-- Borde de color del territorio: solo las celdas que tocan a otro dueño llevan contorno
					local stroke = f:FindFirstChild("S")
					if border then
						if not stroke then
							stroke = Instance.new("UIStroke")
							stroke.Name = "S"
							stroke.Thickness = 1.5
							stroke.Parent = f
						end
						stroke.Enabled = true
						stroke.Color = if o == state.myId then Color3.fromRGB(255, 230, 70) else vividColor(n.color, o)
					elseif stroke then
						stroke.Enabled = false
					end
					-- Misma celda que cambia de dueño = conquista: destello que se asienta
					if state.animReady and prevCell == cell and prevOwner ~= o and detail.flashCount < 700 then
						if not detail.flashing[f] then
							detail.flashCount += 1
						end
						detail.flashing[f] = { t0 = os.clock(), color = n.color, transp = transparency }
						f.BackgroundColor3 = n.color:Lerp(Color3.new(1, 1, 1), 0.65)
						f.BackgroundTransparency = 0.05
					end
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function()
	-- Destellos de conquista en las celdas del detalle
	local now = os.clock()
	for f, d in pairs(detail.flashing) do
		local a = (now - d.t0) / FLASH_TIME
		if a >= 1 or not f.Parent then
			f.BackgroundColor3 = d.color
			f.BackgroundTransparency = d.transp
			detail.flashing[f] = nil
			detail.flashCount -= 1
		else
			f.BackgroundColor3 = d.color:Lerp(Color3.new(1, 1, 1), 0.65 * (1 - a))
			f.BackgroundTransparency = 0.05 + (d.transp - 0.05) * a
		end
	end
	-- Redibujado del detalle limitado a ~8 veces por segundo
	if state.detailDirty and now - detail.last > 0.12 then
		detail.last = now
		state.detailDirty = false
		refreshDetail()
	end
end)

-- ============================================================================
-- FASE DE APARICIÓN: cartel con cuenta atrás, círculo de vista previa, marcas de ubicación y resalte de países
-- ============================================================================
local spawnBanner = Instance.new("Frame")
spawnBanner.Name = "SpawnBanner"
spawnBanner.AnchorPoint = Vector2.new(0.5, 0)
spawnBanner.Position = UDim2.new(0.5, 0, 0, 64)
spawnBanner.Size = UDim2.fromOffset(580, 82)
spawnBanner.BackgroundColor3 = Color3.fromRGB(12, 20, 36)
spawnBanner.BackgroundTransparency = 0.04
spawnBanner.BorderSizePixel = 0
spawnBanner.Visible = false
spawnBanner.ZIndex = 40
spawnBanner.Parent = root

local spawnBannerCorner = Instance.new("UICorner")
spawnBannerCorner.CornerRadius = UDim.new(0, 12)
spawnBannerCorner.Parent = spawnBanner

local spawnBannerStroke = Instance.new("UIStroke")
spawnBannerStroke.Color = Color3.fromRGB(0, 220, 255)
spawnBannerStroke.Thickness = 2
spawnBannerStroke.Parent = spawnBanner

local function bannerLabel(pos, size, font, textSize, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = font
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.TextWrapped = true
	l.ZIndex = 41
	l.Parent = spawnBanner
	return l
end
local bannerTitle = bannerLabel(
	UDim2.fromOffset(16, 8),
	UDim2.new(1, -110, 0, 26),
	Enum.Font.GothamBlack,
	18,
	Color3.fromRGB(240, 248, 255),
	Enum.TextXAlignment.Left
)
local bannerTime = bannerLabel(
	UDim2.new(1, -96, 0, 8),
	UDim2.fromOffset(80, 26),
	Enum.Font.GothamBlack,
	18,
	Color3.fromRGB(0, 220, 255),
	Enum.TextXAlignment.Right
)
local bannerSub = bannerLabel(
	UDim2.fromOffset(16, 34),
	UDim2.new(1, -32, 0, 28),
	Enum.Font.Gotham,
	12,
	Color3.fromRGB(170, 190, 220),
	Enum.TextXAlignment.Left
)
bannerSub.TextYAlignment = Enum.TextYAlignment.Top

local bannerBarBack = Instance.new("Frame")
bannerBarBack.Position = UDim2.new(0, 16, 1, -14)
bannerBarBack.Size = UDim2.new(1, -32, 0, 6)
bannerBarBack.BackgroundColor3 = Color3.fromRGB(30, 44, 70)
bannerBarBack.BorderSizePixel = 0
bannerBarBack.ZIndex = 41
bannerBarBack.Parent = spawnBanner
local bannerBarBackCorner = Instance.new("UICorner")
bannerBarBackCorner.CornerRadius = UDim.new(1, 0)
bannerBarBackCorner.Parent = bannerBarBack
local bannerBar = Instance.new("Frame")
bannerBar.Size = UDim2.fromScale(1, 1)
bannerBar.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
bannerBar.BorderSizePixel = 0
bannerBar.ZIndex = 42
bannerBar.Parent = bannerBarBack
local bannerBarCorner = Instance.new("UICorner")
bannerBarCorner.CornerRadius = UDim.new(1, 0)
bannerBarCorner.Parent = bannerBar

local function updateSpawnUI()
	local s = state.stats
	local spawning = s ~= nil and s.phase == "SPAWN"
	spawnBanner.Visible = spawning and state.initialized and not lobbyScreen.Visible
	if not spawning then
		return
	end
	local countries = state.mode == "COUNTRIES"
	local placed = state.me ~= nil and state.me.alive == true
	local left = s.spawnTimer or 0
	bannerTitle.Text = if countries then "🌍 ELIGE TU PAÍS" else "📍 ELIGE TU UBICACIÓN INICIAL"
	if countries then
		bannerSub.Text = if placed
			then "Ya tienes país. Puedes cambiarlo haciendo clic en otro hasta que acabe el tiempo."
			else "Haz clic sobre un país del mapa o elígelo en la lista (botón 🌍 Países). Los 🔒 ya tienen jugador."
	else
		bannerSub.Text = if placed
			then "Ubicación fijada. Haz clic en otro punto libre para cambiarla antes de que acabe el tiempo."
			else "Haz clic en cualquier terreno libre para colocar tu capital. El círculo verde indica que cabe; rojo, que está ocupado."
	end
	bannerTime.Text = "⏱ " .. left .. "s"
	bannerBar.Size = UDim2.fromScale(math.clamp(left / math.max(1, s.spawnTotal or 25), 0, 1), 1)
	bannerBar.BackgroundColor3 = if left <= 5 then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(0, 220, 255)
	spawnBannerStroke.Color = bannerBar.BackgroundColor3
end

-- Anillo reutilizable (círculo con borde) sobre el mapa, dimensionado en celdas
local function makeRing(parent, zIndex)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	f.Visible = false
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Parent = f
	return f, s
end

local function placeRing(ring, cell, diameterCells)
	ring.Position = UDim2.fromScale((cell % state.w + 0.5) / state.w, (cell // state.w + 0.5) / state.h)
	ring.Size = UDim2.fromScale(diameterCells / state.w, diameterCells / state.h)
end

-- Vista previa de la ubicación (modo Libre): el círculo tiene el tamaño real del territorio inicial
local previewRing, previewStroke = makeRing(mapCanvas, 8)
previewRing.BackgroundTransparency = 0.78
local myPing, myPingStroke = makeRing(mapCanvas, 9)
myPingStroke.Color = Color3.fromRGB(255, 220, 0)
local pingFrames = {} -- marcas de otros jugadores: [nid] = { ring, stroke, label }

-- ¿Cabe un territorio inicial en esa celda? Misma regla que el servidor: tierra y 7x7 celdas libres
local function spawnValid(cell)
	if not state.land or not state.owner then
		return false
	end
	if buffer.readu8(state.land, cell) ~= 1 then
		return false
	end
	local w, h = state.w, state.h
	local cx, cy = cell % w, cell // w
	for dy = -3, 3 do
		local y = cy + dy
		if y >= 0 and y < h then
			for dx = -3, 3 do
				if buffer.readu8(state.owner, y * w + ((cx + dx) % w)) ~= 0 then
					return false
				end
			end
		end
	end
	return true
end

local function pointerOverUI(mp)
	local panel = root:FindFirstChild("CountryPanel")
	for _, ui in ipairs({ bottomHUD, leaderFrame, zoomBar, topBar, spawnBanner, panel or topBar }) do
		if ui.Visible then
			local p, s = ui.AbsolutePosition, ui.AbsoluteSize
			if mp.X >= p.X and mp.X <= p.X + s.X and mp.Y >= p.Y and mp.Y <= p.Y + s.Y then
				return true
			end
		end
	end
	return false
end

-- Marcas de los demás jugadores durante la aparición (para ver dónde se colocan los amigos)
local function updatePlayerPings()
	local s = state.stats
	local seen = {}
	if s and s.phase == "SPAWN" and s.humans then
		for _, p in ipairs(s.humans) do
			if p.nid ~= state.myId and p.alive and p.capital then
				seen[p.nid] = true
				local pf = pingFrames[p.nid]
				if not pf then
					local ring, stroke = makeRing(mapCanvas, 9)
					local rosterEntry = state.rosterById[p.nid]
					stroke.Color = if rosterEntry and rosterEntry.color
						then rosterEntry.color:Lerp(Color3.new(1, 1, 1), 0.3)
						else Color3.fromRGB(120, 235, 160)
					local label = Instance.new("TextLabel")
					label.AnchorPoint = Vector2.new(0.5, 0)
					label.BackgroundTransparency = 1
					label.Font = Enum.Font.GothamBlack
					label.TextSize = 12
					label.TextColor3 = Color3.fromRGB(235, 255, 240)
					label.TextStrokeTransparency = 0.3
					label.Size = UDim2.fromOffset(160, 16)
					label.ZIndex = 12
					label.Parent = mapCanvas
					pf = { ring = ring, stroke = stroke, label = label }
					pingFrames[p.nid] = pf
				end
				pf.cell = p.capital
				pf.label.Text = "👤 " .. p.name
				pf.ring.Visible = true
				pf.label.Visible = true
				placeRing(pf.ring, p.capital, 10.4)
				pf.label.Position = UDim2.fromScale(
					(p.capital % state.w + 0.5) / state.w,
					(p.capital // state.w + 0.5) / state.h
				) + UDim2.fromOffset(0, 18)
			end
		end
	end
	for nid, pf in pairs(pingFrames) do
		if not seen[nid] then
			pf.ring:Destroy()
			pf.label:Destroy()
			pingFrames[nid] = nil
		end
	end
end

-- Resalte del país bajo el cursor (modo Países): se tiñen sus bloques de blanco translúcido
local hlLayer = Instance.new("Frame")
hlLayer.Name = "CountryHighlight"
hlLayer.Size = UDim2.fromScale(1, 1)
hlLayer.BackgroundTransparency = 1
hlLayer.BorderSizePixel = 0
hlLayer.ZIndex = -2
hlLayer.Parent = mapCanvas
local hlPool, hlOwner = {}, nil

-- Lista de bloques de cada nación (una pasada por el mapa, por tandas para no agotar el tiempo del script)
local function buildNationBlocks()
	state.nationBlocks = nil
	if not state.owner or state.blockW == 0 then
		warn("[WorldClient] resalte de países no disponible (sin mapa de bloques)")
		return
	end
	local w, h, bw = state.w, state.h, state.blockW
	local sets = {}
	for y = 0, h - 1 do
		local rowBlock = (y // BLOCK) * bw + 1
		for x = 0, w - 1 do
			local o = buffer.readu8(state.owner, y * w + x)
			if o ~= 0 then
				local set = sets[o]
				if not set then
					set = {}
					sets[o] = set
				end
				set[rowBlock + x // BLOCK] = true
			end
		end
		if y % 40 == 39 then
			task.wait()
		end
	end
	local lists = {}
	for o, set in pairs(sets) do
		local l = {}
		for bi in pairs(set) do
			l[#l + 1] = bi
		end
		lists[o] = l
	end
	state.nationBlocks = lists
	hlOwner = nil -- fuerza a recalcular el resalte con la lista nueva
end

local function setHighlight(ownerId)
	if hlOwner == ownerId then
		return
	end
	if ownerId and not state.nationBlocks then
		return -- la lista aún se está construyendo: no se cachea, se reintenta en el siguiente fotograma
	end
	hlOwner = ownerId
	local list = if ownerId and state.nationBlocks then state.nationBlocks[ownerId] else nil
	local used = 0
	if list then
		local bw, bh = state.blockW, state.blockH
		for _, bi in ipairs(list) do
			used += 1
			local f = hlPool[used]
			if not f then
				f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.ZIndex = 4
				f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				f.BackgroundTransparency = 0.62
				f.Parent = hlLayer
				hlPool[used] = f
			end
			f.Position = UDim2.fromScale(((bi - 1) % bw) / bw, ((bi - 1) // bw) / bh)
			f.Size = UDim2.fromScale(1 / bw, 1 / bh)
			f.Visible = true
		end
	end
	for i = used + 1, #hlPool do
		hlPool[i].Visible = false
	end
end

RunService.RenderStepped:Connect(function()
	local s = state.stats
	local ready = state.initialized and state.owner ~= nil and not lobbyScreen.Visible
	local spawning = ready and s ~= nil and s.phase == "SPAWN"
	local placed = state.me ~= nil and state.me.alive == true
	local mp = Vector2.new(mouse.X, mouse.Y)
	local cell = -1
	if ready and not (drag.active and drag.moved) and not pointerOverUI(mp) then
		cell = screenToCell(mp)
	end

	-- Círculo de vista previa: modo Libre, mientras se puede elegir (aparición, o si aún no tienes territorio)
	local canPickFree = ready
		and state.mode == "FREE"
		and cell >= 0
		and (spawning or not placed)
		and not (s and s.phase == "ENDED")
	-- Arma apuntada: el círculo muestra el área real del impacto
	local armedKind = nil
	if state.actionMode == "NUKE" then
		armedKind = "NUKE"
	elseif state.actionMode:sub(1, 7) == "WEAPON_" then
		armedKind = state.actionMode:sub(8)
	end
	local armedInfo = if armedKind then WEAPON_INFO[armedKind] else nil
	if armedInfo and ready and placed and not spawning and cell >= 0 then
		previewStroke.Color = armedInfo.color
		previewRing.BackgroundColor3 = armedInfo.color
		placeRing(previewRing, cell, armedInfo.radius * 2 + 1)
		previewRing.Visible = true
	elseif canPickFree then
		previewStroke.Color = if spawnValid(cell) then Color3.fromRGB(70, 255, 150) else Color3.fromRGB(255, 80, 80)
		previewRing.BackgroundColor3 = previewStroke.Color
		placeRing(previewRing, cell, 10.4)
		previewRing.Visible = true
	else
		previewRing.Visible = false
	end

	-- Resalte del país bajo el cursor (modo Países, si aún se puede elegir)
	local hl = nil
	if ready and state.mode == "COUNTRIES" and cell >= 0 and (spawning or not placed) then
		local o = buffer.readu8(state.owner, cell)
		local n = state.rosterById[o]
		if o ~= 0 and n and n.countryId and n.bot ~= false then
			hl = o
		end
	end
	setHighlight(hl)

	-- Pulso en tu ubicación y en la de los demás jugadores durante la aparición
	local t = (os.clock() % 1.4) / 1.4
	local mine = state.rosterById[state.myId]
	if spawning and placed and mine and mine.capital and mine.capital >= 0 then
		placeRing(myPing, mine.capital, 5 + 12 * t)
		myPingStroke.Transparency = t
		myPing.Visible = true
	else
		myPing.Visible = false
	end
	for _, pf in pairs(pingFrames) do
		if pf.cell and pf.ring.Visible then
			placeRing(pf.ring, pf.cell, 5 + 9 * t)
			pf.stroke.Transparency = t * 0.8
		end
	end
end)

-- ============================================================================
-- FRENTE DE CONQUISTA: animación de expansión a escala de celda
-- Cada celda que cambia de dueño aparece como un cuadro de UNA celda, claro, que se apaga en ~1,3 s mientras el
-- tinte de bloques ya recoge el cambio. Se ve avanzar el territorio píxel a píxel aunque el mapa vaya en bloques.
-- Solo se animan celdas visibles, con presupuesto por actualización y tope de cuadros activos (rendimiento).
-- ============================================================================
local FRONT_MAX_ACTIVE = 5000
local FRONT_PER_DIFF = 500
local FRONT_FADE = 1.3
local front = {
	layer = nil,
	free = {},
	active = {},
	count = 0,
	chance = 1,
	x0 = 0,
	x1 = -1,
	y0 = 0,
	y1 = -1,
}

-- Se llama una vez por cada paquete de cambios: calcula la zona visible y qué fracción de celdas se animará
local function frontBegin(changes)
	if not front.layer then
		local l = Instance.new("Frame")
		l.Name = "FrontLayer"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.ZIndex = 4
		l.Parent = mapCanvas
		front.layer = l
	end
	front.chance = math.min(1, FRONT_PER_DIFF / math.max(1, changes))
	local w, h = state.w, state.h
	local vs = mapContainer.AbsoluteSize
	local cellW = BASE_WIDTH * state.zoom / w
	local cellH = BASE_HEIGHT * state.zoom / h
	local left = vs.X / 2 + state.pan.X - BASE_WIDTH * state.zoom / 2
	local top = vs.Y / 2 + state.pan.Y - BASE_HEIGHT * state.zoom / 2
	front.x0 = math.max(0, math.floor(-left / cellW))
	front.x1 = math.min(w - 1, math.ceil((vs.X - left) / cellW))
	front.y0 = math.max(0, math.floor(-top / cellH))
	front.y1 = math.min(h - 1, math.ceil((vs.Y - top) / cellH))
end

local function frontPush(cell, ownerId)
	if front.count >= FRONT_MAX_ACTIVE or math.random() > front.chance then
		return
	end
	local w = state.w
	local x, y = cell % w, cell // w
	if x < front.x0 or x > front.x1 or y < front.y0 or y > front.y1 then
		return
	end
	local n = state.rosterById[ownerId]
	if not n then
		return
	end
	local f = table.remove(front.free)
	if not f then
		f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.ZIndex = 4
		f.Size = UDim2.fromScale(1 / w, 1 / state.h)
		f.Parent = front.layer
	end
	f.Position = UDim2.fromScale(x / w, y / state.h)
	f.BackgroundColor3 = n.color:Lerp(Color3.new(1, 1, 1), 0.5)
	f.BackgroundTransparency = 0.05
	f.Visible = true
	front.active[#front.active + 1] = { f = f, t0 = os.clock() }
	front.count += 1
end

local frontAcc = 0
RunService.Heartbeat:Connect(function(dt)
	frontAcc += dt
	if frontAcc < 0.066 then -- ~15 actualizaciones por segundo bastan para un desvanecido
		return
	end
	frontAcc = 0
	local now = os.clock()
	local act = front.active
	local i = 1
	while i <= #act do
		local a = act[i]
		local t = (now - a.t0) / FRONT_FADE
		if t >= 1 then
			a.f.Visible = false
			table.insert(front.free, a.f)
			front.count -= 1
			act[i] = act[#act]
			act[#act] = nil
		else
			a.f.BackgroundTransparency = 0.05 + 0.95 * t * t -- se mantiene visible al principio y se apaga al final
			i += 1
		end
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
	-- Sin tarjeta mientras arrastras el mapa o si el ratón está sobre un panel (no debe tapar los botones)
	local blocked = drag.active and drag.moved
	if not blocked then
		-- countryPanel se declara más abajo en el archivo: se busca por nombre
		local panel = root:FindFirstChild("CountryPanel")
		for _, ui in ipairs({ bottomHUD, leaderFrame, zoomBar, panel or topBar, topBar }) do
			if ui.Visible then
				local p, s = ui.AbsolutePosition, ui.AbsoluteSize
				if mp.X >= p.X and mp.X <= p.X + s.X and mp.Y >= p.Y and mp.Y <= p.Y + s.Y then
					blocked = true
					break
				end
			end
		end
	end
	local cell = if blocked then -1 else screenToCell(mp)
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
-- Mismos tonos que usa el servidor para colorear cada continente (África, Antártida, Asia, Europa, Norteamérica, Oceanía, Sudamérica)
local TEAM_HUES = { 0.08, 0.55, 0.0, 0.58, 0.33, 0.8, 0.15 }

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
	state.teamMode = data.teamMode == true
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
	fitToScreen() -- vista inicial: el mundo entero ajustado a la pantalla
	if data.mode == "COUNTRIES" then -- state.mode aún no se ha actualizado en este punto
		task.spawn(buildNationBlocks) -- para resaltar el país bajo el cursor al elegir
	else
		state.nationBlocks = nil
		setHighlight(nil)
	end

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

-- Entra un jugador a mitad de partida: se añade su nación para ver su color, su rótulo y su capital
WorldRoster.OnClientEvent:Connect(function(entry)
	if not state.initialized or type(entry) ~= "table" or not entry.id then
		return -- si aún no hay partida, el WorldInit que llegue ya la incluirá
	end
	entry.color = Color3.fromRGB(entry.r or 200, entry.g or 200, entry.b or 200)
	local replaced = false
	for i, e in ipairs(state.roster) do
		if e.id == entry.id then
			state.roster[i] = entry
			replaced = true
			break
		end
	end
	if not replaced then
		table.insert(state.roster, entry)
	end
	state.rosterById[entry.id] = entry
	updateMarkers()
end)

local function applyDiff(diffBuf)
	-- Mientras se crean los bloques solo se anotan los dueños (el dibujado completo llega después)
	if state.owner and state.blockBuilding then
		for i = 0, math.floor(buffer.len(diffBuf) / 4) - 1 do
			local packed = buffer.readu32(diffBuf, i * 4)
			local cell = math.floor(packed / 256)
			if cell < (state.w * state.h) then
				buffer.writeu8(state.owner, cell, packed % 256)
			end
		end
		return
	end
	if not state.owner or (not state.editableImage and not state.blockMode) then
		return
	end

	local count = math.floor(buffer.len(diffBuf) / 4)
	-- Con el mapa por bloques, las celdas conquistadas se animan una a una (el detalle por celdas ya anima las suyas)
	local animateFront = state.blockMode and state.animReady and not detail.active and not lobbyScreen.Visible
	if animateFront then
		frontBegin(count)
	end
	-- Con EditableImage, el borde de una celda depende de sus vecinas: al cambiar una, hay que repintar las 4 de alrededor
	local repaintNeighbors = state.editableImage ~= nil and not state.blockMode
	local changed = if repaintNeighbors then {} else nil
	for i = 0, count - 1 do
		local packed = buffer.readu32(diffBuf, i * 4)
		local cell = math.floor(packed / 256)
		local ownerId = packed % 256

		if cell < (state.w * state.h) then
			local previous = buffer.readu8(state.owner, cell)
			buffer.writeu8(state.owner, cell, ownerId)
			drawCell(cell, ownerId)
			if changed then
				changed[#changed + 1] = cell
			end
			if animateFront and ownerId ~= 0 and previous ~= ownerId then
				frontPush(cell, ownerId)
			end
		end
	end
	if changed then
		local w, h = state.w, state.h
		local seen = {}
		for _, cell in ipairs(changed) do
			local x, y = cell % w, cell // w
			local around = {
				y * w + (if x == 0 then w - 1 else x - 1),
				y * w + (if x == w - 1 then 0 else x + 1),
				if y > 0 then cell - w else nil,
				if y < h - 1 then cell + w else nil,
			}
			for k = 1, 4 do
				local nb = around[k]
				if nb and not seen[nb] then
					seen[nb] = true
					drawCell(nb, buffer.readu8(state.owner, nb))
				end
			end
		end
	end

	flushImage()
end

-- Suavizado: el servidor manda un lote cada 0,2 s. Si es grande se reparte en 4 trozos a lo largo de ese intervalo
-- para que el territorio crezca de forma continua en vez de aparecer de golpe.
local DIFF_SLICES = 4
local DIFF_SLICE_DELAY = 0.05
WorldDiff.OnClientEvent:Connect(function(diffBuf)
	local count = math.floor(buffer.len(diffBuf) / 4)
	if count < 40 or state.blockBuilding or not state.animReady then
		applyDiff(diffBuf)
		return
	end
	local per = math.ceil(count / DIFF_SLICES)
	for s = 0, DIFF_SLICES - 1 do
		local first = s * per
		local n = math.min(per, count - first)
		if n > 0 then
			local slice = buffer.create(n * 4)
			buffer.copy(slice, 0, diffBuf, first * 4, n * 4)
			if s == 0 then
				applyDiff(slice)
			else
				task.delay(s * DIFF_SLICE_DELAY, function()
					applyDiff(slice)
				end)
			end
		end
	end
end)

WorldStats.OnClientEvent:Connect(function(stats)
	state.stats = stats
	updateFronts(stats.fronts)
	updateSpawnUI()
	updatePlayerPings()
	-- Búsquedas rápidas para el tooltip y el ranking
	state.statById = {}
	for _, e in ipairs(stats.nations or {}) do
		state.statById[e.id] = e
	end
	updateLabelTroops()
	state.humanById = {}
	for _, t in ipairs(stats.taken or {}) do
		state.humanById[t.nid] = t
	end
	-- La lista de naciones es estática: las capitales de los jugadores se actualizan según se colocan
	local capitalMoved = false
	for _, hu in ipairs(stats.humans or {}) do
		local r = state.rosterById[hu.nid]
		if r and hu.capital and r.capital ~= hu.capital then
			r.capital = hu.capital
			capitalMoved = true
		end
		-- El continente de un jugador cambia al elegir país: define su equipo
		if r and hu.team and r.continent ~= hu.team then
			r.continent = hu.team
			if state.teamMode and state.rebuildEdges then
				task.spawn(state.rebuildEdges)
			end
		end
	end
	if capitalMoved then
		updateMarkers()
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

	-- Modo equipos: la clasificación muestra los continentes (equipos) en vez de países sueltos
	local board = stats.top
	if stats.teams then
		leaderTitle.Text = "🤝 EQUIPOS (CONTINENTES)"
		local myTeam = nil
		for _, hu in ipairs(stats.humans or {}) do
			if hu.nid == state.myId then
				myTeam = hu.team
			end
		end
		board = {}
		for _, t in ipairs(stats.teams) do
			table.insert(board, {
				name = CONTINENT_NAMES[t.id] or "Equipo",
				pct = t.pct,
				isMe = (t.id == myTeam),
				isTeam = true,
				color = Color3.fromHSV(TEAM_HUES[t.id] or 0.5, 0.7, 1),
				isBot = true,
			})
		end
	else
		leaderTitle.Text = "🏆 CLASIFICACIÓN MUNDIAL"
	end

	if board then
		for rank, entry in ipairs(board) do
			if rank <= 7 then
				if not entry.isTeam then
					entry.isMe = entry.id == state.myId -- el servidor no envía esta marca
				end
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
				swatch.BackgroundColor3 = if entry.color
					then entry.color
					elseif rosterEntry and rosterEntry.color then rosterEntry.color
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

				-- El ScreenGui usa capas globales: la fila y sus textos deben quedar por encima de los rótulos del mapa
				row.ZIndex = 22
				for _, d in ipairs(row:GetDescendants()) do
					if d:IsA("GuiObject") then
						d.ZIndex = 23
					end
				end
			end
		end
	end
end)

-- Modo espectador: quien es eliminado por las tropas rivales pierde y solo puede observar la partida
local spectatorBanner = Instance.new("TextLabel")
spectatorBanner.Name = "SpectatorBanner"
spectatorBanner.AnchorPoint = Vector2.new(0.5, 1)
spectatorBanner.Position = UDim2.new(0.5, 0, 1, -16)
spectatorBanner.Size = UDim2.fromOffset(460, 40)
spectatorBanner.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
spectatorBanner.BackgroundTransparency = 0.12
spectatorBanner.BorderSizePixel = 0
spectatorBanner.Font = Enum.Font.GothamBold
spectatorBanner.Text = "💀 Has sido eliminado · Modo espectador"
spectatorBanner.TextColor3 = Color3.fromRGB(255, 120, 120)
spectatorBanner.TextSize = 15
spectatorBanner.Visible = false
spectatorBanner.ZIndex = 25
spectatorBanner.Parent = root
roundCorners(spectatorBanner, 10)

-- Píldora "Atacando a X con N" (estilo RoWorld): tu ataque más grande contra otra nación
local attackPill = Instance.new("TextLabel")
attackPill.Name = "AttackPill"
attackPill.AnchorPoint = Vector2.new(0.5, 0)
attackPill.Position = UDim2.new(0.5, 0, 0, 74)
attackPill.Size = UDim2.fromOffset(300, 26)
attackPill.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
attackPill.BackgroundTransparency = 0.1
attackPill.BorderSizePixel = 0
attackPill.Font = Enum.Font.GothamBold
attackPill.TextColor3 = Color3.fromRGB(255, 205, 80)
attackPill.TextSize = 13
attackPill.Visible = false
attackPill.ZIndex = 24
attackPill.Parent = root
roundCorners(attackPill, 13)

local function updateAttackPill(meData)
	local best, bestTroops = nil, 0
	for _, a in ipairs(meData.attacks or {}) do
		if a.target and a.target ~= 0 and a.troops > bestTroops then
			best, bestTroops = a, a.troops
		end
	end
	local target = best and state.rosterById[best.target]
	if best and target then
		attackPill.Text = string.format("⚔️ Atacando a %s con %s", target.name, troopText(best.troops))
		attackPill.Size = UDim2.fromOffset(math.max(220, #attackPill.Text * 8), 26)
		attackPill.Visible = true
	else
		attackPill.Visible = false
	end
end

-- ----------------------------------------------------------------------------
-- ALIANZAS: botón "🤝 Alianza" (luego clic en el territorio de una nación para proponer o romper) y tarjetas de
-- solicitudes entrantes con Aceptar / Rechazar
-- ----------------------------------------------------------------------------
local btnAlly = Instance.new("TextButton")
btnAlly.Name = "BtnAlly"
btnAlly.AnchorPoint = Vector2.new(1, 0.5)
btnAlly.Position = UDim2.new(1, -386, 0.5, 0)
btnAlly.Size = UDim2.fromOffset(110, 34)
btnAlly.BackgroundColor3 = Color3.fromRGB(70, 60, 130)
btnAlly.Font = Enum.Font.GothamBold
btnAlly.Text = "🤝 Alianza"
btnAlly.TextColor3 = Color3.fromRGB(255, 255, 255)
btnAlly.TextSize = 12
btnAlly.BorderSizePixel = 0
btnAlly.ZIndex = 21
btnAlly.Parent = topBar
roundCorners(btnAlly, 6)

btnAlly.MouseButton1Click:Connect(function()
	state.allyMode = not state.allyMode
	btnAlly.BackgroundColor3 = if state.allyMode then Color3.fromRGB(150, 120, 255) else Color3.fromRGB(70, 60, 130)
	if state.allyMode then
		state.showToast(
			"🤝 Haz clic en el territorio de una nación: propones alianza (o la rompes si ya sois aliados)",
			Color3.fromRGB(180, 160, 255)
		)
	end
end)

local allyCards = Instance.new("Frame")
allyCards.Name = "AllyCards"
allyCards.AnchorPoint = Vector2.new(0.5, 0)
allyCards.Position = UDim2.new(0.5, 0, 0, 108)
allyCards.Size = UDim2.fromOffset(380, 200)
allyCards.BackgroundTransparency = 1
allyCards.ZIndex = 26
allyCards.Parent = root
local allyLayout = Instance.new("UIListLayout")
allyLayout.Padding = UDim.new(0, 6)
allyLayout.Parent = allyCards

local function updateAllyCards(meData)
	local info = meData.ally
	local requests = info and info.requests or {}
	for _, c in ipairs(allyCards:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, req in ipairs(requests) do
		if i > 3 then
			break
		end
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 58)
		card.BackgroundColor3 = Color3.fromRGB(22, 28, 46)
		card.BackgroundTransparency = 0.05
		card.BorderSizePixel = 0
		card.ZIndex = 27
		card.Parent = allyCards
		roundCorners(card, 8)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -12, 0, 22)
		title.Position = UDim2.fromOffset(8, 4)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 12
		title.TextColor3 = Color3.fromRGB(235, 240, 255)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = string.format("🤝 %s propone una alianza (%ds)", req.name, req.left)
		title.ZIndex = 28
		title.Parent = card

		local function makeButton(text, x, color, action)
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromOffset(110, 24)
			b.Position = UDim2.fromOffset(x, 30)
			b.BackgroundColor3 = color
			b.Font = Enum.Font.GothamBold
			b.TextSize = 12
			b.TextColor3 = Color3.new(1, 1, 1)
			b.Text = text
			b.BorderSizePixel = 0
			b.ZIndex = 28
			b.Parent = card
			roundCorners(b, 6)
			b.MouseButton1Click:Connect(function()
				WorldCommand:FireServer({ a = action, target = req.from })
				card:Destroy()
			end)
		end
		makeButton("Aceptar", 8, Color3.fromRGB(40, 150, 90), "ALLY_ACCEPT")
		makeButton("Rechazar", 126, Color3.fromRGB(150, 60, 60), "ALLY_DECLINE")
	end
end

local function setSpectator(on)
	if spectatorBanner.Visible == on then
		return
	end
	spectatorBanner.Visible = on
	bottomHUD.Visible = not on
	weaponBar.Visible = not on
end

WorldMe.OnClientEvent:Connect(function(meData)
	local wasAlive = state.me and state.me.alive
	state.me = meData
	setSpectator(meData.eliminated == true)
	updateAttackPill(meData)
	updateAllyCards(meData)
	updateSpawnUI()
	updateWeaponCooldowns(meData.weapons)
	if meData.autoMode and meData.autoMode ~= state.autoMode then
		state.autoMode = meData.autoMode -- el servidor manda: refleja el estado real del autojuego
		state.refreshAuto()
	end
	-- Al conseguir tu país (o aparecer), la cámara se acerca a tu capital
	if meData.alive and not wasAlive and meData.capital and meData.capital >= 0 then
		focusCell(meData.capital, fitZoom() * 2.4)
	end
	if meData.capital and meData.capital >= 0 then
		local myRoster = state.rosterById[state.myId]
		if myRoster and myRoster.capital ~= meData.capital then
			myRoster.capital = meData.capital
			updateMarkers()
		end
	end
	-- Valores reales del servidor: tropas/tope y ritmo por segundo (crecimiento compuesto), oro y su ritmo
	troopsCard.Text = string.format(
		"⚔️ Tropas: %d/%d (+%d/s)",
		meData.troops or 0,
		meData.maxTroops or 0,
		math.floor((meData.troopRate or 0) + 0.5)
	)
	goldCard.Text = string.format("💰 Oro: %d (+%d/s)", meData.gold or 0, math.floor((meData.goldRate or 0) + 0.5))
end)

WorldNotice.OnClientEvent:Connect(function(msg)
	showToast(msg, Color3.fromRGB(255, 220, 50))
end)

-- La partida empieza cuando el jugador pulsa JUGAR en la pantalla de lobby (ver LobbyScreen).

updateMapTransform()
