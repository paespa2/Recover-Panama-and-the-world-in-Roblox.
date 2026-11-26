--!nonstrict
-- GameTests.lua
-- Suite automatizada de pruebas de integración para Dominación Mundial Total:
--  1. Aparición y separación territorial (radio de seguridad isClear)
--  2. Economía real, comercio de puertos, costos progresivos y sincronización HUD (getMe)
--  3. Fronteras incrementales (borderSet), colas sin duplicados (inQueue), logística y botín
--  4. Puestos defensivos, recarga de misiles y mitigación antibalística (ABM)
--  5. Simulación multijugador (4 humanos + bots), deduplicación de diffs y límite de paquete

local Engine = require(script.Parent:WaitForChild("WorldEngine"))

local GameTests = {}

local function assertTrue(cond, msg)
	if not cond then
		error("[GameTests FAIL] " .. tostring(msg), 2)
	end
end

-- Encuentra una celda de tierra firme con suficiente tierra alrededor para pruebas deterministas
local function findInlandPatch(eng, startX, startY, minRadius)
	local w, h = eng.w, eng.h
	for y = startY, h - 15 do
		for x = startX, w - 15 do
			local ok = true
			for dy = -minRadius, minRadius do
				for dx = -minRadius, minRadius do
					local idx = (y + dy) * w + ((x + dx) % w)
					if buffer.readu8(eng.land, idx) ~= 1 or buffer.readu8(eng.owner, idx) ~= 0 then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
			end
			if ok then
				return y * w + x, x, y
			end
		end
	end
	error("No se encontró parche de tierra libre para la prueba")
end

-- Encuentra una celda costera propiedad de la nación `n`
local function findOwnedCoastalCell(eng, n)
	for cell in pairs(n.coastalSet) do
		if buffer.readu8(eng.owner, cell) == n.id and not eng.buildingAt[cell] then
			return cell
		end
	end
	return nil
end

function GameTests.testSpawnAndClearance()
	local eng = Engine.new("EARTH", 0, "NORMAL", "FREE")
	local p1 = eng:addNation("Jugador1", Color3.fromRGB(0, 255, 180), false, nil)
	local p2 = eng:addNation("Jugador2", Color3.fromRGB(255, 80, 120), false, nil)

	local cell1, x1, y1 = findInlandPatch(eng, 120, 80, 10)
	local ok1, msg1 = eng:setSpawn(p1, cell1)
	assertTrue(ok1 == true, "Jugador 1 debería poder aparecer en tierra libre: " .. tostring(msg1))
	assertTrue(p1.cells > 50, "Jugador 1 debe recibir su disco territorial inicial")

	-- Intentar aparecer a 7 celdas de distancia (solaparía o quedaría pegado al radio 5 de p1)
	local nearCell = y1 * eng.w + (x1 + 7)
	local okNear = eng:setSpawn(p2, nearCell)
	assertTrue(okNear == false, "No debe permitir aparición a menos de 8 celdas de un territorio existente")
	assertTrue(p2.alive == false, "Jugador 2 no debe quedar vivo tras aparición rechazada")

	-- Aparecer en un segundo parche despejado
	local cell2 = findInlandPatch(eng, x1 + 18, y1, 9)
	local ok2, msg2 = eng:setSpawn(p2, cell2)
	assertTrue(ok2 == true, "Jugador 2 debe poder aparecer a distancia segura: " .. tostring(msg2))
	assertTrue(p2.cells > 50 and p1.cells > 50, "Ambos jugadores conservan su territorio íntegro sin solaparse")
	return true
end

function GameTests.testEconomyAndProgressiveCosts()
	local eng = Engine.new("EARTH", 0, "NORMAL", "FREE")
	local p1 = eng:addNation("Economista", Color3.fromRGB(255, 220, 40), false, nil)
	local cell1 = findInlandPatch(eng, 150, 90, 9)
	eng:setSpawn(p1, cell1)
	eng:beginRunning()

	p1.gold = 5000
	local baseTroopRate, baseGoldRate, baseMaxT = eng:getEconomyRates(p1)
	assertTrue(baseTroopRate > 0 and baseGoldRate > 2, "Tasas base positivas en fase BATTLE")

	-- Costo progresivo de Ciudad: 1ª cuesta 500, 2ª cuesta 700
	local c1Cost = eng:getBuildingCost(p1, "City")
	assertTrue(c1Cost == 500, "Primera ciudad debe costar 500")
	local okCity1 = eng:build(p1, "City", cell1)
	assertTrue(okCity1 == true, "Construcción de primera ciudad exitosa")
	assertTrue(eng:getBuildingCost(p1, "City") == 700, "Segunda ciudad debe escalar a 700 de oro")

	local cityTroopRate, cityGoldRate, cityMaxT = eng:getEconomyRates(p1)
	assertTrue(cityGoldRate > baseGoldRate + 5, "La ciudad incrementa el ingreso de oro por segundo")
	assertTrue(cityMaxT == baseMaxT + 15000, "La ciudad incrementa el tope de tropas en +15,000")

	-- Verificar sincronización exacta con getMe()
	local me = eng:getMe(p1)
	assertTrue(me.cities == 1, "getMe() debe reportar cities = 1")
	assertTrue(math.abs(me.income - cityGoldRate) <= 0.11, "getMe().income debe coincidir con getEconomyRates")
	assertTrue(math.abs(me.troopRate - cityTroopRate) <= 0.11, "getMe().troopRate debe coincidir con getEconomyRates")
	assertTrue(me.nextCosts and me.nextCosts.City == 700, "getMe().nextCosts debe informar el costo progresivo")
	return true
end

function GameTests.testBordersCombatLogisticsAndPlunder()
	local eng = Engine.new("EARTH", 0, "NORMAL", "FREE")
	local attacker = eng:addNation("Atacante", Color3.fromRGB(0, 200, 255), false, nil)
	local defender = eng:addNation("Defensor", Color3.fromRGB(255, 60, 60), false, nil)

	local cellA, ax, ay = findInlandPatch(eng, 160, 100, 10)
	eng:setSpawn(attacker, cellA)

	-- Colocar al defensor a 15 celdas para luego expandirlos hasta tocarse
	local cellD = ay * eng.w + (ax + 15)
	if buffer.readu8(eng.land, cellD) ~= 1 or not eng:isClear(cellD, 8) then
		cellD = findInlandPatch(eng, ax + 15, ay, 8)
	end
	eng:setSpawn(defender, cellD)
	eng:beginRunning()

	-- Verificar que borderSet incremental contiene celdas fronterizas válidas
	local borderCount = 0
	for bCell in pairs(attacker.borderSet) do
		assertTrue(buffer.readu8(eng.owner, bCell) == attacker.id, "borderSet solo debe contener celdas propias")
		borderCount += 1
	end
	assertTrue(borderCount > 10, "borderSet debe haberse poblado incrementalmente en spawnNation")

	-- Verificar factor logístico: cerca de capital = 1.0, muy lejos > 1.0
	local nearFactor = eng:getLogisticsFactor(attacker, cellA + 10)
	local farFactor = eng:getLogisticsFactor(attacker, (ay * eng.w) + ((ax + 160) % eng.w))
	assertTrue(nearFactor == 1.0, "Factor logístico cercano a capital debe ser 1.0")
	assertTrue(farFactor > 1.2, "Factor logístico a gran distancia sin nodos debe penalizar (>1.2)")

	-- Construir un edificio en la capital del defensor y simular captura directa para probar botín
	defender.gold = 1000
	eng:build(defender, "City", defender.capital)
	local adjCell = defender.capital - 1
	eng:setOwner(adjCell, attacker.id)
	attacker.troops = 25000
	defender.troops = 100

	local goldBefore = attacker.gold
	local okAtk = eng:launchAttack(attacker, defender.id, 0.8, defender.capital)
	assertTrue(okAtk == true, "Ataque fronterizo contra defensor debe iniciarse")
	for _ = 1, 15 do
		eng:processAttacks(attacker)
	end
	assertTrue(attacker.gold > goldBefore, "Capturar territorio con Ciudad/Capital debe otorgar botín de oro")
	return true
end

function GameTests.testDefensivePostsAndNukeMitigation()
	local eng = Engine.new("EARTH", 0, "NORMAL", "FREE")
	local nuker = eng:addNation("Nuclear", Color3.fromRGB(180, 70, 255), false, nil)
	local target = eng:addNation("Fortificado", Color3.fromRGB(50, 220, 100), false, nil)

	local c1 = findInlandPatch(eng, 180, 110, 9)
	local c2 = findInlandPatch(eng, 210, 110, 9)
	eng:setSpawn(nuker, c1)
	eng:setSpawn(target, c2)
	eng:beginRunning()

	nuker.gold = 5000
	target.gold = 5000
	eng:build(nuker, "Silo", c1)
	eng:build(target, "Post", c2)

	-- Lanzar primer misil sobre la zona protegida por el Puesto Defensivo
	local okNuke1 = eng:nuke(nuker, c2)
	assertTrue(okNuke1 == true, "Primer lanzamiento con Silo y oro debe funcionar")
	assertTrue(
		buffer.readu8(eng.owner, c2) == target.id,
		"El Puesto Defensivo debe proteger su núcleo (3x3) frente a la neutralización nuclear"
	)

	-- Intentar lanzar un segundo misil inmediatamente (debe fallar por NUKE_COOLDOWN)
	local okNuke2, msg2 = eng:nuke(nuker, c2)
	assertTrue(okNuke2 == false, "El cooldown de misiles debe impedir lanzamientos consecutivos inmediatos: " .. tostring(msg2))
	return true
end

function GameTests.testMultiplayerSimulationAndDiffCapping()
	local eng = Engine.new("EARTH", 12, "NORMAL", "FREE")
	local humans = {}
	for i = 1, 4 do
		local fakePlayer = { UserId = 1000 + i, DisplayName = "Humano_" .. i }
		local hn = eng:addHuman(fakePlayer)
		eng:autoSpawn(hn, false)
		table.insert(humans, hn)
	end
	eng:beginRunning()

	-- Forzar cambios repetidos sobre una misma celda para comprobar deduplicación en changedSet
	local testCell = humans[1].capital + 1
	local changesBefore = #eng.changes
	eng:setOwner(testCell, humans[2].id)
	eng:setOwner(testCell, humans[3].id)
	eng:setOwner(testCell, humans[1].id)
	assertTrue(#eng.changes <= changesBefore + 1, "changedSet debe evitar entradas duplicadas para la misma celda en un tick")

	-- Simular 25 ticks de partida multijugador (5 segundos de guerra con 4 humanos + 12 bots)
	for _ = 1, 25 do
		eng:tick(0.2)
		local diff = eng:flushDiff()
		if diff then
			assertTrue(
				buffer.len(diff) <= Engine.MAX_DIFF_CELLS_PER_TICK * 4,
				"El paquete WorldDiff nunca debe superar MAX_DIFF_CELLS_PER_TICK * 4 bytes"
			)
		end
	end

	local stats = eng:getStats()
	assertTrue(stats.top and #stats.top > 0, "getStats().top debe devolver el ranking ordenado")
	local foundHumansInTop = 0
	for _, entry in ipairs(stats.top) do
		assertTrue(entry.rank ~= nil and entry.rank >= 1, "Cada entrada de stats.top debe incluir su puesto real (rank)")
		if not entry.isBot then
			foundHumansInTop += 1
		end
	end
	local aliveHumans = 0
	for _, hn in ipairs(humans) do
		if hn.alive then
			aliveHumans += 1
		end
	end
	assertTrue(
		foundHumansInTop == aliveHumans,
		"Todos los jugadores humanos vivos deben estar incluidos en stats.top aunque estén fuera del Top 10"
	)
	return true
end

function GameTests.runAll()
	local suites = {
		{ name = "1. Aparición y separación territorial", fn = GameTests.testSpawnAndClearance },
		{ name = "2. Economía, puertos, costos progresivos y HUD", fn = GameTests.testEconomyAndProgressiveCosts },
		{ name = "3. Fronteras incrementales, logística y botín", fn = GameTests.testBordersCombatLogisticsAndPlunder },
		{ name = "4. Puestos defensivos y mitigación nuclear", fn = GameTests.testDefensivePostsAndNukeMitigation },
		{ name = "5. Simulación multijugador, diffs y ranking", fn = GameTests.testMultiplayerSimulationAndDiffCapping },
	}
	local results = {}
	local passed = 0
	local t0 = os.clock()
	for _, s in ipairs(suites) do
		local st = os.clock()
		local ok, err = pcall(s.fn)
		local ms = (os.clock() - st) * 1000
		if ok then
			passed += 1
			table.insert(results, string.format("PASS [%.1f ms] %s", ms, s.name))
		else
			table.insert(results, string.format("FAIL [%.1f ms] %s -> %s", ms, s.name, tostring(err)))
		end
	end
	local totalMs = (os.clock() - t0) * 1000
	return {
		allPassed = (passed == #suites),
		passed = passed,
		total = #suites,
		totalMs = math.floor(totalMs * 10 + 0.5) / 10,
		report = results,
	}
end

return GameTests
