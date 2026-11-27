--!strict
-- OpenFront.io: UnitGrid
-- Spatial registry for structures and dynamic units (ships, missiles)

local UnitGrid = {}
UnitGrid.__index = UnitGrid

export type Structure = {
	id: string,
	unitType: string,
	tileIdx: number,
	x: number,
	y: number,
	ownerSmallID: number,
	level: number,
	isUnderConstruction: boolean,
	constructionTicksLeft: number,
}

export type DynamicUnit = {
	id: string,
	unitType: string,
	ownerSmallID: number,
	tileIdx: number,
	x: number,
	y: number,
	troops: number?,
	health: number?,
	targetTileIdx: number?,
	srcX: number?,
	srcY: number?,
	dstX: number?,
	dstY: number?,
	progress: number?,
	targetNukeId: string?,
	state: any,
}

function UnitGrid.new()
	local self = setmetatable({}, UnitGrid)
	self.structures = {} :: { [string]: Structure }
	self.structuresByTile = {} :: { [number]: Structure }
	self.dynamicUnits = {} :: { [string]: DynamicUnit }
	self.nextId = 1
	return self
end

function UnitGrid:GenerateId(): string
	self.nextId += 1
	return "u_" .. tostring(self.nextId)
end

function UnitGrid:AddStructure(s: Structure)
	self.structures[s.id] = s
	self.structuresByTile[s.tileIdx] = s
end

function UnitGrid:RemoveStructure(id: string)
	local s = self.structures[id]
	if s then
		self.structuresByTile[s.tileIdx] = nil
		self.structures[id] = nil
	end
end

function UnitGrid:GetStructureAt(tileIdx: number): Structure?
	return self.structuresByTile[tileIdx]
end

function UnitGrid:AddDynamicUnit(u: DynamicUnit)
	self.dynamicUnits[u.id] = u
end

function UnitGrid:RemoveDynamicUnit(id: string)
	self.dynamicUnits[id] = nil
end

function UnitGrid:GetStructuresNear(x: number, y: number, radius: number): { Structure }
	local res = {}
	local r2 = radius * radius
	for _, s in pairs(self.structures) do
		local dx = s.x - x
		local dy = s.y - y
		if (dx * dx + dy * dy) <= r2 then
			table.insert(res, s)
		end
	end
	return res
end

function UnitGrid:GetDynamicUnitsNear(x: number, y: number, radius: number, unitType: string?): { DynamicUnit }
	local res = {}
	local r2 = radius * radius
	for _, u in pairs(self.dynamicUnits) do
		if unitType == nil or u.unitType == unitType then
			local dx = u.x - x
			local dy = u.y - y
			if (dx * dx + dy * dy) <= r2 then
				table.insert(res, u)
			end
		end
	end
	return res
end

return UnitGrid
