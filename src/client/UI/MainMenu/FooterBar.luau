--!strict
-- FooterBar.luau
-- Pie de página centrado en la parte inferior con créditos, versión y enlace interactivo a Ayuda y Créditos.

local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local FooterBar = {}
FooterBar.__index = FooterBar

export type FooterCallbacks = {
	OnOpenCredits: (() -> ())?,
}

export type FooterBarInstance = {
	root: Frame,
	linkBtn: TextButton,
	cleanupFX: () -> (),
	Destroy: (self: FooterBarInstance) -> (),
}

function FooterBar.new(parent: Instance, callbacks: FooterCallbacks?): FooterBarInstance
	local cb: FooterCallbacks = callbacks or {}

	local root = Instance.new("Frame")
	root.Name = "FooterBar"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 0.99, 0)
	root.Size = UDim2.fromOffset(480, 22)
	root.BackgroundTransparency = 1
	root.ZIndex = 6
	root.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = root

	local creditsLabel = Instance.new("TextLabel")
	creditsLabel.Name = "VersionCredits"
	creditsLabel.LayoutOrder = 1
	creditsLabel.AutomaticSize = Enum.AutomaticSize.X
	creditsLabel.Size = UDim2.fromOffset(0, 18)
	creditsLabel.BackgroundTransparency = 1
	creditsLabel.Font = MenuTheme.Fonts.Regular
	creditsLabel.Text = "CONQUER THE WORLD v2.4 • Tactical Global RTS •"
	creditsLabel.TextColor3 = MenuTheme.Colors.MutedText
	creditsLabel.TextTransparency = 0.25
	creditsLabel.TextSize = 11
	creditsLabel.ZIndex = 7
	creditsLabel.Parent = root

	local linkBtn = Instance.new("TextButton")
	linkBtn.Name = "BtnHelpCredits"
	linkBtn.LayoutOrder = 2
	linkBtn.AutomaticSize = Enum.AutomaticSize.X
	linkBtn.Size = UDim2.fromOffset(0, 18)
	linkBtn.BackgroundTransparency = 1
	linkBtn.AutoButtonColor = false
	linkBtn.Font = MenuTheme.Fonts.Bold
	linkBtn.Text = "Ayuda y Créditos"
	linkBtn.TextColor3 = MenuTheme.Colors.CyanAccent
	linkBtn.TextSize = 11
	linkBtn.ZIndex = 7
	linkBtn.Parent = root

	local cleanupFX = MenuTheme.applyButtonFX(linkBtn, {
		hoverScale = 1.05,
		pressScale = 0.96,
	})

	linkBtn.MouseButton1Click:Connect(function()
		if cb.OnOpenCredits then
			cb.OnOpenCredits()
		end
	end)

	local self = setmetatable({
		root = root,
		linkBtn = linkBtn,
		cleanupFX = cleanupFX,
	}, FooterBar)

	return (self :: any) :: FooterBarInstance
end

function FooterBar:Destroy()
	if self.cleanupFX then
		self.cleanupFX()
	end
	if self.root then
		self.root:Destroy()
	end
end

return FooterBar
