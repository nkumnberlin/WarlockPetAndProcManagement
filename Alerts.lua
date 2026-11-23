-- Warlock Pet & Proc Management: on-screen warnings and sounds.
--
-- One holder frame near the screen center carries one line per warning kind ("idle" = pet not attacking, "brand"),
-- stacked top to bottom in that order; only the active ones take space. Each line: optional icon +
-- the player's own message in their size and color, optionally pulsing. A sound plays when a warning
-- comes up and, if wanted, again every few seconds while it stays.
--
-- Position: own numbers (db.pos = { x, y } of the holder's top center in UIParent coordinates), moved
-- by following the cursor in move mode. Nothing here shows secret values.

local _, ns = ...
local L = ns.L
local A = {}
ns.Alert = A

A.KINDS = { "idle", "brand" } -- top to bottom
A.DEFAULT_TEXT = {
  idle = "Your pet is not attacking!",
  brand = "Pet attacks without %s!", -- %s = the talent's name from the game
}

-- Demonic Brand in the client's language (spell names come from the game)
function ns.brandName()
  local n = C_Spell and C_Spell.GetSpellName and ns.str(ns.plain(C_Spell.GetSpellName, 1293695))
  return n or "Demonic Brand"
end

function A.defaultText(kind)
  local t = L[A.DEFAULT_TEXT[kind]]
  if kind == "brand" then t = string.format(t, ns.brandName()) end
  return t
end

-- warning sounds, soft to loud: game sounds only, by SOUNDKIT name with the classic ID as fallback
A.SOUNDS = {
  { key = "click",   label = "Soft click",          kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856 },
  { key = "page",    label = "Page turn",           kit = "IG_QUEST_LIST_OPEN",             id = 875 },
  { key = "whisper", label = "Whisper",             kit = "TELL_MESSAGE",                   id = 3081 },
  { key = "ping",    label = "Map ping",            kit = "MAP_PING",                       id = 3175 },
  { key = "clock1",  label = "Alarm clock (soft)",  kit = "ALARM_CLOCK_WARNING_3",          id = 12889 },
  { key = "clock2",  label = "Alarm clock",         kit = "ALARM_CLOCK_WARNING_2",          id = 12867 },
  { key = "ready",   label = "Ready check",         kit = "READY_CHECK",                    id = 8960 },
  { key = "emote",   label = "Boss emote",          kit = "RAID_BOSS_EMOTE_WARNING",        id = 12197 },
  { key = "pvp",     label = "Battleground ready",  kit = "PVP_THROUGH_QUEUE",              id = 8458 },
  { key = "horn",    label = "Raid warning (horn)", kit = "RAID_WARNING",                   id = 8959 },
}
function A.soundIndex(key)
  for i, snd in ipairs(A.SOUNDS) do if snd.key == key then return i end end
  return #A.SOUNDS
end
function A.playSound(key)
  local snd = A.SOUNDS[A.soundIndex(key)]
  local id = (SOUNDKIT and SOUNDKIT[snd.kit]) or snd.id
  pcall(PlaySound, id, "Master")
end

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function iconFor(kind)
  if kind == "idle" then return PET_ATTACK_TEXTURE or "Interface\\Icons\\Ability_GhoulFrenzy" end
  local tex = C_Spell and C_Spell.GetSpellTexture and ns.plain(C_Spell.GetSpellTexture, 1293695)
  if not tex and C_Spell and C_Spell.GetSpellTexture then tex = ns.plain(C_Spell.GetSpellTexture, 5676) end
  return tex or "Interface\\Icons\\Spell_Fire_SoulBurn"
end

-- the message to show: the player's own text or the default; {pet} = the pet's name
function A.text(kind)
  local c = ns.db[kind]
  local t = (type(c.text) == "string" and c.text:match("%S")) and c.text or A.defaultText(kind)
  local pet = ns.str(ns.plain(UnitName, "pet")) or L["your pet"]
  return (t:gsub("{pet}", function() return pet end))
end

---------------------------------------------------------------------------
-- A warning line (used by the real holder and by the previews in the options)
---------------------------------------------------------------------------
function A.newLine(parent)
  local line = CreateFrame("Frame", nil, parent)
  line:SetSize(10, 10)
  line.fs = line:CreateFontString(nil, "OVERLAY")
  line.fs:SetPoint("CENTER", line, "CENTER", 0, 0)
  line.icon = line:CreateTexture(nil, "OVERLAY")
  line.icon:SetPoint("RIGHT", line.fs, "LEFT", -8, 0)
  line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  line.icon2 = line:CreateTexture(nil, "OVERLAY") -- the same icon right of the text, for balance
  line.icon2:SetPoint("LEFT", line.fs, "RIGHT", 8, 0)
  line.icon2:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  return line
end

-- returns the line's height (own number)
function A.paint(line, kind, scale)
  local c = ns.db[kind]
  local size = math.floor((c.size or 26) * (scale or 1) + 0.5)
  if not pcall(line.fs.SetFont, line.fs, FONT, size, "THICKOUTLINE") then
    pcall(line.fs.SetFont, line.fs, FONT, size, "OUTLINE")
  end
  local col = c.color or { 1, 1, 1 }
  line.fs:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1)
  line.fs:SetText(A.text(kind))
  local tex = iconFor(kind)
  local isz = math.floor(size * 1.15 + 0.5)
  for _, ic in ipairs({ line.icon, line.icon2 }) do
    ic:SetTexture(tex)
    ic:SetSize(isz, isz)
    ic:SetShown(c.icon ~= false)
  end
  local h = math.max(size, c.icon ~= false and isz or 0) + 8
  line:SetHeight(h)
  return h
end

function A.pulseAlpha(kind, t)
  if ns.db[kind].pulse == false then return 1 end
  return 0.6 + 0.4 * math.abs(math.sin(t * 3.2))
end

---------------------------------------------------------------------------
-- The holder on screen
---------------------------------------------------------------------------
local holder = CreateFrame("Frame", "WarlockPetProcAlertFrame", UIParent)
holder:SetSize(460, 40)
holder:SetFrameStrata("HIGH")
holder:SetClampedToScreen(true)
holder:EnableMouse(false)
holder:Hide()
A.holder = holder

A.lines = {}
for _, kind in ipairs(A.KINDS) do A.lines[kind] = A.newLine(holder) end

A.active = {}   -- kind -> { since, lastSound } while the condition holds
A.testUntil = {} -- kind -> time a test display ends

local function uiSize()
  local w, h = ns.plain(UIParent.GetWidth, UIParent), ns.plain(UIParent.GetHeight, UIParent)
  return (type(w) == "number" and w > 0) and w or 1920, (type(h) == "number" and h > 0) and h or 1080
end
local function validPos(p) return type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" end

function A.applyPosition()
  local db = ns.db
  if not validPos(db.pos) then
    local w, h = uiSize()
    db.pos = { w / 2, h * 0.72 }
  end
  holder:ClearAllPoints()
  holder:SetPoint("TOP", UIParent, "BOTTOMLEFT", db.pos[1], db.pos[2])
end

local function shouldShow(kind, t)
  if not ns.db then return false end
  if not ns.db.locked then return true end -- move mode: every warning as a sample
  if A.testUntil[kind] and A.testUntil[kind] > t then return true end
  return A.active[kind] ~= nil
end

-- stack the visible lines from the top (own height numbers)
function A.layout()
  if not ns.db then return end
  local t = ns.now()
  local y, any = 0, false
  for _, kind in ipairs(A.KINDS) do
    local line = A.lines[kind]
    if shouldShow(kind, t) then
      local h = A.paint(line, kind)
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
      line:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -y)
      line:Show()
      y = y + h + 4
      any = true
    else
      line:Hide()
    end
  end
  holder:SetHeight(math.max(y, 30))
  holder:SetShown(any)
end
A.refresh = A.layout

-- a warning starts (sound) or ends
function A.set(kind, on)
  local a = A.active[kind]
  if on and not a then
    local t = ns.now()
    A.active[kind] = { since = t, lastSound = t }
    if ns.db[kind].sound then A.playSound(ns.db[kind].soundKey) end
    ns.dbg("ALERT " .. kind .. " on")
    A.layout()
  elseif not on and a then
    A.active[kind] = nil
    ns.dbg(string.format("ALERT %s off after %.1fs", kind, ns.now() - a.since))
    A.layout()
  end
end

-- show warnings for 5 s (all enabled ones, or one kind); their sounds one after the other
function A.test(kind)
  local t = ns.now()
  local n = 0
  for _, k in ipairs(A.KINDS) do
    if (kind == nil and ns.db[k].on) or k == kind then
      A.testUntil[k] = t + 5
      if ns.db[k].sound then
        local key = ns.db[k].soundKey
        C_Timer.After(n * 0.7, function() A.playSound(key) end)
        n = n + 1
      end
    end
  end
  A.layout()
end

holder:SetScript("OnUpdate", function()
  local t = ns.now()
  local relayout = false
  for _, kind in ipairs(A.KINDS) do
    local line = A.lines[kind]
    if line:IsShown() then line:SetAlpha(A.pulseAlpha(kind, t)) end
    if A.testUntil[kind] and A.testUntil[kind] <= t then
      A.testUntil[kind] = nil
      relayout = true
    end
    local a = A.active[kind]
    local c = ns.db[kind]
    if a and c.sound and (c.repeatSec or 0) > 0 and t - a.lastSound >= c.repeatSec then
      a.lastSound = t
      A.playSound(c.soundKey)
    end
  end
  if relayout then A.layout() end
end)

---------------------------------------------------------------------------
-- Move mode: purple box, gold edge, a tab with "Move mode: drag me" and a Lock button
---------------------------------------------------------------------------
local moveBg = holder:CreateTexture(nil, "BACKGROUND")
moveBg:SetAllPoints()
moveBg:SetColorTexture(0.3, 0.1, 0.5, 0.45)
local edges = {}
for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, -1 },
                     { "TOPLEFT", "BOTTOMLEFT", -1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
  local e = holder:CreateTexture(nil, "BORDER")
  e:SetColorTexture(1, 0.82, 0, 0.9)
  e:SetPoint(p[1], holder, p[1], p[3], p[4])
  e:SetPoint(p[2], holder, p[2], p[3], p[4])
  if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
  edges[i] = e
end
local tab = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
tab:SetHeight(24)
tab:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 2)
tab:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, 2)
tab:EnableMouse(true)
if tab.SetBackdrop then
  tab:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  tab:SetBackdropColor(0.08, 0.06, 0.04, 0.95)
  tab:SetBackdropBorderColor(1, 0.82, 0)
end
local lockBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
lockBtn:SetSize(60, 18)
lockBtn:SetPoint("RIGHT", -4, 0)
lockBtn:SetScript("OnClick", function() A.setLocked(true) end)
local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tabText:SetPoint("LEFT", 8, 0)
tabText:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)
tabText:SetJustifyH("LEFT")
tabText:SetWordWrap(false)

local function moveParts(show)
  moveBg:SetShown(show)
  for _, e in ipairs(edges) do e:SetShown(show) end
  tab:SetShown(show)
  holder:EnableMouse(show)
end

local drag
holder:SetScript("OnMouseDown", function(self, button)
  if button ~= "LeftButton" or ns.db.locked then return end
  local cx, cy = GetCursorPosition()
  local eff = ns.plain(self.GetEffectiveScale, self) or 1
  drag = { cx = cx, cy = cy, x = ns.db.pos[1], y = ns.db.pos[2], eff = eff }
end)
holder:SetScript("OnMouseUp", function()
  if not drag then return end
  drag = nil
  local w, h = uiSize()
  ns.db.pos[1] = math.max(0, math.min(w, ns.db.pos[1]))
  ns.db.pos[2] = math.max(30, math.min(h, ns.db.pos[2]))
  A.applyPosition()
end)
holder:HookScript("OnUpdate", function()
  if not drag then return end
  local cx, cy = GetCursorPosition()
  ns.db.pos[1] = drag.x + (cx - drag.cx) / drag.eff
  ns.db.pos[2] = drag.y + (cy - drag.cy) / drag.eff
  A.applyPosition()
end)
tab:SetScript("OnMouseDown", function(_, button) holder:GetScript("OnMouseDown")(holder, button) end)
tab:SetScript("OnMouseUp", function() holder:GetScript("OnMouseUp")(holder) end)
local function moveTip()
  GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
  GameTooltip:AddLine(L["Move mode"])
  GameTooltip:AddLine(L["Drag the warnings where you want them, then click Lock. The purple box only shows in move mode."], 1, 1, 1, true)
  GameTooltip:Show()
end
tab:SetScript("OnEnter", moveTip)
tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
holder:SetScript("OnEnter", function() if not ns.db.locked then moveTip() end end)
holder:SetScript("OnLeave", function() GameTooltip:Hide() end)

function A.setLocked(v)
  ns.db.locked = v and true or false
  drag = nil
  moveParts(not ns.db.locked)
  A.layout()
  if ns.Options then ns.Options.refresh() end
  if ns.db.locked then
    ns.say(L["Warnings locked. Move them again: /wpm unlock or Options > General."])
  else
    ns.say(L["Move mode: drag the warnings, then click Lock."])
  end
end

table.insert(ns.hooks.ready, function()
  lockBtn:SetText(L["Lock"])
  tabText:SetText(L["Move mode: drag me"])
  A.applyPosition()
  moveParts(not ns.db.locked)
  A.layout()
end)
