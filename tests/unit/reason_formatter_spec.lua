require("tests.support.load").load()
local NS = SmartShopSearch
local ReasonFormatter = NS.app.ReasonFormatter
local Models = NS.core.Models

local function fakeI18n(map)
    return {
        getText = function(_, key)
            return map[key] or key
        end,
    }
end

describe("ReasonFormatter", function()
    it("formata uma reason completa como '✓ <campo>: <detalhe>'", function()
        local i18n = fakeI18n({ sss_reason_exact = "Nome" })
        local reason = Models.reason("exact", "name", "trator", "trator", "casou exatamente", 1)
        local line = ReasonFormatter.formatOne(reason, i18n)
        assert.is_not_nil(line:find("Nome"))
        assert.is_not_nil(line:find("casou exatamente"))
    end)

    it("formata sem detail (omite a parte do detalhe)", function()
        local reason = Models.reason("alias", "brand", "fendt", "FENDT", nil, 0.9)
        local line = ReasonFormatter.formatOne(reason, nil)
        assert.is_not_nil(line)
        assert.is_not_nil(line:find("brand"))
    end)

    it("nunca lança erro com reason incompleto (sem kind, sem field)", function()
        assert.has_no.errors(function()
            ReasonFormatter.formatOne({}, nil)
        end)
        assert.has_no.errors(function()
            ReasonFormatter.formatOne(nil, nil)
        end)
        assert.is_nil(ReasonFormatter.formatOne({}, nil))
        assert.is_nil(ReasonFormatter.formatOne(nil, nil))
    end)

    it("format() limita a 4 linhas mesmo com mais reasons", function()
        local reasons = {}
        for i = 1, 10 do
            reasons[i] = Models.reason("exact", "name", "x", "x", "d" .. i, 1)
        end
        local lines = ReasonFormatter.format(reasons, nil)
        assert.are.equal(4, #lines)
    end)

    it("format() com lista vazia/nula não lança erro", function()
        assert.are.same({}, ReasonFormatter.format({}, nil))
        assert.are.same({}, ReasonFormatter.format(nil, nil))
    end)

    it("usa o texto traduzido quando i18n tem a chave (RF-052)", function()
        local i18n = fakeI18n({ sss_reason_constraint = "Especificação" })
        local reason = Models.reason("constraint", "spec.power", "200cv", "184", "184 kW", 0)
        local line = ReasonFormatter.formatOne(reason, i18n)
        assert.is_not_nil(line:find("Especificação"))
    end)
end)

describe("FilterPresets", function()
    local FilterPresets = NS.app.FilterPresets

    it("degraus de preço cobrem 0..300k+ sem sobreposição", function()
        assert.are.equal(0, FilterPresets.price[1].min)
        assert.are.equal(50000, FilterPresets.price[1].max)
        assert.are.equal(50000, FilterPresets.price[2].min)
        assert.is_nil(FilterPresets.price[4].max)
    end)

    it("toCanonicalRange converte a unidade de exibição (cv) para canônica (kW)", function()
        local range = FilterPresets.toCanonicalRange(FilterPresets.power[2], 0.7355) -- 100-200cv
        assert.is_true(math.abs(range.min - 100 * 0.7355) < 0.001)
        assert.is_true(math.abs(range.max - 200 * 0.7355) < 0.001)
    end)

    it("toCanonicalRange preserva nil (faixa aberta)", function()
        local range = FilterPresets.toCanonicalRange(FilterPresets.power[5], 0.7355)
        assert.is_nil(range.max)
    end)
end)
