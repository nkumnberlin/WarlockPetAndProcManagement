-- Warlock Pet & Proc Management: core.
-- Namespace, saved settings, helpers that never touch secret values, the event hub, the debug
-- log and the slash commands. The features live in Alerts.lua (on-screen warnings and sounds),
-- Pet.lua (pet on passive, Demonic Brand) and Options.lua (options window, minimap button).
--
-- WoW Forever rules this addon follows (see AGENTS.md): no combat log, no reading of enemy auras in
-- combat, no math or comparisons on secret values, no writes to Blizzard globals or tables.

local ADDON_NAME, ns = ...
local L = ns.L

ns.VERSION = "0.1.0"
ns.TITLE = "Warlock Pet & Proc"
ns.SAME_FRAME = 0.02 -- seconds: events in the same frame (DotWatch, DotProbe 0.7)

local issecret = issecretvalue or function() return false end
ns.issecret = issecret

-- call f safely; nil when it fails or the answer is secret
function ns.plain(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if not ok or issecret(v) then return nil end
  return v
end
function ns.str(v)
  if issecret(v) or type(v) ~= "string" then return nil end
  return v
end
function ns.num(v)
  if issecret(v) or type(v) ~= "number" then return nil end
  return v
end
function ns.guidOf(unit) return ns.str(ns.plain(UnitGUID, unit)) end
function ns.now() return GetTime() end
function ns.short(guid) return guid and guid:sub(-6) or "?" end

function ns.say(msg) print("|cff9482c9" .. ns.TITLE .. ":|r " .. msg) end

-- Chat lines from combat wait until the fight is over (DotWatch 0.23.1: printing from addon code in a
-- dungeon fight started the chat-tab fade with a secret alpha -> "tainted by" errors).
ns.held = {}
function ns.sayLater(msg)
  if not InCombatLockdown() then ns.say(msg) return end
  if #ns.held < 20 then ns.held[#ns.held + 1] = msg end
end
function ns.flushHeld()
  local list = ns.held
  if #list == 0 then return end
  ns.held = {}
  for _, msg in ipairs(list) do ns.say(msg) end
end

-- debug log in the SavedVariables (db.debug, last 500 lines; the session before in db.debugPrev)
local DEBUG_MAX = 500
function ns.dbg(msg)
  local db = ns.db
  if not db then return end
  local line = string.format("%.3f %s %s", GetTime(), InCombatLockdown() and "C" or "-", msg)
  local l = db.debug
  l[#l + 1] = line
  if #l > DEBUG_MAX then table.remove(l, 1) end
  if db.debugChat then print("|cff888888PPM " .. line .. "|r") end
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
-- text = nil means "the default message in the current language" (Alerts.lua)
ns.DEFAULTS = {
  locked = true,
  lang = "auto",
  debugChat = false,
  minimap = { angle = 215, hide = false },
  passive = { on = true, size = 30, color = { 1, 0.22, 0.22 }, icon = true, pulse = true,
    sound = true, soundKey = "horn", repeatSec = 0 },
  brand = { on = true, size = 26, color = { 1, 0.55, 0.12 }, icon = true, pulse = true,
    sound = true, soundKey = "emote", repeatSec = 0, delay = 1, charges = false },
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      fill(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end
ns.fillDefaults = fill

-- reset one part (e.g. "passive") or everything but the debug log
function ns.resetSettings(part)
  local db = ns.db
  if part then
    db[part] = {}
    fill(db[part], ns.DEFAULTS[part])
  else
    for k in pairs(ns.DEFAULTS) do db[k] = nil end
    db.pos = nil
    fill(db, ns.DEFAULTS)
  end
end

---------------------------------------------------------------------------
-- Event hub: modules register handlers with ns.on(event, fn); hooks run at "ready" (saved variables
-- loaded) and "login" (PLAYER_LOGIN, class known)
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local handlers = {}
ns.hooks = { ready = {}, login = {} }

function ns.on(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- unknown events (other client versions) must not break loading
    local ok = pcall(ev.RegisterEvent, ev, event)
    if not ok then handlers[event].missing = true end
  end
  table.insert(handlers[event], fn)
end

local errCount = 0
local function report(where, err)
  errCount = errCount + 1
  if errCount <= 20 then ns.dbg("ERROR " .. where .. ": " .. tostring(err)) end
end
ns.report = report

local function run(list, where, ...)
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, ...)
    if not ok then report(where, err) end
  end
end

ev:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if list then run(list, event, ...) end
end)

ns.on("ADDON_LOADED", function(name)
  if name ~= ADDON_NAME then return end
  local db = WarlockPetAndProcManagementDB
  if type(db) ~= "table" then db = {} WarlockPetAndProcManagementDB = db end
  fill(db, ns.DEFAULTS)
  db.debugPrev = db.debug
  db.debug = {}
  ns.db = db
  ns.freezeLanguage()
  ns.dbg("LOAD " .. ns.VERSION .. ", language " .. tostring(ns.active))
  run(ns.hooks.ready, "ready")
end)

ns.on("PLAYER_LOGIN", function()
  local _, class = UnitClass("player")
  ns.isWarlock = class == "WARLOCK"
  ns.inCombat = InCombatLockdown() or ns.plain(UnitAffectingCombat, "player") == true -- /reload in a fight
  ns.dbg("LOGIN class " .. tostring(class))
  run(ns.hooks.login, "login")
  if ns.isWarlock then
    ns.say(string.format(L["%s loaded. /wpm for options, /wpm help for commands."], "v" .. ns.VERSION))
  else
    ns.say(L["This addon is made for warlocks and stays idle on this character."])
  end
end)

ns.inCombat = false
ns.on("PLAYER_REGEN_DISABLED", function() ns.inCombat = true end)
ns.on("PLAYER_REGEN_ENABLED", function()
  ns.inCombat = false
  ns.flushHeld()
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function help()
  ns.say(L["Commands:"])
  print("  /wpm  - " .. L["open or close the options"])
  print("  /wpm test  - " .. L["show both warnings for a few seconds"])
  print("  /wpm unlock | lock  - " .. L["move the warnings / fix them in place"])
  print("  /wpm status  - " .. L["pet, pet mode, talent and running brands"])
  print("  /wpm debug  - " .. L["debug lines in chat on/off"])
  print("  /wpm lang <auto|en|de>  - " .. L["interface language (then /reload)"])
  print("  /wpm reset  - " .. L["all settings back to default"])
end

SLASH_WARLOCKPETPROC1 = "/wpm"
SLASH_WARLOCKPETPROC2 = "/petproc"
SlashCmdList.WARLOCKPETPROC = function(msg)
  if not ns.db then return end
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" or cmd == "options" or cmd == "config" then
    if ns.Options then ns.Options.toggle() end
  elseif cmd == "help" then
    help()
  elseif cmd == "test" then
    ns.Alert.test()
  elseif cmd == "unlock" or cmd == "move" then
    ns.Alert.setLocked(false)
  elseif cmd == "lock" then
    ns.Alert.setLocked(true)
  elseif cmd == "status" then
    ns.Pet.status()
  elseif cmd == "debug" then
    ns.db.debugChat = not ns.db.debugChat
    ns.say(ns.db.debugChat and L["Debug lines in chat: on."] or L["Debug lines in chat: off."])
  elseif cmd == "lang" then
    local tag = ns.findLanguage(rest)
    if not tag then
      ns.say(L["Languages: auto, en, de"])
    else
      ns.db.lang = tag
      ns.say(L["Language saved. Type /reload to switch."])
    end
  elseif cmd == "reset" then
    ns.resetSettings()
    ns.Alert.applyPosition()
    ns.Alert.refresh()
    if ns.Options then ns.Options.refresh() end
    ns.say(L["All settings are back to default."])
  else
    help()
  end
end
