--!strict
-- OpenFront.io: AttackExecution
-- Parity with packages/engine/src/execution/AttackExecution.ts

local EngineConfig = require(script.Parent.Parent.Parent.shared.EngineConfig)
local Config = require(script.Parent.Parent.Parent.shared.Config)

local AttackExecution = {}
AttackExecution.__index = AttackExecution

function AttackExecution.new(
	id: string,
	attacker: any,
	targetTileIdx: number,
	troopsCommitted: number,
	gameRunner: any
)
	local self = setmetatable({}, AttackExecution)
	self.id = id
	self.attacker = attacker
	self.targetTileIdx = targetTileIdx
	self.remainingTroops = troopsCommitted
	self.gameRunner = gameRunner
	self.finished = false
	self.activeFrontier = { targetTileIdx }
	self.visited = {} :: { [number]: boolean }
	self.visited[targetTileIdx] = true
	return self
end

function AttackExecution:IsFinished(): boolean
	return self.finished or self.remainingTroops <= 5
end

function AttackExecution:Tick(dt: number, tickNumber: number): boolean
	if self:IsFinished() then return false end

	local gameMap = self.gameRunner.gameMap
	local unitGrid = self.gameRunner.unitGrid

	-- Process up to 3 tiles per tick for smooth expansion animation
	local tilesToConquer = 3
	while tilesToConquer > 0 and #self.activeFrontier > 0 and self.remainingTroops > 5 do
		local currentTile = table.remove(self.activeFrontier, 1) :: number
		if not gameMap:InBounds(gameMap:GetCoords(currentTile)) then
			continue
		end

		-- If water tile, land attack cannot conquer ocean directly
		if gameMap:IsOcean(currentTile) then
			continue
		end

		local owner = gameMap:GetOwner(currentTile)
		if owner ~= self.attacker.smallID then
			-- Calculate defender resistance
			local defenderPlayer = self.gameRunner.playersBySmallID[owner]
			local defenderTroops = 0
			if defenderPlayer then
				-- Density based on player's total troops / tiles
				defenderTroops = math.clamp(math.floor(defenderPlayer.troops / math.max(1, defenderPlayer.tilesCount)), 1, 200)
			end

			-- Check if near any defense posts
			local tx, ty = gameMap:GetCoords(currentTile)
			local nearStructures = unitGrid:GetStructuresNear(tx, ty, Config.DEFENSE_POST_RANGE)
			local hasDefensePost = false
			for _, s in ipairs(nearStructures) do
				if s.unitType == "DefensePost" and s.ownerSmallID == owner and not s.isUnderConstruction then
					hasDefensePost = true
					break
				end
			end

			local elev = gameMap:GetElevation(currentTile)
			local outcome = EngineConfig.ResolveCombatStep(self.remainingTroops, defenderTroops, hasDefensePost, elev)

			self.remainingTroops -= outcome.attackerLoss
			if defenderPlayer and outcome.defenderLoss > 0 then
				defenderPlayer:SpendTroops(outcome.defenderLoss)
			end

			if outcome.conquered then
				gameMap:SetOwner(currentTile, self.attacker.smallID)
				self.gameRunner:RecordTileDelta(currentTile, self.attacker.smallID)

				-- Destroy any enemy structure on this tile
				local struct = unitGrid:GetStructureAt(currentTile)
				if struct and struct.ownerSmallID ~= self.attacker.smallID then
					unitGrid:RemoveStructure(struct.id)
				end
			else
				-- Repelled
				self.finished = true
				return false
			end
		end

		-- Expand frontier to 4-way neighbors
		local neighbors = gameMap:GetNeighbors4(currentTile)
		for _, nIdx in ipairs(neighbors) do
			if not self.visited[nIdx] and gameMap:IsLand(nIdx) and not gameMap:IsImpassable(nIdx) then
				self.visited[nIdx] = true
				if gameMap:GetOwner(nIdx) ~= self.attacker.smallID then
					table.insert(self.activeFrontier, nIdx)
				end
			end
		end

		tilesToConquer -= 1
	end

	if #self.activeFrontier == 0 or self.remainingTroops <= 5 then
		self.finished = true
		return false
	end

	return true
end

return AttackExecution
