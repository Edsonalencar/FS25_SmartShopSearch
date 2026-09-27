-- Normalização de texto (PRD §6.2): idempotente, sem dependências externas.
-- cfg.protected: lista de {from, to} vindos de data/common/units.xml (ex.
-- {"km/h","kmh"}, {"m³","m3"}, {"r$"," r$ "}). cfg.currency: símbolos
-- monetários a isolar por espaços (L8), ex. {"r$","$","€","£"}.
local NS = SmartShopSearch
local Utf8 = NS.core.Utf8
local TextNormalizer = {}
TextNormalizer.__index = TextNormalizer

-- Marcadores de bytes de controle (removidos por %c antes de serem
-- introduzidos, portanto nunca colidem com o texto de entrada).
local PROT_DOT = "\5"
local PROT_COMMA = "\6"
local PROT_DOLLAR = "\7"
local JOIN_OPEN = "\16"
local JOIN_CLOSE = "\17"

local function escapePattern(s)
    return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

--- Substitui `from` por `to` literalmente (sem interpretar padrões Lua),
--- equivalente a um find/replace "plain". Checa primeiro com find "plain"
--- (rápido, em C) antes do gsub baseado em padrão — a maioria dos campos
--- não contém nenhuma das sequências protegidas.
local function plainReplace(s, from, to)
    if not s:find(from, 1, true) then
        return s
    end
    local pattern = escapePattern(from)
    local repl = (to:gsub("%%", "%%%%"))
    return (s:gsub(pattern, repl))
end

--- Isola `sym` com espaços, exceto quando imediatamente precedido por um dos
--- prefixos em `excluded` (ex. não isolar o "$" de "r$", já tratado à parte).
local function isolateSymbolExcluding(s, sym, excluded)
    local out = {}
    local i, n, symLen = 1, #s, #sym
    while i <= n do
        if s:sub(i, i + symLen - 1) == sym then
            local isExcluded = false
            for prefix in pairs(excluded) do
                local pl = #prefix
                if pl > 0 and s:sub(i - pl, i - 1) == prefix then
                    isExcluded = true
                    break
                end
            end
            out[#out + 1] = isExcluded and sym or (" " .. sym .. " ")
            i = i + symLen
        else
            out[#out + 1] = s:sub(i, i)
            i = i + 1
        end
    end
    return table.concat(out)
end

--- Marca "." e "," como protegidos quando cercados por dígitos dos dois
--- lados (separadores decimais/milhares, ex. "40.000", "1,5"), inclusive em
--- cadeias com múltiplos separadores ("40.000.000"), avaliando cada símbolo
--- independentemente contra seus vizinhos imediatos.
local function protectNumberSeparators(s)
    if not s:find("[.,]") then
        return s -- atalho: nada a proteger, evita a varredura byte a byte
    end
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "." or c == "," then
            local prev, nxt = s:sub(i - 1, i - 1), s:sub(i + 1, i + 1)
            if prev:match("%d") and nxt:match("%d") then
                out[#out + 1] = (c == "." and PROT_DOT or PROT_COMMA)
            else
                out[#out + 1] = c
            end
        else
            out[#out + 1] = c
        end
    end
    return table.concat(out)
end

---@param cfg {protected: {[1]:string,[2]:string}[], currency: string[]}|nil
function TextNormalizer.new(cfg)
    cfg = cfg or {}
    local protectedPairs = {}
    for _, p in ipairs(cfg.protected or {}) do
        protectedPairs[#protectedPairs + 1] = { from = p[1] or p.from, to = p[2] or p.to }
    end
    table.sort(protectedPairs, function(a, b)
        return #a.from > #b.from
    end)

    -- Alvos com adjacência letra-dígito (ex. "m3") precisam ser marcados
    -- antes da separação letra<->dígito (passo 6), senão seriam quebrados.
    local joinedTargets = {}
    for _, p in ipairs(protectedPairs) do
        if p.to:find("%a%d") or p.to:find("%d%a") then
            joinedTargets[#joinedTargets + 1] = p.to
        end
    end
    table.sort(joinedTargets, function(a, b)
        return #a > #b
    end)

    -- Símbolos de moeda já cobertos por um par protegido (ex. "r$" -> " r$ ")
    -- não entram de novo no passo 5, senão a re-aplicação genérica de "$"
    -- quebraria o "r$" que o passo 4 acabou de isolar.
    local protectedFrom = {}
    for _, p in ipairs(protectedPairs) do
        protectedFrom[p.from] = true
    end
    local currency = {}
    for _, sym in ipairs(cfg.currency or {}) do
        if not protectedFrom[sym] then
            currency[#currency + 1] = sym
        end
    end

    -- Para cada símbolo "solto" (ex. "$"), evita reprocessar ocorrências que
    -- já fazem parte de um par protegido mais longo terminado no mesmo
    -- símbolo (ex. "r$"), cujo isolamento já ocorreu no passo 4: guarda o
    -- prefixo ("r") que deve ser ignorado ao isolar o símbolo solto.
    local currencyExclusions = {}
    for _, sym in ipairs(currency) do
        local set = {}
        for _, p in ipairs(protectedPairs) do
            if #p.from > #sym and p.from:sub(-#sym) == sym then
                set[p.from:sub(1, #p.from - #sym)] = true
            end
        end
        currencyExclusions[sym] = set
    end

    return setmetatable({
        protected = protectedPairs,
        joinedTargets = joinedTargets,
        currency = currency,
        currencyExclusions = currencyExclusions,
    }, TextNormalizer)
end

--- @param s string
--- @param splitDigitLetter boolean  false para a variante "joined" (normalizeForIndex)
function TextNormalizer:_run(s, splitDigitLetter)
    if type(s) ~= "string" then
        return ""
    end

    -- 1. códigos de cor/formatação ($RRGGBB) e bytes de controle.
    s = s:gsub("%$%x%x%x%x%x%x", "")
    s = s:gsub("%c", "")

    -- 2. dobra de acentos UTF-8.
    s = Utf8.fold(s)

    -- 3. minúsculas (ASCII; bytes >= 0x80 preservados).
    s = s:lower()

    -- 4. sequências protegidas (unidades, moeda), da mais longa para a mais curta.
    for _, p in ipairs(self.protected) do
        s = plainReplace(s, p.from, p.to)
    end

    -- 5. símbolos monetários isolados por espaços (L8), pulando ocorrências
    -- que são a cauda de um par protegido mais longo (ex. o "$" de "r$").
    for _, sym in ipairs(self.currency) do
        local excluded = self.currencyExclusions[sym]
        if next(excluded) == nil then
            s = plainReplace(s, sym, " " .. sym .. " ")
        else
            s = isolateSymbolExcluding(s, sym, excluded)
        end
    end

    -- Protege "$" e separadores decimais/milhares antes da pontuação → espaço
    -- (€/£ não são classificados como pontuação por %p e sobrevivem sozinhos).
    s = s:gsub("%$", PROT_DOLLAR)
    s = protectNumberSeparators(s)

    if splitDigitLetter then
        -- marca os alvos de unidade com adjacência letra-dígito (ex. "m3")
        for i, target in ipairs(self.joinedTargets) do
            s = plainReplace(s, target, JOIN_OPEN .. i .. JOIN_CLOSE)
        end

        -- 6. fronteira letra <-> dígito ("200cv" -> "200 cv").
        s = s:gsub("(%a)(%d)", "%1 %2")
        s = s:gsub("(%d)(%a)", "%1 %2")

        for i, target in ipairs(self.joinedTargets) do
            s = s:gsub(JOIN_OPEN .. i .. JOIN_CLOSE, target)
        end
    end

    -- 7. pontuação → espaço (exceto separadores numéricos e "$", já protegidos).
    s = s:gsub("%p", " ")
    s = s:gsub(PROT_DOT, "."):gsub(PROT_COMMA, ","):gsub(PROT_DOLLAR, "$")

    -- 8. colapso de espaços + trim.
    s = s:gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$")

    return s
end

---@param s string
---@return string
function TextNormalizer:normalize(s)
    return self:_run(s, true)
end

--- Retorna {norm, joined}: `norm` é a normalização padrão (com separação
--- letra<->dígito); `joined` preserva a forma colada ("6r") como token
--- secundário (PRD §6.2 item 4).
---@param s string
---@return {norm:string, joined:string}
function TextNormalizer:normalizeForIndex(s)
    return { norm = self:_run(s, true), joined = self:_run(s, false) }
end

NS.core.TextNormalizer = TextNormalizer
