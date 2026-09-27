-- Gera um catálogo sintético determinístico de N RawItem para benchmark
-- (padrão 3000, PRD §15). Tabelas Lua diretas (sem XML) para não medir o
-- custo do parser de teste junto com o do índice.
local M = {}

local BRANDS = {
    { id = "JOHNDEERE", title = "John Deere" },
    { id = "FENDT", title = "Fendt" },
    { id = "NEWHOLLAND", title = "New Holland" },
    { id = "CASEIH", title = "Case IH" },
    { id = "MASSEYFERGUSON", title = "Massey Ferguson" },
    { id = "VALTRA", title = "Valtra" },
    { id = "CLAAS", title = "Claas" },
    { id = "KUHN", title = "Kuhn" },
}
local CATEGORIES = {
    { id = "TRACTORSS", title = "Tratores S" },
    { id = "TRACTORSM", title = "Tratores M" },
    { id = "TRACTORSL", title = "Tratores L" },
    { id = "SPRAYERSM", title = "Pulverizadores" },
    { id = "TRAILERSM", title = "Reboques" },
    { id = "HARVESTERSL", title = "Colheitadeiras" },
    { id = "BALERSM", title = "Enfardadeiras" },
}

local function makeRng(seed)
    local state = seed
    return function(mod)
        state = (state * 1103515245 + 12345) % 2147483648
        if mod then
            return state % mod
        end
        return state
    end
end

---@param n integer
---@param seed integer|nil
---@return RawItem[]
function M.generate(n, seed)
    local rng = makeRng(seed or 42)
    local items = {}
    for i = 1, n do
        local brand = BRANDS[(rng(#BRANDS)) + 1]
        local category = CATEGORIES[(rng(#CATEGORIES)) + 1]
        local isMod = rng(10) == 0
        local power = 50 + rng(350)
        items[i] = {
            xmlFilename = string.format("bench/item_%05d.xml", i),
            name = string.format("%s Model %d", brand.title, 1000 + i),
            brand = brand.id,
            brandTitle = brand.title,
            categoryId = category.id,
            categoryTitle = category.title,
            species = "vehicle",
            price = 50000 + rng(500000),
            origin = isMod and "mod" or "base",
            modName = isMod and ("FS25_BenchMod" .. (rng(20))) or nil,
            modTitle = isMod and ("Bench Mod Pack " .. (rng(20))) or nil,
            author = isMod and ("BenchAuthor" .. (rng(50))) or nil,
            specs = { power = { value = power, unit = "kw" } },
        }
    end
    return items
end

return M
