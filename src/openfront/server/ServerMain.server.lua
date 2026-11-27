--!strict
-- OpenFront.io: ServerMain
-- Primary game server entry point

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Set up RemoteEvents & RemoteFunctions in ReplicatedStorage.OpenFrontRemotes
local remotes = ReplicatedStorage:FindFirstChild("OpenFrontRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "OpenFrontRemotes"
	remotes.Parent = ReplicatedStorage
end

local function getOrCreateRemote(className: string, name: string): Instance
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local selectMapFunc = getOrCreateRemote("RemoteFunction", "SelectMap") :: RemoteFunction
local joinNationFunc = getOrCreateRemote("RemoteFunction", "JoinNation") :: RemoteFunction
local attackEvent = getOrCreateRemote("RemoteEvent", "SendAttack") :: RemoteEvent
local buildEvent = getOrCreateRemote("RemoteEvent", "BuildStructure") :: RemoteEvent
local nukeEvent = getOrCreateRemote("RemoteEvent", "LaunchNuke") :: RemoteEvent
local serverSnapshotEvent = getOrCreateRemote("RemoteEvent", "ServerSnapshot") :: RemoteEvent
local gameWonEvent = getOrCreateRemote("RemoteEvent", "GameWon") :: RemoteEvent
local serverMessageEvent = getOrCreateRemote("RemoteEvent", "ServerMessage") :: RemoteEvent

-- Initialize GameRunner
local GameRunner = require(script.Parent.GameRunner)
local runner = GameRunner.new(remotes)

-- Load default map: "world"
runner:LoadMap("world")

-- Remote handlers
selectMapFunc.OnServerInvoke = function(player: Player, mapId: string)
	print("[ServerMain] Player requested map change to: " .. tostring(mapId))
	runner:LoadMap(mapId)
	return { success = true, mapId = mapId }
end

joinNationFunc.OnServerInvoke = function(player: Player, nationName: string?)
	local human = runner:JoinHumanPlayer(player, nationName)
	return {
		success = true,
		smallID = human.smallID,
		nationName = human.name,
		mapId = runner.currentMapId,
	}
end

attackEvent.OnServerEvent:Connect(function(player: Player, targetX: number, targetY: number, ratio: number)
	runner:ExecuteAttack(tostring(player.UserId), targetX, targetY, ratio)
end)

buildEvent.OnServerEvent:Connect(function(player: Player, unitType: string, tileX: number, tileY: number)
	runner:BuildStructure(tostring(player.UserId), unitType, tileX, tileY)
end)

nukeEvent.OnServerEvent:Connect(function(player: Player, nukeType: string, targetX: number, targetY: number)
	runner:LaunchNuke(tostring(player.UserId), nukeType, targetX, targetY)
end)

-- 10 Hz Game Loop
local accumulator = 0
local TICK_INTERVAL = 0.1 -- 100ms

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	while accumulator >= TICK_INTERVAL do
		accumulator -= TICK_INTERVAL
		runner:Tick(TICK_INTERVAL)
	end
end)

print("[ServerMain] OpenFront Server Engine initialized successfully at 10 Hz!")
