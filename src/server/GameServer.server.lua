--!strict
-- GameServer.server.lua
-- Motor principal del servidor para "Recuperar Panamá y el Mundo" (2D Pixel Conquest)
-- Gestiona el estado de las provincias, economía, órdenes del jugador (construcción + expansión + Dedo Divino)
-- y coordina la IA de Defensa Territorial.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MapData = require(Shared:WaitForChild("MapData"))
local DefenseAI = require(script.Parent:WaitForChild("DefenseAI"))

-- Creación de RemoteEvents para sincronización en tiempo real con la interfaz 2D Pixel
local RemotesFolder = Instance.new("Folder")
RemotesFolder.Name = "ConquestRemotes"
RemotesFolder.Parent = ReplicatedStorage

local StateSyncEvent = Instance.new("RemoteEvent")
StateSyncEvent.Name = "StateSyncEvent"
StateSyncEvent.Parent = RemotesFolder

local PlayerCommandEvent = Instance.new("RemoteEvent")
PlayerCommandEvent.Name = "PlayerCommandEvent"
PlayerCommandEvent.Parent = RemotesFolder

local CombatFxEvent = Instance.new("RemoteEvent")
CombatFxEvent.Name = "CombatFxEvent"
CombatFxEvent.Parent = RemotesFolder

-- Estado de la partida activa
local currentMapId: string = GameConfig.MAP_MODES.PANAMA
local playerFaction: string = "PANAMA"
local regions: { [string]: DefenseAI.RegionState } = {}
local economies: { [string]: DefenseAI.NationEconomy } = {}
local battleLogs: { string } = {}
local matchVictoryFaction: string? = nil

local function pushLog(msg: string)
	table.insert(battleLogs, 1, msg)
	if #battleLogs > 8 then
		table.remove(battleLogs, #battleLogs)
	end
end

local function recalculateEconomies()
	-- Reiniciar acumuladores por segundo
	for _, econ in pairs(economies) do
		econ.goldPerSec = 10
		econ.oilPerSec = 2
		econ.manpowerPerSec = 8
		econ.popCap = 300
		econ.totalTroops = 0
		econ.regionCount = 0
	end

	for _, reg in pairs(regions) do
		local econ = economies[reg.owner]
		if not econ then
			econ = {
				factionId = reg.owner,
				gold = 220,
				oil = 40,
				goldPerSec = 10,
				oilPerSec = 2,
				manpowerPerSec = 8,
				popCap = 300,
				totalTroops = 0,
				regionCount = 0,
				aiDefenseMode = "SMART",
				isPlayer = (reg.owner == playerFaction),
			}
			economies[reg.owner] = econ
		end

		econ.regionCount += 1
		econ.totalTroops += math.floor(reg.troops)
		econ.goldPerSec += reg.goldBonus
		econ.oilPerSec += reg.oilBonus
		econ.popCap += 140
		econ.manpowerPerSec += 4

		if reg.building then
			local bDef = GameConfig.BUILDINGS[reg.building]
			if bDef then
				econ.goldPerSec += bDef.goldPerSec
				econ.oilPerSec += bDef.oilPerSec
				econ.manpowerPerSec += bDef.manpowerPerSec
				econ.popCap += bDef.popCapBonus
			end
		end
	end
end

local function loadMap(mapId: string)
	local mapTemplate = MapData.MAPS[mapId] or MapData.MAPS.PANAMA
	currentMapId = mapTemplate.id
	regions = {}
	economies = {}
	battleLogs = {}
	matchVictoryFaction = nil

	-- Inicializar economía del jugador (Panamá)
	economies[playerFaction] = {
		factionId = playerFaction,
		gold = 320,
		oil = 60,
		goldPerSec = 0,
		oilPerSec = 0,
		manpowerPerSec = 0,
		popCap = 500,
		totalTroops = 0,
		regionCount = 0,
		aiDefenseMode = "SMART",
		isPlayer = true,
	}

	for _, node in ipairs(mapTemplate.regions) do
		regions[node.id] = {
			id = node.id,
			name = node.name,
			owner = node.initialOwner,
			troops = node.initialTroops,
			building = node.initialBuilding,
			shieldUntil = 0,
			underAttackUntil = 0,
			neighbors = table.clone(node.neighbors),
			goldBonus = node.goldBonus,
			oilBonus = node.oilBonus,
			x = node.x,
			y = node.y,
		}
	end

	recalculateEconomies()
	pushLog(string.format("🗺️ %s iniciada. ¡Construye edificios y expande Panamá!", mapTemplate.title))
end

local function hasPortOrNavalRoute(fromReg: DefenseAI.RegionState, toReg: DefenseAI.RegionState): boolean
	for _, nId in ipairs(fromReg.neighbors) do
		if nId == toReg.id then
			return true
		end
	end
	-- Si la provincia origen tiene un Puerto/Canal construido, puede lanzar invasión anfibia a cualquier región costera o con puerto
	if fromReg.building == "Port" then
		return true
	end
	return false
end

local function hasMissileSilo(factionId: string): boolean
	for _, reg in pairs(regions) do
		if reg.owner == factionId and reg.building == "MissileSilo" then
			return true
		end
	end
	return false
end

local function broadcastState()
	recalculateEconomies()

	local totalRegions = 0
	for _ in pairs(regions) do
		totalRegions += 1
	end

	-- Verificar condición de victoria (65% del mapa o 100% en campaña Panamá)
	if not matchVictoryFaction and totalRegions > 0 then
		for factionId, econ in pairs(economies) do
			if factionId ~= "NEUTRAL" then
				local controlRatio = econ.regionCount / totalRegions
				if controlRatio >= GameConfig.VICTORY_PERCENTAGE then
					matchVictoryFaction = factionId
					local fName = if GameConfig.FACTIONS[factionId]
						then GameConfig.FACTIONS[factionId].name
						else factionId
					pushLog(
						string.format(
							"🏆 ¡VICTORIA! %s domina el %d%% del mapa!",
							fName,
							math.floor(controlRatio * 100)
						)
					)
				end
			end
		end
	end

	local payload = {
		mapId = currentMapId,
		playerFaction = playerFaction,
		regions = regions,
		economies = economies,
		logs = battleLogs,
		victoryFaction = matchVictoryFaction,
		serverTime = os.clock(),
	}

	StateSyncEvent:FireAllClients(payload)
end

-- Ejecuta movimiento de tropas (Refuerzo si es propio, Conquista/Ataque si es enemigo)
local function executeTroopMarch(fromId: string, toId: string, sendRatio: number, isAi: boolean)
	local fromReg = regions[fromId]
	local toReg = regions[toId]
	if not fromReg or not toReg or fromId == toId then
		return
	end

	if not hasPortOrNavalRoute(fromReg, toReg) then
		return
	end

	local clampedRatio = math.clamp(sendRatio or 0.5, 0.15, 0.85)
	if fromReg.troops < 20 then
		return
	end

	local attackingTroops = math.floor(fromReg.troops * clampedRatio)
	if attackingTroops < 10 then
		return
	end

	fromReg.troops -= attackingTroops
	local now = os.clock()

	-- Caso 1: Movimiento de refuerzo entre provincias del mismo país
	if fromReg.owner == toReg.owner then
		toReg.troops += attackingTroops
		CombatFxEvent:FireAllClients({
			type = "REINFORCE",
			fromId = fromId,
			toId = toId,
			faction = fromReg.owner,
			amount = attackingTroops,
		})
		if not isAi then
			pushLog(
				string.format("🚚 Reforzaste %s con +%d tropas desde %s.", toReg.name, attackingTroops, fromReg.name)
			)
		end
		return
	end

	-- Caso 2: Invasión / Conquista territorial
	toReg.underAttackUntil = now + 8.0

	local defenseMultiplier = 1.0
	if toReg.building and GameConfig.BUILDINGS[toReg.building] then
		defenseMultiplier += GameConfig.BUILDINGS[toReg.building].defenseBonus
	end
	if toReg.shieldUntil > now then
		defenseMultiplier += 1.0 -- Escudo Soberano activo
	end

	local effectiveDefenders = math.floor(toReg.troops * defenseMultiplier)

	CombatFxEvent:FireAllClients({
		type = "ATTACK",
		fromId = fromId,
		toId = toId,
		attackerFaction = fromReg.owner,
		defenderFaction = toReg.owner,
		amount = attackingTroops,
	})

	if attackingTroops > effectiveDefenders then
		-- Provincia conquistada
		local remainingAttackers = math.max(15, math.floor((attackingTroops - effectiveDefenders) / defenseMultiplier))
		local oldOwner = toReg.owner
		toReg.owner = fromReg.owner
		toReg.troops = remainingAttackers
		toReg.shieldUntil = 0

		local attackerName = if GameConfig.FACTIONS[fromReg.owner]
			then GameConfig.FACTIONS[fromReg.owner].name
			else fromReg.owner
		local oldName = if GameConfig.FACTIONS[oldOwner] then GameConfig.FACTIONS[oldOwner].shortName else oldOwner

		pushLog(string.format("⚔️ ¡%s conquistó %s (antes %s)!", attackerName, toReg.name, oldName))
	else
		-- Defensa exitosa
		local survivingDefenders = math.max(10, math.floor((effectiveDefenders - attackingTroops) / defenseMultiplier))
		toReg.troops = survivingDefenders

		if toReg.owner == playerFaction then
			-- Activar respuesta inmediata de la IA de Defensa del jugador cuando atacan una de sus provincias
			local playerEcon = economies[playerFaction]
			if playerEcon and playerEcon.aiDefenseMode ~= "MANUAL" then
				DefenseAI.StepPlayerCountryDefense(
					playerFaction,
					playerEcon.aiDefenseMode,
					regions,
					now,
					function(actionType, fId, tId, amt, summary)
						CombatFxEvent:FireAllClients({
							type = actionType,
							fromId = fId,
							toId = tId,
							faction = playerFaction,
							amount = amt,
						})
						pushLog(summary)
					end
				)
			end
		end
	end
end

-- Procesar comandos enviados por el jugador desde la interfaz 2D Pixel
PlayerCommandEvent.OnServerEvent:Connect(function(_player: Player, command: { [string]: any })
	if type(command) ~= "table" then
		return
	end

	local action = command.action
	local playerEcon = economies[playerFaction]
	if not playerEcon then
		return
	end

	if action == "MARCH" then
		-- Expansión territorial o movimiento manual del jugador
		local fromId = tostring(command.fromId or "")
		local toId = tostring(command.toId or "")
		local ratio = tonumber(command.ratio) or 0.5
		local fromReg = regions[fromId]
		if fromReg and fromReg.owner == playerFaction then
			executeTroopMarch(fromId, toId, ratio, false)
			broadcastState()
		end
	elseif action == "BUILD" then
		-- Construcción manual de edificios por el jugador
		local regionId = tostring(command.regionId or "")
		local buildingId = tostring(command.buildingId or "")
		local reg = regions[regionId]
		local bDef = GameConfig.BUILDINGS[buildingId]

		if reg and reg.owner == playerFaction and bDef then
			if playerEcon.gold >= bDef.costGold and playerEcon.oil >= bDef.costOil then
				playerEcon.gold -= bDef.costGold
				playerEcon.oil -= bDef.costOil
				reg.building = buildingId
				pushLog(string.format("🏗️ Construiste %s %s en %s.", bDef.icon, bDef.name, reg.name))
				CombatFxEvent:FireAllClients({
					type = "BUILD",
					toId = regionId,
					buildingId = buildingId,
				})
				broadcastState()
			else
				pushLog("⚠️ Recursos insuficientes para construir " .. bDef.name)
				broadcastState()
			end
		end
	elseif action == "GOD_TOOL" then
		-- Herramienta estilo WorldBox (Dedo de Dios, Meteoro/Bomba, Escudo Soberano)
		local toolId = tostring(command.toolId or "")
		local targetId = tostring(command.targetId or "")
		local reg = regions[targetId]
		local toolDef = GameConfig.GOD_TOOLS[toolId]

		if not reg or not toolDef then
			return
		end

		if toolId == "Meteor" and not hasMissileSilo(playerFaction) then
			pushLog("🚀 Necesitas construir un Silo Táctico antes de lanzar Meteoros/Bombas.")
			broadcastState()
			return
		end

		if playerEcon.gold < toolDef.costGold or playerEcon.oil < toolDef.costOil then
			pushLog("⚠️ Recursos insuficientes para usar " .. toolDef.name)
			broadcastState()
			return
		end

		playerEcon.gold -= toolDef.costGold
		playerEcon.oil -= toolDef.costOil

		if toolId == "DivineFinger" then
			if reg.owner == playerFaction then
				reg.troops += 130
				pushLog(string.format("👆 Dedo Divino bendijo %s (+130 tropas).", reg.name))
			else
				reg.troops = math.max(10, reg.troops - 110)
				pushLog(string.format("👆 Dedo Divino golpeó a %s (-110 tropas).", reg.name))
			end
			CombatFxEvent:FireAllClients({
				type = "GOD_FINGER",
				toId = targetId,
				isFriendly = (reg.owner == playerFaction),
			})
		elseif toolId == "Meteor" then
			reg.troops = math.max(8, math.floor(reg.troops * 0.35))
			if reg.building and reg.owner ~= playerFaction and math.random() < 0.55 then
				reg.building = nil
			end
			pushLog(string.format("☄️ Impacto táctico devastó las defensas en %s!", reg.name))
			CombatFxEvent:FireAllClients({
				type = "METEOR",
				toId = targetId,
			})
		elseif toolId == "DivineShield" then
			if reg.owner == playerFaction then
				reg.shieldUntil = os.clock() + 15.0
				pushLog(string.format("✨ Escudo Soberano activado en %s por 15s.", reg.name))
				CombatFxEvent:FireAllClients({
					type = "SHIELD",
					toId = targetId,
				})
			end
		end

		broadcastState()
	elseif action == "SET_AI_DEFENSE" then
		-- Cambiar el modo de la IA de Defensa del país del jugador
		local newMode = tostring(command.mode or "SMART")
		if GameConfig.DEFENSE_AI_MODES[newMode] then
			playerEcon.aiDefenseMode = newMode
			pushLog("🤖 Modo configurado: " .. GameConfig.DEFENSE_AI_MODES[newMode].name)
			broadcastState()
		end
	elseif action == "SWITCH_MAP" then
		local newMapId = tostring(command.mapId or "PANAMA")
		if MapData.MAPS[newMapId] then
			loadMap(newMapId)
			broadcastState()
		end
	end
end)

Players.PlayerAdded:Connect(function(_player: Player)
	task.wait(0.5)
	broadcastState()
end)

-- Inicializar el mapa por defecto ("Recuperar Panamá")
loadMap(GameConfig.MAP_MODES.PANAMA)

-- Bucle principal de Economía y Crecimiento de Tropas (1 segundo)
task.spawn(function()
	while true do
		task.wait(GameConfig.TICK_RATE)
		recalculateEconomies()

		-- Sumar recursos de cada nación
		for _, econ in pairs(economies) do
			econ.gold = math.clamp(econ.gold + econ.goldPerSec, 0, 99999)
			econ.oil = math.clamp(econ.oil + econ.oilPerSec, 0, 99999)
		end

		-- Crecimiento de tropas en cada provincia según edificios y límite de población
		for _, reg in pairs(regions) do
			if reg.owner ~= "NEUTRAL" then
				local econ = economies[reg.owner]
				if econ and econ.totalTroops < econ.popCap then
					local growth = 4
					if reg.building and GameConfig.BUILDINGS[reg.building] then
						growth += math.floor(GameConfig.BUILDINGS[reg.building].manpowerPerSec * 0.45)
					end
					reg.troops = math.min(999, reg.troops + growth)
				end
			end
		end

		broadcastState()
	end
end)

-- Bucle dedicado de Agentes IA:
-- 1) Ejecuta la IA de Defensa Automática para Panamá (el jugador)
-- 2) Ejecuta la IA de los países rivales
task.spawn(function()
	local botStepCounter = 0
	while true do
		task.wait(GameConfig.AI_DEFENSE_TICK)
		local now = os.clock()
		local playerEcon = economies[playerFaction]

		if playerEcon then
			DefenseAI.StepPlayerCountryDefense(
				playerFaction,
				playerEcon.aiDefenseMode,
				regions,
				now,
				function(actionType, fromId, toId, amount, summary)
					CombatFxEvent:FireAllClients({
						type = actionType,
						fromId = fromId,
						toId = toId,
						faction = playerFaction,
						amount = amount,
					})
					pushLog(summary)
				end
			)
		end

		botStepCounter += 1
		if botStepCounter >= 3 then
			botStepCounter = 0
			for factionId, econ in pairs(economies) do
				if factionId ~= playerFaction and factionId ~= "NEUTRAL" then
					DefenseAI.StepRivalBotNation(factionId, econ, regions, now, executeTroopMarch)
				end
			end
		end
	end
end)
