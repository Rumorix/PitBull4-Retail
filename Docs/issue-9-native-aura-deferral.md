# Issue #9: native aura combat deferral

This Retail checkout identifies itself as Midnight 12.1.5 P010 in README.md;
the issue's P008 baseline is historical. Source inspection confirms an
unconditional combat success result, but does not reproduce missing auras.

`Modules/Aura/NativeContainer_12_1.lua` now returns `nil, "deferred"` during
combat unless both groups completed configuration for the current public unit
token. Successful configuration marks addon-owned readiness independently of
the optional geometry cache; detaching a group clears readiness. Intentionally
disabled groups count as configured. Existing configured containers continue
to report success while layout/filter mutations wait until combat ends.

The renderer wrapper returns immediately on deferral, preserving legacy buttons
and highlights without recording an API failure or entering legacy fallback.
Actual failures retain their existing handling, including the prohibition on
unfiltered fallback for native-filter layouts. Existing PLAYER_REGEN_ENABLED
UpdateAll handling reconciles current frames and settings after combat.
No saved-profile schema or protected API calls were added.

## Local validation

- `python3 -m unittest discover -s Tests -v`: four tests passed, including two
  Lua 5.1 mocked native-aura checks in `Tests/test_native_aura_deferral.py`.
- `luac5.1 -p Modules/Aura/NativeContainer_12_1.lua`: passed.
- `git diff --check`: passed.

The mocked tests execute extracted source functions. They cover missing and
partial state, detachment, unit-token reuse, prepared and intentionally disabled
groups, deferred cleanup suppression, simulated postcombat recovery, actual
failure handling, native-filter fallback restrictions, and readiness without
caching secret geometry. They do not emulate WoW's secure implementation.

## Risk and remaining validation

**In-game test needed; no WoW tests were run.** Verify on Retail 12.1.5:

- Prepared absent bosses appearing during combat, and any reachable missing or
  detached native state for newly created/reused boss and raid frames.
- Aura additions/removals, repeated combat transitions, hiding/reappearance,
  unit-token rebinding and configuration changes deferred until combat ends.
- Automatic postcombat recovery, no duplicate rows or stale auras, correct
  native filters, and no taint, protected-action or secret-value errors.

Deferral cannot create missing native containers in combat. Existing legacy
visuals can remain until reconciliation; the change corrects status and cleanup,
not the unverified underlying reachability or visual impact. UNIT_AURA routing
and legacy ticker policy remain unchanged. No package/build or live-client
validation was performed, and no distribution artifact was produced.

Rollback: revert the Lua changes and remove the accompanying test/document.
No profile migration or release metadata change is required.
