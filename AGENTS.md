# AGENTS.md – Warlock Pet & Proc Management

Working guide for coding agents on this repo. **Warlock Pet & Proc Management** is a warlock-only addon for **World of Warcraft: Forever** (client 1.60.x): pet management now, proc management later. The maintainer is Nico. Its sibling project is **DotWatch** (`../DotWatch`, https://github.com/nkumnberlin/DotWatch); that repo's `AGENTS.md` holds the full list of what Forever allows and the proven techniques. This file repeats what matters here.

Docs and code comments are in **English**. Reply to Nico in the language he writes in (German or English, often dictated, so expect typos – "VOV" = WoW).

---

## 1. Hard rules (same as DotWatch)

1. **Never write Blizzard globals or Blizzard tables** (no `StaticPopupDialogs[...]`, no `tinsert(UISpecialFrames, ...)`). Only the addon's own globals (SavedVariables, slash command, named frames).
2. **Never compare, do math on, or store secret values.** Hand them to widgets.
3. **Never read the geometry of anything that has ever shown a secret value.** Positions are our own numbers.
4. **No combat log** (`COMBAT_LOG_EVENT_UNFILTERED` = ADDON_ACTION_FORBIDDEN). Build on own casts and unit events.
5. **Probe before you build** when it's unclear what Forever allows (DotProbe pattern, see DotWatch).
6. **Wrap risky UI/API calls in `pcall`**; event handlers run through `ns.on` (Core.lua), which already does.
7. **Lua 5.1.** Code lives in several files sharing the addon table `ns`; no new top-level globals.
8. **Only Forever data for game facts** (spells, talents, durations).
9. **Release only what Nico tested in game and explicitly OK'd.**
10. **Before deleting anything:** list what would go and wait for Nico's OK.
11. **Classic Blizzard look**, game textures and icons only.
12. **No chat prints from combat** (`ns.sayLater`): in dungeon fights they tainted the chat-tab fade (DotWatch 0.23.1).

Unlike DotWatch this addon is **warlock-only by design**: on other classes it loads, says so once and stays idle.

---

## 2. Forever facts this addon is built on

- **Pet mode:** `GetPetActionInfo(slot)` → token `PET_MODE_PASSIVE` with `isActive`. Some clients put a subtext before the texture, then `isActive` is one position further (handled in `P.readPassive`). Forever's modes: `PET_MODE_PASSIVE`, `PET_MODE_DEFENSIVEASSIST`, `PET_MODE_ASSIST`. Events: `PET_BAR_UPDATE`, `PET_UI_UPDATE`, `UNIT_PET`. ⚠️ Not yet confirmed in our own log whether it stays readable in combat; a secret/unreadable answer keeps the last known state (`PASSIVE` debug lines).
- **Pet attacking (0.1.1):** Nico keeps his pet on Passive on purpose and sends it in with Attack, so the warning is "pet not attacking", not "pet on passive". Signals: `IsPetAttackActive()` (+ `PET_ATTACK_START/STOP`), a pet `UNIT_SPELLCAST_SUCCEEDED` in the last 3 s (Imp Firebolt); if the attack state is unreadable, a living enemy as `pettarget` counts. ⚠️ Not yet confirmed on Forever whether `IsPetAttackActive` is plain in combat and true for the Imp (`ATTACK` debug lines say which signal answered).
- **Imp stall (0.3.1):** Nico saw no warning while his pet was in the fight but did nothing: `IsPetAttackActive()` stays true then (Attack on, pet out of range/sight, out of mana, CC'd). The 2026-11-25 log shows the plain case works mid-fight (PET_ATTACK_STOP → `ALERT idle on` 1.6 s later). So for the **Imp** (`UnitCreatureFamily` Imp/Wichtel, or a Firebolt cast since summon) Attack on + no pet cast event (START/SUCCEEDED/STOP/INTERRUPTED…) for 3.5 s counts as not attacking; grace restarts on Attack on and on `UNIT_TARGET pet`; then the normal 1.5 s delay. Melee pets aren't judged: `ATTACK <family>: attack on, no pet cast for 5.0s (not judged)` logs it, to learn later what Forever shows for them. ⚠️ Not yet confirmed that pet `UNIT_SPELLCAST_START` fires and `UnitCreatureFamily("pet")` is readable on Forever (`ATTACK pet is an Imp` / `no Imp cast for` lines).
- **Pet health (0.1.2):** ⚠️ not known yet whether `UnitHealth("pet")` is secret in fights on Forever (enemy health is). Readable → compared in `P.checkHP` (threshold, 3 % hysteresis, sound). Secret → the "hp" line sits in a clip frame over the empty part of an invisible 200,000 px StatusBar fed with the secret health (the kill-skull idea from DotWatch), so the game decides visibility; no sound, the line keeps its slot (it is the last kind). `HP readable` / `HP secret` debug lines.
- **Talents:** the classic talent API is missing on Forever. `IsPlayerSpell(1293695)` = Demonic Brand learned (DotProbe 0.7).
- **Demonic Brand** (Demonology talent, 3 ranks): Searing Pain brands the enemy for **10 s**; rank 3 = the pet's next **6** attacks deal bonus fire/shadow damage. It is a **debuff on the enemy**, `UNIT_AURA added` in the same frame as Searing Pain's SUCCEEDED; **not readable in combat**. It ran out at ~10 s in the probe; an early end by used-up charges was likely but not proven.
- **Resist:** a failed cast gets `UNIT_COMBAT` MISS/RESIST/IMMUNE/EVADE on that enemy in the same frame (≤ 0.02 s) and no `UNIT_AURA added`.
- **Empowered pet hit:** fire/shadow `UNIT_COMBAT WOUND` + `UNIT_AURA updated` on the branded enemy in the same frame (Imp: Firebolt hits twice, one update).
- **Pet casts** are readable (`UNIT_SPELLCAST_SUCCEEDED` for `pet`, with spell ID).
- **Instances (confirmed by Nico's dungeon log, 2026-11-23):** enemy names/GUIDs are secret; `UnitIsUnit` matched `target` with nameplates, but `pettarget` never matched the branded enemy. So since 0.1.4 the brand check uses a **time rule** whenever the pet's target has no readable GUID: any brand applied in the last 10 s (or a Searing Pain on its way) counts; brands are kept until their 10 s end even when their enemy can't be followed. Known limit: a brand on another enemy also counts there. Open world stays per enemy (GUIDs). **Pet health is secret in fights** there too (`HP secret`) → the low-health warning runs through the gate, without sound.
- **Game aura engine (0.2.0):** `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")`, `AddAuraGroup(key, "HARMFUL|PLAYER", {candidateFilters = {includeSpellIDs = {[id] = true}}, maxFrameCount = 1, layout = {elementWidth, elementHeight}, initializeFrame})`, `SetUnit("pettarget")`, `SetEnabled(true)`, `UpdateAllAuras()` (no aura events for pettarget: refreshed on UNIT_TARGET pet, any UNIT_AURA while the line is up, every 0.4 s). The brand line's text sits in a clip from the container's right edge to the line's right edge: the container is only wide while our brand is on the pet's target, so the game hides the line then (idea from ForeverAuras' "Aura(s) Missing", SecretAuraSingle.lua). The addon can't know whether it shows: the line is up "quiet" while a brand of the last 10 s exists, with sound only when none does. **Confirmed in game (Nico, dungeon, 2026-11-23):** the engine follows `pettarget`, debuff ID **1293696** is the brand on the enemy, and the line disappears while the brand is on the pet's target. The container's width reads 0 once, then is secret (the addon can't learn presence from it). Same log: `UnitIsUnit("pettarget", "target")` is secret, `UnitIsUnit(<enemy>, "nameplateN")` vs pettarget is nil. `/wpm brandid <id>` stays for testing. `ENGINE` and `BRAND why ... engine ..., width ...` debug lines.
- **Decimation (0.3.0)** (Demonology talent, tier 4, 2 ranks; foreverchanges.pro build 1.60.1.71037 + Wowhead Forever): Shadow Bolt or Searing Pain on an enemy **below 35 %** → for **10 s** Soul Fire casts 20 % / 40 % faster and costs no Soul Shard; the talent also cuts Soul Fire's cooldown 45 % / 90 % and gives SB/SP 3 % / 6 % damage there. Spell **440870** = the talent's passive (hidden aura, same name as the proc; rank values in one trait node). Soul Fire IDs 6353 / 17924. ⚠️ Not known: the **proc buff's spell ID** (on no site), whether your own buffs read in combat, whether the client's spell info shows the faster cast time (the reduction is a server-side dummy effect on Wowhead), whether Soul Fire glows. So `Procs.lua` asks three signals: the buff (by name out of combat, skipping 440870; then by learned ID → `db.learned.deciBuff`), the Soul Fire glow (overlay events + `IsSpellOverlayed`), Soul Fire's cast time ÷ Searing Pain's (haste-free) under 90 % of the highest seen. A readable buff decides alone. Enemy health is secret, so "below 35 %" is never checked by the addon. `PROC` debug lines say which signal answered and how long after SB/SP.

---

## 3. Code layout

| File | What |
|---|---|
| `WarlockPetAndProcManagement.toc` | load order: Strings → Strings_deDE → Core → Alerts → Pet → Procs → Options |
| `Strings.lua`, `Strings_deDE.lua` | `ns.L` (English keys, frozen at ADDON_LOADED), German texts |
| `Core.lua` | helpers (`ns.plain/str/num`), defaults, event hub `ns.on`, hooks `ready`/`login`, debug log, `/wpm` |
| `Alerts.lua` | `ns.Alert`: on-screen warning lines (text, size, color, icon, pulse), sounds, move mode, test, the secret-health gate |
| `Pet.lua` | `ns.Pet`: pet-not-attacking check (`P.attackState`), Demonic Brand tracking (`P.brand`), low pet health (`P.checkHP`), 0.2 s ticker |
| `Procs.lua` | `ns.Procs`: Decimation proc (`R.deci`: buff / glow / cast-time signals, `D.check`), 0.2 s ticker |
| `Options.lua` | `ns.Options`: options window (700 × 520, nav left: General, Pet management, Proc management), AddOns settings entry, minimap button |

- SavedVariables `WarlockPetAndProcManagementDB`: `locked`, `pos = {x, y}` (top center of the warnings), `lang`, `debugChat`, `minimap`, `idle{...}` (pet not attacking; was `passive` in 0.1.0, migrated on load), `brand{...}`, `hp{...}` (+ `threshold`, `ooc`), `deci{...}` (0.3.0), `learned{deciBuff}` (spell IDs found in game; survives `/wpm reset`), `debug` (last 500 lines) + `debugPrev`.
- Per-warning settings: `on, text (nil = default), size, color, icon, pulse, sound, soundKey, repeatSec, delay`; brand also `charges`, `engine` (0.2.0, default on), `debuffID` (nil = 1293696) (experimental, off by default).
- Debug tags: LOAD, LOGIN, PET, ATTACK, HP, GATE, ENGINE, ZONE, ALERT, BRAND, PROC, TALENT, SETTINGS, ERROR.
- Warning kinds top to bottom: `idle`, `brand`, `deci`, `hp` (`hp` last: its gated line keeps its slot). New procs go into `Procs.lua`, `Alert.KINDS` before `hp` and the "Proc management" nav group.

---

## 4. Checks before a commit

- Compile every file with LuaJIT (`loadstring`).
- Mock run with a stubbed WoW API (pet attacking or idle in and out of combat, settings migration, pet health readable and secret, brand start/expiry/resist, secret GUIDs, options window; Decimation by cast time, haste, glow, buff learned after a fight, buff readable/unreadable in combat).
- Same keys in every language, every key used, `%s/%d` identical.

---

## 5. Git, install and release

Same workflow as DotWatch: bump `## Version:` in the TOC → install into Nico's Forever AddOns folder (`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\WarlockPetAndProcManagement`) → commit + push to `main`. After Nico's in-game OK: `git push origin main:release` → `tag-release.yml` creates tag `v<version>` → CurseForge packages it (`.pkgmeta`). Experimental features ship switched off and labeled "(experimental)". Commit identity: `nkumnberlin` + `nkumnberlin@users.noreply.github.com`.
