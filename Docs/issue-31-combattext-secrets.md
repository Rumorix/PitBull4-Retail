# Issue #31: CombatText secret values

This checkout identifies itself as Retail/Midnight 12.1.5 P008 in README.md.
The report names P009; that installed package and the full-health reproduction
have not been verified. Both reported unsafe comparisons exist in this source,
so a local defensive correction is justified independently of reproduction.

Modules/CombatText/CombatText.lua now skips UNIT_COMBAT payloads if unit, event,
flags, amount or damage type is secret. The check precedes frame lookup,
comparisons, table indexing, arithmetic and formatting. This deliberately loses
feedback for those events; existing feedback continues its normal fade. Checking
all consumed payload fields also avoids moving the failure to a later operation.
UpdateFrame checks whether rendered text is secret before comparing it with the
preview string. Accessible preview text still clears as before; secret display
contents are left alone. No profile, layout or protected-frame changes are made.

Tests/test_combattext_secrets.py executes the actual module under Lua 5.1 with
stubbed APIs. It checks rejection of each payload field for damage, healing,
energize and immunity events, secret displayed text, entering/leaving preview,
ordinary damage/healing/energize/absorb/block/immunity feedback, and fading.
It also checks behavior when issecretvalue is absent. Sentinels model rejection;
Lua 5.1 cannot reproduce the client's actual secret-value semantics.

Local validation passed:

```
python3 -B -m unittest discover -s Tests -v
luac -p Modules/CombatText/CombatText.lua
git diff --check
```

Risk: entire events with any secret payload field are suppressed, even when a
particular branch would not use that field. This conservative fallback avoids
attempting to reveal or transform secret data. Rollback is confined to the two
CombatText guards and their accompanying test/documentation files.

**In-game test needed; no WoW tests performed.** On Retail 12.1.5, check full and
partial health, player/target/target-of-target frames, damage, heals, energize,
criticals, absorbs, blocks, resists and immunity. Verify accessible feedback and
fading, secret-event suppression, target changes, hide/show and frame reuse,
preview/Edit Mode transitions, and combat entry/exit. Check for recurring secret
errors and protected-action/taint failures. The harness does not load the full
addon, validate dependencies, or establish actual client secrecy behavior.
