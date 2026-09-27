-- Faixas de preço/specs em degraus predefinidos por grandeza (G8, RF-045),
-- exibidos na unidade preferida do jogador; convertidos para a unidade
-- canônica (via UnitParser.toCanonical) só ao aplicar o filtro.
local NS = SmartShopSearch
local FilterPresets = {}

FilterPresets.price = {
    { min = 0, max = 50000 },
    { min = 50000, max = 150000 },
    { min = 150000, max = 300000 },
    { min = 300000, max = nil },
}

-- Exibido em cv (unidade métrica de referência); o adapter de UI converte
-- para a unidade preferida do jogador antes de mostrar o rótulo.
FilterPresets.power = {
    { min = 0, max = 100 },
    { min = 100, max = 200 },
    { min = 200, max = 300 },
    { min = 300, max = 400 },
    { min = 400, max = nil },
}

-- Exibido em litros.
FilterPresets.capacity = {
    { min = 0, max = 2000 },
    { min = 2000, max = 5000 },
    { min = 5000, max = 10000 },
    { min = 10000, max = nil },
}

--- Converte um degrau (numa unidade de exibição, ex. cv) para a faixa
--- canônica (kW), usando o fator de conversão do UnitParser.
---@param preset {min:number|nil, max:number|nil}
---@param factor number  fator de conversão para a unidade canônica
---@return {min:number|nil, max:number|nil}
function FilterPresets.toCanonicalRange(preset, factor)
    factor = factor or 1
    return {
        min = preset.min and (preset.min * factor) or nil,
        max = preset.max and (preset.max * factor) or nil,
    }
end

NS.app.FilterPresets = FilterPresets
