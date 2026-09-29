-- FS25_SSS_Spike — mod descartável da Fase 5 (spec §Phase 5).
-- Objetivo: responder aos itens [A VALIDAR] do PRD contra o FS25 real antes
-- de implementar adapters/ (F6-F8). Roda SÓ no jogo (Windows/Proton) — não
-- há como executar isto no ambiente de desenvolvimento (núcleo Linux).
--
-- Comandos de console (digite no console de desenvolvedor do jogo,
-- game.xml com <development><controls>true</controls></development>):
--   sssSpikeProbe   -- imprime type() de cada API candidata (§1 do template)
--   sssSpikeDump <perfil>  -- grava modSettings/FS25_SSS_Spike/dumps/catalog_<perfil>.xml
--   sssSpikeBench   -- mede o tempo de iterar getItems() e ler XML de 100 itens
--   sssSpikeGui     -- abre um protótipo de categoria virtual com 3 itens fixos
--                      em ordem não alfabética, prova que a ordem é respeitada
--   sssSpikeGuiEmpty -- idem, mas com lista vazia (G11)

local MOD_DIR = g_currentModDirectory
local MOD_NAME = g_currentModName

SSSSpike = { MOD_DIR = MOD_DIR, MOD_NAME = MOD_NAME }

-- ===========================================================================
-- 1) Probe de APIs candidatas (PRD §1 do api-findings). Preenche a tabela
--    "Tabela [A VALIDAR]" do template com o `type()` de cada uma.
-- ===========================================================================

local CANDIDATES = {
    "ShopMenu.onOpen",
    "ShopMenu.onClose",
    "ShopMenu.updateButtonsPanel",
    "g_shopMenu",
    "g_shopMenu.pageShopItemDetails",
    "g_shopController",
    "g_shopController.makeDisplayItem",
    "TextInputDialog",
    "TextInputDialog.createFromExistingGui",
    "TextInputDialog.INSTANCE",
    "g_brandManager",
    "g_brandManager.getBrandByIndex",
    "g_storeManager",
    "g_storeManager.getItems",
    "g_storeManager.getCategoryByName",
    "g_storeManager.getSpecTypes",
    "g_modManager",
    "g_modManager.nameToMod",
    "g_inputBinding",
    "g_inputBinding.registerActionEvent",
    "XMLFile",
    "XMLFile.load",
    "XMLFile.loadIfExists",
    "Logging",
    "Logging.info",
    "Logging.warning",
    "Logging.error",
    "g_modSettingsDirectory",
    "g_languageShort",
    "g_modIsLoaded",
    "StoreSpecies",
    "StoreSpecies.VEHICLE",
    "StoreSpecies.HANDTOOL",
    "StoreSpecies.PLACEABLE",
    "TabbedMenuWithDetails",
    "TabbedMenuWithDetails.onOpen",
}

-- Resolve uma string "a.b.c" contra os globais, sem lançar erro se algo no
-- meio do caminho não existir.
local function resolvePath(path)
    local parts = {}
    for part in path:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end
    local ok, value = pcall(function()
        local cur = _G[parts[1]]
        for i = 2, #parts do
            if cur == nil then
                return nil
            end
            cur = cur[parts[i]]
        end
        return cur
    end)
    if not ok then
        return nil, "erro ao resolver"
    end
    return value
end

function SSSSpike.probe()
    print("[SSSSpike] === probe de APIs candidatas ===")
    for _, path in ipairs(CANDIDATES) do
        local value = resolvePath(path)
        print(string.format("[SSSSpike] %-45s type=%s", path, type(value)))
    end
    print("[SSSSpike] === fim do probe ===")
end

-- ===========================================================================
-- 2) Dump do catálogo no formato exato de tests/fixtures/catalog/*.xml,
--    incluindo todas as chaves de storeItem.specs encontradas e, para uma
--    amostra de 50 itens, os caminhos XML candidatos (storeData.specs.*,
--    fillUnit, workingWidth, attacherJoints, inputAttacherJoints).
-- ===========================================================================

local function xmlEscape(s)
    if s == nil then
        return ""
    end
    s = tostring(s)
    s = s:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    return s
end

local function attr(name, value)
    if value == nil or value == "" then
        return ""
    end
    return string.format(' %s="%s"', name, xmlEscape(value))
end

--- Extrai um RawItem no formato do fixture a partir de um storeItem real.
--- Guardas defensivas em cada acesso (RF-061/062) — nenhum campo é obrigatório.
local function extractRawItemXml(si)
    local ok, xmlFilename = pcall(function()
        return si.xmlFilename
    end)
    if not ok or not xmlFilename then
        return nil
    end

    local name = pcall(function()
        return si.name
    end) and si.name or nil
    local brand = nil
    local brandTitle = nil
    pcall(function()
        if si.brandIndex and g_brandManager and g_brandManager.getBrandByIndex then
            local b = g_brandManager:getBrandByIndex(si.brandIndex)
            if b then
                brand = b.name or b.brandName
                brandTitle = b.title
            end
        end
    end)
    local categoryId = pcall(function()
        return si.categoryName
    end) and si.categoryName or nil
    local categoryTitle = nil
    pcall(function()
        if categoryId and g_storeManager and g_storeManager.getCategoryByName then
            local cat = g_storeManager:getCategoryByName(categoryId)
            categoryTitle = cat and cat.title or nil
        end
    end)
    local species = pcall(function()
        return si.species
    end) and tostring(si.species) or nil
    local price = pcall(function()
        return si.price
    end) and si.price or nil
    local isMod = pcall(function()
        return si.isMod
    end) and si.isMod or false
    local dlcTitle = pcall(function()
        return si.dlcTitle
    end) and si.dlcTitle or nil
    local modName, modTitle, author = nil, nil, nil
    if isMod then
        pcall(function()
            local env = si.customEnvironment
            local mod = env and g_modManager and g_modManager.nameToMod[env]
            if mod then
                modName = env
                modTitle = mod.title
                author = mod.author
            end
        end)
    end
    -- No Lua, string vazia é truthy; o jogo usa "" para itens sem DLC.
    local origin = isMod and "mod" or (dlcTitle and dlcTitle ~= "" and "dlc" or "base")

    local out = { "    <item" .. attr("xmlFilename", xmlFilename) .. attr("name", name) }
    if brand then
        out[#out + 1] = attr("brand", brand) .. attr("brandTitle", brandTitle)
    end
    out[#out + 1] = attr("categoryId", categoryId) .. attr("categoryTitle", categoryTitle)
    out[#out + 1] = attr("species", species) .. attr("price", price) .. attr("origin", origin)
    if modName then
        out[#out + 1] = attr("modName", modName) .. attr("modTitle", modTitle) .. attr("author", author)
    end
    if dlcTitle then
        out[#out + 1] = attr("dlcTitle", dlcTitle)
    end

    local specParts = {}
    pcall(function()
        if si.specs then
            for specId, specValue in pairs(si.specs) do
                if type(specValue) == "number" then
                    specParts[#specParts + 1] =
                        string.format('<spec id="%s" value="%s"/>', xmlEscape(specId), tostring(specValue))
                end
            end
        end
    end)

    if #specParts > 0 then
        return table.concat(out) .. ">\n        " .. table.concat(specParts, "") .. "\n    </item>"
    end
    return table.concat(out) .. " />"
end

function SSSSpike.dump(selfOrProfile, profileArg)
    -- addConsoleCommand invoca o método com SSSSpike como primeiro argumento.
    local profileName = type(selfOrProfile) == "table" and profileArg or selfOrProfile
    if type(profileName) ~= "string" or profileName == "" then
        profileName = "base"
    end
    if not profileName:match("^[%w_+%-]+$") then
        print("[SSSSpike] ERRO: nome de perfil inválido")
        return
    end
    print("[SSSSpike] iniciando dump do perfil " .. profileName)
    local lines = { '<?xml version="1.0" encoding="utf-8" standalone="no"?>', '<catalog profile="' .. profileName .. '">' }
    local specKeys = {}
    local sampleCount = 0
    local samplePaths = {}

    local ok, items = pcall(function()
        return g_storeManager:getItems()
    end)
    if not ok or not items then
        print("[SSSSpike] ERRO: g_storeManager:getItems() falhou ou não existe")
        return
    end

    for i = 1, #items do
        local si = items[i]
        local xml = extractRawItemXml(si)
        if xml then
            lines[#lines + 1] = xml
        end
        pcall(function()
            if si.specs then
                for specId in pairs(si.specs) do
                    specKeys[specId] = (specKeys[specId] or 0) + 1
                end
            end
        end)
        if sampleCount < 50 then
            sampleCount = sampleCount + 1
            samplePaths[#samplePaths + 1] = string.format("-- amostra %d: xmlFilename=%s", sampleCount, tostring(si.xmlFilename))
        end
    end
    lines[#lines + 1] = "</catalog>"

    local settingsDir = (g_modSettingsDirectory or "") .. "FS25_SSS_Spike/"
    local dumpDir = settingsDir .. "dumps/"
    pcall(function()
        createFolder(settingsDir)
        createFolder(dumpDir)
    end)
    local path = dumpDir .. "catalog_" .. profileName .. ".xml"
    local fh = io.open(path, "w") -- ok aqui: mod de spike, fora de src/, nunca publicado
    if fh then
        fh:write(table.concat(lines, "\n"))
        fh:close()
        print("[SSSSpike] dump gravado em " .. path)
    else
        print("[SSSSpike] ERRO: não foi possível abrir " .. path .. " para escrita")
    end

    print("[SSSSpike] chaves de specs encontradas:")
    for specId, count in pairs(specKeys) do
        print(string.format("[SSSSpike]   %s: %d itens", specId, count))
    end

    local samplePath = dumpDir .. "sample_paths_" .. profileName .. ".txt"
    local sfh = io.open(samplePath, "w")
    if sfh then
        sfh:write(table.concat(samplePaths, "\n"))
        sfh:close()
        print("[SSSSpike] amostra de caminhos gravada em " .. samplePath)
    end
end

-- ===========================================================================
-- 3) Protótipo G1-G6, G11, G12: botão + diálogo + categoria virtual com 3
--    itens fixos em ordem NÃO alfabética (prova que a ordem é respeitada),
--    e lista vazia.
-- ===========================================================================

function SSSSpike.openGui(selfOrEmpty)
    local empty = selfOrEmpty == true
    if not g_shopMenu then
        print("[SSSSpike] g_shopMenu não existe (loja não está aberta?)")
        return
    end
    local ok, err = pcall(function()
        local items = g_storeManager:getItems()
        local display = {}
        if not empty then
            -- ordem deliberadamente não alfabética: prova que a GUI respeita
            -- a ordem que mandamos, não reordena por conta própria.
            local order = { 3, 1, 2 }
            for _, idx in ipairs(order) do
                if items[idx] then
                    local di = g_shopController:makeDisplayItem(items[idx])
                    if di then
                        display[#display + 1] = di
                    end
                end
            end
        end
        local page = g_shopMenu.pageShopItemDetails
        page:setDisplayItems(display)
        page:setCategory("SSS_SPIKE", empty and "SSS Spike (vazio)" or "SSS Spike", ShopMenu.SLICE_ID.VEHICLES)
        g_shopMenu:pushDetail(page)
    end)
    if not ok then
        print("[SSSSpike] ERRO ao abrir GUI de protótipo: " .. tostring(err))
    end
end

-- ===========================================================================
-- 4) Bench: tempo de iterar getItems() e de ler o XML de 100 itens
--    (base para os orçamentos §15 do PRD).
-- ===========================================================================

function SSSSpike.bench()
    local t0 = getTimeSec and getTimeSec() or os.clock()
    local items = g_storeManager:getItems()
    local n = #items
    local t1 = getTimeSec and getTimeSec() or os.clock()
    print(string.format("[SSSSpike] iterar %d itens de getItems(): %.2f ms", n, (t1 - t0) * 1000))

    local sampleSize = math.min(100, n)
    local t2 = getTimeSec and getTimeSec() or os.clock()
    for i = 1, sampleSize do
        pcall(function()
            local xmlFile = XMLFile.load("SSSSpikeBench", items[i].xmlFilename)
            if xmlFile and xmlFile.delete then
                xmlFile:delete()
            end
        end)
    end
    local t3 = getTimeSec and getTimeSec() or os.clock()
    print(string.format("[SSSSpike] ler XML de %d itens: %.2f ms (%.3f ms/item)", sampleSize, (t3 - t2) * 1000, (t3 - t2) * 1000 / sampleSize))
end

-- ===========================================================================
-- Bootstrap: registra os comandos de console.
-- ===========================================================================

local listener = {}
function listener:loadMap()
    if type(addConsoleCommand) == "function" then
        addConsoleCommand("sssSpikeProbe", "Investiga APIs candidatas do FS25", "probe", SSSSpike)
        addConsoleCommand("sssSpikeDump", "Grava dump do catalogo (perfil)", "dump", SSSSpike)
        addConsoleCommand("sssSpikeBench", "Mede tempo de iteracao/leitura de XML", "bench", SSSSpike)
        addConsoleCommand("sssSpikeGui", "Abre protótipo de categoria virtual (3 itens)", "openGui", SSSSpike)
        addConsoleCommand("sssSpikeGuiEmpty", "Abre protótipo de categoria virtual vazia", "openGuiEmpty", SSSSpike)
    end
    print("[SSSSpike] carregado. Comandos: sssSpikeProbe, sssSpikeDump <perfil>, sssSpikeBench, sssSpikeGui, sssSpikeGuiEmpty")
end
function SSSSpike.openGuiEmpty()
    SSSSpike.openGui(true)
end
function listener:deleteMap()
    if type(removeConsoleCommand) == "function" then
        removeConsoleCommand("sssSpikeProbe")
        removeConsoleCommand("sssSpikeDump")
        removeConsoleCommand("sssSpikeBench")
        removeConsoleCommand("sssSpikeGui")
        removeConsoleCommand("sssSpikeGuiEmpty")
    end
end
addModEventListener(listener)
