-- Warlock Pet & Proc Management: on-screen warnings and sounds.
--
-- One holder frame near the screen center carries one line per warning kind ("idle" = pet not attacking, "brand",
-- "deci" = Decimation proc, "hp"),
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

-- top to bottom; "hp" last: while pet health is hidden its line keeps its place even when the game
-- hides it (see the gate below), so it must not push the others down
A.KINDS = { "idle", "brand", "deci", "hp" }
A.DEFAULT_TEXT = {
  idle = "Your pet is not attacking!",
  brand = "Pet attacks without %s!", -- %s = the talent's name from the game
  hp = "{pet} is low on health!",
  deci = "%s: %s now!", -- 0.3.0: Decimation, Soul Fire (names from the game)
}

-- Demonic Brand in the client's language (spell names come from the game)
function ns.brandName()
  local n = C_Spell and C_Spell.GetSpellName and ns.str(ns.plain(C_Spell.GetSpellName, 1293695))
  return n or "Demonic Brand"
end

function A.defaultText(kind)
  local t = L[A.DEFAULT_TEXT[kind]]
  if kind == "brand" then t = string.format(t, ns.brandName()) end
  if kind == "deci" then t = string.format(t, ns.deciName(), ns.soulFireName()) end
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
  if kind == "hp" then -- Health Funnel: the fix for a hurt demon
    local t = C_Spell and C_Spell.GetSpellTexture and ns.plain(C_Spell.GetSpellTexture, 755)
    return t or "Interface\\Icons\\Spell_Shadow_LifeDrain"
  end
  if kind == "deci" then -- Soul Fire: what to cast now
    local t = C_Spell and C_Spell.GetSpellTexture and ns.plain(C_Spell.GetSpellTexture, 6353)
    return t or "Interface\\Icons\\Spell_Fire_Fireball02"
  end
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
local LINE_W = 460       -- the holder's (and every line's) width
local CLIP_MARGIN = 500  -- room around a clipped line for long text and big icons
local CLIP_MARGIN_V = 60

-- clipped = true (0.2.0): text and icons are created inside a clip frame, so a gate can hide them.
-- They are made there in place, never moved into it later (ForeverAuras: frames tied to an aura
-- container must not be re-parented). Until a gate anchors it, the clip is open around the line.
function A.newLine(parent, clipped)
  local line = CreateFrame("Frame", nil, parent)
  line:SetSize(10, 10)
  local host = line
  if clipped and line.SetClipsChildren then
    local ok, clip = pcall(CreateFrame, "Frame", nil, line, "DisableUntrustedLayoutScriptsTemplate")
    if not ok or not clip then clip = CreateFrame("Frame", nil, line) end
    clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT", line, "TOPLEFT", -CLIP_MARGIN, CLIP_MARGIN_V)
    clip:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", CLIP_MARGIN, -CLIP_MARGIN_V)
    line.clip, host = clip, clip
  end
  line.fs = host:CreateFontString(nil, "OVERLAY")
  line.fs:SetPoint("CENTER", line, "CENTER", 0, 0)
  line.icon = host:CreateTexture(nil, "OVERLAY")
  line.icon:SetPoint("RIGHT", line.fs, "LEFT", -8, 0)
  line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  line.icon2 = host:CreateTexture(nil, "OVERLAY") -- the same icon right of the text, for balance
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
holder:SetSize(LINE_W, 40)
holder:SetFrameStrata("HIGH")
holder:SetClampedToScreen(true)
holder:EnableMouse(false)
holder:Hide()
A.holder = holder

A.GATED = { brand = true, hp = true } -- lines whose visibility the game can decide
A.lines = {}
for _, kind in ipairs(A.KINDS) do A.lines[kind] = A.newLine(holder, A.GATED[kind]) end

---------------------------------------------------------------------------
-- Gate for the low-health line (0.1.2). When the pet's health is a secret value in a fight, the addon
-- can't compare it; the game has to. Same idea as DotWatch's kill skull (DoesItDie / Smooth Animated
-- Bars, MIT): an invisible StatusBar GATE_W pixels wide gets range = max health and value = health (both
-- secret, the bar accepts them). Its empty part starts at GATE_W * health% from the bar's left edge.
-- The line's text and icons sit in a clip frame that covers only that empty part, and the bar is placed
-- so that the threshold falls 600 px left of the line: health% <= threshold -> the empty part covers
-- the line (visible); health% above it -> the empty part starts far to the right (clipped away).
-- Nothing is read back. "Open" = range 1, tiny value: always visible (tests, readable health).
---------------------------------------------------------------------------
local GATE_W = 200000 -- px for 100 %: 1 % = 2000 px, more than any line is wide
local function makeGate(line)
  if not line.clip then A.gateErr = "no clip frames" return end
  local ok, err = pcall(function()
    local bar = CreateFrame("StatusBar", nil, line)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fill = bar:GetStatusBarTexture()
    fill:SetVertexColor(0, 0, 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.000001)
    bar:SetSize(GATE_W, 10)
    local clip = line.clip
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    line.gate = { bar = bar, clip = clip }
  end)
  if not ok then A.gateErr = tostring(err) end -- logged once the saved variables are loaded
end
makeGate(A.lines.hp)

---------------------------------------------------------------------------
-- Engine gate for the Demonic Brand line (0.2.0). In raids and dungeons the game hides which enemy the
-- pet attacks, but Blizzard's own aura engine (CustomAuraContainerTemplate, Blizzard_AuraContainer) can
-- still read the pet's target's auras and lay them out; the addon never sees them. The trick comes from
-- ForeverAuras' "Aura(s) Missing" (SecretAuraSingle.lua, GPL; only the idea is used here): an invisible
-- aura group bound to "pettarget", filtered to our own Demonic Brand debuff, gives its container a width
-- only while the brand is there. The line's clip starts at the container's right edge and ends at the
-- line's right edge (+ margin): no brand -> container ~1 px wide -> the clip covers the line (visible);
-- brand -> container exactly as wide as the clip -> the clip has no width (hidden).
-- The game decides; nothing is read back, so the addon doesn't know whether the line shows.
---------------------------------------------------------------------------
A.BRAND_GROUP = "WPPMBrand"
A.BRAND_DEBUFF_IDS = { 1293696 } -- Wowhead: the 10 s Demonic Brand aura (talent 1293695)

function A.brandDebuffIDs()
  local ids = {}
  local own = ns.db and tonumber(ns.db.brand.debuffID)
  for _, id in ipairs(own and { own } or A.BRAND_DEBUFF_IDS) do ids[id] = true end
  return ids
end

local function makeEngineGate(line)
  if not line.clip then return "no clip frames" end
  if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return "no C_XMLUtil" end
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
    pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
  end
  if not C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") then return "no CustomAuraContainerTemplate" end
  local ok, err = pcall(function()
    local okC, c = pcall(CreateFrame, "AuraContainer", nil, line, "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    if not okC or not c then c = CreateFrame("AuraContainer", nil, line, "CustomAuraContainerTemplate") end
    c:SetEnabled(false)
    if c.SetAuraProcessingPolicy and CustomAuraContainerAuraProcessingPolicy then
      c:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
    end
    c:SetPoint("TOPLEFT", line, "TOPLEFT", -CLIP_MARGIN, 0)
    local w = LINE_W + 1 + 2 * CLIP_MARGIN
    c:AddAuraGroup(A.BRAND_GROUP, "HARMFUL|PLAYER", {
      candidateFilters = { includeSpellIDs = A.brandDebuffIDs() },
      maxFrameCount = 1,
      layout = { elementWidth = w, elementHeight = 10 },
      initializeFrame = function(button) -- draws nothing; only the container's width is used
        button:SetSize(w, 10)
        button:SetAlpha(0)
        button:EnableMouse(false)
      end,
    })
    local clip = line.clip
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", c, "TOPRIGHT", -1, CLIP_MARGIN_V)
    clip:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", CLIP_MARGIN, -CLIP_MARGIN_V)
    c:SetUnit("pettarget")
    c:SetEnabled(true)
    line.engine = { container = c, groupOn = true }
  end)
  if not ok then return tostring(err) end
end

-- called at login (the saved variables are there for a custom debuff ID)
function A.setupEngine()
  local line = A.lines.brand
  if line.engine or A.engineErr then return end
  A.engineErr = makeEngineGate(line)
  ns.dbg("ENGINE brand gate " .. (line.engine and "ready (pettarget)" or ("not available: " .. tostring(A.engineErr))))
end
function A.engineReady() return A.lines.brand.engine ~= nil end
-- the engine reads the pet's target again (pet target changed, auras changed)
function A.engineRefresh()
  local e = A.lines.brand.engine
  if e and e.groupOn then pcall(e.container.UpdateAllAuras, e.container) end
end
-- open = the group off: nothing found, the line always visible (tests, move mode, engine switched off)
function A.engineOpen(open)
  local e = A.lines.brand.engine
  if not e or e.groupOn == not open then return end
  if pcall(e.container.SetAuraGroupEnabled, e.container, A.BRAND_GROUP, not open) then
    e.groupOn = not open
    if e.groupOn then A.engineRefresh() end
  end
end
-- a new debuff ID (/wpm brandid)
function A.engineFilters()
  local e = A.lines.brand.engine
  if not e then return false end
  local ok = pcall(e.container.SetAuraGroupCandidateFilters, e.container, A.BRAND_GROUP, { includeSpellIDs = A.brandDebuffIDs() })
  A.engineRefresh()
  return ok
end
-- diagnostics: is the container's width readable? (if it were, the addon could know the brand)
function A.engineWidth()
  local e = A.lines.brand.engine
  if not e then return "none" end
  local ok, w = pcall(e.container.GetWidth, e.container)
  if not ok then return "err" end
  if ns.issecret(w) then return "secret" end
  return tostring(w)
end

local function placeGate(line, kind, h)
  local g = line.gate
  if not g then return end
  local th = (ns.db[kind].threshold or 30) / 100
  g.bar:ClearAllPoints()
  g.bar:SetPoint("TOPLEFT", line, "TOPLEFT", -600 - GATE_W * th, 0)
  g.bar:SetHeight(h)
end
function A.gateOpen(kind)
  local g = A.lines[kind].gate
  if g and not g.open then
    g.bar:SetMinMaxValues(0, 1)
    g.bar:SetValue(0.000001)
    g.open = true
  end
end
-- cur/max may be secret: only handed to the bar. Returns false when there is no gate (warning can't show).
function A.gateFeed(kind, cur, max)
  local g = A.lines[kind].gate
  if not g then return false end
  if not ns.db.locked or (A.testUntil[kind] and A.testUntil[kind] > ns.now()) then
    A.gateOpen(kind) -- a test or move mode shows the line
    return true
  end
  local ok = pcall(g.bar.SetMinMaxValues, g.bar, 0, max)
  ok = ok and pcall(g.bar.SetValue, g.bar, cur)
  g.open = nil
  return ok
end

A.active = {}   -- kind -> { since, lastSound, quiet } while the condition holds
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
      placeGate(line, kind, h)
      local sample = not ns.db.locked or (A.testUntil[kind] and A.testUntil[kind] > t)
      if sample then A.gateOpen(kind) end
      if kind == "brand" then A.engineOpen(sample or ns.db.brand.engine == false) end
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

-- a warning starts (sound) or ends. quiet = the game decides whether it is visible (hidden pet health):
-- the addon doesn't know when it shows, so no sound
function A.set(kind, on, quiet)
  local a = A.active[kind]
  if on and a and (a.quiet or false) ~= (quiet or false) then
    a.quiet = quiet
    ns.dbg("ALERT " .. kind .. (quiet and " now decided by the game" or " now decided by the addon"))
    -- 0.2.0: became certain while up -> its sound now
    if not quiet and ns.db[kind].sound then
      A.playSound(ns.db[kind].soundKey)
      a.lastSound = ns.now()
    end
  end
  if on and not a then
    local t = ns.now()
    A.active[kind] = { since = t, lastSound = t, quiet = quiet }
    if ns.db[kind].sound and not quiet then A.playSound(ns.db[kind].soundKey) end
    ns.dbg("ALERT " .. kind .. " on" .. (quiet and " (game decides, no sound)" or ""))
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
    if a and not a.quiet and c.sound and (c.repeatSec or 0) > 0 and t - a.lastSound >= c.repeatSec then
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
  if A.gateErr then ns.dbg("GATE not available: " .. A.gateErr) end
  tabText:SetText(L["Move mode: drag me"])
  A.applyPosition()
  moveParts(not ns.db.locked)
  A.layout()
end)
table.insert(ns.hooks.login, function()
  if ns.isWarlock then
    A.setupEngine()
    A.layout()
  end
end)
