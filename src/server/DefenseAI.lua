--!strict
-- DefenseAI.lua
-- Agente de IA de Defensa Territorial del Jugador + IA Estratégica de Líderes Históricos y Bots
-- Soporta eras evolutivas (Dinosaurio -> Homo Sapiens -> Tesla -> Andrómeda), Crisis Humanitarias y Comandantes.

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
	unitType: string?, -- Tropa especializada o armamento bélico estacionado
	crisisId: string?, -- Crisis humanitaria activa en la región
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
	commanderId: string,
	evolutionLevel: number,
	gold: number,
	oil: number,
	science: number,
	goldPerSec: number,
	oilPerSec: number,
	sciencePerSec: number,
	manpowerPerSec: number,
	popCap: number,
	totalTroops: number,
	regionCount: number,
	aiDefenseMode: string, -- "SMART" | "FORTIFY" | "MANUAL"
	isPlayer: boolean,
}

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
				enemyWeight = enemyWeight * 1.35
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

	if region.underAttackUntil > now then
		threat = threat * 2.2 + 120
	end

	if region.crisisId then
		threat += 90 -- Priorizar también regiones debilitadas por crisis humanitarias
	end

	if
		region.building == "Port"
		or region.building == "City"
		or region.building == "ResearchLab"
		or region.building == "MissileSilo"
	then
		threat = threat * 1.25
	end

	return threat, strongestEnemyId
end

function DefenseAI.StepPlayerCountryDefense(
	factionId: string,
	aiMode: string,
	commanderId: string,
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
	local turretMultiplier = if commanderId == "TESLA" then 1.85 else 1.0

	-- 1. FUEGO AUTOMÁTICO DE BÚNKERES / TORRETAS TESLA IA
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
				local baseDmg = math.clamp(math.floor(region.troops * 0.08) + 8, 6, 38)
				local turretDamage = math.floor(baseDmg * turretMultiplier)
				bestTarget.troops = math.max(5, bestTarget.troops - turretDamage)
				emitActionCallback(
					"AI_TURRET",
					region.id,
					bestTarget.id,
					turretDamage,
					string.format(
						"🛡️ Búnker IA en %s electrocutó a %s (-%d)",
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
			threats[region.id] = DefenseAI.CalculateThreatScore(region, allRegions, now)
		end
	end

	if #ownedRegions < 2 then
		return
	end

	for _, donor in ipairs(ownedRegions) do
		local donorThreat = threats[donor.id] or 0
		local minReserve = if aiMode == "FORTIFY" then 30 else 45

		if donor.troops > minReserve + 25 then
			local bestBorderNeighbor: RegionState? = nil
			local highestThreatRatio = 1.25

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
							"🤖 IA Defensa reforzó %s desde %s (+%d)",
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

-- IA para Naciones y Líderes Históricos Rivales (Tesla, Newton, Trump, Escobar, Gengis Kan, Andrómeda, Dinosaurios)
function DefenseAI.StepRivalBotNation(
	factionId: string,
	economy: NationEconomy,
	allRegions: { [string]: RegionState },
	now: number,
	executeAttackCallback: (fromId: string, toId: string, ratio: number, isAi: boolean) -> ()
)
	DefenseAI.StepPlayerCountryDefense(factionId, "SMART", economy.commanderId, allRegions, now, function() end)

	local owned: { RegionState } = {}
	for _, region in pairs(allRegions) do
		if region.owner == factionId then
			table.insert(owned, region)
		end
	end

	if #owned == 0 then
		return
	end

	-- Evolución científica automática de los bots si acumulan suficiente Ciencia
	local nextEra = GameConfig.EVOLUTION_STAGES[economy.evolutionLevel + 1]
	if nextEra and economy.science >= nextEra.costScience and economy.gold >= nextEra.costGold then
		economy.science -= nextEra.costScience
		economy.gold -= nextEra.costGold
		economy.evolutionLevel += 1
	end

	-- Construcciones de los bots
	if economy.gold >= 160 then
		for _, region in ipairs(owned) do
			if not region.building then
				local threat = DefenseAI.CalculateThreatScore(region, allRegions, now)
				local choice = "City"
				if threat > 140 then
					choice = "Fortress"
				elseif math.random() < 0.30 then
					choice = "ResearchLab"
				elseif math.random() < 0.50 then
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

	-- Ataques tácticos de los líderes históricos
	for _, region in ipairs(owned) do
		if region.troops >= 95 then
			local weakestTarget: RegionState? = nil
			local bestAdvantage = 1.36

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

			if weakestTarget and math.random() < 0.38 then
				executeAttackCallback(region.id, weakestTarget.id, 0.55, true)
				break
			end
		end
	end
end

return DefenseAI
