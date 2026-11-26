--!strict
-- BackgroundMapView.luau
-- Fondo táctico animado (ZIndex = 0) con territorios coloreados, fronteras costeras,
-- íconos de puertos/ciudades, unidades navales en movimiento y viñeta oscura radial.

local RunService = game:GetService("RunService")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local BackgroundMapView = {}
BackgroundMapView.__index = BackgroundMapView

export type NavalUnit = {
	frame: Frame,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	speed: number,
	phase: number,
}

export type BackgroundMapViewInstance = {
	root: Frame,
	canvas: Frame,
	units: { NavalUnit },
	conn: RBXScriptConnection?,
	Destroy: (self: BackgroundMapViewInstance) -> (),
}

type TerritoryDef = {
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	border: Color3,
	city: string?,
	hasPort: boolean?,
}

local TERRITORIES: { TerritoryDef } = {
	{
		name = "NORTH AMERICA",
		x = 0.08,
		y = 0.16,
		w = 0.22,
		h = 0.26,
		color = Color3.fromHex("#1E4E79"),
		border = Color3.fromHex("#65C7EF"),
		city = "Nueva York",
		hasPort = true,
	},
	{
		name = "CENTRAL AMERICA & PANAMA",
		x = 0.18,
		y = 0.43,
		w = 0.10,
		h = 0.10,
		color = Color3.fromHex("#1E6B52"),
		border = Color3.fromHex("#4ADE80"),
		city = "Panamá",
		hasPort = true,
	},
	{
		name = "SOUTH AMERICA",
		x = 0.23,
		y = 0.55,
		w = 0.15,
		h = 0.30,
		color = Color3.fromHex("#25634B"),
		border = Color3.fromHex("#34D399"),
		city = "São Paulo",
		hasPort = true,
	},
	{
		name = "WESTERN EUROPE",
		x = 0.44,
		y = 0.18,
		w = 0.13,
		h = 0.18,
		color = Color3.fromHex("#5B3486"),
		border = Color3.fromHex("#C084FC"),
		city = "Londres",
		hasPort = true,
	},
	{
		name = "NORTH AFRICA",
		x = 0.43,
		y = 0.39,
		w = 0.16,
		h = 0.20,
		color = Color3.fromHex("#7C4A1E"),
		border = Color3.fromHex("#FBBF24"),
		city = "El Cairo",
		hasPort = true,
	},
	{
		name = "SOUTH AFRICA",
		x = 0.48,
		y = 0.61,
		w = 0.12,
		h = 0.22,
		color = Color3.fromHex("#6E3232"),
		border = Color3.fromHex("#F87171"),
		city = "Ciudad del Cabo",
		hasPort = true,
	},
	{
		name = "EURASIA",
		x = 0.58,
		y = 0.14,
		w = 0.26,
		h = 0.24,
		color = Color3.fromHex("#7A283B"),
		border = Color3.fromHex("#FB7185"),
		city = "Moscú",
		hasPort = false,
	},
	{
		name = "EAST ASIA",
		x = 0.68,
		y = 0.38,
		w = 0.18,
		h = 0.22,
		color = Color3.fromHex("#78571C"),
		border = Color3.fromHex("#FACC15"),
		city = "Tokio",
		hasPort = true,
	},
	{
		name = "OCEANIA",
		x = 0.74,
		y = 0.65,
		w = 0.15,
		h = 0.18,
		color = Color3.fromHex("#1D5B63"),
		border = Color3.fromHex("#2DD4BF"),
		city = "Sídney",
		hasPort = true,
	},
}

local NAVAL_ROUTES = {
	{ x0 = 0.29, y0 = 0.34, x1 = 0.43, y1 = 0.28, speed = 0.045, phase = 0.0 },
	{ x0 = 0.27, y0 = 0.48, x1 = 0.42, y1 = 0.46, speed = 0.038, phase = 0.35 },
	{ x0 = 0.37, y0 = 0.68, x1 = 0.47, y1 = 0.70, speed = 0.042, phase = 0.65 },
	{ x0 = 0.60, y0 = 0.52, x1 = 0.73, y1 = 0.67, speed = 0.036, phase = 0.20 },
	{ x0 = 0.84, y0 = 0.46, x1 = 0.94, y1 = 0.38, speed = 0.050, phase = 0.75 },
}

function BackgroundMapView.new(parent: Instance): BackgroundMapViewInstance
	local root = Instance.new("Frame")
	root.Name = "BackgroundMapView"
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromScale(0, 0)
	root.BackgroundColor3 = Color3.fromHex("#091324")
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.ZIndex = 0
	root.Parent = parent

	-- Lienzo táctico más grande que la pantalla para paneo continuo suave
	local canvas = Instance.new("Frame")
	canvas.Name = "TacticalMapCanvas"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Size = UDim2.fromScale(1.16, 1.16)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.BackgroundColor3 = Color3.fromHex("#0B172A")
	canvas.BorderSizePixel = 0
	canvas.ZIndex = 0
	canvas.Parent = root

	-- Líneas de cuadrícula táctica (latitud / longitud)
	for i = 1, 11 do
		local vLine = Instance.new("Frame")
		vLine.Name = "LonLine_" .. tostring(i)
		vLine.Size = UDim2.new(0, 1, 1, 0)
		vLine.Position = UDim2.fromScale(i / 12, 0)
		vLine.BackgroundColor3 = Color3.fromHex("#1E3A5F")
		vLine.BackgroundTransparency = 0.78
		vLine.BorderSizePixel = 0
		vLine.ZIndex = 0
		vLine.Parent = canvas
	end
	for j = 1, 7 do
		local hLine = Instance.new("Frame")
		hLine.Name = "LatLine_" .. tostring(j)
		hLine.Size = UDim2.new(1, 0, 0, 1)
		hLine.Position = UDim2.fromScale(0, j / 8)
		hLine.BackgroundColor3 = Color3.fromHex("#1E3A5F")
		hLine.BackgroundTransparency = 0.78
		hLine.BorderSizePixel = 0
		hLine.ZIndex = 0
		hLine.Parent = canvas
	end

	-- Renderizar bloques continentales tácticos con fronteras iluminadas, ciudades y puertos
	for idx, t in ipairs(TERRITORIES) do
		local region = Instance.new("Frame")
		region.Name = "Territory_" .. tostring(idx)
		region.Position = UDim2.fromScale(t.x, t.y)
		region.Size = UDim2.fromScale(t.w, t.h)
		region.BackgroundColor3 = t.color
		region.BackgroundTransparency = 0.28
		region.BorderSizePixel = 0
		region.ZIndex = 0
		region.Parent = canvas

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = region

		local stroke = Instance.new("UIStroke")
		stroke.Color = t.border
		stroke.Thickness = 1.6
		stroke.Transparency = 0.25
		stroke.Parent = region

		local lbl = Instance.new("TextLabel")
		lbl.Name = "RegionCode"
		lbl.AnchorPoint = Vector2.new(0.5, 0.5)
		lbl.Position = UDim2.fromScale(0.5, 0.42)
		lbl.Size = UDim2.fromScale(0.9, 0.24)
		lbl.BackgroundTransparency = 1
		lbl.Font = MenuTheme.Fonts.Bold
		lbl.Text = t.name
		lbl.TextColor3 = t.border
		lbl.TextTransparency = 0.35
		lbl.TextSize = 11
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.ZIndex = 0
		lbl.Parent = region

		if t.city then
			local cityPin = Instance.new("TextLabel")
			cityPin.Name = "CityPin"
			cityPin.AnchorPoint = Vector2.new(0.5, 0.5)
			cityPin.Position = UDim2.fromScale(0.48, 0.68)
			cityPin.Size = UDim2.fromOffset(110, 18)
			cityPin.BackgroundTransparency = 1
			cityPin.Font = MenuTheme.Fonts.Medium
			cityPin.Text = "🏙️ " .. t.city
			cityPin.TextColor3 = Color3.fromHex("#E2E8F0")
			cityPin.TextTransparency = 0.25
			cityPin.TextSize = 10
			cityPin.ZIndex = 0
			cityPin.Parent = region
		end

		if t.hasPort then
			local portBadge = Instance.new("TextLabel")
			portBadge.Name = "PortBadge"
			portBadge.AnchorPoint = Vector2.new(1, 1)
			portBadge.Position = UDim2.new(1, -6, 1, -4)
			portBadge.Size = UDim2.fromOffset(20, 20)
			portBadge.BackgroundColor3 = Color3.fromHex("#0F2942")
			portBadge.BackgroundTransparency = 0.2
			portBadge.Font = MenuTheme.Fonts.Bold
			portBadge.Text = "⚓"
			portBadge.TextColor3 = MenuTheme.Colors.CyanAccent
			portBadge.TextSize = 11
			portBadge.ZIndex = 0
			portBadge.Parent = region

			local pc = Instance.new("UICorner")
			pc.CornerRadius = UDim.new(1, 0)
			pc.Parent = portBadge
		end
	end

	-- Unidades navales desplazándose entre puertos
	local units: { NavalUnit } = {}
	for idx, route in ipairs(NAVAL_ROUTES) do
		local ship = Instance.new("Frame")
		ship.Name = "NavalUnit_" .. tostring(idx)
		ship.AnchorPoint = Vector2.new(0.5, 0.5)
		ship.Size = UDim2.fromOffset(22, 12)
		ship.Position = UDim2.fromScale(route.x0, route.y0)
		ship.BackgroundColor3 = Color3.fromHex("#132F4C")
		ship.BackgroundTransparency = 0.15
		ship.BorderSizePixel = 0
		ship.ZIndex = 0
		ship.Parent = canvas

		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(1, 0)
		sc.Parent = ship

		local ss = Instance.new("UIStroke")
		ss.Color = MenuTheme.Colors.CyanAccent
		ss.Thickness = 1
		ss.Transparency = 0.25
		ss.Parent = ship

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.fromScale(1, 1)
		icon.BackgroundTransparency = 1
		icon.Font = MenuTheme.Fonts.Bold
		icon.Text = "🚢"
		icon.TextSize = 9
		icon.TextColor3 = MenuTheme.Colors.White
		icon.ZIndex = 0
		icon.Parent = ship

		table.insert(units, {
			frame = ship,
			x0 = route.x0,
			y0 = route.y0,
			x1 = route.x1,
			y1 = route.y1,
			speed = route.speed,
			phase = route.phase,
		})
	end

	-- Viñeta oscura superior/inferior para garantizar contraste perfecto con la UI
	local vignetteTop = Instance.new("Frame")
	vignetteTop.Name = "VignetteOverlay"
	vignetteTop.Size = UDim2.fromScale(1, 1)
	vignetteTop.BackgroundColor3 = Color3.fromHex("#050914")
	vignetteTop.BackgroundTransparency = 0.22
	vignetteTop.BorderSizePixel = 0
	vignetteTop.ZIndex = 0
	vignetteTop.Parent = root

	local vGrad = Instance.new("UIGradient")
	vGrad.Rotation = 90
	vGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.35, 0.42),
		NumberSequenceKeypoint.new(0.70, 0.38),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	vGrad.Parent = vignetteTop

	local t = 0
	local conn = RunService.RenderStepped:Connect(function(dt: number)
		t += dt
		-- Movimiento orbital suave del mapa táctico sin saltos
		local offsetX = math.sin(t * 0.14) * 0.045
		local offsetY = math.cos(t * 0.11) * 0.035
		canvas.Position = UDim2.fromScale(0.5 + offsetX, 0.5 + offsetY)

		-- Actualizar unidades navales a lo largo de las rutas marítimas
		for _, u in ipairs(units) do
			local alpha = (math.sin((t * u.speed + u.phase) * math.pi * 2) + 1) * 0.5
			local ux = u.x0 + (u.x1 - u.x0) * alpha
			local uy = u.y0 + (u.y1 - u.y0) * alpha
			u.frame.Position = UDim2.fromScale(ux, uy)
		end
	end)

	local self = setmetatable({
		root = root,
		canvas = canvas,
		units = units,
		conn = conn,
	}, BackgroundMapView)

	return (self :: any) :: BackgroundMapViewInstance
end

function BackgroundMapView:Destroy()
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if self.root then
		self.root:Destroy()
	end
end

return BackgroundMapView
