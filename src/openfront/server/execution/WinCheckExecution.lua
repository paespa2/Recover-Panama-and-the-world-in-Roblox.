--!strict
-- OpenFront.io: WinCheckExecution
-- Parity with packages/engine/src/execution/WinCheckExecution.ts

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("OpenFront"):WaitForChild("Shared"):WaitForChild("Config"))

local WinCheckExecution = {}
WinCheckExecution.__index = WinCheckExecution

function WinCheckExecution.new(id: string, gameRunner: any)
	local self = setmetatable({}, WinCheckExecution)
	self.id = id
	self.gameRunner = gameRunner
	self.finished = false
	self.checkInterval = 1.0 -- Check every 1 second
	self.elapsed = 0
	return self
end

function WinCheckExecution:IsFinished(): boolean
	return self.finished
end

function WinCheckExecution:Tick(dt: number, tickNumber: number): boolean
	if self.finished then return false end

	self.elapsed += dt
	if self.elapsed < self.checkInterval then
		return true
	end
	self.elapsed = 0

	local totalLand = self.gameRunner.gameMap.landTilesCount
	if totalLand <= 0 then return true end

	local requiredTiles = math.floor(totalLand * (Config.PERCENT_TILES_OWNED_TO_WIN / 100))

	for smallID, player in pairs(self.gameRunner.playersBySmallID) do
		if player.alive and player.tilesCount >= requiredTiles then
			-- We have a winner!
			self.finished = true
			self.gameRunner:DeclareWinner(player)
			return false
		end
	end

	return true
end

return WinCheckExecution
