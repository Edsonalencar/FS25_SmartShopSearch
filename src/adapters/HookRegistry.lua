-- ADR-03: todo hook do jogo passa por este registro: idempotente, protegido
-- por pcall, com desativação após falhas repetidas.
local NS = SmartShopSearch
local HookRegistry = { hooks = {}, enabled = true }

---@param spec {id:string, target:table, method:string, kind:"append"|"prepend"|"overwrite", fn:function}
function HookRegistry.add(spec)
    if HookRegistry.hooks[spec.id] then
        return true
    end -- idempotente
    local target = spec.target
    if type(target) ~= "table" or type(target[spec.method]) ~= "function" then
        NS.app.logger:warning("hook", "alvo ausente: %s", spec.id)
        return false
    end
    local entry = { id = spec.id, active = true, failures = 0 }
    local body = spec.fn
    local function guarded(...)
        if not (HookRegistry.enabled and entry.active) or NS.app.state:is("degraded") then
            return
        end
        local ok, err = pcall(body, ...)
        if not ok then
            entry.failures = entry.failures + 1
            NS.app.logger:error("hook", "%s: %s", spec.id, tostring(err))
            if entry.failures >= 3 then
                entry.active = false
            end
        end
    end
    if spec.kind == "append" then
        target[spec.method] = Utils.appendedFunction(target[spec.method], guarded)
    elseif spec.kind == "prepend" then
        target[spec.method] = Utils.prependedFunction(target[spec.method], guarded)
    else -- overwrite: body recebe (self, superFunc, ...) e DEVE chamar superFunc; em falha chama superFunc
        target[spec.method] = Utils.overwrittenFunction(target[spec.method], function(self, superFunc, ...)
            if not (HookRegistry.enabled and entry.active) or NS.app.state:is("degraded") then
                return superFunc(self, ...)
            end
            local res = { pcall(body, self, superFunc, ...) }
            if res[1] then
                return unpack(res, 2)
            end
            entry.failures = entry.failures + 1
            NS.app.logger:error("hook", "%s: %s", spec.id, tostring(res[2]))
            if entry.failures >= 3 then
                entry.active = false
            end
            return superFunc(self, ...)
        end)
    end
    HookRegistry.hooks[spec.id] = entry
    return true
end

-- Nota de implementação: no caminho "overwrite", se `body` falhar DEPOIS de já
-- ter chamado `superFunc`, `superFunc` seria chamado de novo aqui. Para
-- garantir que isso nunca aconteça, todo `body` de overwrite DEVE chamar
-- `superFunc` na primeira linha e guardar o retorno (regra verificada em
-- revisão de código, não pelo tipo).

function HookRegistry.uninstall()
    HookRegistry.enabled = false
end -- lógico (§7.1 passo 12)

function HookRegistry.status()
    local out = {}
    for id, e in pairs(HookRegistry.hooks) do
        out[#out + 1] = { id = id, active = e.active, failures = e.failures }
    end
    table.sort(out, function(a, b)
        return a.id < b.id
    end)
    return out
end

NS.adapters.HookRegistry = HookRegistry
