local NS = SmartShopSearch
local SafeCall = { failures = {}, maxFailures = 3 }

--- Executa fn protegida; em falha registra, conta e devolve nil.
---@param context string  identificador estável ("hook:ShopMenu.onOpen")
function SafeCall.run(context, fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then
        return a, b, c
    end
    local n = (SafeCall.failures[context] or 0) + 1
    SafeCall.failures[context] = n
    local log = NS.app.logger
    if log then
        log:error("safecall", "%s falhou (%d): %s", context, n, tostring(a))
    end
    if n >= SafeCall.maxFailures and NS.app.state then
        NS.app.state:degrade("falhas repetidas em " .. context)
    end
    return nil
end

NS.app.SafeCall = SafeCall
