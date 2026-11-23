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

local engine = nil
local config = { planet = "EARTH", bots = 40, difficulty = "NORMAL" }
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
	end
	sendInit(player)
end

local function newMatch(cfg)
	config = cfg
	engine = Engine.new(cfg.planet, cfg.bots, cfg.difficulty)
	endedAt = nil
	humanNations = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if lastCommand[p] ~= nil then
			joinPlayer(p)
		end
	end
end

local function sanitize(cmd)
	local planet = tostring(cmd.planet or "EARTH")
	if not WorldGrid.PLANETS[planet] then
		planet = "EARTH"
	end
	local difficulty = tostring(cmd.difficulty or "NORMAL")
	if not Engine.DIFFICULTY[difficulty] then
		difficulty = "NORMAL"
	end
	local bots = math.clamp(math.floor(tonumber(cmd.bots) or 40), 0, 90)
	return { planet = planet, bots = bots, difficulty = difficulty }
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

	if action == "SPAWN" and validCell then
		local ok, msg = engine:setSpawn(n, cell)
		if not ok then
			notice(player, "⚠️ " .. tostring(msg))
		end
	elseif action == "ATTACK" and validCell then
		local ratio = math.clamp(tonumber(cmd.ratio) or 0.5, 0.1, 1)
		local ok, msg = engine:playerAttack(n, cell, ratio)
		if not ok and msg then
			notice(player, "⚠️ " .. msg)
		end
	elseif action == "BUILD" and validCell then
		local ok, msg = engine:build(n, tostring(cmd.kind), cell)
		if not ok then
			notice(player, "⚠️ " .. tostring(msg))
		end
	elseif action == "NUKE" and validCell then
		local ok, msg = engine:nuke(n, cell)
		if not ok then
			notice(player, "⚠️ " .. tostring(msg))
		end
	elseif action == "RETREAT" then
		engine:retreat(n)
	elseif action == "DEFENSE_AI" then
		n.defenseAI = (cmd.on == true)
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
		WorldStats:FireAllClients(engine:getStats())
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
