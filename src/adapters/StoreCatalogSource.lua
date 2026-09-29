-- Implementa a porta CatalogSource sobre o catálogo real da loja (PRD §9.1).
-- Único adapter que entrega RawItem[] ao IndexBuilder em jogo. Cada item é
-- extraído dentro de um pcall (RF-062): falha em um item não aborta os
-- demais. [A VALIDAR na F5]: nomes exatos de campos de StoreItem.
local NS = SmartShopSearch
local StoreCatalogSource = {}
StoreCatalogSource.__index = StoreCatalogSource

---@param specExtractor table  adapters/SpecExtractor
---@param logger table|nil
function StoreCatalogSource.new(specExtractor, logger)
    return setmetatable({ specExtractor = specExtractor, logger = logger, skipped = {} }, StoreCatalogSource)
end

--- @param si table  StoreItem
--- @return boolean
function StoreCatalogSource:inScope(si)
    if not si.showInStore or si.isBundleItem then
        return false
    end
    local sp = si.species
    return sp == StoreSpecies.VEHICLE
        or sp == StoreSpecies.HANDTOOL
        or (self.includePlaceables and sp == StoreSpecies.PLACEABLE) -- S-03 [A VALIDAR na F5]
end

--- Converte um StoreItem em RawItem, protegendo cada acesso a `nil`
--- (RF-061: campo ausente é só ignorado, nunca aborta o item).
---@param si table
---@return RawItem
function StoreCatalogSource:toRaw(si)
    local raw = { ref = si }

    local ok, xmlFilename = pcall(function()
        return si.xmlFilename
    end)
    raw.xmlFilename = ok and xmlFilename or nil

    pcall(function()
        raw.name = si.name
    end)
    pcall(function()
        raw.species = tostring(si.species)
    end)
    pcall(function()
        raw.price = si.price
    end)

    pcall(function()
        if si.brandIndex ~= nil and g_brandManager and g_brandManager.getBrandByIndex then
            local brand = g_brandManager:getBrandByIndex(si.brandIndex)
            if brand then
                raw.brand = brand.name or brand.brandName
                raw.brandTitle = brand.title
            end
        end
    end)

    pcall(function()
        raw.categoryId = si.categoryName
        if raw.categoryId and g_storeManager and g_storeManager.getCategoryByName then
            local category = g_storeManager:getCategoryByName(raw.categoryId)
            raw.categoryTitle = category and category.title or nil
        end
    end)

    local isMod = false
    pcall(function()
        isMod = si.isMod == true
    end)
    pcall(function()
        raw.dlcTitle = si.dlcTitle
    end)

    if isMod then
        pcall(function()
            local env = si.customEnvironment
            local mod = env and g_modManager and g_modManager.nameToMod[env]
            if mod then
                raw.modName = env
                raw.modTitle = mod.title
                raw.author = mod.author
            end
        end)
        raw.origin = "mod"
    elseif raw.dlcTitle and raw.dlcTitle ~= "" then
        raw.origin = "dlc"
    else
        raw.origin = "base"
    end

    raw.specs = {}
    if self.specExtractor then
        local primary, invalidCount = self.specExtractor:primary(si)
        for specId, value in pairs(primary) do
            raw.specs[specId] = { value = value }
        end
        if invalidCount > 0 then
            self.skipped["invalid-spec:primary"] = (self.skipped["invalid-spec:primary"] or 0) + invalidCount
        end
    end

    return raw
end

---@return RawItem[]
function StoreCatalogSource:items()
    local out = {}
    self.skipped = {}
    local ok, storeItems = pcall(function()
        return g_storeManager:getItems()
    end)
    if not ok or not storeItems then
        if self.logger then
            self.logger:error("catalog", "g_storeManager:getItems() falhou")
        end
        return out
    end

    for i = 1, #storeItems do
        local si = storeItems[i]
        local inScopeOk, inScope = pcall(function()
            return self:inScope(si)
        end)
        if inScopeOk and inScope then
            local rawOk, raw = pcall(function()
                return self:toRaw(si)
            end)
            if rawOk and raw then
                out[#out + 1] = raw
            else
                self.skipped["extract-error"] = (self.skipped["extract-error"] or 0) + 1
                if self.logger then
                    self.logger:warning("catalog", "falha ao extrair item %d: %s", i, tostring(raw))
                end
            end
        end
    end
    return out
end

--- Especificações técnicas secundárias (leitura de XML), fatiada pelo
--- IndexLifecycle após o build primário, fora da abertura da loja (R4).
--- Só para specs com cobertura primária baixa (decisão tomada com os dados
--- reais da F5 — aqui apenas expõe o mecanismo).
---@param rawItem RawItem
---@return table<string, number>
function StoreCatalogSource:secondarySpecsFor(rawItem)
    if not self.specExtractor or not rawItem.ref then
        return {}
    end
    return self.specExtractor:secondary(rawItem.ref)
end

--- Serializa os RawItem extraídos no mesmo formato de tests/fixtures/catalog/*.xml
--- (`sssDumpCatalog`, debug): útil para alimentar o corpus golden com dados
--- reais (§9.4 PRD). Grava em modSettings/FS25_SmartShopSearch/dumps/ via
--- XMLFile (nunca `io.*` — offline-first, RNF-004/check_deps.py: todo
--- arquivo passa pela API do jogo, nunca pela lib `io` do Lua puro).
--- [A VALIDAR na F5]: assinatura exata de XMLFile.create/setString/save
--- para escrever uma lista de elementos dinâmica.
---@return string path
function StoreCatalogSource:dumpToFile()
    local rawItems = self:items()
    local dumpDir = (g_modSettingsDirectory or "") .. "FS25_SmartShopSearch/dumps/"
    local path = dumpDir .. "catalog_live.xml"
    if not (type(XMLFile) == "table" and type(XMLFile.create) == "function") then
        return path .. " (não gravado: XMLFile indisponível)"
    end
    pcall(function()
        createFolder(dumpDir)
    end)
    pcall(function()
        local xmlFile = XMLFile.create("SSSDumpCatalog", path, "catalog")
        xmlFile:setString("catalog#profile", "live")
        for i, raw in ipairs(rawItems) do
            local key = string.format("catalog.item(%d)", i - 1)
            xmlFile:setString(key .. "#xmlFilename", raw.xmlFilename)
            xmlFile:setString(key .. "#name", raw.name)
            xmlFile:setString(key .. "#brand", raw.brand)
            xmlFile:setString(key .. "#brandTitle", raw.brandTitle)
            xmlFile:setString(key .. "#categoryId", raw.categoryId)
            xmlFile:setString(key .. "#categoryTitle", raw.categoryTitle)
            xmlFile:setString(key .. "#species", raw.species)
            if raw.price then
                xmlFile:setFloat(key .. "#price", raw.price)
            end
            xmlFile:setString(key .. "#origin", raw.origin)
            xmlFile:setString(key .. "#modName", raw.modName)
            xmlFile:setString(key .. "#modTitle", raw.modTitle)
            xmlFile:setString(key .. "#author", raw.author)
            xmlFile:setString(key .. "#dlcTitle", raw.dlcTitle)
            local specIndex = 0
            for specId, spec in pairs(raw.specs or {}) do
                local specKey = string.format("%s.spec(%d)", key, specIndex)
                xmlFile:setString(specKey .. "#id", specId)
                xmlFile:setFloat(specKey .. "#value", spec.value)
                specIndex = specIndex + 1
            end
        end
        xmlFile:save()
        if type(xmlFile.delete) == "function" then
            xmlFile:delete()
        end
    end)
    return path
end

NS.adapters.StoreCatalogSource = StoreCatalogSource
