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
local OCEAN_COLOR = Color3.fromRGB(18, 34, 56) -- FrontWars Deep Navy
local DEEP_OCEAN_COLOR = Color3.fromRGB(12, 24, 40)
local UNCLAIMED_LAND = Color3.fromRGB(158, 178, 142) -- FrontWars Flat Pastel Sage
local UNCLAIMED_BORDER = Color3.fromRGB(130, 150, 115)
local HUMAN_AURA_COLOR = Color3.fromRGB(255, 220, 0)
local BASE_WIDTH = 2400
local BASE_HEIGHT = 1000

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
	dirtyRect = { x0 = math.huge, y0 = math.huge, x1 = -1, y1 = -1 },
	hasDirty = false,
}

-- Referencias de UIScale responsivo automático (1080p / 720p / Móvil)
local radarScale = nil
local zoomScale = nil
local spawnScale = nil
local modalScale = nil
local topBarScale = nil

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

local function roundCorners(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = obj
	return c
end

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
-- TOP CONTROLS & HUD (Estilo OpenFront.io minimalista)
-- ============================================================================
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 50)
topBar.Position = UDim2.fromOffset(0, 0)
topBar.BackgroundTransparency = 1
topBar.BorderSizePixel = 0
topBar.ZIndex = 20
topBar.Parent = root

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Visible = false
titleLabel.Parent = topBar

local phaseBadge = Instance.new("Frame")
phaseBadge.Name = "PhaseBadge"
phaseBadge.Visible = false
phaseBadge.Parent = topBar

local phaseText = Instance.new("TextLabel")
phaseText.Name = "PhaseText"
phaseText.Parent = phaseBadge

local phaseStroke = Instance.new("UIStroke")
phaseStroke.Parent = phaseBadge

-- Dock flotante superior derecho (Estilo OpenFront.io: Reloj, Centrar, Táctica, Salir)
local inGameDock = Instance.new("Frame")
inGameDock.Name = "OpenFrontInGameDock"
inGameDock.AnchorPoint = Vector2.new(1, 0)
inGameDock.Position = UDim2.new(1, -16, 0, 10)
inGameDock.Size = UDim2.fromOffset(360, 36)
inGameDock.BackgroundColor3 = Color3.fromRGB(15, 22, 35)
inGameDock.BackgroundTransparency = 0.08
inGameDock.BorderSizePixel = 0
inGameDock.ZIndex = 25
inGameDock.Parent = topBar
roundCorners(inGameDock, 8)

local dockStroke = Instance.new("UIStroke")
dockStroke.Color = Color3.fromRGB(34, 49, 74)
dockStroke.Thickness = 1.2
dockStroke.Parent = inGameDock

local clockLabel = Instance.new("TextLabel")
clockLabel.Name = "ClockLabel"
clockLabel.Position = UDim2.fromOffset(10, 0)
clockLabel.Size = UDim2.fromOffset(65, 36)
clockLabel.BackgroundTransparency = 1
clockLabel.Font = Enum.Font.GothamBlack
clockLabel.Text = "00:00"
clockLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
clockLabel.TextSize = 14
clockLabel.ZIndex = 26
clockLabel.Parent = inGameDock

-- Botón Centrar Cámara
local btnCenter = Instance.new("TextButton")
btnCenter.Name = "BtnCenter"
btnCenter.Position = UDim2.fromOffset(80, 4)
btnCenter.Size = UDim2.fromOffset(34, 28)
btnCenter.BackgroundColor3 = Color3.fromRGB(24, 34, 52)
btnCenter.Font = Enum.Font.GothamBold
btnCenter.Text = "🎯"
btnCenter.TextColor3 = Color3.fromRGB(255, 220, 0)
btnCenter.TextSize = 14
btnCenter.BorderSizePixel = 0
btnCenter.ZIndex = 26
btnCenter.Parent = inGameDock
roundCorners(btnCenter, 6)

-- Botón Configuración Táctica / Atajos
local btnTactical = Instance.new("TextButton")
btnTactical.Name = "BtnTactical"
btnTactical.Position = UDim2.fromOffset(120, 4)
btnTactical.Size = UDim2.fromOffset(34, 28)
btnTactical.BackgroundColor3 = Color3.fromRGB(24, 34, 52)
btnTactical.Font = Enum.Font.GothamBold
btnTactical.Text = "⚙"
btnTactical.TextColor3 = Color3.fromRGB(245, 175, 45)
btnTactical.TextSize = 14
btnTactical.BorderSizePixel = 0
btnTactical.ZIndex = 26
btnTactical.Parent = inGameDock
roundCorners(btnTactical, 6)

-- Botón Menú / Hub OpenFront
local btnLobby = Instance.new("TextButton")
btnLobby.Name = "BtnLobby"
btnLobby.Position = UDim2.fromOffset(160, 4)
btnLobby.Size = UDim2.fromOffset(95, 28)
btnLobby.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
btnLobby.Font = Enum.Font.GothamBlack
btnLobby.Text = "↪ MENÚ"
btnLobby.TextColor3 = Color3.fromRGB(255, 255, 255)
btnLobby.TextSize = 11
btnLobby.BorderSizePixel = 0
btnLobby.ZIndex = 26
btnLobby.Parent = inGameDock
roundCorners(btnLobby, 6)

-- Botón Clasificación flotante superior izquierdo
local btnLeaderToggle = Instance.new("TextButton")
btnLeaderToggle.Name = "BtnLeaderToggle"
btnLeaderToggle.Position = UDim2.fromOffset(16, 10)
btnLeaderToggle.Size = UDim2.fromOffset(126, 36)
btnLeaderToggle.BackgroundColor3 = Color3.fromRGB(15, 22, 35)
btnLeaderToggle.BackgroundTransparency = 0.08
btnLeaderToggle.Font = Enum.Font.GothamBold
btnLeaderToggle.Text = "📊 Clasificación"
btnLeaderToggle.TextColor3 = Color3.fromRGB(240, 245, 255)
btnLeaderToggle.TextSize = 12
btnLeaderToggle.BorderSizePixel = 0
btnLeaderToggle.ZIndex = 25
btnLeaderToggle.Parent = topBar
roundCorners(btnLeaderToggle, 8)
local ltgStroke = Instance.new("UIStroke")
ltgStroke.Color = Color3.fromRGB(34, 49, 74)
ltgStroke.Thickness = 1.2
ltgStroke.Parent = btnLeaderToggle

-- Modal emergente de Configuración Táctica / Atajos rápidos (Tecla H o botón en barra superior)
local tacticalModal = Instance.new("Frame")
tacticalModal.Name = "TacticalConfigModal"
tacticalModal.AnchorPoint = Vector2.new(0.5, 0.5)
tacticalModal.Position = UDim2.fromScale(0.5, 0.5)
tacticalModal.Size = UDim2.fromOffset(500, 270)
tacticalModal.BackgroundColor3 = Color3.fromRGB(12, 20, 36)
tacticalModal.BorderSizePixel = 0
tacticalModal.ZIndex = 85
tacticalModal.Visible = false
tacticalModal.Parent = root
roundCorners(tacticalModal, 12)

modalScale = Instance.new("UIScale")
modalScale.Parent = tacticalModal

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = Color3.fromRGB(45, 75, 120)
modalStroke.Thickness = 2
modalStroke.Parent = tacticalModal

local modalTitle = Instance.new("TextLabel")
modalTitle.BackgroundTransparency = 1
modalTitle.Position = UDim2.fromOffset(20, 16)
modalTitle.Size = UDim2.new(1, -60, 0, 22)
modalTitle.Font = Enum.Font.GothamBlack
modalTitle.Text = "CONFIGURACIÓN TÁCTICA"
modalTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
modalTitle.TextSize = 18
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.ZIndex = 86
modalTitle.Parent = tacticalModal

local modalSub = Instance.new("TextLabel")
modalSub.BackgroundTransparency = 1
modalSub.Position = UDim2.fromOffset(20, 40)
modalSub.Size = UDim2.new(1, -60, 0, 16)
modalSub.Font = Enum.Font.GothamBold
modalSub.Text = "PREFERENCIAS DE INTERFAZ Y RENDIMIENTO"
modalSub.TextColor3 = Color3.fromRGB(245, 175, 45)
modalSub.TextSize = 11
modalSub.TextXAlignment = Enum.TextXAlignment.Left
modalSub.ZIndex = 86
modalSub.Parent = tacticalModal

local modalClose = Instance.new("TextButton")
modalClose.AnchorPoint = Vector2.new(1, 0)
modalClose.Position = UDim2.new(1, -16, 0, 16)
modalClose.Size = UDim2.fromOffset(28, 28)
modalClose.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
modalClose.BorderSizePixel = 0
modalClose.Font = Enum.Font.GothamBlack
modalClose.Text = "✕"
modalClose.TextColor3 = Color3.fromRGB(255, 255, 255)
modalClose.TextSize = 14
modalClose.ZIndex = 87
modalClose.Parent = tacticalModal
roundCorners(modalClose, 6)
modalClose.MouseButton1Click:Connect(function()
	tacticalModal.Visible = false
end)

local modalBullets = Instance.new("TextLabel")
modalBullets.BackgroundTransparency = 1
modalBullets.Position = UDim2.fromOffset(20, 68)
modalBullets.Size = UDim2.new(1, -40, 0, 80)
modalBullets.Font = Enum.Font.Gotham
modalBullets.Text = "• Atajos rápidos: H (How to Play), M (Silenciar música), Esc (Cerrar menús)\n• Escalado Responsivo UIScale: ACTIVO (Automático 1080p / 720p / Móvil)\n• Renderizado de Fronteras Iluminadas (2 pasadas): ACTIVO\n• Actualización de Bloques Sucios (Dirty Rectangles): ACTIVO"
modalBullets.TextColor3 = Color3.fromRGB(220, 230, 245)
modalBullets.TextSize = 12
modalBullets.TextXAlignment = Enum.TextXAlignment.Left
modalBullets.TextWrapped = true
modalBullets.ZIndex = 86
modalBullets.Parent = tacticalModal

local modalExtra = Instance.new("TextLabel")
modalExtra.BackgroundTransparency = 1
modalExtra.Position = UDim2.fromOffset(20, 154)
modalExtra.Size = UDim2.new(1, -40, 0, 60)
modalExtra.Font = Enum.Font.Gotham
modalExtra.Text = "🖱 Controles: Clic en país o frontera para atacar · Arrastrar para paneo · Rueda para zoom\n⌨️ Construcción: 1-0 Teclado numérico (Ciudad, Fábrica, Puerto, SAM, etc.)\n🏳️ R: Retirada táctica · G: Modo Ataque · X: Modo Demolición"
modalExtra.TextColor3 = Color3.fromRGB(150, 175, 205)
modalExtra.TextSize = 11
modalExtra.TextXAlignment = Enum.TextXAlignment.Left
modalExtra.TextWrapped = true
modalExtra.ZIndex = 86
modalExtra.Parent = tacticalModal

local commanderName = player.DisplayName or player.Name or "paespa"
if commanderName == "" then
	commanderName = "paespa"
end

local modalWelcome = Instance.new("TextLabel")
modalWelcome.BackgroundTransparency = 1
modalWelcome.Position = UDim2.fromOffset(20, 236)
modalWelcome.Size = UDim2.new(1, -40, 0, 18)
modalWelcome.Font = Enum.Font.GothamBold
modalWelcome.Text = "Bienvenido, Comandante " .. commanderName
modalWelcome.TextColor3 = Color3.fromRGB(90, 120, 160)
modalWelcome.TextSize = 12
modalWelcome.TextXAlignment = Enum.TextXAlignment.Left
modalWelcome.ZIndex = 86
modalWelcome.Parent = tacticalModal

btnTactical.MouseButton1Click:Connect(function()
	tacticalModal.Visible = not tacticalModal.Visible
end)

-- ============================================================================
-- LEADERBOARD (Top Naciones + Tu posición destacada en Neón/Oro)
-- ============================================================================
local leaderFrame = Instance.new("Frame")
leaderFrame.Name = "Leaderboard"
leaderFrame.AnchorPoint = Vector2.new(1, 0)
leaderFrame.Position = UDim2.new(1, -16, 0, 52)
leaderFrame.Size = UDim2.fromOffset(230, 250)
leaderFrame.BackgroundColor3 = Color3.fromRGB(15, 22, 35)
leaderFrame.BackgroundTransparency = 0.08
leaderFrame.BorderSizePixel = 0
leaderFrame.ZIndex = 20
leaderFrame.Parent = root
roundCorners(leaderFrame, 8)

local leaderStroke = Instance.new("UIStroke")
leaderStroke.Color = Color3.fromRGB(34, 49, 74)
leaderStroke.Thickness = 1.2
leaderStroke.Parent = leaderFrame

btnLeaderToggle.MouseButton1Click:Connect(function()
	leaderFrame.Visible = not leaderFrame.Visible
end)

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
bottomHUD.Size = UDim2.fromOffset(980, 92)
bottomHUD.BackgroundColor3 = Color3.fromRGB(15, 22, 35)
bottomHUD.BackgroundTransparency = 0.08
bottomHUD.BorderSizePixel = 0
bottomHUD.ZIndex = 20
bottomHUD.Parent = root
roundCorners(bottomHUD, 10)

local bottomStroke = Instance.new("UIStroke")
bottomStroke.Color = Color3.fromRGB(34, 49, 74)
bottomStroke.Thickness = 1.2
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
troopsCard.Size = UDim2.fromOffset(215, 30)
troopsCard.Position = UDim2.fromOffset(0, 2)
troopsCard.BackgroundColor3 = Color3.fromRGB(20, 32, 52)
troopsCard.BorderSizePixel = 0
troopsCard.Font = Enum.Font.GothamBlack
troopsCard.Text = "⚔️ 10.0K / 100K (+218)"
troopsCard.TextColor3 = Color3.fromRGB(0, 229, 255)
troopsCard.TextSize = 12
troopsCard.ZIndex = 22
troopsCard.Parent = statsRow
roundCorners(troopsCard, 6)

local troopsStroke = Instance.new("UIStroke")
troopsStroke.Color = Color3.fromRGB(0, 229, 255)
troopsStroke.Thickness = 1
troopsStroke.Parent = troopsCard

local goldCard = Instance.new("TextLabel")
goldCard.Name = "GoldCard"
goldCard.Size = UDim2.fromOffset(150, 30)
goldCard.Position = UDim2.fromOffset(223, 2)
goldCard.BackgroundColor3 = Color3.fromRGB(20, 32, 52)
goldCard.BorderSizePixel = 0
goldCard.Font = Enum.Font.GothamBlack
goldCard.Text = "💰 Oro: 700 (+15/s)"
goldCard.TextColor3 = Color3.fromRGB(255, 215, 0)
goldCard.TextSize = 12
goldCard.ZIndex = 22
goldCard.Parent = statsRow
roundCorners(goldCard, 6)

local goldStroke = Instance.new("UIStroke")
goldStroke.Color = Color3.fromRGB(45, 60, 90)
goldStroke.Thickness = 1
goldStroke.Parent = goldCard

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
local ratios = { 0.1, 0.2, 0.25, 0.5, 0.75, 1.0 }
for idx, r in ipairs(ratios) do
	local btn = Instance.new("TextButton")
	btn.Name = "Ratio_" .. math.floor(r * 100)
	btn.Size = UDim2.fromOffset(36, 26)
	btn.Position = UDim2.fromOffset(473 + (idx - 1) * 39, 4)
	btn.BackgroundColor3 = (r == 0.25) and Color3.fromRGB(0, 180, 220) or Color3.fromRGB(30, 42, 64)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBlack
	btn.Text = math.floor(r * 100) .. "%"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 10
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
local actionsRow = Instance.new("ScrollingFrame")
actionsRow.Name = "ActionsRow"
actionsRow.Size = UDim2.new(1, -20, 0, 48)
actionsRow.Position = UDim2.fromOffset(10, 44)
actionsRow.BackgroundTransparency = 1
actionsRow.ScrollBarThickness = 2
actionsRow.ScrollBarImageColor3 = Color3.fromRGB(0, 200, 240)
actionsRow.CanvasSize = UDim2.fromOffset(1320, 0)
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

local btnCity = createActionButton("BUILD_City", "CIUDAD", "$500 (+Capacidad)", Color3.fromRGB(40, 110, 180), "🏢")
btnCity.Position = UDim2.fromOffset(140, 2)

local btnFactory =
	createActionButton("BUILD_Factory", "FÁBRICA", "$600 (+Trenes/Oro)", Color3.fromRGB(150, 70, 30), "🏭")
btnFactory.Position = UDim2.fromOffset(280, 2)

local btnPort = createActionButton("BUILD_Port", "PUERTO", "$400 (Mar/Comercio)", Color3.fromRGB(30, 130, 150), "⚓")
btnPort.Position = UDim2.fromOffset(420, 2)

local btnPost =
	createActionButton("BUILD_Post", "PUESTO DEF.", "$350 (Torre x2)", Color3.fromRGB(150, 110, 20), "🛡️")
btnPost.Position = UDim2.fromOffset(560, 2)

local btnSAM = createActionButton("BUILD_SAM", "LANZADOR SAM", "$750 (Antimisil)", Color3.fromRGB(40, 140, 140), "📡")
btnSAM.Position = UDim2.fromOffset(700, 2)

local btnWarship =
	createActionButton("BUILD_Warship", "NAVÍO GUERRA", "$500 (Patrulla)", Color3.fromRGB(20, 80, 160), "🚢")
btnWarship.Position = UDim2.fromOffset(840, 2)

local btnFarm = createActionButton("BUILD_Farm", "GRANJA", "$300 (+35 Tropas)", Color3.fromRGB(40, 150, 60), "🌾")
btnFarm.Position = UDim2.fromOffset(980, 2)

local btnMine = createActionButton("BUILD_Mine", "MINA", "$450 (++10 Oro)", Color3.fromRGB(180, 130, 20), "⛏️")
btnMine.Position = UDim2.fromOffset(1120, 2)

local btnAirbase =
	createActionButton("BUILD_Airbase", "BASE AÉREA", "$800 (Aéreo)", Color3.fromRGB(80, 90, 160), "✈️")
btnAirbase.Position = UDim2.fromOffset(1260, 2)

local btnSilo = createActionButton("BUILD_Silo", "SILO MISIL", "$1200 Oro", Color3.fromRGB(100, 50, 140), "🚀")
btnSilo.Position = UDim2.fromOffset(1400, 2)

local btnAtom =
	createActionButton("WEAPON_ATOM_BOMB", "BOMBA ATÓMICA", "$600 Oro", Color3.fromRGB(200, 100, 0), "☢️")
btnAtom.Position = UDim2.fromOffset(1540, 2)

local btnHBomb = createActionButton("WEAPON_HYDROGEN_BOMB", "BOMBA H", "$1200 Oro", Color3.fromRGB(220, 40, 0), "💥")
btnHBomb.Position = UDim2.fromOffset(1680, 2)

local btnMIRV = createActionButton("WEAPON_MIRV", "MISIL MIRV", "$2200 Oro", Color3.fromRGB(160, 20, 70), "☄️")
btnMIRV.Position = UDim2.fromOffset(1820, 2)

local btnDemolish = createActionButton("DEMOLISH", "DEMOLER", "60% Reembolso", Color3.fromRGB(110, 80, 70), "🏚️")
btnDemolish.Position = UDim2.fromOffset(1960, 2)

local btnRetreat = createActionButton("RETREAT", "RETIRADA", "Recuperar tropas", Color3.fromRGB(130, 40, 40), "🏳️")
btnRetreat.Position = UDim2.fromOffset(2100, 2)

actionsRow.CanvasSize = UDim2.fromOffset(2260, 0)

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
btnFactory.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Factory")
end)
btnPort.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Port")
end)
btnPost.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Post")
end)
btnSAM.MouseButton1Click:Connect(function()
	setActionMode("BUILD_SAM")
end)
btnWarship.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Warship")
end)
btnFarm.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Farm")
end)
btnMine.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Mine")
end)
btnAirbase.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Airbase")
end)
btnSilo.MouseButton1Click:Connect(function()
	setActionMode("BUILD_Silo")
end)
btnAtom.MouseButton1Click:Connect(function()
	setActionMode("WEAPON_ATOM_BOMB")
end)
btnHBomb.MouseButton1Click:Connect(function()
	setActionMode("WEAPON_HYDROGEN_BOMB")
end)
btnMIRV.MouseButton1Click:Connect(function()
	setActionMode("WEAPON_MIRV")
end)
btnDemolish.MouseButton1Click:Connect(function()
	setActionMode("DEMOLISH")
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
weaponBar.Visible = false
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

local playSound = function() end
do
	local SoundService = game:GetService("SoundService")
	local sfxFolder = Instance.new("Folder")
	sfxFolder.Name = "WorldSFX"
	sfxFolder.Parent = SoundService

	local soundPool = {}
	local SOUND_ASSETS = {
		POP = "rbxasset://sounds/action_get_up.mp3",
		EXPAND = "rbxasset://sounds/action_swim.mp3",
		BUILD = "rbxasset://sounds/button.mp3",
		SPAWN = "rbxasset://sounds/electronicpingshort.wav",
		ATTACK = "rbxasset://sounds/action_jump.mp3",
		ALARM = "rbxasset://sounds/electronicpingshort.wav",
		BOMB = "rbxasset://sounds/impact_explosion_01.mp3",
	}

	function playSound(name, pitch, volume)
		local asset = SOUND_ASSETS[name]
		if not asset then
			return
		end
		local s = table.remove(soundPool)
		if not s then
			s = Instance.new("Sound")
			s.Parent = sfxFolder
		end
		s.SoundId = asset
		s.PlaybackSpeed = pitch or (0.95 + math.random() * 0.1)
		s.Volume = volume or 0.4
		s:Play()
		task.delay(1.2, function()
			table.insert(soundPool, s)
		end)
	end
end

local buildingFrames = {}
local updateBuildings = function() end
do
	local BUILDING_ICONS = {
		City = "🏙️",
		Factory = "🏭",
		Port = "⚓",
		Post = "🛡️",
		Silo = "🚀",
		SAM = "📡",
		Warship = "🚢",
		Farm = "🌾",
		Mine = "⛏️",
	}

	function updateBuildings(bList)
		if not state.initialized or not state.w or not state.h then
			return
		end
		local seen = {}
		local w, h = state.w, state.h
		for _, b in ipairs(bList or {}) do
			local cell = b.cell
			seen[cell] = true
			local f = buildingFrames[cell]
			if not f then
				f = Instance.new("Frame")
				f.Name = "Bld_" .. tostring(cell)
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.Size = UDim2.fromOffset(20, 20)
				f.BackgroundColor3 = Color3.fromRGB(15, 20, 32)
				f.BackgroundTransparency = 0.2
				f.BorderSizePixel = 0
				f.ZIndex = 12
				f.Parent = markersLayer
				roundCorners(f, 6)

				local strk = Instance.new("UIStroke")
				strk.Thickness = 1.5
				strk.Color = Color3.fromRGB(255, 215, 0)
				strk.Parent = f

				local iconLbl = Instance.new("TextLabel")
				iconLbl.Name = "Icon"
				iconLbl.Size = UDim2.fromScale(1, 1)
				iconLbl.BackgroundTransparency = 1
				iconLbl.TextSize = 13
				iconLbl.Font = Enum.Font.GothamBlack
				iconLbl.ZIndex = 13
				iconLbl.Parent = f

				buildingFrames[cell] = f
			end
			local bx, by = cell % w, cell // w
			f.Position = UDim2.fromScale((bx + 0.5) / w, (by + 0.5) / h)
			local icon = BUILDING_ICONS[b.kind] or "🏛️"
			local iconLbl = f:FindFirstChild("Icon")
			if iconLbl then
				iconLbl.Text = icon
			end
			local ownerNation = state.rosterById[b.owner]
			local stroke = f:FindFirstChildOfClass("UIStroke")
			if stroke and ownerNation and ownerNation.color then
				stroke.Color = ownerNation.color
			end
			local isMyOrSilo = (b.owner == state.myId) or (b.kind == "Silo")
			f:SetAttribute("MyOrSilo", isMyOrSilo)
			local rel = state.zoom / math.max(0.01, state.fit or state.zoom)
			local show = (rel >= 1.35) or isMyOrSilo
			f.Visible = show
		end

		for cell, f in pairs(buildingFrames) do
			if not seen[cell] then
				f.Visible = false
			end
		end
	end
end

local function showCombatFloat(cell, text, color)
	if not state.w or not state.h or cell < 0 or cell >= state.w * state.h then
		return
	end
	local cx, cy = cell % state.w, cell // state.w
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale((cx + 0.5) / state.w, (cy + 0.5) / state.h)
	lbl.Size = UDim2.fromOffset(80, 20)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.Text = text
	lbl.TextColor3 = color or Color3.fromRGB(255, 235, 80)
	lbl.TextSize = 13
	lbl.ZIndex = 35
	lbl.Parent = mapCanvas

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(10, 15, 25)
	stroke.Thickness = 1.5
	stroke.Parent = lbl

	local tw = TweenService:Create(
		lbl,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale((cx + 0.5) / state.w, (cy - 3.2) / state.h), TextTransparency = 1 }
	)
	tw:Play()
	tw.Completed:Connect(function()
		lbl:Destroy()
	end)
end

local function playWeaponFx(fx)
	if not state.initialized or type(fx) ~= "table" or not fx.cell or fx.cell >= state.w * state.h then
		return
	end
	if fx.kind == "CAPITAL_SPAWN" then
		-- Efecto de fundación de capital estilo FrontWars: 4 ondas concéntricas de pulso que se expanden por el mundo
		local d = (fx.r or 8) * 2 + 1
		local col = fx.color or Color3.fromRGB(0, 220, 255)
		for k = 0, 3 do
			task.delay(k * 0.15, function()
				fxCircle(fx.cell, 1, d * (0.8 + k * 0.7), col, 0.25, 0.9 + k * 0.25, 18)
			end)
		end
		fxCircle(fx.cell, 1, d * 0.6, Color3.new(1, 1, 1), 0.05, 0.6, 20)
		playSound("SPAWN", 1.0, 0.6)
		showCombatFloat(fx.cell, "👑 CAPITAL", Color3.fromRGB(255, 225, 60))
		return
	end
	if fx.kind == "CAPITAL_FALL" then
		local d = (fx.r or 12) * 2 + 1
		for k = 0, 3 do
			task.delay(k * 0.12, function()
				fxCircle(fx.cell, 1, d * (0.6 + k * 0.5), Color3.fromRGB(255, 215, 0), 0.2, 0.8 + k * 0.2, 22)
			end)
		end
		fxCircle(fx.cell, 1, d * 0.5, Color3.fromRGB(255, 255, 255), 0.05, 0.5, 24)
		playSound("BOMB", 1.2, 0.8)
		showToast("👑 ¡CAPITAL ENEMIGA CONQUISTADA!", Color3.fromRGB(255, 215, 0))
		showCombatFloat(fx.cell, "💥 ¡ANEXADO! 👑", Color3.fromRGB(255, 215, 0))
		return
	end
	if fx.kind == "BUILDING_PLACED" then
		fxCircle(fx.cell, 1, 8, Color3.fromRGB(255, 230, 80), 0.25, 0.6, 15)
		playSound("BUILD", 1.1, 0.4)
		return
	end
	if fx.kind == "NAVAL_LANDING" then
		local w, h = state.w, state.h
		local fromCell = fx.from or fx.cell
		local toCell = fx.cell
		local fx0, fy0 = fromCell % w, fromCell // w
		local fx1, fy1 = toCell % w, toCell // w
		for k = 1, 3 do
			task.delay((k - 1) * 0.16, function()
				local boat = Instance.new("TextLabel")
				boat.Text = if k == 2 then "🚢" else "⛵"
				boat.TextSize = 16
				boat.Size = UDim2.fromOffset(20, 20)
				boat.AnchorPoint = Vector2.new(0.5, 0.5)
				boat.BackgroundTransparency = 1
				boat.Position = UDim2.fromScale((fx0 + 0.5) / w, (fy0 + 0.5) / h)
				boat.ZIndex = 14
				boat.Parent = mapCanvas

				local dur = 1.0 + math.random() * 0.3
				local tw = TweenService:Create(
					boat,
					TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = UDim2.fromScale((fx1 + 0.5) / w, (fy1 + 0.5) / h) }
				)
				tw:Play()
				tw.Completed:Connect(function()
					boat:Destroy()
					fxCircle(toCell, 1, 8, Color3.fromRGB(80, 220, 255), 0.3, 0.6, 15)
				end)
			end)
		end
		playSound("EXPAND", 1.2, 0.5)
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
	playSound("BOMB", 0.9, 0.7)
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
		local frac = (k % 1000) // 100
		if frac > 0 then
			return string.format("%.1fK", k / 1000)
		else
			return string.format("%dK", math.floor(k / 1000))
		end
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
local selBots = 35
local selDiff = "NORMAL"
local selMode = "FREE"

local COLOR_CARD = Color3.fromRGB(26, 36, 56)
local COLOR_CARD_SEL = Color3.fromRGB(24, 70, 96)
local COLOR_CHIP = Color3.fromRGB(30, 42, 64)
local COLOR_ACCENT = Color3.fromRGB(0, 200, 255)

local OpenFrontUIModule = script.Parent:WaitForChild("OpenFrontUI")
local OpenFrontUI = require(OpenFrontUIModule)

local openfrontApi = OpenFrontUI.create(root, {
	onLaunchGame = function(planet, bots, diff, mode)
		WorldCommand:FireServer({
			a = "PLAY",
			planet = planet,
			bots = bots,
			difficulty = diff,
			mode = mode,
		})
		showToast("⚔️ Iniciando partida OpenFront.io...", Color3.fromRGB(0, 229, 255))
	end,
	onSettings = function()
		if tacticalModal then
			tacticalModal.Visible = not tacticalModal.Visible
		end
	end,
	onHelp = function()
		showToast("OpenFront.io: Conquista celdas, construye ciudades y defiende con puestos", Color3.fromRGB(255, 215, 0))
	end,
	onNotify = function(msg)
		showToast(msg, Color3.fromRGB(0, 200, 255))
	end,
})

local lobbyScreen = root:WaitForChild("OpenFrontHubScreen", 5) or { Visible = false }

local function showLobby(visible)
	openfrontApi.show(visible)
end

local function updateLobbyStatus()
	-- No-op
end

btnLobby.MouseButton1Click:Connect(function()
	openfrontApi.toggle()
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
local BLOCK = 8

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
		-- Mapa de relieve natural de la Tierra (sin fronteras grises superpuestas sobre el mapa mundi)
		tileLayer = makeTileLayer("TileLayer", EARTH_TILES, 1)
	end
	if tileLayer then
		tileLayer.Visible = visible
	end
end

local function initBlocks(w, h)
	-- Otra carga ya está creando los bloques: se espera a que termine (luego bastará con reutilizarlos)
	while state.blockBuilding do
		task.wait()
	end
	mapImage.Visible = false
	state.useTiles = (state.planet == "EARTH")
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

-- Renderizado ultra-rápido estilo FrontWars: asignación directa sin bucles pesados de Heartbeat
local flashing = {}
local flashCount = 0

-- ----------------------------------------------------------------------------
-- CONTORNO DE COLOR DE CADA TERRITORIO (mapa de bloques)
-- Donde un bloque pertenece a una nación y su vecino a otra (o a nadie), el bloque dibuja una línea de una celda de
-- grosor con el color de su dueño, por dentro de su lado. El contorno crece y se redibuja solo al conquistar.
-- Tu contorno es dorado y late. Con mucho zoom se usa el borde celda por celda del nivel de detalle.
-- ----------------------------------------------------------------------------
-- ============================================================================
-- RENDERIZADO DE FRONTERAS ILUMINADAS (2 PASADAS ESTILO FRONTWARS)
-- Pasada 1: Halo exterior de resplandor neón difuso (Bloom / Glow)
-- Pasada 2: Núcleo central brillante de alta saturación (Crisp Laser Core)
-- ============================================================================
local edgeLayer = Instance.new("Frame")
edgeLayer.Name = "IlluminatedBorderLayer"
edgeLayer.Size = UDim2.fromScale(1, 1)
edgeLayer.BackgroundTransparency = 1
edgeLayer.BorderSizePixel = 0
edgeLayer.Visible = true
edgeLayer.ZIndex = 6
edgeLayer.Parent = mapCanvas

local MAX_VISIBLE_EDGES = 600
local edgeGlowFrames = {} -- Pasada 1 (Bloom / Resplandor)
local edgeCoreFrames = {} -- Pasada 2 (Núcleo nítido de alta definición)
local myGlowEdges = {}
local myCoreEdges = {}
local GLOW_THICK_PX = 4.5
local CORE_THICK_PX = 1.6

for i = 1, MAX_VISIBLE_EDGES do
	local fg = Instance.new("Frame")
	fg.Name = "Glow"
	fg.BorderSizePixel = 0
	fg.ZIndex = 6
	fg.Visible = false
	fg.BackgroundTransparency = 0.55
	fg.Parent = edgeLayer
	edgeGlowFrames[i] = fg

	local fc = Instance.new("Frame")
	fc.Name = "Core"
	fc.BorderSizePixel = 0
	fc.ZIndex = 7
	fc.Visible = false
	fc.BackgroundTransparency = 0.0
	fc.Parent = edgeLayer
	edgeCoreFrames[i] = fc
end

local function sameTeam(a, b)
	if not state.teamMode or a == 0 or b == 0 then
		return false
	end
	local ra, rb = state.rosterById[a], state.rosterById[b]
	return ra ~= nil and rb ~= nil and ra.continent ~= nil and ra.continent == rb.continent
end
state.sameTeam = sameTeam

local function vividColor(c, id)
	local h, s = c:ToHSV()
	local k = ((id or 0) * 37) % 100 / 100
	local sat = math.clamp(s * 1.5, 0.65, 0.95)
	local val = 0.95 + k * 0.05
	local hue = (h + (k - 0.5) * 0.03) % 1
	return Color3.fromHSV(hue, math.clamp(sat, 0.6, 1.0), math.clamp(val, 0.9, 1))
end
state.vividColor = vividColor

local function edgeColor(ownerId)
	if ownerId == state.myId then
		return Color3.fromRGB(255, 235, 50)
	end
	local n = state.rosterById[ownerId]
	if n and n.color then
		return vividColor(n.color, ownerId)
	end
	return Color3.new(1, 1, 1)
end

-- Actualiza los bordes iluminados visibles dentro del viewport (2 pasadas)
local function refreshVisibleEdges()
	local owner = state.owner
	local w, h = state.w, state.h
	if not owner or not w or w == 0 or not state.initialized then
		edgeLayer.Visible = false
		return
	end

	edgeLayer.Visible = true

	local vs = mapContainer.AbsoluteSize
	local cellW = BASE_WIDTH * state.zoom / w
	local cellH = BASE_HEIGHT * state.zoom / h
	if cellW <= 0 or cellH <= 0 then
		return
	end

	local rel = state.zoom / (state.fit or state.zoom)
	local isFar = rel < 1.15
	local step = if isFar then 2 else 1 -- Muestreo adaptativo para mantener 60 FPS fijos a cualquier zoom

	local left = vs.X / 2 + state.pan.X - BASE_WIDTH * state.zoom / 2
	local top = vs.Y / 2 + state.pan.Y - BASE_HEIGHT * state.zoom / 2
	local x0 = math.clamp(math.floor(-left / cellW) - 1, 0, w - 1)
	local x1 = math.clamp(math.ceil((vs.X - left) / cellW) + 1, 0, w - 1)
	local y0 = math.clamp(math.floor(-top / cellH) - 1, 0, h - 1)
	local y1 = math.clamp(math.ceil((vs.Y - top) / cellH) + 1, 0, h - 1)

	table.clear(myGlowEdges)
	table.clear(myCoreEdges)
	local edgeCount = 0

	for y = y0, y1, step do
		local row = y * w
		for x = x0, x1, step do
			local cell = row + x
			local o = buffer.readu8(owner, cell)
			if o ~= 0 then
				local r = buffer.readu8(owner, row + (if x >= w - 1 then 0 else x + 1))
				local d = if y < h - 1 then buffer.readu8(owner, (y + 1) * w + x) else 0
				local col = edgeColor(o)
				local coreCol = if o == state.myId then Color3.fromRGB(255, 255, 230) else col:Lerp(Color3.new(1, 1, 1), 0.35)
				local isMe = (o == state.myId)

				-- Borde derecho
				if r ~= o and not sameTeam(r, o) then
					edgeCount += 1
					if edgeCount <= MAX_VISIBLE_EDGES then
						local fg = edgeGlowFrames[edgeCount]
						local fc = edgeCoreFrames[edgeCount]
						local pos = UDim2.fromScale((x + 1) / w, y / h)
						local gSize = UDim2.new(0, if isMe then 5.5 else GLOW_THICK_PX, step / h, 0)
						local cSize = UDim2.new(0, CORE_THICK_PX, step / h, 0)

						fg.AnchorPoint = Vector2.new(0.5, 0)
						fg.Position = pos
						fg.Size = gSize
						fg.BackgroundColor3 = col
						fg.BackgroundTransparency = if isMe then 0.38 else 0.55
						fg.Visible = true

						fc.AnchorPoint = Vector2.new(0.5, 0)
						fc.Position = pos
						fc.Size = cSize
						fc.BackgroundColor3 = coreCol
						fc.BackgroundTransparency = 0.0
						fc.Visible = true

						if isMe then
							myGlowEdges[fg] = true
							myCoreEdges[fc] = true
						end
					end
				end

				-- Borde inferior
				if d ~= o and not sameTeam(d, o) then
					edgeCount += 1
					if edgeCount <= MAX_VISIBLE_EDGES then
						local fg = edgeGlowFrames[edgeCount]
						local fc = edgeCoreFrames[edgeCount]
						local pos = UDim2.fromScale(x / w, (y + 1) / h)
						local gSize = UDim2.new(step / w, 0, 0, if isMe then 5.5 else GLOW_THICK_PX)
						local cSize = UDim2.new(step / w, 0, 0, CORE_THICK_PX)

						fg.AnchorPoint = Vector2.new(0, 0.5)
						fg.Position = pos
						fg.Size = gSize
						fg.BackgroundColor3 = col
						fg.BackgroundTransparency = if isMe then 0.38 else 0.55
						fg.Visible = true

						fc.AnchorPoint = Vector2.new(0, 0.5)
						fc.Position = pos
						fc.Size = cSize
						fc.BackgroundColor3 = coreCol
						fc.BackgroundTransparency = 0.0
						fc.Visible = true

						if isMe then
							myGlowEdges[fg] = true
							myCoreEdges[fc] = true
						end
					end
				end

				if edgeCount >= MAX_VISIBLE_EDGES then
					break
				end
			end
		end
		if edgeCount >= MAX_VISIBLE_EDGES then
			break
		end
	end

	-- Ocultar frames sobrantes del pool
	for i = edgeCount + 1, MAX_VISIBLE_EDGES do
		edgeGlowFrames[i].Visible = false
		edgeCoreFrames[i].Visible = false
	end
end

state.refreshEdges = refreshVisibleEdges
state.rebuildEdges = refreshVisibleEdges

local function updateCellEdges(cell)
end

-- El contorno iluminado del jugador late con resplandor neón dorado
local edgePulseAcc = 0
RunService.Heartbeat:Connect(function(dt)
	edgePulseAcc += dt
	if edgePulseAcc < 0.1 then
		return
	end
	edgePulseAcc = 0
	if not edgeLayer.Visible then
		return
	end
	local k = (math.sin(os.clock() * 5) + 1) / 2
	local glowColor = Color3.fromRGB(255, 215, 30):Lerp(Color3.fromRGB(255, 245, 100), k)
	local coreColor = Color3.fromRGB(255, 255, 200):Lerp(Color3.fromRGB(255, 255, 255), k)
	local glowAlpha = 0.30 + k * 0.20
	for fg in pairs(myGlowEdges) do
		fg.BackgroundColor3 = glowColor
		fg.BackgroundTransparency = glowAlpha
	end
	for fc in pairs(myCoreEdges) do
		fc.BackgroundColor3 = coreColor
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

	local n = if bestId ~= 0 then state.rosterById[bestId] else nil
	local finalColor
	local transparency = 0

	if state.useTiles then
		if n then
			local isMe = bestId == state.myId
			finalColor = if isMe then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.25) else n.color
			-- Territorio conquistado estilo FrontWars: color vivo pero translúcido para ver la geografía
			transparency = if isMe then 0.25 elseif n.bot == false then 0.30 else 0.38
		else
			-- Continentes y tierra natural neutral: 100% transparente para que el relieve se vea limpio sin veladuras ni sombreados
			finalColor = OCEAN_COLOR
			transparency = 1
		end
	else
		if n then
			finalColor = if bestId == state.myId then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.25) else n.color
		else
			finalColor = if b.isLand then UNCLAIMED_LAND else OCEAN_COLOR
		end
		transparency = 0
	end

	b.frame.BackgroundColor3 = finalColor
	b.frame.BackgroundTransparency = transparency
	b.owner = if n then bestId else 0
end

local function markBlockDirty(idx)
	local w = state.w
	local bx = (idx % w) // BLOCK
	local by = (idx // w) // BLOCK
	local bi = by * state.blockW + bx + 1
	state.dirtyBlocks[bi] = true
	local dr = state.dirtyRect
	if dr then
		if bx < dr.x0 then dr.x0 = bx end
		if bx > dr.x1 then dr.x1 = bx end
		if by < dr.y0 then dr.y0 = by end
		if by > dr.y1 then dr.y1 = by end
	end
	state.hasDirty = true
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
		if not state.hasDirty and not next(state.dirtyBlocks) then
			return
		end
		for bi in pairs(state.dirtyBlocks) do
			recolorBlock(bi)
			state.dirtyBlocks[bi] = nil
		end
		if state.dirtyRect then
			state.dirtyRect.x0, state.dirtyRect.y0 = math.huge, math.huge
			state.dirtyRect.x1, state.dirtyRect.y1 = -1, -1
		end
		state.hasDirty = false
		state.detailDirty = true
		if state.refreshEdges then
			state.refreshEdges()
		end
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
		if not state.blocks or not state.owner then
			return
		end
		state.animReady = false
		local w, land, owner = state.w, state.land, state.owner
		local area = BLOCK * BLOCK
		for bi = 1, state.blockW * state.blockH do
			local bx = (bi - 1) % state.blockW
			local by = (bi - 1) // state.blockW
			local b = state.blocks[bi]
			if b then
				local landCount = 0
				local counts = {}
				local bestId, bestCount = 0, 0
				for y = by * BLOCK, by * BLOCK + BLOCK - 1 do
					local row = y * w
					for x = bx * BLOCK, bx * BLOCK + BLOCK - 1 do
						local cell = row + x
						if land and buffer.readu8(land, cell) == 1 then
							landCount += 1
						end
						local o = buffer.readu8(owner, cell)
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
				b.isLand = (landCount >= (area / 3))
				local n = if bestId ~= 0 then state.rosterById[bestId] else nil
				local col = OCEAN_COLOR
				local transp = 0

				if state.useTiles then
					if n then
						local isMe = bestId == state.myId
						col = if isMe then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.25) else n.color
						transp = if isMe then 0.20 elseif n.bot == false then 0.26 else 0.34
					else
						col = OCEAN_COLOR
						transp = 1
					end
				else
					if n then
						col = if bestId == state.myId then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.25) else n.color
					else
						col = if b.isLand then UNCLAIMED_LAND else OCEAN_COLOR
					end
					transp = 0
				end

				b.frame.BackgroundColor3 = col
				b.frame.BackgroundTransparency = transp
				b.owner = if n then bestId else 0
			end
		end
		state.animReady = true
		if state.refreshEdges then
			state.refreshEdges()
		end
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
	local w, h = state.w or 960, state.h or 400
	local vs = mapContainer.AbsoluteSize
	local cellW = BASE_WIDTH * state.zoom / w
	local cellH = BASE_HEIGHT * state.zoom / h
	local left = vs.X / 2 + state.pan.X - BASE_WIDTH * state.zoom / 2
	local top = vs.Y / 2 + state.pan.Y - BASE_HEIGHT * state.zoom / 2
	local x0 = math.clamp(math.floor(-left / cellW) - 8, 0, w)
	local x1 = math.clamp(math.ceil((vs.X - left) / cellW) + 8, 0, w)
	local y0 = math.clamp(math.floor(-top / cellH) - 8, 0, h)
	local y1 = math.clamp(math.ceil((vs.Y - top) / cellH) + 8, 0, h)

	for _, m in ipairs(markerLabels) do
		local inView = true
		if m.capX and m.capY then
			inView = (m.capX >= x0 and m.capX <= x1 and m.capY >= y0 and m.capY <= y1)
		end
		if not inView then
			if m.marker then m.marker.Visible = false end
		else
			if m.marker then m.marker.Visible = true end
			local ds = math.clamp(math.floor((if m.isMe then 24 else 18) * (0.85 + 0.2 * rel)), 14, 30)
			m.dot.Size = UDim2.fromOffset(ds, ds)
			local show = m.always or rel >= 1.3
			if m.badge then
				m.badge.Visible = show
				m.badge.Position = UDim2.fromOffset(0, -ds / 2 - 4)
			end
			if m.troops then
				m.troops.Visible = show and m.troops.Text ~= ""
				m.troops.Position = UDim2.fromOffset(0, ds / 2 + 2)
			end
		end
	end

	if buildingFrames then
		for cell, f in pairs(buildingFrames) do
			local cx, cy = cell % w, cell // w
			local inView = (cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1)
			local isMyOrSilo = f:GetAttribute("MyOrSilo") == true
			f.Visible = inView and ((rel >= 1.35) or isMyOrSilo)
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

			local isHuman = n.bot == false

			-- Disco Base / Fortaleza circular estilo FrontWars
			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(0.5, 0.5)
			dot.Size = isMe and UDim2.fromOffset(22, 22) or UDim2.fromOffset(16, 16)
			dot.BackgroundColor3 = isMe and Color3.fromRGB(255, 225, 50) or n.color
			dot.BorderSizePixel = 0
			dot.ZIndex = 12
			dot.Parent = marker

			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot

			local dotStroke = Instance.new("UIStroke")
			dotStroke.Thickness = 2.5
			dotStroke.Color = Color3.fromRGB(15, 22, 34)
			dotStroke.Parent = dot

			local centerIcon = Instance.new("TextLabel")
			centerIcon.Name = "CenterIcon"
			centerIcon.Size = UDim2.fromScale(1, 1)
			centerIcon.BackgroundTransparency = 1
			centerIcon.Font = Enum.Font.GothamBlack
			centerIcon.Text = if isMe then "👑" elseif isHuman then "👤" else "⭐"
			centerIcon.TextSize = isMe and 12 or 9
			centerIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
			centerIcon.ZIndex = 13
			centerIcon.Parent = dot

			-- Badge flotante superior estilo FrontWars: [ 🇲🇽 Mexico 766 ]
			local badge = Instance.new("Frame")
			badge.Name = "FloatingBadge"
			badge.AnchorPoint = Vector2.new(0.5, 1)
			badge.Position = UDim2.fromOffset(0, isMe and -16 or -12)
			badge.Size = UDim2.fromOffset(110, 20)
			badge.BackgroundColor3 = Color3.fromRGB(12, 18, 28)
			badge.BackgroundTransparency = 0.15
			badge.BorderSizePixel = 0
			badge.ZIndex = 14
			badge.Parent = marker

			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0, 4)
			badgeCorner.Parent = badge

			local badgeStroke = Instance.new("UIStroke")
			badgeStroke.Thickness = 1
			badgeStroke.Color = if isMe then Color3.fromRGB(255, 215, 0) else Color3.fromRGB(45, 60, 90)
			badgeStroke.Parent = badge

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "Name"
			nameLbl.Size = UDim2.new(1, -6, 1, 0)
			nameLbl.Position = UDim2.fromOffset(3, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.Text = (if isMe then "👑 " elseif isHuman then "👤 " else "") .. n.name
			nameLbl.TextColor3 = if isMe then Color3.fromRGB(255, 230, 60) else Color3.fromRGB(240, 245, 255)
			nameLbl.TextSize = 10
			nameLbl.TextXAlignment = Enum.TextXAlignment.Center
			nameLbl.ZIndex = 15
			nameLbl.Parent = badge

			local troopsLbl = Instance.new("TextLabel")
			troopsLbl.Name = "Troops"
			troopsLbl.Size = UDim2.fromOffset(80, 14)
			troopsLbl.Position = UDim2.fromOffset(0, 22)
			troopsLbl.AnchorPoint = Vector2.new(0.5, 0)
			troopsLbl.BackgroundTransparency = 1
			troopsLbl.Font = Enum.Font.GothamBlack
			troopsLbl.Text = ""
			troopsLbl.TextColor3 = Color3.fromRGB(0, 235, 140)
			troopsLbl.TextStrokeTransparency = 0.3
			troopsLbl.TextStrokeColor3 = Color3.fromRGB(10, 15, 25)
			troopsLbl.TextSize = 9
			troopsLbl.ZIndex = 14
			troopsLbl.Parent = marker

			table.insert(markerPool, marker)
			table.insert(markerLabels, {
				id = n.id,
				troops = troopsLbl,
				label = nameLbl,
				badge = badge,
				dot = dot,
				marker = marker,
				capX = capX,
				capY = capY,
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
		playWeaponFx({ kind = "CAPITAL_SPAWN", cell = cell, color = Color3.fromRGB(255, 220, 60), r = 9 })
		if state.mode == "COUNTRIES" then
			showToast("🌍 Reclamando capital de la nación...", Color3.fromRGB(0, 220, 255))
		else
			showToast("👑 ¡Fundando Capital! Expandiendo territorio inicial...", Color3.fromRGB(255, 220, 60))
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
		playSound("ATTACK", 1.1, 0.35)
		-- Feedback visual inmediato estilo FrontWars: onda de choque concéntrica y pulso de conquista
		local o = buffer.readu8(state.owner, cell)
		local isNeutral = (o == 0)
		local cx = cell % state.w
		local cy = math.floor(cell / state.w)
		local ripple = Instance.new("Frame")
		ripple.AnchorPoint = Vector2.new(0.5, 0.5)
		ripple.Position = UDim2.fromScale((cx + 0.5) / state.w, (cy + 0.5) / state.h)
		ripple.Size = UDim2.fromScale(6 / state.w, 6 / state.h)
		ripple.BackgroundColor3 = if isNeutral then Color3.fromRGB(0, 230, 160) else Color3.fromRGB(255, 40, 40)
		ripple.BackgroundTransparency = 0.15
		ripple.BorderSizePixel = 0
		ripple.ZIndex = 25
		ripple.Parent = mapCanvas

		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = ripple

		local strk = Instance.new("UIStroke")
		strk.Color = if isNeutral then Color3.fromRGB(255, 235, 90) else Color3.fromRGB(255, 230, 40)
		strk.Thickness = 2
		strk.Transparency = 0.2
		strk.Parent = ripple

		local tw = TweenService:Create(ripple, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(36 / state.w, 36 / state.h),
			BackgroundTransparency = 1,
		})
		tw:Play()
		tw.Completed:Connect(function()
			ripple:Destroy()
		end)

		if isNeutral then
			showCombatFloat(cell, "+1 🚩", Color3.fromRGB(0, 240, 160))
		else
			local sent = math.max(100, math.floor((state.troops or 1500) * (state.attackRatio or 0.2)))
			showCombatFloat(cell, "-" .. troopText(sent) .. " ⚔️", Color3.fromRGB(255, 75, 75))
		end

		-- Desembarco naval si el ataque cruza océano hacia una isla o costa lejana
		if state.me and state.me.capital and state.me.capital >= 0 then
			local cap = state.me.capital
			local dx = math.abs(cell % state.w - cap % state.w)
			dx = math.min(dx, state.w - dx)
			local dy = math.abs(cell // state.w - cap // state.w)
			if dx * dx + dy * dy > 1600 then
				playWeaponFx({ kind = "NAVAL_LANDING", from = cap, cell = cell })
			end
		end

		-- Marcar objetivo para el flujo de tropas de partículas (neutral o enemigo)
		state.recentTargetCell = cell
		state.recentTargetTime = os.clock()
	elseif state.actionMode:sub(1, 6) == "BUILD_" then
		local kind = state.actionMode:sub(7)
		WorldCommand:FireServer({ a = "BUILD", kind = kind, cell = cell })
		playSound("BUILD", 1.0, 0.4)
	elseif state.actionMode == "DEMOLISH" then
		WorldCommand:FireServer({ a = "DEMOLISH", cell = cell })
	elseif state.actionMode:sub(1, 7) == "WEAPON_" then
		-- El arma sigue apuntada tras disparar (cada una tiene su enfriamiento y el servidor valida oro y recarga)
		WorldCommand:FireServer({ a = "WEAPON", kind = state.actionMode:sub(8), cell = cell })
	elseif state.actionMode == "NUKE" then
		WorldCommand:FireServer({ a = "NUKE", cell = cell })
		setActionMode("ATTACK")
	end
end

local radialMenu = Instance.new("Frame")
radialMenu.Name = "RadialMenu"
radialMenu.Size = UDim2.fromOffset(180, 180)
radialMenu.AnchorPoint = Vector2.new(0.5, 0.5)
radialMenu.BackgroundColor3 = Color3.fromRGB(18, 26, 42)
radialMenu.BackgroundTransparency = 0.1
radialMenu.Visible = false
radialMenu.ZIndex = 60
radialMenu.Parent = root
roundCorners(radialMenu, 90)

local radialStroke = Instance.new("UIStroke")
radialStroke.Color = Color3.fromRGB(0, 200, 240)
radialStroke.Thickness = 2
radialStroke.Parent = radialMenu

local radialTitle = Instance.new("TextLabel")
radialTitle.Size = UDim2.new(1, -20, 0, 24)
radialTitle.Position = UDim2.fromOffset(10, 8)
radialTitle.BackgroundTransparency = 1
radialTitle.Font = Enum.Font.GothamBlack
radialTitle.Text = "ACCIÓN RÁPIDA"
radialTitle.TextColor3 = Color3.fromRGB(255, 230, 40)
radialTitle.TextSize = 10
radialTitle.ZIndex = 61
radialTitle.Parent = radialMenu

local radialTargetCell = -1

local function createRadialBtn(text, icon, posOffset, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(72, 34)
	b.Position = posOffset
	b.BackgroundColor3 = Color3.fromRGB(30, 44, 70)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.Text = icon .. "\n" .. text
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextSize = 9
	b.ZIndex = 62
	b.Parent = radialMenu
	roundCorners(b, 6)
	b.MouseButton1Click:Connect(function()
		radialMenu.Visible = false
		if radialTargetCell >= 0 then
			onClick(radialTargetCell)
		end
	end)
	return b
end

createRadialBtn("ATACAR", "⚔️", UDim2.fromOffset(54, 38), function(c)
	WorldCommand:FireServer({ a = "ATTACK", cell = c, ratio = state.attackRatio })
end)

createRadialBtn("ALIANZA", "🤝", UDim2.fromOffset(10, 80), function(c)
	local targetId = buffer.readu8(state.owner, c)
	if targetId > 0 and targetId ~= state.myId then
		WorldCommand:FireServer({ a = "ALLY_REQUEST", target = targetId })
		state.showToast("🤝 Petición de alianza enviada", Color3.fromRGB(0, 220, 255))
	end
end)

createRadialBtn("CONSTRUIR", "🏢", UDim2.fromOffset(98, 80), function(c)
	setActionMode("BUILD_City")
	WorldCommand:FireServer({ a = "BUILD", kind = "City", cell = c })
end)

createRadialBtn("CANCELAR", "❌", UDim2.fromOffset(54, 126), function()
	radialMenu.Visible = false
end)

local function openRadialMenu(screenPos, cell)
	radialTargetCell = cell
	radialMenu.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	radialMenu.Visible = true
end

-- ============================================================================
-- PAN & ZOOM (Navegación fluida por el mapa)
-- ============================================================================

local function updateMapTransform()
	local viewportSize = mapContainer.AbsoluteSize
	local scaledW = BASE_WIDTH * state.zoom
	local scaledH = BASE_HEIGHT * state.zoom

	mapCanvas.Size = UDim2.fromOffset(scaledW, scaledH)
	mapCanvas.Position = UDim2.fromOffset(viewportSize.X / 2 + state.pan.X, viewportSize.Y / 2 + state.pan.Y)
	state.fit = math.min(viewportSize.X / BASE_WIDTH, viewportSize.Y / BASE_HEIGHT) -- zoom que muestra el mundo entero
	state.detailDirty = true
	applyLabelZoom()
	if state.updateRadar then
		state.updateRadar()
	end
	if state.refreshEdges then
		state.refreshEdges()
	end
end

state.updateMapTransform = updateMapTransform

-- Radar / Minimapa táctico estilo FrontWars (esquina inferior derecha)
do
	local radarCard = Instance.new("Frame")
	radarCard.Name = "RadarFrame"
	radarCard.AnchorPoint = Vector2.new(1, 1)
	radarCard.Position = UDim2.new(1, -18, 1, -125)
	radarCard.Size = UDim2.fromOffset(190, 80)
	radarCard.BackgroundColor3 = Color3.fromRGB(12, 18, 30)
	radarCard.BackgroundTransparency = 0.25
	radarCard.BorderSizePixel = 0
	radarCard.ZIndex = 30
	radarCard.Parent = root
	roundCorners(radarCard, 8)
	radarScale = Instance.new("UIScale")
	radarScale.Parent = radarCard

	local radarStroke = Instance.new("UIStroke")
	radarStroke.Thickness = 1.5
	radarStroke.Color = Color3.fromRGB(45, 75, 115)
	radarStroke.Parent = radarCard

	local radarTitle = Instance.new("TextLabel")
	radarTitle.Size = UDim2.fromOffset(180, 16)
	radarTitle.Position = UDim2.fromOffset(8, 4)
	radarTitle.BackgroundTransparency = 1
	radarTitle.Font = Enum.Font.GothamBold
	radarTitle.Text = "🗺️ RADAR MUNDIAL"
	radarTitle.TextColor3 = Color3.fromRGB(120, 190, 255)
	radarTitle.TextSize = 10
	radarTitle.TextXAlignment = Enum.TextXAlignment.Left
	radarTitle.ZIndex = 31
	radarTitle.Parent = radarCard

	local radarView = Instance.new("Frame")
	radarView.Name = "RadarCanvas"
	radarView.Position = UDim2.fromOffset(6, 22)
	radarView.Size = UDim2.fromOffset(178, 52)
	radarView.BackgroundColor3 = Color3.fromRGB(8, 14, 24)
	radarView.BorderSizePixel = 0
	radarView.ZIndex = 31
	radarView.ClipsDescendants = true
	radarView.Parent = radarCard
	roundCorners(radarView, 4)

	local viewportBox = Instance.new("Frame")
	viewportBox.Name = "ViewportIndicator"
	viewportBox.BorderSizePixel = 0
	viewportBox.BackgroundColor3 = Color3.fromRGB(0, 230, 160)
	viewportBox.BackgroundTransparency = 0.8
	viewportBox.ZIndex = 33
	viewportBox.Parent = radarView
	roundCorners(viewportBox, 2)

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Thickness = 1.5
	boxStroke.Color = Color3.fromRGB(80, 255, 180)
	boxStroke.Parent = viewportBox

	local capitalDot = Instance.new("Frame")
	capitalDot.Name = "MyCapitalDot"
	capitalDot.Size = UDim2.fromOffset(6, 6)
	capitalDot.AnchorPoint = Vector2.new(0.5, 0.5)
	capitalDot.BackgroundColor3 = Color3.fromRGB(255, 220, 0)
	capitalDot.BorderSizePixel = 0
	capitalDot.ZIndex = 34
	capitalDot.Visible = false
	capitalDot.Parent = radarView
	roundCorners(capitalDot, 3)

	local function updateRadar()
		if not state.w or not state.h then
			return
		end
		local vs = mapContainer.AbsoluteSize
		local cw = BASE_WIDTH * state.zoom
		local ch = BASE_HEIGHT * state.zoom

		local normW = math.clamp(vs.X / math.max(1, cw), 0.05, 1)
		local normH = math.clamp(vs.Y / math.max(1, ch), 0.05, 1)

		local normX = 0.5 - (state.pan.X / math.max(1, cw)) - normW * 0.5
		local normY = 0.5 - (state.pan.Y / math.max(1, ch)) - normH * 0.5

		viewportBox.Position = UDim2.fromScale(math.clamp(normX, 0, 1 - normW), math.clamp(normY, 0, 1 - normH))
		viewportBox.Size = UDim2.fromScale(normW, normH)

		if state.me and state.me.capital and state.me.capital >= 0 then
			local cx = (state.me.capital % state.w + 0.5) / state.w
			local cy = (state.me.capital // state.w + 0.5) / state.h
			capitalDot.Position = UDim2.fromScale(cx, cy)
			capitalDot.Visible = true
		else
			capitalDot.Visible = false
		end
	end

	radarView.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local absPos = radarView.AbsolutePosition
			local absSize = radarView.AbsoluteSize
			local relX = math.clamp((input.Position.X - absPos.X) / absSize.X, 0, 1)
			local relY = math.clamp((input.Position.Y - absPos.Y) / absSize.Y, 0, 1)
			if state.w and state.h then
				local cell = math.floor(relY * state.h) * state.w + math.floor(relX * state.w)
				focusCell(cell)
				playSound("ATTACK", 1.2, 0.3)
			end
		end
	end)

	state.updateRadar = updateRadar
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

-- Zoom suave: la rueda y las teclas fijan un objetivo y cada fotograma se acerca a él (ver más abajo)
local MAX_ZOOM = 8.0
local zoomTarget = state.zoom
local zoomAnchor = Vector2.zero
local requestZoom, fitToScreen, focusCell, panTarget -- se definen tras los controles

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
	panTarget = nil
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
	elseif pressesPan and not drag.moved then
		-- FrontWars.io: Clic derecho sobre territorio abre el Menú Radial rápido
		local cell = screenToCell(Vector2.new(input.Position.X, input.Position.Y))
		if cell >= 0 then
			openRadialMenu(Vector2.new(input.Position.X, input.Position.Y), cell)
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
			panTarget = nil
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
	elseif UserInputService:IsKeyDown(Enum.KeyCode.F) then
		fitToScreen()
	end
end)

-- Sistema de Audio y Silenciado (Atajo M)
local isMusicMuted = false
local function toggleMusicMute()
	isMusicMuted = not isMusicMuted
	state.musicMuted = isMusicMuted
	local SoundService = game:GetService("SoundService")
	for _, inst in ipairs(SoundService:GetDescendants()) do
		if inst:IsA("Sound") then
			if isMusicMuted then
				if not inst:GetAttribute("OrigVolume") then
					inst:SetAttribute("OrigVolume", inst.Volume)
				end
				inst.Volume = 0
			else
				inst.Volume = inst:GetAttribute("OrigVolume") or 0.5
			end
		end
	end
	if isMusicMuted then
		state.showToast("🔇 Música y audio silenciados [M]", Color3.fromRGB(240, 100, 100))
	else
		state.showToast("🔊 Audio y efectos activados [M]", Color3.fromRGB(100, 240, 140))
	end
end

-- Cierre de ventanas y menús abiertos (Atajo Esc)
local function closeOpenModals()
	local closed = false
	if tacticalModal and tacticalModal.Visible then
		tacticalModal.Visible = false
		closed = true
	end
	if lobbyScreen and lobbyScreen.Visible and state.initialized then
		showLobby(false)
		closed = true
	end
	local cp = root:FindFirstChild("CountryPanel")
	if cp and cp.Visible then
		cp.Visible = false
		closed = true
	end
	return closed
end

-- FrontWars Hotkeys & Atajos rápidos:
-- H: Configuración Táctica / How to Play
-- M: Silenciar música y audio
-- Esc: Cerrar menús y ventanas emergentes
-- 1-0: Construcción rápida (Ciudad, Fábrica, Puerto, Puesto, SAM, Barco, Granja, Mina, Base Aérea, Silo)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.H then
		if tacticalModal then
			tacticalModal.Visible = not tacticalModal.Visible
		end
	elseif input.KeyCode == Enum.KeyCode.M then
		toggleMusicMute()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		closeOpenModals()
	elseif input.KeyCode == Enum.KeyCode.One then
		setActionMode("BUILD_City")
	elseif input.KeyCode == Enum.KeyCode.Two then
		setActionMode("BUILD_Factory")
	elseif input.KeyCode == Enum.KeyCode.Three then
		setActionMode("BUILD_Port")
	elseif input.KeyCode == Enum.KeyCode.Four then
		setActionMode("BUILD_Post")
	elseif input.KeyCode == Enum.KeyCode.Five then
		setActionMode("BUILD_SAM")
	elseif input.KeyCode == Enum.KeyCode.Six then
		setActionMode("BUILD_Warship")
	elseif input.KeyCode == Enum.KeyCode.Seven then
		setActionMode("BUILD_Farm")
	elseif input.KeyCode == Enum.KeyCode.Eight then
		setActionMode("BUILD_Mine")
	elseif input.KeyCode == Enum.KeyCode.Nine then
		setActionMode("BUILD_Airbase")
	elseif input.KeyCode == Enum.KeyCode.Zero then
		setActionMode("BUILD_Silo")
	elseif input.KeyCode == Enum.KeyCode.R then
		setActionMode("RETREAT")
		WorldCommand:FireServer({ a = "RETREAT" })
		state.showToast("🏳️ Retirada ordenada: tropas devueltas al territorio", Color3.fromRGB(255, 180, 50))
	elseif input.KeyCode == Enum.KeyCode.G then
		setActionMode("ATTACK")
	elseif input.KeyCode == Enum.KeyCode.X then
		setActionMode("DEMOLISH")
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

-- Cada fotograma el zoom y el paneo se acercan al objetivo (animación ultra fluida a 60 FPS)
RunService.RenderStepped:Connect(function(dt)
	local diff = zoomTarget - state.zoom
	if math.abs(diff) > 0.0004 then
		applyZoom(zoomAnchor, (state.zoom + diff * math.min(1, dt * 14)) / state.zoom)
	end
	if panTarget then
		local diffP = panTarget - state.pan
		if diffP.Magnitude > 0.6 then
			state.pan = state.pan + diffP * math.min(1, dt * 14)
			clampPan()
			updateMapTransform()
		else
			state.pan = panTarget
			panTarget = nil
		end
	end
	if state.targetTroops and state.displayedTroops then
		local dTr = state.targetTroops - state.displayedTroops
		if math.abs(dTr) > 0.4 then
			state.displayedTroops += dTr * math.min(1, dt * 12)
			if math.abs(state.targetTroops - state.displayedTroops) < 1 then
				state.displayedTroops = state.targetTroops
			end
			local roundTr = math.floor(state.displayedTroops + 0.5)
			troopsCard.Text = string.format(
				"⚔️ %s / %s (⚡+%.1f%%/s)%s",
				troopText(roundTr),
				troopText(state.maxTroops or 10000),
				state.troopPct or 0,
				if state.isCapped then " ⚠️ CAP" else ""
			)
		end
	end
end)

-- Muestra el mundo entero ajustado a la pantalla
function fitToScreen()
	state.zoom = fitZoom()
	zoomTarget = state.zoom
	state.pan = Vector2.zero
	panTarget = nil
	updateMapTransform()
end

-- Centra la vista en una celda con interpolación suave
function focusCell(cell, zoom)
	local z = zoom or state.zoom
	zoomTarget = math.clamp(z, fitZoom() * 0.85, MAX_ZOOM)
	zoomAnchor = mapContainer.AbsoluteSize / 2
	local normX = (cell % state.w + 0.5) / state.w - 0.5
	local normY = (cell // state.w + 0.5) / state.h - 0.5
	panTarget = Vector2.new(-normX * BASE_WIDTH * zoomTarget, -normY * BASE_HEIGHT * zoomTarget)
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
zoomScale = Instance.new("UIScale")
zoomScale.Parent = zoomBar

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
local cloudsOn = false
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
spawnBanner.Position = UDim2.new(0.5, 0, 0, 10)
spawnBanner.Size = UDim2.fromOffset(440, 44)
spawnBanner.BackgroundColor3 = Color3.fromRGB(15, 22, 35)
spawnBanner.BackgroundTransparency = 0.06
spawnBanner.BorderSizePixel = 0
spawnBanner.Visible = false
spawnBanner.ZIndex = 40
spawnBanner.Parent = root
roundCorners(spawnBanner, 22)

local spawnBannerStroke = Instance.new("UIStroke")
spawnBannerStroke.Color = Color3.fromRGB(0, 229, 255)
spawnBannerStroke.Thickness = 1.5
spawnBannerStroke.Parent = spawnBanner

spawnScale = Instance.new("UIScale")
spawnScale.Parent = spawnBanner

local bannerTitle = Instance.new("TextLabel")
bannerTitle.Position = UDim2.fromOffset(20, 0)
bannerTitle.Size = UDim2.new(1, -150, 1, 0)
bannerTitle.BackgroundTransparency = 1
bannerTitle.Font = Enum.Font.GothamBlack
bannerTitle.Text = "📍 Elige el lugar de inicio"
bannerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
bannerTitle.TextSize = 13
bannerTitle.TextXAlignment = Enum.TextXAlignment.Left
bannerTitle.ZIndex = 41
bannerTitle.Parent = spawnBanner

local bannerTime = bannerTitle
local bannerSub = bannerTitle
local bannerBar = Instance.new("Frame")
bannerBar.Parent = spawnBanner
bannerBar.Visible = false

local btnStartNow = Instance.new("TextButton")
btnStartNow.Name = "BtnStartNow"
btnStartNow.AnchorPoint = Vector2.new(1, 0.5)
btnStartNow.Position = UDim2.new(1, -8, 0.5, 0)
btnStartNow.Size = UDim2.fromOffset(110, 30)
btnStartNow.BackgroundColor3 = Color3.fromRGB(0, 190, 110)
btnStartNow.BorderSizePixel = 0
btnStartNow.Font = Enum.Font.GothamBlack
btnStartNow.Text = "▶ ¡LISTO!"
btnStartNow.TextColor3 = Color3.fromRGB(255, 255, 255)
btnStartNow.TextSize = 12
btnStartNow.ZIndex = 45
btnStartNow.Parent = spawnBanner
roundCorners(btnStartNow, 15)

btnStartNow.MouseButton1Click:Connect(function()
	WorldCommand:FireServer({ a = "START_NOW" })
	btnStartNow.Visible = false
	showToast("⚔️ ¡Comenzando batalla ahora!", Color3.fromRGB(0, 230, 140))
end)

local function updateSpawnUI()
	local s = state.stats
	local spawning = s ~= nil and s.phase == "SPAWN"
	spawnBanner.Visible = spawning and state.initialized and not lobbyScreen.Visible
	if not spawning then
		return
	end
	local left = s.spawnTimer or 0
	local placed = state.me ~= nil and state.me.alive == true
	bannerTitle.Text = if placed
		then string.format("✅ Capital fijada · %ds", math.ceil(left))
		else string.format("📍 Elige el lugar de inicio · %ds", math.ceil(left))
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
		local valid = spawnValid(cell)
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 6)
		previewStroke.Color = if valid then Color3.fromRGB(70, 255, 150) else Color3.fromRGB(255, 80, 80)
		previewRing.BackgroundColor3 = previewStroke.Color
		previewRing.BackgroundTransparency = if valid then (0.70 + 0.15 * pulse) else 0.85
		previewStroke.Thickness = if valid then (2.5 + pulse) else 2
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
-- FRENTE DE EXPANSIÓN ORGÁNICA Y FLUJO INTERNO DE PARTÍCULAS (ESTILO FRONTWARS / CONQUR)
-- Las celdas conquistadas nacen como partículas circulares brillantes que se expanden en ondas fluidas.
-- No hay frontera cuadriculada rígida; el avance es un frente suave de partículas orgánicas.
-- ============================================================================
local frontBegin, frontPush
do
	local FRONT_MAX_ACTIVE = 40
	local FRONT_PER_DIFF = 400
	local FRONT_FADE = 1.1
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

	-- Swarm de partículas internas: tropas marchando desde el interior hacia las fronteras
	local SWARM_MAX = 25
	local swarm = {
		free = {},
		active = {},
		spawnAcc = 0,
	}

	function frontBegin(changes)
		if not front.layer then
			local l = Instance.new("Frame")
			l.Name = "FrontLayer"
			l.Size = UDim2.fromScale(1, 1)
			l.BackgroundTransparency = 1
			l.BorderSizePixel = 0
			l.ZIndex = 5
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

	function frontPush(cell, ownerId)
		if front.count >= FRONT_MAX_ACTIVE or math.random() > front.chance then
			return
		end
		local w, h = state.w, state.h
		local x, y = cell % w, cell // w
		if x < front.x0 or x > front.x1 or y < front.y0 or y > front.y1 then
			return
		end
		local n = state.rosterById[ownerId]
		if not n then
			return
		end
		if ownerId == state.myId and (os.clock() - (state.lastPopSound or 0) > 0.16) then
			state.lastPopSound = os.clock()
			playSound("POP", 1.15 + math.random() * 0.15, 0.25)
		end
		local f = table.remove(front.free)
		if not f then
			f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.ZIndex = 5
			f.Parent = front.layer
			roundCorners(f, 100) -- Partícula circular orgánica (no cuadrada)
		end
		f.Position = UDim2.fromScale((x + 0.5) / w, (y + 0.5) / h)
		f.Size = UDim2.fromScale(1.4 / w, 1.4 / h)
		f.BackgroundColor3 = n.color:Lerp(Color3.new(1, 1, 1), 0.7)
		f.BackgroundTransparency = 0.05
		f.Visible = true
		front.active[#front.active + 1] = {
			f = f,
			t0 = os.clock(),
			baseColor = n.color,
			w = w,
			h = h,
		}
		front.count += 1
	end

	local function spawnTroopParticle(x0, y0, targetCell, color)
		if #swarm.active >= SWARM_MAX or not front.layer then
			return
		end
		local p = table.remove(swarm.free)
		if not p then
			p = Instance.new("Frame")
			p.BorderSizePixel = 0
			p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.ZIndex = 5
			p.Parent = front.layer
			roundCorners(p, 100)
		end
		local w, h = state.w, state.h
		local tx, ty = targetCell % w, targetCell // w
		p.Size = UDim2.fromScale(1.1 / w, 1.1 / h)
		p.Position = UDim2.fromScale((x0 + 0.5) / w, (y0 + 0.5) / h)
		p.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5)
		p.BackgroundTransparency = 0.1
		p.Visible = true
		swarm.active[#swarm.active + 1] = {
			p = p,
			t0 = os.clock(),
			dur = 0.6 + math.random() * 0.4,
			sx = (x0 + 0.5) / w,
			sy = (y0 + 0.5) / h,
			tx = (tx + 0.5) / w,
			ty = (ty + 0.5) / h,
		}
	end

	local frontAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		frontAcc += dt
		if frontAcc < 0.033 then -- ~30 FPS para movimiento ultra fluido de partículas
			return
		end
		frontAcc = 0
		local now = os.clock()

		-- 1. Expansión orgánica de ondas de partículas en el frente conquistado
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
				-- Expansión suave hacia fuera (1.2 -> 2.6 tamaño)
				local grow = 1.2 + 1.4 * math.sin(t * math.pi * 0.5)
				a.f.Size = UDim2.fromScale(grow / a.w, grow / a.h)
				a.f.BackgroundTransparency = 0.05 + 0.95 * (t ^ 1.4)
				a.f.BackgroundColor3 = a.baseColor:Lerp(Color3.new(1, 1, 1), 0.7 * (1 - t))
				i += 1
			end
		end

		-- 2. Flujo de partículas internas marchando desde el interior hacia las fronteras
		swarm.spawnAcc += dt
		local spawnInterval = if (state.recentTargetCell and (now - (state.recentTargetTime or 0) < 3.5)) then 0.06 else 0.12
		if swarm.spawnAcc >= spawnInterval then
			swarm.spawnAcc = 0
			local me = state.me
			if me and me.alive and me.capital and state.w and state.h then
				local w, h = state.w, state.h
				local cap = me.capital
				local cx, cy = cap % w, cap // w
				local myN = state.rosterById[state.myId]
				local col = if myN and myN.color then myN.color else Color3.fromRGB(0, 255, 200)

				-- Si el jugador ha hecho clic recientemente en una celda (expansión neutral o ataque),
				-- o si hay ataques activos del servidor, dirigimos las tropas hacia allí:
				local tgtCell = nil
				if state.recentTargetCell and (now - (state.recentTargetTime or 0) < 4.0) then
					tgtCell = state.recentTargetCell
				else
					local attacks = me.attacks or {}
					if #attacks > 0 and attacks[1].target then
						local tgtNation = state.rosterById[attacks[1].target]
						if tgtNation and tgtNation.capital then
							tgtCell = tgtNation.capital
						end
					end
				end

				-- O emite hacia una celda aleatoria de la frontera
				if not tgtCell then
					local angle = math.random() * math.pi * 2
					local dist = 6 + math.random() * 14
					local fx = math.clamp(math.floor(cx + math.cos(angle) * dist), 0, w - 1)
					local fy = math.clamp(math.floor(cy + math.sin(angle) * dist), 0, h - 1)
					tgtCell = fy * w + fx
				end

				spawnTroopParticle(cx, cy, tgtCell, col)
			end
		end

		local sAct = swarm.active
		local j = 1
		while j <= #sAct do
			local s = sAct[j]
			local st = (now - s.t0) / s.dur
			if st >= 1 then
				s.p.Visible = false
				table.insert(swarm.free, s.p)
				sAct[j] = sAct[#sAct]
				sAct[#sAct] = nil
			else
				local curX = s.sx + (s.tx - s.sx) * st
				local curY = s.sy + (s.ty - s.sy) * st
				s.p.Position = UDim2.fromScale(curX, curY)
				s.p.BackgroundTransparency = 0.1 + 0.6 * st
				j += 1
			end
		end
	end)
end

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

-- ============================================================================
-- CONTROLADOR DE ESCALADO RESPONSIVO UISCALE (1080p / 720p / Móvil Automático)
-- ============================================================================
local function fitUI()
	local vs = root.AbsoluteSize
	if vs.X <= 0 or vs.Y <= 0 then
		return
	end

	-- Modos de resolución de calidad táctica:
	-- 1080p Desktop: vs.X >= 1500 or vs.Y >= 820 -> Escala 1.0 a 1.20
	-- 720p Laptop / Tablet: vs.X entre 1000 y 1500 -> Escala 0.78 a 0.95
	-- Móvil / Ventana pequeña: vs.X < 1000 or vs.Y < 580 -> Escala 0.52 a 0.75
	local s = 1.0
	if vs.X >= 1500 and vs.Y >= 820 then
		s = math.clamp(math.min(vs.X / 1920, vs.Y / 1080) * 1.08, 0.95, 1.20)
	elseif vs.X >= 1000 and vs.Y >= 600 then
		s = math.clamp(math.min(vs.X / 1350, vs.Y / 760), 0.78, 0.95)
	else
		s = math.clamp(math.min(vs.X / 960, vs.Y / 540), 0.52, 0.75)
	end

	hudScale.Scale = s
	leaderScale.Scale = s
	countryScale.Scale = s
	if radarScale then radarScale.Scale = s end
	if zoomScale then zoomScale.Scale = s end
	if spawnScale then spawnScale.Scale = s end
	if modalScale then modalScale.Scale = s end

	-- En pantallas estrechas (móviles / 720p) adaptamos botones para evitar solapamiento
	local isCompact = vs.X < 1180 or s < 0.82
	titleLabel.Visible = vs.X >= 1180
	if isCompact then
		btnTactical.Text = "⚙️ H"
		btnTactical.Size = UDim2.fromOffset(56, 32)
		btnTactical.Position = UDim2.new(1, -380, 0.5, 0)
	else
		btnTactical.Text = "⚙️ Táctica (H)"
		btnTactical.Size = UDim2.fromOffset(116, 34)
		btnTactical.Position = UDim2.new(1, -506, 0.5, 0)
	end

	countryPanel.Size = UDim2.fromOffset(290, math.max(220, (vs.Y - 210) / s))
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
			if state.animReady and updateCellEdges then
				updateCellEdges(cell)
				local w, h = state.w, state.h
				local x, y = cell % w, cell // w
				updateCellEdges(y * w + (if x == w - 1 then 0 else x + 1))
				updateCellEdges(y * w + (if x == 0 then w - 1 else x - 1))
				if y > 0 then updateCellEdges(cell - w) end
				if y < h - 1 then updateCellEdges(cell + w) end
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
	updateBuildings(stats.buildings)
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

	-- Actualizar fase y reloj OpenFront.io
	if stats.phase == "SPAWN" then
		local sLeft = math.max(0, math.ceil(stats.spawnTimer or 0))
		clockLabel.Text = string.format("%02ds", sLeft)
	elseif stats.phase == "BATTLE" or stats.phase == "RUNNING" then
		if stats.time then
			local t = math.floor(stats.time)
			clockLabel.Text = string.format("%02d:%02d", math.floor(t / 60), t % 60)
		end
	elseif stats.phase == "ENDED" then
		clockLabel.Text = "FIN"
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

local updateAttackPill, updateAllyCards, setSpectator
do
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

function updateAttackPill(meData)
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
btnAlly.Position = UDim2.fromOffset(260, 4)
btnAlly.Size = UDim2.fromOffset(92, 28)
btnAlly.BackgroundColor3 = Color3.fromRGB(30, 42, 64)
btnAlly.Font = Enum.Font.GothamBold
btnAlly.Text = "🤝 Alianza"
btnAlly.TextColor3 = Color3.fromRGB(255, 255, 255)
btnAlly.TextSize = 11
btnAlly.BorderSizePixel = 0
btnAlly.ZIndex = 26
btnAlly.Parent = inGameDock
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

function updateAllyCards(meData)
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

function setSpectator(on)
	if spectatorBanner.Visible == on then
		return
	end
	spectatorBanner.Visible = on
	bottomHUD.Visible = not on
	weaponBar.Visible = not on
end
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
	-- Valores reales del servidor: tropas/tope y ritmo por segundo (crecimiento compuesto estilo FrontWars), oro y su ritmo
	local tr = meData.troops or 0
	local maxTr = meData.maxTroops or 10000
	local trRate = meData.troopRate or 0
	local pct = if tr > 0 then (trRate / tr) * 100 else 0
	local isCapped = tr >= maxTr * 0.85

	state.targetTroops = tr
	state.maxTroops = maxTr
	state.troopPct = pct
	state.isCapped = isCapped
	if not state.displayedTroops then
		state.displayedTroops = tr
	end

	troopsCard.Text = string.format(
		"⚔️ %s / %s (⚡+%.1f%%/s)%s",
		troopText(math.floor(state.displayedTroops + 0.5)),
		troopText(maxTr),
		pct,
		if isCapped then " ⚠️ CAP" else ""
	)
	if isCapped then
		troopsCard.TextColor3 = Color3.fromRGB(255, 185, 40)
		if not state.lastCapWarn or (os.clock() - state.lastCapWarn > 18) then
			state.lastCapWarn = os.clock()
			showToast("⚠️ Capacidad casi llena: Construye Ciudades ($500) para aumentar tu límite de tropas", Color3.fromRGB(255, 190, 50))
		end
	else
		troopsCard.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
	goldCard.Text = string.format("💰 Oro: %s (+%d/s)", troopText(meData.gold or 0), math.floor((meData.goldRate or 0) + 0.5))
end)

-- FEED DE EVENTOS (estilo RoWorld): tarjetas a la izquierda; verde = logros, rojo = amenazas, morado = alianzas
task.spawn(
	function() -- el feed vive en su propia función: no consume variables locales del ámbito principal (límite 200)
		local feedLayer = Instance.new("Frame")
		feedLayer.Name = "EventFeed"
		feedLayer.AnchorPoint = Vector2.new(1, 1)
		feedLayer.Position = UDim2.new(1, -80, 1, -130)
		feedLayer.Size = UDim2.fromOffset(310, 220)
		feedLayer.BackgroundTransparency = 1
		feedLayer.ZIndex = 26
		feedLayer.Parent = root
		local feedList = Instance.new("UIListLayout")
		feedList.Padding = UDim.new(0, 4)
		feedList.VerticalAlignment = Enum.VerticalAlignment.Bottom
		feedList.SortOrder = Enum.SortOrder.LayoutOrder
		feedList.Parent = feedLayer

		local FEED_MAX = 6
		local FEED_SECONDS = 9
		local feedOrder = 0

		local function feedColor(text)
			if
				text:find("te está atacando")
				or text:find("Has sido eliminado")
				or text:find("TRAIDOR")
				or text:find("rompió")
			then
				return Color3.fromRGB(230, 70, 70)
			elseif text:find("Has eliminado") or text:find("🏆") or text:find("conquist") then
				return Color3.fromRGB(60, 200, 120)
			elseif text:find("alianza") or text:find("Alianza") then
				return Color3.fromRGB(160, 130, 255)
			end
			return Color3.fromRGB(150, 160, 185)
		end

		local function pushFeed(text)
			feedOrder += 1
			local color = feedColor(text)
			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 30)
			card.BackgroundColor3 = Color3.fromRGB(16, 22, 36)
			card.BackgroundTransparency = 0.08
			card.BorderSizePixel = 0
			card.LayoutOrder = feedOrder
			card.ZIndex = 27
			card.Parent = feedLayer
			roundCorners(card, 6)

			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 4, 1, 0)
			bar.BackgroundColor3 = color
			bar.BorderSizePixel = 0
			bar.ZIndex = 28
			bar.Parent = card
			roundCorners(bar, 2)

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, -16, 1, 0)
			label.Position = UDim2.fromOffset(12, 0)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamMedium
			label.TextSize = 12
			label.TextColor3 = Color3.fromRGB(235, 240, 252)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Text = text
			label.ZIndex = 28
			label.Parent = card

			-- Máximo de tarjetas: se quita la más antigua
			local cards = {}
			for _, c in ipairs(feedLayer:GetChildren()) do
				if c:IsA("Frame") then
					table.insert(cards, c)
				end
			end
			table.sort(cards, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			while #cards > FEED_MAX do
				table.remove(cards, 1):Destroy()
			end

			task.delay(FEED_SECONDS, function()
				if card.Parent then
					TweenService:Create(card, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
					TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
					TweenService:Create(bar, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
					task.delay(0.55, function()
						card:Destroy()
					end)
				end
			end)
		end

		WorldNotice.OnClientEvent:Connect(function(msg)
			-- Los avisos de error ("⚠️") siguen saliendo como aviso central; el resto va al feed
			if msg:sub(1, 2) == "⚠" or msg:find("^⚠") then
				showToast(msg, Color3.fromRGB(255, 220, 50))
			else
				pushFeed(msg)
			end
		end)
	end
)

-- La partida empieza cuando el jugador pulsa JUGAR en la pantalla de lobby (ver LobbyScreen).

updateMapTransform()
