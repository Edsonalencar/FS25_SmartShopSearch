-- Resolve compatibilidade entre veículo e implemento usando SOMENTE
-- evidências de dados do jogo (combinações declaradas, tipos de engate) —
-- nunca por semelhança textual (RF-050, QM-12). Lua puro, sem globais do
-- jogo: cada relação carrega sua própria evidência (RF-048).
local NS = SmartShopSearch
local CompatibilityResolver = {}

---@class CompatInfo
---@field attach table<string, boolean>       -- tipos de junta que o veículo oferece
---@field inputAttach table<string, boolean>  -- tipos de junta que o implemento aceita
---@field power number|nil                    -- kW
---@field neededPower number|nil              -- kW
---@field combinations table<string, boolean> -- xmlFilename declarados

---@param vehicle CompatInfo & {xmlFilename:string}
---@param implement CompatInfo & {xmlFilename:string}
---@return {level:"declared"|"joint", evidence:string[], powerOk:boolean|nil}|nil
function CompatibilityResolver.evaluate(vehicle, implement)
    local ev = {}
    local level

    if implement.combinations[vehicle.xmlFilename] or vehicle.combinations[implement.xmlFilename] then
        level = "declared"
        ev[#ev + 1] = "combinação declarada"
    end

    for jt in pairs(implement.inputAttach) do
        if vehicle.attach[jt] then
            level = level or "joint"
            ev[#ev + 1] = "engate " .. jt
        end
    end

    if not level then
        return nil -- RF-050: sem evidência técnica, sem compatibilidade
    end

    local powerOk = nil
    if vehicle.power and implement.neededPower then
        powerOk = vehicle.power >= implement.neededPower
    end

    return { level = level, evidence = ev, powerOk = powerOk }
end

NS.core.CompatibilityResolver = CompatibilityResolver
