--!strict
-- TerritoryConquestSystem.luau
-- Módulo desacoplado de simulación táctica de combate, frentes activos, desgaste por terreno,
-- tregua inicial, retirada con penalización del 25%, botín de conquista y liderazgo #1.

export type TerrainType = "Plains" | "Highlands" | "Mountains"

export type NationState = {
	id: number,
	name: string,
	isTribe: boolean,
	isMajor: boolean,
	isBot: boolean,
	cells: number,
	troops: number,
	maxTroops: number,
	gold: number,
	cities: number,
	defensePosts: number,
	capitalCell: number?,
	alive: boolean,
}

export type AttackFront = {
	id: string,
	attackerId: number,
	targetId: number,
	targetName: string,
	isExpansion: boolean,
	troops: number,
	initialTroops: number,
	progress: number,
	frontCell: number,
	nearDefensePost: boolean,
	terrain: TerrainType,
	tilesAbsorbed: number,
}

export type ConquestEvent = {
	attackerId: number,
	defenderId: number,
	defenderName: string,
	goldLoot: number,
	cellsTransferred: number,
	newMaxTroops: number,
	captureCell: number,
}

export type ConquestCallbacks = {
	OnFrontStarted: ((front: AttackFront) -> ())?,
	OnFrontAdvanced: ((front: AttackFront, tilesGained: number) -> ())?,
	OnRetreat: ((attackerId: number, attackId: string, returnedTroops: number, penaltyTroops: number) -> ())?,
	OnCapture: ((event: ConquestEvent) -> ())?,
	OnLeaderChanged: ((leaderId: number?, leaderName: string?) -> ())?,
}

local TerritoryConquestSystem = {}
TerritoryConquestSystem.__index = TerritoryConquestSystem

TerritoryConquestSystem.RETREAT_PENALTY = 0.25
TerritoryConquestSystem.DEFENSE_POST_TROOP_MULT = 5
TerritoryConquestSystem.DEFENSE_POST_TIME_MULT = 3
TerritoryConquestSystem.BASE_PROTECTED_SECONDS = 172 -- 2:52

local TERRAIN_COST: { [TerrainType]: { troopCost: number, timeSec: number } } = {
	Plains = { troopCost = 14, timeSec = 0.12 },
	Highlands = { troopCost = 22, timeSec = 0.18 },
	Mountains = { troopCost = 34, timeSec = 0.26 },
}

export type TerritoryConquestSystemInstance = typeof(setmetatable(
	{} :: {
		nations: { [number]: NationState },
		fronts: { AttackFront },
		protectedSeconds: number,
		nextFrontSeq: number,
		currentLeaderId: number?,
		callbacks: ConquestCallbacks,
	},
	TerritoryConquestSystem
))

function TerritoryConquestSystem.new(callbacks: ConquestCallbacks?): TerritoryConquestSystemInstance
	local self = setmetatable({
		nations = {} :: { [number]: NationState },
		fronts = {} :: { AttackFront },
		protectedSeconds = TerritoryConquestSystem.BASE_PROTECTED_SECONDS,
		nextFrontSeq = 1,
		currentLeaderId = nil :: number?,
		callbacks = callbacks or {},
	}, TerritoryConquestSystem)
	return self
end

function TerritoryConquestSystem:RecalculateMaxTroops(nation: NationState): number
	local baseCap = 8000
	local cellCap = math.max(0, nation.cells) * 55
	local cityCap = math.max(0, nation.cities) * 15000
	nation.maxTroops = baseCap + cellCap + cityCap
	if nation.troops > nation.maxTroops then
		nation.troops = nation.maxTroops
	end
	return nation.maxTroops
end

function TerritoryConquestSystem:RegisterNation(nation: NationState): NationState
	nation.alive = nation.alive ~= false
	self:RecalculateMaxTroops(nation)
	self.nations[nation.id] = nation
	self:_updateLeader()
	return nation
end

function TerritoryConquestSystem:GetNation(nationId: number): NationState?
	return self.nations[nationId]
end

function TerritoryConquestSystem:IsProtected(): boolean
	return self.protectedSeconds > 0
end

function TerritoryConquestSystem:GetProtectedSeconds(): number
	return self.protectedSeconds
end

function TerritoryConquestSystem:SetProtectedSeconds(seconds: number)
	self.protectedSeconds = math.max(0, seconds)
end

function TerritoryConquestSystem:GetLeader(): (number?, string?, number)
	local bestId: number? = nil
	local bestName: string? = nil
	local bestCells = -1
	for id, n in pairs(self.nations) do
		if n.alive and id ~= 0 and n.cells > bestCells then
			bestCells = n.cells
			bestId = id
			bestName = n.name
		end
	end
	return bestId, bestName, math.max(0, bestCells)
end

function TerritoryConquestSystem:_updateLeader()
	local bestId, bestName = self:GetLeader()
	if bestId ~= self.currentLeaderId then
		self.currentLeaderId = bestId
		if self.callbacks.OnLeaderChanged then
			self.callbacks.OnLeaderChanged(bestId, bestName)
		end
	end
end

function TerritoryConquestSystem:IsAtWar(attackerId: number, targetId: number): boolean
	for _, front in ipairs(self.fronts) do
		if front.attackerId == attackerId and front.targetId == targetId and front.troops > 0 then
			return true
		end
	end
	return false
end

function TerritoryConquestSystem:GetActiveFronts(attackerId: number?): { AttackFront }
	if attackerId == nil then
		return table.clone(self.fronts)
	end
	local out: { AttackFront } = {}
	for _, front in ipairs(self.fronts) do
		if front.attackerId == attackerId then
			table.insert(out, front)
		end
	end
	return out
end

function TerritoryConquestSystem:GetTroopsInWar(attackerId: number): number
	local sum = 0
	for _, front in ipairs(self.fronts) do
		if front.attackerId == attackerId then
			sum += math.max(0, math.floor(front.troops))
		end
	end
	return sum
end

function TerritoryConquestSystem:LaunchAttack(
	attackerId: number,
	targetId: number,
	ratio: number,
	originCell: number?,
	terrain: TerrainType?,
	nearDefensePost: boolean?
): (AttackFront?, string?)
	local attacker = self.nations[attackerId]
	if not attacker or not attacker.alive then
		return nil, "Atacante inactivo"
	end

	local target = if targetId ~= 0 then self.nations[targetId] else nil
	if targetId ~= 0 and (not target or not target.alive) then
		return nil, "Objetivo inactivo"
	end

	-- Tregua inicial (PROTECTED): permite expandir a terreno neutral o atacar tribus neutrales,
	-- pero bloquea ataques contra naciones mayores hasta que el temporizador llegue a 0:00.
	if self.protectedSeconds > 0 and target and target.isMajor and not target.isTribe then
		return nil, "Protegido por tregua inicial"
	end

	local clampedRatio = math.clamp(ratio, 0.1, 1.0)
	local sendTroops = math.floor(attacker.troops * clampedRatio)
	if sendTroops <= 0 then
		return nil, "Tropas insuficientes"
	end

	attacker.troops = math.max(0, attacker.troops - sendTroops)

	-- Si ya existe un frente contra ese objetivo, reforzarlo
	for _, existing in ipairs(self.fronts) do
		if existing.attackerId == attackerId and existing.targetId == targetId then
			existing.troops += sendTroops
			existing.initialTroops += sendTroops
			if originCell ~= nil then
				existing.frontCell = originCell
			end
			if nearDefensePost ~= nil then
				existing.nearDefensePost = nearDefensePost
			end
			return existing, nil
		end
	end

	local frontId = string.format("atk_%d_%d", attackerId, self.nextFrontSeq)
	self.nextFrontSeq += 1

	local isExpansion = (targetId == 0)
	local targetName = if isExpansion
		then "Terreno neutral"
		elseif target then target.name
		else ("Nación #" .. tostring(targetId))

	local front: AttackFront = {
		id = frontId,
		attackerId = attackerId,
		targetId = targetId,
		targetName = targetName,
		isExpansion = isExpansion,
		troops = sendTroops,
		initialTroops = sendTroops,
		progress = 0,
		frontCell = originCell or (attacker.capitalCell or 0),
		nearDefensePost = nearDefensePost == true,
		terrain = terrain or "Plains",
		tilesAbsorbed = 0,
	}
	table.insert(self.fronts, front)

	if self.callbacks.OnFrontStarted then
		self.callbacks.OnFrontStarted(front)
	end

	return front, nil
end

function TerritoryConquestSystem:RetreatAttack(attackerId: number, attackId: string?): number
	local attacker = self.nations[attackerId]
	if not attacker then
		return 0
	end

	local targetIdx: number? = nil
	if attackId and attackId ~= "" then
		for idx, front in ipairs(self.fronts) do
			if front.attackerId == attackerId and front.id == attackId then
				targetIdx = idx
				break
			end
		end
	else
		for idx = #self.fronts, 1, -1 do
			if self.fronts[idx].attackerId == attackerId then
				targetIdx = idx
				break
			end
		end
	end

	if not targetIdx then
		return 0
	end

	local front = table.remove(self.fronts, targetIdx) :: AttackFront
	local remaining = math.max(0, math.floor(front.troops))
	local returned = math.floor(remaining * (1 - TerritoryConquestSystem.RETREAT_PENALTY))
	local penalty = remaining - returned

	attacker.troops = math.min(attacker.maxTroops, attacker.troops + returned)

	if self.callbacks.OnRetreat then
		self.callbacks.OnRetreat(attackerId, front.id, returned, penalty)
	end

	return returned
end

function TerritoryConquestSystem:StepFronts(dt: number)
	local stepDt = math.max(0, dt)
	if stepDt <= 0 then
		return
	end

	for idx = #self.fronts, 1, -1 do
		local front = self.fronts[idx]
		local attacker = self.nations[front.attackerId]
		if not attacker or not attacker.alive or front.troops <= 0 then
			table.remove(self.fronts, idx)
			continue
		end

		local terrainSpec = TERRAIN_COST[front.terrain] or TERRAIN_COST.Plains
		local troopMult = if front.nearDefensePost then TerritoryConquestSystem.DEFENSE_POST_TROOP_MULT else 1
		local timeMult = if front.nearDefensePost then TerritoryConquestSystem.DEFENSE_POST_TIME_MULT else 1

		local costPerTile = terrainSpec.troopCost * troopMult
		local secPerTile = terrainSpec.timeSec * timeMult

		front.progress += stepDt / math.max(0.01, secPerTile)
		local possibleByTime = math.floor(front.progress)
		local possibleByTroops = math.floor(front.troops / math.max(1, costPerTile))
		local tilesToCapture = math.min(possibleByTime, possibleByTroops)

		if tilesToCapture > 0 then
			front.progress -= tilesToCapture
			local defender = if front.targetId ~= 0 then self.nations[front.targetId] else nil

			if defender and defender.alive then
				tilesToCapture = math.min(tilesToCapture, math.max(1, defender.cells))
				local troopBurn = tilesToCapture * costPerTile
				front.troops = math.max(0, front.troops - troopBurn)
				defender.troops = math.max(0, defender.troops - math.floor(troopBurn * 0.85))
				defender.cells = math.max(0, defender.cells - tilesToCapture)
			else
				front.troops = math.max(0, front.troops - tilesToCapture * costPerTile)
			end

			attacker.cells += tilesToCapture
			front.tilesAbsorbed += tilesToCapture
			self:RecalculateMaxTroops(attacker)

			if self.callbacks.OnFrontAdvanced then
				self.callbacks.OnFrontAdvanced(front, tilesToCapture)
			end

			if defender and (defender.cells <= 0 or defender.troops <= 0) then
				-- Captura total: transferir territorio restante, botín de oro y recalcular límite
				local remainingCells = math.max(0, defender.cells)
				attacker.cells += remainingCells
				attacker.cities += math.max(0, defender.cities)

				local goldLoot = math.floor(defender.gold * 0.5) + math.max(500, (remainingCells + tilesToCapture) * 4)
				attacker.gold += goldLoot

				defender.cells = 0
				defender.troops = 0
				defender.gold = 0
				defender.alive = false

				-- Retornar tropas restantes del frente victorioso
				attacker.troops = math.min(attacker.maxTroops, attacker.troops + math.floor(front.troops))
				local newMax = self:RecalculateMaxTroops(attacker)

				table.remove(self.fronts, idx)

				if self.callbacks.OnCapture then
					self.callbacks.OnCapture({
						attackerId = attacker.id,
						defenderId = defender.id,
						defenderName = defender.name,
						goldLoot = goldLoot,
						cellsTransferred = remainingCells + tilesToCapture,
						newMaxTroops = newMax,
						captureCell = defender.capitalCell or front.frontCell,
					})
				end
				continue
			end
		end

		if front.troops <= 0 then
			table.remove(self.fronts, idx)
		end
	end

	self:_updateLeader()
end

function TerritoryConquestSystem:Tick(dt: number)
	if self.protectedSeconds > 0 then
		self.protectedSeconds = math.max(0, self.protectedSeconds - math.max(0, dt))
	end
	self:StepFronts(dt)
end

return TerritoryConquestSystem
