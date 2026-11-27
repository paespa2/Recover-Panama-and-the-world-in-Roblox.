--!nonstrict
-- WorldGrid.lua
-- Genera mapas de celdas (estilo RoWorld / OpenFront) con la forma REAL de los continentes de la Tierra
-- (polígonos lon/lat rasterizados) y otros mundos (Pangea, Marte, Luna, Venus, Galaxia de Andrómeda).
-- Es determinista: servidor y cliente obtienen la misma máscara de tierra.

local WorldGrid = {}

WorldGrid.W = 960
WorldGrid.H = 400
local W, H = WorldGrid.W, WorldGrid.H
local LAT_TOP, LAT_BOT = 84, -60

-- ============================================================================
-- DEFINICIÓN DE MUNDOS
-- ============================================================================
WorldGrid.PLANETS = {
	EARTH = {
		id = "EARTH",
		name = "Tierra (Globo Terráqueo)",
		icon = "🌍",
		kind = "earth",
		ocean = { 14, 58, 110 },
		mid = { 24, 82, 138 },
		shallow = { 46, 118, 176 },
	},
	PANGEA = {
		id = "PANGAEA",
		name = "Pangea (Supercontinente)",
		icon = "🦖",
		kind = "frontwars",
		mapId = "pangaea",
		ocean = { 12, 66, 92 },
		mid = { 22, 92, 118 },
		shallow = { 44, 134, 150 },
		landA = { 112, 156, 74 },
		landB = { 186, 156, 98 },
	},
	PANGAEA = {
		id = "PANGAEA",
		name = "Pangea (Supercontinente)",
		icon = "🦖",
		kind = "frontwars",
		mapId = "pangaea",
		ocean = { 12, 66, 92 },
		mid = { 22, 92, 118 },
		shallow = { 44, 134, 150 },
		landA = { 112, 156, 74 },
		landB = { 186, 156, 98 },
	},
	MARS = {
		id = "MARS",
		name = "Marte (Planeta Rojo)",
		icon = "🔴",
		kind = "frontwars",
		mapId = "mars",
		ocean = { 46, 20, 18 },
		mid = { 66, 30, 24 },
		shallow = { 92, 44, 30 },
		landA = { 190, 94, 56 },
		landB = { 146, 68, 44 },
	},
	MOON = {
		id = "MOON",
		name = "La Luna (Selene)",
		icon = "🌕",
		kind = "noise",
		seed = 23,
		style = "moon",
		freq = 2.5,
		thr = 0.07,
		ocean = { 22, 24, 32 },
		mid = { 34, 36, 48 },
		shallow = { 52, 54, 68 },
		landA = { 176, 176, 180 },
		landB = { 130, 130, 138 },
	},
	VENUS = {
		id = "VENUS",
		name = "Venus (Nubes de Ácido)",
		icon = "🟠",
		kind = "noise",
		seed = 37,
		style = "venus",
		freq = 1.5,
		thr = 0.0,
		ocean = { 104, 46, 18 },
		mid = { 134, 64, 24 },
		shallow = { 170, 96, 34 },
		landA = { 230, 172, 74 },
		landB = { 196, 130, 52 },
	},
	ANDROMEDA = {
		id = "ANDROMEDA",
		name = "Galaxia de Andrómeda (M31)",
		icon = "🌌",
		kind = "galaxy",
		ocean = { 6, 5, 22 },
		mid = { 14, 10, 42 },
		shallow = { 34, 22, 78 },
		landA = { 255, 232, 176 },
		landB = { 150, 120, 255 },
	},
	WORLD = {
		id = "WORLD",
		name = "Mundo FrontWars (61 Naciones)",
		icon = "🌐",
		kind = "frontwars",
		mapId = "world",
		ocean = { 14, 58, 110 },
		mid = { 24, 82, 138 },
		shallow = { 46, 118, 176 },
	},
	EUROPE = {
		id = "EUROPE",
		name = "Europa FrontWars (49 Naciones)",
		icon = "🏰",
		kind = "frontwars",
		mapId = "europe",
		ocean = { 18, 54, 104 },
		mid = { 30, 78, 132 },
		shallow = { 50, 112, 168 },
	},
	ASIA = {
		id = "ASIA",
		name = "Asia FrontWars (25 Naciones)",
		icon = "🏯",
		kind = "frontwars",
		mapId = "asia",
		ocean = { 16, 62, 115 },
		mid = { 28, 86, 142 },
		shallow = { 48, 122, 180 },
	},
	AFRICA = {
		id = "AFRICA",
		name = "África FrontWars (36 Naciones)",
		icon = "🦁",
		kind = "frontwars",
		mapId = "africa",
		ocean = { 14, 60, 112 },
		mid = { 26, 84, 140 },
		shallow = { 46, 120, 178 },
	},
	MENA = {
		id = "MENA",
		name = "Medio Oriente FrontWars (35 Naciones)",
		icon = "🏜️",
		kind = "frontwars",
		mapId = "mena",
		ocean = { 18, 64, 118 },
		mid = { 32, 88, 146 },
		shallow = { 52, 126, 184 },
	},
	OCEANIA = {
		id = "OCEANIA",
		name = "Oceanía FrontWars (32 Naciones)",
		icon = "🏝️",
		kind = "frontwars",
		mapId = "oceania",
		ocean = { 12, 70, 124 },
		mid = { 24, 96, 154 },
		shallow = { 48, 136, 196 },
	},
	ACHIRAN = {
		id = "ACHIRAN",
		name = "Achiran OpenFront (Competitivo)",
		icon = "⚔️",
		kind = "frontwars",
		mapId = "achiran",
		ocean = { 71, 133, 181 },
	},
	BAIKAL = {
		id = "BAIKAL",
		name = "Baikal OpenFront (Guerra Nuclear)",
		icon = "☢️",
		kind = "frontwars",
		mapId = "baikal",
		ocean = { 71, 133, 181 },
	},
}

WorldGrid.PLANET_ORDER = {
	"WORLD",
	"ACHIRAN",
	"EUROPE",
	"ASIA",
	"AFRICA",
	"PANGAEA",
	"MARS",
	"OCEANIA",
	"MENA",
	"BAIKAL",
	"EARTH",
	"MOON",
	"VENUS",
	"ANDROMEDA",
}

-- Alias insensibles a mayúsculas para compatibilidad total con OpenFront
WorldGrid.PLANETS.world = WorldGrid.PLANETS.WORLD
WorldGrid.PLANETS.achiran = WorldGrid.PLANETS.ACHIRAN
WorldGrid.PLANETS.europe = WorldGrid.PLANETS.EUROPE
WorldGrid.PLANETS.asia = WorldGrid.PLANETS.ASIA
WorldGrid.PLANETS.africa = WorldGrid.PLANETS.AFRICA
WorldGrid.PLANETS.pangaea = WorldGrid.PLANETS.PANGAEA
WorldGrid.PLANETS.pangea = WorldGrid.PLANETS.PANGAEA
WorldGrid.PLANETS.mars = WorldGrid.PLANETS.MARS
WorldGrid.PLANETS.oceania = WorldGrid.PLANETS.OCEANIA
WorldGrid.PLANETS.mena = WorldGrid.PLANETS.MENA
WorldGrid.PLANETS.baikal = WorldGrid.PLANETS.BAIKAL
WorldGrid.PLANETS.earth = WorldGrid.PLANETS.EARTH

-- ============================================================================
-- POLÍGONOS DE LA TIERRA (lon, lat, lon, lat, ...)
-- ============================================================================
local EARTH_LAND = {
	-- Norteamérica
	{
		-168,
		65,
		-163,
		69,
		-156,
		71.5,
		-141,
		70,
		-128,
		70,
		-115,
		68,
		-105,
		68,
		-95,
		71,
		-88,
		68,
		-83,
		67,
		-82,
		63,
		-88,
		64,
		-94,
		60,
		-93,
		57,
		-88,
		56,
		-82,
		55,
		-80,
		52,
		-79,
		55,
		-78,
		58,
		-77,
		62,
		-73,
		62,
		-69,
		60,
		-65,
		60,
		-61,
		56,
		-57,
		53,
		-56,
		52,
		-60,
		49,
		-65,
		48,
		-66,
		45,
		-70,
		43.5,
		-70,
		42,
		-74,
		40.5,
		-76,
		38,
		-76,
		35,
		-80,
		32,
		-81,
		30,
		-80,
		26,
		-81,
		25,
		-82,
		27,
		-83,
		30,
		-85,
		30,
		-89,
		30,
		-94,
		29.5,
		-97,
		27,
		-97.5,
		24,
		-97.5,
		21,
		-96,
		19,
		-94,
		18,
		-91,
		18.5,
		-90.5,
		21,
		-87,
		21,
		-87.5,
		18,
		-88,
		15.8,
		-84,
		15,
		-83.5,
		11,
		-83,
		9,
		-81,
		8.5,
		-79,
		9.5,
		-77.5,
		8,
		-78,
		7.2,
		-80,
		7.5,
		-82,
		8,
		-85.5,
		10,
		-87.5,
		13,
		-92,
		14.5,
		-94.5,
		16,
		-97,
		15.8,
		-101,
		17.3,
		-105.5,
		20,
		-105.5,
		22.5,
		-108,
		25,
		-110,
		27.5,
		-112.8,
		31,
		-114.8,
		31.7,
		-117,
		32.5,
		-118.5,
		34,
		-121,
		35,
		-122.5,
		37.5,
		-124,
		40.5,
		-124,
		43,
		-124,
		46.5,
		-124.5,
		48.5,
		-127,
		50.5,
		-130,
		54,
		-133,
		57,
		-137,
		59,
		-141,
		60,
		-146,
		60.5,
		-150,
		59.5,
		-152,
		58,
		-155,
		57,
		-158,
		56.5,
		-162,
		55,
		-165,
		54.5,
		-161,
		57.5,
		-158,
		58.5,
		-162,
		60,
		-165,
		62,
		-166,
		64,
	},
	-- Groenlandia
	{
		-73,
		78,
		-66,
		81,
		-50,
		83,
		-30,
		83.5,
		-20,
		81.5,
		-18,
		77,
		-20,
		72,
		-26,
		69,
		-34,
		66,
		-40,
		64,
		-43,
		60,
		-48,
		61,
		-52,
		64,
		-54,
		68,
		-58,
		72,
		-66,
		76,
	},
	-- Islandia
	{ -24, 64, -22, 63.5, -18, 63.4, -14, 64.5, -14, 66, -17, 66.5, -22, 66.4 },
	-- Isla de Baffin, Victoria, Ellesmere, Terranova
	{ -80, 73.5, -72, 72, -66, 70, -62, 66.5, -64, 63, -68, 62, -74, 64, -77, 67.5, -80, 69 },
	{ -118, 72, -108, 73, -101, 71, -102, 69, -110, 68.5, -117, 69.5 },
	{ -92, 77, -80, 76, -70, 78.5, -62, 82, -75, 83, -88, 81.5 },
	{ -59, 47.5, -53, 46.7, -52.8, 49, -55.5, 51.5, -58, 50 },
	-- Cuba y La Española
	{ -84.5, 22, -82, 23, -79, 22.5, -75, 20.5, -74.2, 20, -77.5, 19.8, -80, 21.5 },
	{ -74.4, 19.8, -71, 19.9, -68.5, 18.8, -69.5, 18.2, -72, 18, -74.3, 18.4 },
	-- Sudamérica
	{
		-77.5,
		8.5,
		-75,
		11,
		-72,
		12,
		-68,
		10.7,
		-64,
		10.6,
		-61,
		10,
		-60,
		8.5,
		-57,
		6,
		-52,
		5,
		-50.5,
		1.5,
		-50,
		-0.5,
		-46,
		-1.5,
		-42,
		-2.8,
		-38,
		-4,
		-35,
		-5.5,
		-34.8,
		-8,
		-36,
		-10.5,
		-38.5,
		-13,
		-39,
		-17,
		-40,
		-20,
		-41,
		-22,
		-44,
		-23,
		-48,
		-26,
		-48.7,
		-28.5,
		-51,
		-31,
		-53,
		-34,
		-56,
		-34.8,
		-57,
		-36.5,
		-57.5,
		-38.5,
		-62,
		-39,
		-63,
		-41,
		-65,
		-42,
		-64.5,
		-45,
		-66.5,
		-47,
		-67.5,
		-50,
		-68.5,
		-52.5,
		-70,
		-53.5,
		-73,
		-53.5,
		-75,
		-50,
		-74,
		-45,
		-73.5,
		-40,
		-73.5,
		-37,
		-71.7,
		-33,
		-71.5,
		-30,
		-70.5,
		-25,
		-70,
		-19,
		-71,
		-17.5,
		-76,
		-14,
		-78,
		-10,
		-81,
		-6,
		-81,
		-3,
		-80,
		-1,
		-80,
		1,
		-78.5,
		2,
		-78,
		5,
		-77.5,
		7,
	},
	-- África
	{
		-17,
		21,
		-16.2,
		24,
		-13,
		27.8,
		-10,
		29.5,
		-9.5,
		32,
		-6.5,
		34,
		-5.5,
		35.8,
		-2,
		35.2,
		1,
		36.5,
		5,
		36.8,
		10,
		37.2,
		11,
		35,
		10.5,
		33.5,
		15,
		32.5,
		19,
		30.5,
		20,
		32,
		22,
		32.8,
		25,
		31.7,
		29,
		30.8,
		32,
		31.2,
		33,
		29,
		34.8,
		27.8,
		35.5,
		24.5,
		37,
		21,
		38.5,
		18,
		40,
		15.5,
		43,
		12.5,
		44.5,
		10.5,
		48,
		11.2,
		51,
		12,
		51,
		10.5,
		49,
		6,
		47,
		3,
		44,
		0.5,
		41.5,
		-2,
		40,
		-5,
		39.5,
		-8,
		40.5,
		-11,
		40.5,
		-15,
		38,
		-17.5,
		35.5,
		-21,
		35.5,
		-24,
		33,
		-26,
		32.5,
		-28.5,
		31,
		-30,
		28,
		-32.7,
		25.5,
		-34,
		21,
		-34.8,
		18.5,
		-34,
		17.8,
		-31,
		16,
		-28.5,
		15,
		-26,
		14.5,
		-22,
		12,
		-18,
		11.8,
		-15.5,
		13.5,
		-12,
		13.2,
		-9,
		12,
		-6,
		12,
		-5,
		9.5,
		-2,
		9.2,
		0,
		9.8,
		3.5,
		8.5,
		4.5,
		6,
		4.2,
		4,
		6.2,
		1,
		5.8,
		-2,
		4.8,
		-4.5,
		5.2,
		-7.5,
		4.4,
		-9,
		5.2,
		-11.5,
		7.2,
		-13.2,
		9,
		-15,
		10.8,
		-16.7,
		12.5,
		-17.2,
		14.7,
	},
	-- Madagascar
	{
		43.5,
		-23,
		44.5,
		-25,
		47,
		-25.2,
		47.5,
		-24,
		48.5,
		-21,
		49.5,
		-17,
		50.3,
		-15.2,
		49.3,
		-12,
		48.2,
		-13.5,
		44.2,
		-16.5,
		43.8,
		-20,
	},
	-- Eurasia
	{
		-9,
		37,
		-8.8,
		40,
		-9.3,
		43,
		-7,
		43.7,
		-2,
		43.4,
		-1.3,
		46,
		-2.5,
		47.3,
		-4.7,
		48.2,
		-1.5,
		48.7,
		-1.3,
		49.7,
		1.5,
		50.8,
		3,
		51.3,
		4.5,
		52.8,
		5,
		53.5,
		8.5,
		53.8,
		8.5,
		55.5,
		8,
		57,
		10.3,
		57.7,
		10.5,
		56,
		9.8,
		55,
		12,
		54.2,
		14,
		54,
		18,
		54.8,
		20,
		54.5,
		21,
		56,
		21.5,
		57.5,
		24,
		57,
		24.3,
		59.3,
		28,
		59.5,
		30,
		60,
		25,
		60.4,
		21.5,
		60.5,
		21.5,
		62.5,
		25,
		65,
		22,
		65.8,
		21.5,
		64,
		17.5,
		62,
		17.2,
		60.5,
		18.5,
		59.5,
		16.5,
		57,
		16,
		56,
		14,
		55.5,
		12.8,
		55.8,
		11.8,
		58,
		10,
		59,
		8,
		58,
		5.5,
		59,
		5,
		61.5,
		8,
		63.5,
		12,
		66,
		15,
		68.5,
		19,
		70,
		25,
		71,
		30,
		70.3,
		33,
		69.5,
		41,
		67,
		40,
		66,
		35,
		66.2,
		40,
		65,
		44,
		66,
		44,
		68,
		50,
		68,
		53,
		68.5,
		58,
		68.5,
		60,
		69.5,
		67,
		69,
		68,
		71,
		73,
		72.5,
		75,
		72.5,
		80,
		73,
		87,
		75.5,
		100,
		76.5,
		105,
		77.5,
		112,
		76,
		113,
		74,
		120,
		73,
		128,
		72.5,
		130,
		71,
		140,
		72.5,
		150,
		71.2,
		160,
		70,
		170,
		70,
		180,
		69,
		180,
		65,
		176,
		64.5,
		178,
		62.5,
		173,
		61,
		170,
		60,
		165,
		60,
		163,
		58,
		162.5,
		56,
		160,
		54,
		156,
		51,
		155.5,
		55,
		157,
		57.5,
		160,
		61,
		156,
		61.5,
		152,
		59.2,
		145,
		59.3,
		142,
		59,
		137,
		54,
		140,
		53,
		141,
		51,
		140,
		48,
		135.5,
		44,
		132,
		42.8,
		130,
		42.5,
		129.5,
		40,
		128,
		38,
		129.3,
		36,
		126.5,
		34.5,
		126.5,
		37,
		125,
		38,
		125,
		39.7,
		121.5,
		39,
		122,
		40.5,
		119,
		39.2,
		118,
		38,
		120.5,
		36.5,
		121.5,
		36.8,
		119,
		35,
		121,
		33,
		122,
		31,
		122,
		29,
		120.5,
		27,
		119,
		25.3,
		116.5,
		22.8,
		113,
		22,
		110.5,
		21.3,
		108,
		21.5,
		106.5,
		19,
		108.5,
		15.5,
		109.2,
		12,
		107,
		10.4,
		105,
		8.7,
		104.5,
		10.3,
		103,
		10.7,
		100.8,
		12.8,
		100.2,
		13.5,
		99.5,
		10,
		100.3,
		7,
		101.5,
		6.5,
		103.4,
		4,
		103.5,
		1.5,
		102,
		2.5,
		100.5,
		4.5,
		98.5,
		8,
		98.3,
		12,
		97.8,
		16.5,
		94.5,
		16,
		94,
		19,
		92.5,
		20.5,
		91.5,
		22.5,
		89,
		22,
		86.5,
		20,
		84.5,
		18.5,
		82,
		16.5,
		80.3,
		15.5,
		80.2,
		12.5,
		79.8,
		10,
		78,
		8.3,
		77,
		8.5,
		76,
		10.5,
		74.5,
		13.5,
		73.2,
		17,
		72.8,
		19.5,
		72.5,
		21,
		70.5,
		20.8,
		69,
		22.3,
		70.5,
		23.5,
		68.3,
		23.6,
		67,
		24.8,
		64.5,
		25.2,
		61.5,
		25.1,
		57.5,
		25.7,
		56.8,
		27.2,
		54.5,
		26.5,
		51.5,
		27.8,
		50.5,
		29.5,
		48.5,
		30,
		48,
		29.5,
		49.5,
		27.3,
		50.5,
		25.5,
		51.5,
		24.5,
		54,
		24,
		56.2,
		26,
		56.5,
		24.5,
		59.8,
		22.5,
		58.5,
		20.5,
		55.5,
		17.8,
		52.5,
		16.2,
		49,
		14.5,
		45,
		12.8,
		43.2,
		13.3,
		42.8,
		16,
		41,
		19,
		39,
		21.5,
		36.8,
		25.5,
		35,
		28.5,
		34.5,
		29.7,
		34.9,
		31.5,
		35.5,
		33.5,
		36,
		36.2,
		34.5,
		36.7,
		32,
		36.2,
		30,
		36.3,
		28,
		36.8,
		27.2,
		38.4,
		26.2,
		39.5,
		26.6,
		40.4,
		28.5,
		41,
		29.1,
		41.2,
		26,
		40.8,
		24,
		40.8,
		23.5,
		40.3,
		24,
		38.5,
		23,
		36.5,
		21.8,
		36.7,
		21.3,
		38.3,
		20,
		39.5,
		19.5,
		41.5,
		18.5,
		42.4,
		16,
		43.5,
		14,
		45,
		13.5,
		45.7,
		12.3,
		45.3,
		12.5,
		44,
		14,
		42.5,
		16,
		41.8,
		18.5,
		40.2,
		17,
		39,
		16.5,
		38,
		15.8,
		38,
		16,
		39.5,
		15,
		40.2,
		12.5,
		41.5,
		10.5,
		43,
		8.8,
		44.4,
		7,
		43.8,
		4.5,
		43.4,
		3,
		42.3,
		3.2,
		41.8,
		0.8,
		41,
		-0.3,
		39.5,
		-0.5,
		38.5,
		-2,
		36.8,
		-5.4,
		36.1,
		-6.3,
		36.8,
		-7.5,
		37.2,
	},
	-- Gran Bretaña, Irlanda
	{
		-5.7,
		50,
		-3,
		50.5,
		1.3,
		51,
		1.7,
		52.7,
		0,
		53.5,
		-1.5,
		55,
		-2,
		56.8,
		-1.8,
		57.6,
		-3.5,
		58.6,
		-5,
		58.6,
		-6,
		57.5,
		-5.5,
		56,
		-5,
		55,
		-3,
		54.8,
		-3,
		53.5,
		-4.5,
		53.3,
		-4.3,
		52,
		-5.2,
		51.7,
		-3.5,
		51.3,
		-5,
		50.5,
	},
	{ -10, 51.8, -6.3, 52, -6, 53.5, -5.7, 54.8, -7.3, 55.3, -9, 54.2, -10.2, 53.5 },
	-- Japón, Sajalín, Taiwán, Sri Lanka
	{
		130.9,
		33.9,
		132.5,
		35.5,
		135.5,
		35.7,
		137,
		37,
		139.5,
		38.2,
		140,
		40.5,
		141.5,
		41,
		142,
		39.5,
		141,
		37,
		140.7,
		35.5,
		139.8,
		35,
		137.5,
		34.5,
		135.5,
		33.5,
		134,
		34.3,
		132,
		34,
	},
	{ 129.8, 33, 131.8, 33.5, 131.5, 31, 130.3, 31.2 },
	{ 140, 41.5, 141.8, 43.2, 145, 43.5, 145.5, 44.2, 142, 45.5, 141.5, 44, 140.2, 43 },
	{ 142, 46, 143.5, 49, 143.5, 53.5, 142, 54, 141.8, 50 },
	{ 120.2, 22.8, 121.8, 25, 121.5, 22 },
	{ 79.8, 9.5, 81.8, 7.5, 81, 6, 80, 6.5 },
	-- Sumatra, Java, Borneo, Célebes, Nueva Guinea, Filipinas
	{ 95.3, 5.5, 98, 4, 100.5, 2, 103.5, -1, 106, -3, 105.8, -5.8, 103, -4.5, 100.5, -2, 98.5, 0.5, 96.5, 3.5 },
	{ 105.2, -6.8, 108, -6.5, 112.5, -6.8, 114.5, -7.8, 114.3, -8.7, 110, -8.2, 106.5, -7.5 },
	{
		109,
		1.8,
		111,
		1.5,
		113.5,
		3.2,
		115.5,
		5,
		117.7,
		6.8,
		119,
		5.2,
		118,
		2.5,
		117.8,
		1,
		116.5,
		-1.5,
		116.2,
		-3.8,
		114,
		-4,
		111.5,
		-3,
		110,
		-1.5,
	},
	{
		119.5,
		-5,
		120.5,
		-3,
		120,
		-1,
		121,
		1,
		123,
		0.8,
		125,
		1.5,
		122.5,
		-0.5,
		123,
		-2,
		121.8,
		-4.5,
		121,
		-3,
		120.5,
		-5.5,
	},
	{
		131,
		-0.8,
		134,
		-0.8,
		135,
		-3.3,
		138,
		-1.8,
		141,
		-2.6,
		145,
		-4.5,
		147.5,
		-6.2,
		148,
		-8.5,
		150.5,
		-10.5,
		147,
		-10,
		144,
		-7.8,
		141,
		-9,
		138,
		-8,
		137,
		-5.5,
		134,
		-4,
		132.5,
		-3,
	},
	{ 120.3, 18.5, 122.2, 18.4, 122, 16, 124, 13, 122, 13.5, 121, 14, 120, 15 },
	{ 122, 7.5, 124, 8.8, 126.5, 7.5, 125.5, 6, 123.5, 7 },
	-- Australia, Tasmania, Nueva Zelanda
	{
		113.5,
		-22,
		114,
		-26,
		115,
		-30,
		115,
		-34,
		118,
		-35,
		122,
		-34,
		124,
		-33.3,
		129,
		-31.5,
		132,
		-32,
		135,
		-34.7,
		137.5,
		-33,
		139,
		-35.5,
		140.5,
		-38,
		144,
		-38.2,
		146.5,
		-39,
		148.5,
		-37.8,
		150,
		-37,
		151.2,
		-34,
		153,
		-31,
		153.5,
		-27,
		152.5,
		-25,
		150.5,
		-22.5,
		148.5,
		-20,
		146,
		-18.5,
		145.3,
		-15,
		143.5,
		-14,
		142.5,
		-10.8,
		141.5,
		-13,
		141.5,
		-17,
		140,
		-17.7,
		138,
		-16,
		136,
		-15,
		136.5,
		-12,
		132.5,
		-11.5,
		130.5,
		-12.5,
		129.5,
		-15,
		127,
		-14,
		125,
		-15,
		123.5,
		-17,
		122,
		-18,
		121,
		-19.5,
		118,
		-20.5,
		116,
		-20.7,
	},
	{ 145.3, -40.8, 148.3, -41, 147.8, -43.2, 146, -43.5 },
	{ 172.8, -34.5, 175.5, -36.5, 178.5, -37.7, 177, -39.3, 175, -41.5, 174.8, -39.5, 173.8, -39, 174.5, -37 },
	{ 172.7, -40.6, 174.3, -41.7, 172.5, -43.7, 170.5, -46, 166.7, -46, 168, -44, 171, -42.5 },
	-- Svalbard, Nueva Zembla, Tierra del Norte
	{ 11, 78.5, 17, 76.7, 27, 78, 22, 80.2, 14, 80 },
	{ 52, 71, 56, 70.8, 60, 75, 68, 76.8, 62, 76, 55, 73 },
	{ 95, 79, 100, 79.5, 104, 78.5, 98, 78 },
}

-- Mares interiores que se restan a la tierra
local EARTH_SEAS = {
	-- Mar Negro
	{
		28,
		41.8,
		28.5,
		44,
		29.8,
		45.2,
		31,
		46.6,
		33,
		46,
		33.5,
		44.5,
		35.5,
		45.2,
		37,
		45,
		38,
		47,
		39.5,
		46.5,
		40,
		43.8,
		41.5,
		42,
		41.8,
		41.5,
		39,
		41,
		36,
		41.7,
		33,
		42,
		31,
		41.2,
		29.5,
		41.2,
	},
	-- Mar Caspio
	{ 47, 45, 49, 46.5, 51, 47, 53, 45.5, 53.5, 42, 54, 40, 53, 37, 50.5, 37, 49, 38.5, 49.5, 40.5, 47.5, 42.5 },
}

local PANGEA_POLY = {
	-85,
	50,
	-60,
	68,
	-20,
	74,
	30,
	76,
	80,
	70,
	125,
	60,
	140,
	35,
	120,
	10,
	100,
	-15,
	60,
	-40,
	20,
	-52,
	-20,
	-48,
	-55,
	-35,
	-70,
	-10,
	-80,
	15,
	-95,
	30,
}

-- ============================================================================
-- UTILIDADES
-- ============================================================================
local function fillPolygon(mask, poly, value)
	local n = #poly // 2
	for y = 0, H - 1 do
		local lat = LAT_TOP - (y + 0.5) * (LAT_TOP - LAT_BOT) / H
		local xs = {}
		for i = 1, n do
			local j = (i % n) + 1
			local lon1, lat1 = poly[i * 2 - 1], poly[i * 2]
			local lon2, lat2 = poly[j * 2 - 1], poly[j * 2]
			if (lat1 <= lat and lat2 > lat) or (lat2 <= lat and lat1 > lat) then
				local t = (lat - lat1) / (lat2 - lat1)
				table.insert(xs, lon1 + t * (lon2 - lon1))
			end
		end
		table.sort(xs)
		for k = 1, #xs - 1, 2 do
			local x0 = math.ceil((xs[k] + 180) / 360 * W - 0.5)
			local x1 = math.floor((xs[k + 1] + 180) / 360 * W - 0.5)
			for x = math.max(0, x0), math.min(W - 1, x1) do
				buffer.writeu8(mask, y * W + x, value)
			end
		end
	end
end

local function cylNoise(x, y, freq, seed)
	local theta = (x / W) * math.pi * 2
	local nx = math.cos(theta) * freq
	local nz = math.sin(theta) * freq
	local ny = (y / H) * 2.4 * freq
	return math.noise(nx + seed, ny, nz + seed * 0.37)
end

function WorldGrid.LatOfRow(y)
	return LAT_TOP - (y + 0.5) * (LAT_TOP - LAT_BOT) / H
end

-- Decodificador Base64 ultraligero y nativo para mapas de bits de FrontWars
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LUT = {}
for i = 1, #B64_CHARS do
	B64_LUT[string.byte(B64_CHARS, i)] = i - 1
end

local function decodeBase64ToBuffer(b64)
	local len = #b64
	local out = buffer.create(math.ceil(len * 3 / 4))
	local outPos = 0
	local i = 1
	while i <= len do
		local b1_raw = string.byte(b64, i)
		if not b1_raw then
			break
		end
		local c1 = B64_LUT[b1_raw] or 0
		local c2 = B64_LUT[string.byte(b64, i + 1) or 65] or 0
		local c3 = B64_LUT[string.byte(b64, i + 2) or 65] or 0
		local c4 = B64_LUT[string.byte(b64, i + 3) or 65] or 0
		i += 4

		local b1 = bit32.bor(bit32.lshift(c1, 2), bit32.rshift(c2, 4))
		local b2 = bit32.bor(bit32.lshift(bit32.band(c2, 15), 4), bit32.rshift(c3, 2))
		local b3 = bit32.bor(bit32.lshift(bit32.band(c3, 3), 6), c4)

		buffer.writeu8(out, outPos, b1)
		if outPos + 1 < buffer.len(out) then
			buffer.writeu8(out, outPos + 1, b2)
		end
		if outPos + 2 < buffer.len(out) then
			buffer.writeu8(out, outPos + 2, b3)
		end
		outPos += 3
	end
	return out
end

-- ============================================================================
-- GENERACIÓN DE LA MÁSCARA DE TIERRA
-- ============================================================================
function WorldGrid.Generate(planetId)
	local def = WorldGrid.PLANETS[planetId] or WorldGrid.PLANETS.EARTH
	local land = buffer.create(W * H)

	if def.kind == "earth" then
		for _, poly in ipairs(EARTH_LAND) do
			fillPolygon(land, poly, 1)
		end
		for _, poly in ipairs(EARTH_SEAS) do
			fillPolygon(land, poly, 0)
		end
	elseif def.kind == "pangea" then
		fillPolygon(land, PANGEA_POLY, 1)
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local i = y * W + x
				if buffer.readu8(land, i) == 1 and math.noise(x * 0.07, y * 0.09, 9.1) > 0.26 then
					buffer.writeu8(land, i, 0)
				end
			end
		end
	elseif def.kind == "noise" then
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local v = cylNoise(x, y, def.freq, def.seed) + 0.45 * cylNoise(x, y, def.freq * 2.6, def.seed + 5)
				if v > def.thr + 0.1 then
					buffer.writeu8(land, y * W + x, 1)
				end
			end
		end
	elseif def.kind == "galaxy" then
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local u = ((x + 0.5) / W) * 2 - 1
				local v = ((y + 0.5) / H) * 2 - 1
				local r = math.sqrt(u * u + v * v)
				local theta = math.atan2(v, u)
				local arm = 0.5 + 0.5 * math.cos(2 * (theta + 3.4 * math.log(r + 0.05)))
				local n = math.noise(x * 0.12, y * 0.2, 3.3)
				local isLand = false
				if r < 0.13 then
					isLand = true
				elseif r < 0.92 and arm > 0.55 and n > -0.18 then
					isLand = true
				end
				if isLand then
					buffer.writeu8(land, y * W + x, 1)
				end
			end
		end
	elseif def.kind == "frontwars" then
		-- Carga el mapa de pixeles autentico de OpenFront.io con resolucion nativa 1:1
		local fwmModule = script.Parent:FindFirstChild("frontwars_maps")
		if not fwmModule then
			local rs = game:GetService("ReplicatedStorage")
			local sh = rs:FindFirstChild("Shared")
			fwmModule = sh and sh:FindFirstChild("frontwars_maps")
		end
		local mapModule = fwmModule and fwmModule:FindFirstChild(def.mapId)
		local mapNations = nil
		local elevBuf = nil
		local impBuf = nil
		if mapModule then
			local mapData = require(mapModule)
			local maskBuf = decodeBase64ToBuffer(mapData.maskB64)
			W, H = mapData.w, mapData.h
			land = buffer.create(W * H)
			for i = 0, W * H - 1 do
				local byteVal = buffer.readu8(maskBuf, i // 8)
				local bit = bit32.band(bit32.rshift(byteVal, i % 8), 1)
				if bit == 1 then
					buffer.writeu8(land, i, 1)
				end
			end

			-- Decodificar elevación oficial por celdas (nibble 0-14)
			if mapData.elevB64 and #mapData.elevB64 > 0 then
				elevBuf = buffer.create(W * H)
				local packedElev = decodeBase64ToBuffer(mapData.elevB64)
				local landIdx = 0
				for i = 0, W * H - 1 do
					if buffer.readu8(land, i) == 1 then
						local bIdx = landIdx // 2
						if bIdx < buffer.len(packedElev) then
							local byteVal = buffer.readu8(packedElev, bIdx)
							local nibble = if landIdx % 2 == 0 then bit32.band(byteVal, 0x0f) else bit32.rshift(byteVal, 4)
							buffer.writeu8(elevBuf, i, nibble)
						end
						landIdx += 1
					end
				end
			end

			-- Decodificar máscara de montañas infranqueables (bits magnitud 31)
			if mapData.impB64 and #mapData.impB64 > 0 then
				impBuf = buffer.create(W * H)
				local packedImp = decodeBase64ToBuffer(mapData.impB64)
				for i = 0, W * H - 1 do
					local bIdx = i // 8
					if bIdx < buffer.len(packedImp) then
						local byteVal = buffer.readu8(packedImp, bIdx)
						local bit = bit32.band(bit32.rshift(byteVal, i % 8), 1)
						if bit == 1 then
							buffer.writeu8(impBuf, i, 1)
						end
					end
				end
			end
			mapNations = mapData.nations
		end

		local count = 0
		for i = 0, W * H - 1 do
			if buffer.readu8(land, i) == 1 then
				count += 1
			end
		end

		return {
			w = W,
			h = H,
			land = land,
			landCount = count,
			def = def,
			elev = elevBuf,
			impassable = impBuf,
			nations = mapNations,
		}
	end

	local count = 0
	for i = 0, W * H - 1 do
		if buffer.readu8(land, i) == 1 then
			count += 1
		end
	end

	return { w = W, h = H, land = land, landCount = count, def = def }
end

-- ============================================================================
-- TEXTURA BASE (colores del terreno y del océano) -> buffer RGB (3 bytes por celda)
-- ============================================================================
local function lerp(a, b, t)
	return a + (b - a) * t
end

local function mix3(c1, c2, t)
	return lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t), lerp(c1[3], c2[3], t)
end

local function earthLandColor(x, y)
	local realLat = WorldGrid.LatOfRow(y)
	local lat = math.abs(realLat)
	local lon = (x / W) * 360 - 180

	local r, g, b = 68, 142, 64 -- Llanuras y valles templados fértiles por defecto

	-- Ruido orgánico para contornos naturales de biomas y cordilleras
	local bioNoise = math.noise(x * 0.035, y * 0.045, 2.1) * 4.5
	local ridgeNoise = math.noise(x * 0.14, y * 0.14, 4.3)

	-- 1. Casquetes polares y tundra helada
	if lat > (68 + bioNoise) or realLat < -58 then
		r, g, b = 236, 244, 252 -- Nieve y hielo glaciar
	elseif lat > (54 + bioNoise) then
		r, g, b = 46, 102, 54 -- Bosques boreales y taiga de Canadá y Siberia

	-- 2. Cordilleras montañosas naturales (crestas rocosas y picos nevados)
	-- Cordillera de los Andes (Sudamérica)
	elseif lon >= -78 and lon <= -67 and realLat >= -54 and realLat <= 8 and ridgeNoise > 0.18 then
		r, g, b = 142, 138, 148 -- Picos rocosos de los Andes
		if ridgeNoise > 0.42 then
			r, g, b = 232, 238, 246 -- Cumbres nevadas
		end
	-- Cordillera del Himalaya (Norte de India / Tíbet)
	elseif lon >= 74 and lon <= 98 and realLat >= 27 and realLat <= 36 and ridgeNoise > 0.16 then
		r, g, b = 148, 142, 152
		if ridgeNoise > 0.38 then
			r, g, b = 238, 244, 252 -- Everest y nieves eternas
		end
	-- Montañas Rocosas (Norteamérica)
	elseif lon >= -122 and lon <= -106 and realLat >= 34 and realLat <= 58 and ridgeNoise > 0.22 then
		r, g, b = 140, 136, 144
		if ridgeNoise > 0.45 then
			r, g, b = 226, 232, 242
		end
	-- Alpes (Europa)
	elseif lon >= 6 and lon <= 16 and realLat >= 44 and realLat <= 48 and ridgeNoise > 0.15 then
		r, g, b = 152, 148, 156
		if ridgeNoise > 0.4 then
			r, g, b = 232, 238, 246
		end

	-- 3. Desiertos y dunas doradas
	-- Desierto del Sahara y Península Arábiga
	elseif realLat >= (14 + bioNoise) and realLat <= (32 + bioNoise) and lon >= -17 and lon <= 56 then
		r, g, b = 228, 196, 124 -- Arena dorada del Sahara y Arabia
	-- Desierto de Gobi (Asia)
	elseif realLat >= (38 + bioNoise) and realLat <= (46 + bioNoise) and lon >= 92 and lon <= 116 then
		r, g, b = 212, 184, 120
	-- Outback Australiano
	elseif realLat >= (-32 + bioNoise) and realLat <= (-18 + bioNoise) and lon >= 118 and lon <= 142 then
		r, g, b = 216, 144, 86 -- Tierra roja y ocre del interior de Australia
	-- Desierto de Atacama
	elseif realLat >= -28 and realLat <= -18 and lon >= -72 and lon <= -68 then
		r, g, b = 214, 180, 125

	-- 4. Selvas tropicales densas y cuencas fluviales
	-- Cuenca del Amazonas (Sudamérica)
	elseif realLat >= (-14 + bioNoise) and realLat <= (5 + bioNoise) and lon >= -75 and lon <= -48 then
		r, g, b = 24, 128, 48 -- Verde esmeralda profundo de la selva amazónica
	-- Istmo de Panamá y Centroamérica
	elseif realLat >= 7 and realLat <= 12 and lon >= -84 and lon <= -77 then
		r, g, b = 30, 140, 54 -- Selva tropical y canales de Panamá
	-- Cuenca del Congo (África Central)
	elseif realLat >= (-6 + bioNoise) and realLat <= (6 + bioNoise) and lon >= 12 and lon <= 30 then
		r, g, b = 26, 124, 46
	-- Sudeste Asiático e Indonesia
	elseif realLat >= (-10 + bioNoise) and realLat <= (18 + bioNoise) and lon >= 95 and lon <= 145 then
		r, g, b = 28, 132, 50

	-- 5. Sabanas y estepas templadas
	elseif lat > 12 and lat <= 38 then
		local d = math.noise(x * 0.08, y * 0.1, 2.2)
		if d > 0.1 then
			r, g, b = 186, 176, 106 -- Estepa seca
		else
			r, g, b = 92, 158, 68 -- Sabana / Llanuras
		end
	else
		-- Valles templados
		r, g, b = 62, 140, 58
	end

	return r, g, b
end

-- Imagen satelital real (generada por tools/fetch_satellite.py -> TerrainData.lua). Si no existe, se usa el relieve procedural.
local function loadSatellite()
	local mod = script.Parent:FindFirstChild("TerrainData")
	if not mod then
		return nil
	end
	local okReq, data = pcall(require, mod)
	if not okReq then
		warn("[WorldGrid] TerrainData no se pudo cargar:", data)
		return nil
	end
	local okBuf, buf = pcall(data.GetBuffer)
	if okBuf and buf and buffer.len(buf) == W * H * 3 then
		return buf
	end
	warn("[WorldGrid] TerrainData invalido:", buf)
	return nil
end

-- Relieve de los planetas procedurales (Marte, Luna, Venus): elevación en 3 octavas + rasgos propios de cada mundo
local planetElev = nil -- u8 por celda (0..255)

local function elevAt(x, y)
	return buffer.readu8(planetElev, math.clamp(y, 0, H - 1) * W + (x % W))
end

local function computeElevation(def)
	local e = buffer.create(W * H)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local v = 0.55 * cylNoise(x, y, def.freq * 1.3, def.seed + 2)
				+ 0.3 * cylNoise(x, y, def.freq * 3.1, def.seed + 9)
				+ 0.15 * cylNoise(x, y, def.freq * 7.0, def.seed + 17)
			buffer.writeu8(e, y * W + x, math.clamp(math.floor((v + 0.6) / 1.2 * 255), 0, 255))
		end
	end
	return e
end

local function planetPixel(def, x, y)
	local r, g, b = mix3(def.landB, def.landA, elevAt(x, y) / 255)
	local style = def.style
	if style == "mars" then
		-- Cañón largo y oscuro (estilo Valles Marineris) y casquetes polares helados
		if math.abs(cylNoise(x, y, def.freq * 0.8, def.seed + 50)) < 0.035 then
			r, g, b = r * 0.55, g * 0.5, b * 0.5
		end
		local pole = math.max(0, 1 - math.min(y, H - 1 - y) / (H * 0.07))
		if pole > 0 then
			r, g, b = lerp(r, 238, pole), lerp(g, 226, pole), lerp(b, 232, pole)
		end
	elseif style == "moon" then
		-- Mares basálticos oscuros y cráteres con borde marcado
		local maria = cylNoise(x, y, def.freq * 0.9, def.seed + 5)
		if maria < -0.18 then
			local k = math.clamp((-0.18 - maria) * 3, 0, 0.7)
			r, g, b = lerp(r, 78, k), lerp(g, 80, k), lerp(b, 92, k)
		end
		if math.abs(cylNoise(x, y, def.freq * 5.5, def.seed + 23) - 0.22) < 0.018 then
			r, g, b = r * 0.7, g * 0.7, b * 0.72
		end
	elseif style == "pangea" then
		-- Tierras bajas con selva densa y cumbres de roca grisácea
		local el = elevAt(x, y) / 255
		if el < 0.32 then
			r, g, b = lerp(r, 52, 0.45), lerp(g, 104, 0.45), lerp(b, 56, 0.45)
		elseif el > 0.78 then
			r, g, b = lerp(r, 150, 0.5), lerp(g, 140, 0.5), lerp(b, 128, 0.5)
		end
	elseif style == "venus" then
		-- Canales de lava incandescente entre llanuras volcánicas
		if math.abs(cylNoise(x, y, def.freq * 2.0, def.seed + 41)) < 0.03 then
			r, g, b = lerp(r, 255, 0.75), lerp(g, 118, 0.75), lerp(b, 34, 0.75)
		end
	end
	-- Sombreado direccional del relieve (luz desde el noroeste)
	local dzdx = (elevAt(x + 1, y) - elevAt(x - 1, y)) / 255
	local dzdy = (elevAt(x, y + 1) - elevAt(x, y - 1)) / 255
	return r, g, b, math.clamp(1.0 - (dzdx + dzdy) * 2.4, 0.62, 1.4)
end

function WorldGrid.BuildBase(planetId, land, customW, customH, customElev, customImp)
	local def = WorldGrid.PLANETS[planetId] or WorldGrid.PLANETS.EARTH
	local mapW = customW or W
	local mapH = customH or H
	local elevBuf = customElev
	local impBuf = customImp

	if def.kind == "frontwars" and def.mapId then
		local fwmModule = script.Parent:FindFirstChild("frontwars_maps")
		if not fwmModule then
			local rs = game:GetService("ReplicatedStorage")
			local sh = rs:FindFirstChild("Shared")
			fwmModule = sh and sh:FindFirstChild("frontwars_maps")
		end
		local mapModule = fwmModule and fwmModule:FindFirstChild(def.mapId)
		if mapModule then
			local mapData = require(mapModule)
			if not customW or not customH then
				mapW, mapH = mapData.w, mapData.h
			end
			if not elevBuf and mapData.elevB64 and #mapData.elevB64 > 0 then
				elevBuf = buffer.create(mapW * mapH)
				local packedElev = decodeBase64ToBuffer(mapData.elevB64)
				local landIdx = 0
				for i = 0, mapW * mapH - 1 do
					if i < buffer.len(land) and buffer.readu8(land, i) == 1 then
						local bIdx = landIdx // 2
						if bIdx < buffer.len(packedElev) then
							local byteVal = buffer.readu8(packedElev, bIdx)
							local nibble = if landIdx % 2 == 0 then bit32.band(byteVal, 0x0f) else bit32.rshift(byteVal, 4)
							buffer.writeu8(elevBuf, i, nibble)
						end
						landIdx += 1
					end
				end
			end
			if not impBuf and mapData.impB64 and #mapData.impB64 > 0 then
				impBuf = buffer.create(mapW * mapH)
				local packedImp = decodeBase64ToBuffer(mapData.impB64)
				for i = 0, mapW * mapH - 1 do
					local bIdx = i // 8
					if bIdx < buffer.len(packedImp) then
						local byteVal = buffer.readu8(packedImp, bIdx)
						local bit = bit32.band(bit32.rshift(byteVal, i % 8), 1)
						if bit == 1 then
							buffer.writeu8(impBuf, i, 1)
						end
					end
				end
			end
		end
	end

	if def.kind == "earth" and mapW == 960 and mapH == 400 then
		local satellite = loadSatellite()
		if satellite then
			return satellite
		end
	end

	local base = buffer.create(mapW * mapH * 3)
	if def.kind == "noise" or def.kind == "pangea" then
		planetElev = computeElevation(def)
	end

	local function isLand(x, y)
		if y < 0 or y >= mapH then
			return false
		end
		x = x % mapW
		local idx = y * mapW + x
		if idx >= 0 and idx < buffer.len(land) then
			return buffer.readu8(land, idx) == 1
		end
		return false
	end

	for y = 0, mapH - 1 do
		for x = 0, mapW - 1 do
			local i = y * mapW + x
			local r, g, b

			-- Sombreado de relieve 3D direccional (Sol desde el Noroeste)
			local shade = 1.0
			if isLand(x, y) then
				local leftX = if x == 0 then mapW - 1 else x - 1
				local rightX = if x == mapW - 1 then 0 else x + 1
				local upY = math.max(0, y - 1)
				local downY = math.min(mapH - 1, y + 1)

				local hL = math.noise(leftX * 0.1, y * 0.1, 4.3)
				local hR = math.noise(rightX * 0.1, y * 0.1, 4.3)
				local hU = math.noise(x * 0.1, upY * 0.1, 4.3)
				local hD = math.noise(x * 0.1, downY * 0.1, 4.3)

				local dz_dx = (hR - hL) * 0.5
				local dz_dy = (hD - hU) * 0.5
				shade = math.clamp(1.0 - (dz_dx + dz_dy) * 0.32, 0.72, 1.35)

				if def.kind == "frontwars" then
					local isShore = not (isLand(x - 1, y) and isLand(x + 1, y) and isLand(x, y - 1) and isLand(x, y + 1))
					local isImp = (impBuf and buffer.readu8(impBuf, i) == 1)
					local el = if elevBuf then buffer.readu8(elevBuf, i) else 0

					if isImp then
						-- Montañas infranqueables estilo OpenFront (canvas #3c3c3c)
						r, g, b = 60, 60, 60
					elseif isShore then
						-- Playas / arena dorada de la costa (#CCCB9E)
						r, g, b = 204, 203, 158
					elseif el < 5 then
						-- Llanuras fértiles (#BEDC8A)
						r = 190
						g = math.clamp(220 - el * 3, 180, 255)
						b = 138
					elseif el < 10 then
						-- Tierras altas (#C8B78A)
						local m = el - 5
						r = math.min(255, 200 + m * 5)
						g = math.min(255, 183 + m * 4)
						b = math.min(255, 138 + m * 3)
					else
						-- Picos montañosos y cumbres de nieve (#E6E6E6)
						local m = el - 10
						r = math.min(255, 230 + m * 5)
						g = math.min(255, 230 + m * 5)
						b = math.min(255, 230 + m * 5)
					end
				elseif def.kind == "earth" then
					r, g, b = earthLandColor(x, y)
					if def.kind == "pangea" then
						g = math.min(255, g + 14)
					end
				elseif def.kind == "galaxy" then
					local u = ((x + 0.5) / mapW) * 2 - 1
					local v = ((y + 0.5) / mapH) * 2 - 1
					local rr = math.min(1, math.sqrt(u * u + v * v) * 1.1)
					local theta = math.atan2(v, u)
					local arm = (math.sin(2 * theta - rr * 9) + 1) * 0.5
					local dust = (math.noise(x * 0.05, y * 0.07, 2.2) + 1) * 0.5
					local k = math.clamp(arm * (1 - rr * 0.8) * 0.7 + dust * 0.35, 0, 1)
					r, g, b = mix3(def.landB, def.landA, k)
					if math.noise(x * 0.9, y * 0.9, 7.7) > 0.62 then
						r, g, b = 255, 250, 230
					end
				else
					local t = (math.noise(x * 0.16, y * 0.2, 4.4) + 1) * 0.5
					r, g, b, shade = planetPixel(def, x, y)
				end
				r, g, b = r * shade, g * shade, b * shade
			else
				local near1, near2 = false, false
				if
					isLand(x - 1, y)
					or isLand(x + 1, y)
					or isLand(x, y - 1)
					or isLand(x, y + 1)
					or isLand(x - 1, y - 1)
					or isLand(x + 1, y - 1)
					or isLand(x - 1, y + 1)
					or isLand(x + 1, y + 1)
				then
					near1 = true
				elseif isLand(x - 2, y) or isLand(x + 2, y) or isLand(x, y - 2) or isLand(x, y + 2) then
					near2 = true
				end

				if def.kind == "frontwars" then
					if near1 then
						-- Agua costera poco profunda (cian claro: 70% océano + 30% blanco)
						r, g, b = 126, 170, 203
					elseif near2 then
						-- Plataforma continental
						r, g, b = 95, 150, 192
					else
						-- Océano profundo (#4785b5), con leve variación de profundidad
						local depthDim = math.min(25, math.floor(math.noise(x * 0.05, y * 0.05, 1.2) * 20))
						r = math.clamp(71 - depthDim, 40, 71)
						g = math.clamp(133 - depthDim, 90, 133)
						b = math.clamp(181 - depthDim, 140, 181)
					end
				else
					local c = def.ocean or { 71, 133, 181 }
					if near1 then
						c = def.shallow or { 60, 120, 170 }
					elseif near2 then
						c = def.mid or { 50, 110, 160 }
					end
					local oceanShade = 1.0 + math.noise(x * 0.1, y * 0.1, 1.7) * 0.05
					r, g, b = c[1] * oceanShade, c[2] * oceanShade, c[3] * oceanShade
				end
			end

			local o = i * 3
			buffer.writeu8(base, o, math.clamp(math.floor(r), 0, 255))
			buffer.writeu8(base, o + 1, math.clamp(math.floor(g), 0, 255))
			buffer.writeu8(base, o + 2, math.clamp(math.floor(b), 0, 255))
		end
	end
	return base
end

return WorldGrid
