---@meta
-- Anotações LuaLS dos globais do FS25 usados pelos adapters e por main.lua
-- (F1 do spec). Não é carregado pelo jogo nem pelos testes: serve só ao
-- language server (`.luarc.json` → `workspace.library = ["types"]`).
--
-- Tudo aqui é [A VALIDAR na F5]: assinaturas deduzidas do uso nos adapters,
-- não do LUADOC oficial. Ao confirmar um global no spike, ajustar a
-- anotação e registrar o nome em `tools/fs25_globals.lua` (luacheck).

-- ---------------------------------------------------------------------------
-- Ambiente do mod
-- ---------------------------------------------------------------------------

---@type string  diretório do mod em carregamento (com barra final)
g_currentModDirectory = ""
---@type string  nome interno do mod em carregamento (ex. "FS25_SmartShopSearch")
g_currentModName = ""
---@type string  diretório modSettings/ do usuário (com barra final)
g_modSettingsDirectory = ""
---@type string  código curto do idioma do jogo (ex. "en", "br", "de")
g_languageShort = ""
---@type table<string, boolean>  nome do mod → carregado
g_modIsLoaded = {}
---@type table|nil  não-nil em servidor dedicado
g_dedicatedServer = nil
---@type table|nil  missão atual (nil fora de uma savegame)
g_currentMission = nil

--- Carrega e executa um arquivo Lua do mod.
---@param path string
function source(path) end

--- Registra um listener de ciclo de vida do mapa (loadMap/deleteMap/update).
---@param listener table
function addModEventListener(listener) end

--- Registra um comando de console. `target[callbackName]` é chamado com os argumentos em texto.
---@param name string
---@param description string
---@param callbackName string
---@param target table
function addConsoleCommand(name, description, callbackName, target) end

---@param name string
function removeConsoleCommand(name) end

--- Tempo do motor, em segundos.
---@return number
function getTimeSec() end

---@param path string
function createFolder(path) end

-- ---------------------------------------------------------------------------
-- Log
-- ---------------------------------------------------------------------------

---@class Logging
Logging = {}
---@param fmt string
---@param ... any
function Logging.info(fmt, ...) end
---@param fmt string
---@param ... any
function Logging.warning(fmt, ...) end
---@param fmt string
---@param ... any
function Logging.error(fmt, ...) end

-- ---------------------------------------------------------------------------
-- XML
-- ---------------------------------------------------------------------------

---@class XMLFileInstance
local XMLFileInstance = {}
---@param path string
---@param default string|nil
---@return string|nil
function XMLFileInstance:getString(path, default) end
---@param path string
---@param default number|nil
---@return number|nil
function XMLFileInstance:getFloat(path, default) end
---@param path string
---@param default boolean|nil
---@return boolean|nil
function XMLFileInstance:getBool(path, default) end
---@param path string
---@param value string
function XMLFileInstance:setString(path, value) end
---@param path string
---@param value number
function XMLFileInstance:setFloat(path, value) end
---@param path string
---@param value boolean
function XMLFileInstance:setBool(path, value) end
--- Itera os elementos `path(0)`, `path(1)`, … chamando `fn(index, key)`.
---@param path string
---@param fn fun(index:integer, key:string):boolean|nil
function XMLFileInstance:iterate(path, fn) end
---@return boolean
function XMLFileInstance:save() end
function XMLFileInstance:delete() end

---@class XMLFile
XMLFile = {}
---@param objectName string
---@param filename string
---@return XMLFileInstance|nil
function XMLFile.load(objectName, filename) end
---@param objectName string
---@param filename string
---@return XMLFileInstance|nil
function XMLFile.loadIfExists(objectName, filename) end
---@param objectName string
---@param filename string
---@param rootName string
---@return XMLFileInstance|nil
function XMLFile.create(objectName, filename, rootName) end

-- ---------------------------------------------------------------------------
-- Utilitários de hook e GUI
-- ---------------------------------------------------------------------------

---@class Utils
Utils = {}
---@param original function
---@param fn function
---@return function
function Utils.appendedFunction(original, fn) end
---@param original function
---@param fn function
---@return function
function Utils.prependedFunction(original, fn) end
---@param original function
---@param fn function  recebe `(self, superFunc, ...)`
---@return function
function Utils.overwrittenFunction(original, fn) end
--- Clona um botão de um painel de botões da GUI.
---@param template table
---@param parent table
---@return table|nil
function Utils.cloneButton(template, parent) end

---@class TextInputDialogArgs
---@field text string|nil
---@field maxCharacters integer|nil
---@field title string|nil
---@field callback fun(text:string|nil, clickOk:boolean|nil)

---@class TextInputDialog
---@field INSTANCE table|nil
TextInputDialog = {}
---@param args TextInputDialogArgs
function TextInputDialog.createFromExistingGui(args) end

---@class ShopMenu
---@field SLICE_ID table<string, integer>
---@field buttonsPanel table|nil
---@field currentPage table|nil
---@field pageShopItemDetails table|nil
ShopMenu = {}
function ShopMenu:onOpen() end
function ShopMenu:onClose() end
function ShopMenu:updateButtonsPanel() end
---@param dt number  ms
function ShopMenu:update(dt) end
---@param page table
function ShopMenu:pushDetail(page) end
function ShopMenu:popDetail() end

---@class TabbedMenuWithDetails
TabbedMenuWithDetails = {}

---@type ShopMenu|nil
g_shopMenu = nil

---@class ShopController
g_shopController = {}
---@param storeItem table
---@return table|nil displayItem
function g_shopController:makeDisplayItem(storeItem) end

---@type table  gerenciador de GUI (telas e diálogos)
g_gui = {}

-- ---------------------------------------------------------------------------
-- Catálogo
-- ---------------------------------------------------------------------------

---@class StoreSpecies
---@field VEHICLE any
---@field HANDTOOL any
---@field PLACEABLE any
StoreSpecies = {}

---@class StoreManager
g_storeManager = {}
---@return table[] storeItems
function g_storeManager:getItems() end
---@param name string
---@return {title:string}|nil
function g_storeManager:getCategoryByName(name) end
---@return table[]
function g_storeManager:getSpecTypes() end

---@class BrandManager
g_brandManager = {}
---@param index integer
---@return {name:string, title:string}|nil
function g_brandManager:getBrandByIndex(index) end

---@class ModManager
---@field nameToMod table<string, {title:string, author:string}>
g_modManager = { nameToMod = {} }

-- ---------------------------------------------------------------------------
-- Idioma e input
-- ---------------------------------------------------------------------------

---@class I18N
g_i18n = {}
---@param key string
---@return string
function g_i18n:getText(key) end

---@class InputAction
---@field SMART_SHOP_SEARCH string
InputAction = {}

---@class InputBinding
g_inputBinding = {}
---@return boolean ok, string|nil eventId
function g_inputBinding:registerActionEvent(
    actionName,
    target,
    callback,
    triggerUp,
    triggerDown,
    triggerAlways,
    startActive
)
end
---@param eventId string
function g_inputBinding:removeActionEvent(eventId) end
---@param eventId string
---@param visible boolean
function g_inputBinding:setActionEventTextVisibility(eventId, visible) end
---@param eventId string
---@param priority integer
function g_inputBinding:setActionEventTextPriority(eventId, priority) end
