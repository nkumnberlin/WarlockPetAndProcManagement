-- Warlock Pet & Proc Management: interface texts in other languages.
--
-- The addon writes its texts in English and looks each one up here: L["Lock"]. A text without a
-- translation stays English. Language files (Strings_deDE.lua, ...) fill ns.STRINGS[tag] with
-- { [English text] = translation }.
--
-- Which language: the option "Language" (db.lang), else the client's (GetLocale). The language is
-- fixed once the saved variables are loaded (ns.freezeLanguage, called on ADDON_LOADED) and only
-- changes with a /reload. Spell names never come from here: the game names them itself.

local _, ns = ...

ns.STRINGS = {}
ns.LANGUAGES = {
  { tag = "auto", label = "Automatic (client language)" },
  { tag = "enUS", label = "English" },
  { tag = "deDE", label = "Deutsch (German)" },
}

function ns.clientTag()
  local tag = GetLocale and GetLocale() or "enUS"
  if tag == "enGB" then tag = "enUS" end
  return tag
end

-- the language to use: the saved choice if there is one, else the client's
function ns.languageTag()
  local db = WarlockPetAndProcManagementDB
  local choice = type(db) == "table" and db.lang
  if type(choice) == "string" and choice ~= "auto" and (choice == "enUS" or ns.STRINGS[choice]) then
    return choice
  end
  return ns.clientTag()
end

local ALIASES = { auto = "auto", en = "enUS", enus = "enUS", engb = "enUS", english = "enUS",
  de = "deDE", dede = "deDE", deutsch = "deDE", german = "deDE" }
function ns.findLanguage(word)
  word = type(word) == "string" and word:lower():gsub("[%-_ ]", "") or ""
  return ALIASES[word]
end

local active, dict -- nil until ns.freezeLanguage()
function ns.freezeLanguage()
  active = ns.languageTag()
  dict = ns.STRINGS[active]
  ns.active = active
  return active
end

ns.L = setmetatable({}, {
  __index = function(cache, key)
    if key == nil then return "" end
    local d = dict
    if not active then d = ns.STRINGS[ns.languageTag()] end
    local text = d and d[key]
    if text == nil or text == "" then text = key end
    if active and type(key) == "string" then rawset(cache, key, text) end -- fixed language: remember
    return text
  end,
})
