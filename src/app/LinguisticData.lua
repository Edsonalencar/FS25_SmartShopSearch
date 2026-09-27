-- Agrega os dados linguísticos por locale (ADR-06), vindos da porta
-- DataLoader (load(locale, name) -> table|nil). Idioma do jogo primeiro,
-- depois "en" sempre (S-06). Arquivo ausente = conjunto vazio, com um único
-- warning por (locale, categoria).
local NS = SmartShopSearch
local LinguisticData = {}
LinguisticData.__index = LinguisticData

---@param dataLoader table  porta DataLoader
---@param locales string[]  ex. GameLocale.dataLocales() -> {"pt", "en"}
---@param logger table|nil
function LinguisticData.new(dataLoader, locales, logger)
    return setmetatable({
        dataLoader = dataLoader,
        locales = locales or { "en" },
        logger = logger,
        cache = {},
        warned = {},
    }, LinguisticData)
end

--- @param name string  "aliases" | "units" | "numbers" | "comparators" | "stopwords" | "context"
--- @return table[]  uma entrada por locale que tiver o dado, na ordem de `locales`
function LinguisticData:load(name)
    if self.cache[name] then
        return self.cache[name]
    end
    local out = {}
    for _, locale in ipairs(self.locales) do
        local ok, data = pcall(function()
            return self.dataLoader:load(locale, name)
        end)
        if ok and data then
            out[#out + 1] = data
        else
            local key = locale .. ":" .. name
            if not self.warned[key] then
                self.warned[key] = true
                if self.logger then
                    self.logger:warning("data", "dado linguístico ausente: %s/%s", locale, name)
                end
            end
        end
    end
    self.cache[name] = out
    return out
end

function LinguisticData:aliases()
    return self:load("aliases")
end
function LinguisticData:units()
    return self:load("units")
end
function LinguisticData:numbers()
    return self:load("numbers")
end
function LinguisticData:comparators()
    return self:load("comparators")
end
function LinguisticData:stopwords()
    return self:load("stopwords")
end
function LinguisticData:context()
    return self:load("context")
end

--- data/common/units.xml (quantidades canônicas + sequências protegidas):
--- não é por locale, então é carregado uma única vez sob o pseudo-locale
--- "common" (mesma porta DataLoader, mesma estrutura de diretórios).
---@return table|nil {quantities, protected}
function LinguisticData:commonUnits()
    if self.commonUnitsCache ~= nil then
        return self.commonUnitsCache or nil
    end
    local ok, data = pcall(function()
        return self.dataLoader:load("common", "units")
    end)
    if ok and data then
        self.commonUnitsCache = data
    else
        self.commonUnitsCache = false
        if self.logger then
            self.logger:warning("data", "dado linguístico ausente: common/units")
        end
    end
    return self.commonUnitsCache or nil
end

NS.app.LinguisticData = LinguisticData
