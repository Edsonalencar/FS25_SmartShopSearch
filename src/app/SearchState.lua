-- Estado de UI da busca (L3 do spec): texto, filtros, contexto de
-- compatibilidade e a categoria anterior à busca (para "limpar" restaurar).
-- Corrige o defeito da referência onde "limpar" só fazia popDetail sem
-- zerar filtros (RF-004).
local NS = SmartShopSearch
local SearchState = {}
SearchState.__index = SearchState

function SearchState.new()
    return setmetatable({ text = "", ui = nil, context = nil, prevCategory = nil }, SearchState)
end

--- Zera texto, filtros de UI e contexto de compatibilidade. NÃO mexe em
--- `prevCategory` (quem chama decide quando restaurá-la e limpá-la).
function SearchState:clear()
    self.text = ""
    self.ui = nil
    self.context = nil
end

--- @return boolean  true se há uma busca de texto ativa (não vazia)
function SearchState:isActive()
    return self.text ~= nil and self.text ~= ""
end

NS.app.SearchState = SearchState
