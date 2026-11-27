--!strict
-- OpenFront.io: GameRunner
-- Parity with packages/engine/src/GameRunner.ts

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameMap = require(script.Parent.GameMap)
local Player = require(script.Parent.Player)
local UnitGrid = require(script.Parent.UnitGrid)
local ExecutionManager = require(script.Parent.ExecutionManager)
local Config = require(script.Parent.Parent.shared.Config)
local EngineConfig = require(script.Parent.Parent.Parent.shared.EngineConfig)

-- Executions
local AttackExecution = require(script.Parent.execution.AttackExecution)
local TransportShipExecution = require(script.Parent.execution.TransportShipExecution)
local WarshipExecution = require(script.Parent.execution.WarshipExecution)
local ConstructionExecution = require(script.Parent.execution.ConstructionExecution)
local NukeExecution = require(script.Parent.execution.NukeExecution)
local MIRVExecution = require(script.Parent.execution.MIRVExecution)
local SAMLauncherExecution = require(script.Parent.execution.SAMLauncherExecution)
local WinCheckExecution = require(script.Parent.execution.WinCheckExecution)
local NationExecution = require(script.Parent.execution.NationExecution)

local GameRunner = {}
GameRunner.__index = GameRunner

-- 24 distinct nation colors matching OpenFront palette
local NATION_COLORS = {
	Color3.fromRGB(220, 50, 50),   -- Red
	Color3.fromRGB(50, 120, 220),  -- Blue
	Color3.fromRGB(50, 200, 80),   -- Green
	Color3.fromRGB(240, 180, 40),  -- Gold
	Color3.fromRGB(160, 60, 220),  -- Purple
	Color3.fromRGB(240, 110, 40),  -- Orange
	Color3.fromRGB(40, 210, 210),  -- Cyan
	Color3.fromRGB(230, 80, 150),  -- Pink
	Color3.fromRGB(140, 200, 60),  -- Lime
	Color3.fromRGB(120, 100, 220), -- Indigo
	Color3.fromRGB(200, 160, 100), -- Tan
	Color3.fromRGB(100, 180, 160), -- Teal
	Color3.fromRGB(210, 120, 120), -- Salmon
	Color3.fromRGB(180, 180, 50),  -- Olive
	Color3.fromRGB(130, 70, 70),   -- Brown
	Color3.fromRGB(70, 140, 140),  -- Dark Cyan
	Color3.fromRGB(180, 100, 180), -- Magenta
	Color3.fromRGB(220, 140, 60),  -- Amber
	Color3.fromRGB(100, 140, 220), -- Sky Blue
	Color3.fromRGB(160, 210, 100), -- Mint
	Color3.fromRGB(200, 70, 100),  -- Crimson
	Color3.fromRGB(80, 180, 120),  -- Emerald
	Color3.fromRGB(190, 130, 220), -- Lavender
	Color3.fromRGB(220, 190, 80),  -- Yellow
}

function GameRunner.new(remotesFolder: Folder)
	local self = setmetatable({}, GameRunner)
	self.remotes = remotesFolder
	self.gameMap = nil :: any
	self.unitGrid = UnitGrid.new()
	self.executionManager = ExecutionManager.new()
	self.playersBySmallID = {} :: { [number]: any }
	self.playersByUserId = {} :: { [string]: any }
	self.executionsById = {} :: { [string]: any }
	self.tileDeltas = {} :: { { tileIdx: number, ownerSmallID: number } }
	self.nextSmallID = 1
	self.currentMapId = "world"
	self.winnerDeclared = false
	self.mirvsLaunched = 0
	return self
end

function GameRunner:RecordTileDelta(tileIdx: number, ownerSmallID: number)
	table.insert(self.tileDeltas, { tileIdx = tileIdx, ownerSmallID = ownerSmallID })
end

function GameRunner:GetExecutionById(id: string): any?
	return self.executionsById[id]
end

function GameRunner:LoadMap(mapId: string)
	print("[GameRunner] Loading map: " .. mapId)
	self.currentMapId = mapId
	self.gameMap = GameMap.new(mapId)
	self.unitGrid = UnitGrid.new()
	self.executionManager = ExecutionManager.new()
	self.playersBySmallID = {}
	self.playersByUserId = {}
	self.executionsById = {}
	self.tileDeltas = {}
	self.nextSmallID = 1
	self.winnerDeclared = false
	self.mirvsLaunched = 0

	local mapData = self.gameMap.mapData

	-- Spawn AI Nations from official mapData.nations
	if mapData.nations then
		for i, nDef in ipairs(mapData.nations) do
			local smallID = self.nextSmallID
			self.nextSmallID += 1

			local capX = math.clamp(nDef.x, 0, self.gameMap.w - 1)
			local capY = math.clamp(nDef.y, 0, self.gameMap.h - 1)
			local capIdx = self.gameMap:GetIndex(capX, capY)

			local color = NATION_COLORS[((i - 1) % #NATION_COLORS) + 1]
			local p = Player.new(
				smallID,
				"nation_" .. tostring(i),
				nDef.name,
				nDef.flag,
				color,
				"Nation",
				capIdx
			)

			p.troops = 250
			p.gold = 500000

			self.playersBySmallID[smallID] = p

			-- Claim initial capital land cluster (radius 2)
			for dy = -2, 2 do
				for dx = -2, 2 do
					local tx = capX + dx
					local ty = capY + dy
					if self.gameMap:InBounds(tx, ty) and (dx * dx + dy * dy) <= 5 then
						local tidx = self.gameMap:GetIndex(tx, ty)
						if self.gameMap:IsLand(tidx) and not self.gameMap:IsImpassable(tidx) then
							self.gameMap:SetOwner(tidx, smallID)
							p.tilesCount += 1
						end
					end
				end
			end

			-- Add AI Nation execution
			local nationExec = NationExecution.new("nexec_" .. tostring(smallID), p, self)
			self.executionManager:Add(nationExec)
		end
	end

	-- Add WinCheckExecution
	local winCheck = WinCheckExecution.new("win_check", self)
	self.executionManager:Add(winCheck)

	print("[GameRunner] Map loaded with " .. tostring(self.nextSmallID - 1) .. " nations!")
end

function GameRunner:JoinHumanPlayer(player: Player, nationName: string?): any
	local userId = tostring(player.UserId)
	if self.playersByUserId[userId] then
		return self.playersByUserId[userId]
	end

	-- Find selected nation or assign first available
	local targetNationSmallID = nil
	if nationName then
		for smallID, p in pairs(self.playersBySmallID) do
			if p.playerType == "Nation" and string.lower(p.name) == string.lower(nationName) then
				targetNationSmallID = smallID
				break
			end
		end
	end

	local humanPlayer = nil
	if targetNationSmallID and self.playersBySmallID[targetNationSmallID] then
		-- Convert AI nation to Human Player
		humanPlayer = self.playersBySmallID[targetNationSmallID]
		humanPlayer.id = userId
		humanPlayer.playerType = "Human"
		humanPlayer.name = player.DisplayName or player.Name
	else
		-- Assign a new smallID and spawn near random land
		local smallID = self.nextSmallID
		self.nextSmallID += 1
		local capIdx = self.gameMap:GetIndex(math.floor(self.gameMap.w / 2), math.floor(self.gameMap.h / 2))
		local color = NATION_COLORS[((smallID - 1) % #NATION_COLORS) + 1]

		humanPlayer = Player.new(
			smallID,
			userId,
			player.DisplayName or player.Name,
			"player",
			color,
			"Human",
			capIdx
		)
		humanPlayer.troops = 1000
		humanPlayer.gold = 1000000
		self.playersBySmallID[smallID] = humanPlayer
	end

	self.playersByUserId[userId] = humanPlayer
	print("[GameRunner] Human player " .. humanPlayer.name .. " joined as SmallID: " .. tostring(humanPlayer.smallID))
	return humanPlayer
end

function GameRunner:ExecuteAttack(userId: string, targetTileX: number, targetTileY: number, troopRatio: number)
	local p = self.playersByUserId[userId]
	if not p or not p.alive then return end

	local ratio = math.clamp(troopRatio or 0.5, 0.1, 1.0)
	local commit = math.floor(p.troops * ratio)
	if commit <= 10 or not p:SpendTroops(commit) then return end

	local targetIdx = self.gameMap:GetIndex(targetTileX, targetTileY)
	local attackId = "atk_" .. p.id .. "_" .. tostring(os.clock())

	-- Check if target is over water or land
	if self.gameMap:IsOcean(targetIdx) then
		-- Naval landing across water
		local transport = TransportShipExecution.new(
			attackId,
			p,
			p.capitalIdx,
			targetIdx,
			commit,
			self
		)
		self.executionsById[attackId] = transport
		self.executionManager:Add(transport)
	else
		-- Direct land attack
		local attack = AttackExecution.new(
			attackId,
			p,
			targetIdx,
			commit,
			self
		)
		self.executionsById[attackId] = attack
		self.executionManager:Add(attack)
	end
end

function GameRunner:BuildStructure(userId: string, unitType: string, tileX: number, tileY: number)
	local p = self.playersByUserId[userId]
	if not p or not p.alive then return end

	local tileIdx = self.gameMap:GetIndex(tileX, tileY)
	local canBuild, reason = ConstructionExecution.CanBuild(p, unitType, tileIdx, self)
	if not canBuild then
		local ev = self.remotes:FindFirstChild("ServerMessage")
		if ev and ev:IsA("RemoteEvent") then
			local ply = Players:GetPlayerByUserId(tonumber(userId) or 0)
			if ply then ev:FireClient(ply, reason or "No se puede construir aquí") end
		end
		return
	end

	local cost = 0
	if unitType == "City" then cost = EngineConfig.GetCost("City", p.citiesCount)
	elseif unitType == "Port" then cost = EngineConfig.GetCost("Port", p.portsCount, p.factoriesCount)
	elseif unitType == "Factory" then cost = EngineConfig.GetCost("Factory", p.factoriesCount, p.portsCount)
	elseif unitType == "DefensePost" then cost = EngineConfig.GetCost("DefensePost", p.defensePostsCount)
	elseif unitType == "MissileSilo" then cost = EngineConfig.GetCost("MissileSilo", p.silosCount)
	elseif unitType == "SAMLauncher" then cost = EngineConfig.GetCost("SAMLauncher", p.samsCount)
	end

	if p:SpendGold(cost) then
		local bldId = "bld_" .. self.unitGrid:GenerateId()
		local constr = ConstructionExecution.new(bldId, p, unitType, tileIdx, self)
		self.executionsById[bldId] = constr
		self.executionManager:Add(constr)
	end
end

function GameRunner:LaunchNuke(userId: string, nukeType: string, targetX: number, targetY: number)
	local p = self.playersByUserId[userId]
	if not p or not p.alive then return end

	local cost = 0
	if nukeType == "AtomBomb" then cost = EngineConfig.GetCost("AtomBomb")
	elseif nukeType == "HydrogenBomb" then cost = EngineConfig.GetCost("HydrogenBomb")
	elseif nukeType == "MIRV" then cost = EngineConfig.GetCost("MIRV", nil, nil, self.mirvsLaunched)
	end

	if not p:SpendGold(cost) then return end

	local srcX, srcY = self.gameMap:GetCoords(p.capitalIdx)
	local nukeId = "nuke_" .. self.unitGrid:GenerateId()

	if nukeType == "MIRV" then
		self.mirvsLaunched += 1
		local mirv = MIRVExecution.new(nukeId, p, srcX, srcY, targetX, targetY, self)
		self.executionsById[nukeId] = mirv
		self.executionManager:Add(mirv)
	else
		local nuke = NukeExecution.new(nukeId, p, nukeType :: any, srcX, srcY, targetX, targetY, self)
		self.executionsById[nukeId] = nuke
		self.executionManager:Add(nuke)
	end
end

function GameRunner:DeclareWinner(winnerPlayer: any)
	if self.winnerDeclared then return end
	self.winnerDeclared = true
	print("[GameRunner] WINNER DECLARED: " .. winnerPlayer.name)

	local ev = self.remotes:FindFirstChild("GameWon")
	if ev and ev:IsA("RemoteEvent") then
		ev:FireAllClients({
			winnerName = winnerPlayer.name,
			winnerFlag = winnerPlayer.flag,
			winnerSmallID = winnerPlayer.smallID,
			tilesCount = winnerPlayer.tilesCount,
		})
	end
end

function GameRunner:Tick(dt: number)
	if not self.gameMap then return end

	-- Step executions
	self.executionManager:Tick(dt)

	-- Update players
	local playerStats = {}
	for smallID, p in pairs(self.playersBySmallID) do
		p:TickIncome(dt)
		p.tilesCount = self.gameMap.ownerCounts[smallID] or 0
		table.insert(playerStats, {
			smallID = smallID,
			name = p.name,
			flag = p.flag,
			troops = math.floor(p.troops),
			gold = math.floor(p.gold),
			tiles = p.tilesCount,
			color = { p.color.R, p.color.G, p.color.B },
			isHuman = (p.playerType == "Human"),
		})
	end

	-- Collect dynamic units (ships, flying nukes)
	local activeUnits = {}
	for _, u in pairs(self.unitGrid.dynamicUnits) do
		table.insert(activeUnits, {
			id = u.id,
			unitType = u.unitType,
			ownerSmallID = u.ownerSmallID,
			x = math.floor(u.x * 10) / 10,
			y = math.floor(u.y * 10) / 10,
			progress = u.progress,
		})
	end

	-- Broadcast delta snapshot to all clients
	local snapshotEv = self.remotes:FindFirstChild("ServerSnapshot")
	if snapshotEv and snapshotEv:IsA("RemoteEvent") then
		local payload = {
			players = playerStats,
			units = activeUnits,
			deltas = self.tileDeltas,
		}
		snapshotEv:FireAllClients(payload)
	end

	-- Reset deltas for next tick
	self.tileDeltas = {}
end

return GameRunner
