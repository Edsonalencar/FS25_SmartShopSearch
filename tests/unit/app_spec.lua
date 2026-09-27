require("tests.support.load").load()

local MemoryLogger = require("tests.stubs.MemoryLogger")

describe("StateMachine", function()
    local NS = SmartShopSearch

    it("segue as transições válidas loaded -> ready -> indexed", function()
        local logger = MemoryLogger.new()
        local sm = NS.app.StateMachine.new(logger)
        assert.is_true(sm:is("loaded"))
        assert.is_true(sm:set("ready"))
        assert.is_true(sm:is("ready"))
        assert.is_true(sm:set("indexed"))
        assert.is_true(sm:is("indexed"))
    end)

    it("ignora transições inválidas e loga debug", function()
        local logger = MemoryLogger.new()
        local sm = NS.app.StateMachine.new(logger)
        -- loaded -> indexed não é permitido diretamente
        assert.is_false(sm:set("indexed"))
        assert.is_true(sm:is("loaded"))
        assert.is_true(logger:hasLevel("debug"))
    end)

    it("degrade é idempotente e loga uma única linha de erro", function()
        local logger = MemoryLogger.new()
        local sm = NS.app.StateMachine.new(logger)
        sm:degrade("motivo 1")
        sm:degrade("motivo 2")
        assert.is_true(sm:is("degraded"))
        assert.are.equal("motivo 1", sm.reason)
        assert.are.equal(1, logger:countLevel("error"))
    end)

    it("notifica listeners em mudança de estado", function()
        local logger = MemoryLogger.new()
        local sm = NS.app.StateMachine.new(logger)
        local seen = {}
        sm:onChange(function(to)
            seen[#seen + 1] = to
        end)
        sm:set("ready")
        sm:set("indexed")
        assert.are.same({ "ready", "indexed" }, seen)
    end)
end)

describe("SafeCall", function()
    local NS = SmartShopSearch

    before_each(function()
        NS.app.logger = MemoryLogger.new()
        NS.app.state = NS.app.StateMachine.new(NS.app.logger)
        NS.app.SafeCall.failures = {}
    end)

    it("executa a função e devolve o resultado quando não há erro", function()
        local a, b = NS.app.SafeCall.run("ctx:ok", function(x)
            return x, x * 2
        end, 5)
        assert.are.equal(5, a)
        assert.are.equal(10, b)
    end)

    it("captura o erro, loga e conta falhas, devolvendo nil", function()
        local result = NS.app.SafeCall.run("ctx:fail", function()
            error("boom")
        end)
        assert.is_nil(result)
        assert.are.equal(1, NS.app.SafeCall.failures["ctx:fail"])
        assert.is_true(NS.app.logger:hasLevel("error"))
    end)

    it("degrada o estado após 3 falhas no mesmo contexto", function()
        for _ = 1, 3 do
            NS.app.SafeCall.run("ctx:repeat", function()
                error("boom")
            end)
        end
        assert.is_true(NS.app.state:is("degraded"))
    end)

    it("não degrada antes de atingir o limite de falhas", function()
        for _ = 1, 2 do
            NS.app.SafeCall.run("ctx:almost", function()
                error("boom")
            end)
        end
        assert.is_false(NS.app.state:is("degraded"))
    end)
end)
