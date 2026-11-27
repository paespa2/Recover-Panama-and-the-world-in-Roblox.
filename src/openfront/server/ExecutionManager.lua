--!strict
-- OpenFront.io: ExecutionManager
-- Manages and steps all active game executions

local ExecutionManager = {}
ExecutionManager.__index = ExecutionManager

export type Execution = {
	id: string,
	Tick: (self: any, dt: number, tickNumber: number) -> boolean, -- return false when finished
	IsFinished: (self: any) -> boolean,
}

function ExecutionManager.new()
	local self = setmetatable({}, ExecutionManager)
	self.executions = {} :: { Execution }
	self.currentTick = 0
	return self
end

function ExecutionManager:Add(exec: Execution)
	table.insert(self.executions, exec)
end

function ExecutionManager:Tick(dt: number)
	self.currentTick += 1
	local i = 1
	while i <= #self.executions do
		local exec = self.executions[i]
		local alive = true
		local ok, res = pcall(function()
			return exec:Tick(dt, self.currentTick)
		end)
		if not ok then
			warn("[ExecutionManager] Error ticking execution " .. tostring(exec.id) .. ": " .. tostring(res))
			alive = false
		elseif res == false or exec:IsFinished() then
			alive = false
		end

		if not alive then
			table.remove(self.executions, i)
		else
			i += 1
		end
	end
end

return ExecutionManager
