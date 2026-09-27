require("tests.support.load").load()
local NS = SmartShopSearch
local TextNormalizer = NS.core.TextNormalizer
local IndexBuilder = NS.core.IndexBuilder
local Signature = NS.core.Signature

local function normalizer()
    return TextNormalizer.new({ protected = {}, currency = {} })
end

local function builder()
    return IndexBuilder.new(normalizer())
end

describe("IndexBuilder", function()
    it("indexa item sem marca continuando por nome (AC-RES-02)", function()
        local index = builder():build({
            { xmlFilename = "a.xml", name = "Trator Sem Marca", categoryId = "TRACTORSM", price = 100000 },
        })
        assert.are.equal(1, #index.items)
        assert.is_not_nil(index:postingsFor("trator"))
    end)

    it("descarta price inválido (não numérico) e conta invalid-spec:price", function()
        local index = builder():build({
            { xmlFilename = "a.xml", name = "X", price = "abc" },
        })
        assert.are.equal(1, #index.items)
        assert.is_nil(index.items[1].price)
        assert.are.equal(1, index.skipped["invalid-spec:price"])
    end)

    it("descarta spec inválido (negativo) e conta invalid-spec:<id>", function()
        local index = builder():build({
            { xmlFilename = "a.xml", name = "X", specs = { power = { value = -1 } } },
        })
        assert.is_nil(index.items[1].specs.power)
        assert.are.equal(1, index.skipped["invalid-spec:power"])
    end)

    it("descarta spec NaN", function()
        local index = builder():build({
            { xmlFilename = "a.xml", name = "X", specs = { power = { value = 0 / 0 } } },
        })
        assert.is_nil(index.items[1].specs.power)
        assert.are.equal(1, index.skipped["invalid-spec:power"])
    end)

    it("item sem xmlFilename é ignorado com motivo no-id, e ids permanecem alinhados", function()
        local index = builder():build({
            { xmlFilename = "a.xml", name = "A" },
            { name = "Sem id" }, -- sem xmlFilename
            { xmlFilename = "c.xml", name = "C" },
        })
        assert.are.equal(2, #index.items)
        assert.are.equal(1, index.skipped["no-id"])
        -- os dois itens válidos devem estar corretamente indexados sob seus
        -- próprios ids (regressão: array position == id usado em postings)
        assert.is_not_nil(index:postingsFor("a"))
        assert.is_not_nil(index:postingsFor("c"))
        local postingsA = index:postingsFor("a")
        local itemIdA = next(postingsA)
        assert.are.equal("A", index.items[itemIdA].fields.name.raw)
    end)

    it("catálogo vazio produz índice vazio sem erro", function()
        local index = builder():build({})
        assert.are.equal(0, #index.items)
    end)

    it("não muta o RawItem de entrada (D2)", function()
        local raw = { xmlFilename = "a.xml", name = "X" }
        local frozen = setmetatable({}, {
            __index = raw,
            __newindex = function()
                error("RawItem não deve ser mutado")
            end,
        })
        assert.has_no.errors(function()
            builder():build({ frozen })
        end)
    end)
end)

describe("Signature", function()
    it("muda quando a lista de xmlFilename muda", function()
        local s1 = Signature.of({ { xmlFilename = "a.xml" }, { xmlFilename = "b.xml" } })
        local s2 = Signature.of({ { xmlFilename = "a.xml" }, { xmlFilename = "c.xml" } })
        assert.is_not.equal(s1, s2)
    end)

    it("é estável para a mesma lista", function()
        local items = { { xmlFilename = "a.xml" }, { xmlFilename = "b.xml" } }
        assert.are.equal(Signature.of(items), Signature.of(items))
    end)
end)
