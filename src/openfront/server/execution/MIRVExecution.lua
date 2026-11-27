--!strict
-- OpenFront.io: MIRVExecution
-- Parity with packages/engine/src/execution/MIRVExecution.ts

local NukeExecution = require(script.Parent.NukeExecution)

local MIRVExecution = {}
MIRVExecution.__index = MIRVExecution

function MIRVExecution.new(
	id: string,
	owner: any,
	srcX: number,
	srcY: number,
	dstX: number,
	dstY: number,
	gameRunner: any
)
	local self = setmetatable({}, MIRVExecution)
	self.id = id
	self.owner = owner
	self.srcX = srcX
	self.srcY = srcY
	self.dstX = dstX
	self.dstY = dstY
	self.gameRunner = gameRunner
	self.finished = false
	self.hasSplit = false

	local dx = dstX - srcX
	local dy = dstY - srcY
	local dist = math.sqrt(dx * dx + dy * dy)
	self.flightDuration = math.clamp(dist / 25, 6, 15)
	self.elapsed = 0

	self.unitData = {
		id = id,
		unitType = "MIRV",
		ownerSmallID = owner.smallID,
		tileIdx = gameRunner.gameMap:GetIndex(math.floor(srcX), math.floor(srcY)),
		x = srcX,
		y = srcY,
		srcX = srcX,
		srcY = srcY,
		dstX = dstX,
		dstY = dstY,
		progress = 0,
		state = "in_flight",
	}
	gameRunner.unitGrid:AddDynamicUnit(self.unitData)

	return self
end

function MIRVExecution:IsFinished(): boolean
	return self.finished
end

function MIRVExecution:Tick(dt: number, tickNumber: number): boolean
	if self.finished then return false end

	self.elapsed += dt
	local progress = math.clamp(self.elapsed / self.flightDuration, 0, 1)
	self.unitData.progress = progress

	local curX = self.srcX + (self.dstX - self.srcX) * progress
	local curY = self.srcY + (self.dstY - self.srcY) * progress
	self.unitData.x = curX
	self.unitData.y = curY

	-- At 50% flight, MIRV separates into 5 independent warheads!
	if progress >= 0.5 and not self.hasSplit then
		self.hasSplit = true
		self.finished = true
		self.gameRunner.unitGrid:RemoveDynamicUnit(self.id)

		-- Spawn 5 MIRVWarheads scattered around target
		local offsets = {
			{ 0, 0 },
			{ -10, -10 },
			{ 10, -10 },
			{ -10, 10 },
			{ 10, 10 },
		}
		for i, off in ipairs(offsets) do
			local subDstX = math.clamp(self.dstX + off[1], 0, self.gameRunner.gameMap.w - 1)
			local subDstY = math.clamp(self.dstY + off[2], 0, self.gameRunner.gameMap.h - 1)
			local warheadId = self.id .. "_w" .. tostring(i)
			local warhead = NukeExecution.new(
				warheadId,
				self.owner,
				"MIRVWarhead",
				curX,
				curY,
				subDstX,
				subDstY,
				self.gameRunner
			)
			self.gameRunner.executionManager:Add(warhead)
		end

		return false
	end

	return true
end

return MIRVExecution
