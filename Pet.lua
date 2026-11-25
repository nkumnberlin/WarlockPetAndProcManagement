-- Warlock Pet & Proc Management: pet management.
--
-- 1. Pet not attacking (0.1.1, was "pet on passive" in 0.1.0: Nico keeps his pet on Passive on
--    purpose and sends it in with Attack; what matters is whether it attacks). While you are in combat
--    and your pet is alive but not attacking for longer than the wait time, the "idle" warning is up.
--    It goes away when the pet attacks, is gone or the fight ends. Works in every pet mode.
--    "Attacking" = IsPetAttackActive() (the pet's Attack is on; PET_ATTACK_START/STOP), or a pet cast
--    in the last 3 s (the Imp's Firebolt). If IsPetAttackActive can't be read, a living enemy as the
--    pet's target counts as attacking. ATTACK lines in the debug log show which source answered.
--    0.3.1, Imp: its Attack can stay on while it does nothing (out of range or sight, out of mana,
--    crowd-controlled, chasing a fleeing enemy). The Imp attacks by casting Firebolt, so with Attack on
--    and no pet cast (finished or running) for P.STALL s it counts as not attacking. The grace starts
--    again when Attack goes on or the pet gets a new target (travel time). Other pets: only an ATTACK
--    debug line when they cast nothing for a while (to learn what Forever shows for melee pets).
--    0.3.2, every pet: when its target dies mid-fight the game can leave Attack on; Attack on with no
--    pet target (or a dead one) counts as not attacking.
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

-- 0.3.2: what the pet's target is: "enemy", "none", "dead" or "unknown" (the game hides the answer).
-- Only a plain "none" or "dead" counts against the pet; anything hidden gives it the benefit of the doubt.
function P.petTarget()
  local ok, ex = pcall(UnitExists, "pettarget")
  if not ok or ns.issecret(ex) then return "unknown" end
  if not ex then return "none" end
  local okD, dead = pcall(UnitIsDead, "pettarget")
  if okD and not ns.issecret(dead) and dead then return "dead" end
  return "enemy"
end

-- 0.3.1: the Imp (by creature family, or because it cast Firebolt since it was summoned)
P.STALL = 3.5 -- s without a pet cast while Attack is on (Firebolt: 2 s cast, 1.5 s with the talent)
P.FIREBOLT = 3110 -- rank 1; every rank is matched by name
P.IMP_NAMES = { Imp = true, Wichtel = true }
local fireboltIDs = {}
function P.isFirebolt(id)
  id = num(id)
  if not id then return false end
  local c = fireboltIDs[id]
  if c ~= nil then return c end
  local name = C_Spell and C_Spell.GetSpellName and str(plain(C_Spell.GetSpellName, id))
  if not name and GetSpellInfo then name = str(plain(GetSpellInfo, id)) end
  if not name then return false end
  local own = C_Spell and C_Spell.GetSpellName and str(plain(C_Spell.GetSpellName, P.FIREBOLT))
  c = (name == own) or name == "Firebolt" or name == "Feuerblitz"
  fireboltIDs[id] = c
  return c
end
function P.isImp()
  if P.impSeen then return true end
  local fam = str(plain(UnitCreatureFamily, "pet"))
  return fam ~= nil and P.IMP_NAMES[fam] == true
end

-- the pet started / finished / stopped a cast
function P.onPetCast(event, unit, _, spellID)
  if unit ~= "pet" then return end
  local t = ns.now()
  P.lastPetEvent = t -- also a stopped or interrupted cast: the pet is trying
  if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
    P.petCasting = t
  else
    P.petCasting = nil
  end
  if event == "UNIT_SPELLCAST_SUCCEEDED" then B.lastPetCast = t end
  if not P.impSeen and P.isFirebolt(spellID) then
    P.impSeen = true
    ns.dbg("ATTACK pet is an Imp (Firebolt)")
  end
end

-- a new pet target: the pet gets its travel time again
function P.resetAttack()
  if P.attackOn then P.attackOn = ns.now() end
  P.stallSaid = nil
end

-- is the pet attacking? returns true/false and which signal answered (for the debug log)
function P.attackState(t)
  if not P.hasPet() then return false, "no pet" end
  local recent = B.lastPetCast and t - B.lastPetCast < 3
  if IsPetAttackActive then
    local ok, v = pcall(IsPetAttackActive)
    if ok and not ns.issecret(v) then
      if not (v == true or v == 1) then
        P.attackOn, P.stallSaid = nil, nil
        if recent then return true, "pet cast" end
        return false, "attack " .. tostring(v)
      end
      P.attackOn = P.attackOn or t
      -- 0.3.2: the target died (or is gone) and the game leaves Attack on (Nico's log, 2026-11-25:
      -- Attack stayed on up to 48 s over several pet targets while the Succubus stood idle)
      local tgt = P.petTarget()
      if tgt == "none" or tgt == "dead" then
        if recent then return true, "pet cast" end
        return false, "attack on, but pet target " .. tgt
      end
      -- the last sign of life: Attack went on (or a new target), a finished cast, a cast running now
      local last = math.max(P.attackOn, P.lastPetEvent or 0)
      if P.petCasting and t - P.petCasting < 4 then last = t end
      if t - last >= P.STALL then
        if P.isImp() then
          return false, string.format("attack on, but no Imp cast for %.1fs", t - last)
        elseif not P.stallSaid and ns.inCombat and t - last >= 5 then
          P.stallSaid = true
          ns.dbg(string.format("ATTACK %s: attack on, no pet cast for %.1fs (not judged)",
            str(plain(UnitCreatureFamily, "pet")) or "pet family unknown", t - last))
        end
      end
      return true, "attack " .. tostring(v)
    end
  end
  if recent then return true, "pet cast" end
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
-- true / false, or nil = can't tell (0.1.3: in raids and dungeons UnitIsUnit may answer with a secret)
local function isSame(unit, b)
  if not unit then return false end
  local g = ns.guidOf(unit)
  if g and b.guid then return g == b.guid end
  local unknown = false
  for tok in pairs(b.tokens) do
    if tok == unit then return true end
    local ok, v = pcall(UnitIsUnit, unit, tok)
    if ok and ns.issecret(v) then
      unknown = true
    elseif ok and v == true then
      return true
    end
  end
  if unknown then return nil end
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

-- 0.1.3 diagnostics for instances: what a raw answer was (value, "secret", "err")
local function rawAnswer(f, ...)
  local ok, v = pcall(f, ...)
  if not ok then return "err" end
  if ns.issecret(v) then return "secret" end
  return tostring(v)
end
B.rawAnswer = rawAnswer

function B.onSent(unit, destName, castGUID, spellID)
  if unit ~= "player" then return end
  if ns.issecret(spellID) and not B.saidSecretID then
    B.saidSecretID = true
    ns.dbg("BRAND own cast spell ID is secret here")
  end
  if not B.isSearing(spellID) or not B.talent() then return end
  if not str(castGUID) then ns.dbg("BRAND cast ID not readable (" .. rawAnswer(tostring, castGUID) .. ")") end
  castGUID = str(castGUID)
  if not castGUID then return end
  local u, how = resolveDest(destName)
  if not u then ns.dbg("BRAND cast without a resolvable enemy") return end
  local p = { guid = ns.guidOf(u), tokens = tokensOf(u), t = ns.now() }
  B.pending[castGUID] = p
  ns.dbg("BRAND cast at " .. u .. " (" .. how .. ") " .. describe(p) .. string.format(
    " | guid %s, is pettarget %s, is nameplate1 %s", rawAnswer(UnitGUID, u),
    rawAnswer(UnitIsUnit, u, "pettarget"), rawAnswer(UnitIsUnit, u, "nameplate1")))
end

function B.onSucceeded(unit, castGUID, spellID)
  if unit == "pet" then return end -- P.onPetCast
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
  -- 0.2.0: an aura changed somewhere while the brand line is up: let the engine look at the pet's target again
  if ns.Alert.active.brand and unit ~= "player" and unit ~= "pet" then ns.Alert.engineRefresh() end
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
    -- 0.1.4: a brand whose enemy can't be followed any more stays until its 10 s are over (time rule)
    if b.expires <= t then
      ns.dbg("BRAND end " .. describe(b))
      table.remove(B.list, i)
    end
  end
  for g, p in pairs(B.pending) do
    if t - (p.t or t) > 6 then B.pending[g] = nil end
  end
end

-- a running brand (or our Searing Pain on its way) on this unit?
-- true / false, or nil = can't tell for at least one brand and no brand matched
function B.branded(unit, t)
  local unknown = false
  for _, b in ipairs(B.list) do
    if b.expires > t then
      local s = isSame(unit, b)
      if s then return true end
      if s == nil then unknown = true end
    end
  end
  if unknown then return nil end
  return false
end
function B.castingAt(unit)
  local unknown = false
  for _, p in pairs(B.pending) do
    local s = isSame(unit, p)
    if s then return true end
    if s == nil then unknown = true end
  end
  if unknown then return nil end
  return false
end

-- Is the pet's target branded (or our Searing Pain on its way to it)?
-- Open world: per enemy (GUIDs). 0.1.4, time rule: when the game hides who the pet's target is
-- (raids and dungeons: no GUID, and the dungeon log of 2026-11-23 showed that pettarget never matched
-- the branded enemy's target/nameplate tokens), any brand of the last 10 s counts and any Searing Pain
-- on its way counts; the warning comes when none was applied since. (0.1.3 used your own target
-- here; the log showed that's not enough: the brand lost its tokens on every target switch.)
function B.anyRunning(t)
  for _, b in ipairs(B.list) do
    if b.expires > t then return true end
  end
  return false
end
function B.petTargetState(t)
  local hidden = not ns.guidOf("pettarget")
  local br, casting -- nil = can't tell
  if not hidden then br, casting = B.branded("pettarget", t), B.castingAt("pettarget") end
  if br == nil or casting == nil then
    if not B.saidFallback then
      B.saidFallback = true
      ns.dbg("BRAND pet's enemy hidden here (" .. (hidden and "no guid" or "can't compare") ..
        "): any brand of the last 10 s counts")
    end
    if br == nil then br = B.anyRunning(t) end
    if casting == nil then casting = next(B.pending) ~= nil end
  end
  return br and true or false, casting and true or false
end

-- is the pet fighting its target? attacking (see P.attackState) and the target is a living enemy
function P.petAttacking(t)
  return petHasEnemy() and (P.attackState(t)) == true
end

-- 0.2.0: where the pet's target is hidden (raids, dungeons) and Blizzard's aura engine is there, the
-- engine decides whether the line shows (exactly: is our brand on the pet's target?). The addon then
-- only knows the 10 s time rule: no brand of ours in the last 10 s = surely unbranded -> with sound;
-- a brand in the last 10 s (maybe on another enemy) -> the line is up but quiet, the engine shows it
-- only if the pet's target really has no brand. Open world: the per-enemy check alone, as before.
function B.useEngine()
  return ns.db.brand.engine ~= false and ns.Alert.engineReady() and not ns.guidOf("pettarget")
end

function P.checkBrand(t)
  local c = ns.db.brand
  local want = c.on and ns.inCombat and B.talent() and P.petAttacking(t)
  local branded, casting = false, false
  if want then
    branded, casting = B.petTargetState(t)
    want = not casting and (B.useEngine() or not branded)
  end
  if want then
    B.since = B.since or t
    if t - B.since < (c.delay or 0) then want = false end
  else
    B.since = nil
  end
  if want and not ns.Alert.active.brand then B.explain(t) end
  -- the game sends no aura events for "pettarget": while the line is up, the engine looks again twice a second
  if want and B.useEngine() and (not B.lastRefresh or t - B.lastRefresh >= 0.4) then
    B.lastRefresh = t
    ns.Alert.engineRefresh()
  end
  local quiet = want and B.useEngine() and branded
  ns.Alert.set("brand", want and true or false, quiet or nil)
end

-- 0.1.3: why the brand warning comes up: the pet's target against every running brand
function B.explain(t)
  local parts = { "pettarget guid " .. (ns.guidOf("pettarget") and ns.short(ns.guidOf("pettarget")) or rawAnswer(UnitGUID, "pettarget")) }
  for i, b in ipairs(B.list) do
    local r = {}
    for tok in pairs(b.tokens) do r[#r + 1] = tok .. "=" .. rawAnswer(UnitIsUnit, "pettarget", tok) end
    parts[#parts + 1] = string.format("brand%d %s %.1fs left: %s", i, b.guid and ns.short(b.guid) or "no guid",
      b.expires - t, #r > 0 and table.concat(r, ",") or "no tokens")
  end
  if #B.list == 0 then parts[#parts + 1] = "no running brand" end
  parts[#parts + 1] = "engine " .. (B.useEngine() and "decides" or (ns.Alert.engineReady() and "ready, not used" or "none")) .. ", width " .. ns.Alert.engineWidth()
  ns.dbg("BRAND why " .. table.concat(parts, " | "))
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
  P.checkHP()
end

---------------------------------------------------------------------------
-- 3. Low pet health (0.1.2): the pet is alive and at or below the threshold (in a fight, or also out of
--    combat when ticked). Readable health: compared here, with sound; back off only 3 % above the
--    threshold so it doesn't flicker. Secret health (not known yet whether Forever hides the pet's
--    health in fights): the game compares inside the line's gate (Alerts.lua), no sound. HP lines in the
--    debug log say which way it went.
---------------------------------------------------------------------------
P.HP_HYST = 3

-- for the status: "54%", "hidden by the game" or "-" (no pet)
function P.hpText()
  if not P.hasPet() then return "-" end
  local cur, max = plain(UnitHealth, "pet"), plain(UnitHealthMax, "pet")
  if type(cur) == "number" and type(max) == "number" and max > 0 then
    return string.format("%d%%", math.floor(cur / max * 100 + 0.5))
  end
  return L["hidden by the game"]
end

function P.checkHP()
  local c = ns.db.hp
  if not (c.on and P.hasPet() and (ns.inCombat or c.ooc)) then
    P.hpLow = false
    ns.Alert.set("hp", false)
    return
  end
  local cur, max = plain(UnitHealth, "pet"), plain(UnitHealthMax, "pet")
  if type(cur) == "number" and type(max) == "number" and max > 0 then
    if P.hpMode ~= "plain" then ns.dbg("HP readable") P.hpMode = "plain" end
    local pct = cur / max * 100
    P.hpPct = pct
    local th = c.threshold or 30
    P.hpLow = (pct <= th) or (P.hpLow and pct <= th + P.HP_HYST) or false
    ns.Alert.gateOpen("hp")
    ns.Alert.set("hp", P.hpLow)
  else
    if P.hpMode ~= "secret" then ns.dbg("HP secret: the game compares, no sound") P.hpMode = "secret" end
    P.hpPct, P.hpLow = nil, nil
    -- secret values go straight to the gate's bar, never into a variable that outlives this call
    local okC, cur2 = pcall(UnitHealth, "pet")
    local okM, max2 = pcall(UnitHealthMax, "pet")
    local shown = okC and okM and ns.Alert.gateFeed("hp", cur2, max2) or false
    ns.Alert.set("hp", shown, true)
  end
end

function P.status()
  local t = ns.now()
  local att, how = P.attackState(t)
  ns.say(string.format(L["Pet: %s, mode: %s"], P.hasPet() and (str(plain(UnitName, "pet")) or "?") or L["none"],
    P.modeName() or "?"))
  ns.say(string.format(L["Pet attacking: %s (%s)"], att and L["yes"] or L["no"], how))
  ns.say(string.format(L["Pet health: %s"], P.hpText()))
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
  for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
      "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    ns.on(e, function(...) P.onPetCast(e, ...) end)
  end
  ns.on("UNIT_SPELLCAST_FAILED", B.onCastEnd)
  ns.on("UNIT_SPELLCAST_INTERRUPTED", B.onCastEnd)
  ns.on("UNIT_COMBAT", B.onCombat)
  ns.on("UNIT_AURA", B.onAura)
  ns.on("PLAYER_TARGET_CHANGED", function() B.retoken("target") P.update() end)
  ns.on("PLAYER_FOCUS_CHANGED", function() B.retoken("focus") end)
  ns.on("UNIT_TARGET", function(unit)
    if unit == "pet" then
      B.retoken("pettarget")
      ns.dbg("ATTACK pet target changed: " .. P.petTarget())
      B.since = nil -- the delay starts again for the new target
      P.resetAttack() -- 0.3.1: travel time to the new target
      ns.Alert.engineRefresh() -- 0.2.0: the engine reads the new pet target
      P.update()
    end
  end)
  ns.on("NAME_PLATE_UNIT_ADDED", function(tok) B.retoken(tok) end)
  ns.on("NAME_PLATE_UNIT_REMOVED", function(tok) B.dropToken(tok) end)
  ns.on("PLAYER_ENTERING_WORLD", function()
    local ok, inside, kind = pcall(IsInInstance)
    if ns.issecret(inside) then inside = "secret" end
    if ns.issecret(kind) then kind = "secret" end
    ns.dbg("ZONE instance " .. (ok and (tostring(inside) .. " " .. tostring(kind)) or "?"))
    B.saidFallback = nil
  end)
  for _, e in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "PET_ATTACK_START", "PET_ATTACK_STOP" }) do
    ns.on(e, function()
      if e == "PET_ATTACK_START" or e == "PET_ATTACK_STOP" then ns.dbg("ATTACK event " .. e) end
      P.update()
    end)
  end
  ns.on("UNIT_PET", function(unit)
    if unit == "player" then
      B.since = nil
      P.impSeen, P.petCasting, P.attackOn, P.stallSaid, P.lastPetEvent = nil, nil, nil, nil, nil
      P.update()
    end
  end)
  ns.on("PLAYER_REGEN_DISABLED", function() P.idleSince = nil P.update() end)
  ns.on("PLAYER_REGEN_ENABLED", function()
    ns.Alert.set("idle", false)
    ns.Alert.set("brand", false)
    B.since = nil
    P.idleSince = nil
    P.checkHP() -- stays only with "also out of combat"
  end)
  for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
    ns.on(e, function(unit) if unit == "pet" then P.checkHP() end end)
  end
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
