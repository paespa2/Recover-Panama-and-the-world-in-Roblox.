import re

def refactor():
    with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
        src = f.read()

    # 1. Refactor Ally / Spectator block around line 4440
    old_ally_start = '-- Modo espectador: quien es eliminado por las tropas rivales pierde y solo puede observar la partida\nlocal spectatorBanner = Instance.new("TextLabel")'
    assert old_ally_start in src, "Could not find old_ally_start"

    old_ally_end = """local function setSpectator(on)
	if spectatorBanner.Visible == on then
		return
	end
	spectatorBanner.Visible = on
	bottomHUD.Visible = not on
	weaponBar.Visible = not on
end"""
    assert old_ally_end in src, "Could not find old_ally_end"

    # Find the chunk between old_ally_start and old_ally_end + len(old_ally_end)
    start_pos = src.index(old_ally_start)
    end_pos = src.index(old_ally_end) + len(old_ally_end)
    ally_chunk = src[start_pos:end_pos]

    new_ally_chunk = f"""local updateAttackPill, updateAllyCards, setSpectator
do
{ally_chunk}
end"""
    src = src[:start_pos] + new_ally_chunk + src[end_pos:]

    # 2. Refactor Lobby block around line 1058
    old_lobby_start = 'local lobbyCard = Instance.new("Frame")\nlobbyCard.Name = "LobbyCard"'
    assert old_lobby_start in src, "Could not find old_lobby_start"

    old_lobby_end = """btnPlay.MouseButton1Click:Connect(function()
	showLobby(false)
	WorldCommand:FireServer({
		a = "PLAY",
		planet = selPlanet,
		bots = selBots,
		difficulty = selDiff,
		mode = selMode,
	})
	showToast("Cargando partida...", Color3.fromRGB(255, 215, 0))
end)
btnLobbyClose.MouseButton1Click:Connect(function()
	showLobby(false)
end)"""
    assert old_lobby_end in src, "Could not find old_lobby_end"

    l_start = src.index(old_lobby_start)
    l_end = src.index(old_lobby_end) + len(old_lobby_end)
    lobby_chunk = src[l_start:l_end]

    new_lobby_chunk = f"""local showLobby, updateLobbyStatus
do
{lobby_chunk}
end"""
    src = src[:l_start] + new_lobby_chunk + src[l_end:]

    with open("src/client/WorldClient.client.lua", "w", encoding="utf-8") as f:
        f.write(src)
    print("Refactored WorldClient.client.lua successfully!")

if __name__ == "__main__":
    refactor()
