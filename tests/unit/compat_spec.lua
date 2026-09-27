require("tests.support.load").load()
local NS = SmartShopSearch
local CompatibilityResolver = NS.core.CompatibilityResolver
local xml = require("tests.support.xml")

local function buildInfo(node, powerAttr, neededPowerAttr)
    local info = { attach = {}, inputAttach = {}, combinations = {} }
    info.xmlFilename = node.attrs.xmlFilename
    if node.attrs[powerAttr] then
        info.power = tonumber(node.attrs[powerAttr])
    end
    if node.attrs[neededPowerAttr] then
        info.neededPower = tonumber(node.attrs[neededPowerAttr])
    end
    for _, a in ipairs(xml.children(node, "attach")) do
        info.attach[a.attrs.type] = true
    end
    for _, a in ipairs(xml.children(node, "inputAttach")) do
        info.inputAttach[a.attrs.type] = true
    end
    for _, c in ipairs(xml.children(node, "combination")) do
        info.combinations[c.attrs.xmlFilename] = true
    end
    return info
end

local function loadCases()
    local root = xml.load("tests/fixtures/compat/joints.xml")
    local cases = {}
    for _, caseNode in ipairs(xml.children(root, "case")) do
        local vehicleNode = xml.child(caseNode, "vehicle")
        local implementNode = xml.child(caseNode, "implement")
        local expectNode = xml.child(caseNode, "expect")
        cases[#cases + 1] = {
            id = caseNode.attrs.id,
            vehicle = buildInfo(vehicleNode, "power", "neededPower"),
            implement = buildInfo(implementNode, "power", "neededPower"),
            expectLevel = expectNode.attrs.level,
            expectPowerOk = expectNode.attrs.powerOk,
        }
    end
    return cases
end

describe("CompatibilityResolver (fixtures/compat/joints.xml)", function()
    for _, case in ipairs(loadCases()) do
        it(case.id, function()
            local result = CompatibilityResolver.evaluate(case.vehicle, case.implement)
            if case.expectLevel == "none" then
                assert.is_nil(result, case.id .. ": esperava nil (sem evidência)")
            else
                assert.is_not_nil(result, case.id .. ": esperava resultado não-nil")
                assert.are.equal(case.expectLevel, result.level)
                assert.is_true(#result.evidence >= 1)
                if case.expectPowerOk ~= nil then
                    local expected = case.expectPowerOk == "true"
                    assert.are.equal(expected, result.powerOk)
                end
            end
        end)
    end

    it("caso obrigatório RF-050: itens com nome/marca iguais mas sem joints/combinações -> nil", function()
        local vehicle = { xmlFilename = "same-brand-tractor.xml", attach = {}, inputAttach = {}, combinations = {} }
        local implement = { xmlFilename = "same-brand-implement.xml", attach = {}, inputAttach = {}, combinations = {} }
        assert.is_nil(CompatibilityResolver.evaluate(vehicle, implement))
    end)

    it("declared tem prioridade de nível mesmo se também houver joint compatível", function()
        local vehicle = {
            xmlFilename = "v.xml",
            attach = { cat2 = true },
            inputAttach = {},
            combinations = { ["i.xml"] = true },
        }
        local implement = { xmlFilename = "i.xml", attach = {}, inputAttach = { cat2 = true }, combinations = {} }
        local result = CompatibilityResolver.evaluate(vehicle, implement)
        assert.are.equal("declared", result.level)
    end)

    it("powerOk é nil quando falta power ou neededPower (não afirma nem nega)", function()
        local vehicle = { xmlFilename = "v.xml", attach = { cat2 = true }, inputAttach = {}, combinations = {} }
        local implement = { xmlFilename = "i.xml", attach = {}, inputAttach = { cat2 = true }, combinations = {} }
        local result = CompatibilityResolver.evaluate(vehicle, implement)
        assert.is_nil(result.powerOk)
    end)

    it("texto nunca entra na decisão: CompatInfo não tem nem aceita campo de nome", function()
        local vehicle = { xmlFilename = "v.xml", attach = { cat2 = true }, inputAttach = {}, combinations = {} }
        local implement = { xmlFilename = "i.xml", attach = {}, inputAttach = { cat2 = true }, combinations = {} }
        -- mesmo se alguém tentasse colar um campo de nome, evaluate() nunca o lê.
        vehicle.name = "Trator Genérico"
        implement.name = "Trator Genérico"
        local result = CompatibilityResolver.evaluate(vehicle, implement)
        assert.are.equal("joint", result.level)
    end)
end)
