local NS = SmartShopSearch
local Table = {}

function Table.copyShallow(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

function Table.keys(t)
    local out = {}
    for k in pairs(t) do
        out[#out + 1] = k
    end
    return out
end

function Table.sortedKeys(t)
    local out = Table.keys(t)
    table.sort(out, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return out
end

function Table.contains(t, value)
    for _, v in ipairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

--- Compara um id de facet (que pode terminar em "*" para curinga de prefixo,
--- ex. "TRACTORS*") contra um valor real (ex. "TRACTORSM"). Usado pelo
--- AliasResolver e pelos casos golden `<expectTop category="TRACTORS*">`.
function Table.idMatches(id, value)
    if id == nil or value == nil then
        return false
    end
    if id:sub(-1) == "*" then
        local prefix = id:sub(1, -2)
        return value:sub(1, #prefix) == prefix
    end
    return id == value
end

NS.core.Table = Table

-- IdMatcher: mesma comparação de curinga de prefixo, exposta com o nome usado
-- pelo AliasResolver (F3) para resolver conceitos como "TRACTORS*".
NS.core.IdMatcher = { matches = Table.idMatches }
