--!strict
-- OpenFront.io: NationExecution
-- Parity with packages/engine/src/execution/NationExecution.ts

local AttackExecution = require(script.Parent.AttackExecution)
local ConstructionExecution = require(script.Parent.ConstructionExecution)

local NationExecution = {}
NationExecution.__index = NationExecution

function NationExecution.new(id: string, nationPlayer: any, gameRunner: any)
	local self = setmetatable({}, NationExecution)
	self.id = id
	self.player = nationPlayer
	self.gameRunner = gameRunner
	self.finished = false
	self.thinkTimer = math.random() * 2 -- staggered start
	return self
end

function NationExecution:IsFinished(): boolean
	return self.finished or not self.player.alive or self.player.tilesCount <= 0
end

function NationExecution:Tick(dt: number, tickNumber: number): boolean
	if self:IsFinished() then return false end

	self.thinkTimer += dt
	if self.thinkTimer < 2.5 then
		return true
	end
	self.thinkTimer = 0

	local gameMap = self.gameRunner.gameMap

	-- Economy: Build structures if wealthy
	if self.player.gold >= 250000 and self.player.factoriesCount < 3 then
		-- Try to build a Factory on a random owned tile
		local myTile = self:FindRandomOwnedTile()
		if myTile then
			local canBuild = ConstructionExecution.CanBuild(self.player, "Factory", myTile, self.gameRunner)
			if canBuild then
				self.player:SpendGold(125000)
				local constr = ConstructionExecution.new(
					"bld_" .. self.gameRunner.unitGrid:GenerateId(),
					self.player,
					"Factory",
					myTile,
					self.gameRunner
				)
				self.gameRunner.executionManager:Add(constr)
			end
		end
	end

	-- Military expansion: Attack if troops are sufficient (e.g. >= 200)
	if self.player.troops >= 200 then
		local targetTile = self:FindBorderTarget()
		if targetTile then
			local commit = math.floor(self.player.troops * 0.4)
			if self.player:SpendTroops(commit) then
				local attackId = "atk_" .. self.player.id .. "_" .. tostring(tickNumber)
				local attack = AttackExecution.new(
					attackId,
					self.player,
					targetTile,
					commit,
					self.gameRunner
				)
				self.gameRunner.executionManager:Add(attack)
			end
		end
	end

	return true
end

function NationExecution:FindRandomOwnedTile(): number?
	local gameMap = self.gameRunner.gameMap
	local cx, cy = gameMap:GetCoords(self.player.capitalIdx)
	for r = 1, 15 do
		local tx = cx + math.random(-r, r)
		local ty = cy + math.random(-r, r)
		if gameMap:InBounds(tx, ty) then
			local idx = gameMap:GetIndex(tx, ty)
			if gameMap:GetOwner(idx) == self.player.smallID and gameMap:IsLand(idx) and not gameMap:IsImpassable(idx) then
				return idx
			end
		end
	end
	return nil
end

function NationExecution:FindBorderTarget(): number?
	local gameMap = self.gameRunner.gameMap
	local cx, cy = gameMap:GetCoords(self.player.capitalIdx)
	local range = math.clamp(math.floor(math.sqrt(self.player.tilesCount) * 2), 5, 40)

	for _ = 1, 30 do
		local tx = cx + math.random(-range, range)
		local ty = cy + math.random(-range, range)
		if gameMap:InBounds(tx, ty) then
			local idx = gameMap:GetIndex(tx, ty)
			if gameMap:IsLand(idx) and not gameMap:IsImpassable(idx) then
				local owner = gameMap:GetOwner(idx)
				if owner ~= self.player.smallID then
					-- Check if adjacent to an owned tile
					local neighbors = gameMap:GetNeighbors4(idx)
					for _, nIdx in ipairs(neighbors) do
						if gameMap:GetOwner(nIdx) == self.player.smallID then
							return idx
						end
					end
				end
			end
		end
	end
	return nil
end

return NationExecution
