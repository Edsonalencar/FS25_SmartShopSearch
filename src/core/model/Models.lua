-- Anotações LuaLS dos contratos de dados (PRD §6, com os acréscimos deste
-- spec em §2.2, §4.4 e §8.1). Tabelas Lua simples; nenhum modelo guarda
-- referência mutável ao StoreItem além de `ref` (somente leitura).
local NS = SmartShopSearch
local Models = {}

---@class RawItem
---@field xmlFilename string
---@field name string|nil
---@field brand string|nil
---@field brandTitle string|nil
---@field categoryId string|nil
---@field categoryTitle string|nil
---@field species string|nil
---@field price number|nil
---@field origin "base"|"dlc"|"mod"|nil
---@field modName string|nil
---@field modTitle string|nil
---@field author string|nil
---@field dlcTitle string|nil
---@field specs table<string, number>|nil
---@field ref table|nil  -- StoreItem original (jogo); nil nos testes offline

---@class IndexedField
---@field raw string     -- texto original para exibição
---@field norm string    -- normalizado (§6.2 PRD)
---@field tokens string[] -- tokens normalizados

---@class SpecValue
---@field value number   -- sempre na unidade canônica (§6.3 PRD)
---@field unit string    -- "kw", "l", "m", "kmh", "kg", "money"
---@field source string  -- de onde veio (diagnóstico)

---@class IndexedItem
---@field id integer              -- posição estável no índice
---@field ref table|nil           -- StoreItem original (somente leitura, nunca mutado)
---@field xmlFilename string      -- chave de identidade/assinatura
---@field species string          -- "vehicle" | "handTool" | "placeable" | …
---@field fields table<string, IndexedField>  -- name, brand, category, mod, author, dlc
---@field specs table<string, SpecValue>      -- power, capacity, width, speed, …
---@field price number|nil
---@field origin "base"|"dlc"|"mod"
---@field brandId string|nil
---@field categoryIdInternal string|nil
---@field phrases string[]|nil    -- frases normalizadas multi-palavra (F3, fuzzy de frase)
---@field compat CompatInfo|nil   -- preenchido sob demanda (F8)

---@class QueryTerm
---@field text string     -- normalizado
---@field span integer[]  -- {inicio, fim} na consulta original
---@field fuzzyMax integer -- distância máxima permitida para este termo

---@class QueryConcept
---@field kind "category"|"brand"|"species"|"origin"
---@field value string    -- id canônico (ex.: "TRACTORSM", "JOHNDEERE")
---@field confidence number -- 0..1
---@field span integer[]

---@class Constraint
---@field quantity string  -- "power" | "volume" | "money" | … (grandeza; L10 do spec)
---@field op "gt"|"gte"|"lt"|"lte"|"eq"|"between"|"approx"
---@field min number|nil   -- unidade canônica
---@field max number|nil
---@field span integer[]

---@class QueryContext
---@field kind "compatibleWith"
---@field target "selected"|"query"
---@field targetTerms string[]
---@field span integer[]

---@class Query
---@field raw string
---@field terms QueryTerm[]         -- termos textuais restantes (RF-036)
---@field concepts QueryConcept[]   -- categoria/marca resolvidas por alias
---@field constraints Constraint[]  -- numéricos
---@field context QueryContext|nil  -- L4 do spec
---@field locale string
---@field warnings string[]        -- partes não compreendidas (diagnóstico)

---@class UiFilters
---@field category table|nil  -- {ids=...}
---@field brand table|nil
---@field origin table|nil
---@field species table|nil
---@field price {min:number|nil, max:number|nil}|nil
---@field specs table<string, {min:number|nil, max:number|nil}>|nil

---@class MatchReason
---@field kind "exact"|"prefix"|"fuzzy"|"alias"|"constraint"|"compat"
---@field field string      -- "name", "brand", "spec.power", …
---@field query string      -- trecho da consulta
---@field matched string    -- valor do item
---@field detail string|nil -- ex.: "distância 1", "221 cv ∈ [200, 300]"
---@field weight number     -- contribuição ao score

---@class SearchResult
---@field item IndexedItem
---@field score number     -- 0..1 após normalização
---@field coverage number  -- fração de termos/conceitos satisfeitos
---@field reasons MatchReason[]

---@class CompatInfo
---@field attach table<string, boolean>       -- tipos de junta que o veículo oferece
---@field inputAttach table<string, boolean>  -- tipos de junta que o implemento aceita
---@field power number|nil                    -- kW
---@field neededPower number|nil              -- kW
---@field combinations table<string, boolean> -- xmlFilename declarados

---@param item IndexedItem
---@param score number
---@param coverage number
---@param reasons MatchReason[]
---@return SearchResult
function Models.result(item, score, coverage, reasons)
    return { item = item, score = score, coverage = coverage, reasons = reasons or {} }
end

---@param kind string
---@param field string
---@param query string
---@param matched string
---@param detail string|nil
---@param weight number|nil
---@return MatchReason
function Models.reason(kind, field, query, matched, detail, weight)
    return { kind = kind, field = field, query = query, matched = matched, detail = detail, weight = weight or 0 }
end

NS.core.Models = Models
