-- Warlock Pet & Proc Management: pet management.
--
-- 1. Pet not attacking (0.1.1, was "pet on passive" in 0.1.0: Nico keeps his pet on Passive on
--    purpose and sends it in with Attack; what matters is whether it attacks). While you are in combat
--    and your pet is alive but not attacking for longer than the wait time, the "idle" warning is up.
--    It goes away when the pet attacks, is gone or the fight ends. Works in every pet mode.
--    "Attacking" = IsPetAttackActive() (the pet's Attack is on; PET_ATTACK_START/STOP), or a pet cast
--    in the last 3 s (the Imp's Firebolt). If IsPetAttackActive can't be read, a living enemy as the
--    pet's target counts as attacking. ATTACK lines in the debug log show which source answered.
--
-- 2. Demonic Brand (Forever Demonology talent, spell 1293695): your Searing Pain brands the enemy
--    for 10 s; your pet's next attacks on it deal extra damage. When the talent is learned and your
--    pet attacks an enemy without a running brand, the "brand" warning comes up (after a short delay,
--    so a Searing Pain already on its way can land first).
--    The brand can't be read in combat (DotProbe 0.7, see AGENTS.md), so it is tracked from your own
--    casts like DotWatch does: Searing Pain SUCCEEDED + no resist in the same frame = brand for 10 s.
--    The branded enemy is remembered by GUID (open world) and by the unit tokens that point at it
--    (target, focus, pettarget, nameplates): in dungeons GUIDs are secret, but UnitIsUnit still works.
--    Optional (experimental, off by default): count the pet's empowered attacks (6 charges at rank 3)
--    from fire/shadow hits that come with an aura update in the same frame, and end the brand early.

local _, ns = ...
local L = ns.L
local plain, str, num = ns.plain, ns.str, ns.num
local P = {}
ns.Pet = P

---------------------------------------------------------------------------
-- Pet basics
---------------------------------------------------------------------------
function P.hasPet()
  return plain(UnitExists, "pet") == true and plain(UnitIsDeadOrGhost, "pet") ~= true
end

-- pet mode for /wpm status and the options (pet bar token PET_MODE_*; some clients put a subtext
-- before the texture, then isActive is one position further)
function P.modeName()
  if not P.hasPet() or not GetPetActionInfo then return nil end
  for i = 1, NUM_PET_ACTION_SLOTS or 10 do
    local r = { pcall(GetPetActionInfo, i) }
    local name = r[1] and r[2]
    if type(name) == "string" and not ns.issecret(name) and name:find("^PET_MODE_") then
      local active = type(r[4]) == "string" and r[6] or r[5]
      if not ns.issecret(active) and (active == true or active == 1) then
        local label = _G[name]
        return (type(label) == "string" and label ~= "") and label or name
      end
    end
  end
end

local B = { list = {}, pending = {}, recent = {} } -- Demonic Brand, section 2

---------------------------------------------------------------------------
-- 1. Pet not attacking
---------------------------------------------------------------------------
-- a living enemy as the pet's target
local function petHasEnemy()
  return plain(UnitExists, "pettarget") == true and plain(UnitCanAttack, "player", "pettarget") ~= false
    and plain(UnitIsDead, "pettarget") ~= true
end

-- is the pet attacking? returns true/false and which signal answered (for the debug log)
function P.attackState(t)
  if not P.hasPet() then return false, "no pet" end
  if B.lastPetCast and t - B.lastPetCast < 3 then return true, "pet cast" end
  if IsPetAttackActive then
    local ok, v = pcall(IsPetAttackActive)
    if ok and not ns.issecret(v) then return (v == true or v == 1), "attack " .. tostring(v) end
  end
  return petHasEnemy(), "pet target (attack state unreadable)"
end

P.attacking = nil -- last state, for the log
function P.checkIdle(t)
  local c = ns.db.idle
  local att, how = P.attackState(t)
  if att ~= P.attacking then
    ns.dbg("ATTACK " .. tostring(att) .. " (" .. how .. ")")
    P.attacking = att
  end
  local want = c.on and ns.inCombat and P.hasPet() and not att
  if want then
    P.idleSince = P.idleSince or t
    if t - P.idleSince < (c.delay or 0) then want = false end
  else
    P.idleSince = nil
  end
  ns.Alert.set("idle", want and true or false)
end

---------------------------------------------------------------------------
-- 2. Demonic Brand
---------------------------------------------------------------------------
P.brand = B
B.TALENT = 1293695
B.SEARING = 5676 -- rank 1; every rank is matched by name
B.DUR = 10
B.CHARGES = 6 -- rank 3/3: "your pet's next 6 attacks" (the rank spells' IDs are unknown)
B.TOKENS = { "target", "focus", "pettarget" } -- stable unit tokens (+ nameplates)
B.CAST_UNITS = { "target", "mouseover", "focus", "targettarget" } -- where a cast can have gone

function B.talent()
  if B.talentKnown == nil then B.talentKnown = plain(IsPlayerSpell, B.TALENT) == true end
  return B.talentKnown
end
function B.rescanTalent()
  local before = B.talentKnown
  B.talentKnown = nil
  if B.talent() ~= before then ns.dbg("TALENT Demonic Brand " .. (B.talentKnown and "learned" or "not learned")) end
  if ns.Options then ns.Options.refresh() end
end

-- Searing Pain in any rank and client language
B.searingIDs = {}
function B.isSearing(id)
  id = num(id)
  if not id then return false end
  local c = B.searingIDs[id]
  if c ~= nil then return c end
  local name = C_Spell and C_Spell.GetSpellName and str(plain(C_Spell.GetSpellName, id))
  if not name and GetSpellInfo then name = str(plain(GetSpellInfo, id)) end
  if not name then return false end
  local own = C_Spell and C_Spell.GetSpellName and str(plain(C_Spell.GetSpellName, B.SEARING))
  c = (name == own) or name == "Searing Pain"
  B.searingIDs[id] = c
  return c
end

-- every stable token that points at this unit right now
local function tokensOf(unit)
  local set = {}
  for _, tok in ipairs(B.TOKENS) do
    if tok == unit or plain(UnitIsUnit, unit, tok) == true then set[tok] = true end
  end
  if unit:sub(1, 9) == "nameplate" then set[unit] = true end
  for i = 1, 40 do
    local tok = "nameplate" .. i
    if not set[tok] and plain(UnitExists, tok) == true and plain(UnitIsUnit, unit, tok) == true then set[tok] = true end
  end
  return set
end

-- is this unit the enemy of brand (or pending cast) b?
local function isSame(unit, b)
  if not unit then return false end
  local g = ns.guidOf(unit)
  if g and b.guid then return g == b.guid end
  for tok in pairs(b.tokens) do
    if tok == unit or plain(UnitIsUnit, unit, tok) == true then return true end
  end
  return false
end
B.isSame = isSame

-- the enemy a cast went to: by the SENT name, or (hidden name in instances) the first hostile living
-- unit of target / mouseover / focus / targettarget
local function resolveDest(destName)
  if ns.issecret(destName) or not str(destName) or destName == "" then
    for _, u in ipairs(B.CAST_UNITS) do
      if plain(UnitExists, u) == true and plain(UnitCanAttack, "player", u) ~= false and plain(UnitIsDead, u) ~= true then
        return u, "hidden name"
      end
    end
    return nil
  end
  for _, u in ipairs(B.CAST_UNITS) do
    if str(plain(UnitName, u)) == destName then return u, "name" end
  end
  for i = 1, 40 do
    local u = "nameplate" .. i
    if str(plain(UnitName, u)) == destName then return u, "name" end
  end
end

local function describe(b)
  local toks = {}
  for tok in pairs(b.tokens) do toks[#toks + 1] = tok end
  table.sort(toks)
  return "[" .. ns.short(b.guid) .. " " .. table.concat(toks, ",") .. "]"
end

function B.onSent(unit, destName, castGUID, spellID)
  if unit ~= "player" or not B.isSearing(spellID) or not B.talent() then return end
  castGUID = str(castGUID)
  if not castGUID then return end
  local u, how = resolveDest(destName)
  if not u then ns.dbg("BRAND cast without a resolvable enemy") return end
  local p = { guid = ns.guidOf(u), tokens = tokensOf(u), t = ns.now() }
  B.pending[castGUID] = p
  ns.dbg("BRAND cast at " .. u .. " (" .. how .. ") " .. describe(p))
end

function B.onSucceeded(unit, castGUID, spellID)
  if unit == "pet" then B.lastPetCast = ns.now() return end
  if unit ~= "player" or not B.isSearing(spellID) or not B.talent() then return end
  castGUID = str(castGUID)
  local p = castGUID and B.pending[castGUID]
  if castGUID then B.pending[castGUID] = nil end
  if not p then
    -- no SENT: the current target
    if plain(UnitCanAttack, "player", "target") == false or plain(UnitExists, "target") ~= true then return end
    p = { guid = ns.guidOf("target"), tokens = tokensOf("target") }
  end
  local t = ns.now()
  -- a new brand on the same enemy replaces the old one (full time, full charges)
  for i = #B.list, 1, -1 do
    local o = B.list[i]
    if (p.guid and o.guid == p.guid) or (not p.guid and next(p.tokens) and isSame(next(p.tokens), o)) then
      table.remove(B.list, i)
    end
  end
  local b = { guid = p.guid, tokens = p.tokens, start = t, expires = t + B.DUR, charges = B.CHARGES }
  table.insert(B.list, b)
  ns.dbg("BRAND start " .. describe(b))
  -- resisted? (same-frame rule: MISS/RESIST/IMMUNE/EVADE on it in this frame and no new aura)
  C_Timer.After(0.1, function() B.verify(b) end)
  P.update()
end

function B.onCastEnd(unit, castGUID)
  if unit ~= "player" then return end
  castGUID = str(castGUID)
  if castGUID and B.pending[castGUID] then B.pending[castGUID] = nil end
end

-- recent UNIT_COMBAT / UNIT_AURA events (last 0.3 s) for the resist check and the charge counter
local function remember(kind, unit, extra)
  local t = ns.now()
  local r = B.recent
  r[#r + 1] = { kind = kind, unit = unit, t = t, extra = extra }
  while #r > 0 and t - r[1].t > 0.3 do table.remove(r, 1) end
end

function B.verify(b)
  local failed, landed
  for _, e in ipairs(B.recent) do
    if math.abs(e.t - b.start) <= ns.SAME_FRAME and isSame(e.unit, b) then
      if e.kind == "fail" then failed = e.extra end
      if e.kind == "added" then landed = true end
    end
  end
  if failed and not landed then
    for i, o in ipairs(B.list) do
      if o == b then table.remove(B.list, i) break end
    end
    ns.dbg("BRAND failed (" .. tostring(failed) .. ") " .. describe(b))
    P.update()
  else
    ns.dbg("BRAND " .. (landed and "landed" or "no aura seen") .. " " .. describe(b))
  end
end

local FAIL = { MISS = true, RESIST = true, IMMUNE = true, EVADE = true }
function B.onCombat(unit, action, _, _, school)
  action = str(action)
  -- also while our cast is on its way: a resist can come a moment before SUCCEEDED in the same frame
  if not action or not (next(B.list) or next(B.pending)) then return end
  if FAIL[action] then remember("fail", unit, action) return end
  if action == "WOUND" then
    school = num(school)
    if school == 4 or school == 32 then B.chargeSignal(unit, "hit") end
  end
end

function B.onAura(unit, info)
  if not (next(B.list) or next(B.pending)) or type(info) ~= "table" or ns.issecret(info) then return end
  if unit == "player" or unit == "pet" then return end
  local added, updated = info.addedAuras, info.updatedAuraInstanceIDs
  if ns.issecret(added) or (type(added) == "table" and #added > 0) then remember("added", unit) end
  if ns.issecret(updated) or (type(updated) == "table" and #updated > 0) then B.chargeSignal(unit, "upd") end
end

-- experimental: one charge per empowered pet attack = fire/shadow hit + aura update on the branded
-- enemy in the same frame, only while it is the pet's target, not right after our own Searing Pain
function B.chargeSignal(unit, kind)
  if not ns.db.brand.charges then return end
  local t = ns.now()
  for _, b in ipairs(B.list) do
    if b.expires > t and isSame(unit, b) and plain(UnitIsUnit, "pettarget", unit) == true then
      if kind == "hit" then b.hitT = t else b.updT = t end
      if b.hitT and b.updT and math.abs(b.hitT - b.updT) <= ns.SAME_FRAME
          and not (b.usedT and t - b.usedT <= 0.15) and t - b.start > 0.15 then
        b.usedT = t
        b.charges = b.charges - 1
        ns.dbg(string.format("BRAND charge %+.2fs: %d left %s", t - b.start, b.charges, describe(b)))
        if b.charges <= 0 then
          b.expires = t
          ns.dbg("BRAND used up " .. describe(b))
        end
      end
      return
    end
  end
end

-- a token now points at another unit: drop it from every brand, then give it back to the brand whose
-- enemy it shows now (by GUID or another token of that brand)
function B.retoken(tok)
  local function fix(b)
    b.tokens[tok] = nil
    if plain(UnitExists, tok) ~= true then return end
    if isSame(tok, b) then b.tokens[tok] = true end
  end
  for _, b in ipairs(B.list) do fix(b) end
  for _, p in pairs(B.pending) do fix(p) end
end
function B.dropToken(tok)
  for _, b in ipairs(B.list) do b.tokens[tok] = nil end
  for _, p in pairs(B.pending) do p.tokens[tok] = nil end
end

function B.prune(t)
  for i = #B.list, 1, -1 do
    local b = B.list[i]
    local known = b.guid or next(b.tokens)
    if b.expires <= t or not known then
      ns.dbg("BRAND end " .. (b.expires <= t and "" or "(enemy lost) ") .. describe(b))
      table.remove(B.list, i)
    end
  end
  for g, p in pairs(B.pending) do
    if t - (p.t or t) > 6 then B.pending[g] = nil end
  end
end

-- a running brand (or our Searing Pain on its way) on this unit?
function B.branded(unit, t)
  for _, b in ipairs(B.list) do
    if b.expires > t and isSame(unit, b) then return true end
  end
  return false
end
function B.castingAt(unit)
  for _, p in pairs(B.pending) do
    if isSame(unit, p) then return true end
  end
  return false
end

-- is the pet fighting its target? attacking (see P.attackState) and the target is a living enemy
function P.petAttacking(t)
  return petHasEnemy() and (P.attackState(t)) == true
end

function P.checkBrand(t)
  local c = ns.db.brand
  local want = c.on and ns.inCombat and B.talent() and P.petAttacking(t)
    and not B.branded("pettarget", t) and not B.castingAt("pettarget")
  if want then
    B.since = B.since or t
    if t - B.since < (c.delay or 0) then want = false end
  else
    B.since = nil
  end
  ns.Alert.set("brand", want and true or false)
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
function P.update()
  if not (ns.db and ns.isWarlock) then return end
  local t = ns.now()
  B.prune(t)
  P.checkIdle(t)
  P.checkBrand(t)
end

function P.status()
  local t = ns.now()
  local att, how = P.attackState(t)
  ns.say(string.format(L["Pet: %s, mode: %s"], P.hasPet() and (str(plain(UnitName, "pet")) or "?") or L["none"],
    P.modeName() or "?"))
  ns.say(string.format(L["Pet attacking: %s (%s)"], att and L["yes"] or L["no"], how))
  ns.say(string.format(L["%s talent: %s, running brands: %d"], ns.brandName(),
    B.talent() and L["learned"] or L["not learned"], #B.list))
  for _, b in ipairs(B.list) do
    print(string.format("  %s %.1fs%s", describe(b), b.expires - t,
      ns.db.brand.charges and (", " .. b.charges .. " charges") or ""))
  end
end

local started = false
function P.start()
  if started or not ns.isWarlock then return end
  started = true
  ns.on("UNIT_SPELLCAST_SENT", B.onSent)
  ns.on("UNIT_SPELLCAST_SUCCEEDED", B.onSucceeded)
  ns.on("UNIT_SPELLCAST_FAILED", B.onCastEnd)
  ns.on("UNIT_SPELLCAST_INTERRUPTED", B.onCastEnd)
  ns.on("UNIT_COMBAT", B.onCombat)
  ns.on("UNIT_AURA", B.onAura)
  ns.on("PLAYER_TARGET_CHANGED", function() B.retoken("target") P.update() end)
  ns.on("PLAYER_FOCUS_CHANGED", function() B.retoken("focus") end)
  ns.on("UNIT_TARGET", function(unit)
    if unit == "pet" then
      B.retoken("pettarget")
      B.since = nil -- the delay starts again for the new target
      P.update()
    end
  end)
  ns.on("NAME_PLATE_UNIT_ADDED", function(tok) B.retoken(tok) end)
  ns.on("NAME_PLATE_UNIT_REMOVED", function(tok) B.dropToken(tok) end)
  for _, e in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "PET_ATTACK_START", "PET_ATTACK_STOP" }) do
    ns.on(e, function()
      if e == "PET_ATTACK_START" or e == "PET_ATTACK_STOP" then ns.dbg("ATTACK event " .. e) end
      P.update()
    end)
  end
  ns.on("UNIT_PET", function(unit)
    if unit == "player" then
      B.since = nil
      P.update()
    end
  end)
  ns.on("PLAYER_REGEN_DISABLED", function() P.idleSince = nil P.update() end)
  ns.on("PLAYER_REGEN_ENABLED", function()
    ns.Alert.set("idle", false)
    ns.Alert.set("brand", false)
    B.since = nil
    P.idleSince = nil
  end)
  for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    ns.on(e, B.rescanTalent)
  end
  C_Timer.NewTicker(0.2, function()
    local ok, err = pcall(P.update)
    if not ok then ns.report("tick", err) end
  end)
  ns.dbg("PET start, Demonic Brand talent " .. (B.talent() and "learned" or "not learned"))
end

table.insert(ns.hooks.login, function() P.start() end)
