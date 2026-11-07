# Issue #18: descending raid whitelist ordering

Confirmed in the Retail Midnight 12.1.5 P008 source. The raid name-list builder
used by Exclude Main Tanks expressed each comparison as
`direction == "DESC" and a > b or a < b`. In descending mode a false `a > b`
fell through to `a < b`, allowing both comparison directions to return true.
This violates Lua's sort contract. Live impact and the issue's severity have
not been reproduced or established.

`GroupHeader.lua` now returns the descending comparison explicitly at each of
the three levels: grouping rank, name, and roster index. Ascending behavior,
unknown grouping rank (999), and index tie-breaking remain as before. The
change preserves the existing direction applied to grouping ranks. It changes
no profile fields, filters, secure attributes, or combat deferral boundaries.
The adjacent secret-value guards are outside this fix's scope.

`Tests/test_groupheader_raid_sort.py` extracts the actual builder and grouping
definitions and runs them in Lua 5.1 with synthetic public roster values. It
covers ascending/descending and default settings, group/class/role/assigned-role
grouping, name/index sorting, equal names, unknown ranks, filtering, native and
oRA3 tank exclusion, empty/single/full rosters, and comparator irreflexivity,
asymmetry and transitivity. Full-roster output is compared with independently
constructed lexicographic keys. Restoring the original comparisons in memory
makes the test fail its asymmetry assertion.

Local validation passed:

```
python3 -B -m unittest discover -s Tests -v
luac5.1 -p GroupHeader.lua
git diff --check
```

Both discovered regression tests passed. No dependencies were installed or
package builds performed. The harness does not load the full addon or emulate
WoW secret values or protected APIs.

Risk is limited to ordering in the raid whitelist path when Exclude Main Tanks
is active. Descending output can change because the former comparator was
invalid. Rollback consists of reverting the three explicit comparison branches;
no saved-data migration is required.

**In-game test needed; no WoW tests performed.** On Retail 12.1.5, verify raid
headers with Exclude Main Tanks enabled, both directions, name/index sorting,
all grouping modes and custom class/role orders. Use exclusion disabled as a
control and verify tank assignments with and without oRA3. Exercise roster,
subgroup and role changes, reloads, configuration preview, and combat entry/exit.
Confirm deferred refresh and absence of Lua errors, secret-value errors, taint
and blocked protected actions. No experimental ZIP or release was created.
