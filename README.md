# DotRange

World of Warcraft addon (Retail 12.1, Midnight) that shows the distance to your current target as three colored boxes.

| Boxes | Color (default) | Meaning |
|---|---|---|
| 3 | Green | Melee range (~5 yd) |
| 2 | Yellow | Medium distance (~13–30 yd, depending on class) |
| 1 | White | Target visible, but further away |
| 0 | Dark | No target / target not visible |

<!-- Screenshot: display in combat -->

## Installation

Download the zip from the [Releases](../../releases) page and extract it to `World of Warcraft\_retail_\Interface\AddOns\`.

The zip contains all required libraries. A plain copy of the repository does **not** work, because the libraries are only added by the packager.

## Usage

- **Settings:** type `/dotrange` or open *Settings > AddOns > DotRange*. Changes apply immediately.
- **Position:** drag the boxes with the left mouse button. With *Lock position* enabled, they can no longer be moved and clicks go through them.
- **Settings are stored per character.** Settings from DotRange 2.x are taken over automatically on the first start of 3.0.

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

- **Friendly targets:** the spells only work on hostile targets, so friendly targets show at most 1 box.
- **Ranged and healer specializations** without matching spells (for example Beast Mastery/Marksmanship hunters, mages, priests) show at most 1 box.
- **Secret values (Midnight):** if the game returns the range check as a protected ("secret") value, DotRange does not evaluate it and treats it as out of range. Whether this happens in combat in instances has not been tested yet; the debug mode records it.

## Development

Libraries are fetched by the [BigWigs packager](https://github.com/BigWigsMods/packager) from `.pkgmeta` and are not part of the repository: LibStub, CallbackHandler-1.0, AceDB-3.0, AceDBOptions-3.0, AceGUI-3.0, AceConfig-3.0, LibEditMode.

### Releases

Pushing a tag `v*` (for example `v3.0.0`, test builds `v3.0.0-alpha.N`) starts `.github/workflows/release.yml`. It builds a zip with all libraries and publishes it as a GitHub release.

**CurseForge upload (optional):** the workflow already passes `CF_API_TOKEN` to the packager. The packager only uploads to CurseForge when both a token and a project ID are present. To enable it, add an Actions secret named `CF_API_TOKEN` and replace the line `# ## X-Curse-Project-ID:` in `DotRange.toc` with `## X-Curse-Project-ID: <your project ID>`.

## License

MIT, see [LICENSE](LICENSE).
