--!strict
-- MenuTheme.luau
-- Paleta de colores exacta, tipografías, radios, grosores, curvas de animación y micro-interacciones
-- para el menú principal de CONQUER THE WORLD.

local TweenService = game:GetService("TweenService")

local MenuTheme = {}

MenuTheme.Colors = {
	-- Tarjetas principales
	CenterCardBg = Color3.fromHex("#1C253C"),
	SideCardBg = Color3.fromHex("#141E30"),
	CardRowBg = Color3.fromHex("#172035"),
	CardRowHoverBg = Color3.fromHex("#1F2B46"),
	CardStroke = Color3.fromHex("#24324A"),

	-- Título CONQUER THE WORLD (Degradado 90°)
	TitleGradTop = Color3.fromHex("#FFF9F7"),
	TitleGradBottom = Color3.fromHex("#FFD9A8"),
	TitleStroke = Color3.fromHex("#0D1322"),
	GoldDivider = Color3.fromHex("#E8BC77"),

	-- Botón principal PLAY SOLO y ayuda
	PlaySoloBg = Color3.fromHex("#FFB344"),
	PlaySoloHover = Color3.fromHex("#FFC266"),
	DarkText = Color3.fromHex("#111827"),
	HelpBtnBg = Color3.fromHex("#232E47"),

	-- Acentos Cian (PUBLIC MATCHES, JOIN, PARTY)
	CyanAccent = Color3.fromHex("#65C7EF"),
	CyanBorder = Color3.fromHex("#68C8EA"),

	-- Columna Derecha (ARSENAL, CAJAS, Tienda de banderas, GENERAL)
	PillGold = Color3.fromHex("#E8BC77"),
	PillGoldHover = Color3.fromHex("#F3CB8B"),
	BadgeGreen = Color3.fromHex("#28A959"),
	White = Color3.fromHex("#FFFFFF"),
	MutedText = Color3.fromHex("#94A3B8"),
	SubtleText = Color3.fromHex("#CBD5E1"),

	-- Banner Tienda de banderas
	FlagGradStart = Color3.fromHex("#6B3FA0"),
	FlagGradEnd = Color3.fromHex("#B38DF3"),
	FlagStroke = Color3.fromHex("#D8B4FE"),

	-- Tarjeta GENERAL
	GeneralBg = Color3.fromHex("#141E30"),
	GeneralEdgeGold = Color3.fromHex("#FADD91"),
	MonthlyBadge = Color3.fromHex("#FDE8A2"),

	-- Estado
	OnlineGreen = Color3.fromHex("#22C55E"),
	UtilityBtnBg = Color3.fromHex("#111827"),

	-- Modal HOW TO PLAY
	ModalBg = Color3.fromHex("#0F1626"),
	KeybindPillBg = Color3.fromHex("#1E293B"),
	AccentGold = Color3.fromHex("#EAB308"),
	AccentOrange = Color3.fromHex("#F97316"),
	AccentCyan = Color3.fromHex("#38BDF8"),
	AccentPurple = Color3.fromHex("#8B5CF6"),
	AccentRed = Color3.fromHex("#F43F5E"),
}

MenuTheme.Transparency = {
	CenterCard = 0.08,
	SideCard = 0.10,
	UtilityBtn = 0.22,
}

MenuTheme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Regular = Enum.Font.Gotham,
}

MenuTheme.Corners = {
	Card = UDim.new(0, 12),
	InnerCard = UDim.new(0, 10),
	CTA = UDim.new(0, 10),
	Pill = UDim.new(1, 0),
	Badge = UDim.new(0, 6),
}

MenuTheme.Tweens = {
	Hover = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Fade = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	FlagRotate = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

export type ButtonFXOptions = {
	hoverScale: number?,
	pressScale: number?,
	baseColor: Color3?,
	hoverColor: Color3?,
	stroke: UIStroke?,
	baseStrokeColor: Color3?,
	hoverStrokeColor: Color3?,
}

-- Aplica micro-interacciones suaves con TweenService (hover 1.03, press 0.97, brillo/borde)
function MenuTheme.applyButtonFX(button: GuiButton, opts: ButtonFXOptions?): () -> ()
	local options: ButtonFXOptions = opts or {}
	local hoverScale = options.hoverScale or 1.03
	local pressScale = options.pressScale or 0.97

	local scaleObj = button:FindFirstChildOfClass("UIScale")
	if not scaleObj then
		local newScale = Instance.new("UIScale")
		newScale.Scale = 1
		newScale.Parent = button
		scaleObj = newScale
	end
	local uiScale = scaleObj :: UIScale

	local baseColor = options.baseColor or button.BackgroundColor3
	local hoverColor = options.hoverColor or baseColor:Lerp(Color3.new(1, 1, 1), 0.10)
	local stroke = options.stroke
	local baseStrokeColor = if stroke then (options.baseStrokeColor or stroke.Color) else nil
	local hoverStrokeColor = if stroke and baseStrokeColor
		then (options.hoverStrokeColor or baseStrokeColor:Lerp(Color3.new(1, 1, 1), 0.25))
		else nil

	local isHovered = false

	local connEnter = button.MouseEnter:Connect(function()
		isHovered = true
		TweenService:Create(uiScale, MenuTheme.Tweens.Hover, { Scale = hoverScale }):Play()
		if button.BackgroundTransparency < 1 then
			TweenService:Create(button, MenuTheme.Tweens.Hover, { BackgroundColor3 = hoverColor }):Play()
		end
		if stroke and hoverStrokeColor then
			TweenService:Create(stroke, MenuTheme.Tweens.Hover, { Color = hoverStrokeColor }):Play()
		end
	end)

	local connLeave = button.MouseLeave:Connect(function()
		isHovered = false
		TweenService:Create(uiScale, MenuTheme.Tweens.Hover, { Scale = 1 }):Play()
		if button.BackgroundTransparency < 1 then
			TweenService:Create(button, MenuTheme.Tweens.Hover, { BackgroundColor3 = baseColor }):Play()
		end
		if stroke and baseStrokeColor then
			TweenService:Create(stroke, MenuTheme.Tweens.Hover, { Color = baseStrokeColor }):Play()
		end
	end)

	local connDown = button.MouseButton1Down:Connect(function()
		TweenService:Create(uiScale, MenuTheme.Tweens.Press, { Scale = pressScale }):Play()
	end)

	local connUp = button.MouseButton1Up:Connect(function()
		local target = if isHovered then hoverScale else 1
		TweenService:Create(uiScale, MenuTheme.Tweens.Hover, { Scale = target }):Play()
	end)

	return function()
		connEnter:Disconnect()
		connLeave:Disconnect()
		connDown:Disconnect()
		connUp:Disconnect()
	end
end

-- Formatea enteros con separador de miles (p. ej. 148510 -> "148,510")
function MenuTheme.formatNumber(n: number): string
	local sign = if n < 0 then "-" else ""
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local rev = string.reverse(s)
	local withCommas = string.gsub(rev, "(%d%d%d)", "%1,")
	local res = string.reverse(withCommas)
	if string.sub(res, 1, 1) == "," then
		res = string.sub(res, 2)
	end
	return sign .. res
end

-- Formatea segundos como MM:SS (p. ej. 62 -> "1:02")
function MenuTheme.formatMMSS(totalSeconds: number): string
	local sec = math.max(0, math.floor(totalSeconds))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%d:%02d", m, s)
end

-- Formatea segundos como HH:MM:SS (p. ej. 78556 -> "21:49:16")
function MenuTheme.formatHHMMSS(totalSeconds: number): string
	local sec = math.max(0, math.floor(totalSeconds))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

return MenuTheme
