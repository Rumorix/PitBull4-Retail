# Issue #21: deferred callback error isolation

The source confirms the reported failure in the core combat-deferred queue.
README.md identifies this checkout as Retail/Midnight 12.1.5 P010, while
AGENTS.md and the audit refer to P008. This fix targets the checked-out source;
the pinned audit baseline and a live-client trigger were not verified.

Main.lua now detaches the pending batch before draining it and runs each callback
inside xpcall with the current client geterrorhandler(). A closure forwards the
stored arguments with their explicit count under Lua 5.1. Failed callbacks are
reported, cleaned up and pooled just like successful callbacks; later callbacks
continue in order. Failed work is never automatically retried. Detaching the
batch keeps any newly deferred work in a dense queue for the next regen event.
Immediate calls and existing combat gating remain unchanged. No arguments are
formatted or logged by this change, and no saved-profile fields are changed.

Tests/test_combat_queue.py extracts the actual queue block from Main.lua and
executes it with Lua 5.1 and stubbed client APIs. It covers failures at the first,
middle and last positions, error reporting, cleanup, no retries, subsequent
cycles, pooled entries, zero and trailing-nil arguments, opaque argument identity,
synchronous nested calls, immediate error propagation, combat entry before
lockdown, and newly deferred work during a drain.

Local validation passed:

```
python3 -B -m unittest discover -s Tests -v
luac5.1 -p Main.lua
git diff --check
```

Risk: isolation cannot undo partial changes made by a failing callback; later
callbacks may depend on those changes. The change deliberately continues later
work and reports the original error through the client handler. It introduces
no protected-API bypass. Rollback consists of reverting the queue-drain change
in Main.lua and removing the accompanying test and this document.

**In-game test needed; no WoW tests performed.** On Retail 12.1.5, inject a
controlled failure between independent deferred operations and confirm one error,
later completion, and normal work on subsequent combat cycles. Check deferred
layout/group refresh, click registration and clamping, combat entry/exit, reload
during combat and Edit Mode transitions for blocked actions or taint. Confirm
actual secret-valued arguments remain opaque. The standalone harness does not
model client secret semantics, protected execution, full-addon integration or
dependency packaging. No test ZIP, release or external review was produced.
