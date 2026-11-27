--!strict
-- OpenFront.io: InGameHUD
-- Parity with OpenFront HUD Dock, Attack Sliders, Build Bars, and Leaderboard

local InGameHUD = {}
InGameHUD.__index = InGameHUD

export type InGameHUDInstance = {
	gui: ScreenGui,
	dockFrame: Frame,
	leaderboardFrame: Frame,
	attackRatio: number,
	currentMode: string, -- "attack", "build_City", "build_Port", "build_Factory", "build_DefensePost", "build_SAMLauncher", "build_MissileSilo", "nuke_AtomBomb", "nuke_HydrogenBomb", "nuke_MIRV"
	
	Init: (self: InGameHUDInstance, parentGui: ScreenGui, onActionSelected: (mode: string) -> ()) -> (),
	UpdateStats: (self: InGameHUDInstance, troops: number, maxTroops: number, gold: number, incomeTroops: number, incomeGold: number) -> (),
	UpdateLeaderboard: (self: InGameHUDInstance, players: { any }, totalLand: number) -> (),
	SetVisible: (self: InGameHUDInstance, visible: boolean) -> (),
}

local function formatNumber(n: number): string
	if n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 1000 then
		return string.format("%.1fk", n / 1000)
	else
		return tostring(math.floor(n))
	end
end

function InGameHUD.new(): InGameHUDInstance
	local self = setmetatable({}, InGameHUD)
	self.attackRatio = 0.5
	self.currentMode = "attack"
	return (self :: any) :: InGameHUDInstance
end

function InGameHUD:Init(parentGui: ScreenGui, onActionSelected: (mode: string) -> ())
	self.gui = parentGui

	-- Top-Right Leaderboard
	local lb = Instance.new("Frame")
	lb.Name = "Leaderboard"
	lb.Size = UDim2.new(0, 260, 0, 320)
	lb.Position = UDim2.new(1, -270, 0, 20)
	lb.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	lb.BackgroundTransparency = 0.2
	lb.BorderSizePixel = 0
	lb.Parent = parentGui

	local lbCorner = Instance.new("UICorner")
	lbCorner.CornerRadius = UDim.new(0, 8)
	lbCorner.Parent = lb

	local lbStroke = Instance.new("UIStroke")
	lbStroke.Color = Color3.fromRGB(50, 70, 100)
	lbStroke.Thickness = 1
	lbStroke.Parent = lb

	local lbTitle = Instance.new("TextLabel")
	lbTitle.Name = "Title"
	lbTitle.Size = UDim2.new(1, 0, 0, 30)
	lbTitle.BackgroundTransparency = 1
	lbTitle.Font = Enum.Font.GothamBold
	lbTitle.TextSize = 13
	lbTitle.TextColor3 = Color3.fromRGB(240, 200, 60)
	lbTitle.Text = "★ CLASIFICACIÓN MUNDIAL ★"
	lbTitle.Parent = lb

	local lbList = Instance.new("ScrollingFrame")
	lbList.Name = "List"
	lbList.Size = UDim2.new(1, -10, 1, -40)
	lbList.Position = UDim2.new(0, 5, 0, 35)
	lbList.BackgroundTransparency = 1
	lbList.BorderSizePixel = 0
	lbList.ScrollBarThickness = 4
	lbList.Parent = lb

	local lbLayout = Instance.new("UIListLayout")
	lbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lbLayout.Padding = UDim.new(0, 4)
	lbLayout.Parent = lbList

	self.leaderboardFrame = lb

	-- Bottom Dock (OpenFront style)
	local dock = Instance.new("Frame")
	dock.Name = "BottomDock"
	dock.Size = UDim2.new(0, 780, 0, 76)
	dock.Position = UDim2.new(0.5, -390, 1, -90)
	dock.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
	dock.BackgroundTransparency = 0.15
	dock.BorderSizePixel = 0
	dock.Parent = parentGui

	local dockCorner = Instance.new("UICorner")
	dockCorner.CornerRadius = UDim.new(0, 10)
	dockCorner.Parent = dock

	local dockStroke = Instance.new("UIStroke")
	dockStroke.Color = Color3.fromRGB(60, 90, 130)
	dockStroke.Thickness = 1.5
	dockStroke.Parent = dock

	-- Troops Display (Left)
	local troopBox = Instance.new("Frame")
	troopBox.Name = "TroopBox"
	troopBox.Size = UDim2.new(0, 150, 1, -12)
	troopBox.Position = UDim2.new(0, 8, 0, 6)
	troopBox.BackgroundColor3 = Color3.fromRGB(25, 35, 55)
	troopBox.BorderSizePixel = 0
	troopBox.Parent = dock
	Instance.new("UICorner", troopBox).CornerRadius = UDim.new(0, 6)

	local troopLabel = Instance.new("TextLabel")
	troopLabel.Name = "TroopLabel"
	troopLabel.Size = UDim2.new(1, -8, 0, 24)
	troopLabel.Position = UDim2.new(0, 6, 0, 4)
	troopLabel.BackgroundTransparency = 1
	troopLabel.Font = Enum.Font.GothamBold
	troopLabel.TextSize = 15
	troopLabel.TextColor3 = Color3.fromRGB(80, 230, 100)
	troopLabel.TextXAlignment = Enum.TextXAlignment.Left
	troopLabel.Text = "🛡️ 1,000"
	troopLabel.Parent = troopBox
	self.troopLabel = troopLabel

	local troopIncome = Instance.new("TextLabel")
	troopIncome.Name = "TroopIncome"
	troopIncome.Size = UDim2.new(1, -8, 0, 16)
	troopIncome.Position = UDim2.new(0, 6, 0, 26)
	troopIncome.BackgroundTransparency = 1
	troopIncome.Font = Enum.Font.Gotham
	troopIncome.TextSize = 11
	troopIncome.TextColor3 = Color3.fromRGB(150, 220, 160)
	troopIncome.TextXAlignment = Enum.TextXAlignment.Left
	troopIncome.Text = "+12 /s"
	troopIncome.Parent = troopBox
	self.troopIncome = troopIncome

	-- Gold Display (Middle-Left)
	local goldBox = Instance.new("Frame")
	goldBox.Name = "GoldBox"
	goldBox.Size = UDim2.new(0, 150, 1, -12)
	goldBox.Position = UDim2.new(0, 166, 0, 6)
	goldBox.BackgroundColor3 = Color3.fromRGB(25, 35, 55)
	goldBox.BorderSizePixel = 0
	goldBox.Parent = dock
	Instance.new("UICorner", goldBox).CornerRadius = UDim.new(0, 6)

	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldLabel"
	goldLabel.Size = UDim2.new(1, -8, 0, 24)
	goldLabel.Position = UDim2.new(0, 6, 0, 4)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Font = Enum.Font.GothamBold
	goldLabel.TextSize = 15
	goldLabel.TextColor3 = Color3.fromRGB(255, 215, 50)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.Text = "💰 $1.0M"
	goldLabel.Parent = goldBox
	self.goldLabel = goldLabel

	local goldIncome = Instance.new("TextLabel")
	goldIncome.Name = "GoldIncome"
	goldIncome.Size = UDim2.new(1, -8, 0, 16)
	goldIncome.Position = UDim2.new(0, 6, 0, 26)
	goldIncome.BackgroundTransparency = 1
	goldIncome.Font = Enum.Font.Gotham
	goldIncome.TextSize = 11
	goldIncome.TextColor3 = Color3.fromRGB(230, 200, 120)
	goldIncome.TextXAlignment = Enum.TextXAlignment.Left
	goldIncome.Text = "+$2.5k /s"
	goldIncome.Parent = goldBox
	self.goldIncome = goldIncome

	-- Attack Slider Ratio (20%, 40%, 60%, 80%, 100%)
	local ratios = { 0.2, 0.4, 0.6, 0.8, 1.0 }
	local ratioButtons = {}
	for i, r in ipairs(ratios) do
		local btn = Instance.new("TextButton")
		btn.Name = "Ratio_" .. tostring(r * 100)
		btn.Size = UDim2.new(0, 42, 0, 26)
		btn.Position = UDim2.new(0, 324 + (i - 1) * 46, 0, 8)
		btn.BackgroundColor3 = (r == 0.6) and Color3.fromRGB(220, 60, 60) or Color3.fromRGB(35, 45, 65)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 11
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Text = tostring(math.floor(r * 100)) .. "%"
		btn.BorderSizePixel = 0
		btn.Parent = dock
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

		btn.MouseButton1Click:Connect(function()
			self.attackRatio = r
			for _, b in ipairs(ratioButtons) do
				b.BackgroundColor3 = Color3.fromRGB(35, 45, 65)
			end
			btn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		end)
		table.insert(ratioButtons, btn)
	end

	-- Action Buttons (City, Port, Factory, Defense, SAM, Silo, Nuclear)
	local actions = {
		{ id = "build_City", label = "🏛️ Ciudad", cost = "$125k" },
		{ id = "build_Port", label = "⚓ Puerto", cost = "$125k" },
		{ id = "build_Factory", label = "🏭 Fábrica", cost = "$125k" },
		{ id = "build_DefensePost", label = "🛡️ Defensa", cost = "$50k" },
		{ id = "build_SAMLauncher", label = "📡 SAM", cost = "$1.5M" },
		{ id = "build_MissileSilo", label = "🚀 Silo", cost = "$1M" },
		{ id = "nuke_AtomBomb", label = "☢️ Nuclear", cost = "$750k" },
	}

	for i, act in ipairs(actions) do
		local abtn = Instance.new("TextButton")
		abtn.Name = "Action_" .. act.id
		abtn.Size = UDim2.new(0, 62, 0, 28)
		abtn.Position = UDim2.new(0, 324 + (i - 1) * 65, 0, 40)
		abtn.BackgroundColor3 = Color3.fromRGB(40, 55, 80)
		abtn.Font = Enum.Font.GothamBold
		abtn.TextSize = 10
		abtn.TextColor3 = Color3.fromRGB(220, 230, 255)
		abtn.Text = act.label
		abtn.BorderSizePixel = 0
		abtn.Parent = dock
		Instance.new("UICorner", abtn).CornerRadius = UDim.new(0, 4)

		abtn.MouseButton1Click:Connect(function()
			if self.currentMode == act.id then
				self.currentMode = "attack"
				abtn.BackgroundColor3 = Color3.fromRGB(40, 55, 80)
			else
				self.currentMode = act.id
				abtn.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
			end
			onActionSelected(self.currentMode)
		end)
	end

	self.dockFrame = dock
end

function InGameHUD:UpdateStats(troops: number, maxTroops: number, gold: number, incomeTroops: number, incomeGold: number)
	if self.troopLabel then
		self.troopLabel.Text = "🛡️ " .. formatNumber(troops) .. " / " .. formatNumber(maxTroops)
	end
	if self.troopIncome then
		self.troopIncome.Text = "+" .. formatNumber(incomeTroops) .. " /s"
	end
	if self.goldLabel then
		self.goldLabel.Text = "💰 $" .. formatNumber(gold)
	end
	if self.goldIncome then
		self.goldIncome.Text = "+$" .. formatNumber(incomeGold) .. " /s"
	end
end

function InGameHUD:UpdateLeaderboard(players: { any }, totalLand: number)
	if not self.leaderboardFrame then return end
	local list = self.leaderboardFrame:FindFirstChild("List") :: ScrollingFrame?
	if not list then return end

	-- Sort by tiles descending
	table.sort(players, function(a, b)
		return (a.tiles or 0) > (b.tiles or 0)
	end)

	-- Update or create rows
	for i = 1, math.min(10, #players) do
		local p = players[i]
		local row = list:FindFirstChild("Row_" .. tostring(i)) :: Frame?
		if not row then
			row = Instance.new("Frame")
			row.Name = "Row_" .. tostring(i)
			row.Size = UDim2.new(1, 0, 0, 24)
			row.BackgroundColor3 = Color3.fromRGB(25, 35, 50)
			row.BackgroundTransparency = 0.5
			row.BorderSizePixel = 0
			row.Parent = list
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "Name"
			nameLbl.Size = UDim2.new(0.55, 0, 1, 0)
			nameLbl.Position = UDim2.new(0, 6, 0, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamMedium
			nameLbl.TextSize = 11
			nameLbl.TextColor3 = Color3.new(1, 1, 1)
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.Parent = row

			local statsLbl = Instance.new("TextLabel")
			statsLbl.Name = "Stats"
			statsLbl.Size = UDim2.new(0.4, 0, 1, 0)
			statsLbl.Position = UDim2.new(0.6, 0, 0, 0)
			statsLbl.BackgroundTransparency = 1
			statsLbl.Font = Enum.Font.Gotham
			statsLbl.TextSize = 10
			statsLbl.TextColor3 = Color3.fromRGB(200, 210, 230)
			statsLbl.TextXAlignment = Enum.TextXAlignment.Right
			statsLbl.Parent = row
		end

		local nameLbl = row:FindFirstChild("Name") :: TextLabel
		local statsLbl = row:FindFirstChild("Stats") :: TextLabel
		if nameLbl and statsLbl then
			local crown = (i == 1) and "👑 " or ""
			nameLbl.Text = crown .. tostring(i) .. ". " .. p.name
			local pct = totalLand > 0 and math.floor((p.tiles / totalLand) * 100) or 0
			statsLbl.Text = formatNumber(p.troops or 0) .. " (" .. tostring(pct) .. "%)"
			if p.isHuman then
				nameLbl.TextColor3 = Color3.fromRGB(255, 220, 60)
			else
				nameLbl.TextColor3 = Color3.fromRGB(220, 230, 240)
			end
		end
	end
end

function InGameHUD:SetVisible(visible: boolean)
	if self.dockFrame then self.dockFrame.Visible = visible end
	if self.leaderboardFrame then self.leaderboardFrame.Visible = visible end
end

return InGameHUD
