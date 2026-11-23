--!strict
-- CountryballUI.lua
-- Generador de avatares Countryballs en estilo 2D Pixel Art (sin depender de imágenes externas que puedan fallar)
-- Dibuja la bandera pixelada, el borde negro estilo Polandball y los ojos expresivos (determinado, gafas USA, etc.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local CountryballUI = {}

function CountryballUI.CreateCountryball(parent: GuiObject, factionId: string, sizePx: number): Frame
	local faction = GameConfig.FACTIONS[factionId] or GameConfig.FACTIONS.NEUTRAL

	local container = Instance.new("Frame")
	container.Name = "Countryball_" .. factionId
	container.Size = UDim2.fromOffset(sizePx, sizePx)
	container.BackgroundColor3 = faction.primaryColor
	container.BorderSizePixel = 2
	container.BorderColor3 = Color3.fromRGB(20, 20, 25)
	container.ClipsDescendants = true
	container.Parent = parent

	-- Esquinas ligeramente pixeladas (no círculo perfecto sino octágono/bloque pixel)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.max(4, math.floor(sizePx * 0.25)))
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(15, 15, 20)
	stroke.Thickness = 2
	stroke.Parent = container

	-- Diseño de bandera específico para Panamá (4 cuadrantes: Blanco, Rojo, Azul, Blanco)
	if factionId == "PANAMA" then
		container.BackgroundColor3 = Color3.fromRGB(245, 247, 250)

		local bottomLeft = Instance.new("Frame")
		bottomLeft.Size = UDim2.fromScale(0.5, 0.5)
		bottomLeft.Position = UDim2.fromScale(0, 0.5)
		bottomLeft.BackgroundColor3 = Color3.fromRGB(0, 103, 198)
		bottomLeft.BorderSizePixel = 0
		bottomLeft.Parent = container

		local topRight = Instance.new("Frame")
		topRight.Size = UDim2.fromScale(0.5, 0.5)
		topRight.Position = UDim2.fromScale(0.5, 0)
		topRight.BackgroundColor3 = Color3.fromRGB(210, 16, 52)
		topRight.BorderSizePixel = 0
		topRight.Parent = container
	else
		-- Franja inferior secundaria en estilo pixel
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.fromScale(1, 0.42)
		stripe.Position = UDim2.fromScale(0, 0.58)
		stripe.BackgroundColor3 = faction.secondaryColor
		stripe.BorderSizePixel = 0
		stripe.Parent = container
	end

	-- Ojos pixelados blancos con borde negro característicos de Countryballs
	local leftEye = Instance.new("Frame")
	leftEye.Name = "LeftEye"
	leftEye.Size = UDim2.fromScale(0.24, 0.26)
	leftEye.Position = UDim2.fromScale(0.18, 0.28)
	leftEye.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	leftEye.BorderSizePixel = 1
	leftEye.BorderColor3 = Color3.fromRGB(10, 10, 10)
	leftEye.ZIndex = 3
	leftEye.Parent = container

	local rightEye = Instance.new("Frame")
	rightEye.Name = "RightEye"
	rightEye.Size = UDim2.fromScale(0.24, 0.26)
	rightEye.Position = UDim2.fromScale(0.56, 0.28)
	rightEye.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	rightEye.BorderSizePixel = 1
	rightEye.BorderColor3 = Color3.fromRGB(10, 10, 10)
	rightEye.ZIndex = 3
	rightEye.Parent = container

	-- Expresión según el estilo de cada país
	if faction.eyeStyle == "sunglasses" then
		leftEye.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		rightEye.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		local bridge = Instance.new("Frame")
		bridge.Size = UDim2.fromScale(0.82, 0.08)
		bridge.Position = UDim2.fromScale(0.09, 0.30)
		bridge.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
		bridge.BorderSizePixel = 0
		bridge.ZIndex = 4
		bridge.Parent = container
	elseif faction.eyeStyle == "angry" or faction.eyeStyle == "determined" then
		local browL = Instance.new("Frame")
		browL.Size = UDim2.fromScale(0.26, 0.08)
		browL.Position = UDim2.fromScale(0.17, 0.24)
		browL.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		browL.BorderSizePixel = 0
		browL.Rotation = 12
		browL.ZIndex = 4
		browL.Parent = container

		local browR = Instance.new("Frame")
		browR.Size = UDim2.fromScale(0.26, 0.08)
		browR.Position = UDim2.fromScale(0.55, 0.24)
		browR.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		browR.BorderSizePixel = 0
		browR.Rotation = -12
		browR.ZIndex = 4
		browR.Parent = container
	end

	return container
end

return CountryballUI
