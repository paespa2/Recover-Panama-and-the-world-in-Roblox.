--!strict
-- BrandHeader.luau
-- Cabecera central: emblema cuadrado redondeado (48x48), título CONQUER THE WORLD
-- con UIGradient vertical (#FFF9F7 -> #FFD9A8) y subtítulo CONQUER THE REAL WORLD
-- flanqueado por líneas doradas con degradado de transparencia.

local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local BrandHeader = {}
BrandHeader.__index = BrandHeader

export type BrandHeaderInstance = {
	root: Frame,
	Destroy: (self: BrandHeaderInstance) -> (),
}

local function createFadeLine(parent: Instance, name: string, invertFade: boolean): Frame
	local line = Instance.new("Frame")
	line.Name = name
	line.Size = UDim2.fromOffset(92, 2)
	line.BackgroundColor3 = MenuTheme.Colors.GoldDivider
	line.BorderSizePixel = 0
	line.ZIndex = 6
	line.Parent = parent

	local grad = Instance.new("UIGradient")
	if invertFade then
		-- Transparente a la izquierda -> opaco a la derecha
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.85, 0.15),
			NumberSequenceKeypoint.new(1, 0),
		})
	else
		-- Opaco a la izquierda -> transparente a la derecha
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.15, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	grad.Parent = line
	return line
end

function BrandHeader.new(parent: Instance): BrandHeaderInstance
	local root = Instance.new("Frame")
	root.Name = "BrandHeader"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0.08, 0)
	root.Size = UDim2.fromOffset(620, 134)
	root.BackgroundTransparency = 1
	root.ZIndex = 5
	root.Parent = parent

	-- Emblema cuadrado redondeado (48x48 px) centrado arriba del título
	local emblem = Instance.new("Frame")
	emblem.Name = "Emblem"
	emblem.AnchorPoint = Vector2.new(0.5, 0)
	emblem.Position = UDim2.new(0.5, 0, 0, 0)
	emblem.Size = UDim2.fromOffset(48, 48)
	emblem.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	emblem.BackgroundTransparency = 0.05
	emblem.BorderSizePixel = 0
	emblem.ZIndex = 6
	emblem.Parent = root

	local emblemCorner = Instance.new("UICorner")
	emblemCorner.CornerRadius = UDim.new(0, 12)
	emblemCorner.Parent = emblem

	local emblemStroke = Instance.new("UIStroke")
	emblemStroke.Color = MenuTheme.Colors.PillGold
	emblemStroke.Thickness = 1.6
	emblemStroke.Parent = emblem

	local emblemGrad = Instance.new("UIGradient")
	emblemGrad.Rotation = 45
	emblemGrad.Color = ColorSequence.new(Color3.fromHex("#1E293B"), Color3.fromHex("#334155"))
	emblemGrad.Parent = emblem

	local emblemIcon = Instance.new("TextLabel")
	emblemIcon.Name = "GlobeCrown"
	emblemIcon.Size = UDim2.fromScale(1, 1)
	emblemIcon.BackgroundTransparency = 1
	emblemIcon.Font = MenuTheme.Fonts.Title
	emblemIcon.Text = "🌍"
	emblemIcon.TextSize = 26
	emblemIcon.TextColor3 = MenuTheme.Colors.TitleGradBottom
	emblemIcon.ZIndex = 7
	emblemIcon.Parent = emblem

	-- Sombra del título principal
	local titleShadow = Instance.new("TextLabel")
	titleShadow.Name = "TitleShadow"
	titleShadow.AnchorPoint = Vector2.new(0.5, 0)
	titleShadow.Position = UDim2.new(0.5, 0, 0, 56)
	titleShadow.Size = UDim2.new(1, 0, 0, 46)
	titleShadow.BackgroundTransparency = 1
	titleShadow.Font = MenuTheme.Fonts.Title
	titleShadow.Text = "CONQUER THE WORLD"
	titleShadow.TextColor3 = Color3.fromHex("#050811")
	titleShadow.TextTransparency = 0.35
	titleShadow.TextSize = 40
	titleShadow.TextScaled = true
	titleShadow.ZIndex = 5
	titleShadow.Parent = root

	local shadowConstraint = Instance.new("UITextSizeConstraint")
	shadowConstraint.MaxTextSize = 40
	shadowConstraint.MinTextSize = 20
	shadowConstraint.Parent = titleShadow

	-- Título principal: CONQUER THE WORLD
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 0, 53)
	titleLabel.Size = UDim2.new(1, 0, 0, 46)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = MenuTheme.Fonts.Title
	titleLabel.Text = "CONQUER THE WORLD"
	titleLabel.TextColor3 = MenuTheme.Colors.White
	titleLabel.TextSize = 40
	titleLabel.TextScaled = true
	titleLabel.ZIndex = 6
	titleLabel.Parent = root

	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MaxTextSize = 40
	titleConstraint.MinTextSize = 20
	titleConstraint.Parent = titleLabel

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = MenuTheme.Colors.TitleStroke
	titleStroke.Thickness = 1.8
	titleStroke.Transparency = 0.2
	titleStroke.Parent = titleLabel

	local titleGrad = Instance.new("UIGradient")
	titleGrad.Rotation = 90
	titleGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, MenuTheme.Colors.TitleGradTop),
		ColorSequenceKeypoint.new(1, MenuTheme.Colors.TitleGradBottom),
	})
	titleGrad.Parent = titleLabel

	-- Fila del subtítulo con líneas divisorias doradas
	local subRow = Instance.new("Frame")
	subRow.Name = "SubtitleRow"
	subRow.AnchorPoint = Vector2.new(0.5, 0)
	subRow.Position = UDim2.new(0.5, 0, 0, 104)
	subRow.Size = UDim2.fromOffset(480, 22)
	subRow.BackgroundTransparency = 1
	subRow.ZIndex = 6
	subRow.Parent = root

	local subLayout = Instance.new("UIListLayout")
	subLayout.FillDirection = Enum.FillDirection.Horizontal
	subLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	subLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	subLayout.SortOrder = Enum.SortOrder.LayoutOrder
	subLayout.Padding = UDim.new(0, 12)
	subLayout.Parent = subRow

	local leftLine = createFadeLine(subRow, "LeftDivider", true)
	leftLine.LayoutOrder = 1

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubtitleLabel"
	subLabel.LayoutOrder = 2
	subLabel.AutomaticSize = Enum.AutomaticSize.X
	subLabel.Size = UDim2.fromOffset(220, 20)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = MenuTheme.Fonts.Bold
	subLabel.Text = "C O N Q U E R   T H E   R E A L   W O R L D"
	subLabel.TextColor3 = MenuTheme.Colors.TitleGradBottom
	subLabel.TextSize = 11
	subLabel.ZIndex = 6
	subLabel.Parent = subRow

	local rightLine = createFadeLine(subRow, "RightDivider", false)
	rightLine.LayoutOrder = 3

	local self = setmetatable({
		root = root,
	}, BrandHeader)

	return (self :: any) :: BrandHeaderInstance
end

function BrandHeader:Destroy()
	if self.root then
		self.root:Destroy()
	end
end

return BrandHeader
