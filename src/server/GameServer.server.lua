--!strict
-- GameServer.server.lua
-- Motor principal del servidor para "Recuperar Panamá, el Sistema Solar y Andrómeda"
-- Soporta:
-- 1) Lobby Multijugador (Amigos vs Bots, Cooperativo Mundo vs Bots, Movimientos Históricos, Historia Evolutiva)
-- 2) 28 Mapas con Globo Terráqueo / Planetario 3D en Workspace + Tablero Táctico 2D Pixel
-- 3) Evolución Humana y Tecnológica (Dinosaurio -> Homo Sapiens -> Era Industrial -> Tesla -> Andrómeda)
-- 4) Tropas Ficticias y Armamento Bélico Histórico
-- 5) Crisis Humanitarias periódicas y Misiones de Ayuda Humanitaria
-- 6) Comandantes Históricos (Torrijos, Tesla, Newton, Trump, Escobar, Bolívar, Einstein, Napoleón, Gengis Kan, Darwin)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MapData = require(Shared:WaitForChild("MapData"))
local DefenseAI = require(script.Parent:WaitForChild("DefenseAI"))

local RemotesFolder = ReplicatedStorage:FindFirstChild("ConquestRemotes")
if not RemotesFolder then
	RemotesFolder = Instance.new("Folder")
	RemotesFolder.Name = "ConquestRemotes"
	RemotesFolder.Parent = ReplicatedStorage
end

local function ensureRemote(name: string): RemoteEvent
	local existing = RemotesFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = RemotesFolder
	return ev
end

local StateSyncEvent = ensureRemote("StateSyncEvent")
local PlayerCommandEvent = ensureRemote("PlayerCommandEvent")
local CombatFxEvent = ensureRemote("CombatFxEvent")

-- Estado global de la partida
local currentMapId: string = "PANAMA"
local currentGameMode: string = "FRIENDS_VS_BOTS"
local playerFaction: string = "PANAMA"
local playerCommanderId: string = "TORRIJOS"
local regions: { [string]: DefenseAI.RegionState } = {}
local economies: { [string]: DefenseAI.NationEconomy } = {}
local battleLogs: { string } = {}
local activeCrisisSummary: string? = nil
local matchVictoryFaction: string? = nil

-- Asignación de comandantes por defecto a cada facción
local FACTION_COMMANDER_MAP: { [string]: string } = {
	PANAMA = "TORRIJOS",
	TESLA_SYN = "TESLA",
	UK = "NEWTON",
	USA = "TRUMP",
	CARTEL = "ESCOBAR",
	COLOMBIA = "BOLIVAR",
	SCIENCE_COALITION = "EINSTEIN",
	FRANCE = "NAPOLEON",
	MONGOL = "GENGHIS",
	EVO_PANGEA = "DARWIN",
	DINO_APEX = "DARWIN",
}

local function pushLog(msg: string)
	table.insert(battleLogs, 1, msg)
	if #battleLogs > 9 then
		table.remove(battleLogs, #battleLogs)
	end
end

-- ============================================================================
-- GENERADOR DEL GLOBO TERRÁQUEO / PLANETARIO 3D EN EL WORKSPACE
-- ============================================================================
local globeMarkerParts: { [string]: Part } = {}

local function build3DPlanetaryGlobe(mapTemplate: MapData.MapTemplate)
	local oldGlobe = workspace:FindFirstChild("PlanetaryGlobe3D")
	if oldGlobe then
		oldGlobe:Destroy()
	end
	globeMarkerParts = {}

	local folder = Instance.new("Folder")
	folder.Name = "PlanetaryGlobe3D"
	folder.Parent = workspace

	local center = Vector3.new(0, 34, 0)
	local radius = 26

	-- Esfera del Planeta / Globo Terráqueo
	local sphere = Instance.new("Part")
	sphere.Name = "PlanetCoreSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	sphere.Position = center
	sphere.Anchored = true
	sphere.Color = mapTemplate.globeColor
	sphere.Material = Enum.Material.SmoothPlastic
	sphere.Parent = folder

	-- Atmósfera luminosa alrededor del globo
	local atmo = Instance.new("Part")
	atmo.Name = "AtmosphereHalo"
	atmo.Shape = Enum.PartType.Ball
	atmo.Size = Vector3.new(radius * 2.12, radius * 2.12, radius * 2.12)
	atmo.Position = center
	atmo.Anchored = true
	atmo.CanCollide = false
	atmo.Transparency = 0.82
	atmo.Color = mapTemplate.landColor
	atmo.Material = Enum.Material.Neon
	atmo.Parent = folder

	-- Anillos planetarios si es Saturno, Urano o Andrómeda
	if mapTemplate.hasRings then
		for r = 1, 2 do
			local ring = Instance.new("Part")
			ring.Name = "PlanetaryRing_" .. tostring(r)
			ring.Shape = Enum.PartType.Cylinder
			local d = radius * (2.6 + r * 0.45)
			ring.Size = Vector3.new(0.4, d, d)
			ring.CFrame = CFrame.new(center) * CFrame.Angles(math.rad(18), 0, math.rad(75))
			ring.Anchored = true
			ring.CanCollide = false
			ring.Transparency = 0.45
			ring.Color = mapTemplate.landColor
			ring.Material = Enum.Material.ForceField
			ring.Parent = folder
		end
	end

	-- Colocar cada territorio sobre la superficie esférica 3D (Mapeo Latitud/Longitud)
	for _, node in ipairs(mapTemplate.regions) do
		local lon = (node.x - 0.5) * math.pi * 1.85
		local lat = (0.5 - node.y) * math.pi * 0.85

		local dir = Vector3.new(math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon))

		local surfacePos = center + dir * (radius + 0.8)
		local faction = GameConfig.FACTIONS[node.initialOwner] or GameConfig.FACTIONS.NEUTRAL

		local nodePart = Instance.new("Part")
		nodePart.Name = "GlobeNode_" .. node.id
		nodePart.Size = Vector3.new(3.4, 3.4, 1.4)
		nodePart.CFrame = CFrame.lookAt(surfacePos, center)
		nodePart.Anchored = true
		nodePart.Color = faction.primaryColor
		nodePart.Material = Enum.Material.SmoothPlastic
		nodePart.TopSurface = Enum.SurfaceType.Studs
		nodePart.Parent = folder

		local bb = Instance.new("BillboardGui")
		bb.Name = "NodeBillboard"
		bb.Size = UDim2.fromOffset(130, 36)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = true
		bb.Parent = nodePart

		local lbl = Instance.new("TextLabel")
		lbl.Name = "InfoLabel"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
		lbl.BackgroundTransparency = 0.25
		lbl.Font = Enum.Font.Arcade
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.TextSize = 11
		lbl.Text = string.format("%s %s\n⚔️%d", faction.flagEmoji, node.name, node.initialTroops)
		lbl.Parent = bb

		globeMarkerParts[node.id] = nodePart
	end
end

local function update3DGlobeColors()
	for id, reg in pairs(regions) do
		local part = globeMarkerParts[id]
		if part then
			local faction = GameConfig.FACTIONS[reg.owner] or GameConfig.FACTIONS.NEUTRAL
			part.Color = faction.primaryColor
			local bb = part:FindFirstChild("NodeBillboard")
			if bb then
				local lbl = bb:FindFirstChild("InfoLabel") :: TextLabel?
				if lbl then
					local crisisIcon = if reg.crisisId then "☣️" else ""
					lbl.Text = string.format(
						"%s%s %s\n⚔️%d",
						faction.flagEmoji,
						crisisIcon,
						reg.name,
						math.floor(reg.troops)
					)
				end
			end
		end
	end
end

-- ============================================================================
-- ECONOMÍA, CIENCIA Y EVOLUCIÓN
-- ============================================================================
local function recalculateEconomies()
	for _, econ in pairs(economies) do
		econ.goldPerSec = 12
		econ.oilPerSec = 3
		econ.sciencePerSec = 5
		econ.manpowerPerSec = 8
		econ.popCap = 320
		econ.totalTroops = 0
		econ.regionCount = 0
	end

	for _, reg in pairs(regions) do
		local econ = economies[reg.owner]
		if not econ then
			local cmdId = if reg.owner == playerFaction
				then playerCommanderId
				else (FACTION_COMMANDER_MAP[reg.owner] or "TORRIJOS")
			local mapTemplate = MapData.MAPS[currentMapId] or MapData.MAPS.PANAMA
			local initEra = if currentGameMode == "EVOLUTION_STORY" then 1 else mapTemplate.startEra

			econ = {
				factionId = reg.owner,
				commanderId = cmdId,
				evolutionLevel = initEra,
				gold = 260,
				oil = 50,
				science = 40,
				goldPerSec = 12,
				oilPerSec = 3,
				sciencePerSec = 5,
				manpowerPerSec = 8,
				popCap = 320,
				totalTroops = 0,
				regionCount = 0,
				aiDefenseMode = "SMART",
				isPlayer = (reg.owner == playerFaction),
			}
			economies[reg.owner] = econ
		end

		local cmdDef = GameConfig.COMMANDERS[econ.commanderId] or GameConfig.COMMANDERS.TORRIJOS
		local eraDef = GameConfig.EVOLUTION_STAGES[econ.evolutionLevel] or GameConfig.EVOLUTION_STAGES[1]

		econ.regionCount += 1
		econ.totalTroops += math.floor(reg.troops)
		econ.goldPerSec += math.floor(reg.goldBonus * cmdDef.goldMultiplier)
		econ.oilPerSec += reg.oilBonus
		econ.sciencePerSec += math.floor(3 * cmdDef.scienceMultiplier)
		econ.popCap += 160
		econ.manpowerPerSec += (4 + eraDef.growthBonus)

		if reg.building then
			local bDef = GameConfig.BUILDINGS[reg.building]
			if bDef then
				econ.goldPerSec += math.floor(bDef.goldPerSec * cmdDef.goldMultiplier)
				econ.oilPerSec += bDef.oilPerSec
				econ.sciencePerSec += math.floor(bDef.sciencePerSec * cmdDef.scienceMultiplier)
				econ.manpowerPerSec += bDef.manpowerPerSec
				econ.popCap += bDef.popCapBonus
			end
		end
	end
end

local function loadMap(mapId: string, gameMode: string?, commanderId: string?)
	local mapTemplate = MapData.MAPS[mapId] or MapData.MAPS.PANAMA
	currentMapId = mapTemplate.id
	if gameMode and GameConfig.GAME_MODES[gameMode] then
		currentGameMode = gameMode
	end
	if commanderId and GameConfig.COMMANDERS[commanderId] then
		playerCommanderId = commanderId
	end

	regions = {}
	economies = {}
	battleLogs = {}
	activeCrisisSummary = nil
	matchVictoryFaction = nil

	local startEra = if currentGameMode == "EVOLUTION_STORY" then 1 else mapTemplate.startEra
	local defaultUnit = GameConfig.EVOLUTION_STAGES[startEra].unlockedUnitId

	economies[playerFaction] = {
		factionId = playerFaction,
		commanderId = playerCommanderId,
		evolutionLevel = startEra,
		gold = 360,
		oil = 75,
		science = 60,
		goldPerSec = 0,
		oilPerSec = 0,
		sciencePerSec = 0,
		manpowerPerSec = 0,
		popCap = 600,
		totalTroops = 0,
		regionCount = 0,
		aiDefenseMode = "SMART",
		isPlayer = true,
	}

	for _, node in ipairs(mapTemplate.regions) do
		local owner = node.initialOwner
		-- En modo Cooperativo Mundo vs Coalición IA, aliados iniciales se unen a Panamá
		if currentGameMode == "COOP_WORLD" and (owner == "COLOMBIA" or owner == "COSTA_RICA") then
			owner = playerFaction
		elseif currentGameMode == "EVOLUTION_STORY" and owner ~= playerFaction and owner ~= "NEUTRAL" then
			owner = if math.random() < 0.5 then "DINO_APEX" else "EVO_PANGEA"
		end

		regions[node.id] = {
			id = node.id,
			name = node.name,
			owner = owner,
			troops = node.initialTroops,
			building = node.initialBuilding,
			unitType = defaultUnit,
			crisisId = nil,
			shieldUntil = 0,
			underAttackUntil = 0,
			neighbors = table.clone(node.neighbors),
			goldBonus = node.goldBonus,
			oilBonus = node.oilBonus,
			x = node.x,
			y = node.y,
		}
	end

	build3DPlanetaryGlobe(mapTemplate)
	recalculateEconomies()

	local cmdDef = GameConfig.COMMANDERS[playerCommanderId] or GameConfig.COMMANDERS.TORRIJOS
	local eraDef = GameConfig.EVOLUTION_STAGES[startEra]
	pushLog(string.format("🌍 [%s] Comandante: %s | %s", mapTemplate.title, cmdDef.name, eraDef.name))
end

local function hasPortOrNavalRoute(fromReg: DefenseAI.RegionState, toReg: DefenseAI.RegionState): boolean
	for _, nId in ipairs(fromReg.neighbors) do
		if nId == toReg.id then
			return true
		end
	end
	if fromReg.building == "Port" then
		return true
	end
	local econ = economies[fromReg.owner]
	-- En la Era 7 (Andrómeda), las naves pueden saltar entre cualquier sector
	if econ and econ.evolutionLevel >= 7 then
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
	update3DGlobeColors()

	local totalRegions = 0
	for _ in pairs(regions) do
		totalRegions += 1
	end

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
							"🏆 ¡VICTORIA CÓSMICA! %s domina el %d%% de %s!",
							fName,
							math.floor(controlRatio * 100),
							currentMapId
						)
					)
				end
			end
		end
	end

	local payload = {
		mapId = currentMapId,
		gameMode = currentGameMode,
		playerFaction = playerFaction,
		playerCommanderId = playerCommanderId,
		regions = regions,
		economies = economies,
		logs = battleLogs,
		activeCrisis = activeCrisisSummary,
		victoryFaction = matchVictoryFaction,
		serverTime = os.clock(),
	}

	StateSyncEvent:FireAllClients(payload)
end

-- ============================================================================
-- COMBATE CON MODIFICADORES DE EVOLUCIÓN, ARMAMENTO BÉLICO Y COMANDANTES
-- ============================================================================
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

	-- Refuerzo propio
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

	toReg.underAttackUntil = now + 8.0

	-- Multiplicadores de Era Evolutiva, Comandante y Armamento Bélico
	local atkEcon = economies[fromReg.owner]
	local defEcon = economies[toReg.owner]

	local atkEra = if atkEcon
		then (GameConfig.EVOLUTION_STAGES[atkEcon.evolutionLevel] or GameConfig.EVOLUTION_STAGES[1])
		else GameConfig.EVOLUTION_STAGES[1]
	local defEra = if defEcon
		then (GameConfig.EVOLUTION_STAGES[defEcon.evolutionLevel] or GameConfig.EVOLUTION_STAGES[1])
		else GameConfig.EVOLUTION_STAGES[1]

	local atkCmd = if atkEcon
		then (GameConfig.COMMANDERS[atkEcon.commanderId] or GameConfig.COMMANDERS.TORRIJOS)
		else GameConfig.COMMANDERS.TORRIJOS
	local defCmd = if defEcon
		then (GameConfig.COMMANDERS[defEcon.commanderId] or GameConfig.COMMANDERS.TORRIJOS)
		else GameConfig.COMMANDERS.TORRIJOS

	local unitPower = 1.0
	if fromReg.unitType and GameConfig.MILITARY_UNITS[fromReg.unitType] then
		unitPower = 1.0 + (GameConfig.MILITARY_UNITS[fromReg.unitType].powerBonus - 1.0) * 0.35
	end

	local attackMultiplier = atkEra.attackMultiplier * atkCmd.attackMultiplier * unitPower
	local defenseMultiplier = defEra.defenseMultiplier * defCmd.defenseMultiplier

	if toReg.building and GameConfig.BUILDINGS[toReg.building] then
		defenseMultiplier += GameConfig.BUILDINGS[toReg.building].defenseBonus
	end
	if toReg.shieldUntil > now then
		defenseMultiplier += 1.0
	end
	if toReg.crisisId then
		defenseMultiplier *= 0.80 -- Una crisis humanitaria sin atender reduce la capacidad defensiva
	end

	local effectiveAttack = math.floor(attackingTroops * attackMultiplier)
	local effectiveDefenders = math.floor(toReg.troops * defenseMultiplier)

	CombatFxEvent:FireAllClients({
		type = "ATTACK",
		fromId = fromId,
		toId = toId,
		attackerFaction = fromReg.owner,
		defenderFaction = toReg.owner,
		amount = attackingTroops,
	})

	if effectiveAttack > effectiveDefenders then
		local remainingAttackers =
			math.max(15, math.floor((effectiveAttack - effectiveDefenders) / math.max(1, attackMultiplier)))
		local oldOwner = toReg.owner
		toReg.owner = fromReg.owner
		toReg.troops = remainingAttackers
		toReg.unitType = fromReg.unitType
		toReg.shieldUntil = 0

		-- Bonus de saqueo si el comandante es Gengis Kan o Escobar
		if atkEcon and (atkEcon.commanderId == "GENGHIS" or atkEcon.commanderId == "ESCOBAR") then
			atkEcon.gold += 55
		end

		local attackerName = if GameConfig.FACTIONS[fromReg.owner]
			then GameConfig.FACTIONS[fromReg.owner].name
			else fromReg.owner
		local oldName = if GameConfig.FACTIONS[oldOwner] then GameConfig.FACTIONS[oldOwner].shortName else oldOwner

		pushLog(string.format("⚔️ ¡%s conquistó %s (antes %s)!", attackerName, toReg.name, oldName))
	else
		local survivingDefenders =
			math.max(10, math.floor((effectiveDefenders - effectiveAttack) / math.max(1, defenseMultiplier)))
		toReg.troops = survivingDefenders

		if toReg.owner == playerFaction then
			local playerEcon = economies[playerFaction]
			if playerEcon and playerEcon.aiDefenseMode ~= "MANUAL" then
				DefenseAI.StepPlayerCountryDefense(
					playerFaction,
					playerEcon.aiDefenseMode,
					playerEcon.commanderId,
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

-- ============================================================================
-- COMANDOS DEL JUGADOR (LOBBY, EVOLUCIÓN, ARMAMENTO, CRISIS, EDIFICIOS)
-- ============================================================================
PlayerCommandEvent.OnServerEvent:Connect(function(_player: Player, command: { [string]: any })
	if type(command) ~= "table" then
		return
	end

	local action = command.action
	local playerEcon = economies[playerFaction]
	if not playerEcon then
		return
	end

	if action == "START_LOBBY_MATCH" then
		local chosenMap = tostring(command.mapId or currentMapId)
		local chosenMode = tostring(command.gameMode or currentGameMode)
		local chosenCommander = tostring(command.commanderId or playerCommanderId)
		loadMap(chosenMap, chosenMode, chosenCommander)
		broadcastState()
	elseif action == "MARCH" then
		local fromId = tostring(command.fromId or "")
		local toId = tostring(command.toId or "")
		local ratio = tonumber(command.ratio) or 0.5
		local fromReg = regions[fromId]
		if fromReg and fromReg.owner == playerFaction then
			executeTroopMarch(fromId, toId, ratio, false)
			broadcastState()
		end
	elseif action == "BUILD" then
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
	elseif action == "EVOLVE_ERA" then
		-- Evolucionar de Dinosaurio -> Homínido -> Homo Sapiens -> Era Industrial -> Atómica -> Tesla -> Andrómeda
		local nextLevel = playerEcon.evolutionLevel + 1
		local nextStage = GameConfig.EVOLUTION_STAGES[nextLevel]
		if not nextStage then
			pushLog("🌌 ¡Ya alcanzaste la Era 7 máxima: Civilización Intergaláctica de Andrómeda!")
			broadcastState()
			return
		end

		local costMultiplier = if playerEcon.commanderId == "DARWIN" then 0.70 else 1.0
		local reqScience = math.floor(nextStage.costScience * costMultiplier)
		local reqGold = math.floor(nextStage.costGold * costMultiplier)

		if playerEcon.science >= reqScience and playerEcon.gold >= reqGold then
			playerEcon.science -= reqScience
			playerEcon.gold -= reqGold
			playerEcon.evolutionLevel = nextLevel

			-- Actualizar las tropas de tus regiones a la nueva era evolutiva
			for _, reg in pairs(regions) do
				if reg.owner == playerFaction then
					reg.unitType = nextStage.unlockedUnitId
					reg.troops += 45
				end
			end

			pushLog(string.format("🧬 ¡EVOLUCIÓN COMPLETADA! Avanzaste a %s (%s)!", nextStage.icon, nextStage.name))
			broadcastState()
		else
			pushLog(
				string.format(
					"⚠️ Necesitas 🧬%d Ciencia y 💰%d Oro para evolucionar a %s.",
					reqScience,
					reqGold,
					nextStage.name
				)
			)
			broadcastState()
		end
	elseif action == "DEPLOY_UNIT" then
		-- Desplegar Tropas Ficticias o Armamento Bélico Histórico en la provincia seleccionada
		local regionId = tostring(command.regionId or "")
		local unitId = tostring(command.unitId or "")
		local reg = regions[regionId]
		local uDef = GameConfig.MILITARY_UNITS[unitId]

		if not reg or reg.owner ~= playerFaction or not uDef then
			return
		end

		if playerEcon.evolutionLevel < uDef.minEra then
			local reqEra = GameConfig.EVOLUTION_STAGES[uDef.minEra]
			pushLog(string.format("🔒 %s requiere evolucionar a %s.", uDef.name, reqEra.name))
			broadcastState()
			return
		end

		if playerEcon.gold >= uDef.costGold and playerEcon.oil >= uDef.costOil then
			playerEcon.gold -= uDef.costGold
			playerEcon.oil -= uDef.costOil
			reg.troops += uDef.troopBonus
			reg.unitType = unitId
			pushLog(
				string.format(
					"%s Desplegaste %s en %s (+%d tropas de élite)!",
					uDef.icon,
					uDef.name,
					reg.name,
					uDef.troopBonus
				)
			)
			CombatFxEvent:FireAllClients({
				type = "SHIELD",
				toId = regionId,
			})
			broadcastState()
		else
			pushLog("⚠️ Recursos insuficientes para desplegar " .. uDef.name)
			broadcastState()
		end
	elseif action == "GOD_TOOL" then
		local toolId = tostring(command.toolId or "")
		local targetId = tostring(command.targetId or "")
		local reg = regions[targetId]
		local toolDef = GameConfig.GOD_TOOLS[toolId]

		if not reg or not toolDef then
			return
		end

		if toolId == "Meteor" and not hasMissileSilo(playerFaction) then
			pushLog("🚀 Necesitas construir un Silo Estratégico antes de lanzar Meteoros/Nukes.")
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

		if toolId == "HumanitarianAid" then
			reg.crisisId = nil
			reg.troops += 90
			playerEcon.science += 55
			activeCrisisSummary = nil
			pushLog(
				string.format(
					"🏥 Misión Humanitaria en %s completada: Crisis resuelta, +90 Tropas y +55 Ciencia!",
					reg.name
				)
			)
			CombatFxEvent:FireAllClients({
				type = "SHIELD",
				toId = targetId,
			})
		elseif toolId == "DivineFinger" then
			if reg.owner == playerFaction then
				reg.troops += 140
				pushLog(string.format("👆 Dedo Divino bendijo %s (+140 tropas).", reg.name))
			else
				reg.troops = math.max(10, reg.troops - 120)
				pushLog(string.format("👆 Dedo Divino castigó a %s (-120 tropas).", reg.name))
			end
			CombatFxEvent:FireAllClients({
				type = "GOD_FINGER",
				toId = targetId,
				isFriendly = (reg.owner == playerFaction),
			})
		elseif toolId == "Meteor" then
			local dmgFactor = if playerEcon.commanderId == "NEWTON" then 0.25 else 0.35
			reg.troops = math.max(8, math.floor(reg.troops * dmgFactor))
			if reg.building and reg.owner ~= playerFaction and math.random() < 0.60 then
				reg.building = nil
			end
			pushLog(string.format("☄️ Impacto orbital devastó %s!", reg.name))
			CombatFxEvent:FireAllClients({
				type = "METEOR",
				toId = targetId,
			})
		elseif toolId == "DivineShield" then
			if reg.owner == playerFaction then
				reg.shieldUntil = os.clock() + 15.0
				pushLog(string.format("✨ Escudo Cuántico activado en %s por 15s.", reg.name))
				CombatFxEvent:FireAllClients({
					type = "SHIELD",
					toId = targetId,
				})
			end
		end

		broadcastState()
	elseif action == "SET_AI_DEFENSE" then
		local newMode = tostring(command.mode or "SMART")
		if GameConfig.DEFENSE_AI_MODES[newMode] then
			playerEcon.aiDefenseMode = newMode
			pushLog("🤖 Modo configurado: " .. GameConfig.DEFENSE_AI_MODES[newMode].name)
			broadcastState()
		end
	elseif action == "SWITCH_MAP" then
		local newMapId = tostring(command.mapId or "PANAMA")
		if MapData.MAPS[newMapId] then
			loadMap(newMapId, currentGameMode, playerCommanderId)
			broadcastState()
		end
	end
end)

Players.PlayerAdded:Connect(function(_player: Player)
	task.wait(0.5)
	broadcastState()
end)

loadMap("PANAMA", "FRIENDS_VS_BOTS", "TORRIJOS")

-- Bucle principal de Economía, Ciencia, Evolución y Crisis Humanitarias
task.spawn(function()
	local crisisTimer = 0
	while true do
		task.wait(GameConfig.TICK_RATE)
		recalculateEconomies()

		for _, econ in pairs(economies) do
			econ.gold = math.clamp(econ.gold + econ.goldPerSec, 0, 999999)
			econ.oil = math.clamp(econ.oil + econ.oilPerSec, 0, 999999)
			econ.science = math.clamp(econ.science + econ.sciencePerSec, 0, 999999)
		end

		for _, reg in pairs(regions) do
			if reg.owner ~= "NEUTRAL" then
				local econ = economies[reg.owner]
				if econ and econ.totalTroops < econ.popCap then
					local eraDef = GameConfig.EVOLUTION_STAGES[econ.evolutionLevel] or GameConfig.EVOLUTION_STAGES[1]
					local growth = 4 + math.floor(eraDef.growthBonus * 0.5)
					if reg.building and GameConfig.BUILDINGS[reg.building] then
						growth += math.floor(GameConfig.BUILDINGS[reg.building].manpowerPerSec * 0.45)
					end
					if reg.crisisId then
						growth = math.max(1, math.floor(growth * 0.35))
					end
					reg.troops = math.min(2500, reg.troops + growth)
				end
			end
		end

		-- Generador periódico de Crisis Humanitarias y Eventos Globales
		crisisTimer += 1
		if crisisTimer >= GameConfig.CRISIS_INTERVAL then
			crisisTimer = 0
			local allRegList: { DefenseAI.RegionState } = {}
			for _, r in pairs(regions) do
				table.insert(allRegList, r)
			end
			if #allRegList > 0 then
				local targetReg = allRegList[math.random(1, #allRegList)]
				local crisis = GameConfig.HUMANITARIAN_CRISES[math.random(1, #GameConfig.HUMANITARIAN_CRISES)]
				targetReg.crisisId = crisis.id
				local lost = math.max(8, math.floor(targetReg.troops * crisis.troopLossRatio))
				targetReg.troops = math.max(12, targetReg.troops - lost)
				activeCrisisSummary = string.format(
					"%s CRISIS EN %s: %s (-%d tropas). ¡Usa 🏥 Ayuda Humanitaria!",
					crisis.icon,
					string.upper(targetReg.name),
					crisis.name,
					lost
				)
				pushLog(activeCrisisSummary)
			end
		end

		broadcastState()
	end
end)

-- Bucle de IA de Defensa del Jugador + Bots de Líderes Históricos
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
				playerEcon.commanderId,
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
