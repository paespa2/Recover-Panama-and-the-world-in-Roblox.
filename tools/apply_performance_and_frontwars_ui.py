# tools/apply_performance_and_frontwars_ui.py
import re

with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
    code = f.read()

# 1. Update BLOCK from 5 to 8
code = code.replace("local BLOCK = 5", "local BLOCK = 8")

# 2. Update cloudsOn from true to false
code = code.replace("local cloudsOn = true", "local cloudsOn = false")

# 3. Update FRONT_MAX_ACTIVE and SWARM_MAX
code = code.replace("local FRONT_MAX_ACTIVE = 2500", "local FRONT_MAX_ACTIVE = 40")
code = code.replace("local SWARM_MAX = 100", "local SWARM_MAX = 25")

# 4. Remove the heavy 900-frame flashing Heartbeat loop and simplify recolorBlock
# Find the flashing Heartbeat section
old_flashing_section = """-- Animación de propagación: bloques recién conquistados destellan y se asientan en 0,9 s
local flashing = {}
local flashCount = 0
local FLASH_TIME = 0.9
RunService.Heartbeat:Connect(function()
\tlocal now = os.clock()
\tfor b, t0 in pairs(flashing) do
\t\tlocal a = (now - t0) / FLASH_TIME
\t\tif a >= 1 then
\t\t\tb.frame.BackgroundColor3 = b.finalColor
\t\t\tb.frame.BackgroundTransparency = b.finalTransp
\t\t\tflashing[b] = nil
\t\t\tflashCount -= 1
\t\telse
\t\t\tb.frame.BackgroundColor3 = b.finalColor:Lerp(Color3.new(1, 1, 1), 0.65 * (1 - a))
\t\t\tb.frame.BackgroundTransparency = 0.05 + (b.finalTransp - 0.05) * a
\t\tend
\tend
end)"""

new_flashing_section = """-- Renderizado ultra-rápido estilo FrontWars: asignación directa sin bucles pesados de Heartbeat
local flashing = {}
local flashCount = 0"""

if old_flashing_section in code:
    code = code.replace(old_flashing_section, new_flashing_section)
    print("Replaced flashing Heartbeat section successfully")
else:
    print("WARNING: old_flashing_section not found exactly, searching regex...")
    code = re.sub(
        r"-- Animación de propagación: bloques recién conquistados destellan.*?end\)\n",
        new_flashing_section + "\n",
        code,
        flags=re.DOTALL
    )

# 5. Simplify recolorBlock to directly assign color without 900-frame flashing loop
old_recolor_flash = """\t-- Propagación: al cambiar de dueño, el bloque "destella" claro y se asienta en su color (ver Heartbeat arriba)
\tlocal ownerNow = if n then bestId else 0
\tif state.animReady and n and b.owner ~= ownerNow and flashCount < 900 then
\t\tb.finalColor, b.finalTransp = finalColor, transparency
\t\tb.frame.BackgroundColor3 = finalColor:Lerp(Color3.new(1, 1, 1), 0.65)
\t\tb.frame.BackgroundTransparency = 0.05
\t\tif not flashing[b] then
\t\t\tflashCount += 1
\t\tend
\t\tflashing[b] = os.clock()
\telse
\t\tif flashing[b] then
\t\t\tflashing[b] = nil
\t\t\tflashCount -= 1
\t\tend
\t\tb.frame.BackgroundColor3 = finalColor
\t\tb.frame.BackgroundTransparency = transparency
\tend
\tlocal ownerChanged = b.owner ~= ownerNow
\tb.owner = ownerNow"""

new_recolor_flash = """\tlocal ownerNow = if n then bestId else 0
\tb.frame.BackgroundColor3 = finalColor
\tb.frame.BackgroundTransparency = transparency
\tlocal ownerChanged = b.owner ~= ownerNow
\tb.owner = ownerNow"""

if old_recolor_flash in code:
    code = code.replace(old_recolor_flash, new_recolor_flash)
    print("Replaced recolorBlock flashing section successfully")
else:
    print("WARNING: old_recolor_flash not found exactly")

with open("src/client/WorldClient.client.lua", "w", encoding="utf-8") as f:
    f.write(code)

print("Base optimizations applied successfully.")
