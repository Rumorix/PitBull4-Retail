# Issue #15: trailing fallback raid aura refresh

The checked-out README identifies Retail/Midnight 12.1.5 P010, while the
report and AGENTS.md cite P008. Equivalence to the audit baseline is unverified.
Static source inspection establishes a lost trailing event in the fallback
UNIT_AURA handler; it does not establish a failure in healthy native containers.

Aura.lua now drains pending raid refreshes through its existing OnUpdate frame,
before the slower filter ticker. Update.lua records a public unit token and the
existing 0.12-second deadline when an event is suppressed. Further events do not
postpone that deadline. A normal event at the deadline satisfies pending work.
The drain re-enters UNIT_AURA, checking native ownership and current frame and
layout bindings without retaining or inspecting update_info. Existing rendering
and combat safeguards remain in use. Disable, profile changes and performance
mode changes clear throttle state.

Risk: fallback raids can perform an additional frame scan at the end of a burst.
Delivery occurs on the first rendered frame at or after the deadline, so client
stalls can increase latency. Existing next-deadline bookkeeping is retained;
pending work is coalesced per unit. No saved-profile fields change.

Rollback: revert the changes in Modules/Aura/Aura.lua and Modules/Aura/Update.lua.
The regression test and this note may be removed with them.

Local validation: `python3 -m unittest discover -s Tests -v` passed all three
tests, including the new Lua 5.1 stub regression in Tests/test_aura_throttle.py.
`luac5.1 -p Modules/Aura/Aura.lua Modules/Aura/Update.lua` passed.
The stubs test scheduling and handler behavior, not Blizzard's APIs.

**In-game test needed on WoW Retail 12.1.5.** No WoW tests were run. Verify buff
and debuff bursts ending in removal with performance mode on/off, healthy native
rendering and supported fallback configurations. Exercise combat transitions,
restricted aura data, roster reassignment, frame hiding/rebinding, profile
changes and disable/re-enable. Check final display accuracy, raid performance,
secret-value errors, taint and blocked protected actions. No package or release
was built, and no independent review was performed.
