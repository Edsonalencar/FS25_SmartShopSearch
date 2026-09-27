local NS = SmartShopSearch
local StateMachine = {}
StateMachine.__index = StateMachine

local ALLOWED = {
    loaded = { ready = true, ["disabled-dedicated"] = true, degraded = true, unloaded = true },
    ready = { indexed = true, degraded = true, unloaded = true },
    indexed = { indexed = true, degraded = true, unloaded = true, ready = true },
    degraded = { unloaded = true },
    ["disabled-dedicated"] = { unloaded = true },
}

function StateMachine.new(logger)
    return setmetatable({ current = "loaded", reason = nil, logger = logger, listeners = {} }, StateMachine)
end

function StateMachine:set(to)
    if not (ALLOWED[self.current] or {})[to] then
        self.logger:debug("state", "transição ignorada %s→%s", self.current, to)
        return false
    end
    self.current = to
    for _, fn in ipairs(self.listeners) do
        pcall(fn, to)
    end
    return true
end

function StateMachine:degrade(reason)
    if self.current == "degraded" then
        return
    end
    self.reason = reason
    self.logger:error("state", "modo degradado: %s", reason)
    self:set("degraded")
end

function StateMachine:is(s)
    return self.current == s
end

function StateMachine:onChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

NS.app.StateMachine = StateMachine
