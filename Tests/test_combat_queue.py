"""Exercise the actual core queue block with Lua 5.1 and client API stubs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CombatQueueTest(unittest.TestCase):
    def test_deferred_failures_and_reentry(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Main.lua").read_text()
        start = source.index("do\n\tlocal in_combat = false")
        end = source.index("\nend", start) + len("\nend")
        queue = source[start:end]
        harness = r'''
local errors, wiped = {}, {}
local lockdown = true
PitBull4 = {SingletonUnitFrame = {PLAYER_REGEN_DISABLED = function() end},
            MemberUnitFrame = {PLAYER_REGEN_DISABLED = function() end}}
function InCombatLockdown() return lockdown end
function geterrorhandler()
    return function(err) errors[#errors + 1] = err end
end
function wipe(t)
    for k in pairs(t) do t[k] = nil end
    wiped[#wiped + 1] = t
end
'''
        checks = r'''
local p = PitBull4
local function enter() lockdown = true; p:PLAYER_REGEN_DISABLED() end
local function leave() lockdown = false; p:PLAYER_REGEN_ENABLED() end
local calls = {}
local function record(v) calls[#calls + 1] = v end
-- Each failure position must report once, release every entry, and continue.
for failed = 1, 3 do
    calls, errors, wiped = {}, {}, {}
    enter()
    for i = 1, 3 do
        local index = i
        p:RunOnLeaveCombat(function()
            record(index)
            if index == failed then error("controlled callback failure") end
        end)
    end
    assert(#calls == 0)
    leave()
    assert(table.concat(calls, ",") == "1,2,3")
    assert(#errors == 1 and string.find(errors[1], "controlled callback failure"))
    assert(#wiped == 3)
    for _, t in ipairs(wiped) do assert(next(t) == nil) end
    leave()
    assert(#calls == 3 and #errors == 1, "callback retried")
end
-- Explicit argument counts survive failure, pooling, and trailing nils.
local opaque = setmetatable({}, {__tostring = function() error("inspected") end})
enter()
p:RunOnLeaveCombat(function(...) assert(select('#', ...) == 4)
    local a, b, c, d = ...
    assert(a == "arg" and b == nil and rawequal(c, opaque) and d == nil)
end, "arg", nil, opaque, nil)
p:RunOnLeaveCombat(function(...) assert(select('#', ...) == 0) end)
leave()
assert(#errors == 1)
-- Out-of-combat scheduling stays synchronous, including error propagation.
calls = {}
enter()
p:RunOnLeaveCombat(function()
    record("outer")
    p:RunOnLeaveCombat(record, "inner")
    record("returned")
end)
p:RunOnLeaveCombat(record, "later")
leave()
assert(table.concat(calls, ",") == "outer,inner,returned,later")
assert(not pcall(function() p:RunOnLeaveCombat(error, "immediate") end))
-- A new combat cycle during a callback uses a separate dense pending queue.
calls = {}
enter()
p:RunOnLeaveCombat(function()
    record("first")
    enter()
    p:RunOnLeaveCombat(record, "next cycle")
end)
p:RunOnLeaveCombat(record, "old batch")
leave()
assert(table.concat(calls, ",") == "first,old batch")
leave()
assert(table.concat(calls, ",") == "first,old batch,next cycle")
-- Combat entry before lockdown retains its existing immediate behavior.
enter()
lockdown = false
p:RunOnLeaveCombat(record, "entry")
assert(calls[#calls] == "entry")
leave()
'''
        result = subprocess.run([lua, "-"], input=harness + queue + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
