--!nonstrict
-- OpenFrontUI.lua
-- Réplica 1:1 de la interfaz completa de OpenFront.io (Alpha v0.36.9) para Roblox.
-- Contiene: Top Navbar, Identity Bar, Featured Card, Hero Buttons (SOLO / TUTORIAL),
-- Matches Queue (PRÓXIMA...), y el Modal de Selección de Mapas (#modal=single-player).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local OpenFrontUI = {}
OpenFrontUI.__index = OpenFrontUI

local function roundCorners(guiObj, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = guiObj
	return c
end

function OpenFrontUI.create(root, callbacks)
	callbacks = callbacks or {}

	local localPlayer = Players.LocalPlayer
	local commanderName = if localPlayer then (localPlayer.DisplayName or localPlayer.Name) else "AnonGoblin"

	local hubScreen = Instance.new("Frame")
	hubScreen.Name = "OpenFrontHubScreen"
	hubScreen.Size = UDim2.fromScale(1, 1)
	hubScreen.BackgroundColor3 = Color3.fromRGB(11, 15, 25)
	hubScreen.BorderSizePixel = 0
	hubScreen.Active = true
	hubScreen.ZIndex = 60
	hubScreen.Parent = root

	local bgGradient = Instance.new("UIGradient")
	bgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 21, 35)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(11, 15, 25)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 11, 18)),
	})
	bgGradient.Rotation = 45
	bgGradient.Parent = hubScreen

	-- ========================================================================
	-- TOP NAVBAR
	-- ========================================================================
	local navbar = Instance.new("Frame")
	navbar.Name = "OpenFrontNavbar"
	navbar.Size = UDim2.new(1, 0, 0, 52)
	navbar.Position = UDim2.fromOffset(0, 0)
	navbar.BackgroundColor3 = Color3.fromRGB(15, 20, 32)
	navbar.BorderSizePixel = 0
	navbar.ZIndex = 62
	navbar.Parent = hubScreen

	local navbarStroke = Instance.new("UIStroke")
	navbarStroke.Color = Color3.fromRGB(31, 41, 61)
	navbarStroke.Thickness = 1
	navbarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	navbarStroke.Parent = navbar

	local brandLogo = Instance.new("TextLabel")
	brandLogo.Name = "BrandLogo"
	brandLogo.Position = UDim2.fromOffset(24, 8)
	brandLogo.Size = UDim2.fromOffset(160, 22)
	brandLogo.BackgroundTransparency = 1
	brandLogo.Font = Enum.Font.GothamBlack
	brandLogo.Text = ">OPENFRONT<"
	brandLogo.TextColor3 = Color3.fromRGB(0, 229, 255)
	brandLogo.TextSize = 19
	brandLogo.TextXAlignment = Enum.TextXAlignment.Left
	brandLogo.ZIndex = 63
	brandLogo.Parent = navbar

	local brandVer = Instance.new("TextLabel")
	brandVer.Name = "BrandVersion"
	brandVer.Position = UDim2.fromOffset(24, 30)
	brandVer.Size = UDim2.fromOffset(80, 14)
	brandVer.BackgroundTransparency = 1
	brandVer.Font = Enum.Font.GothamBold
	brandVer.Text = "v0.36.9"
	brandVer.TextColor3 = Color3.fromRGB(113, 130, 157)
	brandVer.TextSize = 9
	brandVer.TextXAlignment = Enum.TextXAlignment.Left
	brandVer.ZIndex = 63
	brandVer.Parent = navbar

	local navTabs = Instance.new("Frame")
	navTabs.Name = "NavTabs"
	navTabs.Position = UDim2.fromOffset(200, 0)
	navTabs.Size = UDim2.fromOffset(480, 52)
	navTabs.BackgroundTransparency = 1
	navTabs.ZIndex = 63
	navTabs.Parent = navbar

	local tabListLayout = Instance.new("UIListLayout")
	tabListLayout.FillDirection = Enum.FillDirection.Horizontal
	tabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabListLayout.Padding = UDim.new(0, 24)
	tabListLayout.Parent = navTabs

	local function makeNavTab(text, active, hasBadge)
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. text
		tab.Size = UDim2.fromOffset(text == "JUGAR" and 65 or 90, 52)
		tab.BackgroundTransparency = 1
		tab.Font = Enum.Font.GothamBlack
		tab.Text = text
		tab.TextColor3 = if active then Color3.fromRGB(0, 229, 255) else Color3.fromRGB(138, 153, 173)
		tab.TextSize = 13
		tab.ZIndex = 64
		tab.Parent = navTabs

		if active then
			local underline = Instance.new("Frame")
			underline.Size = UDim2.new(1, 0, 0, 3)
			underline.Position = UDim2.new(0, 0, 1, -3)
			underline.BackgroundColor3 = Color3.fromRGB(0, 229, 255)
			underline.BorderSizePixel = 0
			underline.ZIndex = 65
			underline.Parent = tab
		end

		if hasBadge then
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(6, 6)
			dot.Position = UDim2.new(1, -6, 0, 14)
			dot.BackgroundColor3 = Color3.fromRGB(255, 59, 48)
			dot.BorderSizePixel = 0
			dot.ZIndex = 65
			dot.Parent = tab
			roundCorners(dot, 3)
		end
		return tab
	end

	makeNavTab("JUGAR", true, false)
	makeNavTab("TIENDA", false, true)
	makeNavTab("INVENTARIO", false, false)
	makeNavTab("CLASIFICACIÓN", false, false)
	makeNavTab("CLANES", false, false)

	local rightNav = Instance.new("Frame")
	rightNav.Name = "RightNav"
	rightNav.AnchorPoint = Vector2.new(1, 0.5)
	rightNav.Position = UDim2.new(1, -24, 0.5, 0)
	rightNav.Size = UDim2.fromOffset(260, 38)
	rightNav.BackgroundTransparency = 1
	rightNav.ZIndex = 63
	rightNav.Parent = navbar

	local rightNavLayout = Instance.new("UIListLayout")
	rightNavLayout.FillDirection = Enum.FillDirection.Horizontal
	rightNavLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rightNavLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rightNavLayout.Padding = UDim.new(0, 12)
	rightNavLayout.Parent = rightNav

	local function makeNavIconBtn(icon, cb)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(32, 32)
		b.BackgroundColor3 = Color3.fromRGB(22, 32, 50)
		b.Font = Enum.Font.GothamBold
		b.Text = icon
		b.TextColor3 = Color3.fromRGB(200, 215, 235)
		b.TextSize = 14
		b.ZIndex = 64
		b.Parent = rightNav
		roundCorners(b, 6)
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(43, 59, 82)
		st.Thickness = 1
		st.Parent = b
		if cb then b.MouseButton1Click:Connect(cb) end
		return b
	end

	makeNavIconBtn("🔔", function() if callbacks.onNotify then callbacks.onNotify("Sin notificaciones nuevas") end end)
	makeNavIconBtn("❓", function() if callbacks.onHelp then callbacks.onHelp() end end)
	makeNavIconBtn("⚙", function() if callbacks.onSettings then callbacks.onSettings() end end)

	local userPill = Instance.new("Frame")
	userPill.Name = "UserPill"
	userPill.Size = UDim2.fromOffset(130, 32)
	userPill.BackgroundColor3 = Color3.fromRGB(22, 32, 50)
	userPill.BorderSizePixel = 0
	userPill.ZIndex = 64
	userPill.Parent = rightNav
	roundCorners(userPill, 6)
	local userPillStroke = Instance.new("UIStroke")
	userPillStroke.Color = Color3.fromRGB(43, 59, 82)
	userPillStroke.Thickness = 1
	userPillStroke.Parent = userPill

	local userPillText = Instance.new("TextLabel")
	userPillText.Size = UDim2.fromScale(1, 1)
	userPillText.BackgroundTransparency = 1
	userPillText.Font = Enum.Font.GothamBold
	userPillText.Text = "👤 " .. string.sub(commanderName, 1, 12)
	userPillText.TextColor3 = Color3.fromRGB(230, 240, 255)
	userPillText.TextSize = 11
	userPillText.ZIndex = 65
	userPillText.Parent = userPill

	-- Botón salir / volver a la partida
	local btnCloseHub = Instance.new("TextButton")
	btnCloseHub.AnchorPoint = Vector2.new(1, 0)
	btnCloseHub.Position = UDim2.new(1, -16, 0, 12)
	btnCloseHub.Size = UDim2.fromOffset(28, 28)
	btnCloseHub.BackgroundColor3 = Color3.fromRGB(200, 45, 45)
	btnCloseHub.Font = Enum.Font.GothamBlack
	btnCloseHub.Text = "✕"
	btnCloseHub.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnCloseHub.TextSize = 13
	btnCloseHub.Visible = false
	btnCloseHub.ZIndex = 70
	btnCloseHub.Parent = navbar
	roundCorners(btnCloseHub, 6)

	-- ========================================================================
	-- CONTENIDO CENTRAL
	-- ========================================================================
	local hubContainer = Instance.new("Frame")
	hubContainer.Name = "HubContainer"
	hubContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	hubContainer.Position = UDim2.new(0.5, 0, 0.54, 0)
	hubContainer.Size = UDim2.fromOffset(1020, 520)
	hubContainer.BackgroundTransparency = 1
	hubContainer.ZIndex = 62
	hubContainer.Parent = hubScreen

	local hubScale = Instance.new("UIScale")
	hubScale.Parent = hubContainer
	local function fitHub()
		local vs = root.AbsoluteSize
		if vs.X > 0 and vs.Y > 0 then
			hubScale.Scale = math.clamp(math.min(vs.X / 1080, vs.Y / 620), 0.45, 1.15)
		end
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHub)
	fitHub()

	-- Identity Bar
	local identityBar = Instance.new("Frame")
	identityBar.Name = "IdentityBar"
	identityBar.Position = UDim2.fromOffset(0, 0)
	identityBar.Size = UDim2.new(1, 0, 0, 42)
	identityBar.BackgroundColor3 = Color3.fromRGB(15, 22, 35)
	identityBar.BorderSizePixel = 0
	identityBar.ZIndex = 63
	identityBar.Parent = hubContainer
	roundCorners(identityBar, 10)
	local idStroke = Instance.new("UIStroke")
	idStroke.Color = Color3.fromRGB(34, 49, 74)
	idStroke.Thickness = 1
	idStroke.Parent = identityBar

	local clanBtn = Instance.new("TextButton")
	clanBtn.Name = "ClanBtn"
	clanBtn.Position = UDim2.fromOffset(8, 6)
	clanBtn.Size = UDim2.fromOffset(110, 30)
	clanBtn.BackgroundColor3 = Color3.fromRGB(22, 32, 50)
	clanBtn.Font = Enum.Font.GothamBlack
	clanBtn.Text = "ETIQUETA ▾"
	clanBtn.TextColor3 = Color3.fromRGB(160, 180, 205)
	clanBtn.TextSize = 11
	clanBtn.ZIndex = 64
	clanBtn.Parent = identityBar
	roundCorners(clanBtn, 6)

	local userBox = Instance.new("TextBox")
	userBox.Name = "UserBox"
	userBox.Position = UDim2.fromOffset(126, 6)
	userBox.Size = UDim2.fromOffset(240, 30)
	userBox.BackgroundColor3 = Color3.fromRGB(10, 15, 25)
	userBox.Font = Enum.Font.GothamBlack
	userBox.Text = commanderName
	userBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	userBox.TextSize = 13
	userBox.ClearTextOnFocus = false
	userBox.ZIndex = 64
	userBox.Parent = identityBar
	roundCorners(userBox, 6)

	local randomNames = { "AnonGoblin3", "CyberVanguard", "TerraNova", "SolarisPrime", "HexCommander", "AuraStriker" }
	local diceBtn = Instance.new("TextButton")
	diceBtn.Name = "DiceBtn"
	diceBtn.Position = UDim2.fromOffset(372, 6)
	diceBtn.Size = UDim2.fromOffset(32, 30)
	diceBtn.BackgroundColor3 = Color3.fromRGB(22, 32, 50)
	diceBtn.Font = Enum.Font.GothamBold
	diceBtn.Text = "🎲"
	diceBtn.TextSize = 15
	diceBtn.ZIndex = 64
	diceBtn.Parent = identityBar
	roundCorners(diceBtn, 6)
	diceBtn.MouseButton1Click:Connect(function()
		userBox.Text = randomNames[math.random(1, #randomNames)]
	end)

	local verifiedPill = Instance.new("TextButton")
	verifiedPill.Name = "VerifiedPill"
	verifiedPill.AnchorPoint = Vector2.new(1, 0.5)
	verifiedPill.Position = UDim2.new(1, -12, 0.5, 0)
	verifiedPill.Size = UDim2.fromOffset(140, 28)
	verifiedPill.BackgroundColor3 = Color3.fromRGB(20, 30, 48)
	verifiedPill.Font = Enum.Font.GothamBold
	verifiedPill.Text = "✔ Usar verificado"
	verifiedPill.TextColor3 = Color3.fromRGB(0, 220, 150)
	verifiedPill.TextSize = 11
	verifiedPill.ZIndex = 64
	verifiedPill.Parent = identityBar
	roundCorners(verifiedPill, 6)

	-- Left Col (Featured card + Buttons)
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftCol"
	leftCol.Position = UDim2.fromOffset(0, 52)
	leftCol.Size = UDim2.fromOffset(590, 460)
	leftCol.BackgroundTransparency = 1
	leftCol.ZIndex = 63
	leftCol.Parent = hubContainer

	local featCard = Instance.new("Frame")
	featCard.Name = "FeaturedCard"
	featCard.Position = UDim2.fromOffset(0, 0)
	featCard.Size = UDim2.new(1, 0, 0, 240)
	featCard.BackgroundColor3 = Color3.fromRGB(16, 24, 38)
	featCard.BorderSizePixel = 0
	featCard.ZIndex = 64
	featCard.Parent = leftCol
	roundCorners(featCard, 12)
	local featStroke = Instance.new("UIStroke")
	featStroke.Color = Color3.fromRGB(34, 49, 74)
	featStroke.Thickness = 1
	featStroke.Parent = featCard

	local badgeCompact = Instance.new("TextLabel")
	badgeCompact.Position = UDim2.fromOffset(12, 12)
	badgeCompact.Size = UDim2.fromOffset(120, 24)
	badgeCompact.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
	badgeCompact.Font = Enum.Font.GothamBlack
	badgeCompact.Text = "MAPA COMPACTO"
	badgeCompact.TextColor3 = Color3.fromRGB(255, 255, 255)
	badgeCompact.TextSize = 10
	badgeCompact.ZIndex = 66
	badgeCompact.Parent = featCard
	roundCorners(badgeCompact, 6)

	local timerBadge = Instance.new("TextLabel")
	timerBadge.AnchorPoint = Vector2.new(1, 0)
	timerBadge.Position = UDim2.new(1, -12, 0, 12)
	timerBadge.Size = UDim2.fromOffset(80, 24)
	timerBadge.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
	timerBadge.Font = Enum.Font.GothamBlack
	timerBadge.Text = "1min 57s"
	timerBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	timerBadge.TextSize = 10
	timerBadge.ZIndex = 66
	timerBadge.Parent = featCard
	roundCorners(timerBadge, 6)

	local playersBadge = Instance.new("TextLabel")
	playersBadge.AnchorPoint = Vector2.new(1, 1)
	playersBadge.Position = UDim2.new(1, -12, 1, -12)
	playersBadge.Size = UDim2.fromOffset(70, 24)
	playersBadge.BackgroundColor3 = Color3.fromRGB(15, 22, 35)
	playersBadge.Font = Enum.Font.GothamBlack
	playersBadge.Text = "👥 9/13"
	playersBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	playersBadge.TextSize = 11
	playersBadge.ZIndex = 66
	playersBadge.Parent = featCard
	roundCorners(playersBadge, 6)

	local featTitle = Instance.new("TextLabel")
	featTitle.Position = UDim2.fromOffset(16, 175)
	featTitle.Size = UDim2.fromOffset(360, 24)
	featTitle.BackgroundTransparency = 1
	featTitle.Font = Enum.Font.GothamBlack
	featTitle.Text = "MUNDO / ACHIRAN"
	featTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	featTitle.TextSize = 20
	featTitle.TextXAlignment = Enum.TextXAlignment.Left
	featTitle.ZIndex = 66
	featTitle.Parent = featCard

	local featSub = Instance.new("TextLabel")
	featSub.Position = UDim2.fromOffset(16, 202)
	featSub.Size = UDim2.fromOffset(360, 16)
	featSub.BackgroundTransparency = 1
	featSub.Font = Enum.Font.GothamBold
	featSub.Text = "TODOS CONTRA TODOS (FFA)"
	featSub.TextColor3 = Color3.fromRGB(160, 180, 205)
	featSub.TextSize = 12
	featSub.TextXAlignment = Enum.TextXAlignment.Left
	featSub.ZIndex = 66
	featSub.Parent = featCard

	-- Hero Row: SOLO y TUTORIAL
	local heroRow = Instance.new("Frame")
	heroRow.Name = "HeroRow"
	heroRow.Position = UDim2.fromOffset(0, 252)
	heroRow.Size = UDim2.new(1, 0, 0, 52)
	heroRow.BackgroundTransparency = 1
	heroRow.ZIndex = 64
	heroRow.Parent = leftCol

	local btnSolo = Instance.new("TextButton")
	btnSolo.Name = "BtnSolo"
	btnSolo.Size = UDim2.new(0.58, -6, 1, 0)
	btnSolo.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
	btnSolo.Font = Enum.Font.GothamBlack
	btnSolo.Text = "SOLO"
	btnSolo.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnSolo.TextSize = 17
	btnSolo.ZIndex = 65
	btnSolo.Parent = heroRow
	roundCorners(btnSolo, 10)

	local btnTutorial = Instance.new("TextButton")
	btnTutorial.Name = "BtnTutorial"
	btnTutorial.Position = UDim2.new(0.58, 6, 0, 0)
	btnTutorial.Size = UDim2.new(0.42, -6, 1, 0)
	btnTutorial.BackgroundColor3 = Color3.fromRGB(250, 190, 0)
	btnTutorial.Font = Enum.Font.GothamBlack
	btnTutorial.Text = "TUTORIAL"
	btnTutorial.TextColor3 = Color3.fromRGB(20, 24, 34)
	btnTutorial.TextSize = 17
	btnTutorial.ZIndex = 65
	btnTutorial.Parent = heroRow
	roundCorners(btnTutorial, 10)

	-- Secondary Row: CREAR LOBBY, CLASIFICATORIO, UNIRSE AL LOBBY
	local subRow = Instance.new("Frame")
	subRow.Name = "SubRow"
	subRow.Position = UDim2.fromOffset(0, 314)
	subRow.Size = UDim2.new(1, 0, 0, 44)
	subRow.BackgroundTransparency = 1
	subRow.ZIndex = 64
	subRow.Parent = leftCol

	local function makeSubBtn(text, cb)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.333, -7, 1, 0)
		b.BackgroundColor3 = Color3.fromRGB(18, 26, 42)
		b.Font = Enum.Font.GothamBlack
		b.Text = text
		b.TextColor3 = Color3.fromRGB(230, 240, 255)
		b.TextSize = 11
		b.ZIndex = 65
		b.Parent = subRow
		roundCorners(b, 8)
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(34, 49, 74)
		st.Thickness = 1
		st.Parent = b
		if cb then b.MouseButton1Click:Connect(cb) end
		return b
	end

	makeSubBtn("CREAR LOBBY", function()
		if callbacks.onNotify then callbacks.onNotify("Lobby personalizado listo") end
	end)
	makeSubBtn("CLASIFICATORIO", function()
		if callbacks.onNotify then callbacks.onNotify("Modo Clasificatorio ELO") end
	end)
	makeSubBtn("UNIRSE AL LOBBY", function()
		if callbacks.onNotify then callbacks.onNotify("Buscando lobbies...") end
	end)

	-- Right Col (Matches Queue)
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightCol"
	rightCol.Position = UDim2.fromOffset(604, 52)
	rightCol.Size = UDim2.fromOffset(416, 460)
	rightCol.BackgroundTransparency = 1
	rightCol.ZIndex = 63
	rightCol.Parent = hubContainer

	local matchHeader = Instance.new("Frame")
	matchHeader.Size = UDim2.new(1, 0, 0, 24)
	matchHeader.BackgroundTransparency = 1
	matchHeader.ZIndex = 64
	matchHeader.Parent = rightCol

	local prxTitle = Instance.new("TextLabel")
	prxTitle.Size = UDim2.fromOffset(120, 24)
	prxTitle.BackgroundTransparency = 1
	prxTitle.Font = Enum.Font.GothamBlack
	prxTitle.Text = "PRÓXIMA..."
	prxTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	prxTitle.TextSize = 13
	prxTitle.TextXAlignment = Enum.TextXAlignment.Left
	prxTitle.ZIndex = 65
	prxTitle.Parent = matchHeader

	local verTodosBtn = Instance.new("TextButton")
	verTodosBtn.AnchorPoint = Vector2.new(1, 0)
	verTodosBtn.Position = UDim2.new(1, 0, 0, 0)
	verTodosBtn.Size = UDim2.fromOffset(120, 24)
	verTodosBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
	verTodosBtn.Font = Enum.Font.GothamBlack
	verTodosBtn.Text = "VER TODOS 18 >"
	verTodosBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	verTodosBtn.TextSize = 11
	verTodosBtn.ZIndex = 65
	verTodosBtn.Parent = matchHeader
	roundCorners(verTodosBtn, 6)

	local matchesScroll = Instance.new("ScrollingFrame")
	matchesScroll.Position = UDim2.fromOffset(0, 32)
	matchesScroll.Size = UDim2.new(1, 0, 1, -32)
	matchesScroll.BackgroundTransparency = 1
	matchesScroll.BorderSizePixel = 0
	matchesScroll.ScrollBarThickness = 4
	matchesScroll.ZIndex = 64
	matchesScroll.Parent = rightCol

	local matchesLayout = Instance.new("UIListLayout")
	matchesLayout.Padding = UDim.new(0, 10)
	matchesLayout.Parent = matchesScroll

	local function makeMatchCard(modeId, badgeTxt, badgeCol, timeTxt, playersTxt, titleTxt, subTxt)
		local c = Instance.new("TextButton")
		c.Name = "Match_" .. modeId
		c.Size = UDim2.new(1, -6, 0, 94)
		c.BackgroundColor3 = Color3.fromRGB(16, 24, 38)
		c.BorderSizePixel = 0
		c.Text = ""
		c.ZIndex = 65
		c.Parent = matchesScroll
		roundCorners(c, 10)
		local cst = Instance.new("UIStroke")
		cst.Color = Color3.fromRGB(34, 49, 74)
		cst.Thickness = 1
		cst.Parent = c

		if badgeTxt then
			local bg = Instance.new("TextLabel")
			bg.Position = UDim2.fromOffset(10, 8)
			bg.Size = UDim2.fromOffset(68, 20)
			bg.BackgroundColor3 = badgeCol or Color3.fromRGB(255, 120, 0)
			bg.Font = Enum.Font.GothamBlack
			bg.Text = badgeTxt
			bg.TextColor3 = Color3.fromRGB(255, 255, 255)
			bg.TextSize = 9
			bg.ZIndex = 66
			bg.Parent = c
			roundCorners(bg, 4)
		end

		local tm = Instance.new("TextLabel")
		tm.AnchorPoint = Vector2.new(1, 0)
		tm.Position = UDim2.new(1, -10, 0, 8)
		tm.Size = UDim2.fromOffset(60, 20)
		tm.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
		tm.Font = Enum.Font.GothamBlack
		tm.Text = timeTxt
		tm.TextColor3 = Color3.fromRGB(255, 255, 255)
		tm.TextSize = 10
		tm.ZIndex = 66
		tm.Parent = c
		roundCorners(tm, 4)

		local pl = Instance.new("TextLabel")
		pl.AnchorPoint = Vector2.new(1, 1)
		pl.Position = UDim2.new(1, -10, 1, -10)
		pl.Size = UDim2.fromOffset(80, 20)
		pl.BackgroundColor3 = Color3.fromRGB(12, 18, 28)
		pl.Font = Enum.Font.GothamBold
		pl.Text = "👥 " .. playersTxt
		pl.TextColor3 = Color3.fromRGB(255, 255, 255)
		pl.TextSize = 10
		pl.ZIndex = 66
		pl.Parent = c
		roundCorners(pl, 4)

		local ttl = Instance.new("TextLabel")
		ttl.Position = UDim2.fromOffset(10, 36)
		ttl.Size = UDim2.new(1, -100, 0, 20)
		ttl.BackgroundTransparency = 1
		ttl.Font = Enum.Font.GothamBlack
		ttl.Text = titleTxt
		ttl.TextColor3 = Color3.fromRGB(255, 255, 255)
		ttl.TextSize = 14
		ttl.TextXAlignment = Enum.TextXAlignment.Left
		ttl.ZIndex = 66
		ttl.Parent = c

		local subt = Instance.new("TextLabel")
		subt.Position = UDim2.fromOffset(10, 58)
		subt.Size = UDim2.new(1, -100, 0, 16)
		subt.BackgroundTransparency = 1
		subt.Font = Enum.Font.GothamBold
		subt.Text = subTxt
		subt.TextColor3 = Color3.fromRGB(140, 160, 185)
		subt.TextSize = 11
		subt.TextXAlignment = Enum.TextXAlignment.Left
		subt.ZIndex = 66
		subt.Parent = c

		c.MouseButton1Click:Connect(function()
			if callbacks.onLaunchGame then
				callbacks.onLaunchGame("EARTH", 35, "NORMAL", modeId)
			end
		end)
		return c
	end

	makeMatchCard("TEAMS_2", "CUSTOM", Color3.fromRGB(255, 107, 0), "56s", "74/200", "BAIKAL (GUERRA NUCLEAR)", "2 EQUIPOS DE 100")
	makeMatchCard("CONTINENTS", nil, nil, "30s", "86/95", "RUSIA", "5 EQUIPOS DE 19")
	makeMatchCard("BLITZ", "RÁPIDO", Color3.fromRGB(0, 200, 83), "1m 15s", "15/30", "MODO RÁPIDO (BLITZ)", "ECONOMÍA X2.5")

	-- ========================================================================
	-- MODAL DE SELECCIÓN DE MAPA SOLO (#modal=single-player en OpenFront.io)
	-- ========================================================================
	local soloModal = Instance.new("Frame")
	soloModal.Name = "OpenFrontSoloModal"
	soloModal.AnchorPoint = Vector2.new(0.5, 0.5)
	soloModal.Position = UDim2.fromScale(0.5, 0.5)
	soloModal.Size = UDim2.fromOffset(680, 510)
	soloModal.BackgroundColor3 = Color3.fromRGB(15, 22, 35)
	soloModal.BorderSizePixel = 0
	soloModal.Visible = false
	soloModal.ZIndex = 80
	soloModal.Parent = hubScreen
	roundCorners(soloModal, 14)
	local soloModalStroke = Instance.new("UIStroke")
	soloModalStroke.Color = Color3.fromRGB(34, 49, 74)
	soloModalStroke.Thickness = 1
	soloModalStroke.Parent = soloModal

	local soloHeader = Instance.new("Frame")
	soloHeader.Size = UDim2.new(1, 0, 0, 48)
	soloHeader.BackgroundTransparency = 1
	soloHeader.ZIndex = 81
	soloHeader.Parent = soloModal

	local btnBackSolo = Instance.new("TextButton")
	btnBackSolo.Position = UDim2.fromOffset(16, 10)
	btnBackSolo.Size = UDim2.fromOffset(100, 28)
	btnBackSolo.BackgroundColor3 = Color3.fromRGB(25, 36, 56)
	btnBackSolo.Font = Enum.Font.GothamBlack
	btnBackSolo.Text = "←  SOLO"
	btnBackSolo.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnBackSolo.TextSize = 13
	btnBackSolo.ZIndex = 82
	btnBackSolo.Parent = soloHeader
	roundCorners(btnBackSolo, 6)
	btnBackSolo.MouseButton1Click:Connect(function()
		soloModal.Visible = false
	end)

	local searchBox = Instance.new("TextBox")
	searchBox.Position = UDim2.new(1, -220, 0, 10)
	searchBox.Size = UDim2.fromOffset(204, 28)
	searchBox.BackgroundColor3 = Color3.fromRGB(20, 28, 44)
	searchBox.BorderSizePixel = 0
	searchBox.Font = Enum.Font.Gotham
	searchBox.PlaceholderText = "🔍 Buscar mapas..."
	searchBox.PlaceholderColor3 = Color3.fromRGB(110, 130, 160)
	searchBox.Text = ""
	searchBox.TextColor3 = Color3.fromRGB(240, 245, 255)
	searchBox.TextSize = 11
	searchBox.ZIndex = 82
	searchBox.Parent = soloHeader
	roundCorners(searchBox, 6)
	local sbStroke = Instance.new("UIStroke")
	sbStroke.Color = Color3.fromRGB(34, 49, 74)
	sbStroke.Thickness = 1
	sbStroke.Parent = searchBox

	local mapTabsRow = Instance.new("Frame")
	mapTabsRow.Position = UDim2.fromOffset(16, 54)
	mapTabsRow.Size = UDim2.new(1, -32, 0, 34)
	mapTabsRow.BackgroundColor3 = Color3.fromRGB(10, 15, 25)
	mapTabsRow.BorderSizePixel = 0
	mapTabsRow.ZIndex = 81
	mapTabsRow.Parent = soloModal
	roundCorners(mapTabsRow, 8)

	local currentTab = "DESTACADO"
	local tabButtons = {}
	local function updateTabStyles()
		for name, btn in pairs(tabButtons) do
			local isActive = (name == currentTab)
			btn.TextColor3 = if isActive then Color3.fromRGB(0, 229, 255) else Color3.fromRGB(130, 150, 175)
			btn.BackgroundColor3 = if isActive then Color3.fromRGB(20, 36, 58) else Color3.fromRGB(10, 15, 25)
			btn.BackgroundTransparency = if isActive then 0 else 1
		end
	end

	local mapsGrid = Instance.new("ScrollingFrame")
	mapsGrid.Position = UDim2.fromOffset(16, 96)
	mapsGrid.Size = UDim2.new(1, -32, 0, 330)
	mapsGrid.BackgroundTransparency = 1
	mapsGrid.BorderSizePixel = 0
	mapsGrid.ScrollBarThickness = 4
	mapsGrid.ZIndex = 81
	mapsGrid.Parent = soloModal

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(204, 100)
	gridLayout.CellPadding = UDim2.fromOffset(12, 12)
	gridLayout.Parent = mapsGrid

	local selectedSoloPlanet = "WORLD"
	local SOLO_MAPS = {
		{ id = "WORLD", name = "MUNDO", tag = "POPULAR", desc = "61 Naciones · Global FFA", tab = "DESTACADO", icon = "🌐" },
		{ id = "EUROPE", name = "EUROPA", tag = "CLÁSICO", desc = "49 Naciones · Alta Densidad", tab = "DESTACADO", icon = "🏰" },
		{ id = "ASIA", name = "ASIA", tag = "BATALLA", desc = "25 Naciones · Potencias", tab = "DESTACADO", icon = "🏯" },
		{ id = "AFRICA", name = "ÁFRICA", tag = "ESTRATÉGICO", desc = "36 Naciones · Recursos", tab = "DESTACADO", icon = "🦁" },
		{ id = "PANGAEA", name = "PANGAEA", tag = "GIGANTE", desc = "Supercontinente Continuo", tab = "TODO", icon = "🦖" },
		{ id = "MARS", name = "MARTE", tag = "ESPACIAL", desc = "Planeta Rojo Marciano", tab = "TODO", icon = "🔴" },
		{ id = "OCEANIA", name = "OCEANÍA", tag = "ISLAS", desc = "32 Naciones · Guerra Naval", tab = "TODO", icon = "🏝️" },
		{ id = "MENA", name = "MEDIO ORIENTE", tag = "TÁCTICO", desc = "35 Naciones · Petróleo", tab = "TODO", icon = "🏜️" },
	}

	local mapCardFrames = {}
	local function filterMapCards()
		local query = string.lower(string.gsub(searchBox.Text, "^%s*(.-)%s*$", "%1"))
		for _, sm in ipairs(SOLO_MAPS) do
			local refs = mapCardFrames[sm.id]
			if refs then
				local matchTab = (currentTab == "TODO" or currentTab == "ATLAS" or sm.tab == currentTab)
				local matchSearch = (query == "" or string.find(string.lower(sm.name), query, 1, true) ~= nil or string.find(string.lower(sm.desc), query, 1, true) ~= nil)
				refs.card.Visible = matchTab and matchSearch
			end
		end
	end

	local function makeMapTab(name, posIdx)
		local t = Instance.new("TextButton")
		t.Position = UDim2.fromOffset(8 + (posIdx - 1) * 122, 4)
		t.Size = UDim2.fromOffset(116, 26)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.Text = name
		t.TextColor3 = if name == currentTab then Color3.fromRGB(0, 229, 255) else Color3.fromRGB(130, 150, 175)
		t.TextSize = 11
		t.ZIndex = 82
		t.Parent = mapTabsRow
		roundCorners(t, 6)
		tabButtons[name] = t

		t.MouseButton1Click:Connect(function()
			currentTab = name
			updateTabStyles()
			filterMapCards()
		end)
		return t
	end
	makeMapTab("DESTACADO", 1)
	makeMapTab("TODO", 2)
	makeMapTab("ATLAS", 3)
	makeMapTab("FAVORITOS", 4)
	updateTabStyles()

	searchBox:GetPropertyChangedSignal("Text"):Connect(filterMapCards)

	for _, sm in ipairs(SOLO_MAPS) do
		local mc = Instance.new("TextButton")
		mc.Name = "MapCard_" .. sm.id
		mc.BackgroundColor3 = if sm.id == selectedSoloPlanet then Color3.fromRGB(15, 45, 75) else Color3.fromRGB(20, 30, 48)
		mc.BorderSizePixel = 0
		mc.Text = ""
		mc.ZIndex = 82
		mc.Parent = mapsGrid
		roundCorners(mc, 8)

		local mcStroke = Instance.new("UIStroke")
		mcStroke.Color = if sm.id == selectedSoloPlanet then Color3.fromRGB(0, 229, 255) else Color3.fromRGB(34, 49, 74)
		mcStroke.Thickness = if sm.id == selectedSoloPlanet then 2 else 1
		mcStroke.Parent = mc

		local smTitle = Instance.new("TextLabel")
		smTitle.Position = UDim2.fromOffset(12, 10)
		smTitle.Size = UDim2.new(1, -24, 0, 20)
		smTitle.BackgroundTransparency = 1
		smTitle.Font = Enum.Font.GothamBlack
		smTitle.Text = sm.icon .. " " .. sm.name
		smTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		smTitle.TextSize = 13
		smTitle.TextXAlignment = Enum.TextXAlignment.Left
		smTitle.ZIndex = 83
		smTitle.Parent = mc

		local smTag = Instance.new("TextLabel")
		smTag.Position = UDim2.fromOffset(12, 34)
		smTag.Size = UDim2.fromOffset(74, 18)
		smTag.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
		smTag.Font = Enum.Font.GothamBold
		smTag.Text = sm.tag
		smTag.TextColor3 = Color3.fromRGB(255, 255, 255)
		smTag.TextSize = 9
		smTag.ZIndex = 83
		smTag.Parent = mc
		roundCorners(smTag, 4)

		local smDesc = Instance.new("TextLabel")
		smDesc.Position = UDim2.fromOffset(12, 58)
		smDesc.Size = UDim2.new(1, -24, 0, 32)
		smDesc.BackgroundTransparency = 1
		smDesc.Font = Enum.Font.Gotham
		smDesc.Text = sm.desc
		smDesc.TextColor3 = Color3.fromRGB(140, 165, 195)
		smDesc.TextSize = 10
		smDesc.TextXAlignment = Enum.TextXAlignment.Left
		smDesc.TextWrapped = true
		smDesc.ZIndex = 83
		smDesc.Parent = mc

		mapCardFrames[sm.id] = { card = mc, stroke = mcStroke }

		mc.MouseButton1Click:Connect(function()
			selectedSoloPlanet = sm.id
			for id, refs in pairs(mapCardFrames) do
				refs.card.BackgroundColor3 = if id == selectedSoloPlanet then Color3.fromRGB(15, 45, 75) else Color3.fromRGB(20, 30, 48)
				refs.stroke.Color = if id == selectedSoloPlanet then Color3.fromRGB(0, 229, 255) else Color3.fromRGB(34, 49, 74)
				refs.stroke.Thickness = if id == selectedSoloPlanet then 2 else 1
			end
		end)
	end
	filterMapCards()

	local btnStartGame = Instance.new("TextButton")
	btnStartGame.Name = "BtnStartGame"
	btnStartGame.Position = UDim2.fromOffset(16, 442)
	btnStartGame.Size = UDim2.new(1, -32, 0, 48)
	btnStartGame.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
	btnStartGame.Font = Enum.Font.GothamBlack
	btnStartGame.Text = "INICIAR PARTIDA"
	btnStartGame.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnStartGame.TextSize = 16
	btnStartGame.ZIndex = 82
	btnStartGame.Parent = soloModal
	roundCorners(btnStartGame, 10)

	btnStartGame.MouseButton1Click:Connect(function()
		soloModal.Visible = false
		hubScreen.Visible = false
		if callbacks.onLaunchGame then
			callbacks.onLaunchGame(selectedSoloPlanet, 35, "NORMAL", "FREE")
		end
	end)

	btnSolo.MouseButton1Click:Connect(function()
		soloModal.Visible = true
	end)

	btnTutorial.MouseButton1Click:Connect(function()
		soloModal.Visible = false
		hubScreen.Visible = false
		if callbacks.onLaunchGame then
			callbacks.onLaunchGame("EARTH", 15, "EASY", "FREE")
		end
	end)

	btnCloseHub.MouseButton1Click:Connect(function()
		hubScreen.Visible = false
	end)

	local api = {}
	function api.show(visible)
		hubScreen.Visible = visible
		btnCloseHub.Visible = visible
		if not visible then
			soloModal.Visible = false
		end
	end
	function api.toggle()
		api.show(not hubScreen.Visible)
	end
	function api.isVisible()
		return hubScreen.Visible
	end

	return api
end

return OpenFrontUI
