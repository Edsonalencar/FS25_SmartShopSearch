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

local listener = {}

function listener:loadMap() -- luacheck: ignore 212/self
    NS.app.SafeCall.run("bootstrap:loadMap", function()
        if g_dedicatedServer ~= nil then
            NS.app.state:set("disabled-dedicated")
            return
        end
        NS.app.settings:loadSettings()
        NS.app.logger:setLevel(NS.app.settings:get("debug#logLevel"))

        -- F3+: dados linguísticos (LinguisticData) carregados aqui.
        -- F6+: StoreCatalogSource, SearchService real e ShopGuiAdapter.install() aqui.

        NS.app.consoleRegistrar = NS.app.consoleRegistrar or ConsoleRegistrar.new()
        NS.app.Console.install(NS.app.consoleRegistrar, NS.adapters.HookRegistry.status)

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
