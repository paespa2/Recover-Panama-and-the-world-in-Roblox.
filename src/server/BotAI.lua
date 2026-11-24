--!nonstrict
-- BotAI.lua
-- IA de las naciones bot. Cada bot tiene una PERSONALIDAD que cambia cómo expande, construye,
-- ataca, desembarca y lanza misiles. Además:
--  * Coalición: si una nación domina >=35% del mapa, todos los bots se vuelcan contra ella.
--  * Rencor: los bots recuerdan a quien los atacó y devuelven el golpe.
--  * Economía: construyen Ciudades, Puertos, Puestos defensivos y Silos según su personalidad.
--  * Rendimiento: el escaneo del mapa usa muestreo adaptativo (stride) en naciones grandes.
-- Este módulo NO requiere WorldEngine (recibe el motor como argumento) para evitar dependencias circulares.

local BotAI = {}

-- Campos de cada personalidad:
--  aggression  peso de atacar enemigos frente a expandirse en tierra libre
--  weak        cuánto pesa que el vecino sea débil (oportunismo)
--  spite       peso del rencor
--  cautious    multiplica el margen de seguridad de la dificultad (menor = más audaz)
--  ratioMul    multiplica el % de tropas enviado por ataque
--  reserve     fracción del tope de tropas que no se arriesga contra enemigos
--  extraAttacks ataques simultáneos extra
--  cityBase/cityPer  ciudades objetivo = cityBase + celdas // cityPer
--  ports/posts       cantidad objetivo de Puertos / Puestos defensivos
--  silo/nuke         construye Silo y lanza misiles
--  spearhead   dirige el ataque hacia la capital enemiga
BotAI.PERSONAS = {
	CONQUEROR = {
		name = "Conquistador",
		icon = "⚔️",
		aggression = 1.4,
		weak = 1.0,
		spite = 1.0,
		cautious = 0.8,
		ratioMul = 1.3,
		reserve = 0.15,
		extraAttacks = 1,
		cityBase = 1,
		cityPer = 500,
		ports = 1,
		posts = 0,
		silo = false,
		nuke = false,
		spearhead = true,
	},
	MERCHANT = {
		name = "Mercader",
		icon = "💰",
		aggression = 0.6,
		weak = 1.2,
		spite = 0.8,
		cautious = 1.2,
		ratioMul = 0.8,
		reserve = 0.30,
		extraAttacks = 0,
		cityBase = 2,
		cityPer = 250,
		ports = 2,
		posts = 1,
		silo = false,
		nuke = false,
		spearhead = false,
	},
	TURTLE = {
		name = "Defensor",
		icon = "🛡️",
		aggression = 0.3,
		weak = 1.0,
		spite = 1.5,
		cautious = 1.5,
		ratioMul = 0.7,
		reserve = 0.40,
		extraAttacks = 0,
		cityBase = 1,
		cityPer = 400,
		ports = 0,
		posts = 4,
		silo = false,
		nuke = false,
		spearhead = false,
	},
	OPPORTUNIST = {
		name = "Oportunista",
		icon = "🦊",
		aggression = 1.0,
		weak = 2.0,
		spite = 0.6,
		cautious = 1.0,
		ratioMul = 1.0,
		reserve = 0.20,
		extraAttacks = 1,
		cityBase = 1,
		cityPer = 450,
		ports = 1,
		posts = 1,
		silo = false,
		nuke = false,
		spearhead = true,
	},
	ADMIRAL = {
		name = "Navegante",
		icon = "⚓",
		aggression = 0.9,
		weak = 1.1,
		spite = 0.9,
		cautious = 1.0,
		ratioMul = 1.0,
		reserve = 0.20,
		extraAttacks = 0,
		cityBase = 1,
		cityPer = 400,
		ports = 3,
		posts = 0,
		silo = false,
		nuke = false,
		spearhead = false,
	},
	NUKER = {
		name = "Estratega Nuclear",
		icon = "☢️",
		aggression = 0.8,
		weak = 1.0,
		spite = 1.2,
		cautious = 1.1,
		ratioMul = 0.9,
		reserve = 0.25,
		extraAttacks = 0,
		cityBase = 2,
		cityPer = 300,
		ports = 1,
		posts = 1,
		silo = true,
		nuke = true,
		spearhead = false,
	},
}

-- Personalidad "de carácter" para figuras históricas conocidas; el resto se sortea.
local NAMED = {
	["Gengis Kan"] = "CONQUEROR",
	["Atila"] = "CONQUEROR",
	["Napoleón"] = "CONQUEROR",
	["Alejandro Magno"] = "CONQUEROR",
	["Julio César"] = "CONQUEROR",
	["Shaka Zulú"] = "CONQUEROR",
	["Tamerlán"] = "CONQUEROR",
	["Aníbal"] = "OPPORTUNIST",
	["Pablo Escobar"] = "OPPORTUNIST",
	["Bismarck"] = "OPPORTUNIST",
	["Trump"] = "MERCHANT",
	["Donald Trump"] = "MERCHANT",
	["Marco Polo"] = "MERCHANT",
	["Da Vinci"] = "MERCHANT",
	["Leonidas"] = "TURTLE",
	["Churchill"] = "TURTLE",
	["Gandhi"] = "TURTLE",
	["Mandela"] = "TURTLE",
	["Qin Shi Huang"] = "TURTLE",
	["Colón"] = "ADMIRAL",
	["Magallanes"] = "ADMIRAL",
	["Reino Unido"] = "ADMIRAL",
	["Nikola Tesla"] = "NUKER",
	["Einstein"] = "NUKER",
	["Isaac Newton"] = "NUKER",
	["Marie Curie"] = "NUKER",
}

local WEIGHTED = {
	"CONQUEROR",
	"CONQUEROR",
	"MERCHANT",
	"MERCHANT",
	"TURTLE",
	"OPPORTUNIST",
	"OPPORTUNIST",
	"ADMIRAL",
	"NUKER",
}

local GRUDGE_SECONDS = 30
local NUKE_COOLDOWN = 40
local COALITION_SHARE = 0.35

function BotAI.assign(rng, name)
	local key = NAMED[name]
	if key then
		return key
	end
	return WEIGHTED[rng:NextInteger(1, #WEIGHTED)]
end

-- ============================================================================
-- ESCANEO DEL MAPA
-- ============================================================================
local function reservoir(list, seen, value, cap, rng)
	if #list < cap then
		list[#list + 1] = value
	else
		local k = rng:NextInteger(1, seen)
		if k <= cap then
			list[k] = value
		end
	end
end

-- Recorre las celdas propias (con muestreo si la nación es grande) y devuelve:
--  counts[id]       contacto fronterizo con cada vecino (0 = tierra libre)
--  enemyCells[id]   muestra de celdas enemigas junto a nuestra frontera
--  border/coast/interior/samples  muestras de celdas propias
local function scan(engine, n, stride)
	local owner, land = engine.owner, engine.land
	local nb = engine._nb
	local rng = engine.rng
	local counts = {}
	local enemyCells = {}
	local enemySeen = {}
	local border, coast, interior, samples = {}, {}, {}, {}
	local nBorder, nCoast, nInterior, nSamples = 0, 0, 0, 0
	local id = n.id
	local start = if stride > 1 then rng:NextInteger(0, stride - 1) else 0
	local w, h = engine.w, engine.h
	-- Solo se recorre la caja envolvente de la nación (mucho más barato con muchos bots pequeños)
	local x0, x1 = n.bx0 or 0, n.bx1 or (w - 1)
	local y0, y1 = n.by0 or 0, n.by1 or (h - 1)

	for y = y0, y1 do
		for x = x0 + (y + start) % stride, x1, stride do
			local i = y * w + x
			if buffer.readu8(owner, i) == id then
				local cnt = engine:neighbors(i, nb)
				local isBorder, isCoast = false, false
				for q = 1, cnt do
					local j = nb[q]
					if buffer.readu8(land, j) == 1 then
						local o = buffer.readu8(owner, j)
						if o ~= id and not engine:isAlly(n, engine.nations[o]) then
							isBorder = true
							counts[o] = (counts[o] or 0) + 1
							local list = enemyCells[o]
							if not list then
								list = {}
								enemyCells[o] = list
								enemySeen[o] = 0
							end
							enemySeen[o] += 1
							reservoir(list, enemySeen[o], j, 6, rng)
						end
					else
						isCoast = true
					end
				end
				nSamples += 1
				reservoir(samples, nSamples, i, 12, rng)
				if isBorder then
					nBorder += 1
					reservoir(border, nBorder, i, 8, rng)
				end
				if isCoast then
					nCoast += 1
					reservoir(coast, nCoast, i, 8, rng)
				end
				if not isBorder and not isCoast then
					nInterior += 1
					reservoir(interior, nInterior, i, 8, rng)
				end
			end
		end
	end

	return {
		counts = counts,
		enemyCells = enemyCells,
		border = border,
		coast = coast,
		interior = interior,
		samples = samples,
	}
end

local function hasKind(n, kind)
	for _, b in ipairs(n.buildings) do
		if b.kind == kind then
			return true
		end
	end
	return false
end

local function pick(list, rng)
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- ============================================================================
-- ECONOMÍA / CONSTRUCCIÓN (máximo 1 edificio por "pensada")
-- ============================================================================
local function tryBuild(engine, n, info, p)
	local costs = engine.COSTS
	local rng = engine.rng

	local cityTarget = p.cityBase + n.cells // p.cityPer
	if n.cities < cityTarget and n.gold >= costs.City then
		local cell = pick(info.interior, rng) or pick(info.samples, rng)
		if cell and engine:build(n, "City", cell) then
			return
		end
	end

	if #n.ports < p.ports and n.gold >= costs.Port then
		local cell = pick(info.coast, rng)
		if cell and engine:build(n, "Port", cell) then
			return
		end
	end

	if #n.posts < p.posts and n.gold >= costs.Post then
		local cell = pick(info.border, rng)
		if cell and engine:build(n, "Post", cell) then
			return
		end
	end

	if p.silo and n.cities >= 2 and not hasKind(n, "Silo") and n.gold >= costs.Silo then
		local cell = pick(info.interior, rng) or pick(info.samples, rng)
		if cell then
			engine:build(n, "Silo", cell)
		end
	end
end

-- ============================================================================
-- MISILES
-- ============================================================================
local function tryNuke(engine, n, info, p, leaderId, leaderShare)
	if not p.nuke or n.gold < engine.NUKE_COST then
		return
	end
	if engine.time - (n.lastNuke or -999) < NUKE_COOLDOWN then
		return
	end
	if not hasKind(n, "Silo") then
		return
	end

	local targetId = nil
	if leaderId and leaderId ~= n.id and leaderShare >= 0.25 then
		targetId = leaderId
	else
		local newest = -math.huge
		for id, t in pairs(n.attackedBy) do
			local en = engine.nations[id]
			if en and en.alive and engine.time - t < 20 and t > newest then
				newest = t
				targetId = id
			end
		end
	end
	if not targetId then
		return
	end
	local en = engine.nations[targetId]
	if not en or not en.alive then
		return
	end

	local cell = nil
	if en.capital and buffer.readu8(engine.owner, en.capital) == en.id then
		cell = en.capital
	else
		local list = info.enemyCells[targetId]
		cell = list and pick(list, engine.rng)
	end
	if cell and engine:nuke(n, cell) then
		n.lastNuke = engine.time
	end
end

-- ============================================================================
-- ARMAS BÉLICAS (además del misil nuclear): cada personalidad tiene las suyas
-- ============================================================================
local WEAPONS_BY_PERSONA = {
	CONQUEROR = { "BOMB", "ARTILLERY" },
	OPPORTUNIST = { "ARTILLERY", "BOMB" },
	TURTLE = { "ARTILLERY" },
	ADMIRAL = { "BOMB" },
	NUKER = { "METEOR", "QUAKE" },
	MERCHANT = {},
}

-- Ataca con un arma a quien acaba de atacar al bot o, si nadie, al líder; solo a vecinos con frontera
local function tryWeapon(engine, n, info, key, leaderId, leaderShare)
	local list = WEAPONS_BY_PERSONA[key]
	if not list or #list == 0 or engine.rng:NextNumber() > 0.35 then
		return
	end
	local targetId = nil
	local newest = -math.huge
	for id, t in pairs(n.attackedBy) do
		local en = engine.nations[id]
		if en and en.alive and engine.time - t < 20 and t > newest and info.enemyCells[id] then
			newest = t
			targetId = id
		end
	end
	if not targetId and leaderId and leaderId ~= n.id and leaderShare >= 0.2 and info.enemyCells[leaderId] then
		targetId = leaderId
	end
	if not targetId then
		return
	end
	local kind = list[engine.rng:NextInteger(1, #list)]
	local def = engine.WEAPONS[kind]
	-- Se reserva oro para construir: las armas solo gastan el excedente
	if not def or n.gold < def.cost + 300 then
		return
	end
	local cell = pick(info.enemyCells[targetId], engine.rng)
	if cell then
		engine:weapon(n, kind, cell)
	end
end

-- ============================================================================
-- DESEMBARCOS
-- ============================================================================
local function tryLanding(engine, n, info, naval)
	local samples = if #info.coast > 0 then info.coast else info.samples
	if #samples == 0 then
		return
	end
	local rng = engine.rng
	local w, h = engine.w, engine.h
	local minD, maxD = 6, 22
	if naval then
		minD, maxD = 10, 40
	end
	for _ = 1, 10 do
		local c = samples[rng:NextInteger(1, #samples)]
		local cx, cy = c % w, c // w
		local angle = rng:NextNumber() * math.pi * 2
		local dist = minD + rng:NextNumber() * (maxD - minD)
		local tx = (cx + math.floor(math.cos(angle) * dist)) % w
		local ty = cy + math.floor(math.sin(angle) * dist)
		if ty >= 1 and ty < h - 1 then
			local j = ty * w + tx
			if buffer.readu8(engine.land, j) == 1 then
				local o = buffer.readu8(engine.owner, j)
				local okTarget = (o == 0)
				if naval and o ~= 0 and o ~= n.id then
					local en = engine.nations[o]
					okTarget = en ~= nil and en.alive and en.troops < n.troops * 0.7
				end
				if okTarget then
					if engine:landing(n, j, if naval then 600 else 350) then
						return
					end
				end
			end
		end
	end
end

-- ============================================================================
-- DECISIÓN PRINCIPAL
-- ============================================================================
function BotAI.think(engine, n)
	if not n.alive then
		return
	end
	local d = engine.diff
	local rng = engine.rng
	local key = n.persona
	if not key or not BotAI.PERSONAS[key] then
		key = BotAI.assign(rng, n.name)
		n.persona = key
	end
	local p = BotAI.PERSONAS[key]
	local now = engine.time

	local maxAttacks = d.maxAttacks + p.extraAttacks
	local busy = n.troops < 250 or #n.attacks >= maxAttacks
	-- Evita escanear el mapa si no hay nada que decidir
	if busy and n.gold < engine.COSTS.Post then
		return
	end

	local stride = math.clamp(n.cells // 250, 1, 6)
	local info = scan(engine, n, stride)

	-- Líder actual (para coalición y misiles)
	local leaderId, leaderShare = nil, 0
	for _, o in ipairs(engine.list) do
		if o.alive and engine.landCount > 0 then
			local share = o.cells / engine.landCount
			if share > leaderShare then
				leaderShare = share
				leaderId = o.id
			end
		end
	end

	tryBuild(engine, n, info, p)
	tryNuke(engine, n, info, p, leaderId, leaderShare)
	tryWeapon(engine, n, info, key, leaderId, leaderShare)

	if busy then
		return
	end

	local counts = info.counts
	local totalContact = 0
	for id, c in pairs(counts) do
		if id ~= 0 then
			totalContact += c
		end
	end

	-- Mejor objetivo enemigo
	local bestId, bestScore = nil, -math.huge
	for id, c in pairs(counts) do
		if id ~= 0 then
			local en = engine.nations[id]
			if en and en.alive then
				local ratio = n.troops / math.max(100, en.troops)
				local grudgeT = n.attackedBy[id]
				local grudge = grudgeT ~= nil and (now - grudgeT) < GRUDGE_SECONDS
				local isLeader = id == leaderId and leaderShare >= COALITION_SHARE and leaderId ~= n.id
				local safe = ratio >= d.edge * p.cautious
				if safe or isLeader or (grudge and ratio > 0.9) then
					local score = p.aggression * (0.4 + p.weak * math.clamp(ratio - 0.8, -0.5, 3))
					if grudge then
						score += 1.5 * p.spite
					end
					if isLeader then
						score += 1.5
					end
					score += 0.6 * c / math.max(1, totalContact)
					score += rng:NextNumber() * 0.4
					if score > bestScore then
						bestScore = score
						bestId = id
					end
				end
			end
		end
	end

	local neutralScore = -math.huge
	if (counts[0] or 0) > 0 then
		neutralScore = 1.4 + rng:NextNumber() * 0.6 - (p.aggression - 1) * 0.3
	end

	local reserveOk = n.troops >= engine:maxTroops(n) * p.reserve * 0.5
	local target, targetCell = nil, nil
	if bestId and reserveOk and bestScore > 0.9 and bestScore > neutralScore then
		target = bestId
		if p.spearhead then
			local en = engine.nations[bestId]
			if en and en.capital and buffer.readu8(engine.owner, en.capital) == en.id then
				targetCell = en.capital
			end
		end
	elseif neutralScore > -math.huge then
		target = 0
	end

	if target ~= nil then
		local ratio = (d.minRatio + (d.maxRatio - d.minRatio) * rng:NextNumber()) * p.ratioMul
		engine:launchAttack(n, target, math.clamp(ratio, 0.1, 0.85), targetCell)
		return
	end

	-- Sin vecinos terrestres (isla) o bot naval con puerto: desembarcar
	local isolated = next(counts) == nil
	if isolated and n.troops > 700 then
		tryLanding(engine, n, info, false)
	elseif p.ports > 0 and #n.ports > 0 and n.troops > 1500 and rng:NextNumber() < 0.35 then
		tryLanding(engine, n, info, true)
	end
end

-- ============================================================================
-- AUTOJUEGO PARA JUGADORES HUMANOS
-- Solo decide a quién atacar: nunca construye, ni gasta oro, ni lanza misiles (eso lo decide el jugador).
--   EXPAND   : se expande por la tierra libre vecina.
--   CONQUER  : como EXPAND y, cuando no queda tierra libre, ataca al vecino más débil que pueda vencer.
-- ============================================================================
function BotAI.autoplay(engine, n, mode, ratio)
	if not n.alive or n.troops < 250 or #n.attacks >= 2 then
		return
	end
	local info = scan(engine, n, math.clamp(n.cells // 250, 1, 6))
	local counts = info.counts
	if (counts[0] or 0) > 0 then
		engine:launchAttack(n, 0, ratio)
		return
	end
	if mode ~= "CONQUER" then
		return
	end
	local bestId, bestTroops = nil, math.huge
	for id in pairs(counts) do
		if id ~= 0 then
			local en = engine.nations[id]
			-- Solo ataca si tiene ventaja clara: así el autojuego no malgasta las tropas del jugador
			if en and en.alive and n.troops > en.troops * 1.3 and en.troops < bestTroops then
				bestId, bestTroops = id, en.troops
			end
		end
	end
	if bestId then
		engine:launchAttack(n, bestId, ratio)
	end
end

return BotAI
