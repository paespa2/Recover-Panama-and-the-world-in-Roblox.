# tools/apply_full_frontwars_optimization.py
import re

with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
    code = f.read()

# 1. PixelEdgeLayer with Viewport Culling
old_edge_section_pattern = re.compile(
    r"-- ============================================================================\n"
    r"-- FRONTERAS DE PÍXELES FINOS.*?-- El contorno del jugador late con resplandor dorado\n"
    r"local edgePulseAcc = 0\n"
    r"RunService\.Heartbeat:Connect\(function\(dt\).*?end\)\n",
    re.DOTALL
)

new_edge_section = """-- ============================================================================
-- FRONTERAS DE PÍXELES FINOS OPTIMIZADAS (VIEWPORT CULLING ESTILO FRONTWARS)
-- ============================================================================
local edgeLayer = Instance.new("Frame")
edgeLayer.Name = "PixelEdgeLayer"
edgeLayer.Size = UDim2.fromScale(1, 1)
edgeLayer.BackgroundTransparency = 1
edgeLayer.BorderSizePixel = 0
edgeLayer.Visible = true
edgeLayer.ZIndex = 6
edgeLayer.Parent = mapCanvas

local MAX_VISIBLE_EDGES = 350
local edgeFrames = {}
local myEdges = {}
local LINE_THICK_PX = 1.5

-- Pre-instanciamos el pool fijo de frames (máximo 350 para 60 FPS garantizados)
for i = 1, MAX_VISIBLE_EDGES do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.ZIndex = 6
	f.Visible = false
	f.Parent = edgeLayer
	edgeFrames[i] = f
end

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

-- Actualiza los bordes visibles SOLO dentro de la pantalla del jugador (Viewport Culling)
local function refreshVisibleEdges()
	local owner = state.owner
	local w, h = state.w, state.h
	if not owner or not w or w == 0 or not state.initialized then
		edgeLayer.Visible = false
		return
	end

	local rel = state.zoom / (state.fit or state.zoom)
	-- Con zoom alejado (mapa entero) las líneas de 1px causan lag y aliasing; los bloques bastan
	if rel < 1.25 then
		edgeLayer.Visible = false
		table.clear(myEdges)
		return
	end
	edgeLayer.Visible = true

	local vs = mapContainer.AbsoluteSize
	local cellW = BASE_WIDTH * state.zoom / w
	local cellH = BASE_HEIGHT * state.zoom / h
	if cellW <= 0 or cellH <= 0 then
		return
	end

	local left = vs.X / 2 + state.pan.X - BASE_WIDTH * state.zoom / 2
	local top = vs.Y / 2 + state.pan.Y - BASE_HEIGHT * state.zoom / 2
	local x0 = math.clamp(math.floor(-left / cellW) - 1, 0, w - 1)
	local x1 = math.clamp(math.ceil((vs.X - left) / cellW) + 1, 0, w - 1)
	local y0 = math.clamp(math.floor(-top / cellH) - 1, 0, h - 1)
	local y1 = math.clamp(math.ceil((vs.Y - top) / cellH) + 1, 0, h - 1)

	table.clear(myEdges)
	local edgeCount = 0

	for y = y0, y1 do
		local row = y * w
		for x = x0, x1 do
			local cell = row + x
			local o = buffer.readu8(owner, cell)
			if o ~= 0 then
				local r = buffer.readu8(owner, row + (if x == w - 1 then 0 else x + 1))
				local d = if y < h - 1 then buffer.readu8(owner, (y + 1) * w + x) else 0

				-- Borde derecho
				if r ~= o and not sameTeam(r, o) then
					edgeCount += 1
					if edgeCount <= MAX_VISIBLE_EDGES then
						local f = edgeFrames[edgeCount]
						f.AnchorPoint = Vector2.new(0.5, 0)
						f.Position = UDim2.fromScale((x + 1) / w, y / h)
						f.Size = UDim2.new(0, LINE_THICK_PX, 1 / h, 0)
						f.BackgroundColor3 = edgeColor(o)
						f.BackgroundTransparency = 0.05
						f.Visible = true
						if o == state.myId then
							myEdges[f] = true
						end
					end
				end

				-- Borde inferior
				if d ~= o and not sameTeam(d, o) then
					edgeCount += 1
					if edgeCount <= MAX_VISIBLE_EDGES then
						local f = edgeFrames[edgeCount]
						f.AnchorPoint = Vector2.new(0, 0.5)
						f.Position = UDim2.fromScale(x / w, (y + 1) / h)
						f.Size = UDim2.new(1 / w, 0, 0, LINE_THICK_PX)
						f.BackgroundColor3 = edgeColor(o)
						f.BackgroundTransparency = 0.05
						f.Visible = true
						if o == state.myId then
							myEdges[f] = true
						end
					end
				end

				if edgeCount >= MAX_VISIBLE_EDGES then
					break
				end
			end
		end
		if edgeCount >= MAX_VISIBLE_EDGES then
			break
		end
	end

	-- Ocultar frames sobrantes del pool
	for i = edgeCount + 1, MAX_VISIBLE_EDGES do
		edgeFrames[i].Visible = false
	end
end

state.refreshEdges = refreshVisibleEdges
state.rebuildEdges = refreshVisibleEdges

local function updateCellEdges(cell)
	-- Viewport Culling gestionado eficientemente en refreshVisibleEdges
end

-- El contorno del jugador late con resplandor dorado (solo en frames activos)
local edgePulseAcc = 0
RunService.Heartbeat:Connect(function(dt)
	edgePulseAcc += dt
	if edgePulseAcc < 0.15 then
		return
	end
	edgePulseAcc = 0
	if not edgeLayer.Visible then
		return
	end
	local k = (math.sin(os.clock() * 4) + 1) / 2
	local c = Color3.fromRGB(255, 215, 40):Lerp(Color3.fromRGB(255, 255, 240), k)
	for f in pairs(myEdges) do
		f.BackgroundColor3 = c
	end
end)
"""

match = old_edge_section_pattern.search(code)
if match:
    code = code[:match.start()] + new_edge_section + code[match.end():]
    print("Replaced PixelEdgeLayer section successfully")
else:
    print("WARNING: PixelEdgeLayer pattern not matched!")

# 2. Add refreshEdges to updateMapTransform
old_upd_transform = """	state.detailDirty = true
	applyLabelZoom()
	if state.updateRadar then
		state.updateRadar()
	end
end"""

new_upd_transform = """	state.detailDirty = true
	applyLabelZoom()
	if state.updateRadar then
		state.updateRadar()
	end
	if state.refreshEdges then
		state.refreshEdges()
	end
end"""

if old_upd_transform in code:
    code = code.replace(old_upd_transform, new_upd_transform)
    print("Added refreshEdges to updateMapTransform")
else:
    print("WARNING: updateMapTransform pattern not found")

# 3. Viewport culling in marker labels
old_marker_insert = """			table.insert(markerPool, marker)
			table.insert(markerLabels, {
				id = n.id,
				troops = troopsLbl,
				label = nameLbl,
				dot = dot,
				isMe = isMe,
				strong = isMe or isHuman,
				always = isMe or isHuman or bigIds[n.id] == true,
			})"""

new_marker_insert = """			table.insert(markerPool, marker)
			table.insert(markerLabels, {
				id = n.id,
				troops = troopsLbl,
				label = nameLbl,
				dot = dot,
				marker = marker,
				capX = capX,
				capY = capY,
				isMe = isMe,
				strong = isMe or isHuman,
				always = isMe or isHuman or bigIds[n.id] == true,
			})"""

if old_marker_insert in code:
    code = code.replace(old_marker_insert, new_marker_insert)
    print("Updated markerLabels insertion with cap coordinates and marker reference")
else:
    print("WARNING: marker insert pattern not found")

# 4. Viewport culling inside applyLabelZoom
old_apply_label_zoom = """local function applyLabelZoom()
	local rel = state.zoom / (state.fit or state.zoom)
	for _, m in ipairs(markerLabels) do
		local ds = math.clamp(math.floor((if m.isMe then 12 else 7) * (0.75 + 0.3 * rel)), 5, 24)
		m.dot.Size = UDim2.fromOffset(ds, ds)
		local show = m.always or rel >= 1.8
		m.label.Visible = show
		if m.troops then
			m.troops.Visible = show and m.troops.Text ~= ""
		end
		if show then
			local size = math.clamp(math.floor(7 + 3 * rel), 8, 17) + (if m.strong then 2 else 0)
			local width = math.max(100, size * 14)
			m.label.TextSize = size
			m.label.Size = UDim2.fromOffset(width, size + 6)
			m.label.Position = UDim2.fromOffset(12 - width / 2, 10 + ds / 2)
			if m.troops then
				m.troops.TextSize = math.max(8, size - 1)
				m.troops.Size = UDim2.fromOffset(width, size + 4)
				m.troops.Position = UDim2.fromOffset(12 - width / 2, 10 + ds / 2 + size + 4)
			end
		end
	end
end"""

new_apply_label_zoom = """local function applyLabelZoom()
	local rel = state.zoom / (state.fit or state.zoom)
	local w, h = state.w or 960, state.h or 400
	local vs = mapContainer.AbsoluteSize
	local cellW = BASE_WIDTH * state.zoom / w
	local cellH = BASE_HEIGHT * state.zoom / h
	local left = vs.X / 2 + state.pan.X - BASE_WIDTH * state.zoom / 2
	local top = vs.Y / 2 + state.pan.Y - BASE_HEIGHT * state.zoom / 2
	local x0 = math.clamp(math.floor(-left / cellW) - 8, 0, w)
	local x1 = math.clamp(math.ceil((vs.X - left) / cellW) + 8, 0, w)
	local y0 = math.clamp(math.floor(-top / cellH) - 8, 0, h)
	local y1 = math.clamp(math.ceil((vs.Y - top) / cellH) + 8, 0, h)

	for _, m in ipairs(markerLabels) do
		local inView = true
		if m.capX and m.capY then
			inView = (m.capX >= x0 and m.capX <= x1 and m.capY >= y0 and m.capY <= y1)
		end
		if not inView then
			if m.marker then m.marker.Visible = false end
		else
			if m.marker then m.marker.Visible = true end
			local ds = math.clamp(math.floor((if m.isMe then 12 else 7) * (0.75 + 0.3 * rel)), 5, 24)
			m.dot.Size = UDim2.fromOffset(ds, ds)
			local show = m.always or rel >= 1.8
			m.label.Visible = show
			if m.troops then
				m.troops.Visible = show and m.troops.Text ~= ""
			end
			if show then
				local size = math.clamp(math.floor(7 + 3 * rel), 8, 17) + (if m.strong then 2 else 0)
				local width = math.max(100, size * 14)
				m.label.TextSize = size
				m.label.Size = UDim2.fromOffset(width, size + 6)
				m.label.Position = UDim2.fromOffset(12 - width / 2, 10 + ds / 2)
				if m.troops then
					m.troops.TextSize = math.max(8, size - 1)
					m.troops.Size = UDim2.fromOffset(width, size + 4)
					m.troops.Position = UDim2.fromOffset(12 - width / 2, 10 + ds / 2 + size + 4)
				end
			end
		end
	end
end"""

if old_apply_label_zoom in code:
    code = code.replace(old_apply_label_zoom, new_apply_label_zoom)
    print("Updated applyLabelZoom with Viewport Culling")
else:
    print("WARNING: applyLabelZoom pattern not matched")

# 5. TopBar & BottomHUD FrontWars styling
code = code.replace(
    'topBar.Size = UDim2.new(1, 0, 0, 54)',
    'topBar.Size = UDim2.new(1, 0, 0, 44)'
)
code = code.replace(
    'titleLabel.Text = "🌍 RECUPERAR PANAMÁ Y EL MUNDO"',
    'titleLabel.Text = "⚔️ FRONTWARS | RECUPERAR PANAMÁ"'
)
code = code.replace(
    'phaseBadge.Size = UDim2.fromOffset(360, 36)',
    'phaseBadge.Size = UDim2.fromOffset(360, 30)'
)
code = code.replace(
    'phaseCorner.CornerRadius = UDim.new(0, 8)',
    'phaseCorner.CornerRadius = UDim.new(0, 4)'
)
code = code.replace(
    'phaseStroke.Thickness = 1.5',
    'phaseStroke.Thickness = 1'
)
code = code.replace(
    'btnLobbyCorner.CornerRadius = UDim.new(0, 6)',
    'btnLobbyCorner.CornerRadius = UDim.new(0, 4)'
)
code = code.replace(
    'btnCenterCorner.CornerRadius = UDim.new(0, 6)',
    'btnCenterCorner.CornerRadius = UDim.new(0, 4)'
)

# BottomHUD
code = code.replace(
    'bottomHUD.Size = UDim2.fromOffset(1000, 104)',
    'bottomHUD.Size = UDim2.fromOffset(980, 92)'
)
code = code.replace(
    'bottomCorner.CornerRadius = UDim.new(0, 10)',
    'bottomCorner.CornerRadius = UDim.new(0, 6)'
)
code = code.replace(
    'bottomStroke.Thickness = 1.5',
    'bottomStroke.Thickness = 1'
)
code = code.replace(
    'troopsCorner.CornerRadius = UDim.new(0, 6)',
    'troopsCorner.CornerRadius = UDim.new(0, 4)'
)
code = code.replace(
    'goldCorner.CornerRadius = UDim.new(0, 6)',
    'goldCorner.CornerRadius = UDim.new(0, 4)'
)

with open("src/client/WorldClient.client.lua", "w", encoding="utf-8") as f:
    f.write(code)

print("Full FrontWars optimization applied successfully.")
