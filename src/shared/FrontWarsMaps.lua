--!native
local FrontWarsMaps = {}
FrontWarsMaps.LIST = {
	{ id = "world", name = "WORLD", w = 480, h = 240, nationsCount = 61 },
	{ id = "pangaea", name = "PANGAEA", w = 480, h = 480, nationsCount = 29 },
	{ id = "europe", name = "EUROPE", w = 480, h = 342, nationsCount = 49 },
	{ id = "asia", name = "ASIA", w = 480, h = 288, nationsCount = 25 },
	{ id = "africa", name = "AFRICA", w = 480, h = 500, nationsCount = 36 },
	{ id = "mena", name = "MENA", w = 480, h = 210, nationsCount = 35 },
	{ id = "mars", name = "MARS", w = 480, h = 240, nationsCount = 6 },
	{ id = "oceania", name = "OCEANIA", w = 480, h = 240, nationsCount = 32 },
}

function FrontWarsMaps.get(id)
	local scriptParent = script
	local child = scriptParent:FindFirstChild(id)
	if child then
		return require(child)
	end
	return nil
end

return FrontWarsMaps
