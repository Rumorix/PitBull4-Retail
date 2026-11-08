# Issue #11: ImportantDebuffs initialization

The inspected checkout is Retail/Midnight 12.1.5; README identifies its source
snapshot as P010, later than the issue's P008 audit baseline. Static inspection
confirms that a failed construction was cached by layout signature, and the
ordinary regen update did not clear that failure. No live reproduction or
severity confirmation was supplied.

The fix in Modules/ImportantDebuffs/ImportantDebuffs.lua defers first native
container creation and layout replacement during combat lockdown. An existing
container remains active until replacement can run out of combat. The existing
UpdateAll dispatch on regen processes eligible frames with their current layout;
no profile fields or persistent queue are added. Matching active containers keep
their existing update path.

Construction now records holder/container references before configuring them,
allowing the existing best-effort disable, unit-clear and hide helper to clean
partial failures outside combat. Incomplete states are never added to the reusable
retired-state pool. WoW frames cannot be destroyed, and cleanup API failures are
still suppressed by the existing helper. A regen handler clears failure caching
once per combat exit, permitting recovery with an unchanged signature. Persistent
failures remain cached between explicit retry events; they can allocate another
partial state on each combat exit. Existing world/addon-load retry behavior stays
in place.

Validation: `python3 -m unittest discover -s Tests -v` passes all three tests,
including the new Lua 5.1 mocked lifecycle regression. It covers initial combat
deferral, existing-state updates, deferred replacement, failures during container
creation and group setup, partial hiding/disabling, unchanged-signature recovery,
persistent missing prerequisites, addon-load recovery, and retired-state reuse.
Mocks do not reproduce protected APIs, taint, or secret values.

**In-game test needed:** No WoW client tests were run. On Retail 12.1.5, verify
first initialization and layout changes during combat recover after regen;
existing player/party/raid displays continue through repeated combat cycles;
hiding/showing and unit reassignment work; boss/role and priority auras, durations
and combat tooltip restrictions remain correct. Check blocked actions, taint,
duplicate or stale partial displays, and repeated initialization errors.

Risk is limited to native-container lifecycle and retry timing. Reverting this
Lua change restores prior behavior without saved-profile migration. No release
package, dependency validation, live-client validation, or external review was
performed; no version or packaging metadata changed.
