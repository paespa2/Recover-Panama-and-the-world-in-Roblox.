--!strict
-- RightRailShop.luau
-- Columna derecha:
--  1. Fila superior (ARSENAL con ★ 148,510 + CAJAS con badge verde 15 tokens y botones píldora #E8BC77)
--  2. Banner Tienda de banderas (degradado morado #6B3FA0 -> #B38DF3, badge NUEVO #28A959,
--     bandera con rotación automática cada 3.5s vía TweenService y temporizador NUEVO EN 21:49:16)
--  3. Tarjeta GENERAL (fondo #141E30, borde dorado, badge MENSUAL #FDE8A2, emblema 3 estrellas
--     y subtítulo con transición fade cada 4s entre "+50% Estrellas en cada partida" y "Una nueva piel cada mes")

local TweenService = game:GetService("TweenService")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local RightRailShop = {}
RightRailShop.__index = RightRailShop

export type RightRailCallbacks = {
	OnOpenArsenal: (() -> ())?,
	OnOpenCrates: (() -> ())?,
	OnOpenFlagShop: (() -> ())?,
	OnOpenPass: (() -> ())?,
}

export type RightRailShopInstance = {
	root: Frame,
	starsBadgeLabel: TextLabel,
	cratesBadgeLabel: TextLabel,
	cleanups: { () -> () },
	running: boolean,
	SetCurrency: (self: RightRailShopInstance, stars: number, crateTokens: number) -> (),
	Destroy: (self: RightRailShopInstance) -> (),
}

type FlagDesign = {
	top: Color3,
	mid: Color3,
	bot: Color3,
	symbol: string,
}

local FLAG_DESIGNS: { FlagDesign } = {
	{ top = Color3.fromHex("#0067C6"), mid = Color3.fromHex("#FFFFFF"), bot = Color3.fromHex("#D21034"), symbol = "★" },
	{ top = Color3.fromHex("#FACC15"), mid = Color3.fromHex("#1D4ED8"), bot = Color3.fromHex("#DC2626"), symbol = "☀" },
	{ top = Color3.fromHex("#16A34A"), mid = Color3.fromHex("#FFFFFF"), bot = Color3.fromHex("#DC2626"), symbol = "🦅" },
	{ top = Color3.fromHex("#111827"), mid = Color3.fromHex("#DC2626"), bot = Color3.fromHex("#FACC15"), symbol = "⚔" },
	{ top = Color3.fromHex("#2563EB"), mid = Color3.fromHex("#FFFFFF"), bot = Color3.fromHex("#2563EB"), symbol = "⚜" },
}

local GENERAL_SUBTITLES: { string } = {
	"+50% Estrellas en cada partida",
	"Una nueva piel cada mes",
}

function RightRailShop.new(parent: Instance, callbacks: RightRailCallbacks?): RightRailShopInstance
	local cb: RightRailCallbacks = callbacks or {}
	local cleanups: { () -> () } = {}

	local root = Instance.new("Frame")
	root.Name = "RightRailShop"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(0.985, 0, 0.08, 0)
	root.Size = UDim2.fromOffset(296, 360)
	root.BackgroundTransparency = 1
	root.ZIndex = 6
	root.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = root

	-- =========================================================================
	-- 1. FILA SUPERIOR: ARSENAL y CAJAS (2 tarjetas lado a lado)
	-- =========================================================================
	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.LayoutOrder = 1
	topRow.Size = UDim2.new(1, 0, 0, 132)
	topRow.BackgroundTransparency = 1
	topRow.ZIndex = 7
	topRow.Parent = root

	local topRowLayout = Instance.new("UIListLayout")
	topRowLayout.FillDirection = Enum.FillDirection.Horizontal
	topRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	topRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topRowLayout.Padding = UDim.new(0, 12)
	topRowLayout.Parent = topRow

	local function createTopWidget(
		order: number,
		name: string,
		iconText: string,
		badgeText: string,
		isGreenBadge: boolean,
		buttonLabel: string,
		onClick: (() -> ())?
	): TextLabel
		local card = Instance.new("Frame")
		card.Name = name .. "Card"
		card.LayoutOrder = order
		card.Size = UDim2.fromOffset(142, 132)
		card.BackgroundColor3 = MenuTheme.Colors.SideCardBg
		card.BackgroundTransparency = MenuTheme.Transparency.SideCard
		card.BorderSizePixel = 0
		card.ZIndex = 7
		card.Parent = topRow

		local cc = Instance.new("UICorner")
		cc.CornerRadius = MenuTheme.Corners.Card
		cc.Parent = card

		local cs = Instance.new("UIStroke")
		cs.Color = MenuTheme.Colors.CardStroke
		cs.Thickness = 1
		cs.Parent = card

		-- Badge superior tipo píldora
		local badge = Instance.new("Frame")
		badge.Name = "TopBadge"
		badge.AnchorPoint = Vector2.new(0.5, 0)
		badge.Position = UDim2.new(0.5, 0, 0, 8)
		badge.Size = UDim2.fromOffset(if isGreenBadge then 74 else 118, 22)
		badge.BackgroundColor3 = if isGreenBadge then MenuTheme.Colors.BadgeGreen else Color3.fromHex("#0F172A")
		badge.BorderSizePixel = 0
		badge.ZIndex = 8
		badge.Parent = card

		local bc = Instance.new("UICorner")
		bc.CornerRadius = MenuTheme.Corners.Pill
		bc.Parent = badge

		local bs = Instance.new("UIStroke")
		bs.Color = if isGreenBadge then Color3.fromHex("#4ADE80") else MenuTheme.Colors.PillGold
		bs.Thickness = 1
		bs.Parent = badge

		local badgeLbl = Instance.new("TextLabel")
		badgeLbl.Name = "BadgeText"
		badgeLbl.Size = UDim2.fromScale(1, 1)
		badgeLbl.BackgroundTransparency = 1
		badgeLbl.Font = MenuTheme.Fonts.Heading
		badgeLbl.Text = badgeText
		badgeLbl.TextColor3 = if isGreenBadge then MenuTheme.Colors.White else MenuTheme.Colors.MonthlyBadge
		badgeLbl.TextSize = 11
		badgeLbl.ZIndex = 9
		badgeLbl.Parent = badge

		-- Brillo radial detrás del ícono central
		local glow = Instance.new("Frame")
		glow.Name = "RadialGlow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.new(0.5, 0, 0, 62)
		glow.Size = UDim2.fromOffset(50, 50)
		glow.BackgroundColor3 = MenuTheme.Colors.PillGold
		glow.BackgroundTransparency = 0.78
		glow.BorderSizePixel = 0
		glow.ZIndex = 7
		glow.Parent = card

		local gc = Instance.new("UICorner")
		gc.CornerRadius = MenuTheme.Corners.Pill
		gc.Parent = glow

		local centerIcon = Instance.new("TextLabel")
		centerIcon.Name = "CenterIcon"
		centerIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		centerIcon.Position = UDim2.new(0.5, 0, 0, 62)
		centerIcon.Size = UDim2.fromOffset(48, 48)
		centerIcon.BackgroundTransparency = 1
		centerIcon.Font = MenuTheme.Fonts.Title
		centerIcon.Text = iconText
		centerIcon.TextSize = 30
		centerIcon.TextColor3 = MenuTheme.Colors.MonthlyBadge
		centerIcon.ZIndex = 8
		centerIcon.Parent = card

		-- Botón inferior píldora #E8BC77 con texto oscuro #111827
		local pillBtn = Instance.new("TextButton")
		pillBtn.Name = "Btn" .. name
		pillBtn.AnchorPoint = Vector2.new(0.5, 1)
		pillBtn.Position = UDim2.new(0.5, 0, 1, -8)
		pillBtn.Size = UDim2.fromOffset(122, 30)
		pillBtn.BackgroundColor3 = MenuTheme.Colors.PillGold
		pillBtn.AutoButtonColor = false
		pillBtn.Font = MenuTheme.Fonts.Heading
		pillBtn.Text = buttonLabel
		pillBtn.TextColor3 = MenuTheme.Colors.DarkText
		pillBtn.TextSize = 12
		pillBtn.ZIndex = 8
		pillBtn.Parent = card

		local pc = Instance.new("UICorner")
		pc.CornerRadius = MenuTheme.Corners.Pill
		pc.Parent = pillBtn

		table.insert(
			cleanups,
			MenuTheme.applyButtonFX(pillBtn, {
				baseColor = MenuTheme.Colors.PillGold,
				hoverColor = MenuTheme.Colors.PillGoldHover,
			})
		)

		pillBtn.MouseButton1Click:Connect(function()
			if onClick then
				onClick()
			end
		end)

		return badgeLbl
	end

	local starsBadgeLabel = createTopWidget(
		1,
		"Arsenal",
		"🛡️",
		"★ " .. MenuTheme.formatNumber(148510),
		false,
		"ARSENAL",
		cb.OnOpenArsenal
	)

	local cratesBadgeLabel = createTopWidget(2, "Cajas", "🧰", "◈ 15", true, "CAJAS", cb.OnOpenCrates)

	-- =========================================================================
	-- 2. BANNER TIENDA DE BANDERAS (Degradado morado #6B3FA0 -> #B38DF3)
	-- =========================================================================
	local flagBtn = Instance.new("TextButton")
	flagBtn.Name = "FlagShopBanner"
	flagBtn.LayoutOrder = 2
	flagBtn.Size = UDim2.new(1, 0, 0, 96)
	flagBtn.BackgroundColor3 = MenuTheme.Colors.White
	flagBtn.AutoButtonColor = false
	flagBtn.Text = ""
	flagBtn.ZIndex = 7
	flagBtn.Parent = root

	local fc = Instance.new("UICorner")
	fc.CornerRadius = MenuTheme.Corners.Card
	fc.Parent = flagBtn

	local fg = Instance.new("UIGradient")
	fg.Rotation = 25
	fg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, MenuTheme.Colors.FlagGradStart),
		ColorSequenceKeypoint.new(1, MenuTheme.Colors.FlagGradEnd),
	})
	fg.Parent = flagBtn

	local fs = Instance.new("UIStroke")
	fs.Color = MenuTheme.Colors.FlagStroke
	fs.Thickness = 1.2
	fs.Transparency = 0.25
	fs.Parent = flagBtn

	-- Badge píldora verde #28A959 en la esquina superior derecha: NUEVO
	local newBadge = Instance.new("Frame")
	newBadge.Name = "NewBadge"
	newBadge.AnchorPoint = Vector2.new(1, 0)
	newBadge.Position = UDim2.new(1, -8, 0, 8)
	newBadge.Size = UDim2.fromOffset(58, 20)
	newBadge.BackgroundColor3 = MenuTheme.Colors.BadgeGreen
	newBadge.BorderSizePixel = 0
	newBadge.ZIndex = 9
	newBadge.Parent = flagBtn

	local nbc = Instance.new("UICorner")
	nbc.CornerRadius = MenuTheme.Corners.Pill
	nbc.Parent = newBadge

	local newBadgeText = Instance.new("TextLabel")
	newBadgeText.Size = UDim2.fromScale(1, 1)
	newBadgeText.BackgroundTransparency = 1
	newBadgeText.Font = MenuTheme.Fonts.Heading
	newBadgeText.Text = "NUEVO"
	newBadgeText.TextColor3 = MenuTheme.Colors.White
	newBadgeText.TextSize = 10
	newBadgeText.ZIndex = 10
	newBadgeText.Parent = newBadge

	-- Contenedor cuadrado redondeado a la izquierda con bandera rotativa
	local flagBox = Instance.new("Frame")
	flagBox.Name = "FlagShowcaseBox"
	flagBox.AnchorPoint = Vector2.new(0, 0.5)
	flagBox.Position = UDim2.new(0, 12, 0.5, 0)
	flagBox.Size = UDim2.fromOffset(64, 64)
	flagBox.BackgroundColor3 = Color3.fromHex("#2E1065")
	flagBox.BackgroundTransparency = 0.15
	flagBox.BorderSizePixel = 0
	flagBox.ClipsDescendants = true
	flagBox.ZIndex = 8
	flagBox.Parent = flagBtn

	local fbc = Instance.new("UICorner")
	fbc.CornerRadius = UDim.new(0, 10)
	fbc.Parent = flagBox

	local fbs = Instance.new("UIStroke")
	fbs.Color = MenuTheme.Colors.White
	fbs.Thickness = 1
	fbs.Transparency = 0.4
	fbs.Parent = flagBox

	local flagCanvas = Instance.new("Frame")
	flagCanvas.Name = "FlagGraphic"
	flagCanvas.AnchorPoint = Vector2.new(0.5, 0.5)
	flagCanvas.Position = UDim2.fromScale(0.5, 0.5)
	flagCanvas.Size = UDim2.fromOffset(46, 32)
	flagCanvas.BackgroundColor3 = MenuTheme.Colors.White
	flagCanvas.BorderSizePixel = 0
	flagCanvas.ZIndex = 9
	flagCanvas.Parent = flagBox

	local fgc = Instance.new("UICorner")
	fgc.CornerRadius = UDim.new(0, 4)
	fgc.Parent = flagCanvas

	local stripeTop = Instance.new("Frame")
	stripeTop.Size = UDim2.fromScale(1, 0.34)
	stripeTop.Position = UDim2.fromScale(0, 0)
	stripeTop.BackgroundColor3 = FLAG_DESIGNS[1].top
	stripeTop.BorderSizePixel = 0
	stripeTop.ZIndex = 9
	stripeTop.Parent = flagCanvas

	local stripeMid = Instance.new("Frame")
	stripeMid.Size = UDim2.fromScale(1, 0.33)
	stripeMid.Position = UDim2.fromScale(0, 0.34)
	stripeMid.BackgroundColor3 = FLAG_DESIGNS[1].mid
	stripeMid.BorderSizePixel = 0
	stripeMid.ZIndex = 9
	stripeMid.Parent = flagCanvas

	local stripeBot = Instance.new("Frame")
	stripeBot.Size = UDim2.fromScale(1, 0.33)
	stripeBot.Position = UDim2.fromScale(0, 0.67)
	stripeBot.BackgroundColor3 = FLAG_DESIGNS[1].bot
	stripeBot.BorderSizePixel = 0
	stripeBot.ZIndex = 9
	stripeBot.Parent = flagCanvas

	local flagSymbol = Instance.new("TextLabel")
	flagSymbol.Size = UDim2.fromScale(1, 1)
	flagSymbol.BackgroundTransparency = 1
	flagSymbol.Font = MenuTheme.Fonts.Heading
	flagSymbol.Text = FLAG_DESIGNS[1].symbol
	flagSymbol.TextColor3 = Color3.fromHex("#FACC15")
	flagSymbol.TextStrokeTransparency = 0.2
	flagSymbol.TextSize = 14
	flagSymbol.ZIndex = 10
	flagSymbol.Parent = flagCanvas

	-- Textos a la derecha del banner Tienda de banderas
	local flagTitle = Instance.new("TextLabel")
	flagTitle.Name = "FlagTitle"
	flagTitle.Position = UDim2.fromOffset(86, 16)
	flagTitle.Size = UDim2.new(1, -150, 0, 20)
	flagTitle.BackgroundTransparency = 1
	flagTitle.Font = MenuTheme.Fonts.Heading
	flagTitle.Text = "Tienda de banderas"
	flagTitle.TextColor3 = MenuTheme.Colors.White
	flagTitle.TextSize = 15
	flagTitle.TextXAlignment = Enum.TextXAlignment.Left
	flagTitle.TextTruncate = Enum.TextTruncate.AtEnd
	flagTitle.ZIndex = 8
	flagTitle.Parent = flagBtn

	local flagSub = Instance.new("TextLabel")
	flagSub.Name = "FlagSubtitle"
	flagSub.Position = UDim2.fromOffset(86, 38)
	flagSub.Size = UDim2.new(1, -94, 0, 16)
	flagSub.BackgroundTransparency = 1
	flagSub.Font = MenuTheme.Fonts.Bold
	flagSub.Text = "NUEVAS BANDERAS DIARIAS"
	flagSub.TextColor3 = Color3.fromHex("#F3E8FF")
	flagSub.TextSize = 10
	flagSub.TextXAlignment = Enum.TextXAlignment.Left
	flagSub.TextTruncate = Enum.TextTruncate.AtEnd
	flagSub.ZIndex = 8
	flagSub.Parent = flagBtn

	local flagTimerLbl = Instance.new("TextLabel")
	flagTimerLbl.Name = "FlagTimer"
	flagTimerLbl.Position = UDim2.fromOffset(86, 58)
	flagTimerLbl.Size = UDim2.new(1, -94, 0, 18)
	flagTimerLbl.BackgroundTransparency = 1
	flagTimerLbl.Font = MenuTheme.Fonts.Heading
	flagTimerLbl.Text = "NUEVO EN 21:49:16"
	flagTimerLbl.TextColor3 = MenuTheme.Colors.MonthlyBadge
	flagTimerLbl.TextSize = 11
	flagTimerLbl.TextXAlignment = Enum.TextXAlignment.Left
	flagTimerLbl.ZIndex = 8
	flagTimerLbl.Parent = flagBtn

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(flagBtn, {
			stroke = fs,
			baseStrokeColor = MenuTheme.Colors.FlagStroke,
			hoverStrokeColor = MenuTheme.Colors.White,
		})
	)

	flagBtn.MouseButton1Click:Connect(function()
		if cb.OnOpenFlagShop then
			cb.OnOpenFlagShop()
		end
	end)

	-- =========================================================================
	-- 3. TARJETA GENERAL (Pase Mensual con borde dorado y subtítulo alternante)
	-- =========================================================================
	local generalBtn = Instance.new("TextButton")
	generalBtn.Name = "GeneralPassCard"
	generalBtn.LayoutOrder = 3
	generalBtn.Size = UDim2.new(1, 0, 0, 102)
	generalBtn.BackgroundColor3 = MenuTheme.Colors.GeneralBg
	generalBtn.AutoButtonColor = false
	generalBtn.Text = ""
	generalBtn.ZIndex = 7
	generalBtn.Parent = root

	local gcCard = Instance.new("UICorner")
	gcCard.CornerRadius = MenuTheme.Corners.Card
	gcCard.Parent = generalBtn

	local gsCard = Instance.new("UIStroke")
	gsCard.Color = MenuTheme.Colors.GeneralEdgeGold
	gsCard.Thickness = 1.5
	gsCard.Parent = generalBtn

	local gGrad = Instance.new("UIGradient")
	gGrad.Rotation = 15
	gGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#141E30")),
		ColorSequenceKeypoint.new(0.75, Color3.fromHex("#1E293B")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("#3B2F1E")),
	})
	gGrad.Parent = generalBtn

	-- Badge píldora dorado #FDE8A2 en la esquina superior derecha: MENSUAL
	local monthlyBadge = Instance.new("Frame")
	monthlyBadge.Name = "MonthlyBadge"
	monthlyBadge.AnchorPoint = Vector2.new(1, 0)
	monthlyBadge.Position = UDim2.new(1, -8, 0, 8)
	monthlyBadge.Size = UDim2.fromOffset(68, 20)
	monthlyBadge.BackgroundColor3 = MenuTheme.Colors.MonthlyBadge
	monthlyBadge.BorderSizePixel = 0
	monthlyBadge.ZIndex = 9
	monthlyBadge.Parent = generalBtn

	local mbc = Instance.new("UICorner")
	mbc.CornerRadius = MenuTheme.Corners.Pill
	mbc.Parent = monthlyBadge

	local monthlyText = Instance.new("TextLabel")
	monthlyText.Size = UDim2.fromScale(1, 1)
	monthlyText.BackgroundTransparency = 1
	monthlyText.Font = MenuTheme.Fonts.Heading
	monthlyText.Text = "MENSUAL"
	monthlyText.TextColor3 = MenuTheme.Colors.DarkText
	monthlyText.TextSize = 10
	monthlyText.ZIndex = 10
	monthlyText.Parent = monthlyBadge

	-- Emblema izquierdo de 3 estrellas doradas
	local starsEmblem = Instance.new("Frame")
	starsEmblem.Name = "StarsEmblem"
	starsEmblem.AnchorPoint = Vector2.new(0, 0.5)
	starsEmblem.Position = UDim2.new(0, 12, 0.5, 0)
	starsEmblem.Size = UDim2.fromOffset(64, 64)
	starsEmblem.BackgroundColor3 = Color3.fromHex("#1E293B")
	starsEmblem.BorderSizePixel = 0
	starsEmblem.ZIndex = 8
	starsEmblem.Parent = generalBtn

	local sec = Instance.new("UICorner")
	sec.CornerRadius = UDim.new(0, 10)
	sec.Parent = starsEmblem

	local ses = Instance.new("UIStroke")
	ses.Color = MenuTheme.Colors.PillGold
	ses.Thickness = 1.2
	ses.Parent = starsEmblem

	local starsIcon = Instance.new("TextLabel")
	starsIcon.Size = UDim2.fromScale(1, 1)
	starsIcon.BackgroundTransparency = 1
	starsIcon.Font = MenuTheme.Fonts.Title
	starsIcon.Text = "★★★"
	starsIcon.TextColor3 = MenuTheme.Colors.MonthlyBadge
	starsIcon.TextSize = 18
	starsIcon.ZIndex = 9
	starsIcon.Parent = starsEmblem

	-- Textos de la tarjeta GENERAL
	local genHeader = Instance.new("TextLabel")
	genHeader.Name = "MiniHeader"
	genHeader.Position = UDim2.fromOffset(86, 14)
	genHeader.Size = UDim2.new(1, -162, 0, 14)
	genHeader.BackgroundTransparency = 1
	genHeader.Font = MenuTheme.Fonts.Bold
	genHeader.Text = "CONQUER THE WORLD"
	genHeader.TextColor3 = MenuTheme.Colors.PillGold
	genHeader.TextSize = 9
	genHeader.TextXAlignment = Enum.TextXAlignment.Left
	genHeader.ZIndex = 8
	genHeader.Parent = generalBtn

	local genTitle = Instance.new("TextLabel")
	genTitle.Name = "GeneralTitle"
	genTitle.Position = UDim2.fromOffset(86, 30)
	genTitle.Size = UDim2.new(1, -100, 0, 26)
	genTitle.BackgroundTransparency = 1
	genTitle.Font = MenuTheme.Fonts.Title
	genTitle.Text = "GENERAL"
	genTitle.TextColor3 = MenuTheme.Colors.White
	genTitle.TextSize = 22
	genTitle.TextXAlignment = Enum.TextXAlignment.Left
	genTitle.ZIndex = 8
	genTitle.Parent = generalBtn

	local genPerkLabel = Instance.new("TextLabel")
	genPerkLabel.Name = "AlternatingPerk"
	genPerkLabel.Position = UDim2.fromOffset(86, 60)
	genPerkLabel.Size = UDim2.new(1, -94, 0, 22)
	genPerkLabel.BackgroundTransparency = 1
	genPerkLabel.Font = MenuTheme.Fonts.Medium
	genPerkLabel.Text = GENERAL_SUBTITLES[1]
	genPerkLabel.TextColor3 = MenuTheme.Colors.MonthlyBadge
	genPerkLabel.TextSize = 11
	genPerkLabel.TextXAlignment = Enum.TextXAlignment.Left
	genPerkLabel.TextTruncate = Enum.TextTruncate.AtEnd
	genPerkLabel.ZIndex = 8
	genPerkLabel.Parent = generalBtn

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(generalBtn, {
			stroke = gsCard,
			baseStrokeColor = MenuTheme.Colors.GeneralEdgeGold,
			hoverStrokeColor = MenuTheme.Colors.White,
		})
	)

	generalBtn.MouseButton1Click:Connect(function()
		if cb.OnOpenPass then
			cb.OnOpenPass()
		end
	end)

	local self = setmetatable({
		root = root,
		starsBadgeLabel = starsBadgeLabel,
		cratesBadgeLabel = cratesBadgeLabel,
		cleanups = cleanups,
		running = true,
	}, RightRailShop)

	-- Loop 1: Temporizador en vivo de Tienda de banderas (21:49:16 descontando cada 1s)
	local remainingShopSec = 21 * 3600 + 49 * 60 + 16
	task.spawn(function()
		while self.running and self.root.Parent ~= nil do
			task.wait(1)
			if not self.running then
				break
			end
			remainingShopSec -= 1
			if remainingShopSec < 0 then
				remainingShopSec = 24 * 3600 - 1
			end
			flagTimerLbl.Text = "NUEVO EN " .. MenuTheme.formatHHMMSS(remainingShopSec)
		end
	end)

	-- Loop 2: Rotación de bandera cada 3.5 segundos usando TweenService
	local flagIdx = 1
	task.spawn(function()
		while self.running and self.root.Parent ~= nil do
			task.wait(3.5)
			if not self.running then
				break
			end
			flagIdx = (flagIdx % #FLAG_DESIGNS) + 1
			local nextDesign = FLAG_DESIGNS[flagIdx]

			local shrink = TweenService:Create(
				flagCanvas,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.fromOffset(4, 32), Rotation = 12 }
			)
			shrink:Play()
			shrink.Completed:Wait()
			if not self.running then
				break
			end

			stripeTop.BackgroundColor3 = nextDesign.top
			stripeMid.BackgroundColor3 = nextDesign.mid
			stripeBot.BackgroundColor3 = nextDesign.bot
			flagSymbol.Text = nextDesign.symbol
			flagCanvas.Rotation = -12

			TweenService:Create(
				flagCanvas,
				MenuTheme.Tweens.FlagRotate,
				{ Size = UDim2.fromOffset(46, 32), Rotation = 0 }
			):Play()
		end
	end)

	-- Loop 3: Subtítulo de tarjeta GENERAL con transición fade cada 4 segundos
	local subIdx = 1
	task.spawn(function()
		while self.running and self.root.Parent ~= nil do
			task.wait(4.0)
			if not self.running then
				break
			end
			subIdx = (subIdx % #GENERAL_SUBTITLES) + 1
			local fadeOut = TweenService:Create(genPerkLabel, MenuTheme.Tweens.Fade, { TextTransparency = 1 })
			fadeOut:Play()
			fadeOut.Completed:Wait()
			if not self.running then
				break
			end
			genPerkLabel.Text = GENERAL_SUBTITLES[subIdx]
			TweenService:Create(genPerkLabel, MenuTheme.Tweens.Fade, { TextTransparency = 0 }):Play()
		end
	end)

	return (self :: any) :: RightRailShopInstance
end

function RightRailShop:SetCurrency(stars: number, crateTokens: number)
	self.starsBadgeLabel.Text = "★ " .. MenuTheme.formatNumber(stars)
	self.cratesBadgeLabel.Text = "◈ " .. tostring(math.floor(crateTokens))
end

function RightRailShop:Destroy()
	self.running = false
	for _, fn in ipairs(self.cleanups) do
		fn()
	end
	table.clear(self.cleanups)
	if self.root then
		self.root:Destroy()
	end
end

return RightRailShop
