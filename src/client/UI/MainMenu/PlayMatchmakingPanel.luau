--!strict
-- PlayMatchmakingPanel.luau
-- Tarjeta central: saludo dinámico "Bienvenido, Comandante {Player.DisplayName}",
-- fila CTA (PLAY SOLO #FFB344 + botón ? #232E47), y lista en vivo PUBLIC MATCHES
-- con contadores X / Max y temporizadores MM:SS reactivos cada segundo.

local Players = game:GetService("Players")
local MenuTheme = require(script.Parent:WaitForChild("MenuTheme"))
local PlaySoloConfigView = require(script.Parent:WaitForChild("PlaySoloConfigView"))

local PlayMatchmakingPanel = {}
PlayMatchmakingPanel.__index = PlayMatchmakingPanel

export type MatchEntryData = {
	id: string,
	title: string,
	prefixText: string,
	players: number,
	maxPlayers: number,
	secondsLeft: number,
	buttonText: string,
	featured: boolean,
	thumbKind: string,
}

export type PlayMatchmakingCallbacks = {
	OnPlaySoloClicked: (() -> ())?,
	OnStartSoloGame: ((mapId: string, difficulty: string) -> ())?,
	OnSoloHelpClicked: (() -> ())?,
	OnJoinMatchClicked: ((matchId: string, entry: MatchEntryData) -> ())?,
}

type MatchRowRefs = {
	data: MatchEntryData,
	statusLabel: TextLabel,
	joinBtn: TextButton,
}

export type PlayMatchmakingPanelInstance = {
	root: Frame,
	lobbyContent: Frame,
	soloConfigView: PlaySoloConfigView.PlaySoloConfigViewInstance,
	rows: { MatchRowRefs },
	cleanups: { () -> () },
	running: boolean,
	ShowSoloConfig: (self: PlayMatchmakingPanelInstance) -> (),
	ShowLobbyContent: (self: PlayMatchmakingPanelInstance) -> (),
	ShowDeploying: (self: PlayMatchmakingPanelInstance, onComplete: (() -> ())?) -> (),
	IsSoloConfigOpen: (self: PlayMatchmakingPanelInstance) -> boolean,
	UpdateMatchEntry: (self: PlayMatchmakingPanelInstance, matchId: string, players: number?, maxPlayers: number?, secondsLeft: number?) -> (),
	Destroy: (self: PlayMatchmakingPanelInstance) -> (),
}

local function buildThumbnail(parent: Instance, kind: string): Frame
	local thumb = Instance.new("Frame")
	thumb.Name = "MapThumb"
	thumb.Position = UDim2.fromOffset(10, 9)
	thumb.Size = UDim2.fromOffset(42, 42)
	thumb.BackgroundColor3 = Color3.fromHex("#0E1A2F")
	thumb.BorderSizePixel = 0
	thumb.ClipsDescendants = true
	thumb.ZIndex = 8
	thumb.Parent = parent

	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 8)
	tc.Parent = thumb

	local ts = Instance.new("UIStroke")
	ts.Color = if kind == "PUBLIC" then MenuTheme.Colors.CyanBorder else MenuTheme.Colors.CardStroke
	ts.Thickness = 1
	ts.Parent = thumb

	if kind == "PUBLIC" then
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.fromScale(1, 1)
		icon.BackgroundTransparency = 1
		icon.Font = MenuTheme.Fonts.Heading
		icon.Text = "👥"
		icon.TextColor3 = MenuTheme.Colors.CyanAccent
		icon.TextSize = 20
		icon.ZIndex = 9
		icon.Parent = thumb
	elseif kind == "WORLD" then
		-- Miniatura estilizada del mapa mundial
		local c1 = Instance.new("Frame")
		c1.Position = UDim2.fromScale(0.12, 0.20)
		c1.Size = UDim2.fromScale(0.30, 0.55)
		c1.BackgroundColor3 = Color3.fromHex("#34D399")
		c1.BorderSizePixel = 0
		c1.ZIndex = 9
		c1.Parent = thumb
		local c1c = Instance.new("UICorner")
		c1c.CornerRadius = UDim.new(0, 3)
		c1c.Parent = c1

		local c2 = Instance.new("Frame")
		c2.Position = UDim2.fromScale(0.50, 0.16)
		c2.Size = UDim2.fromScale(0.38, 0.62)
		c2.BackgroundColor3 = Color3.fromHex("#60A5FA")
		c2.BorderSizePixel = 0
		c2.ZIndex = 9
		c2.Parent = thumb
		local c2c = Instance.new("UICorner")
		c2c.CornerRadius = UDim.new(0, 3)
		c2c.Parent = c2
	else
		-- Miniatura estilizada de Norteamérica
		local na1 = Instance.new("Frame")
		na1.Position = UDim2.fromScale(0.18, 0.14)
		na1.Size = UDim2.fromScale(0.62, 0.36)
		na1.BackgroundColor3 = Color3.fromHex("#F59E0B")
		na1.BorderSizePixel = 0
		na1.ZIndex = 9
		na1.Parent = thumb
		local na1c = Instance.new("UICorner")
		na1c.CornerRadius = UDim.new(0, 4)
		na1c.Parent = na1

		local na2 = Instance.new("Frame")
		na2.Position = UDim2.fromScale(0.28, 0.52)
		na2.Size = UDim2.fromScale(0.42, 0.34)
		na2.BackgroundColor3 = Color3.fromHex("#38BDF8")
		na2.BorderSizePixel = 0
		na2.ZIndex = 9
		na2.Parent = thumb
		local na2c = Instance.new("UICorner")
		na2c.CornerRadius = UDim.new(0, 4)
		na2c.Parent = na2
	end

	return thumb
end

local function formatRowStatus(entry: MatchEntryData): string
	local timeStr = MenuTheme.formatMMSS(entry.secondsLeft)
	if entry.prefixText ~= "" then
		return string.format(
			"%s • %d / %d jugadores • comienza en %s",
			entry.prefixText,
			entry.players,
			entry.maxPlayers,
			timeStr
		)
	end
	return string.format("%d / %d jugadores • comienza en %s", entry.players, entry.maxPlayers, timeStr)
end

function PlayMatchmakingPanel.new(parent: Instance, callbacks: PlayMatchmakingCallbacks?): PlayMatchmakingPanelInstance
	local cb: PlayMatchmakingCallbacks = callbacks or {}
	local cleanups: { () -> () } = {}

	local root = Instance.new("Frame")
	root.Name = "PlayMatchmakingPanel"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 0.94, 0)
	root.Size = UDim2.fromOffset(560, 358)
	root.BackgroundColor3 = MenuTheme.Colors.CenterCardBg
	root.BackgroundTransparency = MenuTheme.Transparency.CenterCard
	root.BorderSizePixel = 0
	root.ZIndex = 6
	root.Parent = parent

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = MenuTheme.Corners.Card
	rootCorner.Parent = root

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = MenuTheme.Colors.CardStroke
	rootStroke.Thickness = 1
	rootStroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = root

	local lobbyContent = Instance.new("Frame")
	lobbyContent.Name = "LobbyContent"
	lobbyContent.Size = UDim2.fromScale(1, 1)
	lobbyContent.BackgroundTransparency = 1
	lobbyContent.Visible = true
	lobbyContent.ZIndex = 7
	lobbyContent.Parent = root

	-- Saludo dinámico: Bienvenido, Comandante {Player.DisplayName}
	local localPlayer = Players.LocalPlayer
	local displayName = if localPlayer and localPlayer.DisplayName ~= "" then localPlayer.DisplayName else "Jugador"

	local welcomeLabel = Instance.new("TextLabel")
	welcomeLabel.Name = "WelcomeLabel"
	welcomeLabel.Size = UDim2.new(1, 0, 0, 22)
	welcomeLabel.Position = UDim2.fromOffset(0, 0)
	welcomeLabel.BackgroundTransparency = 1
	welcomeLabel.Font = MenuTheme.Fonts.Bold
	welcomeLabel.Text = string.format("Bienvenido, Comandante %s", displayName)
	welcomeLabel.TextColor3 = MenuTheme.Colors.White
	welcomeLabel.TextSize = 15
	welcomeLabel.TextTruncate = Enum.TextTruncate.AtEnd
	welcomeLabel.ZIndex = 7
	welcomeLabel.Parent = lobbyContent

	-- Fila CTA principal: PLAY SOLO (~88%) + botón ? (~10%)
	local ctaRow = Instance.new("Frame")
	ctaRow.Name = "CTARow"
	ctaRow.Position = UDim2.fromOffset(0, 28)
	ctaRow.Size = UDim2.new(1, 0, 0, 46)
	ctaRow.BackgroundTransparency = 1
	ctaRow.ZIndex = 7
	ctaRow.Parent = lobbyContent

	local playSoloBtn = Instance.new("TextButton")
	playSoloBtn.Name = "BtnPlaySolo"
	playSoloBtn.Size = UDim2.new(0.885, 0, 1, 0)
	playSoloBtn.Position = UDim2.fromScale(0, 0)
	playSoloBtn.BackgroundColor3 = MenuTheme.Colors.PlaySoloBg
	playSoloBtn.AutoButtonColor = false
	playSoloBtn.Text = ""
	playSoloBtn.ZIndex = 8
	playSoloBtn.Parent = ctaRow

	local playCorner = Instance.new("UICorner")
	playCorner.CornerRadius = MenuTheme.Corners.CTA
	playCorner.Parent = playSoloBtn

	local playIcon = Instance.new("TextLabel")
	playIcon.Name = "PlayIcon"
	playIcon.Position = UDim2.fromOffset(18, 0)
	playIcon.Size = UDim2.new(0, 24, 1, 0)
	playIcon.BackgroundTransparency = 1
	playIcon.Font = MenuTheme.Fonts.Heading
	playIcon.Text = "▶"
	playIcon.TextColor3 = MenuTheme.Colors.DarkText
	playIcon.TextSize = 18
	playIcon.ZIndex = 9
	playIcon.Parent = playSoloBtn

	local playText = Instance.new("TextLabel")
	playText.Name = "PlayText"
	playText.Size = UDim2.fromScale(1, 1)
	playText.BackgroundTransparency = 1
	playText.Font = MenuTheme.Fonts.Heading
	playText.Text = "PLAY SOLO"
	playText.TextColor3 = MenuTheme.Colors.DarkText
	playText.TextSize = 17
	playText.ZIndex = 9
	playText.Parent = playSoloBtn

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(playSoloBtn, {
			hoverScale = 1.02,
			pressScale = 0.98,
			baseColor = MenuTheme.Colors.PlaySoloBg,
			hoverColor = MenuTheme.Colors.PlaySoloHover,
		})
	)

	-- Botón cuadrado (?) a la derecha (~10% del ancho) en fondo oscuro #232E47
	local soloHelpBtn = Instance.new("TextButton")
	soloHelpBtn.Name = "BtnSoloHelp"
	soloHelpBtn.AnchorPoint = Vector2.new(1, 0)
	soloHelpBtn.Position = UDim2.fromScale(1, 0)
	soloHelpBtn.Size = UDim2.new(0.095, 0, 1, 0)
	soloHelpBtn.BackgroundColor3 = MenuTheme.Colors.HelpBtnBg
	soloHelpBtn.AutoButtonColor = false
	soloHelpBtn.Font = MenuTheme.Fonts.Heading
	soloHelpBtn.Text = "?"
	soloHelpBtn.TextColor3 = MenuTheme.Colors.SubtleText
	soloHelpBtn.TextSize = 18
	soloHelpBtn.ZIndex = 8
	soloHelpBtn.Parent = ctaRow

	local helpCorner = Instance.new("UICorner")
	helpCorner.CornerRadius = MenuTheme.Corners.CTA
	helpCorner.Parent = soloHelpBtn

	local helpStroke = Instance.new("UIStroke")
	helpStroke.Color = MenuTheme.Colors.CardStroke
	helpStroke.Thickness = 1
	helpStroke.Parent = soloHelpBtn

	table.insert(
		cleanups,
		MenuTheme.applyButtonFX(soloHelpBtn, {
			stroke = helpStroke,
			hoverStrokeColor = MenuTheme.Colors.CyanAccent,
		})
	)

	soloHelpBtn.MouseButton1Click:Connect(function()
		if cb.OnSoloHelpClicked then
			cb.OnSoloHelpClicked()
		end
	end)

	-- Subtítulo de sección: PUBLIC MATCHES centrado, en #65C7EF, negrita
	local sectionLabel = Instance.new("TextLabel")
	sectionLabel.Name = "SectionPublicMatches"
	sectionLabel.Position = UDim2.fromOffset(0, 82)
	sectionLabel.Size = UDim2.new(1, 0, 0, 18)
	sectionLabel.BackgroundTransparency = 1
	sectionLabel.Font = MenuTheme.Fonts.Heading
	sectionLabel.Text = "PUBLIC MATCHES"
	sectionLabel.TextColor3 = MenuTheme.Colors.CyanAccent
	sectionLabel.TextSize = 11
	sectionLabel.ZIndex = 7
	sectionLabel.Parent = lobbyContent

	-- Contenedor de 3 tarjetas apiladas (UIListLayout, Padding = 10px)
	local listContainer = Instance.new("Frame")
	listContainer.Name = "MatchesList"
	listContainer.Position = UDim2.fromOffset(0, 106)
	listContainer.Size = UDim2.new(1, 0, 0, 220)
	listContainer.BackgroundTransparency = 1
	listContainer.ZIndex = 7
	listContainer.Parent = lobbyContent

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = listContainer

	local initialMatches: { MatchEntryData } = {
		{
			id = "PUBLIC_MATCH",
			title = "PUBLIC MATCH",
			prefixText = "Siguiente: América del Sur",
			players = 32,
			maxPlayers = 45,
			secondsLeft = 18,
			buttonText = "JOIN",
			featured = true,
			thumbKind = "PUBLIC",
		},
		{
			id = "WORLD",
			title = "WORLD",
			prefixText = "",
			players = 42,
			maxPlayers = 50,
			secondsLeft = 62,
			buttonText = "JOIN",
			featured = false,
			thumbKind = "WORLD",
		},
		{
			id = "NORTH_AMERICA",
			title = "NORTH AMERICA",
			prefixText = "Humanos contra naciones",
			players = 8,
			maxPlayers = 15,
			secondsLeft = 45,
			buttonText = "JOIN TEAMS",
			featured = false,
			thumbKind = "NORTH_AMERICA",
		},
	}

	local rows: { MatchRowRefs } = {}

	for idx, entry in ipairs(initialMatches) do
		local card = Instance.new("Frame")
		card.Name = "MatchCard_" .. entry.id
		card.LayoutOrder = idx
		card.Size = UDim2.new(1, 0, 0, 62)
		card.BackgroundColor3 = MenuTheme.Colors.CardRowBg
		card.BorderSizePixel = 0
		card.ZIndex = 7
		card.Parent = listContainer

		local cc = Instance.new("UICorner")
		cc.CornerRadius = MenuTheme.Corners.InnerCard
		cc.Parent = card

		local cs = Instance.new("UIStroke")
		cs.Color = if entry.featured then MenuTheme.Colors.CyanBorder else MenuTheme.Colors.CardStroke
		cs.Thickness = if entry.featured then 1.5 else 1
		cs.Parent = card

		buildThumbnail(card, entry.thumbKind)

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Name = "MatchTitle"
		titleLbl.Position = UDim2.fromOffset(62, 10)
		titleLbl.Size = UDim2.new(1, -185, 0, 20)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = MenuTheme.Fonts.Heading
		titleLbl.Text = entry.title
		titleLbl.TextColor3 = MenuTheme.Colors.White
		titleLbl.TextSize = 14
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
		titleLbl.ZIndex = 8
		titleLbl.Parent = card

		-- Punto verde de estado en vivo
		local dot = Instance.new("Frame")
		dot.Name = "LiveDot"
		dot.Position = UDim2.fromOffset(62, 38)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.BackgroundColor3 = MenuTheme.Colors.OnlineGreen
		dot.BorderSizePixel = 0
		dot.ZIndex = 8
		dot.Parent = card

		local dc = Instance.new("UICorner")
		dc.CornerRadius = MenuTheme.Corners.Pill
		dc.Parent = dot

		local statusLbl = Instance.new("TextLabel")
		statusLbl.Name = "StatusText"
		statusLbl.Position = UDim2.fromOffset(76, 33)
		statusLbl.Size = UDim2.new(1, -195, 0, 18)
		statusLbl.BackgroundTransparency = 1
		statusLbl.Font = MenuTheme.Fonts.Medium
		statusLbl.Text = formatRowStatus(entry)
		statusLbl.TextColor3 = MenuTheme.Colors.SubtleText
		statusLbl.TextSize = 11
		statusLbl.TextXAlignment = Enum.TextXAlignment.Left
		statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
		statusLbl.ZIndex = 8
		statusLbl.Parent = card

		-- Botón píldora a la derecha (JOIN / JOIN TEAMS)
		local joinBtn = Instance.new("TextButton")
		joinBtn.Name = "BtnJoin"
		joinBtn.AnchorPoint = Vector2.new(1, 0.5)
		joinBtn.Position = UDim2.new(1, -12, 0.5, 0)
		joinBtn.Size = UDim2.fromOffset(if entry.buttonText == "JOIN TEAMS" then 106 else 86, 32)
		joinBtn.BackgroundColor3 = Color3.fromHex("#132238")
		joinBtn.AutoButtonColor = false
		joinBtn.Font = MenuTheme.Fonts.Heading
		joinBtn.Text = entry.buttonText
		joinBtn.TextColor3 = MenuTheme.Colors.CyanBorder
		joinBtn.TextSize = 12
		joinBtn.ZIndex = 8
		joinBtn.Parent = card

		local jc = Instance.new("UICorner")
		jc.CornerRadius = MenuTheme.Corners.Pill
		jc.Parent = joinBtn

		local js = Instance.new("UIStroke")
		js.Color = MenuTheme.Colors.CyanBorder
		js.Thickness = 1.4
		js.Parent = joinBtn

		table.insert(
			cleanups,
			MenuTheme.applyButtonFX(joinBtn, {
				baseColor = Color3.fromHex("#132238"),
				hoverColor = Color3.fromHex("#1D3557"),
				stroke = js,
				baseStrokeColor = MenuTheme.Colors.CyanBorder,
				hoverStrokeColor = MenuTheme.Colors.White,
			})
		)

		local capturedEntry = entry
		joinBtn.MouseButton1Click:Connect(function()
			if cb.OnJoinMatchClicked then
				cb.OnJoinMatchClicked(capturedEntry.id, capturedEntry)
			end
		end)

		table.insert(rows, {
			data = entry,
			statusLabel = statusLbl,
			joinBtn = joinBtn,
		})
	end

	local soloConfigView: PlaySoloConfigView.PlaySoloConfigViewInstance
	local selfRef: PlayMatchmakingPanelInstance

	soloConfigView = PlaySoloConfigView.new(root, {
		OnBack = function()
			if selfRef then
				selfRef:ShowLobbyContent()
			end
		end,
		OnStartGame = function(mapId: string, difficulty: PlaySoloConfigView.SoloDifficulty)
			if cb.OnStartSoloGame then
				cb.OnStartSoloGame(mapId, difficulty)
			end
		end,
	})

	local self = setmetatable({
		root = root,
		lobbyContent = lobbyContent,
		soloConfigView = soloConfigView,
		rows = rows,
		cleanups = cleanups,
		running = true,
	}, PlayMatchmakingPanel)
	selfRef = (self :: any) :: PlayMatchmakingPanelInstance

	playSoloBtn.MouseButton1Click:Connect(function()
		self:ShowSoloConfig()
		if cb.OnPlaySoloClicked then
			cb.OnPlaySoloClicked()
		end
	end)

	-- Actualización reactiva cada segundo para temporizadores (MM:SS) y fluctuación realista de cola
	task.spawn(function()
		while self.running and self.root.Parent ~= nil do
			task.wait(1)
			if not self.running then
				break
			end
			for _, row in ipairs(self.rows) do
				local d = row.data
				d.secondsLeft -= 1
				if d.secondsLeft <= 0 then
					d.secondsLeft = 55 + math.random(0, 25)
					d.players = math.max(4, math.floor(d.maxPlayers * 0.45))
				else
					local delta = math.random(-1, 2)
					d.players = math.clamp(d.players + delta, 2, d.maxPlayers - 1)
				end
				row.statusLabel.Text = formatRowStatus(d)
			end
		end
	end)

	return (self :: any) :: PlayMatchmakingPanelInstance
end

function PlayMatchmakingPanel:ShowSoloConfig()
	self.lobbyContent.Visible = false
	self.soloConfigView:Show()
end

function PlayMatchmakingPanel:ShowLobbyContent()
	self.soloConfigView:Hide()
	self.lobbyContent.Visible = true
end

function PlayMatchmakingPanel:ShowDeploying(onComplete: (() -> ())?)
	self.lobbyContent.Visible = false
	self.soloConfigView:ShowDeploying(1.15, onComplete)
end

function PlayMatchmakingPanel:IsSoloConfigOpen(): boolean
	return self.soloConfigView.root.Visible
end

function PlayMatchmakingPanel:UpdateMatchEntry(
	matchId: string,
	players: number?,
	maxPlayers: number?,
	secondsLeft: number?
)
	for _, row in ipairs(self.rows) do
		if row.data.id == matchId then
			if players ~= nil then
				row.data.players = players
			end
			if maxPlayers ~= nil then
				row.data.maxPlayers = maxPlayers
			end
			if secondsLeft ~= nil then
				row.data.secondsLeft = secondsLeft
			end
			row.statusLabel.Text = formatRowStatus(row.data)
			break
		end
	end
end

function PlayMatchmakingPanel:Destroy()
	self.running = false
	for _, fn in ipairs(self.cleanups) do
		fn()
	end
	table.clear(self.cleanups)
	if self.soloConfigView then
		self.soloConfigView:Destroy()
	end
	if self.root then
		self.root:Destroy()
	end
end

return PlayMatchmakingPanel
