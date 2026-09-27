require("tests.support.load").load()
local NS = SmartShopSearch
local SearchState = NS.app.SearchState

describe("SearchState (L3)", function()
    it("clear() zera texto, filtros de UI e contexto", function()
        local state = SearchState.new()
        state.text = "trator fendt"
        state.ui = { brand = { ids = { "FENDT" } } }
        state.context = { kind = "compatibleWith" }
        state.prevCategory = { name = "VEHICLES" }

        state:clear()

        assert.are.equal("", state.text)
        assert.is_nil(state.ui)
        assert.is_nil(state.context)
        -- prevCategory não é zerada por clear(): quem chama decide quando restaurá-la
        assert.is_not_nil(state.prevCategory)
    end)

    it("isActive() reflete se há texto de busca", function()
        local state = SearchState.new()
        assert.is_false(state:isActive())
        state.text = "trator"
        assert.is_true(state:isActive())
        state:clear()
        assert.is_false(state:isActive())
    end)
end)
