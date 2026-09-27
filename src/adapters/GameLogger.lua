-- Implementa a porta Logger (error/warning/info/debug(key, fmt, ...)).
-- Usa Logging.info/warning/error se existirem [A VALIDAR na F5], senão print,
-- sempre com o prefixo [SmartShopSearch]. Rate limit por (key..fmt) de 60s,
-- com contagem de supressões emitida na próxima linha permitida.
local NS = SmartShopSearch
local GameLogger = {}
GameLogger.__index = GameLogger

local PREFIX = "[SmartShopSearch]"
local RATE_LIMIT_SECONDS = 60
local LEVEL_RANK = { error = 1, warning = 2, info = 3, debug = 4 }

local function now()
    if type(getTimeSec) == "function" then
        return getTimeSec()
    end
    return os.clock()
end

function GameLogger.new(settings)
    return setmetatable({
        settings = settings,
        level = (settings and settings:get("debug#logLevel")) or "info",
        lastEmit = {},
        suppressed = {},
    }, GameLogger)
end

function GameLogger:setLevel(level)
    self.level = level
end

local function emit(prefix, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        msg = fmt
    end
    local line = PREFIX .. " " .. prefix .. ": " .. msg
    if Logging and type(Logging.info) == "function" then
        if prefix == "error" and type(Logging.error) == "function" then
            Logging.error(line)
        elseif prefix == "warning" and type(Logging.warning) == "function" then
            Logging.warning(line)
        else
            Logging.info(line)
        end
    else
        print(line)
    end
end

function GameLogger:log(level, key, fmt, ...)
    local levelRank = LEVEL_RANK[level] or LEVEL_RANK.debug
    local currentRank = LEVEL_RANK[self.level] or LEVEL_RANK.info
    if levelRank > currentRank then
        return
    end
    local args = { ... }
    local nargs = select("#", ...)
    local rateLimited = level == "error" or level == "warning"
    local id = key .. "|" .. fmt
    if rateLimited then
        local last = self.lastEmit[id]
        local t = now()
        if last and (t - last) < RATE_LIMIT_SECONDS then
            self.suppressed[id] = (self.suppressed[id] or 0) + 1
            return
        end
        local suppressedCount = self.suppressed[id]
        self.lastEmit[id] = t
        self.suppressed[id] = nil
        if suppressedCount and suppressedCount > 0 then
            args[nargs + 1] = suppressedCount
            emit(level, fmt .. " (%d mensagens suprimidas)", unpack(args, 1, nargs + 1))
            return
        end
    end
    emit(level, fmt, unpack(args, 1, nargs))
end

function GameLogger:error(key, fmt, ...)
    self:log("error", key, fmt, ...)
end
function GameLogger:warning(key, fmt, ...)
    self:log("warning", key, fmt, ...)
end
function GameLogger:info(key, fmt, ...)
    self:log("info", key, fmt, ...)
end
function GameLogger:debug(key, fmt, ...)
    self:log("debug", key, fmt, ...)
end

NS.adapters.GameLogger = GameLogger
