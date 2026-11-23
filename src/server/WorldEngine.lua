--!nonstrict
-- WorldEngine.lua
-- Motor de conquista territorial por celdas (estilo RoWorld / OpenFront) sobre el globo terráqueo.
--  * Cada nación (jugadores humanos + bots con nombres de países y personajes históricos) posee celdas.
--  * Las tropas se gastan para conquistar celdas vecinas (neutrales o enemigas).
--  * El jugador construye (Ciudad, Puerto, Puesto defensivo, Silo) y decide la expansión.
--  * La IA de Defensa (opcional) contraataca a quien te ataca y fortalece tus fronteras.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldGrid = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldGrid"))

local Engine = {}
Engine.__index = Engine

local SPAWN_SECONDS = 25
local WIN_RATIO = 0.65
local START_TROOPS = 2000
local NUKE_COST = 900
local NUKE_RADIUS = 9
local POST_RADIUS = 12
local PORT_RANGE = 80

Engine.COSTS = { City = 500, Port = 400, Post = 350, Silo = 1200 }

local DIFFICULTY = {
	EASY = { think = 5.0, maxAttacks = 1, minRatio = 0.2, maxRatio = 0.35, growth = 0.8, edge = 1.4 },
	NORMAL = { think = 3.5, maxAttacks = 2, minRatio = 0.25, maxRatio = 0.5, growth = 1.0, edge = 1.0 },
	HARD = { think = 2.5, maxAttacks = 2, minRatio = 0.3, maxRatio = 0.6, growth = 1.2, edge = 0.8 },
	EXTREME = { think = 1.8, maxAttacks = 3, minRatio = 0.35, maxRatio = 0.7, growth = 1.5, edge = 0.6 },
}
Engine.DIFFICULTY = DIFFICULTY

local BOT_NAMES = {
	"Nikola Tesla",
	"Isaac Newton",
	"Donald Trump",
	"Pablo Escobar",
	"Napoleón",
	"Gengis Kan",
	"Cleopatra",
	"Simón Bolívar",
	"Einstein",
	"Darwin",
	"Alejandro Magno",
	"Julio César",
	"Carlomagno",
	"Atila",
	"Aníbal",
	"Saladino",
	"Shaka Zulú",
	"Moctezuma",
	"Pachacútec",
	"Isabel I",
	"Pedro el Grande",
	"Catalina la Grande",
	"Churchill",
	"Gandhi",
	"Mandela",
	"Lincoln",
	"Washington",
	"Bismarck",
	"Sun Tzu",
	"Qin Shi Huang",
	"Kublai Kan",
	"Tamerlán",
	"Ramsés II",
	"Leonidas",
	"Marco Polo",
	"Colón",
	"Magallanes",
	"Da Vinci",
	"Galileo",
	"Marie Curie",
	"Hammurabi",
	"Ciro el Grande",
	"Constantino",
	"Justiniano",
	"Juana de Arco",
	"San Martín",
	"O'Higgins",
	"Pancho Villa",
	"Zapata",
	"Torrijos",
	"Brasil",
	"Japón",
	"Egipto",
	"Rusia",
	"India",
	"China",
	"México",
	"Canadá",
	"Australia",
	"Sudáfrica",
	"Argentina",
	"Turquía",
	"Persia",
	"Colombia",
	"Costa Rica",
	"Francia",
	"Alemania",
	"Italia",
	"España",
	"Reino Unido",
	"Perú",
	"Chile",
	"Nigeria",
	"Etiopía",
	"Indonesia",
	"Corea",
	"Vietnam",
	"Tailandia",
	"Arabia",
	"Marruecos",
	"Kenia",
	"Venezuela",
	"Cuba",
	"Ucrania",
	"Polonia",
	"Suecia",
	"Noruega",
	"Grecia",
	"Mongolia",
	"Kazajistán",
	"Pakistán",
	"Irán",
}

-- Los jugadores humanos usan colores NEÓN muy saturados; los bots usan tonos apagados.
local HUMAN_COLORS = {
	Color3.fromRGB(255, 40, 70),
	Color3.fromRGB(255, 205, 0),
	Color3.fromRGB(0, 255, 130),
	Color3.fromRGB(0, 210, 255),
	Color3.fromRGB(255, 0, 210),
	Color3.fromRGB(255, 125, 0),
	Color3.fromRGB(170, 90, 255),
	Color3.fromRGB(255, 255, 255),
}

local function botColor(i)
	local hue = (i * 0.61803398875) % 1
	local sat = 0.38 + ((i * 7) % 5) * 0.035
	local val = 0.58 + ((i * 3) % 4) * 0.05
	return Color3.fromHSV(hue, sat, val)
end

-- ============================================================================
-- CONSTRUCCIÓN
-- ============================================================================
function Engine.new(planetId, botCount, difficulty)
	local grid = WorldGrid.Generate(planetId)
	local self = setmetatable({}, Engine)
	self.planetId = if WorldGrid.PLANETS[planetId] then planetId else "EARTH"
	self.w = grid.w
	self.h = grid.h
	self.size = grid.w * grid.h
	self.land = grid.land
	self.landCount = grid.landCount
	self.owner = buffer.create(self.size)
	self.nations = {}
	self.list = {}
	self.changes = {}
	self.buildingAt = {}
	self.events = {}
	self.difficultyName = if DIFFICULTY[difficulty] then difficulty else "NORMAL"
	self.diff = DIFFICULTY[self.difficultyName]
	self.time = 0
	self.econAccum = 0
	self.phase = "SPAWN"
	self.spawnTimer = SPAWN_SECONDS
	self.paused = true
	self.winner = nil
	self.nextId = 1
	self.humanCount = 0
	self.rng = Random.new()
	self._nb = {}

	local names = table.clone(BOT_NAMES)
	for i = #names, 2, -1 do
		local j = self.rng:NextInteger(1, i)
		names[i], names[j] = names[j], names[i]
	end
	local count = math.clamp(math.floor(botCount or 40), 0, 100)
	for i = 1, count do
		local n = self:addNation(names[i] or ("Nación " .. i), botColor(i), true, nil)
		self:autoSpawn(n, true)
	end
	return self
end

function Engine:addNation(name, color, isBot, player)
	local id = self.nextId
	self.nextId += 1
	local n = {
		id = id,
		name = name,
		color = color,
		isBot = isBot,
		player = player,
		userId = player and player.UserId or nil,
		troops = 0,
		gold = if isBot then 200 else 700,
		cells = 0,
		cities = 0,
		alive = false,
		spawned = false,
		capital = nil,
		attacks = {},
		buildings = {},
		posts = {},
		ports = {},
		defenseAI = true,
		attackedBy = {},
		thinkTimer = self.rng:NextNumber() * 4,
	}
	self.nations[id] = n
	table.insert(self.list, n)
	return n
end

function Engine:addHuman(player)
	self.humanCount += 1
	local color = HUMAN_COLORS[((self.humanCount - 1) % #HUMAN_COLORS) + 1]
	local n = self:addNation(player.DisplayName, color, false, player)
	self.paused = false
	return n
end

function Engine:notify(userId, text)
	table.insert(self.events, { userId = userId, text = text })
end

-- ============================================================================
-- GEOMETRÍA
-- ============================================================================
function Engine:neighbors(i, out)
	local w, h = self.w, self.h
	local x = i % w
	local y = i // w
	local n = 1
	out[1] = y * w + (if x == 0 then w - 1 else x - 1)
	n += 1
	out[2] = y * w + (if x == w - 1 then 0 else x + 1)
	if y > 0 then
		n += 1
		out[n] = i - w
	end
	if y < h - 1 then
		n += 1
		out[n] = i + w
	end
	return n
end

function Engine:cellDistance(a, b)
	local w = self.w
	local ax, ay = a % w, a // w
	local bx, by = b % w, b // w
	local dx = math.abs(ax - bx)
	dx = math.min(dx, w - dx)
	local dy = math.abs(ay - by)
	return math.sqrt(dx * dx + dy * dy)
end

function Engine:isClear(cell, radius)
	local w, h = self.w, self.h
	local cx, cy = cell % w, cell // w
	for dy = -radius, radius do
		local y = cy + dy
		if y >= 0 and y < h then
			for dx = -radius, radius do
				local x = (cx + dx) % w
				if buffer.readu8(self.owner, y * w + x) ~= 0 then
					return false
				end
			end
		end
	end
	return true
end

-- ============================================================================
-- PROPIEDAD DE CELDAS
-- ============================================================================
function Engine:setOwner(i, newId)
	local old = buffer.readu8(self.owner, i)
	if old == newId then
		return
	end
	if old ~= 0 then
		self.nations[old].cells -= 1
	end
	if newId ~= 0 then
		self.nations[newId].cells += 1
	end
	buffer.writeu8(self.owner, i, newId)
	table.insert(self.changes, i)
	local b = self.buildingAt[i]
	if b then
		self:removeBuilding(b)
	end
end

function Engine:removeBuilding(b)
	self.buildingAt[b.cell] = nil
	local n = self.nations[b.owner]
	if not n then
		return
	end
	local idx = table.find(n.buildings, b)
	if idx then
		table.remove(n.buildings, idx)
	end
	if b.kind == "City" then
		n.cities = math.max(0, n.cities - 1)
	elseif b.kind == "Post" then
		local k = table.find(n.posts, b)
		if k then
			table.remove(n.posts, k)
		end
	elseif b.kind == "Port" then
		local k = table.find(n.ports, b)
		if k then
			table.remove(n.ports, k)
		end
	end
	if n.userId then
		self:notify(n.userId, "💥 Perdiste tu edificio: " .. b.kind)
	end
end

function Engine:maxTroops(n)
	return 4000 + n.cells * 30 + n.cities * 8000
end

function Engine:spawnNation(n, cell)
	local w, h = self.w, self.h
	local cx, cy = cell % w, cell // w
	for dy = -3, 3 do
		for dx = -3, 3 do
			if dx * dx + dy * dy <= 10 then
				local y = cy + dy
				if y >= 0 and y < h then
					local j = y * w + ((cx + dx) % w)
					if buffer.readu8(self.land, j) == 1 and buffer.readu8(self.owner, j) == 0 then
						self:setOwner(j, n.id)
					end
				end
			end
		end
	end
	n.spawned = true
	n.alive = n.cells > 0
	n.capital = cell
	n.troops = START_TROOPS
	n.attacks = {}
	return n.alive
end

function Engine:autoSpawn(n, strict)
	for pass = 1, 2 do
		local radius = if pass == 1 then (if strict then 7 else 4) else 2
		for _ = 1, 400 do
			local cell = self.rng:NextInteger(0, self.size - 1)
			if buffer.readu8(self.land, cell) == 1 and self:isClear(cell, radius) then
				return self:spawnNation(n, cell)
			end
		end
	end
	return false
end

function Engine:setSpawn(n, cell)
	if n.alive then
		return false, "Ya estás en el mapa"
	end
	if self.phase == "ENDED" then
		return false, "La partida terminó"
	end
	if buffer.readu8(self.land, cell) ~= 1 then
		return false, "Debes elegir tierra firme"
	end
	if not self:isClear(cell, 3) then
		return false, "Zona ocupada, elige otro lugar"
	end
	self:spawnNation(n, cell)
	self:notify(n.userId, "⭐ ¡Has aparecido! Haz clic en territorio vecino para expandirte")
	return true
end

-- ============================================================================
-- ATAQUES
-- ============================================================================
function Engine:fillQueue(n, atk)
	local owner, land = self.owner, self.land
	local nb = self._nb
	local seen = {}
	local queue = atk.queue
	for i = 0, self.size - 1 do
		if buffer.readu8(owner, i) == n.id then
			local cnt = self:neighbors(i, nb)
			for q = 1, cnt do
				local j = nb[q]
				if
					buffer.readu8(owner, j) == atk.target
					and buffer.readu8(land, j) == 1
					and not seen[j]
					and #queue < 6000
				then
					seen[j] = true
					queue[#queue + 1] = j
				end
			end
		end
	end
end

function Engine:hasAttack(n, target)
	for _, a in ipairs(n.attacks) do
		if a.target == target then
			return true
		end
	end
	return false
end

function Engine:launchAttack(n, targetId, ratio)
	if not n.alive then
		return false, "No estás en el mapa"
	end
	if targetId == n.id then
		return false, "Ese territorio ya es tuyo"
	end
	if targetId ~= 0 then
		local tn = self.nations[targetId]
		if not tn or not tn.alive then
			return false, "Objetivo inválido"
		end
	end
	local troops = math.floor(n.troops * math.clamp(ratio, 0.05, 1))
	if troops < 50 then
		return false, "Tropas insuficientes"
	end
	local existing = nil
	for _, a in ipairs(n.attacks) do
		if a.target == targetId then
			existing = a
		end
	end
	local atk = existing or { target = targetId, troops = 0, queue = {}, refills = 0 }
	if not existing then
		self:fillQueue(n, atk)
		if #atk.queue == 0 then
			return false, "Sin frontera terrestre (necesitas un Puerto para desembarcar)"
		end
		table.insert(n.attacks, atk)
	end
	atk.troops += troops
	n.troops -= troops
	return true
end

function Engine:processAttack(n, atk)
	local target = atk.target
	local tn = nil
	if target ~= 0 then
		tn = self.nations[target]
		if not tn or not tn.alive then
			return true
		end
	end
	if atk.troops < 5 then
		return true
	end
	local queue = atk.queue
	if #queue == 0 then
		atk.refills += 1
		if atk.refills > 40 then
			return true
		end
		self:fillQueue(n, atk)
		if #queue == 0 then
			return true
		end
	end

	local owner, land = self.owner, self.land
	local nb = self._nb
	local maxCells = 3 + math.floor(math.sqrt(n.cells) * 0.6)
	local w = self.w

	for _ = 1, maxCells do
		local qn = #queue
		if qn == 0 then
			break
		end
		local k = self.rng:NextInteger(1, qn)
		local cell = queue[k]
		queue[k] = queue[qn]
		queue[qn] = nil
		if buffer.readu8(owner, cell) == target then
			local cnt = self:neighbors(cell, nb)
			local adjacent = false
			for q = 1, cnt do
				if buffer.readu8(owner, nb[q]) == n.id then
					adjacent = true
					break
				end
			end
			if adjacent then
				local cost = 3.2
				local density = 0
				if tn then
					density = tn.troops / math.max(1, tn.cells)
					cost = 2.5 + density * 0.9
					if tn.defenseAI then
						cost *= 1.25
					end
					if #tn.posts > 0 then
						local cx, cy = cell % w, cell // w
						for _, post in ipairs(tn.posts) do
							local px, py = post.cell % w, post.cell // w
							local dx = math.abs(px - cx)
							dx = math.min(dx, w - dx)
							local dy = math.abs(py - cy)
							if dx * dx + dy * dy <= POST_RADIUS * POST_RADIUS then
								cost *= 2
								break
							end
						end
					end
				end
				if atk.troops < cost then
					return true
				end
				atk.troops -= cost
				if tn then
					tn.troops = math.max(0, tn.troops - density * 0.6)
					tn.attackedBy[n.id] = self.time
				end
				self:setOwner(cell, n.id)
				for q = 1, cnt do
					local j = nb[q]
					if buffer.readu8(owner, j) == target and buffer.readu8(land, j) == 1 and #queue < 6000 then
						queue[#queue + 1] = j
					end
				end
			end
		end
	end
	return false
end

function Engine:processAttacks(n)
	local attacks = n.attacks
	for k = #attacks, 1, -1 do
		local atk = attacks[k]
		if self:processAttack(n, atk) then
			n.troops = math.min(self:maxTroops(n), n.troops + math.max(0, atk.troops))
			table.remove(attacks, k)
		end
	end
end

function Engine:retreat(n)
	for k = #n.attacks, 1, -1 do
		n.troops = math.min(self:maxTroops(n), n.troops + n.attacks[k].troops)
		table.remove(n.attacks, k)
	end
end

-- Desembarco anfibio: toma un bloque 3x3 de tierra
function Engine:landing(n, cell, cost)
	if n.troops < cost then
		return false, "Tropas insuficientes para desembarcar"
	end
	local w, h = self.w, self.h
	local cx, cy = cell % w, cell // w
	n.troops -= cost
	for dy = -1, 1 do
		for dx = -1, 1 do
			local y = cy + dy
			if y >= 0 and y < h then
				local j = y * w + ((cx + dx) % w)
				if buffer.readu8(self.land, j) == 1 and buffer.readu8(self.owner, j) ~= n.id then
					local old = buffer.readu8(self.owner, j)
					if old ~= 0 then
						local on = self.nations[old]
						on.attackedBy[n.id] = self.time
					end
					self:setOwner(j, n.id)
				end
			end
		end
	end
	return true
end

function Engine:playerAttack(n, cell, ratio)
	if self.phase ~= "RUNNING" then
		return false, "Espera a que termine la fase de aparición"
	end
	if buffer.readu8(self.land, cell) ~= 1 then
		return false, "Eso es océano"
	end
	local target = buffer.readu8(self.owner, cell)
	if target == n.id then
		return false, "Ese territorio ya es tuyo"
	end
	local ok, msg = self:launchAttack(n, target, ratio)
	if ok then
		return true
	end
	-- Sin frontera: intentar desembarco desde un puerto
	if msg and string.find(msg, "frontera") then
		for _, port in ipairs(n.ports) do
			if self:cellDistance(port.cell, cell) <= PORT_RANGE then
				local lok, lmsg = self:landing(n, cell, math.max(300, math.floor(n.troops * ratio * 0.5)))
				if lok then
					self:notify(n.userId, "⚓ ¡Desembarco exitoso! Ahora expándete desde la cabeza de playa")
					return true
				end
				return false, lmsg
			end
		end
	end
	return false, msg
end

-- ============================================================================
-- EDIFICIOS Y ARMAS
-- ============================================================================
function Engine:build(n, kind, cell)
	local cost = Engine.COSTS[kind]
	if not cost then
		return false, "Edificio inválido"
	end
	if not n.alive then
		return false, "No estás en el mapa"
	end
	if buffer.readu8(self.owner, cell) ~= n.id then
		return false, "Debes construir en tu territorio"
	end
	if self.buildingAt[cell] then
		return false, "Ya hay un edificio ahí"
	end
	if n.gold < cost then
		return false, string.format("Necesitas 💰%d de oro", cost)
	end
	if kind == "Port" then
		local nb = self._nb
		local cnt = self:neighbors(cell, nb)
		local coastal = false
		for q = 1, cnt do
			if buffer.readu8(self.land, nb[q]) == 0 then
				coastal = true
			end
		end
		if not coastal then
			return false, "El Puerto debe estar en la costa"
		end
	end
	n.gold -= cost
	local b = { kind = kind, cell = cell, owner = n.id }
	self.buildingAt[cell] = b
	table.insert(n.buildings, b)
	if kind == "City" then
		n.cities += 1
	elseif kind == "Post" then
		table.insert(n.posts, b)
	elseif kind == "Port" then
		table.insert(n.ports, b)
	end
	return true
end

function Engine:nuke(n, cell)
	local hasSilo = false
	for _, b in ipairs(n.buildings) do
		if b.kind == "Silo" then
			hasSilo = true
		end
	end
	if not hasSilo then
		return false, "Necesitas un Silo para lanzar misiles"
	end
	if n.gold < NUKE_COST then
		return false, string.format("Necesitas 💰%d de oro", NUKE_COST)
	end
	n.gold -= NUKE_COST
	local w, h = self.w, self.h
	local cx, cy = cell % w, cell // w
	local victims = {}
	for dy = -NUKE_RADIUS, NUKE_RADIUS do
		for dx = -NUKE_RADIUS, NUKE_RADIUS do
			if dx * dx + dy * dy <= NUKE_RADIUS * NUKE_RADIUS then
				local y = cy + dy
				if y >= 0 and y < h then
					local j = y * w + ((cx + dx) % w)
					local o = buffer.readu8(self.owner, j)
					if buffer.readu8(self.land, j) == 1 and o ~= 0 and o ~= n.id then
						victims[o] = (victims[o] or 0) + 1
						self:setOwner(j, 0)
					end
				end
			end
		end
	end
	for id, cnt in pairs(victims) do
		local tn = self.nations[id]
		tn.troops *= math.max(0.4, 1 - cnt / math.max(1, tn.cells + cnt))
		tn.attackedBy[n.id] = self.time
		if tn.userId then
			self:notify(tn.userId, "☢️ ¡" .. n.name .. " lanzó un misil sobre tu territorio!")
		end
	end
	self:notify(nil, string.format("☢️ %s lanzó un misil nuclear", n.name))
	return true
end

-- ============================================================================
-- BOTS
-- ============================================================================
function Engine:census(n)
	local owner, land = self.owner, self.land
	local nb = self._nb
	local counts = {}
	local sample = {}
	local seenOwned = 0
	for i = 0, self.size - 1 do
		if buffer.readu8(owner, i) == n.id then
			seenOwned += 1
			if #sample < 10 then
				sample[#sample + 1] = i
			elseif self.rng:NextInteger(1, seenOwned) <= 10 then
				sample[self.rng:NextInteger(1, 10)] = i
			end
			local cnt = self:neighbors(i, nb)
			for q = 1, cnt do
				local j = nb[q]
				if buffer.readu8(land, j) == 1 then
					local o = buffer.readu8(owner, j)
					if o ~= n.id then
						counts[o] = (counts[o] or 0) + 1
					end
				end
			end
		end
	end
	return counts, sample
end

function Engine:botLanding(n, sample)
	if #sample == 0 then
		return
	end
	local w, h = self.w, self.h
	for _ = 1, 8 do
		local c = sample[self.rng:NextInteger(1, #sample)]
		local cx, cy = c % w, c // w
		local angle = self.rng:NextNumber() * math.pi * 2
		local dist = 6 + self.rng:NextNumber() * 22
		local tx = (cx + math.floor(math.cos(angle) * dist)) % w
		local ty = cy + math.floor(math.sin(angle) * dist)
		if ty >= 1 and ty < h - 1 then
			local j = ty * w + tx
			if buffer.readu8(self.land, j) == 1 and buffer.readu8(self.owner, j) == 0 then
				self:landing(n, j, 350)
				return
			end
		end
	end
end

function Engine:botThink(n)
	local d = self.diff
	if n.troops < 250 or #n.attacks >= d.maxAttacks then
		return
	end
	local counts, sample = self:census(n)
	local hasEnemy = false
	for id in pairs(counts) do
		if id ~= 0 then
			hasEnemy = true
		end
	end
	local target = nil
	if (counts[0] or 0) > 0 and (not hasEnemy or self.rng:NextNumber() < 0.7) then
		target = 0
	elseif hasEnemy then
		local best = math.huge
		for id in pairs(counts) do
			if id ~= 0 then
				local en = self.nations[id]
				if en and en.alive and n.troops > en.troops * d.edge then
					local score = en.troops * (0.6 + self.rng:NextNumber() * 0.8)
					if score < best then
						best = score
						target = id
					end
				end
			end
		end
	end
	if target then
		local ratio = d.minRatio + (d.maxRatio - d.minRatio) * self.rng:NextNumber()
		self:launchAttack(n, target, ratio)
	elseif next(counts) == nil and n.troops > 700 then
		self:botLanding(n, sample)
	end
end

-- ============================================================================
-- BUCLE PRINCIPAL
-- ============================================================================
function Engine:beginRunning()
	for _, n in ipairs(self.list) do
		if not n.isBot and not n.spawned then
			self:autoSpawn(n, false)
			self:notify(n.userId, "📍 Capital asignada automáticamente")
		end
	end
	self.phase = "BATTLE"
	self:notify(nil, "⚔️ ¡La conquista mundial ha comenzado!")
end

function Engine:economyStep()
	for _, n in ipairs(self.list) do
		if n.spawned and n.alive then
			if n.cells <= 0 then
				n.alive = false
				self:retreat(n)
				n.troops = 0
				self:notify(nil, "💀 " .. n.name .. " fue eliminado")
				if n.userId then
					self:notify(n.userId, "💀 Has sido eliminado. Elige un nuevo punto de aparición")
				end
			else
				local maxT = self:maxTroops(n)
				local mult = if n.isBot then self.diff.growth else 1
				local g = (8 + n.cells * 0.35) * math.max(0, 1 - n.troops / maxT) * mult
				n.troops = math.min(maxT, n.troops + g)
				n.gold += 1.5 + n.cells * 0.05 + n.cities * 3

				-- IA de DEFENSA: contraataca a quien te esté atacando
				if n.defenseAI and #n.attacks < 3 then
					for aid, t in pairs(n.attackedBy) do
						if self.time - t > 10 then
							n.attackedBy[aid] = nil
						elseif self.time - t < 4 then
							local en = self.nations[aid]
							if
								en
								and en.alive
								and not self:hasAttack(n, aid)
								and n.troops > self:maxTroops(n) * 0.35
							then
								local ok = self:launchAttack(n, aid, 0.3)
								if ok and n.userId then
									self:notify(n.userId, "🤖 IA Defensa contraatacó a " .. en.name)
								end
							end
						end
					end
				end
			end
		end
	end
end

function Engine:checkWin()
	for _, n in ipairs(self.list) do
		if n.alive and n.cells >= self.landCount * WIN_RATIO then
			self.phase = "ENDED"
			self.winner = n.id
			self:notify(
				nil,
				string.format(
					"🏆 ¡%s conquistó el %d%% del mundo!",
					n.name,
					math.floor(n.cells / self.landCount * 100)
				)
			)
			return
		end
	end
end

function Engine:tick(dt)
	if self.paused or self.phase == "ENDED" then
		return
	end
	self.time += dt
	if self.phase == "SPAWN" then
		self.spawnTimer -= dt
		if self.spawnTimer <= 0 then
			self:beginRunning()
		end
		return
	end

	for _, n in ipairs(self.list) do
		if n.alive then
			self:processAttacks(n)
			if n.isBot then
				n.thinkTimer -= dt
				if n.thinkTimer <= 0 then
					n.thinkTimer = self.diff.think * (0.7 + self.rng:NextNumber() * 0.6)
					self:botThink(n)
				end
			end
		end
	end

	self.econAccum += dt
	if self.econAccum >= 1 then
		self.econAccum -= 1
		self:economyStep()
		self:checkWin()
	end
end

-- ============================================================================
-- SERIALIZACIÓN
-- ============================================================================
function Engine:flushDiff()
	local c = self.changes
	local count = #c
	if count == 0 then
		return nil
	end
	self.changes = {}
	local buf = buffer.create(count * 4)
	for k = 1, count do
		local i = c[k]
		local ownerId = buffer.readu8(self.owner, i)
		buffer.writeu32(buf, (k - 1) * 4, i * 256 + ownerId)
	end
	return buf
end

function Engine:snapshotOwner()
	local snap = buffer.create(self.size)
	buffer.copy(snap, 0, self.owner)
	return snap
end

function Engine:getRoster()
	local roster = {}
	for _, n in ipairs(self.list) do
		local c = n.color
		table.insert(roster, {
			id = n.id,
			name = n.name,
			r = math.floor(c.R * 255 + 0.5),
			g = math.floor(c.G * 255 + 0.5),
			b = math.floor(c.B * 255 + 0.5),
			bot = n.isBot,
			capital = n.capital,
			cells = n.cells,
		})
	end
	return roster
end

function Engine:getStats()
	local list = {}
	local top = {}
	for _, n in ipairs(self.list) do
		if n.alive then
			table.insert(list, { id = n.id, cells = n.cells, troops = math.floor(n.troops) })
			local pct = if self.landCount > 0 then (n.cells / self.landCount * 100) else 0
			table.insert(top, {
				id = n.id,
				name = n.name,
				cells = n.cells,
				pct = pct,
				alive = n.alive,
				isBot = n.isBot,
			})
		end
	end
	table.sort(top, function(a, b)
		return a.cells > b.cells
	end)
	return {
		phase = self.phase,
		spawnTimer = math.max(0, math.ceil(self.spawnTimer)),
		winner = self.winner,
		landCount = self.landCount,
		nations = list,
		top = top,
	}
end

function Engine:getMe(n)
	local attacks = {}
	for _, a in ipairs(n.attacks) do
		table.insert(attacks, { target = a.target, troops = math.floor(a.troops) })
	end
	local buildings = {}
	for _, b in ipairs(n.buildings) do
		table.insert(buildings, { kind = b.kind, cell = b.cell })
	end
	return {
		id = n.id,
		troops = math.floor(n.troops),
		maxTroops = self:maxTroops(n),
		gold = math.floor(n.gold),
		cells = n.cells,
		alive = n.alive,
		spawned = n.spawned,
		capital = n.capital,
		defenseAI = n.defenseAI,
		attacks = attacks,
		buildings = buildings,
	}
end

return Engine
