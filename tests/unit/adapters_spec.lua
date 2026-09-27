-- Adapters com stubs mínimos dos globais do FS25. Não valida a API real do
-- jogo (isso é da F5): só a lógica própria dos adapters em torno dela.
require("tests.support.load").load({ adapters = true })
local NS = SmartShopSearch
local MemoryLogger = require("tests.stubs.MemoryLogger")
local FakeClock = require("tests.stubs.FakeClock")

local GLOBALS = { "XMLFile", "g_modSettingsDirectory", "g_inputBinding", "InputAction", "g_shopMenu", "g_i18n" }

local function setGlobal(name, value)
    rawset(_G, name, value)
end

local function clearGlobals()
    for _, name in ipairs(GLOBALS) do
        rawset(_G, name, nil)
    end
end

--- XMLFile falso: guarda valores por caminho completo, num "disco" em memória.
local function fakeXmlApi(disk)
    local function handle(filename)
        local values = disk[filename] or {}
        disk[filename] = values
        local h = { values = values }
        function h.getBool(_, path, default)
            local v = values[path]
            if v == nil then
                return default
            end
            return v
        end
        h.getFloat = h.getBool
        h.getString = h.getBool
        function h.setBool(_, path, v)
            values[path] = v
        end
        h.setFloat = h.setBool
        h.setString = h.setBool
        function h.save() end
        function h.delete() end
        return h
    end
    return {
        loadIfExists = function(_, filename)
            return disk[filename] and handle(filename) or nil
        end,
        load = function(_, filename)
            return disk[filename] and handle(filename) or nil
        end,
        create = function(_, filename)
            disk[filename] = {}
            return handle(filename)
        end,
    }
end

describe("SettingsStore", function()
    local disk

    before_each(function()
        disk = {}
        setGlobal("XMLFile", fakeXmlApi(disk))
        setGlobal("g_modSettingsDirectory", "/ms/")
    end)
    after_each(clearGlobals)

    it("grava e lê no formato elemento#atributo do XMLFile", function()
        local store = NS.adapters.SettingsStore.new()
        store:set("ui#showReasons", true)
        local file = disk["/ms/FS25_SmartShopSearch/settings.xml"]
        assert.is_true(file["settings.ui#showReasons"])
        assert.is_nil(file["settings.ui.#showReasons"])

        local reloaded = NS.adapters.SettingsStore.new()
        reloaded:loadSettings()
        assert.is_true(reloaded:get("ui#showReasons"))
        assert.are.equal(300, reloaded:get("search#maxResults"))
    end)

    it("debug#simulateFailure vem vazio por padrão", function()
        assert.are.equal("", NS.adapters.SettingsStore.new():get("debug#simulateFailure"))
    end)
end)

describe("InputAdapter", function()
    local removed

    local function binding(...)
        local ret = { ... }
        removed = {}
        return {
            registerActionEvent = function()
                return unpack(ret)
            end,
            removeActionEvent = function(_, id)
                removed[#removed + 1] = id
            end,
            setActionEventTextVisibility = function() end,
            setActionEventTextPriority = function() end,
        }
    end

    before_each(function()
        setGlobal("InputAction", { SMART_SHOP_SEARCH = "SMART_SHOP_SEARCH" })
    end)
    after_each(clearGlobals)

    it("usa o eventId do segundo retorno (success, eventId)", function()
        setGlobal("g_inputBinding", binding(true, "evt-1"))
        local adapter = NS.adapters.InputAdapter.new(function() end)
        adapter:bind()
        assert.are.equal("evt-1", adapter.eventId)
        adapter:unbind()
        assert.are.same({ "evt-1" }, removed)
    end)

    it("aceita um único retorno com o id", function()
        setGlobal("g_inputBinding", binding("evt-2"))
        local adapter = NS.adapters.InputAdapter.new(function() end)
        adapter:bind()
        assert.are.equal("evt-2", adapter.eventId)
    end)

    it("registro recusado (false) não guarda id", function()
        setGlobal("g_inputBinding", binding(false))
        local adapter = NS.adapters.InputAdapter.new(function() end)
        adapter:bind()
        assert.is_nil(adapter.eventId)
    end)
end)

describe("SpecExtractor:secondary", function()
    after_each(clearGlobals)

    it("lê os caminhos do XML, descarta inválidos e cacheia por xmlFilename", function()
        local disk = {
            ["v.xml"] = {
                ["vehicle.storeData.specs.power"] = 120,
                ["vehicle.storeData.specs.workingWidth"] = -3,
            },
        }
        local api = fakeXmlApi(disk)
        local loads = 0
        local originalLoad = api.load
        api.load = function(...)
            loads = loads + 1
            return originalLoad(...)
        end
        setGlobal("XMLFile", api)
        local extractor = NS.adapters.SpecExtractor.new({}, MemoryLogger.new())
        local out = extractor:secondary({ xmlFilename = "v.xml" })
        assert.are.same({ power = 120 }, out)
        extractor:secondary({ xmlFilename = "v.xml" })
        assert.are.equal(1, loads)
    end)
end)

describe("ShopGuiAdapter", function()
    local logger, state, settingsValues, texts

    local function settings()
        return {
            get = function(_, key)
                return settingsValues[key]
            end,
        }
    end

    local function adapterWith(searchService)
        return NS.adapters.ShopGuiAdapter.new(
            searchService,
            NS.app.SearchState.new(),
            { bind = function() end, unbind = function() end },
            settings(),
            logger,
            state
        )
    end

    before_each(function()
        logger = MemoryLogger.new()
        state = NS.app.StateMachine.new(logger)
        settingsValues = {}
        texts = {}
        setGlobal("g_shopMenu", {})
        setGlobal("g_i18n", {
            getText = function(_, key)
                return key
            end,
        })
    end)
    after_each(clearGlobals)

    describe("simulateFailure=gui (F6)", function()
        it("com debug ligado, a falha simulada degrada o mod sem propagar erro", function()
            settingsValues["debug#enabled"] = true
            settingsValues["debug#simulateFailure"] = "gui"
            local adapter = adapterWith({ deps = {} })
            assert.has_no.errors(function()
                adapter:show({}, { raw = "x" })
            end)
            assert.is_true(state:is("degraded"))
            assert.truthy(state.reason:find("show", 1, true))
        end)

        it("sem debug#enabled, o valor é ignorado", function()
            settingsValues["debug#simulateFailure"] = "gui"
            local adapter = adapterWith({ deps = {} })
            adapter:show({}, { raw = "x" })
            assert.is_false(state:is("degraded"))
        end)
    end)

    describe("indicador sss_indexing e trabalho por frame", function()
        local lifecycle, searches, adapter

        before_each(function()
            local rawItems = {}
            for i = 1, 5 do
                rawItems[i] = { xmlFilename = i .. ".xml", name = "Item " .. i }
            end
            lifecycle = NS.app.IndexLifecycle.new(nil, {
                catalog = {
                    items = function()
                        return rawItems
                    end,
                },
                builder = NS.core.IndexBuilder.new(NS.core.TextNormalizer.new({ protected = {}, currency = {} })),
                clock = FakeClock.new(),
            })
            searches = 0
            local service = {
                deps = { indexLifecycle = lifecycle },
                search = function()
                    searches = searches + 1
                    return {}, { raw = "x" }
                end,
            }
            adapter = adapterWith(service)
            adapter.frameHookActive = true
            local button = {
                setText = function(_, t)
                    texts[#texts + 1] = t
                end,
            }
            adapter.ui[rawget(_G, "g_shopMenu")] = { searchButton = button }
        end)

        it("mostra o indicador enquanto o build fatiado avança e restaura no fim", function()
            lifecycle:ensure(0) -- orçamento zero: só 1 item nesta fatia
            assert.is_true(lifecycle:isBusy())
            adapter:refreshBusy() -- o que o hook de onOpen faz
            local frames = 0
            repeat
                adapter:onFrame()
                frames = frames + 1
            until not lifecycle:isBusy() or frames > 20
            assert.is_false(lifecycle:isBusy())
            assert.are.same({ "sss_indexing", "sss_button_search" }, texts)
            assert.are.equal(5, lifecycle:itemCount())
        end)

        it("busca de compatibilidade roda no frame seguinte, com o indicador antes", function()
            lifecycle:ensure(nil)
            adapter:searchCompatibleWithSelected()
            assert.are.equal(0, searches)
            assert.are.same({ "sss_indexing" }, texts)
            adapter:onFrame()
            assert.are.equal(1, searches)
            assert.are.same({ "sss_indexing", "sss_button_search" }, texts)
        end)

        it("sem hook de frame, executa na hora", function()
            adapter.frameHookActive = false
            lifecycle:ensure(nil)
            adapter:searchCompatibleWithSelected()
            assert.are.equal(1, searches)
            assert.are.same({}, texts)
        end)
    end)
end)
