-- FS25_SmartShopSearch — ponto de entrada único (extraSourceFiles)
local MOD_DIR = g_currentModDirectory
local MOD_NAME = g_currentModName

SmartShopSearch = {
    MOD_DIR = MOD_DIR,
    MOD_NAME = MOD_NAME,
    VERSION = "1.0.0",
    core = {},
    app = {},
    adapters = {},
    data = {},
}

source(MOD_DIR .. "manifest.lua")
for _, rel in ipairs(SmartShopSearch.manifest) do
    source(MOD_DIR .. rel)
end

SmartShopSearch.adapters.GameBootstrap.install(SmartShopSearch)
