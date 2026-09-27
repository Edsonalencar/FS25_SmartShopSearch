-- Parser XML mínimo em Lua 5.1 (elementos, atributos, texto, CDATA, entidades
-- básicas), usado SOMENTE para carregar src/data/** e fixtures/golden nos
-- testes. Em jogo, o equivalente é o adapter XmlDataLoader (F3), que usa a
-- API XMLFile do jogo. Não é um parser XML completo (sem namespaces, sem
-- DOCTYPE, sem processing instructions além de <?xml ... ?>).
local M = {}

local ENTITIES = {
    lt = "<",
    gt = ">",
    amp = "&",
    quot = '"',
    apos = "'",
}

local function decodeEntities(s)
    s = s:gsub("&#(%d+);", function(n)
        return string.char(tonumber(n) % 256)
    end)
    s = s:gsub("&(%a+);", function(name)
        return ENTITIES[name] or ("&" .. name .. ";")
    end)
    return s
end

local function newNode(tag)
    return { tag = tag, attrs = {}, children = {}, text = "" }
end

local function parseAttrs(str)
    local attrs = {}
    for name, _, value in str:gmatch("([%w_:%-%.]+)%s*=%s*([\"'])(.-)%2") do
        attrs[name] = decodeEntities(value)
    end
    return attrs
end

--- Analisa uma string XML e retorna o nó raiz: {tag, attrs, children, text}.
function M.parse(content)
    -- Remove declaração XML e comentários.
    content = content:gsub("<%?.-%?>", "")
    content = content:gsub("<!%-%-.-%-%->", "")

    local stack = { newNode("#root") }
    local pos = 1
    local len = #content

    while pos <= len do
        local ltPos = content:find("<", pos, true)
        if not ltPos then
            local trailing = content:sub(pos)
            if trailing:match("%S") then
                local top = stack[#stack]
                top.text = top.text .. decodeEntities(trailing)
            end
            break
        end
        if ltPos > pos then
            local textChunk = content:sub(pos, ltPos - 1)
            if textChunk:match("%S") then
                local top = stack[#stack]
                top.text = top.text .. decodeEntities(textChunk)
            end
        end

        if content:sub(ltPos, ltPos + 8) == "<![CDATA[" then
            local closePos = content:find("]]>", ltPos + 9, true)
            local cdata = content:sub(ltPos + 9, (closePos or len + 1) - 1)
            local top = stack[#stack]
            top.text = top.text .. cdata
            pos = (closePos or len) + 3
        elseif content:sub(ltPos, ltPos + 1) == "</" then
            local gtPos = content:find(">", ltPos, true)
            pos = gtPos + 1
            if #stack > 1 then
                table.remove(stack)
            end
        else
            local gtPos = content:find(">", ltPos, true)
            local tagContent = content:sub(ltPos + 1, gtPos - 1)
            local selfClose = false
            if tagContent:sub(-1) == "/" then
                selfClose = true
                tagContent = tagContent:sub(1, -2)
            end
            local tag, rest = tagContent:match("^([%w_:%-%.]+)(.*)$")
            local node = newNode(tag)
            node.attrs = parseAttrs(rest or "")
            local top = stack[#stack]
            top.children[#top.children + 1] = node
            if not selfClose then
                stack[#stack + 1] = node
            end
            pos = gtPos + 1
        end
    end

    local root = stack[1]
    return root.children[1]
end

--- Carrega e analisa um arquivo XML do disco.
function M.load(path)
    local fh = io.open(path, "r")
    if not fh then
        return nil
    end
    local content = fh:read("*a")
    fh:close()
    return M.parse(content)
end

--- Retorna a lista de filhos diretos com o nome dado.
function M.children(node, tag)
    local out = {}
    if not node then
        return out
    end
    for _, c in ipairs(node.children) do
        if c.tag == tag then
            out[#out + 1] = c
        end
    end
    return out
end

--- Retorna o primeiro filho direto com o nome dado, ou nil.
function M.child(node, tag)
    if not node then
        return nil
    end
    for _, c in ipairs(node.children) do
        if c.tag == tag then
            return c
        end
    end
    return nil
end

--- Texto (trim) de um nó, ou "" se nil.
function M.text(node)
    if not node then
        return ""
    end
    return (node.text or ""):match("^%s*(.-)%s*$")
end

return M
