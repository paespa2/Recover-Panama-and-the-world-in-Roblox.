--!strict
-- MapOverlayRenderer.luau
-- Renderiza sobre MapCanvas del mapa mundial:
--   • Píldoras flotantes de frente (⚔ Attacking <Objetivo> with <N> / ⚔ Expanding with <N>)
--   • Contador compacto en línea de frente
--   • Corona dorada (👑) sobre el líder #1 del mundo
--   • Texto flotante de botín de oro (+ 15.9K) al conquistar una nación

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

export type FrontOverlayData = {
	id: string,
	targetName: string,
	troops: number,
	cell: number,
	isExpansion: boolean,
	isMine: boolean,
}

local MapOverlayRenderer = {}
MapOverlayRenderer.__index = MapOverlayRenderer

local GOLD_ACCENT = Color3.fromHex("#FFB344")
local GOLD_TEXT = Color3.fromHex("#FDE8A2")
local GREEN_ACCENT = Color3.fromHex("#28A959")
local GREEN_TEXT = Color3.fromHex("#86EFAC")
local PILL_BG = Color3.fromHex("#0F1626")

local function formatCompact(n: number): string
	local v = math.max(0, math.floor(n + 0.5))
	if v >= 1_000_000 then
		return string.format("%.2fM", v / 1_000_000)
	elseif v >= 1_000 then
		return string.format("%.1fK", v / 1_000)
	end
	return tostring(v)
end

export type MapOverlayRendererInstance = typeof(setmetatable(
	{} :: {
		layer: Folder?,
		frontNodes: { [string]: { pill: Frame, pillLabel: TextLabel, counter: TextLabel } },
		leaderBadge: Frame?,
		leaderLabel: TextLabel?,
		leaderBobTween: Tween?,
	},
	MapOverlayRenderer
))

function MapOverlayRenderer.new(): MapOverlayRendererInstance
	local self = setmetatable({
		layer = nil :: Folder?,
		frontNodes = {} :: { [string]: { pill: Frame, pillLabel: TextLabel, counter: TextLabel } },
		leaderBadge = nil :: Frame?,
		leaderLabel = nil :: TextLabel?,
		leaderBobTween = nil :: Tween?,
	}, MapOverlayRenderer)
	return self
end

function MapOverlayRenderer:_ensureLayer(): Frame?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end
	local pgui = localPlayer:FindFirstChild("PlayerGui")
	if not pgui then
		return nil
	end
	local worldGui = pgui:FindFirstChild("WorldConquestGui")
	local root = if worldGui then worldGui:FindFirstChild("Root") else nil
	local mapContainer = if root then root:FindFirstChild("MapContainer") else nil
	local mapCanvas = if mapContainer then mapContainer:FindFirstChild("MapCanvas") else nil
	if not mapCanvas or not mapCanvas:IsA("Frame") then
		return nil
	end

	if not self.layer or self.layer.Parent ~= mapCanvas then
		local existing = mapCanvas:FindFirstChild("MapOverlayLayer")
		if existing and existing:IsA("Folder") then
			self.layer = existing
		else
			local folder = Instance.new("Folder")
			folder.Name = "MapOverlayLayer"
			folder.Parent = mapCanvas
			self.layer = folder
		end
	end

	return mapCanvas
end

function MapOverlayRenderer:UpdateFronts(fronts: { FrontOverlayData }, mapW: number, mapH: number)
	local mapCanvas = self:_ensureLayer()
	local layer = self.layer
	if not mapCanvas or not layer then
		return
	end
	if mapW <= 0 or mapH <= 0 then
		return
	end

	local seen: { [string]: boolean } = {}
	for _, f in ipairs(fronts) do
		if f.cell >= 0 and f.troops > 0 then
			seen[f.id] = true
			local cx = f.cell % mapW
			local cy = math.floor(f.cell / mapW)
			local uPos = UDim2.fromScale((cx + 0.5) / mapW, (cy + 0.5) / mapH)

			local node = self.frontNodes[f.id]
			if not node then
				local pill = Instance.new("Frame")
				pill.Name = "FrontPill_" .. f.id
				pill.AnchorPoint = Vector2.new(0.5, 1)
				pill.Size = UDim2.fromOffset(186, 22)
				pill.BackgroundColor3 = PILL_BG
				pill.BackgroundTransparency = 0.08
				pill.BorderSizePixel = 0
				pill.Active = false
				pill.ZIndex = 24
				pill.Parent = layer

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = pill

				local stroke = Instance.new("UIStroke")
				stroke.Name = "PillStroke"
				stroke.Thickness = 1.4
				stroke.Parent = pill

				local lbl = Instance.new("TextLabel")
				lbl.Name = "Text"
				lbl.Position = UDim2.fromOffset(8, 0)
				lbl.Size = UDim2.new(1, -16, 1, 0)
				lbl.BackgroundTransparency = 1
				lbl.Font = Enum.Font.GothamBold
				lbl.TextSize = 10
				lbl.TextTruncate = Enum.TextTruncate.AtEnd
				lbl.Active = false
				lbl.ZIndex = 25
				lbl.Parent = pill

				local counter = Instance.new("TextLabel")
				counter.Name = "FrontCounter_" .. f.id
				counter.AnchorPoint = Vector2.new(0.5, 0)
				counter.Size = UDim2.fromOffset(58, 15)
				counter.BackgroundColor3 = PILL_BG
				counter.BackgroundTransparency = 0.16
				counter.BorderSizePixel = 0
				counter.Font = Enum.Font.GothamBlack
				counter.TextSize = 9
				counter.Active = false
				counter.ZIndex = 24
				counter.Parent = layer

				local cc = Instance.new("UICorner")
				cc.CornerRadius = UDim.new(1, 0)
				cc.Parent = counter

				node = {
					pill = pill,
					pillLabel = lbl,
					counter = counter,
				}
				self.frontNodes[f.id] = node
			end

			local accent = if f.isExpansion then GREEN_ACCENT else GOLD_ACCENT
			local textColor = if f.isExpansion then GREEN_TEXT else GOLD_TEXT
			local stroke = node.pill:FindFirstChild("PillStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = accent
			end

			local compactTroops = formatCompact(f.troops)
			if f.isExpansion then
				node.pillLabel.Text = string.format("⚔ Expanding with %s", compactTroops)
			else
				node.pillLabel.Text = string.format("⚔ Attacking %s with %s", f.targetName, compactTroops)
			end
			node.pillLabel.TextColor3 = textColor

			local widthEst = math.clamp(42 + #node.pillLabel.Text * 5.6, 128, 260)
			node.pill.Size = UDim2.fromOffset(widthEst, 22)
			node.pill.Position = uPos + UDim2.fromOffset(0, -10)
			node.pill.Visible = f.isMine or f.troops >= 1000

			node.counter.Text = compactTroops
			node.counter.TextColor3 = textColor
			node.counter.Position = uPos + UDim2.fromOffset(0, 6)
			node.counter.Visible = true
		end
	end

	for id, node in pairs(self.frontNodes) do
		if not seen[id] then
			node.pill:Destroy()
			node.counter:Destroy()
			self.frontNodes[id] = nil
		end
	end
end

function MapOverlayRenderer:UpdateLeaderCrown(
	leaderCell: number?,
	leaderName: string?,
	isLocalPlayer: boolean,
	mapW: number,
	mapH: number
)
	local mapCanvas = self:_ensureLayer()
	local layer = self.layer
	if not mapCanvas or not layer or not leaderCell or leaderCell < 0 or mapW <= 0 or mapH <= 0 then
		if self.leaderBadge then
			self.leaderBadge.Visible = false
		end
		return
	end

	if not self.leaderBadge or self.leaderBadge.Parent ~= layer then
		local badge = Instance.new("Frame")
		badge.Name = "LeaderCrown"
		badge.AnchorPoint = Vector2.new(0.5, 1)
		badge.Size = UDim2.fromOffset(132, 24)
		badge.BackgroundColor3 = PILL_BG
		badge.BackgroundTransparency = 0.1
		badge.BorderSizePixel = 0
		badge.Active = false
		badge.ZIndex = 26
		badge.Parent = layer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = badge

		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD_ACCENT
		stroke.Thickness = 1.6
		stroke.Parent = badge

		local lbl = Instance.new("TextLabel")
		lbl.Name = "CrownText"
		lbl.Position = UDim2.fromOffset(8, 0)
		lbl.Size = UDim2.new(1, -16, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextColor3 = GOLD_TEXT
		lbl.TextSize = 11
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Active = false
		lbl.ZIndex = 27
		lbl.Parent = badge

		self.leaderBadge = badge
		self.leaderLabel = lbl
	end

	local badge = self.leaderBadge :: Frame
	local lbl = self.leaderLabel :: TextLabel
	local cx = leaderCell % mapW
	local cy = math.floor(leaderCell / mapW)

	local labelName = leaderName or "Líder"
	lbl.Text = if isLocalPlayer then ("👑 " .. labelName .. " (#1)") else ("👑 #1 " .. labelName)
	local w = math.clamp(38 + #lbl.Text * 6.5, 108, 220)
	badge.Size = UDim2.fromOffset(w, 22)
	badge.Position = UDim2.fromScale((cx + 0.5) / mapW, (cy + 0.5) / mapH) + UDim2.fromOffset(0, -34)
	badge.Visible = true
end

function MapOverlayRenderer:SpawnGoldLoot(cell: number, amount: number, mapW: number, mapH: number)
	local mapCanvas = self:_ensureLayer()
	local layer = self.layer
	if not mapCanvas or not layer or cell < 0 or amount <= 0 or mapW <= 0 or mapH <= 0 then
		return
	end

	local cx = cell % mapW
	local cy = math.floor(cell / mapW)
	local basePos = UDim2.fromScale((cx + 0.5) / mapW, (cy + 0.5) / mapH)

	local popup = Instance.new("TextLabel")
	popup.Name = "GoldLootPopup"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = basePos + UDim2.fromOffset(0, -14)
	popup.Size = UDim2.fromOffset(130, 24)
	popup.BackgroundColor3 = PILL_BG
	popup.BackgroundTransparency = 0.2
	popup.BorderSizePixel = 0
	popup.Font = Enum.Font.GothamBlack
	popup.Text = string.format("◉ + %s", formatCompact(amount))
	popup.TextColor3 = GOLD_TEXT
	popup.TextSize = 13
	popup.TextStrokeColor3 = Color3.fromHex("#090D16")
	popup.TextStrokeTransparency = 0.15
	popup.Active = false
	popup.ZIndex = 30
	popup.Parent = layer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = popup

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD_ACCENT
	stroke.Thickness = 1.4
	stroke.Parent = popup

	local tween = TweenService:Create(
		popup,
		TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = basePos + UDim2.fromOffset(0, -56),
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}
	)
	TweenService:Create(stroke, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
	}):Play()
	tween:Play()
	tween.Completed:Connect(function()
		popup:Destroy()
	end)
end

function MapOverlayRenderer:Clear()
	for id, node in pairs(self.frontNodes) do
		node.pill:Destroy()
		node.counter:Destroy()
		self.frontNodes[id] = nil
	end
	if self.leaderBadge then
		self.leaderBadge.Visible = false
	end
end

function MapOverlayRenderer:Destroy()
	self:Clear()
	if self.leaderBadge then
		self.leaderBadge:Destroy()
		self.leaderBadge = nil
	end
	if self.layer then
		self.layer:Destroy()
		self.layer = nil
	end
end

return MapOverlayRenderer
