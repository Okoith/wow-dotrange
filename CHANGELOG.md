# Changelog

## 3.0.0-alpha.2

Test build for milestone 2.

- New settings menu under *Settings > AddOns > DotRange* (AceConfig), opened with `/dotrange`. All changes apply immediately. The old settings window has been removed.
- Profiles: switch, copy from another character, or reset (AceDBOptions).
- Visibility: always, only in combat, only in instances, or only in a group; optionally hidden in vehicles; always hidden during pet battles.
- New option *Only for hostile targets* (off by default).
- If your character knows none of the spells used for the range check, the display is hidden automatically and the menu shows a note. This is checked again when your specialization or spells change. With only medium-range spells, the display shows at most 2 boxes.
- Debug mode can also be switched on and off in the menu.
- The chat message for classes without spells on login has been replaced by the note in the menu.

## 3.0.0-alpha.1

Test build for milestone 1. The display works as in 2.1.

- The addon is now split into several files and uses AceDB-3.0 for its settings (still per character by default).
- Settings from 2.x (`DotRangeCharDB`) are taken over automatically on the first start. The old data is kept and only marked as migrated.
- English is the default language, German is included as a translation.
- `/dotrange` now opens the settings. `/dotrange help` lists the commands. Showing and hiding the display with `/dotrange` has been removed.
- The previous chat output of `/dotrange debug` is now `/dotrange check`.
- New debug mode (`/dotrange debug on|off|clear|status`, off by default). It writes a log to the SavedVariables (`DotRangeDebugLog`, at most 5000 entries): version, build, class, specialization, known spells, combat start and end, instance changes, errors, and once per second in combat the range result of every spell. Protected ("secret") values are never stored, only marked as `<SECRET>`.
- All range and unit checks are protected against errors and secret values.
- Release packaging with the BigWigs packager (GitHub release on tag `v*`).
- License: MIT.

## 2.1

- Several candidate spells per class and specialization; hunter spell ID fixed, warrior gap between 5 and 8 yards closed, druid and shaman added
- Locked display lets mouse clicks through; position no longer stored twice
- Option "Hide without target"; reset refreshes the open settings window
- Protection against secret values (Midnight 12.0)
