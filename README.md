# Warlock Pet & Proc Management

A warlock addon for **World of Warcraft: Forever**. It watches your demon and warns you on screen (with an optional sound) when something is wrong. Proc management comes in a later version.

## Features (v0.1.0)

**Passive pet**
- When a fight starts and your demon is set to **Passive**, a warning appears in the middle of the screen.
- Also when you set it to Passive or summon it on Passive during a fight. The warning goes away when you change the mode, the pet is gone or the fight ends.

**Demonic Brand** (Demonology talent)
- Only when you have the talent learned.
- When your pet attacks an enemy **without your brand** (never branded, or the 10 seconds ran out), a warning appears. It goes away as soon as your Searing Pain lands on that enemy, and it waits while a Searing Pain is on its way.
- Resisted Searing Pains don't count as a brand.
- Works in dungeons too (enemies are told apart by target, focus, pet target and nameplates).
- *Experimental, off by default:* count the pet's 6 empowered attacks and end the brand early when they are used up.

**For every warning**
- Your own message (`{pet}` = your pet's name), text size, color, icon, pulse.
- Optional sound (10 game sounds, soft to loud), played once or repeated every few seconds.
- Live preview in the options, "Show on screen" test, move mode to place the warnings anywhere.

## Usage

- `/wpm` – options (also the minimap button or Escape › Options › AddOns)
- `/wpm test` – show the warnings for 5 seconds
- `/wpm unlock` / `/wpm lock` – move the warnings
- `/wpm status` – pet, pet mode, talent, running brands
- `/wpm help` – all commands

Languages: English, German.

## Limits

WoW Forever hides the combat log and enemy debuffs in combat. The brand is tracked from your own Searing Pain casts (10 seconds), not read from the enemy. Brands from other warlocks don't count.

## Feedback

Bugs and ideas: [GitHub issues](https://github.com/nkumnberlin/WarlockPetAndProcManagement/issues). Please add your `WTF/Account/<account>/SavedVariables/WarlockPetAndProcManagement.lua` (after `/reload` or logout) – it has a debug log.

## License

MIT
