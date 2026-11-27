--!strict
-- OpenFront.io: TerritoryRenderer
-- Blends territory colors, borders, and renders unit overlay indicators

local TerritoryRenderer = {}
TerritoryRenderer.__index = TerritoryRenderer

export type TerritoryRendererInstance = {
	w: number,
	h: number,
	ownerBuffer: buffer,
	terrainRenderer: any,
	playersBySmallID: { [number]: any },
	mySmallID: number,
	
	Init: (self: TerritoryRendererInstance, w: number, h: number, terrainRenderer: any) -> (),
	ApplyDeltas: (self: TerritoryRendererInstance, deltas: { { tileIdx: number, ownerSmallID: number } }) -> (),
	SetPlayerRoster: (self: TerritoryRendererInstance, players: { any }, mySmallID: number) -> (),
}

function TerritoryRenderer.new(): TerritoryRendererInstance
	local self = setmetatable({}, TerritoryRenderer)
	self.w = 0
	self.h = 0
	self.playersBySmallID = {}
	self.mySmallID = 0
	return (self :: any) :: TerritoryRendererInstance
end

function TerritoryRenderer:Init(w: number, h: number, terrainRenderer: any)
	self.w = w
	self.h = h
	self.terrainRenderer = terrainRenderer
	self.ownerBuffer = buffer.create(w * h * 2)
end

function TerritoryRenderer:SetPlayerRoster(players: { any }, mySmallID: number)
	self.mySmallID = mySmallID
	self.playersBySmallID = {}
	for _, p in ipairs(players) do
		self.playersBySmallID[p.smallID] = p
	end
end

function TerritoryRenderer:ApplyDeltas(deltas: { { tileIdx: number, ownerSmallID: number } })
	local tr = self.terrainRenderer
	local ob = self.ownerBuffer
	local w, h = self.w, self.h

	for _, d in ipairs(deltas) do
		local idx = d.tileIdx
		local owner = d.ownerSmallID
		buffer.writeu16(ob, idx * 2, owner)

		if owner == 0 then
			-- Reset to base natural terrain
			tr:ResetToTerrain(idx)
		else
			local p = self.playersBySmallID[owner]
			local pr = p and math.floor(p.color[1] * 255) or 200
			local pg = p and math.floor(p.color[2] * 255) or 200
			local pb = p and math.floor(p.color[3] * 255) or 200

			-- Check if border cell
			local x = idx % w
			local y = math.floor(idx / w)
			local isBorder = false

			if x > 0 and buffer.readu16(ob, (idx - 1) * 2) ~= owner then isBorder = true
			elseif x < w - 1 and buffer.readu16(ob, (idx + 1) * 2) ~= owner then isBorder = true
			elseif y > 0 and buffer.readu16(ob, (idx - w) * 2) ~= owner then isBorder = true
			elseif y < h - 1 and buffer.readu16(ob, (idx + w) * 2) ~= owner then isBorder = true
			end

			if isBorder then
				if owner == self.mySmallID then
					-- Neon golden border for human player
					tr:DrawCell(idx, 255, 235, 40)
				else
					-- Vivid bright national border
					tr:DrawCell(idx, math.min(255, math.floor(pr * 1.3)), math.min(255, math.floor(pg * 1.3)), math.min(255, math.floor(pb * 1.3)))
				end
			else
				-- Blend 60% player color + 40% natural base terrain
				local o3 = idx * 3
				local baseR = buffer.readu8(tr.baseBuffer, o3)
				local baseG = buffer.readu8(tr.baseBuffer, o3 + 1)
				local baseB = buffer.readu8(tr.baseBuffer, o3 + 2)

				local r = math.floor(pr * 0.6 + baseR * 0.4)
				local g = math.floor(pg * 0.6 + baseG * 0.4)
				local b = math.floor(pb * 0.6 + baseB * 0.4)
				tr:DrawCell(idx, r, g, b)
			end
		end
	end

	tr:Flush()
end

return TerritoryRenderer
