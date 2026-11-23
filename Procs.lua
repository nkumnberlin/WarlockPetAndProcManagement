-- Warlock Pet & Proc Management: proc management.
--
-- 1. Decimation (0.3.0; Forever Demonology talent, 2 ranks, spell 440870): your Shadow Bolt or Searing
--    Pain on an enemy below 35 % health makes your Soul Fire faster (20 % / 40 % cast time) and free of
--    Soul Shards for 10 sec. While that proc is up, the "deci" warning shows ("Decimation: Soul Fire now!").
--
--    Not known yet on Forever: the proc buff's spell ID (Wowhead only has the talent), whether your own
--    buffs can be read in combat, whether the client shows the faster cast time, whether Soul Fire glows.
--    So the addon asks several signals; the warning is up while one of them says "proc":
--      a. the buff itself, by name or learned ID (exact; out of combat always readable, in combat maybe)
--      b. the game's proc glow on Soul Fire (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW, IsSpellOverlayed)
--      c. Soul Fire's cast time from the spell info, divided by Searing Pain's (haste changes both alike),
--         against the highest value seen since the last spell/talent change: under 90 % of it = proc
--    When the buff is readable, it alone decides (a "no" there also ends b and c). Its spell ID is
--    learned (saved in db.learned.deciBuff) the first time it is read, e.g. after a fight ends with it up.
--    PROC lines in the debug log say which signal answered and how long after your Shadow Bolt or Searing
--    Pain the proc came.

local _, ns = ...
local L = ns.L
local plain, str, num = ns.plain, ns.str, ns.num
local R = {}
ns.Procs = R

local D = {} -- Decimation
R.deci = D
D.TALENT = 440870          -- Wowhead Forever: the talent's passive spell (hidden aura on you)
D.SOUL_FIRE = { 17924, 6353 } -- Soul Fire ranks 2, 1 (Wowhead: the spells Decimation modifies)
D.SHADOW_BOLT = 686
D.SEARING = 5676
D.DUR = 10
D.DROP = 0.9 -- Soul Fire cast time (against Searing Pain's) under 90 % of normal = proc (80 % / 60 % then)

local function spellName(id)
  local n = C_Spell and C_Spell.GetSpellName and str(plain(C_Spell.GetSpellName, id))
  if not n and GetSpellInfo then n = str(plain(GetSpellInfo, id)) end
  return n
end

-- names in the client's language (the game names its spells)
function ns.deciName() return spellName(D.TALENT) or "Decimation" end
function ns.soulFireName() return spellName(D.SOUL_FIRE[2]) or "Soul Fire" end

---------------------------------------------------------------------------
-- Talent and spells
---------------------------------------------------------------------------
function D.talent()
  if D.talentKnown == nil then D.talentKnown = plain(IsPlayerSpell, D.TALENT) == true end
  return D.talentKnown
end

-- the Soul Fire the player knows (highest rank), nil if none
function D.soulFire()
  if D.sfID == nil then
    D.sfID = false
    for _, id in ipairs(D.SOUL_FIRE) do
      if plain(IsPlayerSpell, id) == true then D.sfID = id break end
    end
    if not D.sfID and C_Spell and C_Spell.GetSpellInfo then
      -- other ranks, by name (the client returns the known spell)
      local info = plain(C_Spell.GetSpellInfo, ns.soulFireName())
      local id = type(info) == "table" and num(info.spellID)
      if id and plain(IsPlayerSpell, id) == true then D.sfID = id end
    end
  end
  return D.sfID or nil
end

-- spells changed (new rank, respec, talents): look everything up again, learn "normal" again
function D.rescan()
  local before = D.talentKnown
  D.talentKnown, D.sfID, D.spID, D.normal = nil, nil, nil, nil
  if D.talent() ~= before then ns.dbg("TALENT Decimation " .. (D.talentKnown and "learned" or "not learned")) end
  if ns.Options then ns.Options.refresh() end
end

-- Shadow Bolt and Searing Pain in any rank and language (the proc's triggers, for the log)
D.triggerIDs = {}
function D.triggerName(id)
  id = num(id)
  if not id then return nil end
  local c = D.triggerIDs[id]
  if c == nil then
    local n = spellName(id)
    c = false
    if n and (n == spellName(D.SHADOW_BOLT) or n == "Shadow Bolt") then c = "Shadow Bolt" end
    if n and (n == spellName(D.SEARING) or n == "Searing Pain") then c = "Searing Pain" end
    D.triggerIDs[id] = c
  end
  return c or nil
end

-- the spell ID belongs to Soul Fire (any rank)?
function D.isSoulFire(id)
  id = num(id)
  if not id then return false end
  for _, s in ipairs(D.SOUL_FIRE) do if s == id then return true end end
  return spellName(id) == ns.soulFireName()
end

---------------------------------------------------------------------------
-- a. The buff itself
---------------------------------------------------------------------------
-- returns true (up) / false (not up) / nil (can't tell), and the aura's end time when known
function D.readAura()
  if not C_UnitAuras then return nil end
  local learned = ns.db.learned and ns.db.learned.deciBuff
  local aura
  if learned and C_UnitAuras.GetPlayerAuraBySpellID then
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, learned)
    if not ok or ns.issecret(a) then return nil end
    aura = a
    if aura == nil then
      -- nil can also mean "hidden": only trust it out of combat or once a read in combat worked
      if ns.inCombat and not D.auraReadInCombat then return nil end
      return false
    end
  elseif C_UnitAuras.GetAuraDataByIndex then
    -- ID not learned yet: look for a buff with Decimation's name that isn't the talent's hidden passive
    local name = ns.deciName()
    for i = 1, 40 do
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or ns.issecret(a) then return nil end
      if type(a) ~= "table" then break end
      local n, id = str(a.name), num(a.spellId)
      if not (n and id) then return nil end
      if n == name and id ~= D.TALENT then aura = a break end
    end
    if aura == nil then
      if ns.inCombat then return nil end -- in combat an empty list can mean "hidden"
      return false
    end
  else
    return nil
  end
  if type(aura) ~= "table" then return nil end
  local id = num(aura.spellId)
  if not id then return nil end
  if id == D.TALENT then return false end -- the talent's own hidden passive, not the proc
  if ns.inCombat and not D.auraReadInCombat then
    D.auraReadInCombat = true
    ns.dbg("PROC Decimation buff readable in combat (" .. id .. ")")
  end
  if not learned or learned ~= id then
    ns.db.learned = ns.db.learned or {}
    ns.db.learned.deciBuff = id
    ns.dbg("PROC learned Decimation buff ID " .. id)
    ns.sayLater(string.format(L["Learned the %s buff (spell %d)."], ns.deciName(), id))
  end
  return true, num(aura.expirationTime)
end

---------------------------------------------------------------------------
-- b. Proc glow on Soul Fire
---------------------------------------------------------------------------
D.glow = nil -- from the overlay events: true / false, nil = never seen
function D.readGlow()
  local id = D.soulFire()
  if not id then return nil end
  local f = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed
  local v = f and plain(f, id)
  if v == true or v == false then return v end
  return D.glow
end

function D.onGlow(event, id)
  if not D.isSoulFire(id) then return end
  D.glow = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
  ns.dbg("PROC Soul Fire glow " .. (D.glow and "on" or "off"))
  R.update()
end

-- the overlay picture: its spell ID is the proc aura's (a way to learn the buff ID)
function D.onOverlay(event, id)
  id = num(id)
  if not id or event ~= "SPELL_ACTIVATION_OVERLAY_SHOW" then return end
  local n = spellName(id)
  ns.dbg("PROC overlay " .. id .. " " .. tostring(n))
  if n == ns.deciName() and id ~= D.TALENT then
    ns.db.learned = ns.db.learned or {}
    if ns.db.learned.deciBuff ~= id then
      ns.db.learned.deciBuff = id
      ns.dbg("PROC learned Decimation buff ID " .. id .. " (overlay)")
    end
  end
end

---------------------------------------------------------------------------
-- c. Soul Fire's cast time
---------------------------------------------------------------------------
-- a spell's cast time in ms from the spell info (talents and haste included), nil when not readable
local function castMs(id)
  if not id then return nil end
  local ms
  if C_Spell and C_Spell.GetSpellInfo then
    local info = plain(C_Spell.GetSpellInfo, id)
    ms = type(info) == "table" and num(info.castTime) or nil
  end
  if not ms and GetSpellInfo then
    local ok, _, _, _, ct = pcall(GetSpellInfo, id)
    ms = ok and num(ct) or nil
  end
  return ms
end

-- the known Searing Pain (highest rank by name), the yardstick: haste changes both cast times alike
function D.searing()
  if D.spID == nil then
    D.spID = false
    local info = C_Spell and C_Spell.GetSpellInfo and plain(C_Spell.GetSpellInfo, spellName(D.SEARING) or "Searing Pain")
    local id = type(info) == "table" and num(info.spellID)
    if id and plain(IsPlayerSpell, id) == true then D.spID = id
    elseif plain(IsPlayerSpell, D.SEARING) == true then D.spID = D.SEARING end
  end
  return D.spID or nil
end

-- Soul Fire's cast time against Searing Pain's (no unit; raw ms when Searing Pain isn't there), and the raw ms
function D.readCast()
  local sf = castMs(D.soulFire())
  if not sf or sf <= 0 then return nil end
  local sp = castMs(D.searing())
  if sp and sp > 0 then return sf / sp, sf end
  return sf, sf
end

-- true (faster than normal) / false / nil (not readable)
-- normal = the highest value seen since the last spell/talent change. Out of combat it may rise freely;
-- in a fight a jump of more than 10 % up is ignored (something made Searing Pain faster, not Soul Fire slower)
function D.castFast()
  local v, raw = D.readCast()
  if not v then
    if D.castMode ~= "none" then
      D.castMode = "none"
      ns.dbg("PROC Soul Fire cast time " .. (D.soulFire() and "not readable" or "- Soul Fire not known"))
    end
    return nil
  end
  if D.castMode ~= "plain" then
    D.castMode = "plain"
    ns.dbg(string.format("PROC Soul Fire cast time readable: %.2fs (%s)", raw / 1000,
      D.searing() and "against Searing Pain" or "no Searing Pain: raw"))
  end
  D.castNow = raw
  if not D.normal or (v > D.normal and (not ns.inCombat or v <= D.normal * 1.1)) then
    D.normal = v
  elseif v > D.normal then
    return nil
  end
  return v < D.normal * D.DROP
end

---------------------------------------------------------------------------
-- The warning
---------------------------------------------------------------------------
D.up = false
function D.check(t)
  local aura, ends = D.readAura()
  local glow = D.readGlow()
  local fast = D.castFast()
  local up, how
  if aura ~= nil then
    up, how = aura, "buff"
  else
    up = (glow == true) or (fast == true)
    how = glow and "glow" or "cast time"
  end
  if up and not D.up then
    D.since, D.ends = t, ends or (t + D.DUR)
    local tr = D.lastTrigger
    ns.dbg(string.format("PROC Decimation on (%s; buff %s, glow %s, cast %s%s)%s", how, tostring(aura), tostring(glow),
      tostring(fast), D.castNow and string.format(" %.2fs", D.castNow / 1000) or "",
      (tr and t - tr.t < 12) and string.format(" %.2fs after %s", t - tr.t, tr.name) or " no Shadow Bolt/Searing Pain in the last 12 s"))
  elseif not up and D.up then
    ns.dbg(string.format("PROC Decimation off after %.1fs (buff %s, glow %s, cast %s)", t - (D.since or t),
      tostring(aura), tostring(glow), tostring(fast)))
  end
  if up and ends then D.ends = ends end
  D.up = up and true or false
  ns.Alert.set("deci", ns.db.deci.on and D.up)
end

-- own casts: remember the last Shadow Bolt / Searing Pain (the proc's triggers, for the log)
function D.onSucceeded(unit, _, spellID)
  if unit ~= "player" then return end
  local n = D.triggerName(spellID)
  if n then
    D.lastTrigger = { name = n, t = ns.now() }
    D.watchAura = ns.now() + 2
  end
  R.update()
end

-- an aura of yours changed: check now (and log the first new aura after a trigger, for the timing)
function D.onAura(unit, info)
  if unit ~= "player" then return end
  if D.watchAura and ns.now() < D.watchAura and type(info) == "table" and not ns.issecret(info) then
    local added = info.addedAuras
    if ns.issecret(added) or (type(added) == "table" and #added > 0) then
      D.watchAura = nil
      local tr = D.lastTrigger
      ns.dbg(string.format("PROC aura added on you %.2fs after %s", ns.now() - tr.t, tr.name))
    end
  end
  R.update()
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
function R.update()
  if not (ns.db and ns.isWarlock) then return end
  D.check(ns.now())
end

-- seconds left of the proc (for the status), nil when not up
function D.left(t)
  if not D.up or not D.ends then return nil end
  return math.max(0, D.ends - t)
end

-- one line for /wpm status and the options
function R.statusText()
  local t = ns.now()
  local parts = {}
  parts[#parts + 1] = string.format(L["%s talent: %s"], ns.deciName(), D.talent() and L["learned"] or L["not learned"])
  if not D.soulFire() then
    parts[#parts + 1] = string.format(L["%s not known"], ns.soulFireName())
  else
    local _, raw = D.readCast()
    if raw then
      parts[#parts + 1] = string.format(L["%s cast: %.1f s"], ns.soulFireName(), raw / 1000)
    end
  end
  local id = ns.db.learned and ns.db.learned.deciBuff
  parts[#parts + 1] = id and string.format(L["buff ID %d"], id) or L["buff ID not learned yet"]
  local left = D.left(t)
  if left then parts[#parts + 1] = string.format(L["proc up, %.0f s left"], left) end
  return table.concat(parts, ", ")
end

function R.status()
  ns.say(R.statusText())
end

local started = false
function R.start()
  if started or not ns.isWarlock then return end
  started = true
  ns.on("UNIT_SPELLCAST_SUCCEEDED", D.onSucceeded)
  ns.on("UNIT_AURA", D.onAura)
  ns.on("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(id) D.onGlow("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", id) end)
  ns.on("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(id) D.onGlow("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", id) end)
  ns.on("SPELL_ACTIVATION_OVERLAY_SHOW", function(id) D.onOverlay("SPELL_ACTIVATION_OVERLAY_SHOW", id) end)
  for _, e in ipairs({ "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN", "UNIT_SPELL_HASTE" }) do
    ns.on(e, R.update)
  end
  for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    ns.on(e, D.rescan)
  end
  -- after a fight the buff is readable: learn its ID if it is still up
  ns.on("PLAYER_REGEN_ENABLED", function() C_Timer.After(0.1, R.update) end)
  C_Timer.NewTicker(0.2, function()
    local ok, err = pcall(R.update)
    if not ok then ns.report("proc tick", err) end
  end)
  ns.dbg("PROC start, Decimation talent " .. (D.talent() and "learned" or "not learned") ..
    ", Soul Fire " .. tostring(D.soulFire() or "not known") ..
    ", buff ID " .. tostring(ns.db.learned and ns.db.learned.deciBuff or "not learned"))
end

table.insert(ns.hooks.login, function() R.start() end)
