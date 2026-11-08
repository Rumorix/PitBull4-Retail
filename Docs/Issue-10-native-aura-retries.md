# Issue #10: bounded native aura recovery

The inspected source is the Retail/Midnight fork; README identifies P010.
The issue's P008 audit is historical context, not a verified live reproduction.

`Modules/Aura/NativeContainer_12_1.lua` now permits two automatic retries after
an initial failure, delayed by one and two seconds. Ordinary updates cannot
bypass these delays. Combat defers a ready retry to the existing post-combat
UpdateAll path. The retry budget survives successful container creation until
both groups configure successfully. Persistent failures remain latched after
the budget is exhausted; existing explicit rebuild/filter resets still work.

Each failure record also acts as a generation token. Callbacks check that exact
record plus the current addon-owned layout, layout DB and unit token. Reset,
success or changed frame identity makes queued work obsolete. No aura payload
or protected unit identity is inspected. Failed native states still retire
through the existing cleanup path.

Aura events visit only failed frames for fallback delivery while native mode
is active. Failures no longer activate the global legacy aura scan or weapon
enchant ticker. Native-filter layouts retain their restriction against an
unfiltered fallback row. Legacy fallback weapon enchant changes will therefore
not receive ticker updates while native mode remains active; normal native
recovery restores native enchant handling. Disabling native mode retains the
existing full legacy path.

## Validation and remaining risk

The Lua 5.1 mocked regression covers creation and configuration failures,
bounded retries, combat deferral, successful recovery, obsolete callbacks,
frame reuse, disabled layouts, targeted event delivery, and native-filter
fallback restrictions. Python unittest discovery and Lua 5.1 syntax validation
were run locally. Mocks cannot establish protected API or secret-value safety.

**In-game test needed; none performed.** On Retail 12.1.5, verify a transient
failure recovers after combat, persistent failures stop retrying, healthy frames
stay unchanged, and target/focus/boss reuse and profile changes discard obsolete
work. Check filtered buffs/debuffs, weapon enchants, absent boss preparation,
container accumulation, combat transitions, Edit Mode, taint and secret errors.
No package build, dependency installation or distribution validation was run.

Rollback consists of reverting the Lua change; saved profiles and metadata are
unchanged. The regression test and this note can be removed independently.
