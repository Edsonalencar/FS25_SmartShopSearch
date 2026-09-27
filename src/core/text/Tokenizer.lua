-- Tokeniza uma string já normalizada (separada por espaço único). Os `span`s
-- referem-se a posições em bytes na string normalizada — não na consulta
-- original (`Query.raw` guarda o original; para diagnóstico basta mostrar o
-- trecho normalizado).
local NS = SmartShopSearch
local Tokenizer = {}

---@param norm string
---@return {text:string, s:integer, e:integer}[]
function Tokenizer.tokenize(norm)
    local out, pos = {}, 1
    while true do
        local s, e = string.find(norm, "[^ ]+", pos)
        if not s then
            break
        end
        out[#out + 1] = { text = string.sub(norm, s, e), s = s, e = e }
        pos = e + 1
    end
    return out
end

NS.core.Tokenizer = Tokenizer
