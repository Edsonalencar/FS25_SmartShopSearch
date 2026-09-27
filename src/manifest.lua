-- Ordem de carga fixa. Lida por main.lua, tests/support/load.lua e tools/build.py.
SmartShopSearch.manifest = {
    "core/util/Table.lua",
    "core/util/Hash.lua",
    "core/model/Models.lua",
    -- F2+: core/text, core/index, core/match, core/rank
    -- F3+: core/lang/AliasResolver.lua, core/index/TrigramIndex.lua, core/match/FuzzyMatcher.lua
    -- F4+: core/lang/*Parser.lua, core/rank/FilterEngine.lua
    -- F8 : core/compat/CompatibilityResolver.lua
    "app/SafeCall.lua",
    "app/StateMachine.lua",
    "app/Diagnostics.lua",
    "app/IndexLifecycle.lua",
    "app/SearchService.lua",
    "app/Console.lua",
    "adapters/GameLogger.lua",
    "adapters/HookRegistry.lua",
    "adapters/SettingsStore.lua",
    "adapters/GameLocale.lua",
    "adapters/GameBootstrap.lua",
}
