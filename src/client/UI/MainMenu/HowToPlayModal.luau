--!strict
-- HowToPlayModal.luau
-- Modal interactivo HOW TO PLAY con ScrollingFrame, las 7 tarjetas de mecánicas tácticas,
-- sub-grilla de economía (7 estructuras), controles MOUSE & KEYBOARD y TOUCH, y CREDITS & LICENCE.

local TweenService = game:GetService("TweenService")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local HowToPlayModal = {}
HowToPlayModal.__index = HowToPlayModal

export type HowToPlayCallbacks = {
	OnClose: (() -> ())?,
}

export type HowToPlayModalInstance = {
	root: Frame,
	card: Frame,
	isOpen: boolean,
	cleanups: { () -> () },
	Show: (self: HowToPlayModalInstance) -> (),
	Hide: (self: HowToPlayModalInstance) -> (),
	Toggle: (self: HowToPlayModalInstance) -> (),
	Destroy: (self: HowToPlayModalInstance) -> (),
}

local function roundCorners(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function addStroke(parent: Instance, color: Color3, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Parent = parent
	return s
end

local function createIconCircle(parent: Instance, symbol: string, accentColor: Color3): Frame
	local circle = Instance.new("Frame")
	circle.Name = "IconCircle"
	circle.Size = UDim2.fromOffset(40, 40)
	circle.BackgroundColor3 = Color3.fromHex("#141E30")
	circle.BorderSizePixel = 0
	circle.ZIndex = 43
	circle.Parent = parent
	roundCorners(circle, 20)

	local s = addStroke(circle, accentColor, 1.2)
	s.Transparency = 0.25

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = MenuTheme.Fonts.Title
	lbl.Text = symbol
	lbl.TextColor3 = accentColor
	lbl.TextSize = 18
	lbl.ZIndex = 44
	lbl.Parent = circle

	return circle
end

local function createMiniCard(
	parent: Instance,
	order: number,
	numberStr: string,
	titleStr: string,
	bodyStr: string,
	iconSymbol: string,
	accentColor: Color3
): Frame
	local card = Instance.new("Frame")
	card.Name = "Card_" .. numberStr
	card.LayoutOrder = order
	card.Size = UDim2.new(0.5, -6, 0, 116)
	card.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	card.BackgroundTransparency = MenuTheme.Transparency.SideCard
	card.BorderSizePixel = 0
	card.ZIndex = 42
	card.Parent = parent
	roundCorners(card, 10)
	addStroke(card, MenuTheme.Colors.CardStroke, 1)

	local icon = createIconCircle(card, iconSymbol, accentColor)
	icon.Position = UDim2.fromOffset(12, 14)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(62, 12)
	title.Size = UDim2.new(1, -72, 0, 20)
	title.BackgroundTransparency = 1
	title.Font = MenuTheme.Fonts.Heading
	title.Text = numberStr .. "  " .. titleStr
	title.TextColor3 = MenuTheme.Colors.White
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 43
	title.Parent = card

	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.Position = UDim2.fromOffset(62, 34)
	desc.Size = UDim2.new(1, -72, 0, 72)
	desc.BackgroundTransparency = 1
	desc.Font = MenuTheme.Fonts.Regular
	desc.Text = bodyStr
	desc.TextColor3 = MenuTheme.Colors.SubtleText
	desc.TextSize = 11
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.ZIndex = 43
	desc.Parent = card

	return card
end

function HowToPlayModal.new(parent: Instance, callbacks: HowToPlayCallbacks?): HowToPlayModalInstance
	local cb: HowToPlayCallbacks = callbacks or {}
	local cleanups: { () -> () } = {}

	-- Backdrop oscuro
	local root = Instance.new("Frame")
	root.Name = "HowToPlayBackdrop"
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromScale(0, 0)
	root.BackgroundColor3 = Color3.fromHex("#000000")
	root.BackgroundTransparency = 0.45
	root.BorderSizePixel = 0
	root.Visible = false
	root.Active = true
	root.ZIndex = 40
	root.Parent = parent

	-- Contenedor principal
	local card = Instance.new("Frame")
	card.Name = "ModalContainer"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.66, 0.88)
	card.BackgroundColor3 = MenuTheme.Colors.ModalBg
	card.BackgroundTransparency = 0.04
	card.BorderSizePixel = 0
	card.ZIndex = 41
	card.ClipsDescendants = true
	card.Parent = root
	roundCorners(card, 14)
	addStroke(card, MenuTheme.Colors.CardStroke, 1.2)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(620, 500)
	sizeConstraint.MaxSize = Vector2.new(880, 760)
	sizeConstraint.Parent = card

	local cardScale = Instance.new("UIScale")
	cardScale.Scale = 1
	cardScale.Parent = card

	-- =========================================================================
	-- CABECERA FIJA SUPERIOR
	-- =========================================================================
	local header = Instance.new("Frame")
	header.Name = "FixedHeader"
	header.Size = UDim2.new(1, 0, 0, 68)
	header.BackgroundColor3 = Color3.fromHex("#0A101C")
	header.BorderSizePixel = 0
	header.ZIndex = 42
	header.Parent = card

	local headerDiv = Instance.new("Frame")
	headerDiv.Name = "HeaderDivider"
	headerDiv.Position = UDim2.new(0, 0, 1, -1)
	headerDiv.Size = UDim2.new(1, 0, 0, 1)
	headerDiv.BackgroundColor3 = MenuTheme.Colors.CardStroke
	headerDiv.BorderSizePixel = 0
	headerDiv.ZIndex = 43
	headerDiv.Parent = header

	local qCircle = createIconCircle(header, "?", MenuTheme.Colors.AccentGold)
	qCircle.Position = UDim2.fromOffset(20, 14)

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "HeaderTitle"
	headerTitle.Position = UDim2.fromOffset(70, 14)
	headerTitle.Size = UDim2.new(1, -140, 0, 22)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Font = MenuTheme.Fonts.Heading
	headerTitle.Text = "HOW TO PLAY"
	headerTitle.TextColor3 = MenuTheme.Colors.White
	headerTitle.TextSize = 18
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.ZIndex = 43
	headerTitle.Parent = header

	local headerSubtitle = Instance.new("TextLabel")
	headerSubtitle.Name = "HeaderSubtitle"
	headerSubtitle.Position = UDim2.fromOffset(70, 36)
	headerSubtitle.Size = UDim2.new(1, -140, 0, 16)
	headerSubtitle.BackgroundTransparency = 1
	headerSubtitle.Font = MenuTheme.Fonts.Regular
	headerSubtitle.Text = "Conquer the real world in seven ideas."
	headerSubtitle.TextColor3 = MenuTheme.Colors.MutedText
	headerSubtitle.TextSize = 12
	headerSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	headerSubtitle.ZIndex = 43
	headerSubtitle.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "BtnClose"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -18, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.BackgroundColor3 = Color3.fromHex("#1A2538")
	closeBtn.AutoButtonColor = false
	closeBtn.Font = MenuTheme.Fonts.Heading
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = MenuTheme.Colors.SubtleText
	closeBtn.TextSize = 15
	closeBtn.ZIndex = 44
	closeBtn.Parent = header
	roundCorners(closeBtn, 8)
	local closeStroke = addStroke(closeBtn, MenuTheme.Colors.CardStroke, 1)

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(closeBtn, {
			stroke = closeStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanAccent,
		})
	)

	-- =========================================================================
	-- CUERPO DESLIZABLE (ScrollingFrame)
	-- =========================================================================
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ScrollContent"
	scroll.Position = UDim2.fromOffset(0, 68)
	scroll.Size = UDim2.new(1, 0, 1, -68)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = MenuTheme.Colors.CyanAccent
	scroll.ZIndex = 42
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = card

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 16)
	scrollPad.PaddingBottom = UDim.new(0, 24)
	scrollPad.PaddingLeft = UDim.new(0, 20)
	scrollPad.PaddingRight = UDim.new(0, 20)
	scrollPad.Parent = scroll

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.FillDirection = Enum.FillDirection.Vertical
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 12)
	scrollLayout.Parent = scroll

	-- ---- FILA 1: Tarjetas 01 & 02 ----
	local row1 = Instance.new("Frame")
	row1.Name = "Row1"
	row1.LayoutOrder = 1
	row1.Size = UDim2.new(1, 0, 0, 116)
	row1.BackgroundTransparency = 1
	row1.ZIndex = 42
	row1.Parent = scroll

	local row1Layout = Instance.new("UIListLayout")
	row1Layout.FillDirection = Enum.FillDirection.Horizontal
	row1Layout.SortOrder = Enum.SortOrder.LayoutOrder
	row1Layout.Padding = UDim.new(0, 12)
	row1Layout.Parent = row1

	createMiniCard(
		row1,
		1,
		"01",
		"Elige tu inicio",
		"Elige tu capital en tierra libre para comenzar. En modo solo el despliegue es inmediato en 5 s; en multijugador espera a la fase de inicio.",
		"🎯",
		MenuTheme.Colors.AccentGold
	)
	createMiniCard(
		row1,
		2,
		"02",
		"Expandir y atacar",
		"Haz clic en tierra neutral o en naciones vecinas para expandirte. La barra de ratio (20%-100%) define qué porcentaje de tu ejército envías al frente.",
		"⚔️",
		MenuTheme.Colors.AccentOrange
	)

	-- ---- FILA 2: Tarjetas 03 & 04 ----
	local row2 = Instance.new("Frame")
	row2.Name = "Row2"
	row2.LayoutOrder = 2
	row2.Size = UDim2.new(1, 0, 0, 116)
	row2.BackgroundTransparency = 1
	row2.ZIndex = 42
	row2.Parent = scroll

	local row2Layout = Instance.new("UIListLayout")
	row2Layout.FillDirection = Enum.FillDirection.Horizontal
	row2Layout.SortOrder = Enum.SortOrder.LayoutOrder
	row2Layout.Padding = UDim.new(0, 12)
	row2Layout.Parent = row2

	createMiniCard(
		row2,
		1,
		"03",
		"Boats",
		"Transporte marítimo por costa. Los barcos de guerra patrullan y atacan transportes → barcos de guerra → mercantes. Se curan en puertos bajo 75% de vida.",
		"🚢",
		MenuTheme.Colors.AccentCyan
	)
	createMiniCard(
		row2,
		2,
		"04",
		"Alliances & betrayal",
		"Clic derecho para proponer alianza o donar tropas. Romper un pacto te marca como Traidor por 30 s: los ataques te cuestan 50% y aterrizan más rápido.",
		"🤝",
		MenuTheme.Colors.AccentPurple
	)

	-- ---- FILA 3: Tarjeta ancha 05 Build your economy ----
	local econCard = Instance.new("Frame")
	econCard.Name = "Card_05_Economy"
	econCard.LayoutOrder = 3
	econCard.Size = UDim2.new(1, 0, 0, 230)
	econCard.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	econCard.BackgroundTransparency = MenuTheme.Transparency.SideCard
	econCard.BorderSizePixel = 0
	econCard.ZIndex = 42
	econCard.Parent = scroll
	roundCorners(econCard, 10)
	addStroke(econCard, MenuTheme.Colors.CardStroke, 1)

	local econPad = Instance.new("UIPadding")
	econPad.PaddingTop = UDim.new(0, 12)
	econPad.PaddingBottom = UDim.new(0, 12)
	econPad.PaddingLeft = UDim.new(0, 16)
	econPad.PaddingRight = UDim.new(0, 16)
	econPad.Parent = econCard

	local econHeader = Instance.new("Frame")
	econHeader.Name = "EconHeader"
	econHeader.Size = UDim2.new(1, 0, 0, 44)
	econHeader.BackgroundTransparency = 1
	econHeader.ZIndex = 43
	econHeader.Parent = econCard

	local eIcon = createIconCircle(econHeader, "📊", MenuTheme.Colors.AccentGold)
	eIcon.Position = UDim2.fromOffset(0, 2)

	local eTitle = Instance.new("TextLabel")
	eTitle.Name = "Title"
	eTitle.Position = UDim2.fromOffset(48, 2)
	eTitle.Size = UDim2.new(1, -48, 0, 18)
	eTitle.BackgroundTransparency = 1
	eTitle.Font = MenuTheme.Fonts.Heading
	eTitle.Text = "05  Build your economy"
	eTitle.TextColor3 = MenuTheme.Colors.White
	eTitle.TextSize = 14
	eTitle.TextXAlignment = Enum.TextXAlignment.Left
	eTitle.ZIndex = 43
	eTitle.Parent = econHeader

	local eSummary = Instance.new("TextLabel")
	eSummary.Name = "Summary"
	eSummary.Position = UDim2.fromOffset(48, 22)
	eSummary.Size = UDim2.new(1, -48, 0, 22)
	eSummary.BackgroundTransparency = 1
	eSummary.Font = MenuTheme.Fonts.Regular
	eSummary.Text = "Oro por tierra, fábricas y comercio. Separación mínima de 15 casillas. Teclas 1–7. El Puesto de defensa cuesta 5× tropas y 3× tiempo."
	eSummary.TextColor3 = MenuTheme.Colors.SubtleText
	eSummary.TextSize = 11
	eSummary.TextXAlignment = Enum.TextXAlignment.Left
	eSummary.ZIndex = 43
	eSummary.Parent = econHeader

	-- Sub-grilla de 2 columnas con los 7 elementos
	local econGrid = Instance.new("Frame")
	econGrid.Name = "EconGrid"
	econGrid.Position = UDim2.fromOffset(0, 52)
	econGrid.Size = UDim2.new(1, 0, 0, 154)
	econGrid.BackgroundTransparency = 1
	econGrid.ZIndex = 43
	econGrid.Parent = econCard

	local econItems = {
		{ name = "Ciudad", desc = "+25.0K límite de tropas, red de carreteras.", icon = "🏙️" },
		{ name = "Puerto", desc = "Costero, barcos de comercio y de guerra.", icon = "⚓" },
		{ name = "Fábrica", desc = "Centro de carreteras; camiones pagan oro.", icon = "🏭" },
		{ name = "Puesto de defensa", desc = "30 casillas; cuesta 5× tropas / 3× tiempo.", icon = "🛡️" },
		{ name = "Lanzador SAM", desc = "Destruye bombas en 70 casillas (no MIRV).", icon = "📡" },
		{ name = "Silo de misiles", desc = "Requerido para lanzar ataques nucleares.", icon = "🚀" },
		{ name = "Nave de guerra", desc = "Patrulla naval; se repara en puertos.", icon = "⚓" },
	}

	for idx, item in ipairs(econItems) do
		local col = (idx - 1) % 2
		local row = (idx - 1) // 2
		local itemFrame = Instance.new("Frame")
		itemFrame.Name = "Item_" .. item.name
		itemFrame.Position = UDim2.new(col * 0.5, col == 0 and 0 or 8, 0, row * 38)
		itemFrame.Size = UDim2.new(0.5, -8, 0, 34)
		itemFrame.BackgroundColor3 = Color3.fromHex("#111A29")
		itemFrame.BorderSizePixel = 0
		itemFrame.ZIndex = 44
		itemFrame.Parent = econGrid
		roundCorners(itemFrame, 6)

		local iLbl = Instance.new("TextLabel")
		iLbl.Position = UDim2.fromOffset(8, 0)
		iLbl.Size = UDim2.fromOffset(24, 34)
		iLbl.BackgroundTransparency = 1
		iLbl.Font = MenuTheme.Fonts.Heading
		iLbl.Text = item.icon
		iLbl.TextSize = 14
		iLbl.ZIndex = 45
		iLbl.Parent = itemFrame

		local tLbl = Instance.new("TextLabel")
		tLbl.Position = UDim2.fromOffset(34, 4)
		tLbl.Size = UDim2.new(1, -38, 0, 14)
		tLbl.BackgroundTransparency = 1
		tLbl.Font = MenuTheme.Fonts.Bold
		tLbl.Text = item.name
		tLbl.TextColor3 = MenuTheme.Colors.AccentGold
		tLbl.TextSize = 11
		tLbl.TextXAlignment = Enum.TextXAlignment.Left
		tLbl.ZIndex = 45
		tLbl.Parent = itemFrame

		local dLbl = Instance.new("TextLabel")
		dLbl.Position = UDim2.fromOffset(34, 18)
		dLbl.Size = UDim2.new(1, -38, 0, 14)
		dLbl.BackgroundTransparency = 1
		dLbl.Font = MenuTheme.Fonts.Regular
		dLbl.Text = item.desc
		dLbl.TextColor3 = MenuTheme.Colors.MutedText
		dLbl.TextSize = 10
		dLbl.TextXAlignment = Enum.TextXAlignment.Left
		dLbl.TextTruncate = Enum.TextTruncate.AtEnd
		dLbl.ZIndex = 45
		dLbl.Parent = itemFrame
	end

	-- ---- FILA 4: Tarjetas 06 & 07 ----
	local row4 = Instance.new("Frame")
	row4.Name = "Row4"
	row4.LayoutOrder = 4
	row4.Size = UDim2.new(1, 0, 0, 116)
	row4.BackgroundTransparency = 1
	row4.ZIndex = 42
	row4.Parent = scroll

	local row4Layout = Instance.new("UIListLayout")
	row4Layout.FillDirection = Enum.FillDirection.Horizontal
	row4Layout.SortOrder = Enum.SortOrder.LayoutOrder
	row4Layout.Padding = UDim.new(0, 12)
	row4Layout.Parent = row4

	createMiniCard(
		row4,
		1,
		"06",
		"Nukes & SAMs",
		"Bombas atómicas, de hidrógeno y MIRV; dejan radiación residual (fallout). Los SAMs tienen un alcance protector de 70 casillas.",
		"☢️",
		MenuTheme.Colors.AccentRed
	)
	createMiniCard(
		row4,
		2,
		"07",
		"Win at 80%",
		"Mantener el 80% de la tierra habitable (sin contar contaminación). En multijugador la partida concluye automáticamente a los 40 min.",
		"👑",
		MenuTheme.Colors.AccentGold
	)

	-- ---- FILA 5: Tarjeta ancha CONTROLS ----
	local ctrlCard = Instance.new("Frame")
	ctrlCard.Name = "Card_Controls"
	ctrlCard.LayoutOrder = 5
	ctrlCard.Size = UDim2.new(1, 0, 0, 390)
	ctrlCard.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	ctrlCard.BackgroundTransparency = MenuTheme.Transparency.SideCard
	ctrlCard.BorderSizePixel = 0
	ctrlCard.ZIndex = 42
	ctrlCard.Parent = scroll
	roundCorners(ctrlCard, 10)
	addStroke(ctrlCard, MenuTheme.Colors.CardStroke, 1)

	local ctrlPad = Instance.new("UIPadding")
	ctrlPad.PaddingTop = UDim.new(0, 14)
	ctrlPad.PaddingBottom = UDim.new(0, 14)
	ctrlPad.PaddingLeft = UDim.new(0, 16)
	ctrlPad.PaddingRight = UDim.new(0, 16)
	ctrlPad.Parent = ctrlCard

	local ctrlHeader = Instance.new("Frame")
	ctrlHeader.Name = "CtrlHeader"
	ctrlHeader.Size = UDim2.new(1, 0, 0, 42)
	ctrlHeader.BackgroundTransparency = 1
	ctrlHeader.ZIndex = 43
	ctrlHeader.Parent = ctrlCard

	local cIcon = createIconCircle(ctrlHeader, "⌨️", MenuTheme.Colors.AccentCyan)
	cIcon.Position = UDim2.fromOffset(0, 0)

	local cTitle = Instance.new("TextLabel")
	cTitle.Name = "Title"
	cTitle.Position = UDim2.fromOffset(48, 2)
	cTitle.Size = UDim2.new(1, -48, 0, 20)
	cTitle.BackgroundTransparency = 1
	cTitle.Font = MenuTheme.Fonts.Heading
	cTitle.Text = "CONTROLS"
	cTitle.TextColor3 = MenuTheme.Colors.AccentCyan
	cTitle.TextSize = 15
	cTitle.TextXAlignment = Enum.TextXAlignment.Left
	cTitle.ZIndex = 43
	cTitle.Parent = ctrlHeader

	local cSub = Instance.new("TextLabel")
	cSub.Name = "Sub"
	cSub.Position = UDim2.fromOffset(48, 22)
	cSub.Size = UDim2.new(1, -48, 0, 16)
	cSub.BackgroundTransparency = 1
	cSub.Font = MenuTheme.Fonts.Regular
	cSub.Text = "Guía completa para ratón, teclado y pantalla táctil."
	cSub.TextColor3 = MenuTheme.Colors.MutedText
	cSub.TextSize = 11
	cSub.TextXAlignment = Enum.TextXAlignment.Left
	cSub.ZIndex = 43
	cSub.Parent = ctrlHeader

	-- 2 columnas: MOUSE & KEYBOARD (izquierda) y TOUCH (derecha)
	local kbList = {
		{ key = "Click", desc = "Seleccionar celda / enviar ataque" },
		{ key = "Right-click", desc = "Proponer alianza / cancelar" },
		{ key = "Drag", desc = "Mover cámara táctica" },
		{ key = "WASD / Arrows", desc = "Paneo del mapa" },
		{ key = "Wheel / + -", desc = "Zoom in / out" },
		{ key = "1 - 0", desc = "Ratio de tropas / atajos de compra" },
		{ key = "Q / E", desc = "Alternar modo de construcción" },
		{ key = "Space", desc = "Centrar en capital" },
		{ key = "Backspace", desc = "Retirada de tropas" },
		{ key = "X / Right-click", desc = "Cancelar acción o selección" },
		{ key = "H", desc = "Abrir / cerrar Guía táctica" },
		{ key = "Tab", desc = "Tabla de clasificación" },
		{ key = "M", desc = "Silenciar / reproducir música" },
		{ key = "Home", desc = "Centrar cámara en capital" },
		{ key = "Click a warship", desc = "Ordenar patrulla naval" },
	}

	local touchList = {
		{ act = "Tap", desc = "Seleccionar o atacar celda" },
		{ act = "Long-press", desc = "Proponer alianza o menú" },
		{ act = "Drag", desc = "Desplazar mapa táctico" },
		{ act = "Pinch", desc = "Zoom in / out táctico" },
		{ act = "Tap a slot", desc = "Construir edificio elegido" },
		{ act = "Tap your land", desc = "Gestionar defensas locales" },
		{ act = "Tap a warship", desc = "Desplegar ruta naval" },
		{ act = "Tap an ally", desc = "Donar tropas aliadas" },
	}

	-- Columna Izquierda: MOUSE & KEYBOARD
	local colLeft = Instance.new("Frame")
	colLeft.Name = "ColMouseKeyboard"
	colLeft.Position = UDim2.fromOffset(0, 48)
	colLeft.Size = UDim2.new(0.55, -8, 1, -48)
	colLeft.BackgroundTransparency = 1
	colLeft.ZIndex = 43
	colLeft.Parent = ctrlCard

	local klHeader = Instance.new("TextLabel")
	klHeader.Size = UDim2.new(1, 0, 0, 18)
	klHeader.BackgroundTransparency = 1
	klHeader.Font = MenuTheme.Fonts.Heading
	klHeader.Text = "MOUSE & KEYBOARD"
	klHeader.TextColor3 = MenuTheme.Colors.White
	klHeader.TextSize = 11
	klHeader.TextXAlignment = Enum.TextXAlignment.Left
	klHeader.ZIndex = 44
	klHeader.Parent = colLeft

	for i, kb in ipairs(kbList) do
		local row = Instance.new("Frame")
		row.Name = "KBRow_" .. tostring(i)
		row.Position = UDim2.fromOffset(0, 20 + (i - 1) * 20)
		row.Size = UDim2.new(1, 0, 0, 18)
		row.BackgroundTransparency = 1
		row.ZIndex = 44
		row.Parent = colLeft

		local pill = Instance.new("Frame")
		pill.Name = "KeyPill"
		pill.Size = UDim2.fromOffset(88, 16)
		pill.BackgroundColor3 = MenuTheme.Colors.KeybindPillBg
		pill.BorderSizePixel = 0
		pill.ZIndex = 45
		pill.Parent = row
		roundCorners(pill, 4)

		local kLbl = Instance.new("TextLabel")
		kLbl.Size = UDim2.fromScale(1, 1)
		kLbl.BackgroundTransparency = 1
		kLbl.Font = MenuTheme.Fonts.Bold
		kLbl.Text = kb.key
		kLbl.TextColor3 = MenuTheme.Colors.AccentCyan
		kLbl.TextSize = 9
		kLbl.ZIndex = 46
		kLbl.Parent = pill

		local dLbl = Instance.new("TextLabel")
		dLbl.Position = UDim2.fromOffset(96, 0)
		dLbl.Size = UDim2.new(1, -96, 1, 0)
		dLbl.BackgroundTransparency = 1
		dLbl.Font = MenuTheme.Fonts.Regular
		dLbl.Text = kb.desc
		dLbl.TextColor3 = MenuTheme.Colors.SubtleText
		dLbl.TextSize = 10
		dLbl.TextXAlignment = Enum.TextXAlignment.Left
		dLbl.TextTruncate = Enum.TextTruncate.AtEnd
		dLbl.ZIndex = 45
		dLbl.Parent = row
	end

	-- Columna Derecha: TOUCH
	local colRight = Instance.new("Frame")
	colRight.Name = "ColTouch"
	colRight.Position = UDim2.new(0.55, 8, 0, 48)
	colRight.Size = UDim2.new(0.45, -8, 1, -48)
	colRight.BackgroundTransparency = 1
	colRight.ZIndex = 43
	colRight.Parent = ctrlCard

	local trHeader = Instance.new("TextLabel")
	trHeader.Size = UDim2.new(1, 0, 0, 18)
	trHeader.BackgroundTransparency = 1
	trHeader.Font = MenuTheme.Fonts.Heading
	trHeader.Text = "TOUCH CONTROLS"
	trHeader.TextColor3 = MenuTheme.Colors.White
	trHeader.TextSize = 11
	trHeader.TextXAlignment = Enum.TextXAlignment.Left
	trHeader.ZIndex = 44
	trHeader.Parent = colRight

	for i, tc in ipairs(touchList) do
		local row = Instance.new("Frame")
		row.Name = "TouchRow_" .. tostring(i)
		row.Position = UDim2.fromOffset(0, 20 + (i - 1) * 22)
		row.Size = UDim2.new(1, 0, 0, 18)
		row.BackgroundTransparency = 1
		row.ZIndex = 44
		row.Parent = colRight

		local pill = Instance.new("Frame")
		pill.Name = "TouchPill"
		pill.Size = UDim2.fromOffset(80, 16)
		pill.BackgroundColor3 = MenuTheme.Colors.KeybindPillBg
		pill.BorderSizePixel = 0
		pill.ZIndex = 45
		pill.Parent = row
		roundCorners(pill, 4)

		local tLbl = Instance.new("TextLabel")
		tLbl.Size = UDim2.fromScale(1, 1)
		tLbl.BackgroundTransparency = 1
		tLbl.Font = MenuTheme.Fonts.Bold
		tLbl.Text = tc.act
		tLbl.TextColor3 = MenuTheme.Colors.AccentGold
		tLbl.TextSize = 9
		tLbl.ZIndex = 46
		tLbl.Parent = pill

		local dLbl = Instance.new("TextLabel")
		dLbl.Position = UDim2.fromOffset(88, 0)
		dLbl.Size = UDim2.new(1, -88, 1, 0)
		dLbl.BackgroundTransparency = 1
		dLbl.Font = MenuTheme.Fonts.Regular
		dLbl.Text = tc.desc
		dLbl.TextColor3 = MenuTheme.Colors.SubtleText
		dLbl.TextSize = 10
		dLbl.TextXAlignment = Enum.TextXAlignment.Left
		dLbl.TextTruncate = Enum.TextTruncate.AtEnd
		dLbl.ZIndex = 45
		dLbl.Parent = row
	end

	-- ---- FILA 6: Tarjeta CREDITS & LICENCE + pie Source ----
	local credCard = Instance.new("Frame")
	credCard.Name = "Card_Credits"
	credCard.LayoutOrder = 6
	credCard.Size = UDim2.new(1, 0, 0, 126)
	credCard.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	credCard.BackgroundTransparency = MenuTheme.Transparency.SideCard
	credCard.BorderSizePixel = 0
	credCard.ZIndex = 42
	credCard.Parent = scroll
	roundCorners(credCard, 10)
	addStroke(credCard, MenuTheme.Colors.CardStroke, 1)

	local credPad = Instance.new("UIPadding")
	credPad.PaddingTop = UDim.new(0, 12)
	credPad.PaddingBottom = UDim.new(0, 12)
	credPad.PaddingLeft = UDim.new(0, 16)
	credPad.PaddingRight = UDim.new(0, 16)
	credPad.Parent = credCard

	local crTitle = Instance.new("TextLabel")
	crTitle.Name = "CreditsTitle"
	crTitle.Size = UDim2.new(1, 0, 0, 18)
	crTitle.BackgroundTransparency = 1
	crTitle.Font = MenuTheme.Fonts.Heading
	crTitle.Text = "CREDITS & LICENCE"
	crTitle.TextColor3 = MenuTheme.Colors.White
	crTitle.TextSize = 13
	crTitle.TextXAlignment = Enum.TextXAlignment.Left
	crTitle.ZIndex = 43
	crTitle.Parent = credCard

	local crText = Instance.new("TextLabel")
	crText.Name = "CreditsBody"
	crText.Position = UDim2.fromOffset(0, 22)
	crText.Size = UDim2.new(1, 0, 0, 52)
	crText.BackgroundTransparency = 1
	crText.Font = MenuTheme.Fonts.Regular
	crText.Text = "CONQUER THE WORLD es un RTS táctico multijugador sobre mapa mundial global real.\n"
		.. "Diseñado en Luau estricto (--!strict) con sincronización Rojo. Mapas y modelos satelitales optimizados para alta fidelidad táctica."
	crText.TextColor3 = MenuTheme.Colors.MutedText
	crText.TextSize = 11
	crText.TextWrapped = true
	crText.TextXAlignment = Enum.TextXAlignment.Left
	crText.TextYAlignment = Enum.TextYAlignment.Top
	crText.ZIndex = 43
	crText.Parent = credCard

	local srcBtn = Instance.new("TextButton")
	srcBtn.Name = "BtnSource"
	srcBtn.Position = UDim2.fromOffset(0, 78)
	srcBtn.Size = UDim2.fromOffset(130, 24)
	srcBtn.BackgroundColor3 = Color3.fromHex("#142036")
	srcBtn.AutoButtonColor = false
	srcBtn.Font = MenuTheme.Fonts.Bold
	srcBtn.Text = "⚡ Project Source"
	srcBtn.TextColor3 = MenuTheme.Colors.CyanAccent
	srcBtn.TextSize = 11
	srcBtn.ZIndex = 44
	srcBtn.Parent = credCard
	roundCorners(srcBtn, 6)
	local srcStroke = addStroke(srcBtn, MenuTheme.Colors.CardStroke, 1)

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(srcBtn, {
			stroke = srcStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanAccent,
		})
	)

	-- =========================================================================
	-- CONTROLADORES DE APERTURA / CIERRE
	-- =========================================================================
	local self = setmetatable({
		root = root,
		card = card,
		cardScale = cardScale,
		isOpen = false,
		cleanups = cleanups,
		onClose = cb.OnClose,
	}, HowToPlayModal)

	closeBtn.MouseButton1Click:Connect(function()
		self:Hide()
	end)

	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			-- Clic en el backdrop fuera de la tarjeta
			local pos = input.Position
			local cardPos = card.AbsolutePosition
			local cardSize = card.AbsoluteSize
			if
				pos.X < cardPos.X
				or pos.X > cardPos.X + cardSize.X
				or pos.Y < cardPos.Y
				or pos.Y > cardPos.Y + cardSize.Y
			then
				self:Hide()
			end
		end
	end)

	return (self :: any) :: HowToPlayModalInstance
end

function HowToPlayModal:Show()
	if self.isOpen then
		return
	end
	self.isOpen = true
	self.root.BackgroundTransparency = 1
	self.root.Visible = true
	self.cardScale.Scale = 0.94

	TweenService:Create(
		self.root,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.45 }
	):Play()

	TweenService:Create(
		self.cardScale,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

function HowToPlayModal:Hide()
	if not self.isOpen then
		return
	end
	self.isOpen = false

	local fadeTween = TweenService:Create(
		self.root,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	fadeTween:Play()

	TweenService:Create(
		self.cardScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0.94 }
	):Play()

	fadeTween.Completed:Wait()
	if not self.isOpen then
		self.root.Visible = false
	end

	if self.onClose then
		self.onClose()
	end
end

function HowToPlayModal:Toggle()
	if self.isOpen then
		self:Hide()
	else
		self:Show()
	end
end

function HowToPlayModal:Destroy()
	for _, fn in ipairs(self.cleanups) do
		fn()
	end
	table.clear(self.cleanups)
	if self.root then
		self.root:Destroy()
	end
end

return HowToPlayModal