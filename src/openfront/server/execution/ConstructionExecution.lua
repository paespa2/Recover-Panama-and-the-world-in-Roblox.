--!strict
-- OpenFront.io: ConstructionExecution
-- Parity with packages/engine/src/execution/ConstructionExecution.ts

local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("OpenFront"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EngineConfig = require(Shared:WaitForChild("EngineConfig"))

local ConstructionExecution = {}
ConstructionExecution.__index = ConstructionExecution

function ConstructionExecution.new(
	id: string,
	owner: any,
	unitType: string,
	tileIdx: number,
	gameRunner: any
)
	local self = setmetatable({}, ConstructionExecution)
	self.id = id
	self.owner = owner
	self.unitType = unitType
	self.tileIdx = tileIdx
	self.gameRunner = gameRunner
	self.finished = false

	local durationTicks = 50 -- 5s default
	if unitType == "SAMLauncher" then
		durationTicks = Config.SAM_CONSTRUCTION_TICKS -- 30s
	end
	self.ticksRemaining = durationTicks

	local gameMap = gameRunner.gameMap
	local x, y = gameMap:GetCoords(tileIdx)

	self.structureData = {
		id = id,
		unitType = unitType,
		tileIdx = tileIdx,
		x = x,
		y = y,
		ownerSmallID = owner.smallID,
		level = 1,
		isUnderConstruction = true,
		constructionTicksLeft = durationTicks,
	}

	gameRunner.unitGrid:AddStructure(self.structureData)

	-- Update player's structure count
	if unitType == "City" then owner.citiesCount += 1
	elseif unitType == "Port" then owner.portsCount += 1
	elseif unitType == "Factory" then owner.factoriesCount += 1
	elseif unitType == "DefensePost" then owner.defensePostsCount += 1
	elseif unitType == "MissileSilo" then owner.silosCount += 1
	elseif unitType == "SAMLauncher" then owner.samsCount += 1
	end

	return self
end

function ConstructionExecution.CanBuild(
	owner: any,
	unitType: string,
	tileIdx: number,
	gameRunner: any
): (boolean, string?)
	local gameMap = gameRunner.gameMap
	local unitGrid = gameRunner.unitGrid

	if not gameMap:InBounds(gameMap:GetCoords(tileIdx)) then
		return false, "Fuera de los límites del mapa"
	end

	-- Must be inside owned territory
	if gameMap:GetOwner(tileIdx) ~= owner.smallID then
		return false, "Solo puedes construir en tu propio territorio"
	end

	-- Port requires shoreline / coastal tile
	if unitType == "Port" then
		if not gameMap:IsShoreline(tileIdx) then
			return false, "El Puerto debe construirse en la costa"
		end
	else
		-- Other structures must be on land and not impassable
		if not gameMap:IsLand(tileIdx) or gameMap:IsImpassable(tileIdx) then
			return false, "No se puede construir en agua o montañas intransitables"
		end
	end

	-- Check minimum 15-tile distance from other structures
	local x, y = gameMap:GetCoords(tileIdx)
	local near = unitGrid:GetStructuresNear(x, y, Config.STRUCTURE_MIN_DIST)
	if #near > 0 then
		return false, "Demasiado cerca de otra estructura (mínimo 15 celdas)"
	end

	-- Check gold cost
	local cost = 0
	if unitType == "City" then
		cost = EngineConfig.GetCost("City", owner.citiesCount)
	elseif unitType == "Port" then
		cost = EngineConfig.GetCost("Port", owner.portsCount, owner.factoriesCount)
	elseif unitType == "Factory" then
		cost = EngineConfig.GetCost("Factory", owner.factoriesCount, owner.portsCount)
	elseif unitType == "DefensePost" then
		cost = EngineConfig.GetCost("DefensePost", owner.defensePostsCount)
	elseif unitType == "MissileSilo" then
		cost = EngineConfig.GetCost("MissileSilo", owner.silosCount)
	elseif unitType == "SAMLauncher" then
		cost = EngineConfig.GetCost("SAMLauncher", owner.samsCount)
	end

	if owner.gold < cost then
		return false, "Oro insuficiente (Cuesta $" .. tostring(cost) .. ")"
	end

	return true, nil
end

function ConstructionExecution:IsFinished(): boolean
	return self.finished
end

function ConstructionExecution:Tick(dt: number, tickNumber: number): boolean
	if self.finished then return false end

	-- Check if tile was conquered during construction
	if self.gameRunner.gameMap:GetOwner(self.tileIdx) ~= self.owner.smallID then
		self.gameRunner.unitGrid:RemoveStructure(self.id)
		self.finished = true
		return false
	end

	self.ticksRemaining -= 1
	self.structureData.constructionTicksLeft = self.ticksRemaining

	if self.ticksRemaining <= 0 then
		self.structureData.isUnderConstruction = false
		self.finished = true
		return false
	end

	return true
end

return ConstructionExecution
