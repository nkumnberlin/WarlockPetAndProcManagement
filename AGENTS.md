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
- **Talents:** the classic talent API is missing on Forever. `IsPlayerSpell(1293695)` = Demonic Brand learned (DotProbe 0.7).
- **Demonic Brand** (Demonology talent, 3 ranks): Searing Pain brands the enemy for **10 s**; rank 3 = the pet's next **6** attacks deal bonus fire/shadow damage. It is a **debuff on the enemy**, `UNIT_AURA added` in the same frame as Searing Pain's SUCCEEDED; **not readable in combat**. It ran out at ~10 s in the probe; an early end by used-up charges was likely but not proven.
- **Resist:** a failed cast gets `UNIT_COMBAT` MISS/RESIST/IMMUNE/EVADE on that enemy in the same frame (≤ 0.02 s) and no `UNIT_AURA added`.
- **Empowered pet hit:** fire/shadow `UNIT_COMBAT WOUND` + `UNIT_AURA updated` on the branded enemy in the same frame (Imp: Firebolt hits twice, one update).
- **Pet casts** are readable (`UNIT_SPELLCAST_SUCCEEDED` for `pet`, with spell ID).
- **Instances:** enemy names/GUIDs are secret; `UnitIsUnit` between tokens still works. So a brand is remembered by GUID **and** by the tokens that point at its enemy (target, focus, pettarget, nameplates); a token is dropped/re-checked on its change event.

---

## 3. Code layout

| File | What |
|---|---|
| `WarlockPetAndProcManagement.toc` | load order: Strings → Strings_deDE → Core → Alerts → Pet → Options |
| `Strings.lua`, `Strings_deDE.lua` | `ns.L` (English keys, frozen at ADDON_LOADED), German texts |
| `Core.lua` | helpers (`ns.plain/str/num`), defaults, event hub `ns.on`, hooks `ready`/`login`, debug log, `/wpm` |
| `Alerts.lua` | `ns.Alert`: on-screen warning lines (text, size, color, icon, pulse), sounds, move mode, test |
| `Pet.lua` | `ns.Pet`: passive check, Demonic Brand tracking (`P.brand`), 0.2 s ticker |
| `Options.lua` | `ns.Options`: options window (700 × 520, nav left), AddOns settings entry, minimap button |

- SavedVariables `WarlockPetAndProcManagementDB`: `locked`, `pos = {x, y}` (top center of the warnings), `lang`, `debugChat`, `minimap`, `passive{...}`, `brand{...}`, `debug` (last 500 lines) + `debugPrev`.
- Per-warning settings: `on, text (nil = default), size, color, icon, pulse, sound, soundKey, repeatSec`; brand also `delay`, `charges` (experimental, off by default).
- Debug tags: LOAD, LOGIN, PET, PASSIVE, ALERT, BRAND, TALENT, SETTINGS, ERROR.
- Proc management will get its own file (`Procs.lua`), its own warning kinds in `Alert.KINDS` and its own nav group.

---

## 4. Checks before a commit

- Compile every file with LuaJIT (`loadstring`).
- Mock run with a stubbed WoW API (passive on/off in and out of combat, brand start/expiry/resist, secret GUIDs, options window).
- Same keys in every language, every key used, `%s/%d` identical.

---

## 5. Git, install and release

Same workflow as DotWatch: bump `## Version:` in the TOC → install into Nico's Forever AddOns folder (`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\WarlockPetAndProcManagement`) → commit + push to `main`. After Nico's in-game OK: `git push origin main:release` → `tag-release.yml` creates tag `v<version>` → CurseForge packages it (`.pkgmeta`). Experimental features ship switched off and labeled "(experimental)". Commit identity: `nkumnberlin` + `nkumnberlin@users.noreply.github.com`.
