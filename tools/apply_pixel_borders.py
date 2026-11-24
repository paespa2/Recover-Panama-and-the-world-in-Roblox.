with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
    text = f.read()

s1 = 'local edgeLayer = Instance.new("Frame")\nedgeLayer.Name = "EdgeLayer"'
s2 = 'local function recolorBlock(bi)'

idx1 = text.find(s1)
idx2 = text.find(s2)
assert idx1 != -1, "s1 not found"
assert idx2 != -1, "s2 not found"

replacement = """-- ============================================================================
-- FRONTERAS DE PÍXELES FINOS (LÍNEAS DELGADAS POR PEQUEÑOS PÍXELES ESTILO FRONTWARS)
-- Cada frontera entre naciones o costa se dibuja como una línea nítida de 1.5 píxeles de grosor,
-- celda por celda exacta, trazando el perímetro de cada país con su color brillante.
-- ============================================================================
local edgeLayer = Instance.new("Frame")
edgeLayer.Name = "PixelEdgeLayer"
edgeLayer.Size = UDim2.fromScale(1, 1)
edgeLayer.BackgroundTransparency = 1
edgeLayer.BorderSizePixel = 0
edgeLayer.Visible = true
edgeLayer.ZIndex = 6
edgeLayer.Parent = mapCanvas

local edgeFrames = {} -- [cell * 4 + side] = Frame
local edgeFree = {}
local myEdges = {} -- líneas de la propia nación para efecto de pulso dorado neón

local LINE_THICK_PX = 1.5

-- Modo equipos: dos dueños del mismo continente son aliados y no se dibuja contorno entre ellos
local function sameTeam(a, b)
	if not state.teamMode or a == 0 or b == 0 then
		return false
	end
	local ra, rb = state.rosterById[a], state.rosterById[b]
	return ra ~= nil and rb ~= nil and ra.continent ~= nil and ra.continent == rb.continent
end
state.sameTeam = sameTeam

local function vividColor(c, id)
	local h, s = c:ToHSV()
	local k = ((id or 0) * 37) % 100 / 100
	local sat = math.clamp(s * 1.45, 0.55, 0.9) + (k - 0.5) * 0.12
	local val = 0.9 + k * 0.1
	local hue = (h + (k - 0.5) * 0.04) % 1
	return Color3.fromHSV(hue, math.clamp(sat, 0.45, 0.95), math.clamp(val, 0.85, 1))
end
state.vividColor = vividColor

local function edgeColor(ownerId)
	if ownerId == state.myId then
		return Color3.fromRGB(255, 235, 60)
	end
	local n = state.rosterById[ownerId]
	if n and n.color then
		return vividColor(n.color, ownerId)
	end
	return Color3.new(1, 1, 1)
end

local function setCellEdge(cell, side, show, ownerId)
	local key = cell * 4 + side
	local f = edgeFrames[key]
	if not show then
		if f then
			f.Visible = false
			edgeFrames[key] = nil
			myEdges[f] = nil
			edgeFree[#edgeFree + 1] = f
		end
		return
	end
	if not f then
		f = table.remove(edgeFree)
		if not f then
			f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.ZIndex = 6
			f.Parent = edgeLayer
		end
		edgeFrames[key] = f
		local w, h = state.w, state.h
		local x, y = cell % w, cell // w

		-- Líneas delgadas de 1.5 píxeles exactos trazando cada píxel de celda
		if side == 0 then -- Derecha (vertical)
			f.AnchorPoint = Vector2.new(0.5, 0)
			f.Position = UDim2.fromScale((x + 1) / w, y / h)
			f.Size = UDim2.new(0, LINE_THICK_PX, 1 / h, 0)
		elseif side == 1 then -- Abajo (horizontal)
			f.AnchorPoint = Vector2.new(0, 0.5)
			f.Position = UDim2.fromScale(x / w, (y + 1) / h)
			f.Size = UDim2.new(1 / w, 0, 0, LINE_THICK_PX)
		elseif side == 2 then -- Izquierda (vertical)
			f.AnchorPoint = Vector2.new(0.5, 0)
			f.Position = UDim2.fromScale(x / w, y / h)
			f.Size = UDim2.new(0, LINE_THICK_PX, 1 / h, 0)
		else -- Arriba (horizontal)
			f.AnchorPoint = Vector2.new(0, 0.5)
			f.Position = UDim2.fromScale(x / w, y / h)
			f.Size = UDim2.new(1 / w, 0, 0, LINE_THICK_PX)
		end
		f.BackgroundTransparency = 0.05
		f.Visible = true
	end
	f.BackgroundColor3 = edgeColor(ownerId)
	myEdges[f] = if ownerId == state.myId then true else nil
end

local function updateCellEdges(cell)
	local owner = state.owner
	if not owner or not state.w or state.w == 0 then
		return
	end
	local o = buffer.readu8(owner, cell)
	if o == 0 then
		setCellEdge(cell, 0, false)
		setCellEdge(cell, 1, false)
		setCellEdge(cell, 2, false)
		setCellEdge(cell, 3, false)
		return
	end
	local w, h = state.w, state.h
	local x, y = cell % w, cell // w

	local r = buffer.readu8(owner, y * w + (if x == w - 1 then 0 else x + 1))
	local d = if y < h - 1 then buffer.readu8(owner, (y + 1) * w + x) else 0
	local l = buffer.readu8(owner, y * w + (if x == 0 then w - 1 else x - 1))
	local u = if y > 0 then buffer.readu8(owner, (y - 1) * w + x) else 0

	setCellEdge(cell, 0, r ~= o and not sameTeam(r, o), o)
	setCellEdge(cell, 1, d ~= o and not sameTeam(d, o), o)
	setCellEdge(cell, 2, l ~= o and not sameTeam(l, o), o)
	setCellEdge(cell, 3, u ~= o and not sameTeam(u, o), o)
end

-- Reconstruye todas las líneas de frontera pixel a pixel
local rebuildEdges
function rebuildEdges()
	state.rebuildEdges = rebuildEdges
	for key, f in pairs(edgeFrames) do
		f.Visible = false
		edgeFree[#edgeFree + 1] = f
		edgeFrames[key] = nil
	end
	table.clear(myEdges)
	local owner = state.owner
	local w, h = state.w, state.h
	if not owner or not w or w == 0 then
		return
	end
	local total = w * h
	for cell = 0, total - 1 do
		if buffer.readu8(owner, cell) ~= 0 then
			updateCellEdges(cell)
		end
		if cell % 3000 == 0 then
			task.wait()
		end
	end
end

-- El contorno del jugador late con resplandor dorado
local edgePulseAcc = 0
RunService.Heartbeat:Connect(function(dt)
	edgePulseAcc += dt
	if edgePulseAcc < 0.12 then
		return
	end
	edgePulseAcc = 0
	local k = (math.sin(os.clock() * 4) + 1) / 2
	local c = Color3.fromRGB(255, 215, 40):Lerp(Color3.fromRGB(255, 255, 240), k)
	for f in pairs(myEdges) do
		f.BackgroundColor3 = c
	end
end)

"""

text = text[:idx1] + replacement + text[idx2:]

# Also update applyDiff so that updateCellEdges is invoked on modified cells
old_diff = """			if animateFront and ownerId ~= 0 and previous ~= ownerId then
				frontPush(cell, ownerId)
			end
		end"""

new_diff = """			if animateFront and ownerId ~= 0 and previous ~= ownerId then
				frontPush(cell, ownerId)
			end
			if state.animReady and updateCellEdges then
				updateCellEdges(cell)
				local w, h = state.w, state.h
				local x, y = cell % w, cell // w
				updateCellEdges(y * w + (if x == w - 1 then 0 else x + 1))
				updateCellEdges(y * w + (if x == 0 then w - 1 else x - 1))
				if y > 0 then updateCellEdges(cell - w) end
				if y < h - 1 then updateCellEdges(cell + w) end
			end
		end"""

assert old_diff in text, "old_diff not found"
text = text.replace(old_diff, new_diff, 1)

# Remove the old updateBlockEdges in recolorBlock
old_recolor = """	if ownerChanged and state.animReady then
		local bw = state.blockW
		updateBlockEdges(bi)
		updateBlockEdges(bi - 1 + (if (bi - 1) % bw == 0 then bw else 0)) -- izquierda (con vuelta)
		updateBlockEdges(bi + 1 - (if bi % bw == 0 then bw else 0)) -- derecha (con vuelta)
		updateBlockEdges(bi - bw)
		updateBlockEdges(bi + bw)
	end"""

new_recolor = """	-- Las fronteras ahora se dibujan pixel a pixel directamente desde applyDiff
	if ownerChanged and state.animReady then
		-- sin contorno de bloque
	end"""

assert old_recolor in text, "old_recolor not found"
text = text.replace(old_recolor, new_recolor, 1)

with open("src/client/WorldClient.client.lua", "w", encoding="utf-8") as f:
    f.write(text)

print("Pixel borders successfully applied to WorldClient.client.lua!")
