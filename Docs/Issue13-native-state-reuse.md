Issue #13: native aura state reuse

Inspected source: Retail/Midnight WoW 12.1.5, README identifies P010.
The report names P008; equivalence to that baseline was not established.

Signature edits previously discarded the entire native state. The correction
keeps at most two retired, successfully configured states per owner. Both group
signatures must match before acquisition. Retirement still disables containers,
detaches units, invalidates configuration and unregisters visibility drivers.
Acquisition restores drivers and runs the existing configuration path to restore
current units, limits, sorting, geometry and enabled state. Failed creation,
configuration or driver restoration does not enter the cache. Renderer disable
and explicit rebuild clear all reusable states. Combat deferral is unchanged.
No saved-profile fields or aura payload inspection are added.

This bounds cached states per owner, not cumulative client frame allocations.
Previously unseen configurations and evictions can still allocate frames.
The report does not establish a measured memory leak or player-visible impact.

Local validation:
- python3 -m unittest discover -s Tests -v: all three tests passed.
- luac5.1 -p Modules/Aura/NativeContainer_12_1.lua: passed.
- git diff --check: passed.
The new Lua 5.1 lifecycle test uses extracted production lifecycle functions and
stubbed group creation/configuration. Fifty A/B edit cycles allocate two states;
it also checks owner isolation, visibility-driver restoration, cache bounds,
combat deferral, failed configuration exclusion and explicit cache invalidation.
This does not validate Blizzard's native frame internals.

In-game test needed on Retail WoW 12.1.5 (NOT run):
Repeat layout/style/filter reversions with native rendering enabled. Check current
auras and styling without duplicates; scoped visibility, weapon enchants, unit
changes, profiles, renderer toggles and forced rebuilds; combat entry/exit and
Edit Mode transitions. Check taint, protected-action and secret-value errors.
Measure allocations/memory with stable settings and repeated edits separately.
Risk: reactivating a previously disabled protected container or visibility gate
may behave differently in the client than in stubs. Rollback: revert the Lua
change and reload the UI to discard client-created frames.
