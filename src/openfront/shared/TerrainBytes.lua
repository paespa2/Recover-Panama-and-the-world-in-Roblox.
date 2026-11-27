--!strict
-- OpenFront.io: TerrainBytes
-- Parity with packages/engine-lib/src/game/TerrainBytes.ts

local TerrainBytes = {}

-- Bitmask constants
TerrainBytes.FLAG_LAND       = 0x80 -- 1000 0000
TerrainBytes.FLAG_SHORELINE   = 0x40 -- 0100 0000
TerrainBytes.FLAG_OCEAN       = 0x20 -- 0010 0000
TerrainBytes.FLAG_IMPASSABLE  = 0x10 -- 0001 0000
TerrainBytes.ELEVATION_MASK   = 0x0F -- 0000 1111 (0-14 magnitude)

function TerrainBytes.IsLand(b: number): boolean
	return bit32.btest(b, TerrainBytes.FLAG_LAND)
end

function TerrainBytes.IsOcean(b: number): boolean
	return bit32.btest(b, TerrainBytes.FLAG_OCEAN)
end

function TerrainBytes.IsShoreline(b: number): boolean
	return bit32.btest(b, TerrainBytes.FLAG_SHORELINE)
end

function TerrainBytes.IsImpassable(b: number): boolean
	return bit32.btest(b, TerrainBytes.FLAG_IMPASSABLE)
end

function TerrainBytes.GetElevation(b: number): number
	return bit32.band(b, TerrainBytes.ELEVATION_MASK)
end

function TerrainBytes.Pack(isLand: boolean, isShore: boolean, isOcean: boolean, isImpassable: boolean, elevation: number): number
	local val = bit32.band(elevation or 0, TerrainBytes.ELEVATION_MASK)
	if isLand then val = bit32.bor(val, TerrainBytes.FLAG_LAND) end
	if isShore then val = bit32.bor(val, TerrainBytes.FLAG_SHORELINE) end
	if isOcean then val = bit32.bor(val, TerrainBytes.FLAG_OCEAN) end
	if isImpassable then val = bit32.bor(val, TerrainBytes.FLAG_IMPASSABLE) end
	return val
end

return TerrainBytes
