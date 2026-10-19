# PitBull4 Retail — Midnight 12.1.5 (P008)

Community-maintained development fork of **PitBull Unit Frames 4.0** for *World of Warcraft Retail*. Current snapshot: `Midnight-12.1.5-Lorenzo-P008` (from `LORENZO_BUILD_VERSION.txt` and `PitBull4_Mainline.toc`).

## Areas of development

- Retail/Midnight WoW API compatibility, including combat-protected frames and secret values.
- Edit Mode integration, frame positioning and backup/restore support.
- Unit-frame customization, aura displays, Major Cooldown Auras and debuff visualization.
- Profile maintenance, localization and performance/regression fixes.

## Reporting bugs

Open [a bug report](../../issues/new/choose). Include your exact addon and WoW build, reproduction steps, expected versus actual behavior, and relevant error logs or screenshots. Please remove account or personal data from logs.

## Source tree and dependencies

`PitBull4_Mainline.toc` is at the root of this repository. The source archive used for this import contains **some**, but not all, external libraries specified in `.pkgmeta`. The `libs.xml` in P008 explicitly assumes some libraries are installed as **standalone addons**, or that a separate release packager injects them.

**Do not treat a raw GitHub source download as a verified self-contained installable release.** Validate/restore bundled dependencies and test the assembled package in the WoW client before distributing it. The imported source is not modified by this GitHub preparation.

## Development and releases

- Submit changes through a separate branch and pull request; do not push unreviewed fixes straight to `main`.
- WoW in-combat behavior, secret values, aura events and protected frame actions require actual in-game testing; static Lua checks cannot guarantee compatibility.
- Update release metadata (including `.toc` version fields), write English release notes, check dependencies, and obtain maintainer approval before publishing.
- Automated packaging/publishing workflows inherited from the upstream archive were deliberately removed from this initial import.
- Upstream publishing identifiers in `.toc`/`.pkgmeta` are **not** authorization to publish to the original project's CurseForge, Wago or WoWInterface listings.

## Upstream and attribution

This fork derives from the original **PitBull Unit Frames 4.0** project by its respective contributors, including the names preserved in the source metadata (`ckknight`, `Shekfi`, `Nebula`). All existing attributions are retained. **No new license is granted by this README.** Check applicable upstream rights and permissions before making this repository public or redistributing a package.
