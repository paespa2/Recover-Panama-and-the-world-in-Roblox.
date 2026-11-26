--!nonstrict
-- WorldServer.server.lua
-- Servidor multijugador del mapa mundial por celdas. Cada jugador de Roblox obtiene SU PROPIA nación
-- (color neón único); los bots usan nombres de países y personajes históricos (Tesla, Newton, Trump, Escobar...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Engine = require(script.Parent:WaitForChild("WorldEngine"))
local WorldGrid = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldGrid"))

local folder = ReplicatedStorage:FindFirstChild("WorldRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "WorldRemotes"
	folder.Parent = ReplicatedStorage
end

local function remote(name)
	local ev = folder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	return ev
end

local WorldInit = remote("WorldInit")
local WorldDiff = remote("WorldDiff")
local WorldStats = remote("WorldStats")
local WorldMe = remote("WorldMe")
local WorldNotice = remote("WorldNotice")
local WorldCommand = remote("WorldCommand")
local WorldRoster = remote("WorldRoster") -- una nación nueva (jugador que entra) para quienes ya están en la partida
local WorldFx = remote("WorldFx") -- efectos visuales de las armas (explosiones, terremotos...)

local engine = nil
local config = { planet = "WORLD", bots = 35, difficulty = "NORMAL", mode = "FREE" }
local humanNations = {} -- [Player] = nación
local lastCommand = {}
local endedAt = nil

local function sendInit(player)
	local n = humanNations[player]
	if not engine or not n then
		return
	end
	WorldInit:FireClient(player, {
		planet = engine.planetId,
		w = engine.w,
		h = engine.h,
		land = engine.land,
		owner = engine:snapshotOwner(),
		roster = engine:getRoster(),
		myId = n.id,
		stats = engine:getStats(),
		difficulty = engine.difficultyName,
		mode = engine.mode,
		teamMode = engine.teamMode,
	})
end

local function joinPlayer(player)
	if not engine then
		return
	end
	local n = humanNations[player]
	if not n then
		n = engine:addHuman(player)
		humanNations[player] = n
		-- Los demás clientes no la tienen en su lista de naciones (se envió al empezar): sin esto no verían
		-- su color, su rótulo ni su capital
		WorldRoster:FireAllClients(engine:rosterEntry(n))
	end
	sendInit(player)
end

local function newMatch(cfg)
	config = cfg
	engine = Engine.new(cfg.planet, cfg.bots, cfg.difficulty, cfg.mode)
	endedAt = nil
	humanNations = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if lastCommand[p] ~= nil then
			joinPlayer(p)
		end
	end
end

local VALID_MODES = {
	FREE = true,
	TEAMS_2 = true,
	CONTINENTS = true,
	BLITZ = true,
	ZOMBIES = true,
	BATTLE_ROYALE = true,
	COUNTRIES = true,
}

local function sanitize(cmd)
	local rawPlanet = tostring(cmd.planet or "WORLD")
	local planet = "WORLD"
	if WorldGrid.PLANETS[rawPlanet] then
		planet = WorldGrid.PLANETS[rawPlanet].id
	elseif WorldGrid.PLANETS[string.upper(rawPlanet)] then
		planet = WorldGrid.PLANETS[string.upper(rawPlanet)].id
	end
	local difficulty = tostring(cmd.difficulty or "NORMAL")
	if not Engine.DIFFICULTY[difficulty] then
		difficulty = "NORMAL"
	end
	local bots = math.clamp(math.floor(tonumber(cmd.bots) or 35), 0, 90)
	local rawMode = tostring(cmd.mode or "FREE")
	local mode = if VALID_MODES[rawMode] then rawMode else "FREE"
	if (mode == "COUNTRIES" or mode == "CONTINENTS") and planet ~= "EARTH" and planet ~= "WORLD" then
		mode = "FREE"
	end
	return { planet = planet, bots = bots, difficulty = difficulty, mode = mode }
end

local function countHumans()
	local c = 0
	for _ in pairs(humanNations) do
		c += 1
	end
	return c
end

local function notice(player, text)
	WorldNotice:FireClient(player, text)
end

newMatch(config)

WorldCommand.OnServerEvent:Connect(function(player, cmd)
	if type(cmd) ~= "table" then
		return
	end
	local now = os.clock()
	if (lastCommand[player] or 0) > now - 0.08 then
		return
	end
	lastCommand[player] = now

	local action = cmd.a
	if action == "PLAY" then
		local isHost = (Players:GetPlayers()[1] == player)
		if isHost or engine.phase == "ENDED" or countHumans() == 0 or (countHumans() == 1 and humanNations[player]) then
			newMatch(sanitize(cmd))
			joinPlayer(player)
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and lastCommand[p] ~= nil and not humanNations[p] then
					joinPlayer(p)
				end
			end
		else
			joinPlayer(player)
		end
		return
	end

	local n = humanNations[player]
	if not engine or not n then
		return
	end

	local cell = math.floor(tonumber(cmd.cell) or -1)
	local validCell = cell >= 0 and cell < engine.size

	-- Las acciones del jugador son INTENCIONES: el motor las ejecuta al inicio del siguiente tick (ver Engine:runIntents)
	local intent = nil
	if action == "START_NOW" then
		if engine and engine.phase == "SPAWN" then
			engine.spawnTimer = 0
		end
		return
	elseif action == "SPAWN" and validCell then
		intent = { a = "SPAWN", cell = cell }
	elseif action == "ATTACK" and validCell then
		intent = { a = "ATTACK", cell = cell, ratio = math.clamp(tonumber(cmd.ratio) or 0.5, 0.1, 1) }
	elseif action == "BUILD" and validCell then
		intent = { a = "BUILD", cell = cell, kind = tostring(cmd.kind) }
	elseif action == "DEMOLISH" and validCell then
		intent = { a = "DEMOLISH", cell = cell }
	elseif action == "DEBUG_DISASTER" and RunService:IsStudio() then
		-- Solo en Studio: provoca un desastre ahora mismo (kind opcional) para probar animaciones y efectos
		local kind = tostring(cmd.kind or "")
		if engine.DISASTER_INFO[kind] and cell >= 0 then
			engine:runDisaster(kind, if validCell then cell else 0)
		else
			engine:startDisaster()
		end
	elseif action == "DEBUG_PROPAGATION" and RunService:IsStudio() then
		-- Solo en Studio: cambia el estilo de propagación para compararlos
		local style = tostring(cmd.style)
		if style == "CELL" or style == "ORGANIC" or style == "TENDRIL" then
			engine.propagation = style
		end
	elseif action == "WEAPON" and validCell then
		intent = { a = "WEAPON", cell = cell, kind = tostring(cmd.kind) }
	elseif action == "NUKE" and validCell then
		intent = { a = "NUKE", cell = cell }
	elseif
		action == "ALLY_REQUEST"
		or action == "ALLY_ACCEPT"
		or action == "ALLY_DECLINE"
		or action == "ALLY_BREAK"
	then
		local target = math.floor(tonumber(cmd.target) or -1)
		if target > 0 and engine.nations[target] then
			intent = { a = action, target = target }
		end
	elseif action == "RETREAT" then
		intent = { a = "RETREAT" }
	elseif action == "DEFENSE_AI" then
		intent = { a = "DEFENSE_AI", on = (cmd.on == true) }
	elseif action == "AUTO" then
		-- Autojuego: OFF / EXPAND / CONQUER y el porcentaje de tropas por ataque
		local mode = tostring(cmd.mode)
		if mode ~= "OFF" and mode ~= "EXPAND" and mode ~= "CONQUER" then
			mode = nil
		end
		intent = { a = "AUTO", mode = mode, ratio = math.clamp(tonumber(cmd.ratio) or 0.4, 0.1, 1) }
	end
	if intent then
		engine:submit(n, intent)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local n = humanNations[player]
	if n then
		n.isBot = true
		n.player = nil
		n.userId = nil
		humanNations[player] = nil
	end
	lastCommand[player] = nil
end)

local acc, statAcc, meAcc = 0, 0, 0
RunService.Heartbeat:Connect(function(dt)
	if not engine then
		return
	end
	acc = math.min(acc + dt, 0.6)
	statAcc += dt
	meAcc += dt

	while acc >= 0.2 do
		acc -= 0.2
		engine:tick(0.2)
		local diff = engine:flushDiff()
		if diff then
			WorldDiff:FireAllClients(diff)
		end
	end

	-- Efectos de armas: se envían a todos; si hay una ráfaga enorme se recorta para no saturar la red
	local fxEvents = engine.fxEvents
	if #fxEvents > 0 then
		engine.fxEvents = {}
		for i = 1, math.min(#fxEvents, 12) do
			WorldFx:FireAllClients(fxEvents[i])
		end
	end

	local events = engine.events
	if #events > 0 then
		engine.events = {}
		for _, ev in ipairs(events) do
			if ev.userId then
				local p = Players:GetPlayerByUserId(ev.userId)
				if p then
					notice(p, ev.text)
				end
			else
				WorldNotice:FireAllClients(ev.text)
			end
		end
	end

	if statAcc >= 1 then
		statAcc = 0
		local stats = engine:getStats()
		local allPlayers = Players:GetPlayers()
		stats.players = #allPlayers
		stats.maxPlayers = Players.MaxPlayers
		stats.hostId = if allPlayers[1] then allPlayers[1].UserId else 0 -- el anfitrión crea/reinicia la partida
		WorldStats:FireAllClients(stats)
	end

	if meAcc >= 0.5 then
		meAcc = 0
		for player, n in pairs(humanNations) do
			WorldMe:FireClient(player, engine:getMe(n))
		end
	end

	-- Reinicio automático 20 s después de que alguien gane
	if engine.phase == "ENDED" then
		if not endedAt then
			endedAt = os.clock()
		elseif os.clock() - endedAt > 20 then
			newMatch(config)
			for p in pairs(lastCommand) do
				if p.Parent then
					joinPlayer(p)
				end
			end
		end
	end
end)
