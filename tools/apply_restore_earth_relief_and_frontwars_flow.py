# tools/apply_restore_earth_relief_and_frontwars_flow.py
import re

# ============================================================================
# 1. UPDATE SERVER: WorldServer.server.lua
# ============================================================================
with open("src/server/WorldServer.server.lua", "r", encoding="utf-8") as f:
    server_code = f.read()

# Add START_NOW handling
old_action_spawn = 'if action == "SPAWN" and validCell then'
new_action_spawn = """if action == "START_NOW" then
		if engine and engine.phase == "SPAWN" then
			engine.spawnTimer = 0
		end
		return
	elseif action == "SPAWN" and validCell then"""

if old_action_spawn in server_code:
    server_code = server_code.replace(old_action_spawn, new_action_spawn)
    print("Added START_NOW to WorldServer.server.lua")
else:
    print("WARNING: old_action_spawn not matched in WorldServer")

with open("src/server/WorldServer.server.lua", "w", encoding="utf-8") as f:
    f.write(server_code)


# ============================================================================
# 2. UPDATE CLIENT: WorldClient.client.lua
# ============================================================================
with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
    client_code = f.read()

# Restore Earth relief map tiles, but permanently remove BORDER_TILES (no grey border shading over map mundi)
old_set_tiles = """local function setTilesVisible(visible)
	if visible and not tileLayer then
		-- Capas globales del mapa: teselas 1 < bloques 2 < detalle 3 < resalte 4 < fronteras 5 < anillos 8-9 < marcadores 10+
		tileLayer = makeTileLayer("TileLayer", EARTH_TILES, 1)
		borderLayer = makeTileLayer("BorderLayer", BORDER_TILES, 5)
	end
	if tileLayer then
		tileLayer.Visible = visible
	end
	if borderLayer then
		borderLayer.Visible = visible
	end
end"""

new_set_tiles = """local function setTilesVisible(visible)
	if visible and not tileLayer then
		-- Mapa de relieve natural de la Tierra (sin fronteras grises superpuestas sobre el mapa mundi)
		tileLayer = makeTileLayer("TileLayer", EARTH_TILES, 1)
	end
	if tileLayer then
		tileLayer.Visible = visible
	end
end"""

if old_set_tiles in client_code:
    client_code = client_code.replace(old_set_tiles, new_set_tiles)
    print("Updated setTilesVisible (removed BORDER_TILES overlay)")
else:
    print("WARNING: old_set_tiles not matched")

# Set state.useTiles to true on EARTH
old_init_blocks_tiles = """	state.useTiles = false
	setTilesVisible(false)"""

new_init_blocks_tiles = """	state.useTiles = (state.planet == "EARTH")
	setTilesVisible(state.useTiles)"""

if old_init_blocks_tiles in client_code:
    client_code = client_code.replace(old_init_blocks_tiles, new_init_blocks_tiles)
    print("Restored state.useTiles on Earth")
else:
    print("WARNING: old_init_blocks_tiles not matched")

# Update recolorBlock so neutral continents have 0 tint (100% transparent relief), and conquered land has vibrant FrontWars color
old_recolor_func = """local function recolorBlock(bi)
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

new_recolor_func = """local function recolorBlock(bi)
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
	local transparency = 0

	if state.useTiles then
		if n then
			local isMe = bestId == state.myId
			finalColor = if isMe then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.25) else n.color
			-- Territorio conquistado: color vivo de la nación sobre el mapa de relieve
			transparency = if isMe then 0.20 elseif n.bot == false then 0.26 else 0.34
		else
			-- Continentes y tierra natural neutral: 100% transparente para que el relieve se vea limpio sin veladuras ni sombreados
			finalColor = OCEAN_COLOR
			transparency = 1
		end
	else
		if n then
			finalColor = if bestId == state.myId then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.25) else n.color
		else
			finalColor = if b.isLand then UNCLAIMED_LAND else OCEAN_COLOR
		end
		transparency = 0
	end

	b.frame.BackgroundColor3 = finalColor
	b.frame.BackgroundTransparency = transparency
	b.owner = if n then bestId else 0
end"""

if old_recolor_func in client_code:
    client_code = client_code.replace(old_recolor_func, new_recolor_func)
    print("Updated recolorBlock (clean relief map with vivid claimed territory)")
else:
    print("WARNING: old_recolor_func not matched")

# Update fullRedraw similarly
old_full_redraw_func = """function fullRedraw()
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

new_full_redraw_func = """function fullRedraw()
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
				local col = OCEAN_COLOR
				local transp = 0

				if state.useTiles then
					if n then
						local isMe = bestId == state.myId
						col = if isMe then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.25) else n.color
						transp = if isMe then 0.20 elseif n.bot == false then 0.26 else 0.34
					else
						col = OCEAN_COLOR
						transp = 1
					end
				else
					if n then
						col = if bestId == state.myId then n.color:Lerp(Color3.fromRGB(255, 235, 70), 0.25) else n.color
					else
						col = if b.isLand then UNCLAIMED_LAND else OCEAN_COLOR
					end
					transp = 0
				end

				b.frame.BackgroundColor3 = col
				b.frame.BackgroundTransparency = transp
				b.owner = if n then bestId else 0
			end
		end
		state.animReady = true
		if state.refreshEdges then
			state.refreshEdges()
		end
		return
	end"""

if old_full_redraw_func in client_code:
    client_code = client_code.replace(old_full_redraw_func, new_full_redraw_func)
    print("Updated fullRedraw (relief tiles preserved with transparent neutral land)")
else:
    print("WARNING: old_full_redraw_func not matched")

# Add "▶ ¡LISTO!" (Start Now) button to spawnBanner
old_spawn_banner = """	bannerBar.Size = UDim2.fromScale(math.clamp(left / math.max(1, s.spawnTotal or 25), 0, 1), 1)
	bannerBar.BackgroundColor3 = if left <= 5 then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(0, 220, 255)
	spawnBannerStroke.Color = bannerBar.BackgroundColor3
end"""

new_spawn_banner = """	bannerBar.Size = UDim2.fromScale(math.clamp(left / math.max(1, s.spawnTotal or 25), 0, 1), 1)
	bannerBar.BackgroundColor3 = if left <= 5 then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(0, 220, 255)
	spawnBannerStroke.Color = bannerBar.BackgroundColor3
end

-- Botón estilo FrontWars para iniciar la partida de inmediato cuando estés listo
local btnStartNow = Instance.new("TextButton")
btnStartNow.Name = "BtnStartNow"
btnStartNow.Size = UDim2.fromOffset(130, 32)
btnStartNow.AnchorPoint = Vector2.new(1, 0.5)
btnStartNow.Position = UDim2.new(1, -16, 0.5, 0)
btnStartNow.BackgroundColor3 = Color3.fromRGB(0, 190, 110)
btnStartNow.BorderSizePixel = 0
btnStartNow.Font = Enum.Font.GothamBlack
btnStartNow.Text = "▶ ¡LISTO!"
btnStartNow.TextColor3 = Color3.fromRGB(255, 255, 255)
btnStartNow.TextSize = 13
btnStartNow.ZIndex = 45
btnStartNow.Parent = spawnBanner
roundCorners(btnStartNow, 6)

btnStartNow.MouseButton1Click:Connect(function()
	WorldCommand:FireServer({ a = "START_NOW" })
	btnStartNow.Visible = false
	showToast("⚔️ ¡Comenzando batalla ahora!", Color3.fromRGB(0, 230, 140))
end)"""

if old_spawn_banner in client_code:
    client_code = client_code.replace(old_spawn_banner, new_spawn_banner)
    print("Added BtnStartNow to spawnBanner")
else:
    print("WARNING: old_spawn_banner not matched")

with open("src/client/WorldClient.client.lua", "w", encoding="utf-8") as f:
    f.write(client_code)

print("Earth relief restoration & FrontWars flow updates complete.")
