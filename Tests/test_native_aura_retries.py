"""Run the native renderer's failure lifecycle with Lua 5.1 API stubs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeAuraRetriesTest(unittest.TestCase):
    def test_failure_lifecycle(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/Aura/NativeContainer_12_1.lua").read_text()
        harness = r'''
local module = {OnProfileChanged_funcs = {}}
local combat, queue = false, {}
function InCombatLockdown() return combat end
C_Timer = {After = function(delay, callback)
    assert(delay == 1 or delay == 2)
    queue[#queue + 1] = callback
end}
local function tick()
    local callbacks = queue
    queue = {}
    for _, callback in ipairs(callbacks) do callback() end
end
local caps = {is121OrNewer = true, auraContainerAddonLoaded = true,
              nativeAPIPrerequisitesReady = true}
module.Lorenzo121 = caps
PitBull4 = {GetModule = function() return module end}
function CreateFrame() end
AuraContainerSortMethod, AuraContainerSortDirection = {}, {}
AnchorUtil = {FlowLayoutAxis = {}, FlowDirection = {}}
function module:IsEnabled() return true end
function module:GetLayoutDB(frame) return frame.db end
function module:LayoutUsesNativeFilters(db) return db.native end
function module:Update(frame)
    if frame.db.enabled then self:UpdateFrame(frame) else self:ClearFrame(frame) end
end
function module:UpdateFrame(frame) frame.legacy = (frame.legacy or 0) + 1 end
function module:ClearFrame() end
function module:UpdateAll() end
function module:OnEnable() end
function module:OnDisable() end
'''
        checks = r'''
-- Replace only native API boundaries, retaining the real retry, creation,
-- configuration-failure, retirement and renderer wrapper control flow.
local creations, configure_calls, fail = 0, 0, "create"
create_native_group = function(frame, db, buff, state)
    if buff then creations = creations + 1 end
    if fail == "create" then error("transient creation") end
    state.groups[buff and "buff" or "debuff"] = {}
end
configure_group = function()
    configure_calls = configure_calls + 1
    return fail ~= "configure", "transient configuration"
end
group_needs_rebuild = function() return false end
local function frame()
    return {unit = "target", layout = "test", db = {enabled = true, native = true}}
end
local f = frame()
module:UpdateFrame(f)
assert(creations == 1 and #queue == 1)
for i = 1, 10 do module:UpdateFrame(f) end
assert(creations == 1, "ordinary updates bypassed backoff")
assert(module:Lorenzo121NativeHandlesUnitAura("target"))
assert(not module:Lorenzo121ShouldRunLegacyAuraTicker())
combat = true
tick()
module:UpdateFrame(f)
assert(creations == 1, "retry mutated native state during combat")
combat, fail = false, false
module:UpdateFrame(f) -- the same path used by post-combat UpdateAll
assert(creations == 2 and not failed_frames[f] and native_frames[f])
-- Configuration failures must retain the budget across successful creation.
local g = frame()
fail = "configure"
module:UpdateFrame(g)
tick()
tick()
local bounded = creations
for i = 1, 10 do module:UpdateFrame(g); tick() end
assert(creations == bounded and failed_frames[g].retries == 2 and #queue == 0)
assert(not native_frames[g], "failed state was not retired")
-- An explicit reset invalidates queued work from the previous generation.
local h = frame()
fail = "create"
module:UpdateFrame(h)
clear_failure(h)
fail = false
module:UpdateFrame(h)
local before = configure_calls
tick()
assert(configure_calls == before, "stale callback updated replacement state")
-- Reused frame/layout identity invalidates old callbacks and permits a fresh try.
local j = frame()
fail = "create"
module:UpdateFrame(j)
j.unit = "focus"
before = creations
tick()
assert(creations == before)
fail = false
module:UpdateFrame(j)
assert(creations == before + 1 and not failed_frames[j])
local k = frame()
fail = "create"
module:UpdateFrame(k)
k.db = {enabled = true, native = true}
before = creations
tick()
assert(creations == before)
fail = false
module:UpdateFrame(k)
assert(not failed_frames[k])
-- Disabled layouts do not get configured by delayed work.
local disabled = frame()
fail = "create"
module:UpdateFrame(disabled)
disabled.db.enabled = false
before = creations
tick()
assert(creations == before)
-- Legacy fallback receives matching events without visiting healthy frames.
local legacy = frame()
legacy.db.native = false
fail = "create"
module:UpdateFrame(legacy)
local legacy_updates = legacy.legacy
local healthy_updates = configure_calls
module:Lorenzo121NativeHandlesUnitAura("unrelated")
assert(legacy.legacy == legacy_updates)
module:Lorenzo121NativeHandlesUnitAura("target")
assert(legacy.legacy == legacy_updates + 1 and configure_calls == healthy_updates)
-- Native-filter rows remain cleared rather than rendering unfiltered fallback.
assert(not f.legacy and not g.legacy)
'''
        result = subprocess.run([lua, "-"], input=harness + source + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
