-- Implementa a porta DataLoader em jogo: lê src/data/<locale>/<name>.xml via
-- XMLFile. A API exata de iteração [A VALIDAR na F5] — este adapter não é
-- testado offline (Testing Strategy: adapters cobertos pelo smoke em jogo).
-- Os testes usam tests/stubs/FileDataLoader.lua (tests/support/xml.lua).
local NS = SmartShopSearch
local XmlDataLoader = {}
XmlDataLoader.__index = XmlDataLoader

---@param modDir string  g_currentModDirectory
function XmlDataLoader.new(modDir)
    return setmetatable({ modDir = modDir }, XmlDataLoader)
end

-- Cada parser recebe o XMLFile já carregado e devolve a tabela genérica
-- esperada por app/LinguisticData (mesmo formato usado pelos testes).
local PARSERS = {
    aliases = function(xmlFile)
        local out = {}
        -- [A VALIDAR na F5]: assinatura exata de XMLFile:iterate.
        xmlFile:iterate("aliases.concept", function(_, conceptKey)
            local kind = xmlFile:getString(conceptKey .. "#kind")
            local id = xmlFile:getString(conceptKey .. "#id")
            local terms = {}
            xmlFile:iterate(conceptKey .. ".term", function(_, termKey)
                local text = xmlFile:getString(termKey)
                if text then
                    terms[#terms + 1] = text
                end
            end)
            if kind and id then
                out[#out + 1] = { kind = kind, id = id, terms = terms }
            end
        end)
        return out
    end,

    -- Serve tanto data/common/units.xml (quantity + protected) quanto
    -- data/<lang>/units.xml (unit alias->canonical direto na raiz).
    units = function(xmlFile)
        local out = {}
        local hasQuantities = false
        xmlFile:iterate("units.quantity", function(_, qKey)
            hasQuantities = true
            out.quantities = out.quantities or {}
            local units = {}
            xmlFile:iterate(qKey .. ".unit", function(_, uKey)
                units[#units + 1] =
                    { alias = xmlFile:getString(uKey .. "#alias"), factor = xmlFile:getFloat(uKey .. "#factor") }
            end)
            local specsRaw = xmlFile:getString(qKey .. "#specs") or ""
            local specs = {}
            for spec in specsRaw:gmatch("%S+") do
                specs[#specs + 1] = spec
            end
            out.quantities[#out.quantities + 1] = {
                id = xmlFile:getString(qKey .. "#id"),
                canonical = xmlFile:getString(qKey .. "#canonical"),
                specs = specs,
                units = units,
            }
        end)
        xmlFile:iterate("units.protected", function(_, pKey)
            out.protected = out.protected or {}
            out.protected[#out.protected + 1] =
                { from = xmlFile:getString(pKey .. "#from"), to = xmlFile:getString(pKey .. "#to") }
        end)
        if not hasQuantities then
            xmlFile:iterate("units.unit", function(_, uKey)
                out.units = out.units or {}
                out.units[#out.units + 1] =
                    { alias = xmlFile:getString(uKey .. "#alias"), canonical = xmlFile:getString(uKey .. "#canonical") }
            end)
        end
        return out
    end,

    numbers = function(xmlFile)
        local multipliers, spelled = {}, {}
        xmlFile:iterate("numbers.multiplier", function(_, mKey)
            multipliers[xmlFile:getString(mKey .. "#word")] = xmlFile:getFloat(mKey .. "#factor")
        end)
        xmlFile:iterate("numbers.spelled", function(_, sKey)
            spelled[xmlFile:getString(sKey .. "#word")] = xmlFile:getFloat(sKey .. "#value")
        end)
        return {
            decimal = xmlFile:getString("numbers#decimal") or ".",
            thousands = xmlFile:getString("numbers#thousands") or ",",
            multipliers = multipliers,
            spelled = spelled,
        }
    end,

    comparators = function(xmlFile)
        local ops = {}
        xmlFile:iterate("comparators.op", function(_, opKey)
            local id = xmlFile:getString(opKey .. "#id")
            local patterns = {}
            xmlFile:iterate(opKey .. ".p", function(_, pKey)
                patterns[#patterns + 1] = xmlFile:getString(pKey)
            end)
            ops[id] = patterns
        end)
        local range = {}
        xmlFile:iterate("comparators.range.p", function(_, pKey)
            range[#range + 1] = xmlFile:getString(pKey)
        end)
        return { ops = ops, range = range }
    end,

    stopwords = function(xmlFile)
        local set = {}
        xmlFile:iterate("stopwords.w", function(_, wKey)
            local word = xmlFile:getString(wKey)
            if word then
                set[word] = true
            end
        end)
        return set
    end,

    context = function(xmlFile)
        local out = { compat = {}, self = {} }
        xmlFile:iterate("context.compat.p", function(_, pKey)
            out.compat[#out.compat + 1] = xmlFile:getString(pKey)
        end)
        xmlFile:iterate("context.self.p", function(_, pKey)
            out.self[#out.self + 1] = xmlFile:getString(pKey)
        end)
        return out
    end,
}

---@param locale string
---@param name string
---@return table|nil
function XmlDataLoader:load(locale, name)
    if type(XMLFile) ~= "table" or type(XMLFile.load) ~= "function" then
        return nil
    end
    local path = self.modDir .. "data/" .. locale .. "/" .. name .. ".xml"
    local xmlFile = XMLFile.load("SmartShopSearchData", path)
    if not xmlFile then
        return nil
    end
    local parser = PARSERS[name]
    local result = parser and parser(xmlFile) or nil
    if type(xmlFile.delete) == "function" then
        xmlFile:delete()
    end
    return result
end

NS.adapters.XmlDataLoader = XmlDataLoader
