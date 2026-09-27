-- Assinatura do catálogo (ADR-04): contagem + hash determinístico dos
-- xmlFilename, na ordem recebida. Usada por IndexLifecycle para decidir se
-- o índice precisa ser reconstruído.
local NS = SmartShopSearch
local Hash = NS.core.Hash
local Signature = {}

---@param rawItems RawItem[]
---@return string
function Signature.of(rawItems)
    local h = 5381
    for _, item in ipairs(rawItems) do
        h = Hash.string(tostring(item.xmlFilename or ""), h)
    end
    return tostring(#rawItems) .. ":" .. tostring(h)
end

NS.core.Signature = Signature
