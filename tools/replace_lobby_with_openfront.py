# tools/replace_lobby_with_openfront.py
import os

CLIENT_PATH = r"src/client/WorldClient.client.lua"

with open(CLIENT_PATH, "r", encoding="utf-8") as f:
    content = f.read()

start_pattern = "local lobbyScreen = Instance.new(\"Frame\")"
start_idx = content.find(start_pattern)
if start_idx == -1:
    raise RuntimeError("No se encontró start_pattern en WorldClient.client.lua")

end_pattern = "showLobby(true)"
end_idx = content.find(end_pattern, start_idx)
if end_idx == -1:
    raise RuntimeError("No se encontró end_pattern en WorldClient.client.lua")
end_idx += len(end_pattern)

new_snippet = '''local OpenFrontUIModule = script.Parent:WaitForChild("OpenFrontUI")
local OpenFrontUI = require(OpenFrontUIModule)

local openfrontApi = OpenFrontUI.create(root, {
	onLaunchGame = function(planet, bots, diff, mode)
		WorldCommand:FireServer({
			a = "PLAY",
			planet = planet,
			bots = bots,
			difficulty = diff,
			mode = mode,
		})
		showToast("⚔️ Iniciando partida OpenFront.io...", Color3.fromRGB(0, 229, 255))
	end,
	onSettings = function()
		if tacticalModal then
			tacticalModal.Visible = not tacticalModal.Visible
		end
	end,
	onHelp = function()
		showToast("OpenFront.io: Conquista celdas, construye ciudades y defiende con puestos", Color3.fromRGB(255, 215, 0))
	end,
	onNotify = function(msg)
		showToast(msg, Color3.fromRGB(0, 200, 255))
	end,
})

local function showLobby(visible)
	openfrontApi.show(visible)
end

local function updateLobbyStatus()
	-- No-op
end

btnLobby.MouseButton1Click:Connect(function()
	openfrontApi.toggle()
end)

showLobby(true)'''

new_content = content[:start_idx] + new_snippet + content[end_idx:]

with open(CLIENT_PATH, "w", encoding="utf-8") as f:
    f.write(new_content)

print(f"Lobby successfully swapped to OpenFrontUI! New length: {len(new_content)} chars")
