--!strict
-- RoboPush Arena / Maid.lua
-- Lifecycle cleanup helper (AGENTS.md rule 7). Give it connections, instances,
-- threads or functions; cleanup() releases everything exactly once.

local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: { tasks: { any } }, Maid))

function Maid.new(): Maid
    return setmetatable({ tasks = {} }, Maid)
end

function Maid.give<T>(self: Maid, item: T): T
    table.insert(self.tasks, item)
    return item
end

local function release(item: any)
    local kind = typeof(item)
    if kind == "RBXScriptConnection" then
        item:Disconnect()
    elseif kind == "Instance" or (kind == "table" and type(item.Destroy) == "function") then
        item:Destroy()
    elseif kind == "function" then
        item()
    elseif kind == "thread" then
        if coroutine.status(item) ~= "dead" then
            task.cancel(item)
        end
    elseif kind == "table" and type(item.cleanup) == "function" then
        item:cleanup()
    end
end

function Maid.cleanup(self: Maid)
    local tasks = self.tasks
    self.tasks = {}
    -- Release in reverse order of acquisition.
    for i = #tasks, 1, -1 do
        local ok, err = pcall(release, tasks[i])
        if not ok then
            warn("[RoboPush] Maid cleanup error:", err)
        end
    end
end

return Maid
