-- Warlock Pet & Proc Management: options window, AddOns settings entry and minimap button.
--
-- Classic Blizzard dialog look like DotWatch: dark marble on a solid base, gold border, gold titles,
-- red buttons, navigation list on the left (700 x 520). Every warning page has a live preview.
-- Escape is handled by the window itself (no UISpecialFrames, no StaticPopup: they taint).

local _, ns = ...
local L = ns.L
local O = {}
ns.Options = O

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local controls = {}
local previews = {}
local opt -- the window, built on first use

local function changed()
  ns.Alert.refresh()
  for _, pv in ipairs(previews) do pv.redraw() end
end

---------------------------------------------------------------------------
-- Widgets (same look and behavior as in DotWatch)
---------------------------------------------------------------------------
local function tryTemplate(kind, parent, template)
  local ok, f = pcall(CreateFrame, kind, nil, parent, template)
  if ok and f then return f, true end
  return CreateFrame(kind, nil, parent), false
end

-- title/text in English (translated here); raw = true: already translated
local function tip(widget, title, text, raw)
  if not raw then title, text = L[title], text and L[text] end
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function makeButton(parent, label, width, onClick)
  local b, templated = tryTemplate("Button", parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  if not templated then
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
      t:SetTexCoord(0, 0.625, 0, 0.6875)
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
  end
  b:SetText(L[label])
  b:SetScript("OnClick", onClick)
  return b
end

local function makeCheck(parent, label, help, get, set)
  label, help = L[label], help and L[help]
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(26, 26)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  cb.text:SetText(label)
  cb:SetHitRectInsets(0, -(cb.text:GetStringWidth() + 6), 0, 0)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    changed()
  end)
  tip(cb, label, help, true)
  cb.refresh = function() cb:SetChecked(get() and true or false) end
  controls[#controls + 1] = cb
  return cb
end

local function makeSlider(parent, label, minV, maxV, step, fmt, get, set, width)
  label = L[label]
  local show = type(fmt) == "function" and fmt or function(v) return string.format(L[fmt], v) end
  local s = CreateFrame("Slider", nil, parent, BACKDROP_TEMPLATE)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(width or 200, 17)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  pcall(s.SetObeyStepOnDrag, s, true)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  if s.SetBackdrop then
    s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 } })
  end
  s.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
  s.title:SetText(label)
  s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s.value:SetPoint("LEFT", s, "RIGHT", 8, 0)
  local busy = false
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / step + 0.5) * step
    self.value:SetText(show(v))
    if not busy then set(v) changed() end
  end)
  s.refresh = function()
    busy = true
    s:SetValue(get())
    s.value:SetText(show(get()))
    busy = false
  end
  controls[#controls + 1] = s
  return s
end

-- section heading with a thin gold line; x/lineEnd let a page have two columns
local function makeSection(parent, label, y, x, lineEnd)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 24, y)
  fs:SetText(L[label])
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 0.82, 0, 0.25)
  line:SetHeight(1)
  line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  if lineEnd then
    line:SetPoint("RIGHT", parent, "LEFT", lineEnd, 0)
  else
    line:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
  end
  return fs
end

local function smallText(parent, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT")
  return fs
end

-- the game's color picker (old and new API)
local function pickColor(r, g, b, onChange)
  local cpf = ColorPickerFrame
  if not cpf then return end
  local function cur() return cpf:GetColorRGB() end
  if cpf.SetupColorPickerAndShow then
    cpf:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = function() onChange(cur()) end, cancelFunc = function() onChange(r, g, b) end })
  else
    cpf.hasOpacity = false
    cpf.previousValues = { r, g, b }
    cpf.func = function() onChange(cur()) end
    cpf.cancelFunc = function() onChange(r, g, b) end
    cpf:SetColorRGB(r, g, b)
    cpf:Hide()
    cpf:Show()
  end
  pcall(cpf.SetFrameStrata, cpf, "FULLSCREEN_DIALOG")
end

local function makeSwatch(parent, label, get, set)
  local b = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
  b:SetSize(22, 22)
  if b.SetBackdrop then
    b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b:SetBackdropBorderColor(0.8, 0.7, 0.4)
  end
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetPoint("TOPLEFT", 3, -3)
  b.tex:SetPoint("BOTTOMRIGHT", -3, 3)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.text:SetPoint("LEFT", b, "RIGHT", 6, 0)
  b.text:SetText(L[label])
  b:SetScript("OnClick", function()
    local c = get()
    pickColor(c[1], c[2], c[3], function(r, g, bb)
      set({ r, g, bb })
      b.refresh()
      changed()
    end)
  end)
  tip(b, label, "Click to choose the text color.")
  b.refresh = function()
    local c = get()
    b.tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1)
  end
  controls[#controls + 1] = b
  return b
end

-- the warning message: an edit box, saved on Enter or when it loses focus; empty = default text
local function makeTextBox(parent, kind, width)
  local e, templated = tryTemplate("EditBox", parent, "InputBoxTemplate")
  e:SetSize(width, 22)
  e:SetAutoFocus(false)
  e:SetMaxLetters(80)
  if not templated then
    e:SetFontObject(ChatFontNormal)
    local bg = e:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
  end
  local function save()
    local v = e:GetText() or ""
    if not v:match("%S") or v == ns.Alert.defaultText(kind) then v = nil end
    ns.db[kind].text = v
    changed()
  end
  e:SetScript("OnEnterPressed", function(self) save() self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", save)
  e:SetScript("OnEscapePressed", function(self) self.refresh() self:ClearFocus() end)
  e:SetScript("OnTextChanged", function(self, user)
    if user and previews[kind] then previews[kind].redraw(self:GetText()) end
  end)
  e.refresh = function()
    local t = ns.db[kind].text
    e:SetText((type(t) == "string" and t ~= "") and t or ns.Alert.defaultText(kind))
    e:SetCursorPosition(0)
  end
  controls[#controls + 1] = e
  return e
end

-- sound choice: < name > and a test button, soft to loud
local function makeSoundPicker(parent, kind, x, y)
  local name = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local A = ns.Alert
  local function show()
    name:SetText(L[A.SOUNDS[A.soundIndex(ns.db[kind].soundKey)].label])
  end
  local function step(dir)
    local i = A.soundIndex(ns.db[kind].soundKey) + dir
    if i < 1 then i = #A.SOUNDS elseif i > #A.SOUNDS then i = 1 end
    ns.db[kind].soundKey = A.SOUNDS[i].key
    show()
    A.playSound(ns.db[kind].soundKey)
  end
  local prevB = makeButton(parent, "<", 26, function() step(-1) end)
  prevB:SetPoint("TOPLEFT", x, y)
  name:SetPoint("LEFT", prevB, "RIGHT", 4, 0)
  name:SetWidth(112) -- the right column ends at the window edge: < name > Test fits in 200 px
  name:SetJustifyH("CENTER")
  name:SetWordWrap(false)
  local nextB = makeButton(parent, ">", 26, function() step(1) end)
  nextB:SetPoint("LEFT", prevB, "RIGHT", 120, 0)
  local testB = makeButton(parent, "Test", 52, function() A.playSound(ns.db[kind].soundKey) end)
  testB:SetPoint("LEFT", nextB, "RIGHT", 6, 0)
  tip(testB, "Test", "Plays the chosen sound.")
  controls[#controls + 1] = { refresh = show }
end

-- live preview of one warning
local function makePreview(parent, kind, top)
  local box = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
  box:SetPoint("TOPLEFT", 24, top)
  box:SetPoint("BOTTOMRIGHT", -22, 6)
  if box.SetBackdrop then
    box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    box:SetBackdropColor(0.08, 0.06, 0.04, 0.9)
    box:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
  end
  local label = smallText(box, "GameFontDisableSmall")
  label:SetPoint("TOPLEFT", 10, -8)
  label:SetText(L["Preview"])
  local line = ns.Alert.newLine(box)
  line:SetPoint("LEFT", box, "LEFT", 8, -10)
  line:SetPoint("RIGHT", box, "RIGHT", -8, -10)
  -- the page's buttons sit in the preview's top right corner
  local show = makeButton(box, "Show on screen", 130, function() ns.Alert.test(kind) end)
  show:SetPoint("TOPRIGHT", -8, -8)
  tip(show, "Show on screen", "Shows this warning for 5 seconds where it will appear, with its sound.")
  local reset = makeButton(box, "Reset page", 100, function()
    ns.resetSettings(kind)
    O.refresh()
  end)
  reset:SetPoint("RIGHT", show, "LEFT", -6, 0)
  tip(reset, "Reset page", "All settings on this page back to default.")
  local pv = {}
  -- typing = the edit box's text while typing (not saved yet)
  pv.redraw = function(typing)
    local c = ns.db[kind]
    local saved = c.text
    if typing then c.text = typing end
    ns.Alert.paint(line, kind)
    -- big text shrinks to fit the box (our own text, never secret: its width may be read)
    local avail = (ns.plain(box.GetWidth, box) or 480) - 24
    local tw = ns.plain(line.fs.GetStringWidth, line.fs)
    if type(tw) == "number" and tw > 0 then
      local need = tw + (c.icon ~= false and 2 * ((c.size or 26) * 1.15 + 8) or 0)
      if need > avail then ns.Alert.paint(line, kind, avail / need) end
    end
    c.text = saved
    line:SetAlpha(c.on and 1 or 0.35)
  end
  box:SetScript("OnUpdate", function()
    if ns.db[kind].on then line:SetAlpha(ns.Alert.pulseAlpha(kind, GetTime())) end
  end)
  box:SetScript("OnShow", function() pv.redraw() end)
  previews[#previews + 1] = pv
  previews[kind] = pv
  return box
end

---------------------------------------------------------------------------
-- A warning page (pet not attacking, Demonic Brand)
---------------------------------------------------------------------------
local COL2 = 310 -- right column starts here

local function buildAlertPage(pg, kind, title, enableLabel, enableHelp)
  local c = function() return ns.db[kind] end
  makeSection(pg, title, -54)
  makeCheck(pg, enableLabel, enableHelp, function() return c().on end, function(v)
    c().on = v
    if ns.Pet then ns.Pet.update() end
  end):SetPoint("TOPLEFT", 26, -74)

  -- left column: message and look
  makeSection(pg, "Message", -110, 24, COL2 - 14)
  makeTextBox(pg, kind, 250):SetPoint("TOPLEFT", 32, -130)
  local def = makeButton(pg, "Default text", 110, function()
    ns.db[kind].text = nil
    O.refresh()
  end)
  def:SetPoint("TOPLEFT", 26, -156)
  local hint = smallText(pg, "GameFontDisableSmall")
  hint:SetPoint("LEFT", def, "RIGHT", 8, 0)
  hint:SetText(L["{pet} = your pet's name"])
  makeSlider(pg, "Text size", 14, 48, 1, "%d", function() return c().size end,
    function(v) c().size = v end, 200):SetPoint("TOPLEFT", 30, -204)
  makeSwatch(pg, "Text color", function() return c().color end, function(v) c().color = v end)
    :SetPoint("TOPLEFT", 30, -238)
  makeCheck(pg, "Icon", "The spell icon on both sides of the message.", function() return c().icon end,
    function(v) c().icon = v end):SetPoint("TOPLEFT", 160, -236)
  makeCheck(pg, "Pulse", "The message softly blinks while it is up.", function() return c().pulse end,
    function(v) c().pulse = v end):SetPoint("TOPLEFT", 26, -264)

  -- right column: sound
  makeSection(pg, "Sound", -110, COL2)
  makeCheck(pg, "Play a sound", "Once when the warning comes up.", function() return c().sound end,
    function(v) c().sound = v end):SetPoint("TOPLEFT", COL2 + 2, -128)
  makeSoundPicker(pg, kind, COL2 + 6, -160)
  makeSlider(pg, "Repeat the sound", 0, 10, 1, function(v)
    return v == 0 and L["never"] or string.format(L["every %d s"], v)
  end, function() return c().repeatSec end, function(v) c().repeatSec = v end, 150):SetPoint("TOPLEFT", COL2 + 6, -208)
end

-- right column below the sound: how long the problem must last before the warning comes up
local function makeDelay(pg, kind, maxV, help)
  makeSection(pg, "Timing", -244, COL2)
  local s = makeSlider(pg, "Wait before warning", 0, maxV, 0.5, function(v)
    return string.format(L["%.1f s"], v)
  end, function() return ns.db[kind].delay end, function(v) ns.db[kind].delay = v end, 150)
  s:SetPoint("TOPLEFT", COL2 + 6, -282)
  tip(s, "Wait before warning", help)
end

local function buildIdlePage(pg)
  buildAlertPage(pg, "idle", "Pet not attacking", "Warn when my pet doesn't attack in a fight",
    "In a fight, when your pet is alive but not attacking (its Attack isn't on, e.g. on Passive before you send it in, or after its target died), this warning comes up. It goes away when the pet attacks, is gone or the fight ends. Works in every pet mode.")
  makeDelay(pg, "idle", 5, "Time to send your pet in: the warning only comes up when the pet hasn't attacked for this long in a fight.")
  makePreview(pg, "idle", -336)
end

local function buildBrandPage(pg)
  buildAlertPage(pg, "brand", ns.brandName(), "Warn when my pet attacks an enemy without the brand",
    "Demonology talent: your Searing Pain brands the enemy for 10 sec and your pet's next attacks on it deal extra damage. The warning comes up while your pet attacks an enemy that has no brand from you (never branded, or the 10 sec ran out). It goes away when your Searing Pain lands on that enemy.")
  makeDelay(pg, "brand", 3, "The warning only comes up when your pet has attacked an enemy without the brand for this long.")
  local cb = makeCheck(pg, "Count the pet's attacks (experimental)", "The brand also ends when your pet has used its 6 empowered attacks, not only after 10 sec. The game doesn't say which attack used a charge, so this is a guess (a fire/shadow hit and a debuff change on that enemy at the same moment) and can be off, e.g. with your own DoTs on it.",
    function() return ns.db.brand.charges end, function(v) ns.db.brand.charges = v end)
  cb:SetPoint("TOPLEFT", 26, -290)
  O.talentLine = smallText(pg)
  O.talentLine:SetPoint("TOPLEFT", 54, -98)
  makePreview(pg, "brand", -336)
end

-- 0.1.2: low pet health with its threshold slider
local function buildHPPage(pg)
  buildAlertPage(pg, "hp", "Low pet health", "Warn when my pet's health is low",
    "The warning comes up while your pet's health is at or below the value you set, and goes away when it is healed (3 % above the value) or the pet is gone. If the game hides the pet's health in a fight, the game itself decides when the warning shows; then it comes without a sound.")
  makeSection(pg, "Health", -244, COL2)
  local s = makeSlider(pg, "Warn at or below", 5, 80, 5, function(v) return string.format("%d %%", v) end,
    function() return ns.db.hp.threshold end, function(v) ns.db.hp.threshold = v end, 150)
  s:SetPoint("TOPLEFT", COL2 + 6, -282)
  tip(s, "Warn at or below", "Pet health in percent of its maximum.")
  makeCheck(pg, "Also out of combat", "Also warn outside of fights, e.g. before the next pull.",
    function() return ns.db.hp.ooc end, function(v) ns.db.hp.ooc = v if ns.Pet then ns.Pet.update() end end)
    :SetPoint("TOPLEFT", 26, -290)
  O.hpLine = smallText(pg)
  O.hpLine:SetPoint("TOPLEFT", 54, -98)
  makePreview(pg, "hp", -336)
  local acc = 0
  pg:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc > 0.5 then acc = 0 O.refreshStatus() end
  end)
end

---------------------------------------------------------------------------
-- General page
---------------------------------------------------------------------------
local function buildGeneralPage(pg)
  local y = -54
  makeSection(pg, "Warnings on screen", y)
  y = y - 22
  makeCheck(pg, "Move mode", "Shows every warning as a sample with a purple box: drag it where you want it, then click Lock.",
    function() return not ns.db.locked end, function(v) ns.Alert.setLocked(not v) end):SetPoint("TOPLEFT", 26, y)
  local bReset = makeButton(pg, "Reset position", 120, function()
    ns.db.pos = nil
    ns.Alert.applyPosition()
  end)
  bReset:SetPoint("TOPLEFT", 250, y - 2)
  y = y - 40

  makeSection(pg, "Interface", y)
  y = y - 22
  makeCheck(pg, "Minimap button", "Show the button at the minimap. /wpm opens this window either way.",
    function() return not ns.db.minimap.hide end, function(v)
      ns.db.minimap.hide = not v
      O.updateMinimapButton()
    end):SetPoint("TOPLEFT", 26, y)
  makeCheck(pg, "Debug lines in chat", "For troubleshooting. The debug log is saved either way (SavedVariables).",
    function() return ns.db.debugChat end, function(v) ns.db.debugChat = v end):SetPoint("TOPLEFT", 250, y)
  y = y - 32
  local langLabel = smallText(pg, "GameFontNormalSmall")
  langLabel:SetPoint("TOPLEFT", 30, y - 6)
  langLabel:SetText(L["Language:"])
  local langs = ns.LANGUAGES
  local function langIndex()
    for i, l in ipairs(langs) do if l.tag == (ns.db.lang or "auto") then return i end end
    return 1
  end
  local langBtn
  langBtn = makeButton(pg, langs[langIndex()].label, 200, function()
    ns.db.lang = langs[langIndex() % #langs + 1].tag
    langBtn:SetText(L[langs[langIndex()].label])
    ns.say(L["Language saved. Type /reload to switch."])
  end)
  langBtn:SetPoint("LEFT", langLabel, "RIGHT", 8, 0)
  tip(langBtn, "Language", "Language of this addon's own texts. Click for the next language, then /reload.")
  controls[#controls + 1] = { refresh = function() langBtn:SetText(L[langs[langIndex()].label]) end }
  y = y - 40

  makeSection(pg, "Status", y)
  y = y - 22
  local status = smallText(pg)
  status:SetPoint("TOPLEFT", 30, y)
  status:SetPoint("RIGHT", pg, "RIGHT", -28, 0)
  status:SetSpacing(4)
  O.status = status
  y = y - 80

  makeSection(pg, "Coming later", y)
  y = y - 22
  local later = smallText(pg, "GameFontDisableSmall")
  later:SetPoint("TOPLEFT", 30, y)
  later:SetPoint("RIGHT", pg, "RIGHT", -28, 0)
  later:SetText(L["Proc management (alerts for your warlock procs) comes in a later version."])

  -- status refresh while the page is open
  local acc = 0
  pg:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc > 0.5 then acc = 0 O.refreshStatus() end
  end)
end

function O.refreshStatus()
  local P = ns.Pet
  if O.status and P then
    local yes, no = "|cff55ff55", "|cffff5555"
    local pet = P.hasPet() and (ns.str(ns.plain(UnitName, "pet")) or "?") or nil
    local lines = {
      L["Class"] .. ": " .. (ns.isWarlock and (yes .. L["Warlock"] .. "|r") or (no .. L["not a warlock (addon idle)"] .. "|r")),
      L["Pet"] .. ": " .. (pet and (yes .. pet .. "|r") or (no .. L["none"] .. "|r")) ..
        (pet and ("   " .. L["Mode"] .. ": " .. (P.modeName() or "?") .. "   " .. L["Attacking"] .. ": " ..
          ((P.attackState(GetTime())) and (yes .. L["yes"] .. "|r") or (no .. L["no"] .. "|r")) ..
          "   " .. L["Health"] .. ": " .. P.hpText()) or ""),
      string.format(L["%s talent"], ns.brandName()) .. ": " .. (P.brand.talent() and (yes .. L["learned"] .. "|r") or (no .. L["not learned (no brand warning)"] .. "|r")),
    }
    O.status:SetText(table.concat(lines, "\n"))
  end
  if O.talentLine and P then
    O.talentLine:SetText(P.brand.talent() and ("|cff55ff55" .. L["Talent learned."] .. "|r")
      or ("|cffff5555" .. L["Talent not learned: this warning stays off."] .. "|r"))
  end
  if O.hpLine and P then
    local txt = P.hpText()
    if txt == L["hidden by the game"] then
      O.hpLine:SetText("|cffffd100" .. L["Pet health is hidden by the game now: warning without sound."] .. "|r")
    elseif txt == "-" then
      O.hpLine:SetText("|cff888888" .. L["No pet out."] .. "|r")
    else
      O.hpLine:SetText(string.format(L["Pet health now: %s"], txt))
    end
  end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local NAV_W = 160

local function buildOptions()
  local f = CreateFrame("Frame", "WarlockPetProcOptions", UIParent, BACKDROP_TEMPLATE)
  f:SetSize(700, 520)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  -- the dark marble is see-through on its own: a solid base goes under it
  local base = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  base:SetColorTexture(0.04, 0.03, 0.02, 1)
  base:SetPoint("TOPLEFT", 11, -12)
  base:SetPoint("BOTTOMRIGHT", -12, 11)
  local marble = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  marble:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
  pcall(marble.SetHorizTile, marble, true)
  pcall(marble.SetVertTile, marble, true)
  marble:SetPoint("TOPLEFT", 11, -12)
  marble:SetPoint("BOTTOMRIGHT", -12, 11)
  if f.SetBackdrop then
    f:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  end
  -- Escape closes it; in combat every key goes through (SetPropagateKeyboardInput is blocked there)
  f:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      self:Hide()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
      self:EnableKeyboard(false)
    elseif self:IsShown() then
      self:EnableKeyboard(true)
      self:SetPropagateKeyboardInput(true)
    end
  end)

  local header = f:CreateTexture(nil, "ARTWORK")
  header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
  header:SetSize(340, 64)
  header:SetPoint("TOP", 0, 12)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", header, "TOP", 0, -14)
  title:SetText(ns.TITLE)

  local close, templated = tryTemplate("Button", f, "UIPanelCloseButton")
  if not templated then
    close:SetSize(32, 32)
    close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
  end
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() f:Hide() end)

  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOP", 0, -30)
  sub:SetText(L["Pet and proc warnings for warlocks."] .. "  |cff888888v" .. ns.VERSION .. "|r")

  local pages = {}
  for i = 1, 4 do
    local pg = CreateFrame("Frame", nil, f)
    pg:SetPoint("TOPLEFT", NAV_W, 0)
    pg:SetPoint("BOTTOMRIGHT", 0, 50)
    pg:Hide()
    pages[i] = pg
  end
  buildGeneralPage(pages[1])
  buildIdlePage(pages[2])
  buildBrandPage(pages[3])
  buildHPPage(pages[4])

  -- navigation list on the left; "Pet management" groups its pages (procs will get their own group)
  local navBg = CreateFrame("Frame", nil, f, BACKDROP_TEMPLATE)
  navBg:SetPoint("TOPLEFT", 16, -50)
  navBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", NAV_W - 6, 50)
  if navBg.SetBackdrop then
    navBg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    navBg:SetBackdropColor(0.05, 0.04, 0.03, 0.85)
    navBg:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
  end
  local navItems = {}
  local function selectPage(i)
    for k, pg in ipairs(pages) do pg:SetShown(k == i) end
    for k, it in pairs(navItems) do
      it.sel:SetShown(k == i)
      it.mark:SetShown(k == i)
      if k == i then it.label:SetTextColor(1, 1, 1) else it.label:SetTextColor(1, 0.82, 0) end
    end
    f.page = i
  end
  local NAV = { { 1, "General" }, { nil, "Pet management" }, { 2, "Pet not attacking", sub = true },
    { 3, ns.brandName(), sub = true }, { 4, "Low pet health", sub = true } }
  for pos, entry in ipairs(NAV) do
    local i, label = entry[1], entry[2]
    if not i then
      -- group heading, not clickable
      local h = navBg:CreateFontString(nil, "OVERLAY", "GameFontDisable")
      h:SetPoint("TOPLEFT", 19, -16 - (pos - 1) * 26)
      h:SetText(L[label])
    else
      local it = CreateFrame("Button", nil, navBg)
      it:SetSize(NAV_W - 34, 24)
      it:SetPoint("TOPLEFT", 9, -10 - (pos - 1) * 26)
      it.sel = it:CreateTexture(nil, "BACKGROUND")
      it.sel:SetAllPoints()
      it.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
      it.sel:SetVertexColor(1, 0.82, 0, 0.45)
      it.sel:SetBlendMode("ADD")
      it.mark = it:CreateTexture(nil, "ARTWORK")
      it.mark:SetColorTexture(1, 0.82, 0, 1)
      it.mark:SetSize(2, 18)
      it.mark:SetPoint("LEFT", 0, 0)
      it.mark:Hide()
      it:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      it.label = it:CreateFontString(nil, "OVERLAY", entry.sub and "GameFontNormalSmall" or "GameFontNormal")
      it.label:SetPoint("LEFT", entry.sub and 24 or 10, 0)
      it.label:SetText(L[label])
      if entry.sub then
        -- thin gold branch line: this page belongs to the group above
        local br = it:CreateTexture(nil, "ARTWORK")
        br:SetColorTexture(1, 0.82, 0, 0.5)
        br:SetSize(6, 1)
        br:SetPoint("LEFT", 13, 0)
        local up = it:CreateTexture(nil, "ARTWORK")
        up:SetColorTexture(1, 0.82, 0, 0.5)
        up:SetSize(1, 14)
        up:SetPoint("BOTTOMLEFT", br, "LEFT", 0, 0)
      end
      it:SetScript("OnClick", function() selectPage(i) end)
      navItems[i] = it
    end
  end

  -- buttons
  local bClose = makeButton(f, "Close", 100, function() f:Hide() end)
  bClose:SetPoint("BOTTOMRIGHT", -22, 18)
  local bTest = makeButton(f, "Test", 100, function() ns.Alert.test() end)
  bTest:SetPoint("RIGHT", bClose, "LEFT", -6, 0)
  tip(bTest, "Test", "Shows every switched-on warning for 5 seconds where it will appear.")
  local bMove = makeButton(f, "Move warnings", 130, function() ns.Alert.setLocked(not ns.db.locked) end)
  bMove:SetPoint("RIGHT", bTest, "LEFT", -6, 0)
  tip(bMove, "Move warnings", "Move mode on or off: drag the warnings on screen, then click Lock.")

  f:SetScript("OnShow", function(self)
    if InCombatLockdown() then
      self:EnableKeyboard(false)
    else
      self:EnableKeyboard(true)
      self:SetPropagateKeyboardInput(true)
    end
    O.refresh()
    selectPage(self.page or 1)
  end)
  f:Hide()
  return f
end

function O.refresh()
  for _, c in ipairs(controls) do c.refresh() end
  changed()
  O.refreshStatus()
end

function O.toggle()
  opt = opt or buildOptions()
  if opt:IsShown() then opt:Hide() else opt:Show() opt:Raise() end
end

function O.open()
  opt = opt or buildOptions()
  opt:Show()
  opt:Raise()
end

---------------------------------------------------------------------------
-- Entry under Escape > Options > AddOns (official registration calls only, in pcall)
---------------------------------------------------------------------------
local settingsPanel
function O.registerSettings()
  if settingsPanel then return end
  local p = CreateFrame("Frame", "WarlockPetProcSettingsPanel")
  p.name = ns.TITLE
  local logo = p:CreateTexture(nil, "ARTWORK")
  logo:SetSize(40, 40)
  logo:SetPoint("TOPLEFT", 16, -16)
  logo:SetTexture("Interface\\Icons\\Spell_Shadow_SummonImp")
  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", logo, "RIGHT", 10, 6)
  title:SetText(ns.TITLE)
  local ver = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  ver:SetText(string.format(L["Version %s"], ns.VERSION))
  local text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
  text:SetWidth(520)
  text:SetJustifyH("LEFT")
  text:SetText(L["All settings are in the addon's own window (also: /wpm or the minimap button)."])
  local open = makeButton(p, "Open options", 200, function() O.open() end)
  open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
  local ok = false
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    ok = pcall(function()
      local cat = Settings.RegisterCanvasLayoutCategory(p, ns.TITLE)
      Settings.RegisterAddOnCategory(cat)
    end)
  elseif InterfaceOptions_AddCategory then
    ok = pcall(InterfaceOptions_AddCategory, p)
  end
  ns.dbg("SETTINGS entry " .. (ok and "registered" or "not available"))
  settingsPanel = p
end

---------------------------------------------------------------------------
-- Minimap button: Summon Imp icon in the classic round tracking border
---------------------------------------------------------------------------
local mm
local function placeMinimapButton()
  local a = math.rad(ns.db.minimap.angle or 215)
  local r = (Minimap:GetWidth() / 2) + 10
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function createMinimapButton()
  if mm or not Minimap then return end
  mm = CreateFrame("Button", "WarlockPetProcMinimapButton", Minimap)
  mm:SetSize(31, 31)
  mm:SetFrameStrata("MEDIUM")
  mm:SetFrameLevel(8)
  mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mm:RegisterForDrag("LeftButton")
  mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local overlay = mm:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")
  local bg = mm:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = mm:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture("Interface\\Icons\\Spell_Shadow_SummonImp")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint("TOPLEFT", 7, -6)
  mm:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.Alert.test()
    else
      O.toggle()
    end
  end)
  mm:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      ns.db.minimap.angle = math.deg(math.atan2(py / s - my, px / s - mx))
      placeMinimapButton()
    end)
  end)
  mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.TITLE, 1, 0.82, 0)
    GameTooltip:AddLine(L["Left-click: options"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: test the warnings"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move this button"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
  placeMinimapButton()
end

function O.updateMinimapButton()
  if ns.db.minimap.hide then
    if mm then mm:Hide() end
  else
    createMinimapButton()
    if mm then mm:Show() placeMinimapButton() end
  end
end

table.insert(ns.hooks.login, function()
  pcall(O.registerSettings)
  O.updateMinimapButton()
end)
