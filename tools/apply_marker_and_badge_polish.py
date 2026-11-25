# tools/apply_marker_and_badge_polish.py
import re

with open("src/client/WorldClient.client.lua", "r", encoding="utf-8") as f:
    code = f.read()

# 1. Update applyLabelZoom to cleanly position badge and troops around the disc
old_zoom_block = """			if m.marker then m.marker.Visible = true end
			local ds = math.clamp(math.floor((if m.isMe then 12 else 7) * (0.75 + 0.3 * rel)), 5, 24)
			m.dot.Size = UDim2.fromOffset(ds, ds)
			local show = m.always or rel >= 1.8
			m.label.Visible = show
			if m.troops then
				m.troops.Visible = show and m.troops.Text ~= ""
			end
			if show then
				local size = math.clamp(math.floor(7 + 3 * rel), 8, 17) + (if m.strong then 2 else 0)
				local width = math.max(100, size * 14)
				m.label.TextSize = size
				m.label.Size = UDim2.fromOffset(width, size + 6)
				m.label.Position = UDim2.fromOffset(12 - width / 2, 10 + ds / 2)
				if m.troops then
					m.troops.TextSize = math.max(8, size - 1)
					m.troops.Size = UDim2.fromOffset(width, size + 4)
					m.troops.Position = UDim2.fromOffset(12 - width / 2, 10 + ds / 2 + size + 4)
				end
			end"""

new_zoom_block = """			if m.marker then m.marker.Visible = true end
			local ds = math.clamp(math.floor((if m.isMe then 24 else 18) * (0.85 + 0.2 * rel)), 14, 30)
			m.dot.Size = UDim2.fromOffset(ds, ds)
			local show = m.always or rel >= 1.3
			if m.badge then
				m.badge.Visible = show
				m.badge.Position = UDim2.fromOffset(0, -ds / 2 - 4)
			end
			if m.troops then
				m.troops.Visible = show and m.troops.Text ~= ""
				m.troops.Position = UDim2.fromOffset(0, ds / 2 + 2)
			end"""

if old_zoom_block in code:
    code = code.replace(old_zoom_block, new_zoom_block)
    print("Updated applyLabelZoom marker sizing and badge positioning")
else:
    print("WARNING: old_zoom_block not found in WorldClient")

# 2. Update markerLabels insertion to include badge
old_insert = """			table.insert(markerLabels, {
				id = n.id,
				troops = troopsLbl,
				label = nameLbl,
				dot = dot,
				marker = marker,
				capX = capX,
				capY = capY,
				isMe = isMe,
				strong = isMe or isHuman,
				always = isMe or isHuman or bigIds[n.id] == true,
			})"""

new_insert = """			table.insert(markerLabels, {
				id = n.id,
				troops = troopsLbl,
				label = nameLbl,
				badge = badge,
				dot = dot,
				marker = marker,
				capX = capX,
				capY = capY,
				isMe = isMe,
				strong = isMe or isHuman,
				always = isMe or isHuman or bigIds[n.id] == true,
			})"""

if old_insert in code:
    code = code.replace(old_insert, new_insert)
    print("Added badge reference to markerLabels")
else:
    print("WARNING: old_insert not found")

with open("src/client/WorldClient.client.lua", "w", encoding="utf-8") as f:
    f.write(code)

print("Marker and badge polish complete.")
