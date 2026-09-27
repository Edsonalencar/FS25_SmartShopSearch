-- S-06: br -> data/pt, pt -> data/pt, demais -> data/<code> se existir; en sempre carregado.
-- A F5 confirma os códigos reais de idioma do FS25 e só altera esta tabela.
local NS = SmartShopSearch
local GameLocale = {}

GameLocale.LANG_MAP = {
    br = "pt",
    pt = "pt",
    en = "en",
    de = "de",
    fr = "fr",
}

function GameLocale.current()
    -- [A VALIDAR na F5]: nome exato do global de idioma do FS25.
    local code = g_languageShort
    if type(code) ~= "string" then
        return "en"
    end
    return code
end

--- Retorna a lista de locales de dados a carregar: {idioma mapeado, "en"},
--- sem duplicatas, na ordem idioma do jogo primeiro (S-06).
function GameLocale.dataLocales()
    local code = GameLocale.current()
    local mapped = GameLocale.LANG_MAP[code] or code
    if mapped == "en" then
        return { "en" }
    end
    return { mapped, "en" }
end

NS.adapters.GameLocale = GameLocale
