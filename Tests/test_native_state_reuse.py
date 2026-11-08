"""Exercise the native state lifecycle with Lua 5.1 and public frame stubs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeStateReuseTest(unittest.TestCase):
    def test_lifecycle(self):
        lua = shutil.which('lua5.1')
        if not lua:
            self.skipTest('Lua 5.1 is required')
        source = (ROOT / 'Modules/Aura/NativeContainer_12_1.lua').read_text()

        def section(start, end):
            return source[source.index(start):source.index(end)]

        harness = r'''
local PitBull4_Aura = {}
local native_frames, failed_frames = {}, {}
local reusable_states = setmetatable({}, {__mode = "k"})
local MAX_REUSABLE_STATES = 2
local allocations, registered, unregistered = 0, 0, 0
local combat, fail = false, false
function InCombatLockdown() return combat end
function RegisterStateDriver() registered = registered + 1 end
function UnregisterStateDriver() unregistered = unregistered + 1 end
local function get_unit_token(frame) return frame.unit end
local function hide_group(group) group.configuration = nil; group.hidden = true end
local function record_failure(frame, err) failed_frames[frame] = err end
local function clear_failure(frame) failed_frames[frame] = nil end
local function group_needs_rebuild(group, frame, db) return group.signature ~= db.signature end
local function create_native_state(frame, db)
    allocations = allocations + 1
    local state = {groups = {}}
    for _, kind in ipairs({'buff', 'debuff'}) do
        state.groups[kind] = {signature = db.signature, visibilityDriver = 'driver',
            visibilityGate = {Hide = function() end}}
        RegisterStateDriver()
    end
    native_frames[frame] = state
    return state
end
local function configure_group(group)
    assert(group.configuration == nil, 'retirement did not invalidate configuration')
    group.hidden = false
    return not fail, 'configuration failed'
end
function PitBull4_Aura:GetLayoutDB(frame) return frame.db end
'''
        checks = r'''
local a = {unit = 'player', db = {signature = 'A', layout = {buff = {}, debuff = {}}}}
local function update(signature)
    a.db.signature = signature
    return PitBull4_Aura:Lorenzo121UpdateNativeFrame(a)
end
assert(update('A'))
local first = native_frames[a]
for i = 1, 50 do assert(update('B')); assert(update('A')) end
assert(allocations == 2, 'repeated edits allocated new states')
assert(native_frames[a] == first)
assert(registered - unregistered == 2, 'scope drivers were not restored')
local b = {unit = 'target', db = a.db}
assert(PitBull4_Aura:Lorenzo121UpdateNativeFrame(b))
assert(native_frames[b] ~= first, 'state crossed owners')
combat = true
local before = allocations
assert(update('C'))
assert(native_frames[a] == first and allocations == before)
combat = false
for i = 1, 10 do assert(update(tostring(i))) end
assert(#reusable_states[a] <= MAX_REUSABLE_STATES)
fail = true
assert(not update('failed'))
assert(native_frames[a] == nil)
for _, state in ipairs(reusable_states[a]) do
    assert(state.groups.buff.signature ~= 'failed')
end
fail = false
retire_all_states()
assert(next(reusable_states) == nil)
before = allocations
assert(update('A'))
assert(allocations == before + 1, 'explicit rebuild reused a state')
'''
        script = (harness
                  + section('local function retire_state(', 'local function record_failure(')
                  + section('-- Cache only states', 'local function configure_group(')
                  + section('function PitBull4_Aura:Lorenzo121UpdateNativeFrame(', 'local function is_boss_frame(')
                  + checks)
        result = subprocess.run([lua, '-'], input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
