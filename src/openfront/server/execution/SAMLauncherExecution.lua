--!strict
-- OpenFront.io: SAMLauncherExecution
-- Parity with packages/engine/src/execution/SAMLauncherExecution.ts

local Config = require(script.Parent.Parent.Parent.shared.Config)

local SAMLauncherExecution = {}
SAMLauncherExecution.__index = SAMLauncherExecution

function SAMLauncherExecution.new(
	id: string,
	owner: any,
	structureId: string,
	tileIdx: number,
	gameRunner: any
)
	local self = setmetatable({}, SAMLauncherExecution)
	self.id = id
	self.owner = owner
	self.structureId = structureId
	self.tileIdx = tileIdx
	self.gameRunner = gameRunner
	self.finished = false
	self.cooldown = 0

	local x, y = gameRunner.gameMap:GetCoords(tileIdx)
	self.x = x
	self.y = y

	return self
end

function SAMLauncherExecution:IsFinished(): boolean
	return self.finished
end

function SAMLauncherExecution:Tick(dt: number, tickNumber: number): boolean
	if self.finished then return false end

	-- Check if structure still exists and is not under construction
	local struct = self.gameRunner.unitGrid.structures[self.structureId]
	if not struct or struct.isUnderConstruction or struct.ownerSmallID ~= self.owner.smallID then
		self.finished = true
		return false
	end

	if self.cooldown > 0 then
		self.cooldown -= dt
		return true
	end

	-- Scan for incoming nukes within range
	local samRange = Config.SAMRange(struct.level)
	local r2 = samRange * samRange

	for _, unit in pairs(self.gameRunner.unitGrid.dynamicUnits) do
		if (unit.unitType == "AtomBomb" or unit.unitType == "HydrogenBomb" or unit.unitType == "MIRVWarhead")
			and unit.ownerSmallID ~= self.owner.smallID then
			
			local dx = unit.x - self.x
			local dy = unit.y - self.y
			if (dx * dx + dy * dy) <= r2 then
				-- Intercept this nuke!
				local nukeExec = self.gameRunner:GetExecutionById(unit.id)
				if nukeExec and nukeExec.Intercept then
					nukeExec:Intercept()
					-- Set SAM cooldown (5 seconds)
					self.cooldown = 5
					break
				end
			end
		end
	end

	return true
end

return SAMLauncherExecution
