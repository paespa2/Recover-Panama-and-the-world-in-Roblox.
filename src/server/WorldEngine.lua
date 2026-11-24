--!nonstrict
-- WorldEngine.lua
-- Motor de conquista territorial por celdas (estilo RoWorld / OpenFront) sobre el globo terráqueo.
--  * Cada nación (jugadores humanos + bots con nombres de países y personajes históricos) posee celdas.
--  * Las tropas se gastan para conquistar celdas vecinas (neutrales o enemigas).
--  * El jugador construye (Ciudad, Puerto, Puesto defensivo, Silo) y decide la expansión.
--  * La IA de Defensa (opcional) contraataca a quien te ataca y fortalece tus fronteras.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldGrid = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldGrid"))
local BotAI = require(script.Parent:WaitForChild("BotAI"))

-- Países reales por celda (generado por tools/build_countries.py). Si falta, el modo PAÍSES no estará disponible.
local okCountries, CountryData = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CountryData", 5))
end)
if not okCountries then
	CountryData = nil
	warn("[WorldEngine] CountryData no disponible: el modo Países vs Países queda desactivado")
end

local Engine = {}
Engine.__index = Engine

local SPAWN_SECONDS = 25
local WIN_RATIO = 0.65
local START_TROOPS = 3000
local NUKE_COST = 900
local NUKE_RADIUS = 16
local POST_RADIUS = 20
local PORT_RANGE = 140

Engine.COSTS = { City = 500, Port = 400, Post = 350, Silo = 1200 }
Engine.NUKE_COST = NUKE_COST
local NUKE_COOLDOWN = 45

-- Armas bélicas (poderes que se apuntan con un clic). Todas cuestan oro y tienen enfriamiento propio.
--   radius    radio del área en celdas        destroy   fracción de celdas enemigas que pierden dueño
--   troopHit  fracción de tropas que pierden las naciones alcanzadas (además de las celdas perdidas)
--   impacts   número de impactos (el meteorito cae en racimo)        buildings   destruye todos los edificios del área
Engine.NUKE_RADIUS = NUKE_RADIUS
Engine.NUKE_COOLDOWN = NUKE_COOLDOWN
Engine.WEAPONS = {
	BOMB = { name = "Bomba", icon = "💣", cost = 250, radius = 5, cooldown = 6, destroy = 1.0 },
	ARTILLERY = {
		name = "Artillería",
		icon = "🎯",
		cost = 300,
		radius = 3,
		cooldown = 8,
		destroy = 0.4,
		troopHit = 0.3,
	},
	METEOR = { name = "Meteorito", icon = "☄️", cost = 650, radius = 7, cooldown = 25, destroy = 1.0, impacts = 3 },
	QUAKE = {
		name = "Terremoto",
		icon = "🌋",
		cost = 550,
		radius = 13,
		cooldown = 30,
		destroy = 0.35,
		buildings = true,
	},
}
Engine.WEAPON_ORDER = { "BOMB", "ARTILLERY", "METEOR", "QUAKE" }

local DIFFICULTY = {
	EASY = { think = 7.0, maxAttacks = 1, minRatio = 0.15, maxRatio = 0.3, growth = 0.7, edge = 1.8 },
	NORMAL = { think = 5.5, maxAttacks = 1, minRatio = 0.2, maxRatio = 0.4, growth = 0.9, edge = 1.5 },
	HARD = { think = 4.0, maxAttacks = 2, minRatio = 0.25, maxRatio = 0.5, growth = 1.1, edge = 1.2 },
	EXTREME = { think = 2.5, maxAttacks = 2, minRatio = 0.3, maxRatio = 0.6, growth = 1.4, edge = 0.9 },
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
-- Coste de conquista por terreno (u8: 100 = llanura, hasta 180 = montaña muy escarpada). Se deduce de la rugosidad del
-- relieve sombreado de la imagen del mapa: el gradiente de luminosidad es alto donde hay montañas y bajo en llanuras.
local function buildTerrainCost(planetId, land, w, h)
	local ok, base = pcall(WorldGrid.BuildBase, planetId, land)
	if not ok or not base or buffer.len(base) ~= w * h * 3 then
		return nil
	end
	local lum = buffer.create(w * h)
	for i = 0, w * h - 1 do
		local o = i * 3
		buffer.writeu8(
			lum,
			i,
			(buffer.readu8(base, o) * 3 + buffer.readu8(base, o + 1) * 6 + buffer.readu8(base, o + 2)) // 10
		)
	end
	local cost = buffer.create(w * h)
	for y = 0, h - 1 do
		local up, down = math.max(0, y - 1), math.min(h - 1, y + 1)
		for x = 0, w - 1 do
			local i = y * w + x
			local f = 100
			if buffer.readu8(land, i) == 1 then
				local l, r = (x - 1) % w, (x + 1) % w
				local gx = math.abs(buffer.readu8(lum, y * w + r) - buffer.readu8(lum, y * w + l))
				local gy = math.abs(buffer.readu8(lum, down * w + x) - buffer.readu8(lum, up * w + x))
				f = 100 + math.min(70, math.floor((gx + gy) * 1.2))
			end
			buffer.writeu8(cost, i, f)
		end
	end
	return cost
end

function Engine.new(planetId, botCount, difficulty, mode, seed)
	local grid = WorldGrid.Generate(planetId)
	local self = setmetatable({}, Engine)
	self.planetId = if WorldGrid.PLANETS[planetId] then planetId else "EARTH"
	self.w = grid.w
	self.h = grid.h
	self.size = grid.w * grid.h
	self.land = grid.land
	self.landCount = grid.landCount
	self.terrainCost = buildTerrainCost(self.planetId, grid.land, grid.w, grid.h) -- nil si no hay relieve
	self.owner = buffer.create(self.size)
	self.nations = {}
	self.list = {}
	self.changes = {}
	self.buildingAt = {}
	self.events = {}
	self.fxEvents = {} -- efectos visuales de armas para los clientes (los envía WorldServer)
	self.scheduled = {} -- acciones diferidas (impactos de desastres, p. ej.): { at = instante, fn = función }
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
	-- Semilla de la partida: con la misma semilla y las mismas intenciones la simulación se repite (repeticiones y pruebas)
	self.seed = seed or (os.time() % 2147483647)
	self.rng = Random.new(self.seed)
	self.tickCount = 0
	self.pending = {} -- intenciones de los jugadores pendientes de ejecutar
	self.intentLog = {} -- { t = tick, id = nación, intent = ... } para reproducir la partida
	self.disasterTimer = 55 + self.rng:NextNumber() * 30 -- primer desastre 55-85 s después de empezar la guerra
	self._nb = {}

	self.mode = "FREE"
	self.teamMode = false
	-- Estilo de propagación: CELL (célula redonda), ORGANIC (frontera irregular), TENDRIL (tentáculos)
	self.propagation = "CELL"
	if (mode == "COUNTRIES" or mode == "CONTINENTS") and self.planetId == "EARTH" and CountryData then
		self.mode = "COUNTRIES"
		self.teamMode = (mode == "CONTINENTS") -- cada continente es un equipo: los aliados no se atacan
		self:initCountries()
		return self
	end

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
		playerName = player and player.DisplayName or nil,
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
		persona = if isBot then BotAI.assign(self.rng, name) else nil,
		lastNuke = -999,
		weaponReady = {}, -- [arma] = instante (self.time) en que vuelve a estar lista
		-- Autojuego de los jugadores: al empezar la guerra su nación se expande sola (se puede apagar en el HUD)
		autoMode = if isBot then nil else "EXPAND",
		autoRatio = 0.4,
		autoTimer = 0,
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
-- INTENCIONES Y EJECUCIONES (diseño tomado de la arquitectura documentada de OpenFront: los jugadores solo
-- envían intenciones y únicamente el motor modifica el estado, siempre al principio de un tick)
-- ============================================================================
local INTENT_HANDLERS = {
	SPAWN = function(e, n, i)
		return e:setSpawn(n, i.cell)
	end,
	ATTACK = function(e, n, i)
		return e:playerAttack(n, i.cell, i.ratio)
	end,
	BUILD = function(e, n, i)
		return e:build(n, i.kind, i.cell)
	end,
	WEAPON = function(e, n, i)
		return e:weapon(n, i.kind, i.cell)
	end,
	NUKE = function(e, n, i)
		return e:nuke(n, i.cell)
	end,
	RETREAT = function(e, n)
		e:retreat(n)
		return true
	end,
	DEFENSE_AI = function(_, n, i)
		n.defenseAI = i.on == true
		return true
	end,
	AUTO = function(_, n, i)
		if i.mode then
			n.autoMode = i.mode
		end
		n.autoRatio = i.ratio or 0.4
		return true
	end,
}
local INTENT_LOG_MAX = 20000

-- Encola la intención de una nación; no cambia el estado hasta runIntents
function Engine:submit(n, intent)
	if #self.pending < 400 and INTENT_HANDLERS[intent.a] then
		table.insert(self.pending, { n = n, intent = intent })
	end
end

-- Ejecuta las intenciones pendientes (se llama al inicio de cada tick)
function Engine:runIntents()
	local pending = self.pending
	if #pending == 0 then
		return
	end
	self.pending = {}
	for _, p in ipairs(pending) do
		local ok, msg = INTENT_HANDLERS[p.intent.a](self, p.n, p.intent)
		if ok == false and msg and p.n.userId then
			self:notify(p.n.userId, "⚠️ " .. tostring(msg))
		end
		if #self.intentLog < INTENT_LOG_MAX then
			table.insert(self.intentLog, { t = self.tickCount, id = p.n.id, intent = p.intent })
		end
	end
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
		local nn = self.nations[newId]
		nn.cells += 1
		-- Caja envolvente de la nación: limita los escaneos de la IA y de los ataques
		local x = i % self.w
		local y = i // self.w
		if not nn.bx0 or x < nn.bx0 then
			nn.bx0 = x
		end
		if not nn.bx1 or x > nn.bx1 then
			nn.bx1 = x
		end
		if not nn.by0 or y < nn.by0 then
			nn.by0 = y
		end
		if not nn.by1 or y > nn.by1 then
			nn.by1 = y
		end
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
	return 10000 + n.cells * 25 + n.cities * 15000
end

function Engine:spawnNation(n, cell)
	local w, h = self.w, self.h
	local cx, cy = cell % w, cell // w
	for dy = -5, 5 do
		for dx = -5, 5 do
			if dx * dx + dy * dy <= 26 then
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

-- ============================================================================
-- MODO PAÍSES VS PAÍSES: cada país real es una nación con su territorio
-- ============================================================================
-- Matiz base por continente: África, Antártida, Asia, Europa, Norteamérica, Oceanía, Sudamérica
local CONTINENT_HUE = { 0.08, 0.55, 0.0, 0.58, 0.33, 0.8, 0.15 }

function Engine:initCountries()
	local ids = CountryData.GetBuffer()
	local w = self.w
	local byCountry = {}
	for _, c in ipairs(CountryData.countries) do
		local cid, name, iso, cont, pop = c[1], c[2], c[3], c[4], c[5]
		local hue = (CONTINENT_HUE[cont] or 0.5) + (((cid * 37) % 100) / 100 - 0.5) * 0.08
		local color = Color3.fromHSV(hue % 1, 0.42 + ((cid * 7) % 5) * 0.04, 0.6 + ((cid * 3) % 4) * 0.05)
		local n = self:addNation(name, color, true, nil)
		n.countryId = cid
		n.continent = cont
		n.iso = iso
		n.pop = pop
		byCountry[cid] = n
	end

	-- Territorio: toda la tierra de cada país (según la máscara de tierra del motor)
	local sx, sy, cnt = {}, {}, {}
	for i = 0, self.size - 1 do
		local cid = buffer.readu8(ids, i)
		if cid ~= 0 and buffer.readu8(self.land, i) == 1 then
			local n = byCountry[cid]
			if n then
				self:setOwner(i, n.id)
				sx[cid] = (sx[cid] or 0) + i % w
				sy[cid] = (sy[cid] or 0) + i // w
				cnt[cid] = (cnt[cid] or 0) + 1
			end
		end
	end

	-- Capital: la celda propia más cercana al centroide del país
	local bestD = {}
	for i = 0, self.size - 1 do
		local o = buffer.readu8(self.owner, i)
		if o ~= 0 then
			local n = self.nations[o]
			local cid = n.countryId
			local c = cnt[cid]
			if c then
				local dx = i % w - sx[cid] / c
				local dy = i // w - sy[cid] / c
				local d = dx * dx + dy * dy
				if not bestD[cid] or d < bestD[cid] then
					bestD[cid] = d
					n.capital = i
				end
			end
		end
	end

	for _, n in ipairs(self.list) do
		n.spawned = true
		n.alive = n.cells > 0
		n.troops = math.clamp(1500 + n.cells * 5, 1500, 60000)
	end
	self.changes = {} -- el estado inicial viaja en el snapshot, no como diferencias
end

-- Un jugador toma el control de un país (sus celdas pasan a su nación)
function Engine:transferCountry(c, n)
	local w = self.w
	local x0, x1 = c.bx0 or 0, c.bx1 or (w - 1)
	local y0, y1 = c.by0 or 0, c.by1 or (self.h - 1)
	for y = y0, y1 do
		for x = x0, x1 do
			local i = y * w + x
			if buffer.readu8(self.owner, i) == c.id then
				self:setOwner(i, n.id)
			end
		end
	end
	c.attacks = {}
	c.alive = false
	n.countryId = c.countryId
	n.continent = c.continent
	n.iso = c.iso
	n.pop = c.pop
	n.capital = c.capital
	n.troops = c.troops
	n.attacks = {}
	n.spawned = true
	n.alive = n.cells > 0
	n.claimedFrom = c -- para poder devolver el país si el jugador cambia de elección durante la aparición
	n.name = string.format("%s (%s)", c.name, n.name)
	c.capital = nil
end

-- Devuelve a la IA el país que el jugador había tomado (cambio de elección en la fase de aparición)
function Engine:releaseCountry(n)
	local c = n.claimedFrom
	if not c then
		return
	end
	local w = self.w
	local x0, x1 = n.bx0 or 0, n.bx1 or (w - 1)
	local y0, y1 = n.by0 or 0, n.by1 or (self.h - 1)
	for y = y0, y1 do
		for x = x0, x1 do
			local i = y * w + x
			if buffer.readu8(self.owner, i) == n.id then
				self:setOwner(i, c.id)
			end
		end
	end
	c.alive = c.cells > 0
	c.capital = n.capital
	c.attacks = {}
	n.claimedFrom = nil
	n.alive = false
	n.spawned = false
	n.countryId, n.continent, n.iso, n.pop = nil, nil, nil, nil
	n.capital = nil
	n.troops = 0
	n.attacks = {}
	n.name = n.playerName or n.name
end

-- Quita el territorio de un jugador (cambio de ubicación en la fase de aparición)
function Engine:abandonTerritory(n)
	local w = self.w
	local x0, x1 = n.bx0 or 0, n.bx1 or (w - 1)
	local y0, y1 = n.by0 or 0, n.by1 or (self.h - 1)
	for y = y0, y1 do
		for x = x0, x1 do
			local i = y * w + x
			if buffer.readu8(self.owner, i) == n.id then
				self:setOwner(i, 0)
			end
		end
	end
	n.alive = false
	n.spawned = false
	n.capital = nil
	n.troops = 0
	n.attacks = {}
end

function Engine:claimCountry(n, cell)
	if n.eliminated then
		return false, "Estás eliminado: solo puedes observar la partida"
	end
	if self.phase == "ENDED" then
		return false, "La partida terminó"
	end
	local id = buffer.readu8(self.owner, cell)
	local c = if id ~= 0 then self.nations[id] else nil
	if n.alive then
		-- Durante la aparición se puede cambiar de país; después de empezar la guerra, no
		if self.phase ~= "SPAWN" or not n.claimedFrom then
			return false, "Ya estás en el mapa"
		end
		if id == n.id then
			return false, "Ya gobiernas ese país"
		end
	end
	if not c or not c.countryId or not c.alive then
		return false, "Elige un país: haz clic sobre su territorio"
	end
	if not c.isBot then
		return false, "Ese país ya tiene jugador"
	end
	if self.phase ~= "SPAWN" and c.cells > 800 then
		return false, "La guerra ya empezó: elige un país pequeño (menos de 800 celdas)"
	end
	if n.alive then
		self:releaseCountry(n) -- todo validado: se devuelve el país anterior antes de tomar el nuevo
	end
	local cname = c.name
	self:transferCountry(c, n)
	self:notify(n.userId, "🌍 ¡Gobiernas " .. cname .. "! Haz clic en territorio vecino para expandirte")
	return true
end

-- Asigna un país al azar (preferiblemente mediano) a quien no eligió ninguno
function Engine:autoClaim(n)
	local pool, any = {}, {}
	for _, c in ipairs(self.list) do
		if c.countryId and c.isBot and c.alive then
			any[#any + 1] = c
			if c.cells >= 25 and c.cells <= 4000 then
				pool[#pool + 1] = c
			end
		end
	end
	local src = if #pool > 0 then pool else any
	if #src == 0 then
		return false
	end
	local c = src[self.rng:NextInteger(1, #src)]
	local cname = c.name
	self:transferCountry(c, n)
	self:notify(n.userId, "📍 País asignado automáticamente: " .. cname)
	return true
end

function Engine:setSpawn(n, cell)
	if n.eliminated then
		return false, "Estás eliminado: solo puedes observar la partida"
	end
	if self.mode == "COUNTRIES" then
		return self:claimCountry(n, cell)
	end
	if self.phase == "ENDED" then
		return false, "La partida terminó"
	end
	-- Durante la aparición se puede cambiar de ubicación; si el nuevo punto no vale, se recupera el anterior
	local oldCapital = nil
	if n.alive then
		if self.phase ~= "SPAWN" then
			return false, "Ya estás en el mapa"
		end
		oldCapital = n.capital
		self:abandonTerritory(n)
	end
	local function fail(msg)
		if oldCapital then
			self:spawnNation(n, oldCapital)
		end
		return false, msg
	end
	if buffer.readu8(self.land, cell) ~= 1 then
		return fail("Debes elegir tierra firme")
	end
	if not self:isClear(cell, 3) then
		return fail("Zona ocupada, elige otro lugar")
	end
	self:spawnNation(n, cell)
	self:notify(n.userId, "⭐ ¡Has aparecido! Haz clic en territorio vecino para expandirte")
	return true
end

-- ============================================================================
-- ATAQUES
-- ============================================================================
-- Multiplicador de coste del terreno de una celda (1 = llanura, hasta 1,8 en montaña escarpada)
function Engine:terrain(i)
	local c = self.terrainCost
	if not c then
		return 1
	end
	return buffer.readu8(c, i) / 100
end

function Engine:fillQueue(n, atk)
	local owner, land = self.owner, self.land
	local nb = self._nb
	local seen = {}
	local queue = atk.queue
	local w, h = self.w, self.h
	local x0, x1 = n.bx0 or 0, n.bx1 or (w - 1)
	local y0, y1 = n.by0 or 0, n.by1 or (h - 1)
	for y = y0, y1 do
		for x = x0, x1 do
			local i = y * w + x
			if buffer.readu8(owner, i) == n.id then
				local cnt = self:neighbors(i, nb)
				for q = 1, cnt do
					local j = nb[q]
					if
						buffer.readu8(owner, j) == atk.target
						and buffer.readu8(land, j) == 1
						and not seen[j]
						and #queue < 25000
					then
						seen[j] = true
						atk.prio[j] = self:terrain(j) -- llegada: las celdas fáciles se toman antes
						queue[#queue + 1] = j
					end
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

function Engine:launchAttack(n, targetId, ratio, targetCell)
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
		if self:isAlly(n, tn) then
			return false, "No puedes atacar a un aliado de tu continente"
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
	local atk = existing
		or { target = targetId, troops = 0, queue = {}, prio = {}, refills = 0, targetCell = targetCell }
	if targetCell then
		atk.targetCell = targetCell
	end
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
	if atk.troops < 2 then
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
	-- Escalado de velocidad estilo RoWorld / OpenFront: oleadas de conquista rápida
	local maxCells = math.clamp(math.floor(math.sqrt(atk.troops) * 1.6) + math.floor(math.sqrt(n.cells) * 0.4), 8, 120)
	local w = self.w
	local tgtCell = atk.targetCell
	local deferred = {}

	for _ = 1, maxCells do
		local qn = #queue
		if qn == 0 then
			break
		end
		local k = 1
		if tgtCell then
			-- Spearhead: dar prioridad a celdas en dirección al clic del jugador
			local tx, ty = tgtCell % w, tgtCell // w
			local bestDist = math.huge
			local samples = math.min(qn, 8)
			for _s = 1, samples do
				local idx = self.rng:NextInteger(1, qn)
				local c = queue[idx]
				local cx, cy = c % w, c // w
				local dx = math.abs(tx - cx)
				dx = math.min(dx, w - dx)
				local dy = math.abs(ty - cy)
				local distSq = dx * dx + dy * dy
				if distSq < bestDist then
					bestDist = distSq
					k = idx
				end
			end
		else
			k = self.rng:NextInteger(1, qn)
			local style = self.propagation
			local cap = n.capital
			if cap and style ~= "ORGANIC" and qn > 1 then
				-- CELL: crece como una célula/bacteria (blob redondo desde el núcleo).
				-- TENDRIL: lo contrario, emite tentáculos hacia fuera.
				local cx0, cy0 = cap % w, cap // w
				local best = nil
				local samples = if style == "CELL" then 8 else 3
				for _s = 1, samples do
					local idx = if _s == 1 then k else self.rng:NextInteger(1, qn)
					local c = queue[idx]
					local dx = math.abs(c % w - cx0)
					dx = math.min(dx, w - dx)
					local dy = c // w - cy0
					local d = dx * dx + dy * dy
					if style == "TENDRIL" then
						d = -d
					end
					if style == "CELL" then
						-- Frente de onda: se toma primero la celda con menor "tiempo de llegada" (distancia acumulada
						-- ponderada por el coste del terreno): redondo en llanura y más lento en montaña
						d = atk.prio[c] or 0
					end
					if not best or d < best then
						best = d
						k = idx
					end
				end
			end
		end

		local cell = queue[k]
		queue[k] = queue[qn]
		queue[qn] = nil
		-- El orden de la cola casi no cambia la forma (la frontera se consume por oleadas), así que la forma la da
		-- una probabilidad de aceptación: ORGANIC = borde irregular; TENDRIL = lóbulos tipo ameba (pseudópodos)
		local style = self.propagation
		local capCell = n.capital
		if style ~= "CELL" and not tgtCell and capCell then
			local accept = 1
			if style == "ORGANIC" then
				accept = 0.55
			else
				local ang = math.atan2(cell // w - capCell // w, cell % w - capCell % w)
				local lobe = (math.sin(ang * 4 + n.id) + 1) * 0.5 -- 0..1 con 4 lóbulos
				accept = 0.12 + 0.88 * lobe * lobe
			end
			if self.rng:NextNumber() > accept then
				deferred[#deferred + 1] = cell -- se reintenta en el siguiente tick (no dentro de este)
				continue
			end
		end
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
				-- Costo de expansión estilo RoWorld: la tierra libre (neutra) se expande muy rápido y fluido
				local cost = 1.0
				local density = 0
				if tn then
					density = tn.troops / math.max(1, tn.cells)
					cost = 1.8 + density * 0.8
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
								cost *= 2.0
								break
							end
						end
					end
				end
				cost *= self:terrain(cell) -- las montañas cuestan más tropas
				if atk.troops < cost then
					return true
				end
				atk.troops -= cost
				if tn then
					tn.troops = math.max(0, tn.troops - density * 0.5)
					tn.attackedBy[n.id] = self.time
				end
				self:setOwner(cell, n.id)
				for q = 1, cnt do
					local j = nb[q]
					if buffer.readu8(owner, j) == target and buffer.readu8(land, j) == 1 and #queue < 25000 then
						-- llegada = la de la celda conquistada + coste del terreno de la nueva
						local arrival = (atk.prio[cell] or 0) + self:terrain(j)
						local oldArrival = atk.prio[j]
						if not oldArrival or arrival < oldArrival then
							atk.prio[j] = arrival
						end
						queue[#queue + 1] = j
					end
				end
			end
		end
	end
	for _, c in ipairs(deferred) do
		queue[#queue + 1] = c
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

-- Modo equipos: dos naciones del mismo continente son aliadas y no pueden atacarse
function Engine:isAlly(a, b)
	return self.teamMode == true
		and a ~= nil
		and b ~= nil
		and a ~= b
		and a.continent ~= nil
		and a.continent == b.continent
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
				local cur = buffer.readu8(self.owner, j)
				if buffer.readu8(self.land, j) == 1 and cur ~= n.id and not self:isAlly(n, self.nations[cur]) then
					local old = cur
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
	if self.phase ~= "BATTLE" and self.phase ~= "RUNNING" then
		return false, "Espera a que termine la fase de aparición"
	end
	if buffer.readu8(self.land, cell) ~= 1 then
		return false, "Eso es océano"
	end
	local target = buffer.readu8(self.owner, cell)
	if target == n.id then
		return false, "Ese territorio ya es tuyo"
	end
	local ok, msg = self:launchAttack(n, target, ratio, cell)
	if ok then
		return true
	end
	-- Sin frontera: intentar desembarco desde un puerto
	if msg and string.find(msg, "frontera") then
		for _, port in ipairs(n.ports) do
			if self:cellDistance(port.cell, cell) <= PORT_RANGE then
				local lok, lmsg = self:landing(n, cell, math.max(300, math.floor(n.troops * ratio * 0.5)))
				if lok then
					self:notify(n.userId, "⚓ ¡Desembarco exitoso! Expandiéndote desde la costa")
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
	local waitLeft = (n.weaponReady.NUKE or 0) - self.time
	if waitLeft > 0 then
		return false, string.format("El misil nuclear se recarga (%ds)", math.ceil(waitLeft))
	end
	n.gold -= NUKE_COST
	n.weaponReady.NUKE = self.time + NUKE_COOLDOWN
	self:fx("NUKE", cell, NUKE_RADIUS)
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
					if
						buffer.readu8(self.land, j) == 1
						and o ~= 0
						and o ~= n.id
						and not self:isAlly(n, self.nations[o])
					then
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
-- DESASTRES NATURALES: cada mundo tiene los suyos. Se avisa 5 s antes (anillo rojo y mensaje) y luego golpean.
-- ============================================================================
Engine.DISASTERS_ENABLED = true
Engine.DISASTER_INFO = {
	METEOR_SHOWER = { icon = "☄️", name = "lluvia de meteoritos", radius = 14 },
	QUAKE = { icon = "🌋", name = "terremoto", radius = 12 },
	VOLCANO = { icon = "🔥", name = "erupción volcánica", radius = 6 },
	TORNADO = { icon = "🌪️", name = "tornado", radius = 10 },
	SANDSTORM = { icon = "🏜️", name = "tormenta de arena", radius = 20 },
}
Engine.PLANET_DISASTERS = {
	EARTH = { "QUAKE", "TORNADO", "METEOR_SHOWER" },
	PANGEA = { "VOLCANO", "METEOR_SHOWER", "QUAKE" },
	MARS = { "SANDSTORM", "METEOR_SHOWER" },
	MOON = { "METEOR_SHOWER" },
	VENUS = { "VOLCANO", "SANDSTORM" },
	ANDROMEDA = { "METEOR_SHOWER", "QUAKE" },
}

function Engine:schedule(delay, fn)
	table.insert(self.scheduled, { at = self.time + delay, fn = fn })
end

-- Las naciones que pierden celdas pierden también tropas (proporcional) y los jugadores reciben un aviso
function Engine:disasterVictims(victims, label)
	for id, lost in pairs(victims) do
		local tn = self.nations[id]
		if tn and lost > 0 then
			tn.troops *= math.max(0.5, 1 - lost / math.max(1, tn.cells + lost))
			if tn.userId then
				self:notify(tn.userId, label .. " destruyó parte de tu territorio")
			end
		end
	end
end

function Engine:startDisaster()
	local list = Engine.PLANET_DISASTERS[self.planetId] or Engine.PLANET_DISASTERS.EARTH
	local kind = list[self.rng:NextInteger(1, #list)]
	local info = Engine.DISASTER_INFO[kind]
	-- Objetivo: tierra habitada, para que el desastre importe
	local cell = nil
	for _ = 1, 40 do
		local c = self.rng:NextInteger(0, self.size - 1)
		if buffer.readu8(self.land, c) == 1 and buffer.readu8(self.owner, c) ~= 0 then
			cell = c
			break
		end
	end
	if not cell then
		return
	end
	local owner = self.nations[buffer.readu8(self.owner, cell)]
	local where = if owner then " cerca de " .. owner.name else ""
	self:notify(nil, string.format("⚠️ ¡Alerta! %s %s%s en 5 s", info.icon, info.name, where))
	self:fx("WARN", cell, info.radius)
	self:schedule(5, function()
		self:runDisaster(kind, cell)
	end)
end

function Engine:runDisaster(kind, cell)
	local info = Engine.DISASTER_INFO[kind]
	local nature = { id = 0 } -- la naturaleza no es una nación: nada es "suyo" y todo puede ser alcanzado
	local w, h = self.w, self.h
	local cx, cy = cell % w, cell // w
	local label = info.icon .. " " .. info.name

	if kind == "METEOR_SHOWER" then
		for k = 1, 5 do
			self:schedule((k - 1) * 0.5, function()
				local ix = (cx + self.rng:NextInteger(-14, 14)) % w
				local iy = math.clamp(cy + self.rng:NextInteger(-10, 10), 0, h - 1)
				local v = {}
				self:blast(nature, ix, iy, { radius = 4, destroy = 1.0 }, v)
				self:fx("METEOR", iy * w + ix, 4)
				self:disasterVictims(v, "☄️ Un meteorito")
			end)
		end
	elseif kind == "QUAKE" then
		local v = {}
		self:blast(nature, cx, cy, { radius = 12, destroy = 0.3, buildings = true }, v)
		self:fx("QUAKE", cell, 12)
		self:disasterVictims(v, label)
	elseif kind == "VOLCANO" then
		local v = {}
		self:blast(nature, cx, cy, { radius = 6, destroy = 1.0, buildings = true }, v)
		self:fx("VOLCANO", cell, 6)
		self:disasterVictims(v, label)
	elseif kind == "TORNADO" then
		-- El tornado recorre una línea: cada paso es un impacto pequeño y la animación lo sigue
		local dx, dy = self.rng:NextInteger(-3, 3), self.rng:NextInteger(-2, 2)
		if dx == 0 and dy == 0 then
			dx = 3
		end
		for k = 0, 7 do
			self:schedule(k * 0.45, function()
				local ix = (cx + dx * k) % w
				local iy = math.clamp(cy + dy * k, 0, h - 1)
				local v = {}
				self:blast(nature, ix, iy, { radius = 3, destroy = 0.6, buildings = true }, v)
				self:fx("TORNADO", iy * w + ix, 3)
				self:disasterVictims(v, label)
			end)
		end
	elseif kind == "SANDSTORM" then
		-- No quita territorio: las naciones dentro del área pierden el 12 % de sus tropas
		local r = info.radius
		local hit = {}
		for dy = -r, r, 2 do
			local y = cy + dy
			if y >= 0 and y < h then
				for dx = -r, r, 2 do
					if dx * dx + dy * dy <= r * r then
						local o = buffer.readu8(self.owner, y * w + ((cx + dx) % w))
						if o ~= 0 then
							hit[o] = true
						end
					end
				end
			end
		end
		for id in pairs(hit) do
			local tn = self.nations[id]
			if tn and tn.alive then
				tn.troops *= 0.88
				if tn.userId then
					self:notify(tn.userId, label .. " ha mermado tus tropas")
				end
			end
		end
		self:fx("SANDSTORM", cell, r)
	end
end

-- Efecto visual de un arma (lo recogen los clientes a través de WorldFx)
function Engine:fx(kind, cell, radius)
	table.insert(self.fxEvents, { kind = kind, cell = cell, r = radius })
end

-- Un impacto: las celdas enemigas del círculo pierden dueño (según def.destroy). Acumula las bajas en victims.
function Engine:blast(n, cx, cy, def, victims)
	local w, h = self.w, self.h
	local r = def.radius
	for dy = -r, r do
		local y = cy + dy
		if y >= 0 and y < h then
			for dx = -r, r do
				if dx * dx + dy * dy <= r * r then
					local j = y * w + ((cx + dx) % w)
					local o = buffer.readu8(self.owner, j)
					if
						buffer.readu8(self.land, j) == 1
						and o ~= 0
						and o ~= n.id
						and not self:isAlly(n, self.nations[o])
					then
						victims[o] = victims[o] or 0
						if def.destroy >= 1 or self.rng:NextNumber() < def.destroy then
							victims[o] += 1
							self:setOwner(j, 0)
						end
					end
				end
			end
		end
	end
	if def.buildings then
		local doomed = {}
		for cell, b in pairs(self.buildingAt) do
			local bx, by = cell % w, cell // w
			local dx = math.abs(bx - cx)
			dx = math.min(dx, w - dx)
			if b.owner ~= n.id and dx * dx + (by - cy) * (by - cy) <= r * r then
				doomed[#doomed + 1] = b
			end
		end
		for _, b in ipairs(doomed) do
			self:removeBuilding(b)
		end
	end
end

-- Lanza un arma de Engine.WEAPONS sobre una celda. Devuelve true, o false y el motivo.
function Engine:weapon(n, kind, cell)
	local def = Engine.WEAPONS[kind]
	if not def then
		return false, "Arma inválida"
	end
	if not n.alive then
		return false, "No estás en el mapa"
	end
	if self.phase ~= "BATTLE" and self.phase ~= "RUNNING" then
		return false, "Las armas se usan durante la guerra"
	end
	if buffer.readu8(self.land, cell) ~= 1 then
		return false, "Apunta a tierra firme"
	end
	local waitLeft = (n.weaponReady[kind] or 0) - self.time
	if waitLeft > 0 then
		return false, string.format("%s se recarga (%ds)", def.name, math.ceil(waitLeft))
	end
	if n.gold < def.cost then
		return false, string.format("Necesitas 💰%d de oro", def.cost)
	end
	n.gold -= def.cost
	n.weaponReady[kind] = self.time + def.cooldown

	local w, h = self.w, self.h
	local cx, cy = cell % w, cell // w
	local victims = {}
	for k = 1, def.impacts or 1 do
		local ix, iy = cx, cy
		if k > 1 then -- los impactos extra del racimo caen cerca del objetivo
			ix = (cx + self.rng:NextInteger(-8, 8)) % w
			iy = math.clamp(cy + self.rng:NextInteger(-8, 8), 0, h - 1)
		end
		self:blast(n, ix, iy, def, victims)
		self:fx(kind, iy * w + ix, def.radius)
	end

	for id, lost in pairs(victims) do
		local tn = self.nations[id]
		if lost > 0 then
			tn.troops *= math.max(0.4, 1 - lost / math.max(1, tn.cells + lost))
		end
		if def.troopHit then
			tn.troops *= 1 - def.troopHit
		end
		tn.attackedBy[n.id] = self.time
		if tn.userId then
			self:notify(tn.userId, string.format("%s ¡%s te atacó con %s!", def.icon, n.name, def.name))
		end
	end
	return true
end

-- ============================================================================
-- BOTS
-- ============================================================================
function Engine:botThink(n)
	BotAI.think(self, n)
end

-- ============================================================================
-- BUCLE PRINCIPAL
-- ============================================================================
function Engine:beginRunning()
	for _, n in ipairs(self.list) do
		if not n.isBot and not n.spawned then
			if self.mode == "COUNTRIES" then
				self:autoClaim(n)
			else
				self:autoSpawn(n, false)
				self:notify(n.userId, "📍 Capital asignada automáticamente")
			end
		end
	end
	self.phase = "BATTLE"
	self.battleStart = self.time -- los bots no atacan a jugadores humanos durante un periodo de gracia
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
					-- Eliminado por las tropas rivales: pierde y solo puede observar la partida
					n.eliminated = true
					self:notify(
						n.userId,
						"💀 Has sido eliminado. Ahora eres espectador: observa cómo termina la partida"
					)
				end
			else
				local maxT = self:maxTroops(n)
				local mult = if n.isBot then self.diff.growth else 1
				-- Curva de interés compuesto estilo Territorial.io / RoWorld:
				-- Acumular tropas produce interés porcentual; expandir territorio sube el ingreso base y el tope.
				local interest = n.troops * 0.038 * math.max(0, 1 - (n.troops / maxT))
				local baseGrowth = (15 + n.cells * 0.45 + n.cities * 25) * mult
				local g = (baseGrowth + interest) * math.max(0.1, 1 - (n.troops / (maxT * 1.05)))
				local troopsBefore = n.troops
				n.troops = math.min(maxT, n.troops + g)
				local goldGain = 2.0 + n.cells * 0.08 + n.cities * 5
				n.gold += goldGain
				-- Ritmos reales por segundo (el HUD los muestra tal cual; antes usaba una fórmula inventada)
				n.troopRate = n.troops - troopsBefore
				n.goldRate = goldGain

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

-- Celdas y humanos por continente (solo modo equipos)
function Engine:teamCells()
	local byTeam = {}
	for _, n in ipairs(self.list) do
		if n.continent then
			local t = byTeam[n.continent]
			if not t then
				t = { cells = 0, humans = 0 }
				byTeam[n.continent] = t
			end
			t.cells += n.cells
			if not n.isBot then
				t.humans += 1
			end
		end
	end
	return byTeam
end

local TEAM_WIN_RATIO = 0.55

function Engine:checkWin()
	if self.teamMode then
		for cont, t in pairs(self:teamCells()) do
			if t.cells >= self.landCount * TEAM_WIN_RATIO then
				self.phase = "ENDED"
				self.winnerTeam = cont
				self:notify(
					nil,
					string.format(
						"🏆 ¡El equipo del continente %d conquistó el %d%% del mundo!",
						cont,
						math.floor(t.cells / self.landCount * 100)
					)
				)
				return
			end
		end
		return
	end
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
	self.tickCount += 1
	self:runIntents()
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
			end
		end
	end

	-- Presupuesto de "pensadas" por tick (los escaneos del mapa son costosos); el cursor rota para ser justo
	local budget = 4
	local total = #self.list
	local cursor = self.thinkCursor or 0
	for k = 1, total do
		local n = self.list[((cursor + k - 1) % total) + 1]
		if n.alive and n.isBot and n.thinkTimer <= 0 then
			n.thinkTimer = self.diff.think * (0.7 + self.rng:NextNumber() * 0.6)
			self:botThink(n)
			budget -= 1
			if budget <= 0 then
				cursor = (cursor + k) % total
				break
			end
		end
	end
	self.thinkCursor = cursor

	-- Autojuego de los jugadores humanos (solo decide ataques; cada ~1,2 s)
	for _, n in ipairs(self.list) do
		if n.alive and not n.isBot and n.autoMode and n.autoMode ~= "OFF" then
			n.autoTimer -= dt
			if n.autoTimer <= 0 then
				n.autoTimer = 1.2
				BotAI.autoplay(self, n, n.autoMode, n.autoRatio)
			end
		end
	end

	-- Desastres naturales (cada 50-100 s en la fase de guerra) y acciones programadas
	if Engine.DISASTERS_ENABLED and (self.phase == "BATTLE" or self.phase == "RUNNING") then
		self.disasterTimer -= dt
		if self.disasterTimer <= 0 then
			self.disasterTimer = 50 + self.rng:NextNumber() * 50
			self:startDisaster()
		end
	end
	local sched = self.scheduled
	local si = 1
	while si <= #sched do
		if self.time >= sched[si].at then
			table.remove(sched, si).fn()
		else
			si += 1
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

-- Datos de una nación para el cliente (también se envían sueltos cuando entra un jugador a mitad de partida)
function Engine:rosterEntry(n)
	local c = n.color
	return {
		id = n.id,
		name = n.name,
		r = math.floor(c.R * 255 + 0.5),
		g = math.floor(c.G * 255 + 0.5),
		b = math.floor(c.B * 255 + 0.5),
		bot = n.isBot,
		persona = n.persona,
		countryId = n.countryId,
		continent = n.continent,
		capital = n.capital,
		cells = n.cells,
	}
end

function Engine:getRoster()
	local roster = {}
	for _, n in ipairs(self.list) do
		table.insert(roster, self:rosterEntry(n))
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
	-- El cliente solo muestra el top 7: con ~164 países vivos no hace falta enviar la lista completa
	for k = #top, 11, -1 do
		top[k] = nil
	end

	-- Países ya elegidos por jugadores (para la lista de selección del lobby)
	local taken = nil
	if self.mode == "COUNTRIES" then
		taken = {}
		for _, n in ipairs(self.list) do
			if not n.isBot and n.countryId then
				table.insert(taken, { cid = n.countryId, name = n.playerName or n.name, nid = n.id })
			end
		end
	end
	-- Ubicación de cada jugador humano (para marcar dónde se colocan los amigos durante la aparición)
	local players = {}
	for _, n in ipairs(self.list) do
		if not n.isBot and n.playerName then
			table.insert(players, { nid = n.id, name = n.playerName, capital = n.capital, alive = n.alive })
		end
	end
	-- Modo equipos: clasificación por continente
	local teams = nil
	if self.teamMode then
		local byTeam = self:teamCells()
		teams = {}
		for cont, t in pairs(byTeam) do
			table.insert(teams, {
				id = cont,
				cells = t.cells,
				pct = if self.landCount > 0 then t.cells / self.landCount * 100 else 0,
				humans = t.humans,
			})
		end
		table.sort(teams, function(a, b)
			return a.cells > b.cells
		end)
	end
	for _, p in ipairs(players) do
		local pn = self.nations[p.nid]
		p.team = pn and pn.continent
	end
	-- Frentes activos entre naciones (ataque a otra nación): el cliente dibuja flechas con las tropas y chispas
	local fronts = {}
	for _, n in ipairs(self.list) do
		if n.alive then
			for _, atk in ipairs(n.attacks) do
				local first = atk.queue[1]
				if atk.target ~= 0 and first and atk.troops >= 50 then
					table.insert(fronts, { a = n.id, t = atk.target, k = math.floor(atk.troops), c = first })
				end
			end
		end
	end
	table.sort(fronts, function(x, y)
		return x.k > y.k
	end)
	for k = #fronts, 25, -1 do
		fronts[k] = nil
	end
	return {
		fronts = fronts,
		mode = self.mode,
		teamMode = self.teamMode,
		teams = teams,
		winnerTeam = self.winnerTeam,
		taken = taken,
		humans = players, -- no se llama "players": WorldServer ya usa ese campo para el número de jugadores del servidor
		phase = self.phase,
		spawnTotal = SPAWN_SECONDS,
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
	-- Segundos que faltan para que cada arma vuelva a estar lista (solo las que se están recargando)
	local weapons = {}
	for kind, readyAt in pairs(n.weaponReady) do
		local left = readyAt - self.time
		if left > 0 then
			weapons[kind] = left
		end
	end
	return {
		id = n.id,
		weapons = weapons,
		troops = math.floor(n.troops),
		maxTroops = self:maxTroops(n),
		gold = math.floor(n.gold),
		troopRate = n.troopRate or 0,
		goldRate = n.goldRate or 0,
		autoMode = n.autoMode or "OFF",
		cities = n.cities,
		cells = n.cells,
		alive = n.alive,
		eliminated = n.eliminated == true,
		spawned = n.spawned,
		capital = n.capital,
		defenseAI = n.defenseAI,
		attacks = attacks,
		buildings = buildings,
	}
end

return Engine
