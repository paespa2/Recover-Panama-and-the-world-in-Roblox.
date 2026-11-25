# tools/apply_frontwars_colors_and_spawn.py
import re

# ============================================================================
# 1. UPDATE SERVER: WorldEngine.lua
# ============================================================================
with open("src/server/WorldEngine.lua", "r", encoding="utf-8") as f:
    engine_code = f.read()

# Replace botColor with FrontWars vibrant palette
old_bot_color = """local function botColor(i)
	local hue = (i * 0.61803398875) % 1
	local sat = 0.38 + ((i * 7) % 5) * 0.035
	local val = 0.58 + ((i * 3) % 4) * 0.05
	return Color3.fromHSV(hue, sat, val)
end"""

new_bot_color = """local FRONTWARS_PALETTE = {
	Color3.fromRGB(74, 168, 255),  -- Sky Blue (estilo Mexico FW)
	Color3.fromRGB(112, 196, 144), -- Mint Green (verde FW clásico)
	Color3.fromRGB(245, 95, 85),   -- Coral Crimson
	Color3.fromRGB(250, 195, 55),  -- Amber Gold
	Color3.fromRGB(168, 115, 245), -- Pastel Violet
	Color3.fromRGB(255, 140, 55),  -- Tangerine Orange
	Color3.fromRGB(245, 110, 175), -- Candy Pink
	Color3.fromRGB(45, 205, 215),  -- Turquoise / Teal
	Color3.fromRGB(145, 215, 60),  -- Lime Green
	Color3.fromRGB(100, 145, 245), -- Cornflower Blue
	Color3.fromRGB(235, 165, 80),  -- Sandy Peach
	Color3.fromRGB(195, 125, 235), -- Lavender
	Color3.fromRGB(80, 195, 175),  -- Seafoam
	Color3.fromRGB(240, 80, 115),  -- Raspberry
	Color3.fromRGB(215, 195, 55),  -- Yellow Ochre
	Color3.fromRGB(120, 170, 235), -- Steel Blue
	Color3.fromRGB(255, 110, 80),  -- Bright Salmon
	Color3.fromRGB(60, 220, 160),  -- Spring Green
	Color3.fromRGB(190, 95, 245),  -- Deep Orchid
	Color3.fromRGB(255, 175, 45),  -- Bright Marigold
}

local function botColor(i)
	if i <= #FRONTWARS_PALETTE then
		return FRONTWARS_PALETTE[i]
	end
	local hue = (i * 0.61803398875) % 1
	local sat = 0.62 + ((i * 7) % 5) * 0.04
	local val = 0.88 + ((i * 3) % 4) * 0.03
	return Color3.fromHSV(hue, math.clamp(sat, 0.55, 0.85), math.clamp(val, 0.82, 0.98))
end"""

if old_bot_color in engine_code:
    engine_code = engine_code.replace(old_bot_color, new_bot_color)
    print("Updated botColor in WorldEngine")
else:
    print("WARNING: old_bot_color not found in WorldEngine")

# Update countries mode colors to vibrant
old_country_color = "local color = Color3.fromHSV(hue % 1, 0.42 + ((cid * 7) % 5) * 0.04, 0.6 + ((cid * 3) % 4) * 0.05)"
new_country_color = "local color = Color3.fromHSV(hue % 1, 0.62 + ((cid * 7) % 5) * 0.04, 0.88 + ((cid * 3) % 4) * 0.03)"
if old_country_color in engine_code:
    engine_code = engine_code.replace(old_country_color, new_country_color)
    print("Updated country colors in WorldEngine")
else:
    print("WARNING: old_country_color not found")

# Update spawnNation starting territory radius
old_spawn_circle = "if dx * dx + dy * dy <= 26 then"
new_spawn_circle = "if dx * dx + dy * dy <= 38 then"
if old_spawn_circle in engine_code:
    engine_code = engine_code.replace(old_spawn_circle, new_spawn_circle)
    engine_code = engine_code.replace("for dy = -5, 5 do", "for dy = -6, 6 do")
    engine_code = engine_code.replace("for dx = -5, 5 do", "for dx = -6, 6 do")
    engine_code = engine_code.replace('self:fx("CAPITAL_SPAWN", cell, 8)', 'self:fx("CAPITAL_SPAWN", cell, 12)')
    print("Expanded starting territory spawn radius in WorldEngine")

with open("src/server/WorldEngine.lua", "w", encoding="utf-8") as f:
    f.write(engine_code)


# ============================================================================
# 2. UPDATE CLIENT: WorldClient.client.lua
# ============================================================================
with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
    client_code = f.read()

# Update Palettes to FrontWars colors
old_palette = """local OCEAN_COLOR = Color3.fromRGB(15, 32, 58)
local DEEP_OCEAN_COLOR = Color3.fromRGB(10, 22, 42)
local UNCLAIMED_LAND = Color3.fromRGB(72, 85, 78)
local UNCLAIMED_BORDER = Color3.fromRGB(52, 65, 58)"""

new_palette = """local OCEAN_COLOR = Color3.fromRGB(18, 34, 56) -- FrontWars Deep Navy
local DEEP_OCEAN_COLOR = Color3.fromRGB(12, 24, 40)
local UNCLAIMED_LAND = Color3.fromRGB(158, 178, 142) -- FrontWars Flat Pastel Sage
local UNCLAIMED_BORDER = Color3.fromRGB(130, 150, 115)"""

if old_palette in client_code:
    client_code = client_code.replace(old_palette, new_palette)
    print("Updated palette to FrontWars colors in WorldClient")
else:
    print("WARNING: old_palette not matched exactly")

# Disable satellite Earth tiles completely (no satellite shading!)
old_use_tiles = """	state.useTiles = state.planet == "EARTH"
	setTilesVisible(state.useTiles)"""

new_use_tiles = """	state.useTiles = false
	setTilesVisible(false)"""

if old_use_tiles in client_code:
    client_code = client_code.replace(old_use_tiles, new_use_tiles)
    print("Disabled satellite tiles in WorldClient")
else:
    print("WARNING: old_use_tiles not found")

# Replace recolorBlock with SOLID, OPAQUE, VIBRANT FrontWars rendering (NO satellite shading/blending)
old_recolor = """local function recolorBlock(bi)
	local b = state.blocks[bi]
	if not b then
		return
	end
	local bx = (bi - 1) % state.blockW
	local by = (bi - 1) // state.blockW
	local w = state.w
	local owner = state.owner
	local counts = {}
	local bestId, bestCount = 0, 0
	local x0, y0 = bx * BLOCK, by * BLOCK
	for y = y0, y0 + BLOCK - 1 do
		local row = y * w
		for x = x0, x0 + BLOCK - 1 do
			local o = buffer.readu8(owner, row + x)
			if o ~= 0 then
				local c = (counts[o] or 0) + 1
				counts[o] = c
				if c > bestCount then
					bestCount = c
					bestId = o
				end
			end
		end
	end

	local r, g, bl = b.r, b.g, b.b
	local n = if bestId ~= 0 then state.rosterById[bestId] else nil
	-- Con las teselas de fondo, el bloque solo se tiñe (semitransparente) donde un país domina la celda
	if state.useTiles and n and bestCount < 8 then
		n = nil
	end
	local transparency = 0
	if n then
		local isMe = bestId == state.myId
		if state.useTiles then
			r, g, bl = n.r or 200, n.g or 200, n.b or 200
			-- Tú y los jugadores humanos se ven con más fuerza que los bots
			transparency = if isMe then 0.5 elseif n.bot == false then 0.55 else 0.68 -- fills suaves: el relieve se transparenta
		else
			local alpha = math.min(if isMe then 0.8 else 0.64, bestCount / (BLOCK * BLOCK) * 1.6)
			r = r * (1 - alpha) + (n.r or 200) * alpha
			g = g * (1 - alpha) + (n.g or 200) * alpha
			bl = bl * (1 - alpha) + (n.b or 200) * alpha
		end
		if isMe then
			r, g, bl = r * 1.12, g * 1.12, bl * 1.12
		end
	elseif state.useTiles then
		transparency = 1
	end
	local finalColor = Color3.fromRGB(
		math.clamp(math.floor(r), 0, 255),
		math.clamp(math.floor(g), 0, 255),
		math.clamp(math.floor(bl), 0, 255)
	)
	local ownerNow = if n then bestId else 0
	b.frame.BackgroundColor3 = finalColor
	b.frame.BackgroundTransparency = transparency
	local ownerChanged = b.owner ~= ownerNow
	b.owner = ownerNow
	-- Cambió el dueño del bloque: se redibujan sus contornos y los de sus 4 vecinos (comparten lado)
	-- Las fronteras ahora se dibujan pixel a pixel directamente desde applyDiff
	if ownerChanged and state.animReady then
		-- sin contorno de bloque
	end
end"""

new_recolor = """local function recolorBlock(bi)
	local b = state.blocks[bi]
	if not b then
		return
	end
	local bx = (bi - 1) % state.blockW
	local by = (bi - 1) // state.blockW
	local w = state.w
	local owner = state.owner
	local counts = {}
	local bestId, bestCount = 0, 0
	local x0, y0 = bx * BLOCK, by * BLOCK
	for y = y0, y0 + BLOCK - 1 do
		local row = y * w
		for x = x0, x0 + BLOCK - 1 do
			local o = buffer.readu8(owner, row + x)
			if o ~= 0 then
				local c = (counts[o] or 0) + 1
				counts[o] = c
				if c > bestCount then
					bestCount = c
					bestId = o
				end
			end
		end
	end

	local n = if bestId ~= 0 then state.rosterById[bestId] else nil
	local finalColor
	if n then
		-- Colores 100% sólidos, planos y vibrantes estilo FrontWars (sin sombreados de satélite)
		finalColor = if bestId == state.myId then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.22) else n.color
	else
		finalColor = if b.isLand then UNCLAIMED_LAND else OCEAN_COLOR
	end

	b.frame.BackgroundColor3 = finalColor
	b.frame.BackgroundTransparency = 0 -- Totalmente opaco y plano
	b.owner = if n then bestId else 0
end"""

if old_recolor in client_code:
    client_code = client_code.replace(old_recolor, new_recolor)
    print("Replaced recolorBlock with solid FrontWars colors")
else:
    print("WARNING: old_recolor not found in WorldClient")

# Update fullRedraw to precompute isLand and use solid FrontWars colors
old_full_redraw = """function fullRedraw()
	if state.blockMode then
		if not state.blocks or not state.owner or not state.baseBuffer then
			return
		end
		state.animReady = false -- el primer dibujado no debe animarse
		-- Color base de cada bloque = media de la foto satelital (incluye mar y costas)
		local w, base = state.w, state.baseBuffer
		local area = BLOCK * BLOCK
		for bi = 1, state.blockW * state.blockH do
			local bx = (bi - 1) % state.blockW
			local by = (bi - 1) // state.blockW
			local sr, sg, sb = 0, 0, 0
			for y = by * BLOCK, by * BLOCK + BLOCK - 1 do
				for x = bx * BLOCK, bx * BLOCK + BLOCK - 1 do
					local o = (y * w + x) * 3
					sr += buffer.readu8(base, o)
					sg += buffer.readu8(base, o + 1)
					sb += buffer.readu8(base, o + 2)
				end
			end
			local b = state.blocks[bi]
			b.r, b.g, b.b = sr / area, sg / area, sb / area
			state.dirtyBlocks[bi] = true
		end
		flushImage()
		-- Contornos de color de todos los territorios (los cambios que lleguen mientras tanto solo anotan dueños)
		state.blockBuilding = true
		rebuildEdges()
		state.blockBuilding = false
		state.animReady = true -- a partir de aquí, las conquistas se animan
		return
	end"""

new_full_redraw = """function fullRedraw()
	if state.blockMode then
		if not state.blocks or not state.owner then
			return
		end
		state.animReady = false
		local w, land, owner = state.w, state.land, state.owner
		local area = BLOCK * BLOCK
		for bi = 1, state.blockW * state.blockH do
			local bx = (bi - 1) % state.blockW
			local by = (bi - 1) // state.blockW
			local b = state.blocks[bi]
			if b then
				local landCount = 0
				local counts = {}
				local bestId, bestCount = 0, 0
				for y = by * BLOCK, by * BLOCK + BLOCK - 1 do
					local row = y * w
					for x = bx * BLOCK, bx * BLOCK + BLOCK - 1 do
						local cell = row + x
						if land and buffer.readu8(land, cell) == 1 then
							landCount += 1
						end
						local o = buffer.readu8(owner, cell)
						if o ~= 0 then
							local c = (counts[o] or 0) + 1
							counts[o] = c
							if c > bestCount then
								bestCount = c
								bestId = o
							end
						end
					end
				end
				b.isLand = (landCount >= (area / 3))
				local n = if bestId ~= 0 then state.rosterById[bestId] else nil
				local col
				if n then
					col = if bestId == state.myId then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.22) else n.color
				else
					col = if b.isLand then UNCLAIMED_LAND else OCEAN_COLOR
				end
				b.frame.BackgroundColor3 = col
				b.frame.BackgroundTransparency = 0
				b.owner = if n then bestId else 0
			end
		end
		state.animReady = true
		if state.refreshEdges then
			state.refreshEdges()
		end
		return
	end"""

if old_full_redraw in client_code:
    client_code = client_code.replace(old_full_redraw, new_full_redraw)
    print("Replaced fullRedraw with FrontWars flat terrain precomputation")
else:
    print("WARNING: old_full_redraw not found")

# Redesign Base / Capital marker in updateMarkers:
# FrontWars style: round fortress disc + floating pill badge with flag and troop count
old_marker_design = """			-- Punto de la capital
			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(0.5, 0.5)
			dot.Size = isMe and UDim2.fromOffset(14, 14) or UDim2.fromOffset(8, 8)
			dot.BackgroundColor3 = isMe and Color3.fromRGB(255, 240, 50) or n.color
			dot.BorderSizePixel = 1
			dot.BorderColor3 = isMe and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(10, 10, 15)
			dot.Parent = marker

			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot

			-- Etiqueta con el nombre
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "Name"
			nameLbl.Size = UDim2.fromOffset(100, 16)
			nameLbl.Position = UDim2.fromOffset(-38, isMe and 14 or 8)
			nameLbl.BackgroundTransparency = 1
			local isHuman = n.bot == false
			nameLbl.Font = if isMe or isHuman then Enum.Font.GothamBlack else Enum.Font.GothamBold
			nameLbl.Text = (if isMe then "👑 " elseif isHuman then "👤 " else "") .. n.name
			-- El rótulo toma el color del país (aclarado) y lleva contorno oscuro para leerse sobre cualquier fondo
			nameLbl.TextColor3 = if isMe
				then Color3.fromRGB(255, 230, 50)
				else n.color:Lerp(Color3.new(1, 1, 1), if isHuman then 0.25 else 0.55)
			nameLbl.TextStrokeTransparency = 0.35
			nameLbl.TextStrokeColor3 = Color3.fromRGB(8, 10, 16)
			nameLbl.TextSize = if isMe or isHuman then 12 else 9
			nameLbl.ZIndex = 11
			nameLbl.Parent = marker

			-- Tropas debajo del nombre, como en RoWorld ("Guyana 21.1K")
			local troopsLbl = Instance.new("TextLabel")
			troopsLbl.Name = "Troops"
			troopsLbl.Size = UDim2.fromOffset(100, 14)
			troopsLbl.BackgroundTransparency = 1
			troopsLbl.Font = Enum.Font.GothamBlack
			troopsLbl.Text = ""
			troopsLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			troopsLbl.TextStrokeTransparency = 0.25
			troopsLbl.TextStrokeColor3 = Color3.fromRGB(8, 10, 16)
			troopsLbl.TextSize = 9
			troopsLbl.ZIndex = 11
			troopsLbl.Parent = marker"""

new_marker_design = """			local isHuman = n.bot == false

			-- Disco Base / Fortaleza circular estilo FrontWars
			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(0.5, 0.5)
			dot.Size = isMe and UDim2.fromOffset(22, 22) or UDim2.fromOffset(16, 16)
			dot.BackgroundColor3 = isMe and Color3.fromRGB(255, 225, 50) or n.color
			dot.BorderSizePixel = 0
			dot.ZIndex = 12
			dot.Parent = marker

			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot

			local dotStroke = Instance.new("UIStroke")
			dotStroke.Thickness = 2.5
			dotStroke.Color = Color3.fromRGB(15, 22, 34)
			dotStroke.Parent = dot

			local centerIcon = Instance.new("TextLabel")
			centerIcon.Name = "CenterIcon"
			centerIcon.Size = UDim2.fromScale(1, 1)
			centerIcon.BackgroundTransparency = 1
			centerIcon.Font = Enum.Font.GothamBlack
			centerIcon.Text = if isMe then "👑" elseif isHuman then "👤" else "⭐"
			centerIcon.TextSize = isMe and 12 or 9
			centerIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
			centerIcon.ZIndex = 13
			centerIcon.Parent = dot

			-- Badge flotante superior estilo FrontWars: [ 🇲🇽 Mexico 766 ]
			local badge = Instance.new("Frame")
			badge.Name = "FloatingBadge"
			badge.AnchorPoint = Vector2.new(0.5, 1)
			badge.Position = UDim2.fromOffset(0, isMe and -16 or -12)
			badge.Size = UDim2.fromOffset(110, 20)
			badge.BackgroundColor3 = Color3.fromRGB(12, 18, 28)
			badge.BackgroundTransparency = 0.15
			badge.BorderSizePixel = 0
			badge.ZIndex = 14
			badge.Parent = marker

			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0, 4)
			badgeCorner.Parent = badge

			local badgeStroke = Instance.new("UIStroke")
			badgeStroke.Thickness = 1
			badgeStroke.Color = if isMe then Color3.fromRGB(255, 215, 0) else Color3.fromRGB(45, 60, 90)
			badgeStroke.Parent = badge

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "Name"
			nameLbl.Size = UDim2.new(1, -6, 1, 0)
			nameLbl.Position = UDim2.fromOffset(3, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.Text = (if isMe then "👑 " elseif isHuman then "👤 " else "") .. n.name
			nameLbl.TextColor3 = if isMe then Color3.fromRGB(255, 230, 60) else Color3.fromRGB(240, 245, 255)
			nameLbl.TextSize = 10
			nameLbl.TextXAlignment = Enum.TextXAlignment.Center
			nameLbl.ZIndex = 15
			nameLbl.Parent = badge

			local troopsLbl = Instance.new("TextLabel")
			troopsLbl.Name = "Troops"
			troopsLbl.Size = UDim2.fromOffset(80, 14)
			troopsLbl.Position = UDim2.fromOffset(0, 22)
			troopsLbl.AnchorPoint = Vector2.new(0.5, 0)
			troopsLbl.BackgroundTransparency = 1
			troopsLbl.Font = Enum.Font.GothamBlack
			troopsLbl.Text = ""
			troopsLbl.TextColor3 = Color3.fromRGB(0, 235, 140)
			troopsLbl.TextStrokeTransparency = 0.3
			troopsLbl.TextStrokeColor3 = Color3.fromRGB(10, 15, 25)
			troopsLbl.TextSize = 9
			troopsLbl.ZIndex = 14
			troopsLbl.Parent = marker"""

if old_marker_design in client_code:
    client_code = client_code.replace(old_marker_design, new_marker_design)
    print("Replaced marker design with FrontWars base disc and floating badge")
else:
    print("WARNING: old_marker_design not found in WorldClient")

with open("src/client/WorldClient.client.lua", "w", encoding="utf-8") as f:
    f.write(client_code)

print("Applied FrontWars colors and spawn updates successfully.")
