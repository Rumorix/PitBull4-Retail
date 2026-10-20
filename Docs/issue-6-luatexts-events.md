# Issue #6: LuaTexts subscriptions after configuration changes

The text provider replaces `font_string.db` before calling `AddFontString()`.
For a reused string, LuaTexts previously refreshed the script output and returned
without updating event-cache memberships. This can leave the new script listening
to the previous configuration's events.

`Modules/LuaTexts/LuaTexts.lua` now reconciles reused strings against the current
event selections before refreshing output. It removes obsolete memberships, adds
enabled memberships, and unregisters empty events using the existing support-event
exceptions. Other strings' subscriptions and the existing cast refresh remain intact.
The comparison also handles configuration tables edited in place. No saved-profile
format or gameplay-value handling changes.

`Tests/test_luatexts_events.py` runs the actual lifecycle functions in Lua 5.1 with
stubbed display/event APIs. It covers replacement configurations, in-place edits,
false and absent selections, shared subscribers, support events, repeated refresh,
hide/show reuse, Cyrillic slot names, cast refresh and final removal. It fails on
the original source and passes with the correction. Lua syntax and diff whitespace
checks also passed. Run locally with:

```
python3 -B -m unittest discover -s Tests -v
luac -p Modules/LuaTexts/LuaTexts.lua
git diff --check
```

Risk: reconciliation scans the existing event cache on each reused-string refresh.
It follows existing removal rules and avoids clearing auxiliary text caches.
Rollback: revert the added reconciliation block and restore its preceding comment.

**In-game test needed; no WoW tests performed.** The harness does not load the full
addon or validate protected/secret APIs, taint or combat lockdown. Verify profile
A→B→A and layout reassignment with matching slot names and disjoint health/power
events; check immediate output and subsequent event-driven updates. Also verify
copied/imported profiles, hidden/shown frames, disabled/removed slots, ruRU layouts,
ordinary option edits, cast/timer/mouseover texts, and deferred refresh across combat
transitions. Check for Lua errors, blocked actions and taint with Retail secret-valued
data. These switching scenarios are not claimed as reproduced in-game.
