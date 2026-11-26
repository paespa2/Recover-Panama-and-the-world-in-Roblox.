--!native
local FrontWarsMaps = {}
FrontWarsMaps.LIST = {
	{ id = "world", name = "WORLD", w = 516, h = 258, landTiles = 35509 },
	{ id = "achiran", name = "ACHIRAN", w = 500, h = 425, landTiles = 69860 },
	{ id = "europe", name = "EUROPE", w = 726, h = 418, landTiles = 134751 },
	{ id = "asia", name = "ASIA", w = 500, h = 300, landTiles = 64809 },
	{ id = "africa", name = "AFRICA", w = 487, h = 508, landTiles = 130752 },
	{ id = "pangaea", name = "PANGAEA", w = 250, h = 250, landTiles = 24365 },
	{ id = "mars", name = "MARS", w = 500, h = 250, landTiles = 82762 },
	{ id = "oceania", name = "OCEANIA", w = 416, h = 250, landTiles = 10889 },
	{ id = "mena", name = "MENA", w = 550, h = 241, landTiles = 97874 },
	{ id = "baikal", name = "BAIKAL", w = 625, h = 391, landTiles = 133081 },
}

function FrontWarsMaps.get(id)
	id = string.lower(tostring(id or "world"))
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	local mapsFolder = sharedFolder and sharedFolder:FindFirstChild("frontwars_maps")
	if mapsFolder then
		local child = mapsFolder:FindFirstChild(id)
		if child then
			return require(child)
		end
	end
	local direct = script:FindFirstChild(id)
	if direct then
		return require(direct)
	end
	return nil
end

return FrontWarsMaps
