--!strict
-- OpenFront.io: Config
-- Parity with packages/engine-lib/src/configuration/Config.ts

local Config = {}

Config.PERCENT_TILES_OWNED_TO_WIN = 80
Config.TICKS_PER_SECOND = 10
Config.MS_PER_TICK = 100

-- Construction durations (in ticks at 10 ticks/sec)
Config.SAM_CONSTRUCTION_TICKS = 30 * Config.TICKS_PER_SECOND -- 30s
Config.PORT_CONSTRUCTION_TICKS = 5 * Config.TICKS_PER_SECOND -- 5s
Config.FACTORY_CONSTRUCTION_TICKS = 5 * Config.TICKS_PER_SECOND -- 5s
Config.SILO_CONSTRUCTION_TICKS = 5 * Config.TICKS_PER_SECOND -- 5s
Config.CITY_CONSTRUCTION_TICKS = 5 * Config.TICKS_PER_SECOND -- 5s
Config.DEFENSE_POST_CONSTRUCTION_TICKS = 5 * Config.TICKS_PER_SECOND -- 5s

-- Defense and Ranges
Config.DEFENSE_POST_RANGE = 20
Config.DEFENSE_POST_BUFF = 5.0 -- Reduces attacker speed / increases defender resistance 5x
Config.STRUCTURE_MIN_DIST = 15
Config.MAX_SAM_RANGE = 150

function Config.SAMRange(level: number): number
	local lvl = math.max(1, level or 1)
	return math.floor(Config.MAX_SAM_RANGE - 480 / (lvl + 5))
end

-- Nuclear Blast Magnitudes (inner = total disintegration + fallout, outer = heavy troop death)
Config.NUKE_MAGNITUDES = {
	AtomBomb = { inner = 12, outer = 30 },
	HydrogenBomb = { inner = 80, outer = 100 },
	MIRVWarhead = { inner = 12, outer = 18 },
}

-- Troop Limits
Config.BASE_MAX_TROOPS = 1000
Config.CITY_TROOP_INCREASE = 50000

function Config.MaxTroops(tilesCount: number, citiesCount: number, playerType: string?): number
	local tiles = math.max(1, tilesCount or 1)
	local cities = math.max(0, citiesCount or 0)
	local base = Config.BASE_MAX_TROOPS + math.floor((tiles ^ 0.8) * 12)
	local fromCities = cities * Config.CITY_TROOP_INCREASE
	local total = base + fromCities
	if playerType == "Nation" then
		return math.floor(total * 0.8)
	end
	return total
end

-- Troop Growth Rate (per tick = 100ms)
function Config.TroopIncreaseRate(currentTroops: number, maxTroops: number, playerType: string?): number
	local cur = math.max(0, currentTroops or 0)
	local max = math.max(10, maxTroops or 1000)
	
	-- OpenFront formula: toAdd = 10 + (troops^0.73)/4; toAdd *= (1 - troops/max)
	local toAdd = 10 + (cur ^ 0.73) / 4
	local ratio = math.clamp(1 - (cur / max), 0, 1)
	toAdd = toAdd * ratio

	-- Scaled to per tick (10 ticks/sec, base formula is per sec / tuned)
	local perTick = toAdd / Config.TICKS_PER_SECOND

	if playerType == "Bot" then
		perTick = perTick * 0.5
	elseif playerType == "Nation" then
		perTick = perTick * 0.7
	end

	return perTick
end

-- Gold Generation Rate (per second)
function Config.GoldPerSecond(tilesCount: number, factoriesCount: number, playerType: string?): number
	local tiles = math.max(1, tilesCount or 1)
	local factories = math.max(0, factoriesCount or 0)
	-- Base gold income from land plus factory multiplier
	local income = math.floor(tiles * 1.5) + (factories * 2500)
	if playerType == "Nation" then
		income = math.floor(income * 0.6)
	end
	return income
end

return Config
