-- Registro idempotente da hotkey SMART_SHOP_SEARCH (corrige D7: a
-- referência registra a cada abertura sem remover o evento). [A VALIDAR na
-- F5]: assinatura exata de registerActionEvent e o contexto de input certo
-- para a loja.
local NS = SmartShopSearch
local InputAdapter = {}
InputAdapter.__index = InputAdapter

---@param onTrigger fun()
function InputAdapter.new(onTrigger)
    return setmetatable({ onTrigger = onTrigger, eventId = nil }, InputAdapter)
end

function InputAdapter:bind()
    if self.eventId then
        return -- idempotente
    end
    if not (g_inputBinding and InputAction and InputAction.SMART_SHOP_SEARCH) then
        return
    end
    local function callback()
        self.onTrigger()
    end
    -- Nos FS anteriores, registerActionEvent devolve `success, eventId`; aceita
    -- também um único retorno com o id, até a F5 confirmar a assinatura.
    local ok, first, second = pcall(function()
        return g_inputBinding:registerActionEvent(
            InputAction.SMART_SHOP_SEARCH,
            self,
            callback,
            false,
            true,
            false,
            true
        )
    end)
    local eventId = second
    if eventId == nil and type(first) ~= "boolean" then
        eventId = first
    end
    if ok and first ~= false and eventId ~= nil then
        self.eventId = eventId
        pcall(function()
            g_inputBinding:setActionEventTextVisibility(eventId, true)
        end)
        pcall(function()
            -- Prioridade "alta" de exibição do texto do binding [A VALIDAR na F5]:
            -- a referência usa a constante GS_PRIO_HIGH do jogo; usamos o valor
            -- numérico direto para não depender de um global não declarado.
            g_inputBinding:setActionEventTextPriority(eventId, 1)
        end)
    end
end

function InputAdapter:unbind()
    if not self.eventId then
        return -- idempotente
    end
    pcall(function()
        g_inputBinding:removeActionEvent(self.eventId)
    end)
    self.eventId = nil
end

NS.adapters.InputAdapter = InputAdapter
