--!strict
-- OpenFront.io: Player
-- Parity with packages/engine/src/game/Player.ts

local Config = require(script.Parent.Parent.shared.Config)

local Player = {}
Player.__index = Player

export type PlayerInstance = {
	id: string,
	smallID: number,
	name: string,
	flag: string,
	color: Color3,
	playerType: "Human" | "Bot" | "Nation",
	troops: number,
	gold: number,
	tilesCount: number,
	citiesCount: number,
	portsCount: number,
	factoriesCount: number,
	defensePostsCount: number,
	silosCount: number,
	samsCount: number,
	warshipsCount: number,
	alive: boolean,
	capitalIdx: number,

	AddTroops: (self: PlayerInstance, amount: number) -> (),
	SpendTroops: (self: PlayerInstance, amount: number) -> boolean,
	AddGold: (self: PlayerInstance, amount: number) -> (),
	SpendGold: (self: PlayerInstance, amount: number) -> boolean,
	GetMaxTroops: (self: PlayerInstance) -> number,
	TickIncome: (self: PlayerInstance, dt: number) -> (),
}

function Player.new(
	smallID: number,
	id: string,
	name: string,
	flag: string,
	color: Color3,
	playerType: "Human" | "Bot" | "Nation",
	capitalIdx: number
): PlayerInstance
	local self = setmetatable({}, Player)
	self.smallID = smallID
	self.id = id
	self.name = name
	self.flag = flag
	self.color = color
	self.playerType = playerType
	self.troops = 100
	self.gold = 500000
	self.tilesCount = 1
	self.citiesCount = 0
	self.portsCount = 0
	self.factoriesCount = 0
	self.defensePostsCount = 0
	self.silosCount = 0
	self.samsCount = 0
	self.warshipsCount = 0
	self.alive = true
	self.capitalIdx = capitalIdx
	return (self :: any) :: PlayerInstance
end

function Player:GetMaxTroops(): number
	return Config.MaxTroops(self.tilesCount, self.citiesCount, self.playerType)
end

function Player:AddTroops(amount: number)
	local max = self:GetMaxTroops()
	self.troops = math.clamp(self.troops + amount, 0, max)
end

function Player:SpendTroops(amount: number): boolean
	if self.troops >= amount then
		self.troops -= amount
		return true
	end
	return false
end

function Player:AddGold(amount: number)
	self.gold = math.max(0, self.gold + amount)
end

function Player:SpendGold(amount: number): boolean
	if self.gold >= amount then
		self.gold -= amount
		return true
	end
	return false
end

function Player:TickIncome(dt: number)
	if not self.alive then return end
	local max = self:GetMaxTroops()
	local toAdd = Config.TroopIncreaseRate(self.troops, max, self.playerType)
	self.troops = math.clamp(self.troops + (toAdd * (dt / (1 / Config.TICKS_PER_SECOND))), 0, max)

	local goldPerSec = Config.GoldPerSecond(self.tilesCount, self.factoriesCount, self.playerType)
	self.gold += math.floor(goldPerSec * dt)
end

return Player
