--!strict
-- RoboPush Arena / Logger.lua
-- Timeline logging for reproducible bug reports (ARCHITECTURE 7; AGENTS.md
-- rule 9). Keeps the most recent entries in memory and prints each line to
-- the Studio output as "[RoboPush] t=<server time> <event> k=v ...".

local Logger = {}

-- Ring buffer length; diagnostics only, not a gameplay value.
local MAX_ENTRIES = 300

export type Entry = { t: number, event: string, fields: { [string]: any } }

local entries: { Entry } = {}

local function formatFields(fields: { [string]: any }): string
    local keys = {}
    for key in fields do
        table.insert(keys, key)
    end
    table.sort(keys)
    local parts = {}
    for _, key in keys do
        table.insert(parts, string.format("%s=%s", key, tostring(fields[key])))
    end
    return table.concat(parts, " ")
end

function Logger.log(event: string, fields: { [string]: any }?)
    local data = fields or {}
    local now = workspace:GetServerTimeNow()
    table.insert(entries, { t = now, event = event, fields = data })
    if #entries > MAX_ENTRIES then
        table.remove(entries, 1)
    end
    print(string.format("[RoboPush] t=%.3f %s %s", now, event, formatFields(data)))
end

-- Suspicious client behaviour (T11 / T22): logged, never trusted.
function Logger.anomaly(player: Player, reason: string, fields: { [string]: any }?)
    local data = fields and table.clone(fields) or {}
    data.userId = player.UserId
    data.reason = reason
    Logger.log("anomaly", data)
end

function Logger.recent(count: number): { Entry }
    local result = {}
    for i = math.max(1, #entries - count + 1), #entries do
        table.insert(result, entries[i])
    end
    return result
end

return Logger
