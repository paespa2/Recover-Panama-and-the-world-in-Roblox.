--!strict
-- OpenFront.io: WarshipExecution
-- Parity with packages/engine/src/execution/WarshipExecution.ts

local WarshipExecution = {}
WarshipExecution.__index = WarshipExecution

function WarshipExecution.new(
	id: string,
	owner: any,
	startTileIdx: number,
	gameRunner: any
)
	local self = setmetatable({}, WarshipExecution)
	self.id = id
	self.owner = owner
	self.gameRunner = gameRunner
	self.finished = false
	self.health = 1000

	local gameMap = gameRunner.gameMap
	local sx, sy = gameMap:GetCoords(startTileIdx)
	self.x = sx
	self.y = sy
	self.targetX = sx
	self.targetY = sy

	self.unitData = {
		id = id,
		unitType = "Warship",
		ownerSmallID = owner.smallID,
		tileIdx = startTileIdx,
		x = sx,
		y = sy,
		health = 1000,
		state = "patrol",
	}
	gameRunner.unitGrid:AddDynamicUnit(self.unitData)

	return self
end

function WarshipExecution:SetDestination(targetTileIdx: number)
	local tx, ty = self.gameRunner.gameMap:GetCoords(targetTileIdx)
	self.targetX = tx
	self.targetY = ty
end

function WarshipExecution:TakeDamage(amount: number)
	self.health -= amount
	self.unitData.health = self.health
	if self.health <= 0 then
		self.finished = true
		self.gameRunner.unitGrid:RemoveDynamicUnit(self.id)
	end
end

function WarshipExecution:IsFinished(): boolean
	return self.finished
end

function WarshipExecution:Tick(dt: number, tickNumber: number): boolean
	if self.finished then return false end

	-- Move towards destination if commanded
	local dx = self.targetX - self.x
	local dy = self.targetY - self.y
	local dist = math.sqrt(dx * dx + dy * dy)
	local speed = 15 * dt

	if dist > 2 then
		self.x += (dx / dist) * speed
		self.y += (dy / dist) * speed
		self.unitData.x = self.x
		self.unitData.y = self.y
		self.unitData.tileIdx = self.gameRunner.gameMap:GetIndex(math.floor(self.x), math.floor(self.y))
	end

	-- Shell enemy warships or transports in range (radius 12 tiles)
	if tickNumber % 10 == 0 then -- once per second
		local nearEnemies = self.gameRunner.unitGrid:GetDynamicUnitsNear(self.x, self.y, 12)
		for _, u in ipairs(nearEnemies) do
			if u.ownerSmallID ~= self.owner.smallID and u.unitType == "Warship" then
				-- Fire shell at enemy warship: 250 damage
				local otherExec = self.gameRunner:GetExecutionById(u.id)
				if otherExec and otherExec.TakeDamage then
					otherExec:TakeDamage(250)
					break
				end
			end
		end
	end

	return true
end

return WarshipExecution
