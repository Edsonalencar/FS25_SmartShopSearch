-- Constrói um SearchIndex a partir de RawItem[] (PRD §6.1, ADR-04). Cada item
-- é processado dentro de um pcall (RF-062): falha = item descartado, nunca
-- aborta a construção inteira. Suporta construção fatiada via begin/step
-- (orçamento por frame) e construção direta via build.
local NS = SmartShopSearch
local Tokenizer = NS.core.Tokenizer
local SearchIndex = NS.core.SearchIndex
-- TrigramIndex.lua vem depois de IndexBuilder.lua no manifesto (F3): acessar
-- via NS.core.TrigramIndex em tempo de chamada, não no topo do arquivo.

local IndexBuilder = {}
IndexBuilder.__index = IndexBuilder

-- Não usa bitmask real: cada posting guarda uma tabela {[fieldName]=true},
-- porque o Lua 5.1 não tem operadores bitwise (desvio consciente do PRD
-- §6.1, com o mesmo efeito prático). `fieldIds` fica só como referência de
-- prioridade de campo para outros módulos (FieldMatcher, F2.3).
local DEFAULT_FIELD_IDS = { name = 1, brand = 2, category = 4, mod = 8, author = 16, dlc = 32, spec = 64 }

local TEXT_FIELDS = {
    { field = "name", source = "name" },
    { field = "brand", source = "brandTitle", altSource = "brand" },
    { field = "category", source = "categoryTitle", altSource = "categoryId" },
    { field = "mod", source = "modTitle", altSource = "modName" },
    { field = "author", source = "author" },
    { field = "dlc", source = "dlcTitle" },
}

local function isFiniteNonNegativeNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= 0
end

---@param normalizer TextNormalizer
---@param opts table|nil
function IndexBuilder.new(normalizer, opts)
    opts = opts or {}
    return setmetatable({
        normalizer = normalizer,
        fieldIds = opts.fieldIds or DEFAULT_FIELD_IDS,
    }, IndexBuilder)
end

-- Campos cujo texto se repete muito entre itens (marca, categoria, mod…):
-- o IndexedField é compartilhado entre os itens com o mesmo texto durante um
-- build (RNF-003, memória). Os campos são somente leitura depois do build.
local SHARED_FIELDS = { brand = true, category = true, mod = true, author = true, dlc = true }

local function buildField(self, raw, source, altSource, cache)
    local text = raw[source]
    if text == nil or text == "" then
        text = altSource and raw[altSource] or nil
    end
    if text == nil or text == "" then
        return nil
    end
    text = tostring(text)
    if cache then
        local cached = cache[text]
        if cached ~= nil then
            return cached or nil
        end
    end
    local field = self:_makeField(text)
    if cache then
        cache[text] = field or false
    end
    return field
end

function IndexBuilder:_makeField(text)
    local norm = self.normalizer:normalize(text)
    if norm == "" then
        return nil
    end
    local tokens = {}
    for _, tok in ipairs(Tokenizer.tokenize(norm)) do
        tokens[#tokens + 1] = tok.text
    end
    return { raw = text, norm = norm, tokens = tokens }
end

local function addFacet(index, facetName, key, itemId)
    if key == nil or key == "" then
        return
    end
    local facet = index.facets[facetName]
    if not facet then
        facet = {}
        index.facets[facetName] = facet
    end
    local set = facet[key]
    if not set then
        set = {}
        facet[key] = set
    end
    set[itemId] = true
end

-- Durante o build, as faixas numéricas acumulam pares {value, id} em
-- `state.numericPairs`; o `finish` ordena e converte para arrays paralelos.
local function addNumeric(state, specId, value, itemId)
    local list = state.numericPairs[specId]
    if not list then
        list = {}
        state.numericPairs[specId] = list
    end
    list[#list + 1] = { value = value, id = itemId }
end

--- Extrai um IndexedItem "puro" de um RawItem, sem tocar no índice (o id
--- final só é conhecido depois de decidir manter o item — ver step(): itens
--- descartados não podem deixar postings/facets órfãs sob um id que nunca
--- entra em `index.items`, senão o próximo item reaproveitaria o mesmo id).
--- @return IndexedItem|nil item, string|nil reason, table skippedCounts
local function extractItem(self, raw, fieldCache)
    local skippedCounts = {}
    if type(raw.xmlFilename) ~= "string" or raw.xmlFilename == "" then
        return nil, "no-id", skippedCounts
    end

    local item = {
        ref = raw.ref,
        xmlFilename = raw.xmlFilename,
        species = raw.species,
        origin = raw.origin or "base",
        brandId = raw.brand,
        categoryIdInternal = raw.categoryId,
        fields = {},
        specs = {},
        price = nil,
    }

    for _, def in ipairs(TEXT_FIELDS) do
        local field = buildField(self, raw, def.source, def.altSource, SHARED_FIELDS[def.field] and fieldCache or nil)
        if field then
            item.fields[def.field] = field
        end
    end

    -- RF-062: item sem NENHUM campo textual (nem sequer nome) ainda é
    -- indexado (AC-RES-02) — apenas fica pesquisável só por facet/spec.

    if raw.price ~= nil then
        if isFiniteNonNegativeNumber(raw.price) then
            item.price = raw.price
        else
            skippedCounts["invalid-spec:price"] = (skippedCounts["invalid-spec:price"] or 0) + 1
        end
    elseif raw.priceRaw ~= nil then
        skippedCounts["invalid-spec:price"] = (skippedCounts["invalid-spec:price"] or 0) + 1
    end

    for specId, spec in pairs(raw.specs or {}) do
        local value = spec.value
        if value == nil and spec.valueRaw ~= nil then
            value = tonumber(spec.valueRaw)
        end
        if isFiniteNonNegativeNumber(value) then
            -- Só o valor (já canônico): `unit` e `source` não são lidos por
            -- ninguém e custariam ~120 B por spec (RNF-003). `source` só
            -- aparece nas specs secundárias (IndexBuilder.applySecondary).
            item.specs[specId] = { value = value }
        else
            skippedCounts["invalid-spec:" .. specId] = (skippedCounts["invalid-spec:" .. specId] or 0) + 1
        end
    end

    return item, nil, skippedCounts
end

--- Registra um IndexedItem já construído no índice, sob `itemId` (a posição
--- final em `index.items`): postings, facets e faixas numéricas.
-- F3: frases multi-palavra destes campos entram no fuzzy de frase (ADR-14).
local PHRASE_FIELDS = { brand = true, category = true, mod = true }

local function registerItem(state, item, itemId)
    local index = state.index
    item.id = itemId
    for field, fieldData in pairs(item.fields) do
        for _, tok in ipairs(fieldData.tokens) do
            index:addPosting(tok, itemId, field)
        end
        if PHRASE_FIELDS[field] and #fieldData.tokens >= 2 then
            local fieldsOfPhrase = index.phrases[fieldData.norm]
            if not fieldsOfPhrase then
                fieldsOfPhrase = {}
                index.phrases[fieldData.norm] = fieldsOfPhrase
            end
            fieldsOfPhrase[field] = true
        end
    end
    if item.price ~= nil then
        addNumeric(state, "price", item.price, itemId)
    end
    for specId, spec in pairs(item.specs) do
        addNumeric(state, specId, spec.value, itemId)
    end
    addFacet(index, "brand", item.brandId, itemId)
    addFacet(index, "category", item.categoryIdInternal, itemId)
    addFacet(index, "origin", item.origin, itemId)
    addFacet(index, "species", item.species, itemId)
end

---@param rawItems RawItem[]
---@return table state
function IndexBuilder:begin(rawItems)
    return {
        rawItems = rawItems,
        cursor = 1,
        index = SearchIndex.new(),
        skipped = {},
        builder = self,
        fieldCache = {},
        numericPairs = {},
    }
end

--- Processa itens até estourar `budgetSec` (medido via `clock`, que expõe
--- `:now()` em segundos). `budgetSec == nil` processa tudo de uma vez.
---@param state table
---@param budgetSec number|nil
---@param clock table|nil  -- {now = fun():number}
---@return boolean done
function IndexBuilder:step(state, budgetSec, clock)
    local index = state.index
    index.skipped = state.skipped
    local startTime = (budgetSec and clock) and clock:now() or nil

    while state.cursor <= #state.rawItems do
        local raw = state.rawItems[state.cursor]
        local ok, item, reason, skippedCounts = pcall(extractItem, self, raw, state.fieldCache)
        if ok then
            if item then
                local itemId = #index.items + 1
                registerItem(state, item, itemId)
                index.items[itemId] = item
            else
                state.skipped[reason] = (state.skipped[reason] or 0) + 1
            end
            for k, n in pairs(skippedCounts or {}) do
                state.skipped[k] = (state.skipped[k] or 0) + n
            end
        else
            state.skipped["build-error"] = (state.skipped["build-error"] or 0) + 1
        end
        state.cursor = state.cursor + 1

        if startTime and clock:now() - startTime >= budgetSec then
            return false
        end
    end

    self:finish(state)
    return true
end

--- Finaliza a construção: ordena `numeric[spec]`, indexa prefixos e calcula IDF.
function IndexBuilder:finish(state) -- luacheck: ignore 212/self
    local index = state.index
    local N = #index.items

    for specId, list in pairs(state.numericPairs) do
        index:setNumeric(specId, list)
    end
    state.numericPairs = {}
    state.fieldCache = nil

    for token in pairs(index.vocabulary) do
        index:indexPrefixes(token)
    end

    for token, df in pairs(index.vocabulary) do
        index.idf[token] = math.log(1 + N / df)
    end

    -- F3: índice de trigramas do vocabulário, para candidatos fuzzy (ADR-05).
    index.trigramIndex = NS.core.TrigramIndex.build(index.vocabulary)
    -- F3/ADR-14: frases multi-palavra dos itens (poucas centenas, distintas).
    index.phraseTrigram = NS.core.TrigramIndex.build(index.phrases)

    index.skipped = state.skipped
end

--- Fração dos itens que têm cada spec (0..1), para decidir quais specs
--- vão para a camada secundária (IndexLifecycle, < 80%).
---@param index SearchIndex
---@param specIds string[]
---@return table<string, number>
function IndexBuilder.specCoverage(index, specIds)
    local out = {}
    local n = #index.items
    for _, specId in ipairs(specIds) do
        local list = index.numeric[specId]
        local count = list and #list.ids or 0
        out[specId] = (n > 0) and (count / n) or 0
    end
    return out
end

--- Aplica specs secundárias (lidas do XML do item, F6) a um índice já
--- construído, de uma vez só: nunca sobrescreve uma spec primária, descarta
--- valores inválidos e reordena as faixas numéricas afetadas.
---@param index SearchIndex
---@param additions table<integer, table<string, number>>  itemId -> {specId = valor canônico}
---@return integer added
function IndexBuilder.applySecondary(index, additions)
    local added = 0
    local newPairs = {}
    for itemId, specs in pairs(additions) do
        local item = index.items[itemId]
        if item then
            for specId, value in pairs(specs) do
                if not item.specs[specId] and isFiniteNonNegativeNumber(value) then
                    item.specs[specId] = { value = value, source = "secondary" }
                    local list = newPairs[specId]
                    if not list then
                        list = {}
                        newPairs[specId] = list
                    end
                    list[#list + 1] = { value = value, id = itemId }
                    added = added + 1
                end
            end
        end
    end
    for specId, list in pairs(newPairs) do
        local existing = index.numeric[specId]
        if existing then
            for i, v in ipairs(existing.values) do
                list[#list + 1] = { value = v, id = existing.ids[i] }
            end
        end
        index:setNumeric(specId, list)
    end
    return added
end

---@param rawItems RawItem[]
---@return SearchIndex
function IndexBuilder:build(rawItems)
    local state = self:begin(rawItems)
    self:step(state, nil, nil)
    return state.index
end

NS.core.IndexBuilder = IndexBuilder
