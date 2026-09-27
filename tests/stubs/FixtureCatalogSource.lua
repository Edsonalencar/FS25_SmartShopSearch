-- Implementação de teste da porta CatalogSource: lê um fixture XML no
-- formato de tests/fixtures/catalog/*.xml (F2 §2.6) e devolve RawItem[].
-- Não valida nada (a validação é responsabilidade do IndexBuilder, RF-061/062):
-- todo atributo é repassado como veio (inclusive ausente ou malformado), para
-- exercitar a resiliência do núcleo.
local xml = require("tests.support.xml")

local FixtureCatalogSource = {}
FixtureCatalogSource.__index = FixtureCatalogSource

local function toNumberOrNil(s)
    if s == nil then
        return nil
    end
    return tonumber(s)
end

--- @param path string  caminho do fixture XML (ex. "tests/fixtures/catalog/synthetic.xml")
--- @param opts table|nil  {failOnItems=true} para simular falha de items() (resiliência)
function FixtureCatalogSource.new(path, opts)
    return setmetatable({ path = path, opts = opts or {}, cache = nil }, FixtureCatalogSource)
end

local function parseItem(node)
    local item = {
        xmlFilename = node.attrs.xmlFilename,
        name = node.attrs.name,
        brand = node.attrs.brand,
        brandTitle = node.attrs.brandTitle,
        categoryId = node.attrs.categoryId,
        categoryTitle = node.attrs.categoryTitle,
        species = node.attrs.species,
        price = node.attrs.price ~= nil and toNumberOrNil(node.attrs.price) or nil,
        origin = node.attrs.origin,
        modName = node.attrs.modName,
        modTitle = node.attrs.modTitle,
        author = node.attrs.author,
        dlcTitle = node.attrs.dlcTitle,
        specs = {},
    }
    -- preserva o texto bruto do preço quando não numérico (ex. "abc"), para
    -- que o IndexBuilder possa descartá-lo e contar invalid-spec:price.
    if node.attrs.price ~= nil and item.price == nil then
        item.priceRaw = node.attrs.price
    end
    for _, specNode in ipairs(xml.children(node, "spec")) do
        local id = specNode.attrs.id
        if id then
            local value = specNode.attrs.value
            item.specs[id] = { valueRaw = value, value = tonumber(value), unit = specNode.attrs.unit }
        end
    end
    return item
end

function FixtureCatalogSource:items()
    if self.opts.failOnItems then
        error("falha simulada em CatalogSource:items()")
    end
    if self.cache then
        return self.cache
    end
    local root = xml.load(self.path)
    assert(root, "fixture não encontrado: " .. tostring(self.path))
    local out = {}
    for _, node in ipairs(xml.children(root, "item")) do
        out[#out + 1] = parseItem(node)
    end
    self.cache = out
    return out
end

return FixtureCatalogSource
