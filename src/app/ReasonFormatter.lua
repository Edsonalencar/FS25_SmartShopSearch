-- Formata MatchReason em linhas curtas e traduzidas para exibição discreta
-- no detalhe do item (G9, RF-052). Nunca lança erro com `reason` incompleto.
local NS = SmartShopSearch
local ReasonFormatter = {}

local KEY_BY_KIND = {
    exact = "sss_reason_exact",
    prefix = "sss_reason_exact",
    fuzzy1 = "sss_reason_fuzzy",
    fuzzy2 = "sss_reason_fuzzy",
    alias = "sss_reason_alias",
    constraint = "sss_reason_constraint",
    compat = "sss_reason_compat",
}

local MAX_LINES = 4

local function getText(i18n, key, fallback)
    if i18n and type(i18n.getText) == "function" then
        local ok, text = pcall(function()
            return i18n:getText(key)
        end)
        if ok and text then
            return text
        end
    end
    return fallback
end

--- @param reason MatchReason|nil
--- @param i18n table|nil  porta de idioma (g_i18n em jogo)
--- @return string|nil  linha "✓ <campo>: <detalhe>", ou nil se `reason` for inválido
function ReasonFormatter.formatOne(reason, i18n)
    if type(reason) ~= "table" or not reason.kind then
        return nil
    end
    local key = KEY_BY_KIND[reason.kind] or "sss_reason_exact"
    local label = getText(i18n, key, reason.kind)
    local field = reason.field or "?"
    local detail = reason.detail
    if detail and detail ~= "" then
        return string.format("✓ %s (%s): %s", label, field, detail)
    end
    return string.format("✓ %s (%s)", label, field)
end

--- @param reasons MatchReason[]|nil
--- @param i18n table|nil
--- @return string[]  até 4 linhas
function ReasonFormatter.format(reasons, i18n)
    local out = {}
    if type(reasons) ~= "table" then
        return out
    end
    for _, reason in ipairs(reasons) do
        local line = ReasonFormatter.formatOne(reason, i18n)
        if line then
            out[#out + 1] = line
            if #out >= MAX_LINES then
                break
            end
        end
    end
    return out
end

NS.app.ReasonFormatter = ReasonFormatter
