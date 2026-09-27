-- Carrega o mod fora do jogo, na mesma ordem do manifesto, apenas core/ e app/.
-- Com `{adapters = true}`, carrega também adapters/ (menos GameBootstrap), para
-- testes com stubs dos globais do jogo (tests/unit/adapters_spec.lua).
local M = {}
function M.load(opts)
    opts = opts or {}
    SmartShopSearch = { MOD_DIR = "src/", VERSION = "test", core = {}, app = {}, adapters = {}, data = {} }
    dofile("src/manifest.lua")
    for _, rel in ipairs(SmartShopSearch.manifest) do
        local wanted = rel:match("^core/")
            or rel:match("^app/")
            or (opts.adapters and rel:match("^adapters/") and rel ~= "adapters/GameBootstrap.lua")
        if wanted then
            dofile("src/" .. rel)
        end
    end
    return SmartShopSearch
end
return M
