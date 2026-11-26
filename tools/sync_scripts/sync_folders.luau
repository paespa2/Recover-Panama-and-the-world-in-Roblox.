
local shared = game:GetService("ReplicatedStorage").Shared
local fwm = shared:FindFirstChild("FrontWarsMaps")
if not fwm then
    fwm = Instance.new("ModuleScript")
    fwm.Name = "FrontWarsMaps"
    fwm.Parent = shared
end
local folder = shared:FindFirstChild("frontwars_maps")
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "frontwars_maps"
    folder.Parent = shared
end
return true
