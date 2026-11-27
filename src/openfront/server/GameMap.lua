--!strict
-- OpenFront.io: GameMap
-- Fast buffer-based terrain and ownership grid

local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("OpenFront"):WaitForChild("Shared")
local TerrainBytes = require(Shared:WaitForChild("TerrainBytes"))
local MapRegistry = require(Shared:WaitForChild("MapRegistry"))

local GameMap = {}
GameMap.__index = GameMap

export type GameMapInstance = {
	w: number,
	h: number,
	totalTiles: number,
	terrainBuf: buffer,
	ownerBuf: buffer,
	landTilesCount: number,
	ownerCounts: { [number]: number },
	mapData: any,
	
	GetIndex: (self: GameMapInstance, x: number, y: number) -> number,
	GetCoords: (self: GameMapInstance, idx: number) -> (number, number),
	InBounds: (self: GameMapInstance, x: number, y: number) -> boolean,
	GetOwner: (self: GameMapInstance, idx: number) -> number,
	SetOwner: (self: GameMapInstance, idx: number, smallID: number) -> (),
	IsLand: (self: GameMapInstance, idx: number) -> boolean,
	IsOcean: (self: GameMapInstance, idx: number) -> boolean,
	IsShoreline: (self: GameMapInstance, idx: number) -> boolean,
	IsImpassable: (self: GameMapInstance, idx: number) -> boolean,
	GetElevation: (self: GameMapInstance, idx: number) -> number,
	GetNeighbors4: (self: GameMapInstance, idx: number) -> { number },
}

function GameMap.new(mapId: string): GameMapInstance
	local self = setmetatable({}, GameMap)
	local mapData = MapRegistry.GetMap(mapId)
	if not mapData then
		error("Failed to load map: " .. tostring(mapId))
	end

	self.mapData = mapData
	self.w = mapData.w
	self.h = mapData.h
	self.totalTiles = self.w * self.h

	-- 1 byte per tile for terrain (flags + elevation)
	self.terrainBuf = buffer.create(self.totalTiles)
	-- 2 bytes per tile for owner smallID (0 = unowned/water, 1..65535 = players)
	self.ownerBuf = buffer.create(self.totalTiles * 2)

	self.ownerCounts = {}
	self.landTilesCount = 0

	-- Decode Land Mask
	local maskRaw = MapRegistry.DecodeB64(mapData.maskB64)
	local elevRaw = mapData.elevB64 and MapRegistry.DecodeB64(mapData.elevB64) or nil
	local impRaw = mapData.impB64 and MapRegistry.DecodeB64(mapData.impB64) or nil

	local elevLandCounter = 0
	for y = 0, self.h - 1 do
		for x = 0, self.w - 1 do
			local idx = y * self.w + x
			local byteIdx = math.floor(idx / 8)
			local bitIdx = idx % 8

			local isLand = false
			if byteIdx < buffer.len(maskRaw) then
				local b = buffer.readu8(maskRaw, byteIdx)
				isLand = bit32.btest(b, bit32.lshift(1, bitIdx))
			end

			local elevation = 0
			local isImpassable = false

			if isLand then
				self.landTilesCount += 1
				-- Read 4-bit elevation nibble
				if elevRaw then
					local nibbleIdx = elevLandCounter
					local eByte = math.floor(nibbleIdx / 2)
					if eByte < buffer.len(elevRaw) then
						local val = buffer.readu8(elevRaw, eByte)
						if nibbleIdx % 2 == 0 then
							elevation = bit32.band(val, 0x0F)
						else
							elevation = bit32.band(bit32.rshift(val, 4), 0x0F)
						end
					end
				end
				elevLandCounter += 1

				-- Check impassable mountain
				if impRaw and byteIdx < buffer.len(impRaw) then
					local ib = buffer.readu8(impRaw, byteIdx)
					isImpassable = bit32.btest(ib, bit32.lshift(1, bitIdx))
				end
			end

			local packed = TerrainBytes.Pack(isLand, false, not isLand, isImpassable, elevation)
			buffer.writeu8(self.terrainBuf, idx, packed)
			buffer.writeu16(self.ownerBuf, idx * 2, 0)
		end
	end

	-- Derive shorelines: Any land tile adjacent to ocean is shoreline
	for y = 0, self.h - 1 do
		for x = 0, self.w - 1 do
			local idx = y * self.w + x
			local b = buffer.readu8(self.terrainBuf, idx)
			if TerrainBytes.IsLand(b) and not TerrainBytes.IsImpassable(b) then
				local hasOceanNeighbor = false
				local neighbors = {
					x > 0 and (idx - 1) or nil,
					x < self.w - 1 and (idx + 1) or nil,
					y > 0 and (idx - self.w) or nil,
					y < self.h - 1 and (idx + self.w) or nil,
				}
				for _, nIdx in ipairs(neighbors) do
					local nb = buffer.readu8(self.terrainBuf, nIdx)
					if TerrainBytes.IsOcean(nb) then
						hasOceanNeighbor = true
						break
					end
				end
				if hasOceanNeighbor then
					local elev = TerrainBytes.GetElevation(b)
					local newPacked = TerrainBytes.Pack(true, true, false, false, elev)
					buffer.writeu8(self.terrainBuf, idx, newPacked)
				end
			end
		end
	end

	return (self :: any) :: GameMapInstance
end

function GameMap:GetIndex(x: number, y: number): number
	return y * self.w + x
end

function GameMap:GetCoords(idx: number): (number, number)
	local x = idx % self.w
	local y = math.floor(idx / self.w)
	return x, y
end

function GameMap:InBounds(x: number, y: number): boolean
	return x >= 0 and x < self.w and y >= 0 and y < self.h
end

function GameMap:GetOwner(idx: number): number
	if idx < 0 or idx >= self.totalTiles then return 0 end
	return buffer.readu16(self.ownerBuf, idx * 2)
end

function GameMap:SetOwner(idx: number, smallID: number)
	if idx < 0 or idx >= self.totalTiles then return end
	local old = buffer.readu16(self.ownerBuf, idx * 2)
	if old == smallID then return end

	if old > 0 and self.ownerCounts[old] then
		self.ownerCounts[old] = math.max(0, self.ownerCounts[old] - 1)
	end
	if smallID > 0 then
		self.ownerCounts[smallID] = (self.ownerCounts[smallID] or 0) + 1
	end

	buffer.writeu16(self.ownerBuf, idx * 2, smallID)
end

function GameMap:IsLand(idx: number): boolean
	if idx < 0 or idx >= self.totalTiles then return false end
	return TerrainBytes.IsLand(buffer.readu8(self.terrainBuf, idx))
end

function GameMap:IsOcean(idx: number): boolean
	if idx < 0 or idx >= self.totalTiles then return true end
	return TerrainBytes.IsOcean(buffer.readu8(self.terrainBuf, idx))
end

function GameMap:IsShoreline(idx: number): boolean
	if idx < 0 or idx >= self.totalTiles then return false end
	return TerrainBytes.IsShoreline(buffer.readu8(self.terrainBuf, idx))
end

function GameMap:IsImpassable(idx: number): boolean
	if idx < 0 or idx >= self.totalTiles then return true end
	return TerrainBytes.IsImpassable(buffer.readu8(self.terrainBuf, idx))
end

function GameMap:GetElevation(idx: number): number
	if idx < 0 or idx >= self.totalTiles then return 0 end
	return TerrainBytes.GetElevation(buffer.readu8(self.terrainBuf, idx))
end

function GameMap:GetNeighbors4(idx: number): { number }
	local x = idx % self.w
	local y = math.floor(idx / self.w)
	local res = {}
	if x > 0 then table.insert(res, idx - 1) end
	if x < self.w - 1 then table.insert(res, idx + 1) end
	if y > 0 then table.insert(res, idx - self.w) end
	if y < self.h - 1 then table.insert(res, idx + self.w) end
	return res
end

return GameMap
