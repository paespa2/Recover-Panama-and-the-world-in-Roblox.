--!strict
-- OpenFront.io: EngineConfig
-- Parity with packages/engine/src/configuration/EngineConfig.ts

local Config = require(script.Parent.Config)
local EngineConfig = {}

EngineConfig.MIRV_BASE_COST = 25000000
EngineConfig.MIRV_COST_SCALE = 15000000

local function pow2(n: number): number
	return 2 ^ math.clamp(n, 0, 10)
end

function EngineConfig.GetCost(unitType: string, currentCount: number?, extraCount: number?, mirvsLaunched: number?): number
	local num = currentCount or 0
	local extra = extraCount or 0
	local total = num + extra

	if unitType == "Warship" then
		return math.min(1000000, (num + 1) * 250000)
	elseif unitType == "Port" then
		return math.min(1000000, math.floor(pow2(total) * 125000))
	elseif unitType == "Factory" then
		return math.min(1000000, math.floor(pow2(total) * 125000))
	elseif unitType == "City" then
		return math.min(1000000, math.floor(pow2(num) * 125000))
	elseif unitType == "DefensePost" then
		return math.min(250000, (num + 1) * 50000)
	elseif unitType == "SAMLauncher" then
		return math.min(3000000, (num + 1) * 1500000)
	elseif unitType == "MissileSilo" then
		return 1000000
	elseif unitType == "AtomBomb" then
		return 750000
	elseif unitType == "HydrogenBomb" then
		return 5000000
	elseif unitType == "MIRV" then
		local launched = mirvsLaunched or 0
		return EngineConfig.MIRV_BASE_COST + (launched * EngineConfig.MIRV_COST_SCALE)
	end

	return 0
end

-- Combat Resolution Formula
-- Returns { conquered: boolean, attackerLoss: number, defenderLoss: number }
function EngineConfig.ResolveCombatStep(
	attackerCommitted: number,
	defenderAvailable: number,
	hasDefensePost: boolean,
	terrainElevation: number?
): { conquered: boolean, attackerLoss: number, defenderLoss: number }
	local elev = terrainElevation or 0
	local elevMod = 1.0 + (elev * 0.05) -- higher elevation is slightly harder to take
	local defPostMod = hasDefensePost and Config.DEFENSE_POST_BUFF or 1.0

	local defenderStrength = math.max(1, defenderAvailable) * defPostMod * elevMod

	if attackerCommitted > defenderStrength then
		-- Attacker conquers tile
		local attackerLoss = math.floor(defenderStrength * 0.75) + 5
		local defenderLoss = defenderAvailable
		return {
			conquered = true,
			attackerLoss = math.min(attackerCommitted, attackerLoss),
			defenderLoss = defenderLoss,
		}
	else
		-- Attacker repelled
		local defenderLoss = math.floor(attackerCommitted * 0.4)
		return {
			conquered = false,
			attackerLoss = attackerCommitted,
			defenderLoss = math.min(defenderAvailable, defenderLoss),
		}
	end
end

return EngineConfig
