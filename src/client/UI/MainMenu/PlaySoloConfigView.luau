--!strict
-- PlaySoloConfigView.luau
-- Sub-vista de configuración de partida individual (PLAY SOLO) y estado de carga "Deploying a new world..."
-- Mantiene el contenedor de la tarjeta central (#1C253C) reemplazando el lobby principal.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))

local PlaySoloConfigView = {}
PlaySoloConfigView.__index = PlaySoloConfigView

export type SoloDifficulty = "Relaxed" | "Standard" | "Brutal"

export type PlaySoloCallbacks = {
	OnBack: (() -> ())?,
	OnStartGame: ((mapId: string, difficulty: SoloDifficulty) -> ())?,
}

type MapOption = {
	id: string,
	label: string,
}

type DifficultyOption = {
	id: SoloDifficulty,
	description: string,
}

export type PlaySoloConfigViewInstance = {
	root: Frame,
	configContainer: Frame,
	deployingContainer: Frame,
	selectedMapIndex: number,
	selectedDifficulty: SoloDifficulty,
	spinnerConn: RBXScriptConnection?,
	cleanups: { () -> () },
	Show: (self: PlaySoloConfigViewInstance) -> (),
	Hide: (self: PlaySoloConfigViewInstance) -> (),
	ShowDeploying: (self: PlaySoloConfigViewInstance, duration: number?, onComplete: (() -> ())?) -> (),
	Destroy: (self: PlaySoloConfigViewInstance) -> (),
}

local MAPS: { MapOption } = {
	{ id = "EARTH", label = "World (Tierra)" },
	{ id = "WORLD", label = "World (FrontWars)" },
	{ id = "EUROPE", label = "Europa" },
	{ id = "ASIA", label = "Asia" },
	{ id = "AFRICA", label = "África" },
	{ id = "MENA", label = "Medio Oriente" },
	{ id = "OCEANIA", label = "Oceanía" },
	{ id = "PANGEA", label = "Pangea" },
	{ id = "MARS", label = "Marte" },
	{ id = "MOON", label = "Luna" },
	{ id = "VENUS", label = "Venus" },
	{ id = "ANDROMEDA", label = "Andrómeda" },
}

local DIFFICULTIES: { DifficultyOption } = {
	{
		id = "Relaxed",
		description = "A calmer pace against the AI. Computer nations leave you alone for about 4 min 30 s.",
	},
	{
		id = "Standard",
		description = "A fair fight against the AI. Computer nations leave you alone for about 2 min 58 s.",
	},
	{
		id = "Brutal",
		description = "Relentless AI opponents. Computer nations expand aggressively after just 1 min 15 s.",
	},
}

function PlaySoloConfigView.new(parent: Instance, callbacks: PlaySoloCallbacks?): PlaySoloConfigViewInstance
	local cb: PlaySoloCallbacks = callbacks or {}
	local cleanups: { () -> () } = {}

	local root = Instance.new("Frame")
	root.Name = "PlaySoloConfigView"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 7
	root.Parent = parent

	-- =========================================================================
	-- 1. VISTA DE CONFIGURACIÓN (ConfigContainer)
	-- =========================================================================
	local configContainer = Instance.new("Frame")
	configContainer.Name = "ConfigContainer"
	configContainer.Size = UDim2.fromScale(1, 1)
	configContainer.BackgroundTransparency = 1
	configContainer.Visible = true
	configContainer.ZIndex = 7
	configContainer.Parent = root

	-- Cabecera: ▶ PLAY SOLO + botón ×
	local headerRow = Instance.new("Frame")
	headerRow.Name = "HeaderRow"
	headerRow.Position = UDim2.fromOffset(0, 0)
	headerRow.Size = UDim2.new(1, 0, 0, 36)
	headerRow.BackgroundTransparency = 1
	headerRow.ZIndex = 8
	headerRow.Parent = configContainer

	local triIcon = Instance.new("TextLabel")
	triIcon.Name = "PlayTriangle"
	triIcon.Position = UDim2.fromOffset(0, 2)
	triIcon.Size = UDim2.fromOffset(22, 32)
	triIcon.BackgroundTransparency = 1
	triIcon.Font = MenuTheme.Fonts.Heading
	triIcon.Text = "▶"
	triIcon.TextColor3 = MenuTheme.Colors.PlaySoloBg
	triIcon.TextSize = 18
	triIcon.TextXAlignment = Enum.TextXAlignment.Left
	triIcon.ZIndex = 8
	triIcon.Parent = headerRow

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Position = UDim2.fromOffset(26, 0)
	headerTitle.Size = UDim2.new(1, -70, 1, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Font = MenuTheme.Fonts.Heading
	headerTitle.Text = "PLAY SOLO"
	headerTitle.TextColor3 = MenuTheme.Colors.White
	headerTitle.TextSize = 20
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.ZIndex = 8
	headerTitle.Parent = headerRow

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "BtnCloseSolo"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.BackgroundColor3 = MenuTheme.Colors.HelpBtnBg
	closeBtn.AutoButtonColor = false
	closeBtn.Font = MenuTheme.Fonts.Heading
	closeBtn.Text = "×"
	closeBtn.TextColor3 = MenuTheme.Colors.SubtleText
	closeBtn.TextSize = 20
	closeBtn.ZIndex = 9
	closeBtn.Parent = headerRow

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = MenuTheme.Colors.CardStroke
	closeStroke.Thickness = 1
	closeStroke.Parent = closeBtn

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(closeBtn, {
			baseColor = MenuTheme.Colors.HelpBtnBg,
			hoverColor = MenuTheme.Colors.CardRowHoverBg,
			stroke = closeStroke,
			baseStrokeColor = MenuTheme.Colors.CardStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanBorder,
		})
	)

	-- Selector de mapa: #141E30, borde #24324A, UICorner 8px
	local mapBtn = Instance.new("TextButton")
	mapBtn.Name = "BtnMapSelector"
	mapBtn.Position = UDim2.fromOffset(0, 52)
	mapBtn.Size = UDim2.new(1, 0, 0, 48)
	mapBtn.BackgroundColor3 = MenuTheme.Colors.SideCardBg
	mapBtn.AutoButtonColor = false
	mapBtn.Text = ""
	mapBtn.ZIndex = 8
	mapBtn.Parent = configContainer

	local mapCorner = Instance.new("UICorner")
	mapCorner.CornerRadius = UDim.new(0, 8)
	mapCorner.Parent = mapBtn

	local mapStroke = Instance.new("UIStroke")
	mapStroke.Color = MenuTheme.Colors.CardStroke
	mapStroke.Thickness = 1
	mapStroke.Parent = mapBtn

	local mapGlobe = Instance.new("TextLabel")
	mapGlobe.Name = "GlobeIcon"
	mapGlobe.Position = UDim2.fromOffset(14, 0)
	mapGlobe.Size = UDim2.new(0, 26, 1, 0)
	mapGlobe.BackgroundTransparency = 1
	mapGlobe.Font = MenuTheme.Fonts.Heading
	mapGlobe.Text = "🌐"
	mapGlobe.TextColor3 = MenuTheme.Colors.White
	mapGlobe.TextSize = 18
	mapGlobe.ZIndex = 9
	mapGlobe.Parent = mapBtn

	local mapText = Instance.new("TextLabel")
	mapText.Name = "MapValueText"
	mapText.Position = UDim2.fromOffset(48, 0)
	mapText.Size = UDim2.new(1, -84, 1, 0)
	mapText.BackgroundTransparency = 1
	mapText.Font = MenuTheme.Fonts.Bold
	mapText.Text = "Map: World"
	mapText.TextColor3 = MenuTheme.Colors.White
	mapText.TextSize = 15
	mapText.TextXAlignment = Enum.TextXAlignment.Left
	mapText.TextTruncate = Enum.TextTruncate.AtEnd
	mapText.ZIndex = 9
	mapText.Parent = mapBtn

	local mapChevron = Instance.new("TextLabel")
	mapChevron.Name = "Chevron"
	mapChevron.AnchorPoint = Vector2.new(1, 0.5)
	mapChevron.Position = UDim2.new(1, -14, 0.5, 0)
	mapChevron.Size = UDim2.fromOffset(20, 20)
	mapChevron.BackgroundTransparency = 1
	mapChevron.Font = MenuTheme.Fonts.Bold
	mapChevron.Text = "▾"
	mapChevron.TextColor3 = MenuTheme.Colors.MutedText
	mapChevron.TextSize = 15
	mapChevron.ZIndex = 9
	mapChevron.Parent = mapBtn

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(mapBtn, {
			hoverScale = 1.01,
			pressScale = 0.99,
			baseColor = MenuTheme.Colors.SideCardBg,
			hoverColor = MenuTheme.Colors.CardRowHoverBg,
			stroke = mapStroke,
			baseStrokeColor = MenuTheme.Colors.CardStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanBorder,
		})
	)

	-- Fila DIFFICULTY: etiqueta izquierda + 3 píldoras (Relaxed, Standard, Brutal)
	local diffRow = Instance.new("Frame")
	diffRow.Name = "DifficultyRow"
	diffRow.Position = UDim2.fromOffset(0, 118)
	diffRow.Size = UDim2.new(1, 0, 0, 42)
	diffRow.BackgroundTransparency = 1
	diffRow.ZIndex = 8
	diffRow.Parent = configContainer

	local diffLabel = Instance.new("TextLabel")
	diffLabel.Name = "DifficultyTitle"
	diffLabel.Position = UDim2.fromOffset(0, 0)
	diffLabel.Size = UDim2.new(0, 118, 1, 0)
	diffLabel.BackgroundTransparency = 1
	diffLabel.Font = MenuTheme.Fonts.Heading
	diffLabel.Text = "DIFFICULTY"
	diffLabel.TextColor3 = MenuTheme.Colors.MutedText
	diffLabel.TextSize = 12
	diffLabel.TextXAlignment = Enum.TextXAlignment.Left
	diffLabel.ZIndex = 8
	diffLabel.Parent = diffRow

	local pillsContainer = Instance.new("Frame")
	pillsContainer.Name = "PillsContainer"
	pillsContainer.Position = UDim2.fromOffset(122, 2)
	pillsContainer.Size = UDim2.new(1, -122, 1, -4)
	pillsContainer.BackgroundTransparency = 1
	pillsContainer.ZIndex = 8
	pillsContainer.Parent = diffRow

	local pillsLayout = Instance.new("UIListLayout")
	pillsLayout.FillDirection = Enum.FillDirection.Horizontal
	pillsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pillsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pillsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillsLayout.Padding = UDim.new(0, 10)
	pillsLayout.Parent = pillsContainer

	-- Descripción dinámica centrada
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "DifficultyDescription"
	descLabel.Position = UDim2.fromOffset(16, 174)
	descLabel.Size = UDim2.new(1, -32, 0, 56)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = MenuTheme.Fonts.Regular
	descLabel.Text = DIFFICULTIES[2].description
	descLabel.TextColor3 = MenuTheme.Colors.SubtleText
	descLabel.TextSize = 13
	descLabel.TextWrapped = true
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.TextYAlignment = Enum.TextYAlignment.Center
	descLabel.ZIndex = 8
	descLabel.Parent = configContainer

	local descConstraint = Instance.new("UITextSizeConstraint")
	descConstraint.MaxTextSize = 14
	descConstraint.MinTextSize = 10
	descConstraint.Parent = descLabel

	-- Botón ▶ START ancho en #FFB344
	local startBtn = Instance.new("TextButton")
	startBtn.Name = "BtnStartSolo"
	startBtn.AnchorPoint = Vector2.new(0, 1)
	startBtn.Position = UDim2.new(0, 0, 1, 0)
	startBtn.Size = UDim2.new(1, 0, 0, 50)
	startBtn.BackgroundColor3 = MenuTheme.Colors.PlaySoloBg
	startBtn.AutoButtonColor = false
	startBtn.Text = ""
	startBtn.ZIndex = 8
	startBtn.Parent = configContainer

	local startCorner = Instance.new("UICorner")
	startCorner.CornerRadius = MenuTheme.Corners.CTA
	startCorner.Parent = startBtn

	local startText = Instance.new("TextLabel")
	startText.Name = "StartText"
	startText.Size = UDim2.fromScale(1, 1)
	startText.BackgroundTransparency = 1
	startText.Font = MenuTheme.Fonts.Heading
	startText.Text = "▶  START"
	startText.TextColor3 = MenuTheme.Colors.DarkText
	startText.TextSize = 17
	startText.ZIndex = 9
	startText.Parent = startBtn

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(startBtn, {
			hoverScale = 1.02,
			pressScale = 0.98,
			baseColor = MenuTheme.Colors.PlaySoloBg,
			hoverColor = MenuTheme.Colors.PlaySoloHover,
		})
	)

	-- =========================================================================
	-- 2. VISTA DE CARGA (DeployingContainer)
	-- =========================================================================
	local deployingContainer = Instance.new("Frame")
	deployingContainer.Name = "DeployingContainer"
	deployingContainer.Size = UDim2.fromScale(1, 1)
	deployingContainer.BackgroundTransparency = 1
	deployingContainer.Visible = false
	deployingContainer.ZIndex = 8
	deployingContainer.Parent = root

	local spinnerRing = Instance.new("Frame")
	spinnerRing.Name = "SpinnerRing"
	spinnerRing.AnchorPoint = Vector2.new(0.5, 0.5)
	spinnerRing.Position = UDim2.new(0.5, 0, 0.44, 0)
	spinnerRing.Size = UDim2.fromOffset(48, 48)
	spinnerRing.BackgroundTransparency = 1
	spinnerRing.ZIndex = 9
	spinnerRing.Parent = deployingContainer

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = MenuTheme.Corners.Pill
	ringCorner.Parent = spinnerRing

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = MenuTheme.Colors.PlaySoloBg
	ringStroke.Thickness = 4
	ringStroke.Parent = spinnerRing

	local ringGrad = Instance.new("UIGradient")
	ringGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.65, 0.25),
		NumberSequenceKeypoint.new(0.85, 0.92),
		NumberSequenceKeypoint.new(1, 1),
	})
	ringGrad.Parent = ringStroke

	local deployLbl = Instance.new("TextLabel")
	deployLbl.Name = "DeployingText"
	deployLbl.AnchorPoint = Vector2.new(0.5, 0)
	deployLbl.Position = UDim2.new(0.5, 0, 0.56, 8)
	deployLbl.Size = UDim2.new(1, -24, 0, 28)
	deployLbl.BackgroundTransparency = 1
	deployLbl.Font = MenuTheme.Fonts.Bold
	deployLbl.Text = "Deploying a new world..."
	deployLbl.TextColor3 = MenuTheme.Colors.White
	deployLbl.TextSize = 16
	deployLbl.TextTruncate = Enum.TextTruncate.AtEnd
	deployLbl.ZIndex = 9
	deployLbl.Parent = deployingContainer

	-- Gestión de las píldoras de dificultad
	type PillRef = {
		id: SoloDifficulty,
		btn: TextButton,
		stroke: UIStroke,
		desc: string,
	}
	local pillRefs: { PillRef } = {}

	local self = setmetatable({
		root = root,
		configContainer = configContainer,
		deployingContainer = deployingContainer,
		selectedMapIndex = 1,
		selectedDifficulty = "Standard" :: SoloDifficulty,
		spinnerConn = nil :: RBXScriptConnection?,
		cleanups = cleanups,
		ringGrad = ringGrad,
	}, PlaySoloConfigView)

	local function refreshDifficultyVisuals()
		for _, p in ipairs(pillRefs) do
			local active = p.id == self.selectedDifficulty
			if active then
				p.btn.BackgroundColor3 = Color3.fromHex("#3B2D19")
				p.btn.BackgroundTransparency = 0.15
				p.btn.TextColor3 = MenuTheme.Colors.PlaySoloBg
				p.stroke.Color = MenuTheme.Colors.PlaySoloBg
				p.stroke.Thickness = 1.6
				descLabel.Text = p.desc
			else
				p.btn.BackgroundColor3 = MenuTheme.Colors.SideCardBg
				p.btn.BackgroundTransparency = 0
				p.btn.TextColor3 = MenuTheme.Colors.SubtleText
				p.stroke.Color = MenuTheme.Colors.CardStroke
				p.stroke.Thickness = 1
			end
		end
	end

	for idx, d in ipairs(DIFFICULTIES) do
		local pill = Instance.new("TextButton")
		pill.Name = "Pill_" .. d.id
		pill.LayoutOrder = idx
		pill.Size = UDim2.fromOffset(120, 36)
		pill.BackgroundColor3 = MenuTheme.Colors.SideCardBg
		pill.AutoButtonColor = false
		pill.Font = MenuTheme.Fonts.Bold
		pill.Text = d.id
		pill.TextColor3 = MenuTheme.Colors.SubtleText
		pill.TextSize = 13
		pill.ZIndex = 9
		pill.Parent = pillsContainer

		local pc = Instance.new("UICorner")
		pc.CornerRadius = MenuTheme.Corners.Pill
		pc.Parent = pill

		local ps = Instance.new("UIStroke")
		ps.Color = MenuTheme.Colors.CardStroke
		ps.Thickness = 1
		ps.Parent = pill

		local scaleObj = Instance.new("UIScale")
		scaleObj.Scale = 1
		scaleObj.Parent = pill

		local cEnter = pill.MouseEnter:Connect(function()
			TweenService:Create(scaleObj, MenuTheme.Tweens.Hover, { Scale = 1.03 }):Play()
		end)
		local cLeave = pill.MouseLeave:Connect(function()
			TweenService:Create(scaleObj, MenuTheme.Tweens.Hover, { Scale = 1 }):Play()
		end)
		local cDown = pill.MouseButton1Down:Connect(function()
			TweenService:Create(scaleObj, MenuTheme.Tweens.Press, { Scale = 0.97 }):Play()
		end)
		local cUp = pill.MouseButton1Up:Connect(function()
			TweenService:Create(scaleObj, MenuTheme.Tweens.Hover, { Scale = 1.03 }):Play()
		end)
		table.insert(cleanups, function()
			cEnter:Disconnect()
			cLeave:Disconnect()
			cDown:Disconnect()
			cUp:Disconnect()
		end)

		local capturedId = d.id
		pill.MouseButton1Click:Connect(function()
			self.selectedDifficulty = capturedId
			refreshDifficultyVisuals()
		end)

		table.insert(pillRefs, {
			id = d.id,
			btn = pill,
			stroke = ps,
			desc = d.description,
		})
	end

	refreshDifficultyVisuals()

	mapBtn.MouseButton1Click:Connect(function()
		self.selectedMapIndex = (self.selectedMapIndex % #MAPS) + 1
		local chosen = MAPS[self.selectedMapIndex]
		mapText.Text = "Map: " .. chosen.label
	end)

	closeBtn.MouseButton1Click:Connect(function()
		if cb.OnBack then
			cb.OnBack()
		end
	end)

	startBtn.MouseButton1Click:Connect(function()
		local chosenMap = MAPS[self.selectedMapIndex]
		if cb.OnStartGame then
			cb.OnStartGame(chosenMap.id, self.selectedDifficulty)
		end
	end)

	return (self :: any) :: PlaySoloConfigViewInstance
end

function PlaySoloConfigView:Show()
	if self.spinnerConn then
		self.spinnerConn:Disconnect()
		self.spinnerConn = nil
	end
	self.deployingContainer.Visible = false
	self.configContainer.Visible = true
	self.root.Visible = true
end

function PlaySoloConfigView:Hide()
	if self.spinnerConn then
		self.spinnerConn:Disconnect()
		self.spinnerConn = nil
	end
	self.root.Visible = false
end

function PlaySoloConfigView:ShowDeploying(duration: number?, onComplete: (() -> ())?)
	if self.spinnerConn then
		self.spinnerConn:Disconnect()
		self.spinnerConn = nil
	end
	self.configContainer.Visible = false
	self.deployingContainer.Visible = true
	self.root.Visible = true

	local angle = 0
	self.spinnerConn = RunService.RenderStepped:Connect(function(dt: number)
		angle = (angle + dt * 360) % 360
		self.ringGrad.Rotation = angle
	end)

	local waitTime = duration or 1.15
	task.delay(waitTime, function()
		if self.spinnerConn then
			self.spinnerConn:Disconnect()
			self.spinnerConn = nil
		end
		if onComplete then
			onComplete()
		end
	end)
end

function PlaySoloConfigView:Destroy()
	if self.spinnerConn then
		self.spinnerConn:Disconnect()
		self.spinnerConn = nil
	end
	for _, fn in ipairs(self.cleanups) do
		fn()
	end
	table.clear(self.cleanups)
	if self.root then
		self.root:Destroy()
	end
end

return PlaySoloConfigView
