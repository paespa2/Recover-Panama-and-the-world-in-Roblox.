--!strict
-- OpenFront.io: HubScreen
-- Parity with OpenFront Main Menu, Solo Modal, and Map Selection

local MapRegistry = require(script.Parent.Parent.shared.MapRegistry)

local HubScreen = {}
HubScreen.__index = HubScreen

export type HubScreenInstance = {
	gui: ScreenGui,
	hubFrame: Frame,
	soloModal: Frame,
	selectedMapId: string,

	Init: (self: HubScreenInstance, parentGui: ScreenGui, onPlayClicked: (mapId: string) -> ()) -> (),
	SetVisible: (self: HubScreenInstance, visible: boolean) -> (),
}

function HubScreen.new(): HubScreenInstance
	local self = setmetatable({}, HubScreen)
	self.selectedMapId = "world"
	return (self :: any) :: HubScreenInstance
end

function HubScreen:Init(parentGui: ScreenGui, onPlayClicked: (mapId: string) -> ())
	self.gui = parentGui

	local hub = Instance.new("Frame")
	hub.Name = "HubFrame"
	hub.Size = UDim2.new(1, 0, 1, 0)
	hub.BackgroundColor3 = Color3.fromRGB(10, 14, 22)
	hub.BorderSizePixel = 0
	hub.Parent = parentGui
	self.hubFrame = hub

	-- Header Banner: >OPENFRONT<
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
	header.BorderSizePixel = 0
	header.Parent = hub

	local logo = Instance.new("TextLabel")
	logo.Name = "Logo"
	logo.Size = UDim2.new(0, 300, 1, 0)
	logo.Position = UDim2.new(0, 24, 0, 0)
	logo.BackgroundTransparency = 1
	logo.Font = Enum.Font.GothamBlack
	logo.TextSize = 26
	logo.TextColor3 = Color3.fromRGB(245, 200, 45)
	logo.TextXAlignment = Enum.TextXAlignment.Left
	logo.Text = ">OPENFRONT<"
	logo.Parent = header

	-- Solo Modal (Centered)
	local modal = Instance.new("Frame")
	modal.Name = "SoloModal"
	modal.Size = UDim2.new(0, 840, 0, 560)
	modal.Position = UDim2.new(0.5, -420, 0.5, -260)
	modal.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
	modal.BorderSizePixel = 0
	modal.Parent = hub
	Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 12)
	local mStroke = Instance.new("UIStroke", modal)
	mStroke.Color = Color3.fromRGB(45, 65, 95)
	mStroke.Thickness = 1.5

	local mTitle = Instance.new("TextLabel")
	mTitle.Name = "Title"
	mTitle.Size = UDim2.new(1, -40, 0, 40)
	mTitle.Position = UDim2.new(0, 20, 0, 15)
	mTitle.BackgroundTransparency = 1
	mTitle.Font = Enum.Font.GothamBold
	mTitle.TextSize = 20
	mTitle.TextColor3 = Color3.new(1, 1, 1)
	mTitle.TextXAlignment = Enum.TextXAlignment.Left
	mTitle.Text = "MODO SOLITARIO · SELECCIONA TU MAPA"
	mTitle.Parent = modal

	-- Map Grid Scroll
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "MapScroll"
	scroll.Size = UDim2.new(1, -40, 1, -120)
	scroll.Position = UDim2.new(0, 20, 0, 60)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.Parent = modal

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 250, 0, 120)
	grid.CellPadding = UDim2.new(0, 14, 0, 14)
	grid.Parent = scroll

	local mapCards = {}
	local mapsList = MapRegistry.ListMaps()

	for _, mapInfo in ipairs(mapsList) do
		local card = Instance.new("TextButton")
		card.Name = "Card_" .. mapInfo.id
		card.BackgroundColor3 = (mapInfo.id == self.selectedMapId) and Color3.fromRGB(30, 55, 90) or Color3.fromRGB(22, 30, 46)
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = false
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
		local cStroke = Instance.new("UIStroke", card)
		cStroke.Color = (mapInfo.id == self.selectedMapId) and Color3.fromRGB(240, 200, 60) or Color3.fromRGB(40, 55, 80)
		cStroke.Thickness = (mapInfo.id == self.selectedMapId) and 2 or 1

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "Name"
		nameLbl.Size = UDim2.new(1, -16, 0, 24)
		nameLbl.Position = UDim2.new(0, 10, 0, 10)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 15
		nameLbl.TextColor3 = Color3.new(1, 1, 1)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = mapInfo.name
		nameLbl.Parent = card

		local tagLbl = Instance.new("TextLabel")
		tagLbl.Name = "Tag"
		tagLbl.Size = UDim2.new(0, 75, 0, 18)
		tagLbl.Position = UDim2.new(1, -85, 0, 12)
		tagLbl.BackgroundColor3 = Color3.fromRGB(45, 75, 120)
		tagLbl.Font = Enum.Font.GothamBold
		tagLbl.TextSize = 9
		tagLbl.TextColor3 = Color3.fromRGB(230, 240, 255)
		tagLbl.Text = mapInfo.tag
		tagLbl.BorderSizePixel = 0
		tagLbl.Parent = card
		Instance.new("UICorner", tagLbl).CornerRadius = UDim.new(0, 4)

		local descLbl = Instance.new("TextLabel")
		descLbl.Name = "Desc"
		descLbl.Size = UDim2.new(1, -20, 0, 20)
		descLbl.Position = UDim2.new(0, 10, 0, 40)
		descLbl.BackgroundTransparency = 1
		descLbl.Font = Enum.Font.Gotham
		descLbl.TextSize = 11
		descLbl.TextColor3 = Color3.fromRGB(160, 180, 205)
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.Text = mapInfo.subtitle
		descLbl.Parent = card

		local statsLbl = Instance.new("TextLabel")
		statsLbl.Name = "Stats"
		statsLbl.Size = UDim2.new(1, -20, 0, 20)
		statsLbl.Position = UDim2.new(0, 10, 0, 68)
		statsLbl.BackgroundTransparency = 1
		statsLbl.Font = Enum.Font.Gotham
		statsLbl.TextSize = 10
		statsLbl.TextColor3 = Color3.fromRGB(120, 145, 175)
		statsLbl.TextXAlignment = Enum.TextXAlignment.Left
		statsLbl.Text = string.format("📐 %dx%d · 🌍 %d Tierras · 🏳️ %d Naciones", mapInfo.w, mapInfo.h, mapInfo.landTiles, mapInfo.nationsCount)
		statsLbl.Parent = card

		card.MouseButton1Click:Connect(function()
			self.selectedMapId = mapInfo.id
			for _, c in ipairs(mapCards) do
				c.card.BackgroundColor3 = Color3.fromRGB(22, 30, 46)
				c.stroke.Color = Color3.fromRGB(40, 55, 80)
				c.stroke.Thickness = 1
			end
			card.BackgroundColor3 = Color3.fromRGB(30, 55, 90)
			cStroke.Color = Color3.fromRGB(240, 200, 60)
			cStroke.Thickness = 2
		end)

		table.insert(mapCards, { card = card, stroke = cStroke, id = mapInfo.id })
	end

	-- Play Button (Bottom)
	local playBtn = Instance.new("TextButton")
	playBtn.Name = "PlayButton"
	playBtn.Size = UDim2.new(0, 240, 0, 44)
	playBtn.Position = UDim2.new(0.5, -120, 1, -55)
	playBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 70)
	playBtn.Font = Enum.Font.GothamBlack
	playBtn.TextSize = 16
	playBtn.TextColor3 = Color3.new(1, 1, 1)
	playBtn.Text = "JUGAR MAPA ▶"
	playBtn.BorderSizePixel = 0
	playBtn.Parent = modal
	Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0, 8)

	playBtn.MouseButton1Click:Connect(function()
		onPlayClicked(self.selectedMapId)
	end)

	self.soloModal = modal
end

function HubScreen:SetVisible(visible: boolean)
	if self.hubFrame then
		self.hubFrame.Visible = visible
	end
end

return HubScreen
