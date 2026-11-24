# tools/optimize_client.py
import re

with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
    content = f.read()

lines = content.splitlines()

def find_line(pattern):
    for i, line in enumerate(lines):
        if pattern in line:
            return i + 1
    return -1

print("BLOCK:", find_line("local BLOCK = 5"))
print("edgeLayer:", find_line("PixelEdgeLayer"))
print("rebuildEdges:", find_line("local rebuildEdges"))
print("recolorBlock:", find_line("local function recolorBlock(bi)"))
print("cloudsOn:", find_line("cloudsOn"))
print("FRONT_MAX_ACTIVE:", find_line("FRONT_MAX_ACTIVE"))
print("SWARM_MAX:", find_line("SWARM_MAX"))
