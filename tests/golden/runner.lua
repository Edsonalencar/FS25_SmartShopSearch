-- Motor de execução dos testes golden (F2 §2.6 do spec): lê
-- tests/golden/queries.<lang>.xml e os fixtures de tests/fixtures/catalog/,
-- roda cada <case> contra o SearchService e avalia as expectativas.
local xml = require("tests.support.xml")
local IdMatcher = SmartShopSearch.core.IdMatcher
local TextNormalizer = SmartShopSearch.core.TextNormalizer
local IndexBuilder = SmartShopSearch.core.IndexBuilder
local FixtureCatalogSource = require("tests.stubs.FixtureCatalogSource")
local MemoryLogger = require("tests.stubs.MemoryLogger")
local FakeClock = require("tests.stubs.FakeClock")
local FileDataLoader = require("tests.stubs.FileDataLoader")

local M = {}

-- Currency symbols isolados por espaço (L8); as sequências protegidas
-- (km/h, m³, r$) vêm de data/common/units.xml, lido abaixo por locale.
local CURRENCY_SYMBOLS = { "r$", "$", "€", "£" }

local serviceCache = {}

--- @param primaryLocale string  "pt" (padrão, idioma do jogo simulado) ou "en"
local function localesFor(primaryLocale)
    if primaryLocale == "en" then
        return { "en", "pt" }
    end
    return { "pt", "en" }
end

--- Constrói (ou reaproveita) um SearchService sobre um perfil de fixture.
--- @param fixtureProfile string  ex. "synthetic", "base"
--- @param primaryLocale string|nil  "pt" (padrão) ou "en" — define a ordem de
--- locales (decimal/milhar do NumberParser vêm do primeiro) e cacheia por par.
--- @param weightsOverride table|nil  tools/calibrate.lua: pula o cache e usa
--- esta tabela de pesos em vez de core/rank/Weights (nunca cacheado).
function M.serviceFor(fixtureProfile, primaryLocale, weightsOverride)
    primaryLocale = primaryLocale or "pt"
    local cacheKey = fixtureProfile .. "|" .. primaryLocale
    if not weightsOverride and serviceCache[cacheKey] then
        return serviceCache[cacheKey]
    end
    local NS = SmartShopSearch
    local path = "tests/fixtures/catalog/" .. fixtureProfile .. ".xml"
    local loader = FileDataLoader.new("src/data")
    local logger = MemoryLogger.new()
    local data = NS.app.LinguisticData.new(loader, localesFor(primaryLocale), logger)
    local commonUnits = data:commonUnits()
    local normalizer =
        TextNormalizer.new({ protected = (commonUnits and commonUnits.protected) or {}, currency = CURRENCY_SYMBOLS })
    local catalog = FixtureCatalogSource.new(path)
    local builder = IndexBuilder.new(normalizer)
    local diagnostics = NS.app.Diagnostics.new()
    local lifecycle =
        NS.app.IndexLifecycle.new(diagnostics, { catalog = catalog, builder = builder, clock = FakeClock.new() })
    local settings = {
        get = function(_, key)
            if key == "search#maxResults" then
                return 300
            end
            return nil
        end,
    }
    local svc = NS.app.SearchService.new({
        indexLifecycle = lifecycle,
        normalizer = normalizer,
        settings = settings,
        logger = logger,
        data = data,
        weights = weightsOverride,
    })
    local entry = { service = svc, logger = logger, diagnostics = diagnostics, lifecycle = lifecycle }
    if not weightsOverride then
        serviceCache[cacheKey] = entry
    end
    return entry
end

local function splitAttr(value)
    local out = {}
    if not value then
        return out
    end
    for word in value:gmatch("%S+") do
        out[#out + 1] = word
    end
    return out
end

local function itemMatchesAttrs(item, attrs)
    if attrs.category and not IdMatcher.matches(attrs.category, item.categoryIdInternal or "") then
        return false
    end
    if attrs.brand and not IdMatcher.matches(attrs.brand, item.brandId or "") then
        return false
    end
    if attrs.origin and item.origin ~= attrs.origin then
        return false
    end
    if attrs.species and item.species ~= attrs.species then
        return false
    end
    if attrs.name then
        local nameRaw = item.fields.name and item.fields.name.raw or ""
        if IdMatcher.matches(attrs.name, nameRaw) == false and nameRaw ~= attrs.name then
            return false
        end
    end
    return true
end

local function conceptAttrs(node)
    return {
        category = node.attrs.category,
        brand = node.attrs.brand,
        origin = node.attrs.origin,
        species = node.attrs.species,
        name = node.attrs.name,
    }
end

--- Avalia um único elemento de expectativa contra o resultado da busca.
--- Lança erro (assert) em caso de falha, para o busted reportar a mensagem.
local function evalExpectation(node, ctx)
    local results, query, logger = ctx.results, ctx.query, ctx.logger
    local tag = node.tag

    if tag == "expectTop" then
        local n = tonumber(node.attrs.n) or #results
        local minHits = tonumber(node.attrs.minHits) or n
        local attrs = conceptAttrs(node)
        local hits = 0
        for i = 1, math.min(n, #results) do
            if itemMatchesAttrs(results[i].item, attrs) then
                hits = hits + 1
            end
        end
        assert(
            hits >= minHits,
            string.format("expectTop: esperado >=%d hits em top %d, obteve %d (query=%q)", minHits, n, hits, query.raw)
        )
    elseif tag == "expectAll" then
        local top = tonumber(node.attrs.top) or #results
        local attrs = conceptAttrs(node)
        for i = 1, math.min(top, #results) do
            assert(
                itemMatchesAttrs(results[i].item, attrs),
                string.format(
                    "expectAll: item #%d (%s) não satisfaz atributos (query=%q)",
                    i,
                    results[i].item.fields.name and results[i].item.fields.name.raw or "?",
                    query.raw
                )
            )
        end
        assert(#results >= top, string.format("expectAll: esperado >= %d resultados, obteve %d", top, #results))
    elseif tag == "expectFirst" then
        assert(#results >= 1, "expectFirst: nenhum resultado (query=" .. tostring(query.raw) .. ")")
        local nameRaw = results[1].item.fields.name and results[1].item.fields.name.raw or ""
        assert(
            nameRaw == node.attrs.name,
            string.format("expectFirst: esperado nome=%q, obteve %q (query=%q)", node.attrs.name, nameRaw, query.raw)
        )
    elseif tag == "expectRankBefore" then
        local posA, posB = nil, nil
        for i, r in ipairs(results) do
            local nm = r.item.fields.name and r.item.fields.name.raw
            if nm == node.attrs.a then
                posA = posA or i
            end
            if nm == node.attrs.b then
                posB = posB or i
            end
        end
        assert(posA, "expectRankBefore: item a=" .. tostring(node.attrs.a) .. " não encontrado nos resultados")
        assert(posB, "expectRankBefore: item b=" .. tostring(node.attrs.b) .. " não encontrado nos resultados")
        assert(
            posA < posB,
            string.format(
                "expectRankBefore: esperado %s antes de %s (posições %d, %d)",
                node.attrs.a,
                node.attrs.b,
                posA,
                posB
            )
        )
    elseif tag == "expectEmpty" then
        assert(#results == 0, string.format("expectEmpty: esperado 0 resultados, obteve %d", #results))
    elseif tag == "expectMaxScore" then
        local maxAllowed = tonumber(node.attrs.value)
        local best = results[1] and results[1].score or 0
        assert(best <= maxAllowed, string.format("expectMaxScore: melhor score %.3f > %.3f", best, maxAllowed))
    elseif tag == "expectConstraint" then
        local specName = node.attrs.spec
        local op = node.attrs.op
        local min = tonumber(node.attrs.min)
        local max = tonumber(node.attrs.max)
        local found = nil
        for _, c in ipairs(query.constraints or {}) do
            if c.quantity == specName and c.op == op then
                found = c
                break
            end
        end
        assert(
            found,
            string.format("expectConstraint: constraint %s/%s não encontrada (query=%q)", specName, op, query.raw)
        )
        local TOL = 0.1
        if min then
            assert(
                found.min and math.abs(found.min - min) <= TOL,
                string.format("expectConstraint: min esperado %.2f, obteve %s", min, tostring(found.min))
            )
        end
        if max then
            assert(
                found.max and math.abs(found.max - max) <= TOL,
                string.format("expectConstraint: max esperado %.2f, obteve %s", max, tostring(found.max))
            )
        end
    elseif tag == "expectConcept" then
        local found = false
        for _, c in ipairs(query.concepts or {}) do
            if c.kind == node.attrs.kind and IdMatcher.matches(node.attrs.value, c.value) then
                found = true
                break
            end
        end
        assert(
            found,
            string.format(
                "expectConcept: %s=%s não encontrado (query=%q)",
                node.attrs.kind,
                node.attrs.value,
                query.raw
            )
        )
    elseif tag == "expectTerms" then
        local expectedText = xml.text(node)
        local expected = splitAttr(expectedText)
        local got = {}
        for _, t in ipairs(query.terms or {}) do
            got[#got + 1] = t.text
        end
        assert(
            table.concat(expected, " ") == table.concat(got, " "),
            string.format(
                "expectTerms: esperado [%s], obteve [%s]",
                table.concat(expected, " "),
                table.concat(got, " ")
            )
        )
    elseif tag == "expectReasons" then
        assert(#results >= 1, "expectReasons: nenhum resultado")
        local field, kind = node.attrs.field, node.attrs.kind
        local found = false
        for _, r in ipairs(results[1].reasons or {}) do
            if (not field or r.field == field) and (not kind or r.kind == kind) then
                found = true
                break
            end
        end
        assert(found, string.format("expectReasons: nenhum reason com field=%s kind=%s no top-1", field, kind))
    elseif tag == "expectNoError" then
        assert(not (logger and logger:hasLevel("error")), "expectNoError: logger registrou erro")
    else
        error("tipo de expectativa golden desconhecido: " .. tostring(tag))
    end
end

-- Expectativas que definem um conjunto de itens relevantes (para as métricas
-- de ranking). As demais (constraint, termos, vazio…) não entram em P@5/MRR.
local RANKED_TAGS = { expectTop = true, expectAll = true, expectFirst = true }
-- Casos que exigem ao menos um resultado: só eles entram na taxa de vazios
-- (casos só de parser, negativos e expectEmpty ficam fora da conta).
local NEEDS_RESULTS_TAGS =
    { expectTop = true, expectAll = true, expectFirst = true, expectRankBefore = true, expectReasons = true }

--- Predicado de relevância do caso: um item é relevante se satisfaz os
--- atributos de alguma expectativa de ranking (expectFirst: nome exato).
--- @return (fun(item:IndexedItem):boolean)|nil  nil = caso sem julgamento de relevância
local function relevanceOf(caseNode)
    local preds = {}
    for _, node in ipairs(caseNode.children) do
        if RANKED_TAGS[node.tag] then
            if node.tag == "expectFirst" then
                local name = node.attrs.name
                preds[#preds + 1] = function(item)
                    return item.fields.name ~= nil and item.fields.name.raw == name
                end
            else
                local attrs = conceptAttrs(node)
                preds[#preds + 1] = function(item)
                    return itemMatchesAttrs(item, attrs)
                end
            end
        end
    end
    if #preds == 0 then
        return nil
    end
    return function(item)
        for _, p in ipairs(preds) do
            if p(item) then
                return true
            end
        end
        return false
    end
end

--- Métricas de ranking de um caso (F2 §2.6): precisão@5 sobre k = min(5,
--- relevantes no corpus) — assim um caso com 1 item relevante ainda pode
--- valer 1.0 — e reciprocal rank do primeiro relevante.
--- @return {p5:number, rr:number}|nil
function M.rankMetrics(caseNode, results, index)
    local isRelevant = relevanceOf(caseNode)
    if not isRelevant then
        return nil
    end
    local relevantInCorpus = 0
    for _, item in ipairs(index and index.items or {}) do
        if isRelevant(item) then
            relevantInCorpus = relevantInCorpus + 1
        end
    end
    local k = math.min(5, relevantInCorpus)
    local hits, rr = 0, 0
    for i, r in ipairs(results) do
        if isRelevant(r.item) then
            if i <= k then
                hits = hits + 1
            end
            if rr == 0 then
                rr = 1 / i
            end
        end
        if i >= k and rr > 0 then
            break
        end
    end
    return { p5 = (k > 0) and (hits / k) or 0, rr = rr }
end

--- Acumulador das métricas agregadas do corpus golden.
function M.newMetrics()
    return { cases = 0, needResults = 0, empty = 0, ranked = 0, p5Sum = 0, rrSum = 0 }
end

--- @param acc table  M.newMetrics()
--- @param caseResult table  retorno de M.runCase
function M.accumulate(acc, caseResult)
    acc.cases = acc.cases + 1
    if caseResult.needsResults then
        acc.needResults = acc.needResults + 1
        if caseResult.empty then
            acc.empty = acc.empty + 1
        end
    end
    if caseResult.rank then
        acc.ranked = acc.ranked + 1
        acc.p5Sum = acc.p5Sum + caseResult.rank.p5
        acc.rrSum = acc.rrSum + caseResult.rank.rr
    end
end

--- Texto do relatório (impresso e gravado em dist/golden-metrics.txt).
function M.formatMetrics(acc)
    local lines = {
        string.format("casos: %d (com julgamento de ranking: %d)", acc.cases, acc.ranked),
        string.format("precisao@5: %.3f", acc.ranked > 0 and acc.p5Sum / acc.ranked or 0),
        string.format("MRR: %.3f", acc.ranked > 0 and acc.rrSum / acc.ranked or 0),
        string.format(
            "taxa de consultas vazias: %.3f (%d de %d casos que exigem resultado)",
            acc.needResults > 0 and acc.empty / acc.needResults or 0,
            acc.empty,
            acc.needResults
        ),
    }
    return table.concat(lines, "\n") .. "\n"
end

--- Grava o relatório; `dist/` pode não existir num checkout limpo.
function M.writeMetrics(acc, path)
    path = path or "dist/golden-metrics.txt"
    local fh = io.open(path, "w")
    if not fh then
        os.execute("mkdir -p dist")
        fh = io.open(path, "w")
    end
    if fh then
        fh:write(M.formatMetrics(acc))
        fh:close()
    end
    return fh ~= nil
end

--- Roda um único <case>; retorna métricas simples do caso (para agregação).
--- @param primaryLocale string|nil  "pt" (padrão) ou "en" (tests/golden/queries.en.xml)
--- @param metrics table|nil  acumulador (M.newMetrics); preenchido mesmo se o caso falhar
function M.runCase(caseNode, fixtureProfile, primaryLocale, weightsOverride, metrics)
    local entry = M.serviceFor(fixtureProfile, primaryLocale, weightsOverride)
    local query = caseNode.attrs.query
    local ui = nil -- filtros de UI entram na F7 (painel); FilterEngine já aplica constraints
    local results, parsedQuery = entry.service:search(query, ui)
    local ctx = {
        results = results,
        query = parsedQuery or { raw = query, terms = {}, concepts = {}, constraints = {} },
        logger = entry.logger,
        metrics = metrics,
    }
    -- Métricas antes das asserções: um caso que falha também conta no relatório.
    local needsResults = false
    for _, node in ipairs(caseNode.children) do
        if NEEDS_RESULTS_TAGS[node.tag] then
            needsResults = true
        end
    end
    local index = entry.lifecycle and entry.lifecycle.index
    local caseResult = {
        empty = (#results == 0),
        needsResults = needsResults,
        rank = M.rankMetrics(caseNode, results, index),
    }
    if ctx.metrics then
        M.accumulate(ctx.metrics, caseResult)
    end
    for _, node in ipairs(caseNode.children) do
        evalExpectation(node, ctx)
    end
    return caseResult
end

--- Carrega um arquivo queries.<lang>.xml e devolve a lista de <case>.
function M.loadCases(path)
    local root = xml.load(path)
    assert(root, "arquivo golden não encontrado: " .. path)
    return xml.children(root, "case")
end

return M
