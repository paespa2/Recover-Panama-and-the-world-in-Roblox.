--!strict
-- OpenFront.io: NukeExecution
-- Parity with packages/engine/src/execution/NukeExecution.ts

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("OpenFront"):WaitForChild("Shared"):WaitForChild("Config"))

local NukeExecution = {}
NukeExecution.__index = NukeExecution

function NukeExecution.new(
	id: string,
	owner: any,
	nukeType: "AtomBomb" | "HydrogenBomb" | "MIRVWarhead",
	srcX: number,
	srcY: number,
	dstX: number,
	dstY: number,
	gameRunner: any
)
	local self = setmetatable({}, NukeExecution)
	self.id = id
	self.owner = owner
	self.nukeType = nukeType
	self.srcX = srcX
	self.srcY = srcY
	self.dstX = dstX
	self.dstY = dstY
	self.gameRunner = gameRunner
	self.finished = false
	self.intercepted = false

	local dx = dstX - srcX
	local dy = dstY - srcY
	local dist = math.sqrt(dx * dx + dy * dy)
	-- Flight duration: ~5 to 12 seconds
	self.flightDuration = math.clamp(dist / 30, 4, 12)
	self.elapsed = 0

	local mag = Config.NUKE_MAGNITUDES[nukeType] or { inner = 12, outer = 30 }
	self.innerRadius = mag.inner
	self.outerRadius = mag.outer

	self.unitData = {
		id = id,
		unitType = nukeType,
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

function NukeExecution:Intercept()
	self.intercepted = true
	self.finished = true
	self.gameRunner.unitGrid:RemoveDynamicUnit(self.id)
end

function NukeExecution:IsFinished(): boolean
	return self.finished
end

function NukeExecution:Tick(dt: number, tickNumber: number): boolean
	if self.finished then return false end

	self.elapsed += dt
	local progress = math.clamp(self.elapsed / self.flightDuration, 0, 1)
	self.unitData.progress = progress

	-- Current position along line
	local curX = self.srcX + (self.dstX - self.srcX) * progress
	local curY = self.srcY + (self.dstY - self.srcY) * progress
	self.unitData.x = curX
	self.unitData.y = curY

	if progress >= 1 then
		-- Detonation!
		self:Detonate()
		self.finished = true
		self.gameRunner.unitGrid:RemoveDynamicUnit(self.id)
		return false
	end

	return true
end

function NukeExecution:Detonate()
	local gameMap = self.gameRunner.gameMap
	local unitGrid = self.gameRunner.unitGrid

	local cx = math.floor(self.dstX)
	local cy = math.floor(self.dstY)

	local minX = math.max(0, cx - self.outerRadius)
	local maxX = math.min(gameMap.w - 1, cx + self.outerRadius)
	local minY = math.max(0, cy - self.outerRadius)
	local maxY = math.min(gameMap.h - 1, cy + self.outerRadius)

	local innerR2 = self.innerRadius * self.innerRadius
	local outerR2 = self.outerRadius * self.outerRadius

	-- Destroy structures inside inner radius
	local structs = unitGrid:GetStructuresNear(cx, cy, self.innerRadius)
	for _, s in ipairs(structs) do
		unitGrid:RemoveStructure(s.id)
	end

	-- Affect tiles
	for y = minY, maxY do
		for x = minX, maxX do
			local dx = x - cx
			local dy = y - cy
			local d2 = dx * dx + dy * dy
			local idx = gameMap:GetIndex(x, y)

			if d2 <= innerR2 then
				-- Complete obliteration: reset tile owner to unowned / wasteland
				if gameMap:IsLand(idx) then
					gameMap:SetOwner(idx, 0)
					self.gameRunner:RecordTileDelta(idx, 0)
				end
			elseif d2 <= outerR2 then
				-- Outer blast: kills troops of tile owner
				local owner = gameMap:GetOwner(idx)
				if owner > 0 then
					local p = self.gameRunner.playersBySmallID[owner]
					if p then
						p:SpendTroops(math.floor(p.troops * 0.002))
					end
				end
			end
		end
	end
end

return NukeExecution
