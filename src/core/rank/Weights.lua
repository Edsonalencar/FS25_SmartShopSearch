-- Valores iniciais do modelo de score (PRD §6.6), calibrados na F9
-- (tools/calibrate.lua) sobre o corpus golden real. Tabela única, sem lógica.
local NS = SmartShopSearch

local Weights = {
    fields = {
        name = 1.0,
        category = 0.9,
        brand = 0.9,
        spec = 0.8,
        mod = 0.6,
        author = 0.4,
        dlc = 0.5,
    },
    types = {
        exact = 1.0,
        prefix = 0.85,
        alias = 0.9,
        fuzzy1 = 0.7,
        fuzzy2 = 0.45,
    },
    -- limiar de distância fuzzy por comprimento do token (Utf8.len), RF-021/022
    fuzzyMaxByLen = {
        { maxLen = 3, dist = 0 },
        { maxLen = 5, dist = 1 },
        { maxLen = 9, dist = 2 },
        { maxLen = math.huge, dist = 3 },
    },
    minScoreRel = 0.25, -- score mínimo relativo ao melhor resultado da consulta
    minScoreAbs = 0.15, -- piso absoluto (evita exibir tudo quando o melhor score é baixo)
    concept = 0.9, -- wConceito (categoria/marca resolvidos por alias)
    coverageFloor = 0.5, -- fator mínimo de cobertura no modelo de score (§2.4 do spec)
    compat = { declared = 1.0, joint = 0.7, powerInsufficient = 0.3 }, -- F8
    penalty = {
        shortToken = 0.1, -- hit de prefixo em token curto (<= 3)
        secondaryOnly = 0.1, -- todos os hits do item em mod/author/dlc
        fuzzyFar = 0.15, -- hit fuzzy na distância máxima permitida
    },
}

NS.core.Weights = Weights
