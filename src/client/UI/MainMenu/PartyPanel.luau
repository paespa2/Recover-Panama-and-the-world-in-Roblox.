--!strict
-- PartyPanel.luau
-- Tarjeta izquierda de grupo (PARTY) e invitación de amigos mediante SocialService:PromptGameInvite.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local PartyPanel = {}
PartyPanel.__index = PartyPanel

export type PartyPanelCallbacks = {
	OnInviteParty: (() -> ())?,
}

export type PartyPanelInstance = {
	root: Frame,
	inviteBtn: TextButton,
	cleanupFX: () -> (),
	Destroy: (self: PartyPanelInstance) -> (),
}

function PartyPanel.new(parent: Instance, callbacks: PartyPanelCallbacks?): PartyPanelInstance
	local cb: PartyPanelCallbacks = callbacks or {}

	local root = Instance.new("Frame")
	root.Name = "PartyPanel"
	root.AnchorPoint = Vector2.new(0, 0.5)
	root.Position = UDim2.new(0.015, 0, 0.50, 0)
	root.Size = UDim2.fromOffset(280, 174)
	root.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	root.BackgroundTransparency = MenuTheme.Transparency.SideCard
	root.BorderSizePixel = 0
	root.ZIndex = 6
	root.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = MenuTheme.Corners.Card
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = MenuTheme.Colors.CardStroke
	stroke.Thickness = 1
	stroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = root

	-- Encabezado: ícono de grupo cian (#65C7EF) + texto PARTY en mayúsculas bold
	local headerRow = Instance.new("Frame")
	headerRow.Name = "HeaderRow"
	headerRow.Size = UDim2.new(1, 0, 0, 24)
	headerRow.BackgroundTransparency = 1
	headerRow.ZIndex = 7
	headerRow.Parent = root

	local groupIcon = Instance.new("TextLabel")
	groupIcon.Name = "GroupIcon"
	groupIcon.Size = UDim2.fromOffset(24, 24)
	groupIcon.Position = UDim2.fromOffset(0, 0)
	groupIcon.BackgroundTransparency = 1
	groupIcon.Font = MenuTheme.Fonts.Heading
	groupIcon.Text = "👥"
	groupIcon.TextColor3 = MenuTheme.Colors.CyanAccent
	groupIcon.TextSize = 18
	groupIcon.ZIndex = 7
	groupIcon.Parent = headerRow

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Position = UDim2.fromOffset(28, 0)
	headerTitle.Size = UDim2.new(1, -28, 1, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Font = MenuTheme.Fonts.Heading
	headerTitle.Text = "PARTY"
	headerTitle.TextColor3 = MenuTheme.Colors.White
	headerTitle.TextSize = 16
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.ZIndex = 7
	headerTitle.Parent = headerRow

	-- Texto descriptivo en español
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Position = UDim2.fromOffset(0, 34)
	descLabel.Size = UDim2.new(1, 0, 0, 62)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = MenuTheme.Fonts.Regular
	descLabel.Text = "Juega partidas públicas con amigos: en un juego de equipo estarás en el mismo equipo."
	descLabel.TextColor3 = MenuTheme.Colors.SubtleText
	descLabel.TextSize = 12
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.ZIndex = 7
	descLabel.Parent = root

	-- Botón inferior ancho INVITE con borde sutil #24324A
	local inviteBtn = Instance.new("TextButton")
	inviteBtn.Name = "BtnInvite"
	inviteBtn.AnchorPoint = Vector2.new(0, 1)
	inviteBtn.Position = UDim2.new(0, 0, 1, 0)
	inviteBtn.Size = UDim2.new(1, 0, 0, 38)
	inviteBtn.BackgroundColor3 = MenuTheme.Colors.CardRowBg
	inviteBtn.AutoButtonColor = false
	inviteBtn.Font = MenuTheme.Fonts.Heading
	inviteBtn.Text = "👥  INVITE"
	inviteBtn.TextColor3 = MenuTheme.Colors.CyanAccent
	inviteBtn.TextSize = 13
	inviteBtn.ZIndex = 7
	inviteBtn.Parent = root

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = MenuTheme.Corners.InnerCard
	btnCorner.Parent = inviteBtn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = MenuTheme.Colors.CardStroke
	btnStroke.Thickness = 1
	btnStroke.Parent = inviteBtn

	local cleanupFX = MenuTheme.applyButtonFX(inviteBtn, {
		baseColor = MenuTheme.Colors.CardRowBg,
		hoverColor = MenuTheme.Colors.CardRowHoverBg,
		stroke = btnStroke,
		baseStrokeColor = MenuTheme.Colors.CardStroke,
		hoverStrokeColor = MenuTheme.Colors.CyanBorder,
	})

	inviteBtn.MouseButton1Click:Connect(function()
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			pcall(function()
				SocialService:PromptGameInvite(localPlayer)
			end)
		end
		if cb.OnInviteParty then
			cb.OnInviteParty()
		end
	end)

	local self = setmetatable({
		root = root,
		inviteBtn = inviteBtn,
		cleanupFX = cleanupFX,
	}, PartyPanel)

	return (self :: any) :: PartyPanelInstance
end

function PartyPanel:Destroy()
	if self.cleanupFX then
		self.cleanupFX()
	end
	if self.root then
		self.root:Destroy()
	end
end

return PartyPanel
