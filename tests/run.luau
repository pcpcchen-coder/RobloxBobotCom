--!nocheck
-- RoboPush Arena / offline unit test runner (Lune, https://lune-org.github.io).
-- Usage: lune run tests/run
--
-- Emulates just enough of the Rojo tree for *pure* modules:
--   game:GetService("ReplicatedStorage").Shared -> src/shared
--   script.Parent / WaitForChild / FindFirstChild over src/ folders
-- Modules that touch real Roblox services (Services/, Controllers/) are NOT
-- executed here; they need Roblox Studio (see docs/TEST_PLAN.md).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local ROOT = "src"

-- --------------------------------------------------------------- fake tree

local Node = {}
local nodeCache = {}
local moduleCache = {}
local fakeGame

local function makeNode(path, name, isDir, parent)
    if nodeCache[path] then
        return nodeCache[path]
    end
    local node = setmetatable({ __path = path, __isDir = isDir, Name = name, Parent = parent }, Node)
    nodeCache[path] = node
    return node
end

local function findChild(node, name)
    if node.__path == "<ReplicatedStorage>" then
        return if name == "Shared" then makeNode(ROOT .. "/shared", "Shared", true, node) else nil
    end
    if not node.__isDir then
        return nil
    end
    local dirPath = node.__path .. "/" .. name
    if fs.isDir(dirPath) then
        return makeNode(dirPath, name, true, node)
    end
    for _, ext in { ".lua", ".luau" } do
        if fs.isFile(dirPath .. ext) then
            return makeNode(dirPath .. ext, name, false, node)
        end
    end
    return nil
end

Node.__index = function(node, key)
    if key == "WaitForChild" then
        return function(self, name)
            local child = findChild(self, name)
            assert(child, "WaitForChild: missing " .. self.__path .. "/" .. tostring(name))
            return child
        end
    elseif key == "FindFirstChild" then
        return function(self, name)
            return findChild(self, name)
        end
    end
    return findChild(node, key)
end

local services = {
    ReplicatedStorage = makeNode("<ReplicatedStorage>", "ReplicatedStorage", true, nil),
}

fakeGame = {
    GetService = function(_, name)
        local service = services[name]
        assert(service, "fake game: service not emulated in unit tests: " .. tostring(name))
        return service
    end,
}

local function fakeRequire(node)
    assert(type(node) == "table" and node.__path, "require expects a module node")
    local path = node.__path
    if moduleCache[path] ~= nil then
        return moduleCache[path]
    end
    local source = fs.readFile(path)
    local chunk = luau.load(source, {
        debugName = path,
        environment = { script = node, game = fakeGame, require = fakeRequire },
    })
    local result = chunk()
    moduleCache[path] = result
    return result
end

-- --------------------------------------------------------------- framework

local results = { passed = 0, failed = 0, failures = {} }

local function deepEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in a do
        if not deepEqual(v, b[k]) then
            return false
        end
    end
    for k in b do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function fmt(value)
    if type(value) == "table" then
        local parts = {}
        for k, v in value do
            table.insert(parts, tostring(k) .. "=" .. fmt(v))
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end

local expect = {}
function expect.eq(actual, expected, label)
    if not deepEqual(actual, expected) then
        error(string.format("%s: expected %s, got %s", label or "eq", fmt(expected), fmt(actual)), 2)
    end
end
function expect.truthy(value, label)
    if not value then
        error((label or "truthy") .. ": expected truthy, got " .. fmt(value), 2)
    end
end
function expect.falsy(value, label)
    if value then
        error((label or "falsy") .. ": expected falsy, got " .. fmt(value), 2)
    end
end
function expect.near(actual, expected, tolerance, label)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(string.format("%s: expected ~%s, got %s", label or "near", tostring(expected), fmt(actual)), 2)
    end
end

local function makeSuite(fileName)
    local suite = {}
    function suite.test(name, fn)
        local ok, err = pcall(fn)
        if ok then
            results.passed += 1
            print("  PASS  " .. name)
        else
            results.failed += 1
            table.insert(results.failures, fileName .. " :: " .. name .. "\n      " .. tostring(err))
            print("  FAIL  " .. name .. "\n        " .. tostring(err))
        end
    end
    return suite
end

local env = {
    require = fakeRequire,
    game = fakeGame,
    expect = expect,
    shared = function(name)
        return fakeRequire(findChild(makeNode(ROOT .. "/shared", "Shared", true, nil), name))
    end,
    server = function(relPath)
        local node = makeNode(ROOT .. "/server", "ServerScriptService", true, nil)
        for segment in string.gmatch(relPath, "[^/]+") do
            node = findChild(node, segment)
            assert(node, "server module not found: " .. relPath)
        end
        return fakeRequire(node)
    end,
}

local specs = {}
for _, entry in fs.readDir("tests") do
    if string.match(entry, "%.spec%.luau$") then
        table.insert(specs, entry)
    end
end
table.sort(specs)

for _, specName in specs do
    print("\n" .. specName)
    local source = fs.readFile("tests/" .. specName)
    local chunk = luau.load(source, { debugName = specName, environment = env })
    local ok, err = pcall(function()
        chunk()(makeSuite(specName))
    end)
    if not ok then
        results.failed += 1
        table.insert(results.failures, specName .. " :: <load>\n      " .. tostring(err))
        print("  FAIL  <load> " .. tostring(err))
    end
end

print(string.format("\n%d passed, %d failed", results.passed, results.failed))
if results.failed > 0 then
    print("\nFailures:")
    for _, failure in results.failures do
        print("  - " .. failure)
    end
    process.exit(1)
end
