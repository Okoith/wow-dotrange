# Changelog

## 3.2.0

- **M+ statistics per section:** the end-of-run window now lists every section in the order you played it, like WarpDeplete: trash, first boss, trash, second boss, and so on, each with its percentage in range and your best for that section. Trash counts towards the next boss you pull; trash after the last boss is a separate section. A wipe and the next attempt count as the same boss section.
- Boss names come from the encounter, the dungeon journal or the scenario objectives; if none is readable, the boss is shown as "Boss N". The dungeon journal window is never opened.
- Sections are stored per character and dungeon, with best, average and last value. Existing statistics remain valid.
- **Fixed:** the window could show "Unknown dungeon". The start event reports the instance ID, not the keystone dungeon ID. The dungeon is now always taken from the active keystone (or from the completion info at the end of the run), with the instance name as a fallback.
- Statistics recorded with 3.1.0 under the instance ID are moved to the correct dungeon automatically (merged if both exist).
- The window adapts its height to the number of sections and has wider columns.

## 3.1.0

- **Mythic+ statistics "time in range":** during a Mythic+ run, DotRange measures how much of your combat time your target was in melee range (3 boxes; for Devourer: Consume). At the end of the run, a small window shows the result for total, bosses and trash, compared with your best and average in that dungeon. New bests are highlighted.
- Only completed runs with at least 30 seconds of counted combat time are stored, per character and dungeon. Aborted runs are shown but not stored. The measurement continues after a `/reload`.
- New settings tab *M+ statistics*: record statistics, show window at the end of the run, show last run, overview per dungeon, reset statistics.
- New commands: `/dotrange stats` and `/dotrange stats reset`.
- **Devourer Demon Hunter:** own range levels, see 3.1.0-alpha.1 below.

## 3.0.3

- Addon icon in the AddOns list.

## 3.1.0-alpha.1

Test build.

- **Devourer Demon Hunter:** the new ranged Devourer specialization gets its own range levels: 3 boxes with Consume in range (25 yd), 2 boxes with Disrupt (30 yd), 1 box with Voidblade (35 yd). Beyond 35 yd, all boxes are inactive. For the other Demon Hunter specializations nothing changes; Disrupt stays in their melee list.
- DotRange is now made for melee classes and specializations, plus Devourer Demon Hunter.
- Range levels are chosen per specialization and updated when you change your specialization.
- Automatic hiding and `/dotrange check` take the Devourer range levels into account; `/dotrange check` also shows the current specialization.
- Debug mode logs the specialization ID and, for Devourer, the result of each range check.

## 3.0.1

- CurseForge project ID added, automatic uploads to CurseForge.

## 3.0.0

DotRange 3.0 keeps the familiar three boxes and range logic of 2.1 and brings a settings menu, WoW Edit Mode support, visibility rules, profiles and an English and German translation.

### Features

- **Three boxes** show the distance to your target: 3 green boxes in melee range, 2 yellow boxes at medium distance, 1 white box when the target is visible but further away. The range check uses several class-specific spells; one of them being in range is enough.
- **Edit Mode:** move the display in WoW's Edit Mode (*Esc > Edit Mode*); the position is saved per layout. The Edit Mode dialog has a scale slider and a *More settings* button. An optional lock prevents moving, even in Edit Mode. While editing, a sample with three green boxes is shown, regardless of target and visibility rules.
- **Settings menu** under *Settings > AddOns > DotRange* or with `/dotrange`. All changes apply immediately.
- **Visibility:** always, only in combat, only in instances, or only in a group; optionally hidden in vehicles; always hidden during pet battles.
- **Target options:** hide without a target; new option to show the display only for hostile targets.
- **Automatic hiding:** if your character knows none of the spells used for the range check (for example a mage or a Beast Mastery hunter), the display is hidden and the menu shows a note. This is checked again when your specialization or spells change.
- **Appearance:** colors for melee, just outside, medium distance, inactive boxes and border; box size, border width, scale and opacity.
- **Profiles:** settings are stored per character; copy them from another character or reset them.
- **Languages:** English and German.
- **Debug mode** (off by default) that writes a log to the SavedVariables; `/dotrange check` prints the range check for the current target in the chat.

### Changes since 2.1

- Your settings from 2.x are taken over automatically on the first start. Your previous position becomes the starting position in every Edit Mode layout.
- The display is moved in Edit Mode only. Outside Edit Mode, mouse clicks always go through it.
- The old settings window has been replaced by the settings menu.
- `/dotrange` opens the settings instead of showing or hiding the display. The previous `/dotrange debug` output is now `/dotrange check`.
- Leftover files from older versions (`Config.lua`, `DotRange.lua`) are no longer loaded and can be deleted from the `DotRange` folder.

### Changes since 3.0.0-alpha.2

- Edit Mode support (LibEditMode) with position per layout, scale slider, *More settings* button, lock and a sample display.
- Moving the display with the mouse outside Edit Mode has been removed.
- New menu options: *Scale* and *Reset position*.

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
