-- Instala o mod no ciclo de vida do jogo (addModEventListener) e cria os
-- objetos de app/adapters de nível superior (logger, state, settings).
local NS = SmartShopSearch
local GameBootstrap = {}

-- Adapter fino da porta ConsoleRegistrar (app/Console.lua): traduz add/remove
-- para addConsoleCommand/removeConsoleCommand. [A VALIDAR assinatura exata na F5]
local ConsoleRegistrar = {}
ConsoleRegistrar.__index = ConsoleRegistrar

function ConsoleRegistrar.new()
    return setmetatable({}, ConsoleRegistrar)
end

function ConsoleRegistrar:add(name, helpText, fn)
    self[name] = function(_, ...)
        return fn(...)
    end
    if type(addConsoleCommand) == "function" then
        addConsoleCommand(name, helpText, name, self)
    end
end

function ConsoleRegistrar:remove(name)
    self[name] = nil
    if type(removeConsoleCommand) == "function" then
        removeConsoleCommand(name)
    end
end

-- Clock mínimo sobre getTimeSec (jogo) — só usado por IndexLifecycle para
-- orçamento de tempo da construção fatiada do índice (ADR-04).
local GameClock = {}
GameClock.__index = GameClock
function GameClock.new()
    return setmetatable({}, GameClock)
end
function GameClock:now() -- luacheck: ignore 212
    if type(getTimeSec) == "function" then
        return getTimeSec()
    end
    return os.clock()
end

local listener = {}

function listener:loadMap() -- luacheck: ignore 212/self
    NS.app.SafeCall.run("bootstrap:loadMap", function()
        if g_dedicatedServer ~= nil then
            NS.app.state:set("disabled-dedicated")
            return
        end
        NS.app.settings:loadSettings()
        NS.app.logger:setLevel(NS.app.settings:get("debug#logLevel"))

        local locales = NS.adapters.GameLocale.dataLocales()
        local dataLoader = NS.adapters.XmlDataLoader.new(NS.MOD_DIR)
        NS.app.data = NS.app.LinguisticData.new(dataLoader, locales, NS.app.logger)
        local commonUnits = NS.app.data:commonUnits()

        local normalizer = NS.core.TextNormalizer.new({
            protected = (commonUnits and commonUnits.protected) or {},
            currency = { "r$", "$", "€", "£" },
        })

        local specRegistry = NS.core.SpecRegistry.build(commonUnits)
        local specExtractor = NS.adapters.SpecExtractor.new(specRegistry, NS.app.logger)
        NS.adapters.storeCatalogSource = NS.adapters.StoreCatalogSource.new(specExtractor, NS.app.logger)

        local builder = NS.core.IndexBuilder.new(normalizer)
        NS.app.indexLifecycle.deps = {
            catalog = NS.adapters.storeCatalogSource,
            builder = builder,
            clock = GameClock.new(),
        }

        NS.adapters.compatibilityExtractor = NS.adapters.CompatibilityExtractor.new(NS.app.logger)

        NS.app.searchService = NS.app.SearchService.new({
            indexLifecycle = NS.app.indexLifecycle,
            normalizer = normalizer,
            settings = NS.app.settings,
            logger = NS.app.logger,
            data = NS.app.data,
            compatibilityExtractor = NS.adapters.compatibilityExtractor,
            selectedItemFn = function()
                return NS.adapters.shopGuiAdapter and NS.adapters.shopGuiAdapter:selectedItem()
            end,
        })

        NS.app.searchState = NS.app.SearchState.new()
        NS.adapters.inputAdapter = NS.adapters.InputAdapter.new(function()
            NS.adapters.shopGuiAdapter:openInput()
        end)
        NS.adapters.shopGuiAdapter = NS.adapters.ShopGuiAdapter.new(
            NS.app.searchService,
            NS.app.searchState,
            NS.adapters.inputAdapter,
            NS.app.settings,
            NS.app.logger,
            NS.app.state
        )
        NS.adapters.shopGuiAdapter:install()

        NS.app.consoleRegistrar = NS.app.consoleRegistrar or ConsoleRegistrar.new()
        NS.app.Console.install(NS.app.consoleRegistrar, NS.adapters.HookRegistry.status, function()
            return NS.adapters.storeCatalogSource:dumpToFile()
        end)

        NS.app.state:set("ready")
        NS.app.logger:info("bootstrap", "v%s carregado", NS.VERSION)
    end)
end

function listener:deleteMap() -- luacheck: ignore 212/self
    NS.app.SafeCall.run("bootstrap:deleteMap", function()
        NS.adapters.HookRegistry.uninstall()
        NS.app.Console.uninstall()
        NS.app.indexLifecycle:release()
        NS.app.state:set("unloaded")
    end)
end

function GameBootstrap.install(namespace)
    namespace.app.settings = namespace.adapters.SettingsStore.new()
    namespace.app.logger = namespace.adapters.GameLogger.new(namespace.app.settings)
    namespace.app.state = namespace.app.StateMachine.new(namespace.app.logger)
    namespace.app.diagnostics = namespace.app.Diagnostics.new()
    namespace.app.indexLifecycle = namespace.app.IndexLifecycle.new(namespace.app.diagnostics)

    addModEventListener(listener)
end

NS.adapters.GameBootstrap = GameBootstrap
