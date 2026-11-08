# Issue #14: unsupported legacy filters in the Retail native renderer

Source inspection of this Retail P010 checkout confirms that nonempty legacy
custom filter IDs previously became an unrestricted helpful/harmful selection.
The legacy built-ins exempted by the compiler also contain compound predicates;
`!C` and `!E` are not equivalent to an ownership-only selection. No exact native
translation of those expressions is established by this source.

The native compiler now marks every nonempty legacy selection blocked. The
existing renderer handling disables that row and detaches it from the real unit.
The layout warning explains the hidden row, and native status diagnostics count
unsupported legacy selections. Saved IDs, expressions, references and profiles
are not migrated or rewritten. The legacy renderer is unchanged.

Supported paths remain None (all auras), native presets and validated native
custom definitions. Native definitions support the categories, ownership,
spell-ID lists and maximum duration exposed by the existing editor. They do not
evaluate arbitrary legacy Boolean expressions. Native spell-ID lists retain
secure friendly-buff/hostile-debuff visibility scopes. Config Mode previews
placement rather than actual filtering.

## Behavior and risk

Layouts using legacy selections, including default legacy built-ins, will lose
those rows under the native renderer until a supported selection is chosen.
Choose an appropriate native filter; choosing None explicitly selects all auras.
This intentional visibility change prevents silently displaying a broader set
than the saved expression requests. The change reads public settings only and
uses existing blocked-row and combat-deferral handling. It does not establish
Blizzard runtime semantics or add access to restricted aura fields.

Affected source: NativeFilters_12_1.lua (compiler), Options.lua (warning),
NativeContainer_12_1.lua (diagnostic label/count). To roll back, revert these
source changes; no profile conversion needs reversing. Rollback restores the
previous approximation behavior.

## Validation

Passed: `python3 -m unittest discover -s Tests -v` (three tests, including Lua
5.1 compiler fixtures) and `luac5.1 -p` on the three changed Lua files. Fixtures
cover restrictive compound/custom and missing legacy IDs, legacy built-ins,
empty selections, native ownership/categories, validated identity lists,
invalid/incompatible native definitions, and preservation of saved expressions.
The fixtures use stubs and do not exercise Blizzard's AuraContainer.

**In-game test needed:** Retail WoW 12.1.5, with native rendering enabled, verify
legacy rows hide and supported selections restore them; switch filters before,
during and after combat; test own/other casters, friendly/hostile units,
restricted auras and identity-list visibility. Check Config Mode, profile reload,
icon limits, secret-value errors, taint and blocked protected actions. Confirm
native renderer failure does not show an unfiltered row. No live WoW test,
packaged build, or independent review was performed.
