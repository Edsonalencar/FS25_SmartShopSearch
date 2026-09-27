-- Extração de especificações técnicas em camadas (PRD §9.2, RF-011/RF-046).
-- Camada primária: specs já calculadas pelo jogo (storeItem.specs).
-- Camada secundária (sob demanda, fatiada pelo IndexLifecycle, cache por
-- xmlFilename): leitura direta do XML do veículo, só para specs com baixa
-- cobertura na fonte primária. [A VALIDAR na F5]: estrutura exata de
-- storeItem.specs e os caminhos XML reais — nada disso é usado por core/,
-- então uma correção aqui nunca exige mudar o motor de busca.
local NS = SmartShopSearch
local SpecExtractor = {}
SpecExtractor.__index = SpecExtractor

---@param specRegistry table<string, {quantity:string, canonicalUnit:string}>
---@param logger table|nil
function SpecExtractor.new(specRegistry, logger)
    return setmetatable({ specRegistry = specRegistry, logger = logger, xmlCache = {} }, SpecExtractor)
end

local function isFiniteNonNegative(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= 0
end

--- Camada primária: storeItem.specs [A VALIDAR estrutura exata na F5 — pode
--- vir de storeItem.specs[id] diretamente ou exigir g_storeManager:getSpecTypes()].
---@param storeItem table
---@return table<string, number> specs, integer invalidCount
function SpecExtractor:primary(storeItem)
    local out, invalidCount = {}, 0
    local ok = pcall(function()
        if storeItem.specs then
            for specId, rawValue in pairs(storeItem.specs) do
                if self.specRegistry[specId] then
                    if isFiniteNonNegative(rawValue) then
                        out[specId] = rawValue
                    else
                        invalidCount = invalidCount + 1
                    end
                end
            end
        end
    end)
    if not ok and self.logger then
        self.logger:warning(
            "spec",
            "falha ao extrair specs primárias de %s",
            tostring(storeItem and storeItem.xmlFilename)
        )
    end
    return out, invalidCount
end

--- Camada secundária (sob demanda): lê o XML do item para specs ausentes na
--- fonte primária. Cache por xmlFilename — nunca lida na abertura da loja,
--- só fatiada pelo IndexLifecycle depois do build primário (R4).
---@param storeItem table
---@return table<string, number>
function SpecExtractor:secondary(storeItem)
    local xmlFilename = storeItem and storeItem.xmlFilename
    if not xmlFilename then
        return {}
    end
    if self.xmlCache[xmlFilename] then
        return self.xmlCache[xmlFilename]
    end

    local out = {}
    pcall(function()
        if type(XMLFile) == "table" and type(XMLFile.load) == "function" then
            local xmlFile = XMLFile.load("SSSSpecExtractor", xmlFilename)
            if xmlFile then
                -- [A VALIDAR na F5]: caminhos reais de storeData.specs.*, fillUnit, workingWidth.
                local candidates = {
                    power = "vehicle.storeData.specs.power",
                    neededPower = "vehicle.storeData.specs.neededPower",
                    workingWidth = "vehicle.storeData.specs.workingWidth",
                    maxSpeed = "vehicle.storeData.specs.maxSpeed",
                }
                for specId, path in pairs(candidates) do
                    local value = xmlFile:getFloat(path)
                    if isFiniteNonNegative(value) then
                        out[specId] = value
                    end
                end
                if type(xmlFile.delete) == "function" then
                    xmlFile:delete()
                end
            end
        end
    end)
    self.xmlCache[xmlFilename] = out
    return out
end

NS.adapters.SpecExtractor = SpecExtractor
