-- Única camada que toca a GUI da loja (PRD §8, ADR-07). Cria o botão e o
-- diálogo de busca, exibe os resultados como categoria virtual ordenada
-- pelo score, e trata o estado vazio e o "limpar". Toda chamada a uma
-- função do jogo é guardada por `type(x) == "function"` (P7); qualquer
-- falha aqui degrada o mod, nunca quebra a loja (RF-060).
local NS = SmartShopSearch
local ShopGuiAdapter = {}
ShopGuiAdapter.__index = ShopGuiAdapter

-- G3: páginas elegíveis para mostrar o botão de busca [CONFIRMADO v1.1 da
-- referência — reavaliar por patch na F5].
local ELIGIBLE_PAGES = {
    "pageShopVehicles",
    "pageShopBrands",
    "pageShopPacks",
    "pageShopDLCs",
    "pageShopItemDetails",
}
local ELIGIBLE_PAGES_SET = {}
for _, name in ipairs(ELIGIBLE_PAGES) do
    ELIGIBLE_PAGES_SET[name] = true
end

local SSS_CATEGORY = "SSS_SEARCH"

-- Orçamento por frame do trabalho fatiado (build do índice, specs
-- secundárias), só enquanto a loja está aberta (PRD §15: ≤ 8 ms por frame).
local FRAME_BUDGET_SEC = 0.004

---@param searchService table  app/SearchService
---@param searchState table  app/SearchState
---@param inputAdapter table  adapters/InputAdapter
---@param settings table  adapters/SettingsStore
---@param logger table
---@param state table  app/StateMachine
function ShopGuiAdapter.new(searchService, searchState, inputAdapter, settings, logger, state)
    return setmetatable({
        searchService = searchService,
        searchState = searchState,
        inputAdapter = inputAdapter,
        settings = settings,
        logger = logger,
        state = state,
        -- tabela fraca por instância de g_shopMenu (§8.2 PRD): nunca cria
        -- campo novo em g_shopMenu, evitando colisão com outros mods.
        ui = setmetatable({}, { mode = "k" }),
        frameHookActive = false, -- ShopMenu.update enganchado (trabalho fatiado + ações adiadas)
        pendingAction = nil, -- executada no próximo frame, depois de o indicador aparecer
        busyShown = false,
    }, ShopGuiAdapter)
end

local function isFn(x)
    return type(x) == "function"
end

function ShopGuiAdapter:_degrade(where, err)
    if self.logger then
        self.logger:error("gui", "%s: %s", where, tostring(err))
    end
    if self.state then
        self.state:degrade("gui: " .. where)
    end
end

--- Injeção de falha manual (F6): com debug#enabled e
--- debug#simulateFailure="gui", lança erro dentro dos blocos protegidos da
--- GUI, para o smoke verificar a degradação (RF-060, AC-RES-03).
function ShopGuiAdapter:_simulatedFailure(where)
    local settings = self.settings
    if settings and settings:get("debug#enabled") == true and settings:get("debug#simulateFailure") == "gui" then
        error("falha simulada em " .. where .. " (debug#simulateFailure=gui)")
    end
end

function ShopGuiAdapter:_lifecycle()
    return self.searchService and self.searchService.deps and self.searchService.deps.indexLifecycle
end

--- Indicador `sss_indexing` (F6/F8): troca o texto do botão de busca
--- enquanto há trabalho fatiado ou uma ação adiada. Só mexe na GUI quando o
--- estado muda.
function ShopGuiAdapter:_setBusy(busy)
    busy = busy == true
    if busy == self.busyShown then
        return
    end
    self.busyShown = busy
    local entry = g_shopMenu and self.ui[g_shopMenu]
    local button = entry and entry.searchButton
    if button and isFn(button.setText) and g_i18n then
        pcall(function()
            button:setText(g_i18n:getText(busy and "sss_indexing" or "sss_button_search"))
        end)
    end
end

--- Chamado a cada frame da loja aberta (hook em ShopMenu.update): executa a
--- ação adiada, senão avança o trabalho fatiado do índice, e atualiza o
--- indicador. Com a loja fechada não roda nada (PRD §15, FPS).
function ShopGuiAdapter:onFrame()
    local action = self.pendingAction
    if action then
        self.pendingAction = nil
        action()
    else
        local lifecycle = self:_lifecycle()
        if lifecycle and lifecycle:isBusy() then
            lifecycle:stepPending(FRAME_BUDGET_SEC)
        end
    end
    self:refreshBusy()
end

--- Sincroniza o indicador com o estado atual (ação adiada ou índice ocupado).
function ShopGuiAdapter:refreshBusy()
    local lifecycle = self:_lifecycle()
    self:_setBusy(self.pendingAction ~= nil or (lifecycle ~= nil and lifecycle:isBusy()))
end

--- Executa `fn` no próximo frame, com o indicador visível neste; sem o hook
--- de frame (API ausente), executa na hora.
function ShopGuiAdapter:_runWithIndicator(fn)
    if not self.frameHookActive then
        fn()
        return
    end
    self.pendingAction = fn
    self:_setBusy(true)
end

--- Clona (uma vez por instância de g_shopMenu) o primeiro botão do painel,
--- com o texto de busca e o callback de abrir o diálogo, mais um segundo
--- botão de "limpar", visível só com busca ativa.
function ShopGuiAdapter:ensureButton(shopMenu)
    if self.ui[shopMenu] then
        return self.ui[shopMenu]
    end
    if not (shopMenu.buttonsPanel and isFn(Utils and Utils.cloneButton)) then
        return nil -- [A VALIDAR na F5]: UIHelper/cloneButton pode não existir; guarda de existência (P7)
    end
    local ok, entry = pcall(function()
        self:_simulatedFailure("ensureButton")
        local template = shopMenu.buttonsPanel.elements and shopMenu.buttonsPanel.elements[1]
        if not template then
            return nil
        end
        local searchButton = Utils.cloneButton(template, shopMenu.buttonsPanel)
        local clearButton = Utils.cloneButton(template, shopMenu.buttonsPanel)
        local compatButton = Utils.cloneButton(template, shopMenu.buttonsPanel)
        if searchButton and searchButton.setText and g_i18n then
            searchButton:setText(g_i18n:getText("sss_button_search"))
        end
        if clearButton and clearButton.setText and g_i18n then
            clearButton:setText(g_i18n:getText("sss_clear"))
        end
        if compatButton and compatButton.setText and g_i18n then
            compatButton:setText(g_i18n:getText("sss_compat_button"))
        end
        if searchButton then
            searchButton.onClickCallback = function()
                self:openInput()
            end
        end
        if clearButton then
            clearButton.onClickCallback = function()
                self:clear()
            end
            if clearButton.setVisible then
                clearButton:setVisible(false)
            end
        end
        if compatButton then
            compatButton.onClickCallback = function()
                self:searchCompatibleWithSelected()
            end
            if compatButton.setVisible then
                compatButton:setVisible(false)
            end
        end
        return { searchButton = searchButton, clearButton = clearButton, compatButton = compatButton }
    end)
    if not ok then
        self:_degrade("ensureButton", entry)
        return nil
    end
    self.ui[shopMenu] = entry
    return entry
end

--- Mostra/oculta os botões conforme a página atual (G3) e o estado do mod.
function ShopGuiAdapter:updateButtonVisibility(shopMenu)
    local entry = self.ui[shopMenu]
    if not entry then
        return
    end
    local degraded = self.state and self.state:is("degraded")
    local pageName = nil
    pcall(function()
        pageName = shopMenu.currentPage and shopMenu.currentPage.name
    end)
    local eligible = (not degraded) and pageName ~= nil and ELIGIBLE_PAGES_SET[pageName]
    if entry.searchButton and entry.searchButton.setVisible then
        entry.searchButton:setVisible(eligible == true)
    end
    if entry.clearButton and entry.clearButton.setVisible then
        entry.clearButton:setVisible(eligible == true and self.searchState:isActive())
    end
    if entry.compatButton and entry.compatButton.setVisible then
        -- G10: só na página de detalhes, com um item selecionado.
        local onDetails = eligible == true and pageName == "pageShopItemDetails"
        entry.compatButton:setVisible(onDetails and self:selectedItem() ~= nil)
    end
end

local function headerText(query, count)
    local text = g_i18n and isFn(g_i18n.getText) and g_i18n:getText("sss_results_header") or "Busca: %s (%d)"
    local ok, formatted = pcall(string.format, text, query and query.raw or "", count)
    return ok and formatted or (query and query.raw or "")
end

--- Executa a busca e exibe os resultados como categoria virtual (ADR-07),
--- ordenados exatamente pela ordem do Ranker.
function ShopGuiAdapter:runSearch(text)
    self.searchState.text = text
    local function run()
        local results, query = self.searchService:search(text, self.searchState.ui)
        self:show(results, query)
    end
    -- Índice ainda não pronto: a busca vai completar o build de uma vez, então
    -- mostra o indicador por um frame antes.
    local lifecycle = self:_lifecycle()
    if lifecycle and lifecycle.index == nil then
        self:_runWithIndicator(run)
    else
        run()
    end
end

function ShopGuiAdapter:show(results, query)
    if not g_shopMenu then
        return
    end
    local ok, err = pcall(function()
        self:_simulatedFailure("show")
        local display = {}
        for i = 1, #results do
            local itemOk, di = pcall(g_shopController.makeDisplayItem, g_shopController, results[i].item.ref)
            if itemOk and di then
                display[#display + 1] = di
            end
        end

        local page = g_shopMenu.pageShopItemDetails
        if not (page and isFn(page.setDisplayItems) and isFn(page.setCategory)) then
            return -- [A VALIDAR na F5]
        end

        if not self.searchState.prevCategory then
            self.searchState.prevCategory = {
                currentPage = g_shopMenu.currentPage,
            }
        end

        local header = (#display == 0) and (g_i18n and g_i18n:getText("sss_results_empty"))
            or headerText(query, #display)
        page:setDisplayItems(display)
        page:setCategory(SSS_CATEGORY, header, ShopMenu.SLICE_ID and ShopMenu.SLICE_ID.VEHICLES)

        if isFn(page.resetListSelection) then
            page:resetListSelection()
        end

        local alreadyOpen = g_shopMenu.currentPage == page
        if not alreadyOpen and isFn(g_shopMenu.pushDetail) then
            g_shopMenu:pushDetail(page)
        end

        local entry = self.ui[g_shopMenu]
        if entry and entry.clearButton and entry.clearButton.setVisible then
            entry.clearButton:setVisible(self.searchState:isActive())
        end
    end)
    if not ok then
        self:_degrade("show", err)
    end
end

--- Abre o diálogo de texto (fase 1, ADR-08). A busca incremental (campo
--- embutido) é da F7, se a F5 confirmar viabilidade.
function ShopGuiAdapter:openInput()
    if not isFn(TextInputDialog and TextInputDialog.createFromExistingGui) then
        return
    end
    local ok, err = pcall(function()
        self:_simulatedFailure("openInput")
        TextInputDialog.createFromExistingGui({
            text = self.searchState.text or "",
            maxCharacters = 80,
            title = g_i18n and g_i18n:getText("sss_dialog_title"),
            callback = function(dialogText)
                if dialogText == nil or dialogText == "" then
                    self:clear()
                else
                    self:runSearch(dialogText)
                end
            end,
        })
        -- D8: desativa o filtro de palavrões só se a propriedade existir.
        if
            TextInputDialog.INSTANCE
            and TextInputDialog.INSTANCE.textElement
            and TextInputDialog.INSTANCE.textElement.applyProfanityFilter ~= nil
        then
            TextInputDialog.INSTANCE.textElement.applyProfanityFilter = false -- luacheck: ignore 122
        end
    end)
    if not ok then
        self:_degrade("openInput", err)
    end
end

--- Limpa a busca (RF-004, L3): zera texto/filtros/contexto, volta para a
--- categoria anterior e some com o botão "limpar".
function ShopGuiAdapter:clear()
    self.searchState:clear()
    local ok, err = pcall(function()
        if g_shopMenu and isFn(g_shopMenu.popDetail) and g_shopMenu.currentPage == g_shopMenu.pageShopItemDetails then
            g_shopMenu:popDetail()
        end
        self.searchState.prevCategory = nil
        local entry = self.ui[g_shopMenu]
        if entry and entry.clearButton and entry.clearButton.setVisible then
            entry.clearButton:setVisible(false)
        end
    end)
    if not ok then
        self:_degrade("clear", err)
    end
end

--- Item atualmente selecionado na página de detalhes (G10, usado por
--- "compatível com este trator"). [A VALIDAR na F5]: caminho exato do
--- StoreItem selecionado na página de detalhes da loja.
--- @return IndexedItem|nil
function ShopGuiAdapter:selectedItem()
    if not (g_shopMenu and g_shopMenu.pageShopItemDetails) then
        return nil
    end
    local ok, storeItem = pcall(function()
        return g_shopMenu.pageShopItemDetails.currentItem or g_shopMenu.pageShopItemDetails.item
    end)
    if not ok or not storeItem then
        return nil
    end
    local index = self.searchService.deps.indexLifecycle and self.searchService.deps.indexLifecycle.index
    if not index then
        return nil
    end
    for _, item in ipairs(index.items) do
        if item.ref == storeItem then
            return item
        end
    end
    return nil
end

--- Abre a busca de "compatível com este veículo/implemento" (G10), a partir
--- do item selecionado. Reusa a frase "compatível com este", que o
--- QueryParser (core/lang/ContextParser) já reconhece como contexto
--- target="selected" — mais simples do que montar o Query manualmente.
function ShopGuiAdapter:searchCompatibleWithSelected()
    local compatPhrase = (g_i18n and g_i18n:getText("sss_compat_query")) or "compativel com este"
    -- A extração de compatibilidade lê o XML dos candidatos: indicador
    -- `sss_indexing` visível por um frame antes (smoke F8).
    self:_runWithIndicator(function()
        local results, query = self.searchService:search(compatPhrase, nil)
        self:show(results, query)
    end)
end

--- Instala os hooks na loja via HookRegistry (ADR-03). Chamar uma vez no
--- bootstrap, depois que ShopMenu já existe.
function ShopGuiAdapter:install()
    local HookRegistry = NS.adapters.HookRegistry
    local self_ = self

    HookRegistry.add({
        id = "shopgui:onOpen",
        target = ShopMenu,
        method = "onOpen",
        kind = "append",
        fn = function(shopMenu)
            if shopMenu ~= g_shopMenu then
                return
            end
            NS.app.SafeCall.run("shopgui:onOpen", function()
                self_.searchService:ensureIndex(0.008) -- orçamento por frame, ADR-04
                self_.inputAdapter:bind()
                self_:ensureButton(shopMenu)
                self_:updateButtonVisibility(shopMenu)
                self_:refreshBusy() -- build fatiado em andamento: indicador desde a abertura
            end)
        end,
    })

    HookRegistry.add({
        id = "shopgui:onClose",
        target = ShopMenu,
        method = "onClose",
        kind = "append",
        fn = function(shopMenu)
            if shopMenu ~= g_shopMenu then
                return
            end
            NS.app.SafeCall.run("shopgui:onClose", function()
                self_.inputAdapter:unbind()
                self_.pendingAction = nil -- ação adiada não sobrevive ao fechamento
                self_:_setBusy(false)
            end)
        end,
    })

    -- [A VALIDAR na F5]: ShopMenu.update(dt) só roda com a loja aberta. Sem
    -- ele, o trabalho fatiado avança só na abertura/busca e as ações rodam na hora.
    self.frameHookActive = HookRegistry.add({
        id = "shopgui:update",
        target = ShopMenu,
        method = "update",
        kind = "append",
        fn = function(shopMenu)
            if shopMenu ~= g_shopMenu then
                return
            end
            NS.app.SafeCall.run("shopgui:update", function()
                self_:onFrame()
            end)
        end,
    }) == true

    HookRegistry.add({
        id = "shopgui:updateButtonsPanel",
        target = ShopMenu,
        method = "updateButtonsPanel",
        kind = "append",
        fn = function(shopMenu)
            if shopMenu ~= g_shopMenu then
                return
            end
            NS.app.SafeCall.run("shopgui:updateButtonsPanel", function()
                self_:updateButtonVisibility(shopMenu)
            end)
        end,
    })

    if self.state then
        self.state:onChange(function(to)
            if to == "degraded" then
                pcall(function()
                    self:updateButtonVisibility(g_shopMenu)
                    self.inputAdapter:unbind()
                    if
                        g_shopMenu
                        and isFn(g_shopMenu.popDetail)
                        and g_shopMenu.currentPage == g_shopMenu.pageShopItemDetails
                        and g_shopMenu.currentPage.name == SSS_CATEGORY
                    then
                        g_shopMenu:popDetail()
                    end
                end)
            end
        end)
    end
end

NS.adapters.ShopGuiAdapter = ShopGuiAdapter
