import os

fixes = [
    # Server files
    ('src/openfront/server/GameMap.lua', [
        ('local TerrainBytes = require(script.Parent.Parent.shared.TerrainBytes)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Shared = RS:WaitForChild("OpenFront"):WaitForChild("Shared")\nlocal TerrainBytes = require(Shared:WaitForChild("TerrainBytes"))'),
        ('local MapRegistry = require(script.Parent.Parent.shared.MapRegistry)', 'local MapRegistry = require(Shared:WaitForChild("MapRegistry"))')
    ]),
    ('src/openfront/server/Player.lua', [
        ('local Config = require(script.Parent.Parent.shared.Config)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Config = require(RS:WaitForChild("OpenFront"):WaitForChild("Shared"):WaitForChild("Config"))')
    ]),
    ('src/openfront/server/GameRunner.lua', [
        ('local Config = require(script.Parent.Parent.shared.Config)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Shared = RS:WaitForChild("OpenFront"):WaitForChild("Shared")\nlocal Config = require(Shared:WaitForChild("Config"))'),
        ('local EngineConfig = require(script.Parent.Parent.Parent.shared.EngineConfig)', 'local EngineConfig = require(Shared:WaitForChild("EngineConfig"))')
    ]),
    # Executions
    ('src/openfront/server/execution/AttackExecution.lua', [
        ('local EngineConfig = require(script.Parent.Parent.Parent.shared.EngineConfig)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Shared = RS:WaitForChild("OpenFront"):WaitForChild("Shared")\nlocal EngineConfig = require(Shared:WaitForChild("EngineConfig"))'),
        ('local Config = require(script.Parent.Parent.Parent.shared.Config)', 'local Config = require(Shared:WaitForChild("Config"))')
    ]),
    ('src/openfront/server/execution/ConstructionExecution.lua', [
        ('local Config = require(script.Parent.Parent.Parent.shared.Config)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Shared = RS:WaitForChild("OpenFront"):WaitForChild("Shared")\nlocal Config = require(Shared:WaitForChild("Config"))'),
        ('local EngineConfig = require(script.Parent.Parent.Parent.shared.EngineConfig)', 'local EngineConfig = require(Shared:WaitForChild("EngineConfig"))')
    ]),
    ('src/openfront/server/execution/NukeExecution.lua', [
        ('local Config = require(script.Parent.Parent.Parent.shared.Config)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Config = require(RS:WaitForChild("OpenFront"):WaitForChild("Shared"):WaitForChild("Config"))')
    ]),
    ('src/openfront/server/execution/SAMLauncherExecution.lua', [
        ('local Config = require(script.Parent.Parent.Parent.shared.Config)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Config = require(RS:WaitForChild("OpenFront"):WaitForChild("Shared"):WaitForChild("Config"))')
    ]),
    ('src/openfront/server/execution/WinCheckExecution.lua', [
        ('local Config = require(script.Parent.Parent.Parent.shared.Config)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Config = require(RS:WaitForChild("OpenFront"):WaitForChild("Shared"):WaitForChild("Config"))')
    ]),
    # Client files
    ('src/openfront/client/ClientMain.client.lua', [
        ('local MapRegistry = require(script.Parent.Parent.shared.MapRegistry)', 'local Shared = ReplicatedStorage:WaitForChild("OpenFront"):WaitForChild("Shared")\nlocal MapRegistry = require(Shared:WaitForChild("MapRegistry"))'),
        ('local function screenToTile(screenPos: Vector2): (number, number)?', 'local function screenToTile(screenPos: Vector2): (number?, number?)')
    ]),
    ('src/openfront/client/HubScreen.lua', [
        ('local MapRegistry = require(script.Parent.Parent.shared.MapRegistry)', 'local RS = game:GetService("ReplicatedStorage")\nlocal MapRegistry = require(RS:WaitForChild("OpenFront"):WaitForChild("Shared"):WaitForChild("MapRegistry"))')
    ]),
    ('src/openfront/client/TerrainRenderer.lua', [
        ('local MapRegistry = require(script.Parent.Parent.shared.MapRegistry)', 'local RS = game:GetService("ReplicatedStorage")\nlocal Shared = RS:WaitForChild("OpenFront"):WaitForChild("Shared")\nlocal MapRegistry = require(Shared:WaitForChild("MapRegistry"))'),
        ('local TerrainBytes = require(script.Parent.Parent.shared.TerrainBytes)', 'local TerrainBytes = require(Shared:WaitForChild("TerrainBytes"))')
    ]),
]

for fpath, reps in fixes:
    if not os.path.exists(fpath):
        print(f"File not found: {fpath}")
        continue
    with open(fpath, 'r', encoding='utf-8') as f:
        content = f.read()
    for orig, rep in reps:
        if orig in content:
            content = content.replace(orig, rep)
            print(f"Replaced in {fpath}")
        else:
            print(f"Target NOT FOUND in {fpath}: {orig[:40]}...")
    with open(fpath, 'w', encoding='utf-8') as f:
        f.write(content)

print("Done fixing requires.")
