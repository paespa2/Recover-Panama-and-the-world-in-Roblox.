--!strict
-- TopUtilityBar.luau
-- Botones circulares superiores izquierdos (Música, Ayuda ?, Configuración ⚙)
-- desplazados a la derecha del TopBar nativo usando GuiService:GetGuiInset().

local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local TopUtilityBar = {}
TopUtilityBar.__index = TopUtilityBar

export type TopUtilityCallbacks = {
	OnToggleMusic: ((isMuted: boolean) -> ())?,
	OnOpenHelp: (() -> ())?,
	OnOpenSettings: (() -> ())?,
}

export type TopUtilityBarInstance = {
	root: Frame,
	isMuted: boolean,
	musicBtn: TextButton,
	helpBtn: TextButton,
	settingsBtn: TextButton,
	cleanups: { () -> () },
	ToggleMusic: (self: TopUtilityBarInstance) -> (),
	Destroy: (self: TopUtilityBarInstance) -> (),
}

local function createCircleButton(parent: Instance, name: string, symbol: string, order: number): (TextButton, UIStroke)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.LayoutOrder = order
	btn.Size = UDim2.fromOffset(40, 40)
	btn.BackgroundColor3 = MenuTheme.Colors.UtilityBtnBg
	btn.BackgroundTransparency = MenuTheme.Transparency.UtilityBtn
	btn.AutoButtonColor = false
	btn.Font = MenuTheme.Fonts.Heading
	btn.Text = symbol
	btn.TextColor3 = MenuTheme.Colors.White
	btn.TextSize = 18
	btn.ZIndex = 10
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = MenuTheme.Corners.Pill
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = MenuTheme.Colors.CardStroke
	stroke.Thickness = 1
	stroke.Parent = btn

	return btn, stroke
end

function TopUtilityBar.new(parent: Instance, callbacks: TopUtilityCallbacks?): TopUtilityBarInstance
	local cb: TopUtilityCallbacks = callbacks or {}
	local topLeftInset, _ = GuiService:GetGuiInset()
	-- Desplazar a la derecha de los iconos nativos de Roblox TopBar (Unibar + Mic)
	local leftOffset = math.max(255, topLeftInset.X + 185)
	local topOffset = 14

	local root = Instance.new("Frame")
	root.Name = "TopUtilityBar"
	root.Position = UDim2.fromOffset(leftOffset, topOffset)
	root.Size = UDim2.fromOffset(140, 44)
	root.BackgroundTransparency = 1
	root.ZIndex = 10
	root.Parent = parent

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = root

	local musicBtn, musicStroke = createCircleButton(root, "BtnMusic", "♪", 1)
	local helpBtn, helpStroke = createCircleButton(root, "BtnHelp", "?", 2)
	local settingsBtn, settingsStroke = createCircleButton(root, "BtnSettings", "⚙", 3)

	local cleanups: { () -> () } = {}
	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(musicBtn, {
			stroke = musicStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanAccent,
		})
	)
	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(helpBtn, {
			stroke = helpStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanAccent,
		})
	)
	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(settingsBtn, {
			stroke = settingsStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanAccent,
		})
	)

	local self = setmetatable({
		root = root,
		isMuted = false,
		musicBtn = musicBtn,
		helpBtn = helpBtn,
		settingsBtn = settingsBtn,
		cleanups = cleanups,
		onToggleMusic = cb.OnToggleMusic,
		musicStroke = musicStroke,
	}, TopUtilityBar)

	musicBtn.MouseButton1Click:Connect(function()
		self:ToggleMusic()
	end)

	helpBtn.MouseButton1Click:Connect(function()
		if cb.OnOpenHelp then
			cb.OnOpenHelp()
		end
	end)

	settingsBtn.MouseButton1Click:Connect(function()
		if cb.OnOpenSettings then
			cb.OnOpenSettings()
		end
	end)

	return (self :: any) :: TopUtilityBarInstance
end

function TopUtilityBar:ToggleMusic()
	self.isMuted = not self.isMuted
	if self.isMuted then
		self.musicBtn.Text = "🔇"
		self.musicBtn.TextColor3 = MenuTheme.Colors.MutedText
		self.musicStroke.Color = Color3.fromHex("#EF4444")
	else
		self.musicBtn.Text = "♪"
		self.musicBtn.TextColor3 = MenuTheme.Colors.White
		self.musicStroke.Color = MenuTheme.Colors.CardStroke
	end
	for _, desc in ipairs(SoundService:GetDescendants()) do
		if desc:IsA("Sound") then
			desc.Playing = not self.isMuted
		end
	end
	if self.onToggleMusic then
		self.onToggleMusic(self.isMuted)
	end
end

function TopUtilityBar:Destroy()
	for _, fn in ipairs(self.cleanups) do
		fn()
	end
	table.clear(self.cleanups)
	if self.root then
		self.root:Destroy()
	end
end

return TopUtilityBar
