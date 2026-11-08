# Issue #17: raid whitelist role sanitization

This is the Retail/Midnight 12.1.5 fork. README.md identifies the current
snapshot as P010; the issue's P008 baseline is historical. The defective
expressions remain present in this checkout.

In GroupHeader.lua, build_raid_name_list_without_main_tanks now explicitly
clears each role local when issecretvalue reports it secret. Lua's previous
`predicate and nil or value` expression always fell back to the original
value. Both fields are now sanitized before main-tank comparison, role-filter
lookup, record storage and grouping. Ordinary and nil roles retain their
existing behavior. No protected updates, profile fields or API calls change.

Risk: an unknown role cannot identify a main tank or match a role filter.
Without other matching filter tokens it is omitted from a role-filtered list;
without a filter it remains eligible, with the existing unknown grouping rank.
Public oRA3 tank assignments can still exclude it. This follows the existing
unknown-role behavior rather than trying to recover restricted information.
Live impact and the issue's claimed severity remain unconfirmed.

Tests/test_groupheader_roles.py executes the actual extracted helper under
Lua 5.1 with stubbed roster APIs. It covers public/nil roles, independently
flagged and jointly flagged fields, filtering, grouping, ordinary main-tank
exclusion, name sorting and oRA3 full/short-name exclusions. Flagged strings
make accidental use observable, but cannot emulate WoW's secret-value runtime.
The regression test also failed when run against the original two expressions
in memory, without changing the checkout.

Local validation passed:

- `python3 -B -m unittest discover -s Tests -v` (3 tests)
- `luac5.1 -p GroupHeader.lua`
- `git diff --check`

**In-game test needed; no WoW tests performed.** On Retail 12.1.5, exercise
Exclude Main Tanks on raid and raid-pet headers, role filters and grouping,
with and without oRA3, across roster/role changes and combat entry/exit.
Check frame membership/order, refresh recovery, deferred protected updates,
and absence of secret-value errors, blocked actions or taint. The local
harness does not load the full addon or validate packaging/dependencies.

Rollback: restore the two original local initializers in GroupHeader.lua and
remove the issue-specific regression test and this note. No release metadata
or dependencies were changed.
