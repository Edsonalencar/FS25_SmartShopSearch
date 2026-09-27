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

    -- Serve tanto data/common/units.xml (quantity + protected) quanto
    -- data/<lang>/units.xml (unit alias->canonical direto na raiz).
    units = function(root)
        local out = {}
        local quantityNodes = xml.children(root, "quantity")
        if #quantityNodes > 0 then
            out.quantities = {}
            for _, q in ipairs(quantityNodes) do
                local units = {}
                for _, u in ipairs(xml.children(q, "unit")) do
                    units[#units + 1] = { alias = u.attrs.alias, factor = tonumber(u.attrs.factor) }
                end
                local specs = {}
                for spec in (q.attrs.specs or ""):gmatch("%S+") do
                    specs[#specs + 1] = spec
                end
                out.quantities[#out.quantities + 1] =
                    { id = q.attrs.id, canonical = q.attrs.canonical, specs = specs, units = units }
            end
        end
        local protectedNodes = xml.children(root, "protected")
        if #protectedNodes > 0 then
            out.protected = {}
            for _, p in ipairs(protectedNodes) do
                out.protected[#out.protected + 1] = { from = p.attrs.from, to = p.attrs.to }
            end
        end
        local unitNodes = xml.children(root, "unit")
        if #unitNodes > 0 then
            out.units = {}
            for _, u in ipairs(unitNodes) do
                out.units[#out.units + 1] = { alias = u.attrs.alias, canonical = u.attrs.canonical }
            end
        end
        return out
    end,

    numbers = function(root)
        local multipliers, spelled = {}, {}
        for _, m in ipairs(xml.children(root, "multiplier")) do
            multipliers[m.attrs.word] = tonumber(m.attrs.factor)
        end
        for _, s in ipairs(xml.children(root, "spelled")) do
            spelled[s.attrs.word] = tonumber(s.attrs.value)
        end
        return {
            decimal = root.attrs.decimal or ".",
            thousands = root.attrs.thousands or ",",
            multipliers = multipliers,
            spelled = spelled,
        }
    end,

    comparators = function(root)
        local ops = {}
        for _, opNode in ipairs(xml.children(root, "op")) do
            local patterns = {}
            for _, p in ipairs(xml.children(opNode, "p")) do
                patterns[#patterns + 1] = xml.text(p)
            end
            ops[opNode.attrs.id] = patterns
        end
        local range = {}
        local rangeNode = xml.child(root, "range")
        if rangeNode then
            for _, p in ipairs(xml.children(rangeNode, "p")) do
                range[#range + 1] = xml.text(p)
            end
        end
        return { ops = ops, range = range }
    end,

    stopwords = function(root)
        local set = {}
        for _, w in ipairs(xml.children(root, "w")) do
            set[xml.text(w)] = true
        end
        return set
    end,

    context = function(root)
        local out = { compat = {}, self = {} }
        local compatNode = xml.child(root, "compat")
        if compatNode then
            for _, p in ipairs(xml.children(compatNode, "p")) do
                out.compat[#out.compat + 1] = xml.text(p)
            end
        end
        local selfNode = xml.child(root, "self")
        if selfNode then
            for _, p in ipairs(xml.children(selfNode, "p")) do
                out.self[#out.self + 1] = xml.text(p)
            end
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
