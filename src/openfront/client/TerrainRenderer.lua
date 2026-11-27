--!strict
-- OpenFront.io: TerrainRenderer
-- Renders authentic OpenFront pixel shader terrain into EditableImage or Canvas

local AssetService = game:GetService("AssetService")
local MapRegistry = require(script.Parent.Parent.shared.MapRegistry)
local TerrainBytes = require(script.Parent.Parent.shared.TerrainBytes)

local TerrainRenderer = {}
TerrainRenderer.__index = TerrainRenderer

export type TerrainRendererInstance = {
	w: number,
	h: number,
	totalTiles: number,
	baseBuffer: buffer,
	pixelBuffer: buffer,
	editableImage: any,
	imageLabel: ImageLabel,
	dirtyX0: number,
	dirtyY0: number,
	dirtyX1: number,
	dirtyY1: number,

	Init: (self: TerrainRendererInstance, mapData: any, targetImageLabel: ImageLabel) -> boolean,
	DrawCell: (self: TerrainRendererInstance, idx: number, r: number, g: number, b: number) -> (),
	Flush: (self: TerrainRendererInstance) -> (),
	ResetToTerrain: (self: TerrainRendererInstance, idx: number) -> (),
}

function TerrainRenderer.new(): TerrainRendererInstance
	local self = setmetatable({}, TerrainRenderer)
	self.w = 0
	self.h = 0
	self.totalTiles = 0
	self.dirtyX0 = math.huge
	self.dirtyY0 = math.huge
	self.dirtyX1 = -1
	self.dirtyY1 = -1
	return (self :: any) :: TerrainRendererInstance
end

function TerrainRenderer:Init(mapData: any, targetImageLabel: ImageLabel): boolean
	self.w = mapData.w
	self.h = mapData.h
	self.totalTiles = self.w * self.h
	self.imageLabel = targetImageLabel

	self.baseBuffer = buffer.create(self.totalTiles * 3) -- RGB base
	self.pixelBuffer = buffer.create(self.totalTiles * 4) -- RGBA display

	-- Decode terrain
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

				if impRaw and byteIdx < buffer.len(impRaw) then
					local ib = buffer.readu8(impRaw, byteIdx)
					isImpassable = bit32.btest(ib, bit32.lshift(1, bitIdx))
				end
			end

			-- Color determination according to OpenFront ColorUtils.ts
			local r, g, b = 71, 133, 181 -- Deep ocean: #4785b5
			if isLand then
				if isImpassable then
					-- Impassable mountain ridge: #3c3c3c
					r, g, b = 60, 60, 60
				elseif elevation >= 10 then
					-- Snow/Mountain peaks: #E6E6E6
					r, g, b = 230, 230, 230
				elseif elevation >= 6 then
					-- Highlands: #C8B78A
					r, g, b = 200, 183, 138
				elseif elevation >= 3 then
					-- Plains: #BEDC8A
					r, g, b = 190, 220, 138
				else
					-- Lowland / coastal plain: #CCCB9E
					r, g, b = 204, 203, 158
				end
			else
				-- Ocean depth gradient
				local depthRatio = math.clamp(y / self.h, 0, 1)
				r = math.floor(126 - depthRatio * 55)
				g = math.floor(170 - depthRatio * 37)
				b = math.floor(203 - depthRatio * 22)
			end

			local o3 = idx * 3
			buffer.writeu8(self.baseBuffer, o3, r)
			buffer.writeu8(self.baseBuffer, o3 + 1, g)
			buffer.writeu8(self.baseBuffer, o3 + 2, b)

			local o4 = idx * 4
			buffer.writeu8(self.pixelBuffer, o4, r)
			buffer.writeu8(self.pixelBuffer, o4 + 1, g)
			buffer.writeu8(self.pixelBuffer, o4 + 2, b)
			buffer.writeu8(self.pixelBuffer, o4 + 3, 255)
		end
	end

	-- Try creating EditableImage
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(self.w, self.h) })
	end)

	if ok and img then
		local okWrite = pcall(function()
			img:WritePixelsBuffer(Vector2.zero, Vector2.new(self.w, self.h), self.pixelBuffer)
		end)
		if okWrite then
			self.editableImage = img
			self.imageLabel.ImageContent = Content.fromObject(img)
			return true
		end
	end

	return false
end

function TerrainRenderer:DrawCell(idx: number, r: number, g: number, b: number)
	if not self.pixelBuffer then return end
	local o4 = idx * 4
	buffer.writeu8(self.pixelBuffer, o4, r)
	buffer.writeu8(self.pixelBuffer, o4 + 1, g)
	buffer.writeu8(self.pixelBuffer, o4 + 2, b)

	local x = idx % self.w
	local y = math.floor(idx / self.w)
	if x < self.dirtyX0 then self.dirtyX0 = x end
	if y < self.dirtyY0 then self.dirtyY0 = y end
	if x > self.dirtyX1 then self.dirtyX1 = x end
	if y > self.dirtyY1 then self.dirtyY1 = y end
end

function TerrainRenderer:ResetToTerrain(idx: number)
	if not self.baseBuffer then return end
	local o3 = idx * 3
	local r = buffer.readu8(self.baseBuffer, o3)
	local g = buffer.readu8(self.baseBuffer, o3 + 1)
	local b = buffer.readu8(self.baseBuffer, o3 + 2)
	self:DrawCell(idx, r, g, b)
end

function TerrainRenderer:Flush()
	if not self.editableImage or self.dirtyX1 < 0 then return end

	local x0 = self.dirtyX0
	local y0 = self.dirtyY0
	local dw = self.dirtyX1 - x0 + 1
	local dh = self.dirtyY1 - y0 + 1

	self.dirtyX0 = math.huge
	self.dirtyY0 = math.huge
	self.dirtyX1 = -1
	self.dirtyY1 = -1

	if dw == self.w and dh == self.h then
		pcall(function()
			self.editableImage:WritePixelsBuffer(Vector2.zero, Vector2.new(self.w, self.h), self.pixelBuffer)
		end)
	else
		-- Extract sub-buffer for dirty rectangle
		local subBuf = buffer.create(dw * dh * 4)
		local subPos = 0
		for row = 0, dh - 1 do
			local srcIdx = ((y0 + row) * self.w + x0) * 4
			local rowBytes = dw * 4
			buffer.copy(subBuf, subPos, self.pixelBuffer, srcIdx, rowBytes)
			subPos += rowBytes
		end
		pcall(function()
			self.editableImage:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(dw, dh), subBuf)
		end)
	end
end

return TerrainRenderer
