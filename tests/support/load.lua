-- Carrega o mod fora do jogo, na mesma ordem do manifesto, apenas core/ e app/.
local M = {}
function M.load(opts) -- luacheck: ignore 212
    opts = opts or {} -- luacheck: ignore 311
    SmartShopSearch = { MOD_DIR = "src/", VERSION = "test", core = {}, app = {}, adapters = {}, data = {} }
    dofile("src/manifest.lua")
    for _, rel in ipairs(SmartShopSearch.manifest) do
        if rel:match("^core/") or rel:match("^app/") then
            dofile("src/" .. rel)
        end
    end
    return SmartShopSearch
end
return M
