-- Comandos de console do mod (PRD §13.2). Recebe um `registrar` (porta
-- ConsoleRegistrar, implementada por um adapter fino em GameBootstrap) para
-- não tocar `addConsoleCommand` diretamente.
---@class ConsoleRegistrar
---@field add fun(self, name:string, helpText:string, fn:function)
---@field remove fun(self, name:string)
local NS = SmartShopSearch
local Console = {}
local registrar
local hookStatusFn -- injetado por GameBootstrap; evita app/ referenciar adapters/ diretamente

local function statusLines()
    local state = NS.app.state
    local lines = {}
    lines[#lines + 1] = string.format(
        "estado: %s%s",
        state and state.current or "?",
        (state and state.reason) and (" (" .. state.reason .. ")") or ""
    )
    lines[#lines + 1] = string.format("versao: %s", NS.VERSION)
    local size = (NS.app.indexLifecycle and NS.app.indexLifecycle:itemCount()) or 0
    lines[#lines + 1] = string.format("indice: %d itens", size)
    for _, h in ipairs(hookStatusFn and hookStatusFn() or {}) do
        lines[#lines + 1] = string.format("hook %s: ativo=%s falhas=%d", h.id, tostring(h.active), h.failures)
    end
    for ctx, n in pairs(NS.app.SafeCall.failures) do
        lines[#lines + 1] = string.format("safecall %s: %d falhas", ctx, n)
    end
    return lines
end

function Console.status()
    local text = table.concat(statusLines(), "\n")
    NS.app.logger:info("console", "%s", text)
    return text
end

function Console.reindex()
    local t0 = os.clock()
    NS.app.indexLifecycle:forceRebuild()
    NS.app.logger:info("console", "reindexado em %.1f ms", (os.clock() - t0) * 1000)
end

--- @param r ConsoleRegistrar
--- @param hookStatus fun():table[]|nil  -- ex.: NS.adapters.HookRegistry.status, injetado por GameBootstrap
function Console.install(r, hookStatus)
    registrar = r or registrar
    hookStatusFn = hookStatus or hookStatusFn
    if not registrar then
        return
    end
    registrar:add("sssStatus", "Mostra o estado do SmartShopSearch", Console.status)
    registrar:add("sssReindex", "Reconstroi o indice de busca", Console.reindex)
end

function Console.uninstall()
    if not registrar then
        return
    end
    registrar:remove("sssStatus")
    registrar:remove("sssReindex")
end

NS.app.Console = Console
