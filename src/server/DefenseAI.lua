--!strict
-- DefenseAI.lua
-- Agente de IA de Defensa Territorial del Jugador + IA Estratégica de Países Rivales
-- Implementa la solicitud del usuario: "ponerle incluso el manejo de IA para las defensas de los países,
-- pero el resto se lo dejo al jugador tanto construir los edificios necesarios como la expansión territorial".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local DefenseAI = {}

export type RegionState = {
	id: string,
	name: string,
	owner: string,
	troops: number,
	building: string?,
	shieldUntil: number,
	underAttackUntil: number,
	neighbors: { string },
	goldBonus: number,
	oilBonus: number,
	x: number,
	y: number,
}

export type NationEconomy = {
	factionId: string,
	gold: number,
	oil: number,
	goldPerSec: number,
	oilPerSec: number,
	manpowerPerSec: number,
	popCap: number,
	totalTroops: number,
	regionCount: number,
	aiDefenseMode: string, -- "SMART" | "FORTIFY" | "MANUAL"
	isPlayer: boolean,
}

-- Calcula el nivel de amenaza de una provincia propia mirando las tropas enemigas en sus fronteras
function DefenseAI.CalculateThreatScore(
	region: RegionState,
	allRegions: { [string]: RegionState },
	now: number
): (number, string?)
	local threat = 0
	local strongestEnemyId: string? = nil
	local strongestEnemyTroops = 0

	for _, neighborId in ipairs(region.neighbors) do
		local neighbor = allRegions[neighborId]
		if neighbor and neighbor.owner ~= region.owner then
			local enemyWeight = neighbor.troops
			if neighbor.owner ~= "NEUTRAL" then
				enemyWeight = enemyWeight * 1.35 -- Países rivales activos representan mayor peligro que neutrales
			else
				enemyWeight = enemyWeight * 0.35
			end
			threat += enemyWeight
			if neighbor.owner ~= "NEUTRAL" and neighbor.troops > strongestEnemyTroops then
				strongestEnemyTroops = neighbor.troops
				strongestEnemyId = neighbor.id
			end
		end
	end

	-- Si la región está recientemente bajo ataque, prioridad máxima para la IA de Defensa
	if region.underAttackUntil > now then
		threat = threat * 2.2 + 120
	end

	-- Si es un centro económico o estratégico (Puerto/Canal, Ciudad, Silo), proteger con más celo
	if region.building == "Port" or region.building == "City" or region.building == "MissileSilo" then
		threat = threat * 1.25
	end

	return threat, strongestEnemyId
end

-- Ejecuta la IA de Defensa Automática para una facción (especialmente el país del jugador)
-- NUNCA construye edificios por el jugador ni conquista territorios nuevos sin permiso:
-- Se encarga exclusivamente de:
-- 1) Fuego automático de Búnkeres/Fuertes contra tropas hostiles adyacentes.
-- 2) Redistribución inteligente de guarniciones desde la retaguardia segura hacia las fronteras amenazadas.
-- 3) Intercepción / contra-defensa reactiva cuando una provincia propia está siendo atacada.
function DefenseAI.StepPlayerCountryDefense(
	factionId: string,
	aiMode: string,
	allRegions: { [string]: RegionState },
	now: number,
	emitActionCallback: (
		actionType: string,
		fromId: string,
		toId: string,
		amount: number,
		summary: string
	) -> ()
)
	-- 1. FUEGO AUTOMÁTICO DE BÚNKERES / FUERTES (Activo en TODOS los modos, incluso MANUAL)
	for _, region in pairs(allRegions) do
		if region.owner == factionId and region.building == "Fortress" then
			local bestTarget: RegionState? = nil
			for _, neighborId in ipairs(region.neighbors) do
				local neighbor = allRegions[neighborId]
				if
					neighbor
					and neighbor.owner ~= factionId
					and neighbor.owner ~= "NEUTRAL"
					and neighbor.troops > 15
				then
					if not bestTarget or neighbor.troops > bestTarget.troops then
						bestTarget = neighbor
					end
				end
			end

			if bestTarget then
				local turretDamage = math.clamp(math.floor(region.troops * 0.08) + 8, 6, 35)
				bestTarget.troops = math.max(5, bestTarget.troops - turretDamage)
				emitActionCallback(
					"AI_TURRET",
					region.id,
					bestTarget.id,
					turretDamage,
					string.format(
						"🛡️ Búnker IA en %s bombardeó a %s (-%d)",
						region.name,
						bestTarget.name,
						turretDamage
					)
				)
			end
		end
	end

	if aiMode == "MANUAL" then
		return
	end

	-- 2. MOVIMIENTO TÁCTICO DE RESERVAS INTERNAS HACIA FRONTERAS AMENAZADAS
	local ownedRegions: { RegionState } = {}
	local threats: { [string]: number } = {}

	for _, region in pairs(allRegions) do
		if region.owner == factionId then
			table.insert(ownedRegions, region)
			local threatScore = DefenseAI.CalculateThreatScore(region, allRegions, now)
			threats[region.id] = threatScore
		end
	end

	if #ownedRegions < 2 then
		return
	end

	-- Buscar una provincia interior o poco amenazada con superávit de tropas para reforzar la frontera más crítica
	for _, donor in ipairs(ownedRegions) do
		local donorThreat = threats[donor.id] or 0
		local minReserve = if aiMode == "FORTIFY" then 30 else 45

		if donor.troops > minReserve + 25 then
			local bestBorderNeighbor: RegionState? = nil
			local highestThreatRatio = 1.25 -- Necesita al menos 25% más amenaza que el donante

			for _, neighborId in ipairs(donor.neighbors) do
				local neighbor = allRegions[neighborId]
				if neighbor and neighbor.owner == factionId then
					local neighborThreat = threats[neighbor.id] or 0
					local deficit = neighborThreat - neighbor.troops
					if neighborThreat > donorThreat * highestThreatRatio and deficit > -40 then
						highestThreatRatio = neighborThreat / math.max(1, donorThreat)
						bestBorderNeighbor = neighbor
					end
				end
			end

			if bestBorderNeighbor then
				local sendRatio = if aiMode == "FORTIFY" then 0.40 else 0.28
				local transferAmount = math.floor((donor.troops - minReserve) * sendRatio)
				if transferAmount >= 12 then
					donor.troops -= transferAmount
					bestBorderNeighbor.troops += transferAmount
					emitActionCallback(
						"AI_REINFORCE",
						donor.id,
						bestBorderNeighbor.id,
						transferAmount,
						string.format(
							"🤖 IA Defensa reforzó frontera %s desde %s (+%d)",
							bestBorderNeighbor.name,
							donor.name,
							transferAmount
						)
					)
				end
			end
		end
	end
end

-- IA para los Países Rivales (Bots que sí se expanden, construyen y defienden sus fronteras)
function DefenseAI.StepRivalBotNation(
	factionId: string,
	economy: NationEconomy,
	allRegions: { [string]: RegionState },
	now: number,
	executeAttackCallback: (fromId: string, toId: string, ratio: number, isAi: boolean) -> ()
)
	-- 1. Primero ejecuta la misma IA de defensa territorial para proteger sus fronteras
	DefenseAI.StepPlayerCountryDefense(factionId, "SMART", allRegions, now, function() end)

	-- 2. Construcciones de los bots rivales si tienen suficiente oro
	local owned: { RegionState } = {}
	for _, region in pairs(allRegions) do
		if region.owner == factionId then
			table.insert(owned, region)
		end
	end

	if #owned == 0 then
		return
	end

	if economy.gold >= 160 then
		for _, region in ipairs(owned) do
			if not region.building then
				local threat = DefenseAI.CalculateThreatScore(region, allRegions, now)
				local choice = "City"
				if threat > 140 then
					choice = "Fortress"
				elseif math.random() < 0.45 then
					choice = "Barracks"
				end
				local bDef = GameConfig.BUILDINGS[choice]
				if bDef and economy.gold >= bDef.costGold and economy.oil >= bDef.costOil then
					economy.gold -= bDef.costGold
					economy.oil -= bDef.costOil
					region.building = choice
					break
				end
			end
		end
	end

	-- 3. Oportunidad de ataque táctico de los países rivales (si superan claramente a un vecino)
	for _, region in ipairs(owned) do
		if region.troops >= 95 then
			local weakestTarget: RegionState? = nil
			local bestAdvantage = 1.38

			for _, neighborId in ipairs(region.neighbors) do
				local neighbor = allRegions[neighborId]
				if neighbor and neighbor.owner ~= factionId then
					local effectiveDefense = neighbor.troops
					if neighbor.building and GameConfig.BUILDINGS[neighbor.building] then
						effectiveDefense *= (1 + GameConfig.BUILDINGS[neighbor.building].defenseBonus)
					end
					if neighbor.shieldUntil > now then
						effectiveDefense *= 2.0
					end

					local advantage = region.troops / math.max(10, effectiveDefense)
					if advantage > bestAdvantage then
						bestAdvantage = advantage
						weakestTarget = neighbor
					end
				end
			end

			if weakestTarget and math.random() < 0.35 then
				executeAttackCallback(region.id, weakestTarget.id, 0.55, true)
				break
			end
		end
	end
end

return DefenseAI
