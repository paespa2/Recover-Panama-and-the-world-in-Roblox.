--!strict
-- OpenFront.io: ClientMain
-- Client entrypoint driving Hub, Camera, Input, HUD and Renderers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local MapRegistry = require(script.Parent.Parent.shared.MapRegistry)
local TerrainRenderer = require(script.Parent.TerrainRenderer)
local TerritoryRenderer = require(script.Parent.TerritoryRenderer)
local InGameHUD = require(script.Parent.InGameHUD)
local HubScreen = require(script.Parent.HubScreen)

-- Remotes
local remotes = ReplicatedStorage:WaitForChild("OpenFrontRemotes", 10) :: Folder
if not remotes then
	warn("[OpenFrontClient] Waiting for OpenFrontRemotes...")
	remotes = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
end

local selectMapFunc = remotes:WaitForChild("SelectMap") :: RemoteFunction
local joinNationFunc = remotes:WaitForChild("JoinNation") :: RemoteFunction
local attackEvent = remotes:WaitForChild("SendAttack") :: RemoteEvent
local buildEvent = remotes:WaitForChild("BuildStructure") :: RemoteEvent
local nukeEvent = remotes:WaitForChild("LaunchNuke") :: RemoteEvent
local serverSnapshotEvent = remotes:WaitForChild("ServerSnapshot") :: RemoteEvent
local gameWonEvent = remotes:WaitForChild("GameWon") :: RemoteEvent
local serverMessageEvent = remotes:WaitForChild("ServerMessage") :: RemoteEvent

-- ScreenGui Setup
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OpenFrontGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

-- Map Viewport Container
local mapContainer = Instance.new("Frame")
mapContainer.Name = "MapContainer"
mapContainer.Size = UDim2.new(1, 0, 1, 0)
mapContainer.BackgroundColor3 = Color3.fromRGB(8, 12, 18)
mapContainer.BorderSizePixel = 0
mapContainer.ClipsDescendants = true
mapContainer.Visible = false
mapContainer.Parent = screenGui

local mapCanvas = Instance.new("Frame")
mapCanvas.Name = "MapCanvas"
mapCanvas.AnchorPoint = Vector2.new(0.5, 0.5)
mapCanvas.Position = UDim2.new(0.5, 0, 0.5, 0)
mapCanvas.Size = UDim2.new(0, 960, 0, 480)
mapCanvas.BackgroundTransparency = 1
mapCanvas.Parent = mapContainer

local mapImage = Instance.new("ImageLabel")
mapImage.Name = "MapImage"
mapImage.Size = UDim2.new(1, 0, 1, 0)
mapImage.BackgroundTransparency = 1
mapImage.ScaleType = Enum.ScaleType.Stretch
mapImage.Parent = mapCanvas

-- Renderers & UI Controllers
local terrainRenderer = TerrainRenderer.new()
local territoryRenderer = TerritoryRenderer.new()
local hud = InGameHUD.new()
local hub = HubScreen.new()

local currentMapId = "world"
local currentMapData = nil :: any
local mySmallID = 0
local currentActionMode = "attack"

-- Camera Panning & Zooming
local camZoom = 1.0
local camPos = Vector2.new(0.5, 0.5)
local isDragging = false
local dragStartPos = Vector2.zero
local dragStartCam = Vector2.zero

local function updateCanvasTransform()
	if not currentMapData then return end
	local vpSize = mapContainer.AbsoluteSize
	local baseW = currentMapData.w * 2
	local baseH = currentMapData.h * 2

	local scaledW = baseW * camZoom
	local scaledH = baseH * camZoom

	mapCanvas.Size = UDim2.new(0, scaledW, 0, scaledH)
	mapCanvas.Position = UDim2.new(camPos.X, 0, camPos.Y, 0)
end

local function screenToTile(screenPos: Vector2): (number, number)?
	if not currentMapData then return nil, nil end
	local canvasAbs = mapCanvas.AbsolutePosition
	local canvasSize = mapCanvas.AbsoluteSize

	local relX = (screenPos.X - canvasAbs.X) / canvasSize.X
	local relY = (screenPos.Y - canvasAbs.Y) / canvasSize.Y

	if relX >= 0 and relX <= 1 and relY >= 0 and relY <= 1 then
		local tx = math.floor(relX * currentMapData.w)
		local ty = math.floor(relY * currentMapData.h)
		return tx, ty
	end
	return nil, nil
end

local function startMatch(mapId: string)
	print("[OpenFrontClient] Starting match on map: " .. mapId)
	currentMapId = mapId
	currentMapData = MapRegistry.GetMap(mapId)
	if not currentMapData then
		warn("Map not found: " .. mapId)
		return
	end

	-- Call server to switch map and join
	selectMapFunc:InvokeServer(mapId)
	local joinRes = joinNationFunc:InvokeServer()
	if joinRes and joinRes.smallID then
		mySmallID = joinRes.smallID
	end

	-- Initialize renderers
	terrainRenderer:Init(currentMapData, mapImage)
	territoryRenderer:Init(currentMapData.w, currentMapData.h, terrainRenderer)

	-- Show Game UI, Hide Hub
	hub:SetVisible(false)
	mapContainer.Visible = true
	hud:SetVisible(true)

	camZoom = 1.0
	camPos = Vector2.new(0.5, 0.5)
	updateCanvasTransform()
end

-- Initialize Hub
hub:Init(screenGui, function(mapId)
	startMatch(mapId)
end)

-- Initialize HUD
hud:Init(screenGui, function(mode)
	currentActionMode = mode
	print("[OpenFrontClient] Selected mode: " .. mode)
end)
hud:SetVisible(false)

-- Input Handling
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
		-- Start pan
		isDragging = true
		dragStartPos = UserInputService:GetMouseLocation()
		dragStartCam = camPos
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Click on map
		local mPos = UserInputService:GetMouseLocation()
		local tx, ty = screenToTile(mPos)
		if tx and ty then
			if currentActionMode == "attack" then
				attackEvent:FireServer(tx, ty, hud.attackRatio)
			elseif string.sub(currentActionMode, 1, 6) == "build_" then
				local unitType = string.sub(currentActionMode, 7)
				buildEvent:FireServer(unitType, tx, ty)
			elseif string.sub(currentActionMode, 1, 5) == "nuke_" then
				local nukeType = string.sub(currentActionMode, 6)
				nukeEvent:FireServer(nukeType, tx, ty)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
		isDragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		-- Zoom in/out
		local oldZoom = camZoom
		if input.Position.Z > 0 then
			camZoom = math.min(5.0, camZoom * 1.2)
		else
			camZoom = math.max(0.6, camZoom / 1.2)
		end
		updateCanvasTransform()
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and isDragging then
		local mPos = UserInputService:GetMouseLocation()
		local delta = mPos - dragStartPos
		local vpSize = mapContainer.AbsoluteSize
		camPos = Vector2.new(
			dragStartCam.X + (delta.X / vpSize.X),
			dragStartCam.Y + (delta.Y / vpSize.Y)
		)
		updateCanvasTransform()
	end
end)

-- Server Snapshot Listener
serverSnapshotEvent.OnClientEvent:Connect(function(payload)
	if not payload or not currentMapData then return end

	-- Update roster in territory renderer
	if payload.players then
		territoryRenderer:SetPlayerRoster(payload.players, mySmallID)
		hud:UpdateLeaderboard(payload.players, currentMapData.landTiles or 35000)

		-- Find my player stats
		for _, p in ipairs(payload.players) do
			if p.smallID == mySmallID then
				hud:UpdateStats(p.troops, 100000, p.gold, 15, 2500)
				break
			end
		end
	end

	-- Apply territory changes
	if payload.deltas and #payload.deltas > 0 then
		territoryRenderer:ApplyDeltas(payload.deltas)
	end
end)

-- Victory Listener
gameWonEvent.OnClientEvent:Connect(function(data)
	local winBanner = Instance.new("Frame")
	winBanner.Name = "WinBanner"
	winBanner.Size = UDim2.new(0, 500, 0, 160)
	winBanner.Position = UDim2.new(0.5, -250, 0.3, -80)
	winBanner.BackgroundColor3 = Color3.fromRGB(20, 26, 40)
	winBanner.BorderSizePixel = 0
	winBanner.Parent = screenGui
	Instance.new("UICorner", winBanner).CornerRadius = UDim.new(0, 12)
	local bStroke = Instance.new("UIStroke", winBanner)
	bStroke.Color = Color3.fromRGB(255, 215, 50)
	bStroke.Thickness = 2

	local wTitle = Instance.new("TextLabel")
	wTitle.Size = UDim2.new(1, 0, 0, 50)
	wTitle.BackgroundTransparency = 1
	wTitle.Font = Enum.Font.GothamBlack
	wTitle.TextSize = 24
	wTitle.TextColor3 = Color3.fromRGB(255, 215, 50)
	wTitle.Text = "👑 ¡VICTORIA TOTAL! 👑"
	wTitle.Parent = winBanner

	local wSub = Instance.new("TextLabel")
	wSub.Size = UDim2.new(1, -20, 0, 60)
	wSub.Position = UDim2.new(0, 10, 0, 55)
	wSub.BackgroundTransparency = 1
	wSub.Font = Enum.Font.GothamBold
	wSub.TextSize = 18
	wSub.TextColor3 = Color3.new(1, 1, 1)
	wSub.Text = data.winnerName .. " ha conquistado el 80% del mundo y asegurado la dominación global."
	wSub.TextWrapped = true
	wSub.Parent = winBanner
end)

print("[OpenFrontClient] Client initialized cleanly!")
