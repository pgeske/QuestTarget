# QuestTarget

A small WoW: Forever add-on for [Questie](https://github.com/Questie/Questie) users. Right-click a quest or an objective in Questie's tracker, pick **Set as macro target**, and one action-bar macro targets the mobs and NPCs that quest needs.

## How it works

- **Pick what to hunt.** Questie's tracker menu gets a **Set as macro target** entry on each quest (everything it still needs) and on each objective (just that one).
- **One macro, always current.** The add-on writes a character macro named `QuestTarget`. Drag it to an action bar once; after that it rewrites itself:
  - as objectives finish, it moves on to what's left;
  - when the quest is complete, it targets the turn-in NPC;
  - when you turn in or abandon the quest, it clears.
- **Nearest first.** A macro holds 255 characters, so when a quest has many sources the nearest ones are kept, and the nearest one wins.
- **Creatures only.** Macros can't target game objects (chests, plants), so those are skipped. Dead targets are cleared so the button doesn't re-select a corpse.

Macros can't be changed in combat, so updates that happen mid-fight apply as soon as combat ends.

## Commands

- `/qtarget` refreshes the macro.
- `/qtarget clear` stops targeting.

## Install

Copy this folder to `World of Warcraft/_forever_/Interface/AddOns/QuestTarget`, then `/reload`. Requires Questie Forever.

## License

MIT
