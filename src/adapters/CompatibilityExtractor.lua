-- Extrai CompatInfo (engates, combinações declaradas) do XML do item, sob
-- demanda e com cache por xmlFilename (R4: nunca na abertura da loja).
-- [A VALIDAR na F5 §9]: caminhos exatos de attacherJoints/inputAttacherJoints
-- e da lista de combinações declaradas. Falha por item = sem CompatInfo,
-- nunca aparece como compatível (conservador, RF-050).
local NS = SmartShopSearch
local CompatibilityExtractor = {}
CompatibilityExtractor.__index = CompatibilityExtractor

function CompatibilityExtractor.new(logger)
    return setmetatable({ logger = logger, cache = {} }, CompatibilityExtractor)
end

--- @param item IndexedItem
--- @return CompatInfo|nil
function CompatibilityExtractor:infoFor(item)
    if not item or not item.xmlFilename then
        return nil
    end
    if self.cache[item.xmlFilename] ~= nil then
        local cached = self.cache[item.xmlFilename]
        return cached ~= false and cached or nil
    end

    local info = { attach = {}, inputAttach = {}, combinations = {}, xmlFilename = item.xmlFilename }
    if item.specs and item.specs.power then
        info.power = item.specs.power.value
    end
    if item.specs and item.specs.neededPower then
        info.neededPower = item.specs.neededPower.value
    end

    local ok = pcall(function()
        if type(XMLFile) ~= "table" or type(XMLFile.load) ~= "function" then
            return
        end
        local xmlFile = XMLFile.load("SSSCompatExtractor", item.xmlFilename)
        if not xmlFile then
            return
        end
        -- [A VALIDAR na F5]: caminhos reais de attacherJoints/inputAttacherJoints/combinations.
        xmlFile:iterate("vehicle.attacherJoints.attacherJoint", function(_, key)
            local jointType = xmlFile:getString(key .. "#jointType")
            if jointType then
                info.attach[jointType] = true
            end
        end)
        xmlFile:iterate("vehicle.inputAttacherJoints.inputAttacherJoint", function(_, key)
            local jointType = xmlFile:getString(key .. "#jointType")
            if jointType then
                info.inputAttach[jointType] = true
            end
        end)
        xmlFile:iterate("vehicle.storeData.specs.combinations.combination", function(_, key)
            local xmlFilename = xmlFile:getString(key .. "#xmlFilename")
            if xmlFilename then
                info.combinations[xmlFilename] = true
            end
        end)
        if type(xmlFile.delete) == "function" then
            xmlFile:delete()
        end
    end)

    if not ok then
        if self.logger then
            self.logger:warning("compat", "falha ao extrair CompatInfo de %s", item.xmlFilename)
        end
        self.cache[item.xmlFilename] = false
        return nil
    end

    self.cache[item.xmlFilename] = info
    return info
end

NS.adapters.CompatibilityExtractor = CompatibilityExtractor
