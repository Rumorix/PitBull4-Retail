# Issue #19: main-tank exclusion grouping

README.md identifies this checkout as Retail/Midnight 12.1.5 P010, rather than
Forever or the issue's P008 baseline.

GroupHeader.lua used `exclude_main_tanks and nil or group_by` to clear the
secure header's groupBy attribute. In Lua 5.1 this always falls through to
group_by. An explicit conditional now clears groupBy during raid main-tank
exclusion and restores the configured grouping otherwise. The existing helper
already orders the exclusion nameList using the configured grouping and sorting.
Saved settings, cached configured grouping, filtering, groupingOrder and the
existing out-of-combat wrapper are preserved. groupingOrder remains available
for normal grouping when exclusion is disabled; groupBy is the grouping switch.

Tests/test_groupheader_exclusion.py executes the actual RefreshGroup function
with Lua 5.1 and stubbed header APIs. It covers configured GROUP, CLASS, ROLE,
ASSIGNEDROLE and absent grouping, toggles, nameList sorting attributes, saved
settings, exact MAINTANK filters and party headers. A modeled combat wrapper
checks deferred execution at the existing boundary; it does not validate the
real wrapper or Blizzard secure execution. The roster helper is stubbed, so
these tests do not validate roster filtering, oRA3 or secret-value handling.
The regression fails against the original expression.

Local validation passed:

- `python3 -B -m unittest discover -s Tests -v` (three tests)
- `luac5.1 -p GroupHeader.lua`
- `git diff --check`

Risk: clearing groupBy can change raid ordering or column placement while
exclusion is active. Rollback is limited to the conditional in GroupHeader.lua
and the accompanying test/documentation. Separate roster sorting and secret-value
concerns are outside this attribute fix.

**In-game test needed on Retail WoW 12.1.5; no WoW tests performed.** Compare
exclusion on/off for all grouping modes and sort directions, including column
layouts, empty rosters, roster/assignment changes, separate Main Tanks headers
and oRA3 enabled/disabled. Exercise combat entry/exit with queued changes and
verify unit assignments, targeting/healing clicks, configuration previews and
absence of protected-action blocks, taint or secret-value errors. The local
harness does not establish client behavior or package completeness.
