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
