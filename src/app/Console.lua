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
    local lifecycle = NS.app.indexLifecycle
    local size = (lifecycle and lifecycle:itemCount()) or 0
    local busy = lifecycle and lifecycle:isBusy()
    lines[#lines + 1] = string.format("indice: %d itens%s", size, busy and " (indexando)" or "")
    local diag = NS.app.diagnostics
    if diag and diag.secondaryReads > 0 then
        lines[#lines + 1] =
            string.format("specs secundarias: %d XML lidos, %d specs", diag.secondaryReads, diag.secondaryAdded)
    end
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

local function debugEnabled()
    return NS.app.settings and NS.app.settings:get("debug#enabled") == true
end

--- sssQuery <texto>: AST + top 10 + score + reasons (sempre disponível).
function Console.query(text)
    if not (NS.app.searchService and text) then
        return "uso: sssQuery <texto>"
    end
    local results, q = NS.app.searchService:search(text)
    local lines = { "raw: " .. tostring(q and q.raw) }
    if q then
        local terms = {}
        for _, t in ipairs(q.terms) do
            terms[#terms + 1] = t.text
        end
        lines[#lines + 1] = "terms: " .. table.concat(terms, " ")
        for _, c in ipairs(q.concepts) do
            lines[#lines + 1] = string.format("concept: %s=%s (%.2f)", c.kind, c.value, c.confidence)
        end
        for _, c in ipairs(q.constraints) do
            lines[#lines + 1] =
                string.format("constraint: %s %s [%s, %s]", c.quantity, c.op, tostring(c.min), tostring(c.max))
        end
    end
    for i = 1, math.min(10, #results) do
        local r = results[i]
        local name = (r.item.fields.name and r.item.fields.name.raw) or ("#" .. tostring(r.item.id))
        lines[#lines + 1] = string.format("%2d. %-30s score=%.3f cov=%.2f", i, name, r.score, r.coverage)
    end
    local text_ = table.concat(lines, "\n")
    NS.app.logger:info("console", "%s", text_)
    return text_
end

--- sssExplain <xmlFilename> <texto>: explica o score de um item específico (debug).
function Console.explain(xmlFilename, text)
    if not debugEnabled() then
        return "sssExplain requer debug#enabled=true"
    end
    if not (NS.app.searchService and xmlFilename and text) then
        return "uso: sssExplain <xmlFilename> <texto>"
    end
    local results = NS.app.searchService:search(text)
    for _, r in ipairs(results) do
        if r.item.xmlFilename == xmlFilename then
            local lines = { string.format("score=%.3f cov=%.2f", r.score, r.coverage) }
            for _, reason in ipairs(r.reasons) do
                lines[#lines + 1] = string.format(
                    "  %s field=%s query=%s matched=%s %s",
                    reason.kind,
                    reason.field,
                    reason.query,
                    reason.matched,
                    reason.detail or ""
                )
            end
            local out = table.concat(lines, "\n")
            NS.app.logger:info("console", "%s", out)
            return out
        end
    end
    return "item não encontrado nos resultados: " .. xmlFilename
end

local dumpCatalogFn -- injetado por GameBootstrap; evita app/ referenciar adapters/ diretamente

--- sssDumpCatalog: reaproveita o formato do spike (F5), agora via StoreCatalogSource real (debug).
function Console.dumpCatalog()
    if not debugEnabled() then
        return "sssDumpCatalog requer debug#enabled=true"
    end
    if not dumpCatalogFn then
        return "dump do catálogo indisponível (adapter não instalado)"
    end
    local path = dumpCatalogFn()
    NS.app.logger:info("console", "dump do catálogo gravado em %s", tostring(path))
    return "ok: " .. tostring(path)
end

--- sssBench <n>: roda `n` consultas embutidas (app/BenchQueries.lua) e mostra p50/p95 (debug).
function Console.bench(n)
    if not debugEnabled() then
        return "sssBench requer debug#enabled=true"
    end
    n = tonumber(n) or 1
    local queries = NS.app.BenchQueries
    local latencies = {}
    for _ = 1, n do
        for _, q in ipairs(queries) do
            local t0 = os.clock()
            NS.app.searchService:search(q)
            latencies[#latencies + 1] = (os.clock() - t0) * 1000
        end
    end
    table.sort(latencies)
    local p50 = latencies[math.max(1, math.floor(#latencies * 0.5))]
    local p95 = latencies[math.max(1, math.floor(#latencies * 0.95))]
    local text = string.format("bench: %d consultas, p50=%.3fms p95=%.3fms", #latencies, p50 or 0, p95 or 0)
    NS.app.logger:info("console", "%s", text)
    return text
end

-- Chaves alteráveis por `sssSet` (F7, RF-052/G7): nome curto → chave do
-- SettingsStore. Só booleanos nesta versão.
local SETTABLE = {
    showReasons = "ui#showReasons",
    incremental = "ui#incremental",
}
local SETTABLE_ORDER = { "showReasons", "incremental" }

local BOOL_WORDS = {
    ["1"] = true,
    ["true"] = true,
    on = true,
    sim = true,
    ["0"] = false,
    ["false"] = false,
    off = false,
    nao = false,
}

--- sssSet [<chave> <0|1>]: sem argumentos, lista os valores atuais; com
--- argumentos, grava o novo valor em modSettings (sempre disponível).
function Console.set(name, value)
    local settings = NS.app.settings
    if not settings then
        return "configurações indisponíveis"
    end
    if name == nil or name == "" then
        local lines = {}
        for _, short in ipairs(SETTABLE_ORDER) do
            lines[#lines + 1] = string.format("%s = %s", short, tostring(settings:get(SETTABLE[short])))
        end
        local out = table.concat(lines, "\n")
        NS.app.logger:info("console", "%s", out)
        return out
    end
    local key = SETTABLE[name]
    if not key then
        return "chave desconhecida: " .. tostring(name) .. " (use " .. table.concat(SETTABLE_ORDER, ", ") .. ")"
    end
    local parsed = BOOL_WORDS[string.lower(tostring(value or ""))]
    if parsed == nil then
        return "uso: sssSet " .. name .. " <0|1>"
    end
    settings:set(key, parsed)
    local out = string.format("%s = %s", name, tostring(parsed))
    NS.app.logger:info("console", "%s", out)
    return out
end

--- @param r ConsoleRegistrar
--- @param hookStatus fun():table[]|nil  -- ex.: NS.adapters.HookRegistry.status, injetado por GameBootstrap
function Console.install(r, hookStatus, dumpCatalog)
    registrar = r or registrar
    hookStatusFn = hookStatus or hookStatusFn
    dumpCatalogFn = dumpCatalog or dumpCatalogFn
    if not registrar then
        return
    end
    registrar:add("sssStatus", "Mostra o estado do SmartShopSearch", Console.status)
    registrar:add("sssReindex", "Reconstroi o indice de busca", Console.reindex)
    registrar:add("sssQuery", "Executa uma busca e mostra AST + top 10 + reasons", Console.query)
    registrar:add("sssExplain", "Explica o score de um item especifico (debug)", Console.explain)
    registrar:add("sssDumpCatalog", "Grava dump do catalogo extraido (debug)", Console.dumpCatalog)
    registrar:add("sssBench", "Roda consultas embutidas e mostra p50/p95 (debug)", Console.bench)
    registrar:add("sssSet", "Altera showReasons/incremental (sssSet <chave> <0|1>)", Console.set)
end

function Console.uninstall()
    if not registrar then
        return
    end
    registrar:remove("sssStatus")
    registrar:remove("sssReindex")
    registrar:remove("sssQuery")
    registrar:remove("sssExplain")
    registrar:remove("sssDumpCatalog")
    registrar:remove("sssBench")
    registrar:remove("sssSet")
end

NS.app.Console = Console
