-- Implementação em memória da porta Logger, para testes de app/core.
local MemoryLogger = {}
MemoryLogger.__index = MemoryLogger

function MemoryLogger.new()
    return setmetatable({ lines = {} }, MemoryLogger)
end

local function record(self, level, key, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    self.lines[#self.lines + 1] = { level = level, key = key, message = ok and msg or fmt }
end

function MemoryLogger:error(key, fmt, ...)
    record(self, "error", key, fmt, ...)
end
function MemoryLogger:warning(key, fmt, ...)
    record(self, "warning", key, fmt, ...)
end
function MemoryLogger:info(key, fmt, ...)
    record(self, "info", key, fmt, ...)
end
function MemoryLogger:debug(key, fmt, ...)
    record(self, "debug", key, fmt, ...)
end

function MemoryLogger:countLevel(level)
    local n = 0
    for _, l in ipairs(self.lines) do
        if l.level == level then
            n = n + 1
        end
    end
    return n
end

function MemoryLogger:hasLevel(level)
    return self:countLevel(level) > 0
end

return MemoryLogger
