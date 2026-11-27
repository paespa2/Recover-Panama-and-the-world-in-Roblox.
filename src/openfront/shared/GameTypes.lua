--!strict
-- OpenFront.io: GameTypes
-- Parity with @openfront/engine-api/game/GameTypes

export type UnitType = 
	| "City"
	| "Port"
	| "Factory"
	| "DefensePost"
	| "MissileSilo"
	| "SAMLauncher"
	| "AtomBomb"
	| "HydrogenBomb"
	| "MIRV"
	| "MIRVWarhead"
	| "Warship"
	| "TransportShip"
	| "TradeShip"
	| "Train"
	| "Shell"
	| "SAMMissile"

export type PlayerType = "Human" | "Bot" | "Nation"

export type TerrainType = "Land" | "Shoreline" | "Ocean" | "Impassable"

export type NationDef = {
	name: string,
	x: number,
	y: number,
	flag: string,
}

export type MapData = {
	id: string,
	name: string,
	w: number,
	h: number,
	tag: string,
	subtitle: string,
	theme: string,
	landTiles: number,
	impassableTiles: number,
	maskB64: string,
	elevB64: string?,
	impB64: string?,
	nations: { NationDef },
}

local GameTypes = {}

GameTypes.UnitType = {
	City = "City",
	Port = "Port",
	Factory = "Factory",
	DefensePost = "DefensePost",
	MissileSilo = "MissileSilo",
	SAMLauncher = "SAMLauncher",
	AtomBomb = "AtomBomb",
	HydrogenBomb = "HydrogenBomb",
	MIRV = "MIRV",
	MIRVWarhead = "MIRVWarhead",
	Warship = "Warship",
	TransportShip = "TransportShip",
	TradeShip = "TradeShip",
	Train = "Train",
	Shell = "Shell",
	SAMMissile = "SAMMissile",
}

GameTypes.PlayerType = {
	Human = "Human",
	Bot = "Bot",
	Nation = "Nation",
}

GameTypes.TerrainType = {
	Ocean = "Ocean",
	Land = "Land",
	Shoreline = "Shoreline",
	Impassable = "Impassable",
}

return GameTypes
