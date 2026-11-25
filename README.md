# Warlock Pet & Proc Management

A warlock addon for **World of Warcraft: Forever**. It watches your demon and warns you on screen (with an optional sound) when something is wrong, and tells you when a proc is up.

## Features (v0.3.2)

**Pet not attacking**
- In a fight, when your pet is alive but **not attacking** – e.g. it is on Passive and you haven't sent it in yet, its target died, or your Imp has Attack on but casts nothing (out of range or sight, out of mana, crowd-controlled) – a warning appears in the middle of the screen.
- A short grace period (default 1.5 s) gives you time to send the pet in. The warning goes away as soon as the pet attacks, is gone or the fight ends. Works in every pet mode.

**Demonic Brand** (Demonology talent)
- Only when you have the talent learned.
- When your pet attacks an enemy **without your brand** (never branded, or the 10 seconds ran out), a warning appears. It goes away as soon as your Searing Pain lands on that enemy, and it waits while a Searing Pain is on its way.
- Resisted Searing Pains don't count as a brand.
- In raids and dungeons the game hides which enemy your pet attacks from addons. There the game itself checks your brand on your pet's target and shows the warning only while it is missing (v0.2.0, can be switched off). The sound comes when no brand of yours landed in the last 10 seconds. In the open world the addon checks per enemy.
- *Experimental, off by default:* count the pet's 6 empowered attacks and end the brand early when they are used up.

**Low pet health**
- A warning when your pet's health is at or below a value you set with a slider (default 30 %). It goes away when the pet is healed (3 % above the value) or gone.
- In fights by default; tick "Also out of combat" to be warned before the next pull too.
- If the game hides the pet's health in a fight, the game itself decides when the warning shows (no sound then).

**Decimation proc** (Demonology talent, new in v0.3.0)
- When your Shadow Bolt or Searing Pain on an enemy below 35 % health triggers Decimation, a warning shows "Decimation: Soul Fire now!" for as long as the proc is up (10 seconds: faster Soul Fire, no Soul Shard).
- The addon sees the proc by your Soul Fire's shorter cast time, the game's glow on Soul Fire, or the buff itself where the game lets addons read it. It learns the buff's spell ID the first time it can read it.

**For every warning**
- Your own message (`{pet}` = your pet's name), text size, color, icon, pulse.
- Optional sound (10 game sounds, soft to loud), played once or repeated every few seconds.
- Live preview in the options, "Show on screen" test, move mode to place the warnings anywhere.

## Usage

- `/wpm` – options (also the minimap button or Escape › Options › AddOns)
- `/wpm test` – show the warnings for 5 seconds
- `/wpm unlock` / `/wpm lock` – move the warnings
- `/wpm status` – pet, pet mode, attacking or not, pet health, talents, running brands, Decimation
- `/wpm help` – all commands

Languages: English, German.

## Limits

WoW Forever hides the combat log and enemy debuffs in combat. The brand is tracked from your own Searing Pain casts (10 seconds), not read from the enemy. Brands from other warlocks don't count.

## Feedback

Bugs and ideas: [GitHub issues](https://github.com/nkumnberlin/WarlockPetAndProcManagement/issues). Please add your `WTF/Account/<account>/SavedVariables/WarlockPetAndProcManagement.lua` (after `/reload` or logout) – it has a debug log.

## License

MIT
