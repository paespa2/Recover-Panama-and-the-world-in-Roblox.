--!strict
-- OpenFront.io: MapRegistry
-- Indexes and provides fast decoding for all 10 official frontwars maps

local GameTypes = require(script.Parent.GameTypes)

local MapRegistry = {}

local MAP_IDS = {
	"world", "europe", "asia", "africa", "oceania",
	"mena", "achiran", "baikal", "mars", "pangaea"
}

-- Base64 character decoding table
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_MAP = {}
for i = 1, #B64_CHARS do
	B64_MAP[string.byte(B64_CHARS, i)] = i - 1
end

function MapRegistry.DecodeB64(str: string): buffer
	local clean = string.gsub(str, "[^A-Za-z0-9+/]", "")
	local len = #clean
	local outLen = math.floor(len * 3 / 4)
	local outBuf = buffer.create(outLen)
	local outPos = 0

	local i = 1
	while i <= len - 3 do
		local b1 = B64_MAP[string.byte(clean, i)] or 0
		local b2 = B64_MAP[string.byte(clean, i + 1)] or 0
		local b3 = B64_MAP[string.byte(clean, i + 2)] or 0
		local b4 = B64_MAP[string.byte(clean, i + 3)] or 0

		local triple = bit32.bor(
			bit32.lshift(b1, 18),
			bit32.lshift(b2, 12),
			bit32.lshift(b3, 6),
			b4
		)

		if outPos < outLen then
			buffer.writeu8(outBuf, outPos, bit32.band(bit32.rshift(triple, 16), 0xFF))
			outPos += 1
		end
		if outPos < outLen then
			buffer.writeu8(outBuf, outPos, bit32.band(bit32.rshift(triple, 8), 0xFF))
			outPos += 1
		end
		if outPos < outLen then
			buffer.writeu8(outBuf, outPos, bit32.band(triple, 0xFF))
			outPos += 1
		end

		i += 4
	end

	return outBuf
end

local mapModulesCache = {}

local function getMapFolder(): Instance?
	local RS = game:GetService("ReplicatedStorage")
	local shared = RS:FindFirstChild("Shared")
	if shared then
		local maps = shared:FindFirstChild("frontwars_maps")
		if maps then return maps end
	end
	local openfront = RS:FindFirstChild("OpenFront")
	if openfront then
		local maps = openfront:FindFirstChild("Maps")
		if maps then return maps end
	end
	return nil
end

function MapRegistry.GetMap(mapId: string): GameTypes.MapData?
	local id = string.lower(mapId)
	if mapModulesCache[id] then
		return mapModulesCache[id]
	end

	local folder = getMapFolder()
	if folder then
		local mod = folder:FindFirstChild(id)
		if mod and mod:IsA("ModuleScript") then
			local data = require(mod) :: any
			mapModulesCache[id] = data
			return data
		end
	end

	return nil
end

function MapRegistry.ListMaps(): { [number]: { id: string, name: string, w: number, h: number, tag: string, subtitle: string, landTiles: number, impassableTiles: number, nationsCount: number } }
	local list = {}
	for _, id in ipairs(MAP_IDS) do
		local m = MapRegistry.GetMap(id)
		if m then
			table.insert(list, {
				id = m.id,
				name = m.name,
				w = m.w,
				h = m.h,
				tag = m.tag,
				subtitle = m.subtitle,
				landTiles = m.landTiles,
				impassableTiles = m.impassableTiles,
				nationsCount = m.nations and #m.nations or 0,
			})
		end
	end
	return list
end

return MapRegistry
