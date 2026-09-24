# DotRange

<p align="center"><img src="docs/dotrange.jpg" alt="DotRange logo" width="256"></p>

World of Warcraft addon (Retail 12.1, Midnight) that shows the distance to your current target as three colored boxes.

| Boxes | Color (default) | Meaning |
|---|---|---|
| 3 | Green | Melee range (~5 yd) |
| 2 | Yellow | Medium distance (~13–30 yd, depending on class) |
| 1 | White | Target visible, but further away |
| 0 | Dark | No target / target not visible |

<!-- Screenshot: display in combat -->
<!-- Screenshot: settings menu -->
<!-- Screenshot: Edit Mode with the DotRange dialog -->

## Features

- **Three boxes** for melee range, medium distance and "visible but far away", with class-specific range checks
- **Edit Mode:** move the display in WoW's Edit Mode, position saved per layout, scale slider, option to lock it; a sample with three green boxes is shown there
- **Visibility:** always, only in combat, only in instances, or only in a group; optionally hidden in vehicles; always hidden during pet battles
- **Target options:** hide without a target, show only for hostile targets
- **Automatic hiding** for classes and specializations without matching spells
- **Appearance:** colors for every range level, inactive boxes and border; box size, border width, scale, opacity
- **Profiles:** settings per character, copy them from another character
- **Languages:** English and German

## Installation

Download the zip from the [Releases](../../releases) page and extract it to `World of Warcraft\_retail_\Interface\AddOns\`.

The zip contains all required libraries. A plain copy of the repository does **not** work, because the libraries are only added by the packager.

### Updating from an older version

Your settings from DotRange 2.x are taken over automatically on the first start of 3.0. Your previous position is used as the starting position in every Edit Mode layout.

Extracting the new version over an old one leaves files behind that DotRange no longer uses. They are not loaded and can be deleted from the `DotRange` folder:

- `Config.lua` (settings window from 3.0.0-alpha.1)
- `DotRange.lua` (DotRange 2.x)

Alternatively, delete the whole `DotRange` folder before extracting the new version. Your settings are stored elsewhere (in `WTF`) and are kept.

## Usage

- **Settings:** type `/dotrange` or open *Settings > AddOns > DotRange*. Changes apply immediately. The settings cannot be opened during combat.
- **Position:** open WoW's Edit Mode (*Esc > Edit Mode*) and drag the DotRange frame. Clicking it opens a dialog with a scale slider and a *More settings* button. The position is saved per Edit Mode layout. With *Lock* enabled, the frame cannot be moved, not even in Edit Mode. Outside Edit Mode, mouse clicks always go through the display.
- **Edit Mode preview:** in Edit Mode the display always shows three green boxes, regardless of target, visibility rules and automatic hiding, so you can place it without a target.
- **Visibility:** always, only in combat, only in instances, or only in a group; optionally hidden in vehicles; always hidden during pet battles.
- **Target:** optionally hidden without a target, and optionally only shown for hostile targets.
- **Classes without matching spells:** if your character knows none of the spells below (for example a mage or a Beast Mastery hunter), the display is hidden automatically and the settings show a note. This is checked again when you change your specialization or talents.
- **Profiles:** settings are stored per character; copy them from another character or reset them.

### Settings

- **General:** hide without target, only for hostile targets, visibility, hide in vehicles, lock, reset position, debug mode
- **Appearance:** colors (melee, just outside, medium distance, inactive, border), box size, border width, scale, opacity
- **Profiles:** switch, copy from another character, reset

## Commands

| Command | Effect |
|---|---|
| `/dotrange` | Open the settings |
| `/dotrange help` | List the commands |
| `/dotrange check` | Print the range check for the current target in the chat |
| `/dotrange debug on\|off\|clear\|status` | Debug log (`DotRangeDebugLog` in SavedVariables, off by default) |

## How it works

The distance is determined with `C_Spell.IsSpellInRange` and class-specific spells. Each range level has several candidates; one of them being in range is enough. Spells your character does not know (other specialization, talent, form) return no result and are ignored.

| Class | Melee | Medium distance |
|---|---|---|
| Warrior | Pummel | Taunt (30 yd), Charge (8–25 yd) |
| Rogue | Kick | Shadowstep (25 yd), Pistol Shot (20 yd) |
| Paladin | Rebuke, Crusader Strike | Hand of Reckoning (30 yd) |
| Monk | Spear Hand Strike | Provoke (30 yd) |
| Death Knight | Death Strike | Death Grip (30 yd) |
| Demon Hunter | Chaos Strike, Shear, Disrupt | Throw Glaive (30 yd), Torment (30 yd) |
| Hunter (Survival) | Muzzle, Raptor Strike | Harpoon (8–30 yd) |
| Druid (Cat/Bear) | Shred, Mangle | Growl (30 yd), Skull Bash (13 yd) |
| Shaman | Stormstrike, Lava Lash | Wind Shear (30 yd) |

## Known limitations

- **Friendly targets:** the spells only work on hostile targets, so friendly targets show at most 1 box. Enable *Only for hostile targets* to hide the display for them.
- **Secret values (Midnight):** in tests, the range check was readable in combat, in the open world and in dungeons. Should the game ever return it as a protected ("secret") value, DotRange treats it as out of range instead of causing an error.

## Development

Libraries are fetched by the [BigWigs packager](https://github.com/BigWigsMods/packager) from `.pkgmeta` and are not part of the repository: LibStub, CallbackHandler-1.0, AceDB-3.0, AceDBOptions-3.0, AceGUI-3.0, AceConfig-3.0, LibEditMode.

### Releases

Pushing a tag `v*` (for example `v3.0.0`, test builds `v3.0.0-alpha.N` or `v3.0.0-beta.N`) starts `.github/workflows/release.yml`. It builds a zip with all libraries and publishes it as a GitHub release.

**CurseForge upload (optional):** the workflow already passes `CF_API_TOKEN` to the packager. The packager only uploads to CurseForge when both a token and a project ID are present. Without them, only the GitHub release is created. To enable the upload:

1. Create an API token at <https://authors.curseforge.com/#/settings/api-tokens>.
2. In the GitHub repository, add it as an Actions secret named **`CF_API_TOKEN`** (*Settings > Secrets and variables > Actions > New repository secret*).
3. In `DotRange.toc`, replace the line `# ## X-Curse-Project-ID:` with `## X-Curse-Project-ID: <your project ID>`.

## License

MIT, see [LICENSE](LICENSE).
