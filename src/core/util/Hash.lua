-- Hash determinístico sem bitops (Lua 5.1 puro, sem utf8.*, sem bibliotecas
-- externas) — usado pela assinatura do catálogo (core/index/Signature.lua).
local NS = SmartShopSearch
local Hash = {}
local MOD = 2147483647

function Hash.string(s, h)
    h = h or 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % MOD
    end
    return h
end

NS.core.Hash = Hash
