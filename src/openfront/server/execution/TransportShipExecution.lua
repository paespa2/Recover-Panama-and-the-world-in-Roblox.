--!strict
-- OpenFront.io: TransportShipExecution
-- Parity with packages/engine/src/execution/TransportShipExecution.ts

local AttackExecution = require(script.Parent.AttackExecution)

local TransportShipExecution = {}
TransportShipExecution.__index = TransportShipExecution

function TransportShipExecution.new(
	id: string,
	owner: any,
	startTileIdx: number,
	targetTileIdx: number,
	troops: number,
	gameRunner: any
)
	local self = setmetatable({}, TransportShipExecution)
	self.id = id
	self.owner = owner
	self.startTileIdx = startTileIdx
	self.targetTileIdx = targetTileIdx
	self.troops = troops
	self.gameRunner = gameRunner
	self.finished = false

	local gameMap = gameRunner.gameMap
	local sx, sy = gameMap:GetCoords(startTileIdx)
	local tx, ty = gameMap:GetCoords(targetTileIdx)

	self.x = sx
	self.y = sy
	self.targetX = tx
	self.targetY = ty

	-- Register dynamic unit in UnitGrid
	self.unitData = {
		id = id,
		unitType = "TransportShip",
		ownerSmallID = owner.smallID,
		tileIdx = startTileIdx,
		x = sx,
		y = sy,
		troops = troops,
		targetTileIdx = targetTileIdx,
		state = "sailing",
	}
	gameRunner.unitGrid:AddDynamicUnit(self.unitData)

	return self
end

function TransportShipExecution:IsFinished(): boolean
	return self.finished
end

function TransportShipExecution:Tick(dt: number, tickNumber: number): boolean
	if self.finished then return false end

	-- Check if sunk by nearby enemy warship
	local nearWarships = self.gameRunner.unitGrid:GetDynamicUnitsNear(self.x, self.y, 8, "Warship")
	for _, ws in ipairs(nearWarships) do
		if ws.ownerSmallID ~= self.owner.smallID then
			-- Intercepted and sunk!
			self.gameRunner.unitGrid:RemoveDynamicUnit(self.id)
			self.finished = true
			return false
		end
	end

	-- Move towards target along straight line or water waypoints
	local dx = self.targetX - self.x
	local dy = self.targetY - self.y
	local dist = math.sqrt(dx * dx + dy * dy)

	local speed = 25 * dt -- speed in tiles per second
	if dist <= speed or dist < 2 then
		-- Reached target coastline! Land troops and launch AttackExecution
		self.gameRunner.unitGrid:RemoveDynamicUnit(self.id)
		self.finished = true

		local attackId = "atk_landing_" .. tostring(tickNumber)
		local landingAttack = AttackExecution.new(
			attackId,
			self.owner,
			self.targetTileIdx,
			self.troops,
			self.gameRunner
		)
		self.gameRunner.executionManager:Add(landingAttack)
		return false
	else
		-- Advance
		local stepX = (dx / dist) * speed
		local stepY = (dy / dist) * speed
		self.x += stepX
		self.y += stepY
		self.unitData.x = self.x
		self.unitData.y = self.y
		self.unitData.tileIdx = self.gameRunner.gameMap:GetIndex(math.floor(self.x), math.floor(self.y))
	end

	return true
end

return TransportShipExecution
