-- Implementação de teste da porta DataLoader: lê src/data/<locale>/<name>.xml
-- com o parser mínimo de tests/support/xml.lua (equivalente ao adapter
-- adapters/XmlDataLoader.lua, que usa a API XMLFile do jogo).
local xml = require("tests.support.xml")

local FileDataLoader = {}
FileDataLoader.__index = FileDataLoader

---@param baseDir string|nil  padrão "src/data"
function FileDataLoader.new(baseDir)
    return setmetatable({ baseDir = baseDir or "src/data" }, FileDataLoader)
end

local PARSERS = {
    aliases = function(root)
        local out = {}
        for _, node in ipairs(xml.children(root, "concept")) do
            local terms = {}
            for _, t in ipairs(xml.children(node, "term")) do
                terms[#terms + 1] = xml.text(t)
            end
            out[#out + 1] = { kind = node.attrs.kind, id = node.attrs.id, terms = terms }
        end
        return out
    end,
}

---@param locale string
---@param name string
---@return table|nil
function FileDataLoader:load(locale, name)
    local path = self.baseDir .. "/" .. locale .. "/" .. name .. ".xml"
    local fh = io.open(path, "r")
    if not fh then
        return nil
    end
    fh:close()
    local root = xml.load(path)
    if not root then
        return nil
    end
    local parser = PARSERS[name]
    if not parser then
        return nil
    end
    return parser(root)
end

return FileDataLoader
