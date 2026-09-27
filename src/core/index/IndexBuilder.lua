-- Constrói um SearchIndex a partir de RawItem[] (PRD §6.1, ADR-04). Cada item
-- é processado dentro de um pcall (RF-062): falha = item descartado, nunca
-- aborta a construção inteira. Suporta construção fatiada via begin/step
-- (orçamento por frame) e construção direta via build.
local NS = SmartShopSearch
local Tokenizer = NS.core.Tokenizer
local SearchIndex = NS.core.SearchIndex

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

local function buildField(self, raw, source, altSource)
    local text = raw[source]
    if text == nil or text == "" then
        text = altSource and raw[altSource] or nil
    end
    if text == nil or text == "" then
        return nil
    end
    local norm = self.normalizer:normalize(tostring(text))
    if norm == "" then
        return nil
    end
    local tokens = {}
    for _, tok in ipairs(Tokenizer.tokenize(norm)) do
        tokens[#tokens + 1] = tok.text
    end
    return { raw = tostring(text), norm = norm, tokens = tokens }
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

local function addNumeric(index, specId, value, itemId)
    local list = index.numeric[specId]
    if not list then
        list = {}
        index.numeric[specId] = list
    end
    list[#list + 1] = { value = value, id = itemId }
end

--- Extrai um IndexedItem "puro" de um RawItem, sem tocar no índice (o id
--- final só é conhecido depois de decidir manter o item — ver step(): itens
--- descartados não podem deixar postings/facets órfãs sob um id que nunca
--- entra em `index.items`, senão o próximo item reaproveitaria o mesmo id).
--- @return IndexedItem|nil item, string|nil reason, table skippedCounts
local function extractItem(self, raw)
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
        phrases = {},
    }

    for _, def in ipairs(TEXT_FIELDS) do
        local field = buildField(self, raw, def.source, def.altSource)
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
            item.specs[specId] = { value = value, unit = spec.unit, source = "primary" }
        else
            skippedCounts["invalid-spec:" .. specId] = (skippedCounts["invalid-spec:" .. specId] or 0) + 1
        end
    end

    return item, nil, skippedCounts
end

--- Registra um IndexedItem já construído no índice, sob `itemId` (a posição
--- final em `index.items`): postings, facets e faixas numéricas.
local function registerItem(index, item, itemId)
    item.id = itemId
    for field, fieldData in pairs(item.fields) do
        for _, tok in ipairs(fieldData.tokens) do
            index:addPosting(tok, itemId, field)
        end
    end
    if item.price ~= nil then
        addNumeric(index, "price", item.price, itemId)
    end
    for specId, spec in pairs(item.specs) do
        addNumeric(index, specId, spec.value, itemId)
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
        local ok, item, reason, skippedCounts = pcall(extractItem, self, raw)
        if ok then
            if item then
                local itemId = #index.items + 1
                registerItem(index, item, itemId)
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

    for _, list in pairs(index.numeric) do
        table.sort(list, function(a, b)
            return a.value < b.value
        end)
    end

    for token in pairs(index.vocabulary) do
        index:indexPrefixes(token)
    end

    for token, df in pairs(index.vocabulary) do
        index.idf[token] = math.log(1 + N / df)
    end

    index.skipped = state.skipped
end

---@param rawItems RawItem[]
---@return SearchIndex
function IndexBuilder:build(rawItems)
    local state = self:begin(rawItems)
    self:step(state, nil, nil)
    return state.index
end

NS.core.IndexBuilder = IndexBuilder
