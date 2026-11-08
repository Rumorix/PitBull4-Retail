"""Exercise native aura status and caller handling with Lua 5.1 stubs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeAuraDeferralTest(unittest.TestCase):
    def test_configuration_readiness_without_geometry_cache(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/Aura/NativeContainer_12_1.lua").read_text()
        configure = source[source.index("local function configure_group("):
                           source.index("function PitBull4_Aura:Lorenzo121NativeRendererAvailable(")]
        harness = r'''
local native_configuration_count, native_configuration_skip_count = 0, 0
local OWN_GROUP_KEY, OTHER_GROUP_KEY = "own", "other"
local enabled, secret_geometry, reject = true, false, false
function issecretvalue() return secret_geometry end
local function get_ownership_group_filters() return "HELPFUL", nil, "native", {} end
local function get_group_enabled() return enabled end
local function get_unit_token(frame) return frame.unit end
local function get_sort_method() return "Default" end
local function get_sort_direction() return "Normal" end
local function configure_holder() end
local function configure_container_layout() return true end
local function call_method() return not reject, "rejected" end
local function hide_group(group) group.ready = false; group.configuration = nil end
local frame = {unit = "boss1", GetWidth = function() return 100 end,
    GetHeight = function() return 20 end, GetFrameLevel = function() return 1 end}
local db = {layout = {buff = {}}, max_buffs = 10}
local group = {container = {Show = function() end}, holder = {Show = function() end}}
'''
        checks = r'''
assert(configure_group(group, frame, db, true) and group.ready)
assert(configure_group(group, frame, db, true) and group.ready)
assert(native_configuration_skip_count == 1)
group.configuration = nil
group.ready = false
secret_geometry = true
assert(configure_group(group, frame, db, true) and group.ready)
assert(group.configuration == nil, "secret geometry must not be cached")
enabled = false
assert(configure_group(group, frame, db, true) and group.ready and not group.enabled)
group.ready = false
reject = true
assert(not configure_group(group, frame, db, true) and not group.ready)
'''
        result = subprocess.run([lua, "-"], input=harness + configure + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_combat_status_and_recovery(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/Aura/NativeContainer_12_1.lua").read_text()

        def section(start, end):
            return source[source.index(start):source.index(end)]

        hide = section("local function hide_group(", "local function retire_state(")
        update = section("function PitBull4_Aura:Lorenzo121UpdateNativeFrame(",
                         "local function is_boss_frame(")
        wrapper = section("local legacy_update_frame =", "function PitBull4_Aura:ClearFrame(")
        harness = r'''
local combat = true
function InCombatLockdown() return combat end
local native_frames = {}
local failures, mutations, cleaned, legacy, cleared = 0, 0, 0, 0, 0
local fail_create, fail_configure = false, false
local PitBull4_Aura = {}
local db = {layout = {buff = {}, debuff = {}}}
function PitBull4_Aura:GetLayoutDB() return db end
function PitBull4_Aura:LayoutUsesNativeFilters() return db.native_filters end
function PitBull4_Aura:ClearAuras() cleaned = cleaned + 1 end
function PitBull4_Aura:UpdateFrame() legacy = legacy + 1 end
function PitBull4_Aura:ClearFrame() cleared = cleared + 1 end
function PitBull4_Aura:Lorenzo121ClearNativeFrame() end
local function should_use_native() return true end
local function is_boss_frame() return false end
local function get_unit_token(frame) return frame.unit end
local function group_needs_rebuild() return false end
local function record_failure() failures = failures + 1 end
local function clear_failure() end
local function retire_state(frame) native_frames[frame] = nil end
local function create_native_state(frame)
    assert(not combat, "creation in combat")
    mutations = mutations + 1
    if fail_create then return nil, "create-failed" end
    local state = {groups = {buff = {}, debuff = {}}}
    native_frames[frame] = state
    return state
end
local function configure_group(group)
    assert(not combat, "configuration in combat")
    mutations = mutations + 1
    if fail_configure then return false, "configure-failed" end
    group.ready = true
    return true
end
local function call_method(object, method, ...) return pcall(object[method], object, ...) end
'''
        checks = r'''
local frame = {unit = "boss1"}
local deleted = 0
frame.aura_highlight = {Delete = function() deleted = deleted + 1 end}
local function deferred()
    local ok, err = PitBull4_Aura:Lorenzo121UpdateNativeFrame(frame)
    assert(ok == nil and err == "deferred")
    local old_cleaned, old_legacy = cleaned, legacy
    PitBull4_Aura:UpdateFrame(frame)
    assert(cleaned == old_cleaned and legacy == old_legacy)
    assert(failures == 0 and deleted == 0 and mutations == 0)
end
deferred() -- No native state; do not claim success or enter failure fallback.
native_frames[frame] = {unit = "boss1", groups = {buff = {ready = true}}}
deferred() -- Partial state.
local state = native_frames[frame]
state.groups.debuff = {ready = true, enabled = false}
assert(PitBull4_Aura:Lorenzo121UpdateNativeFrame(frame) == true)
-- A disabled group is valid when configured that way; detachment invalidates it.
hide_group(state.groups.buff)
assert(state.groups.buff.ready == false)
deferred()
state.groups.buff.ready = true
state.unit = "boss2"
deferred() -- Rebound public unit token must be reconciled outside combat.
native_frames[frame] = nil
combat = false
PitBull4_Aura:UpdateFrame(frame)
assert(mutations == 3 and cleaned == 1 and deleted == 1 and failures == 0)
combat = true
PitBull4_Aura:UpdateFrame(frame)
assert(mutations == 3 and cleaned == 2 and failures == 0)
combat = false
native_frames[frame] = nil
fail_create = true
PitBull4_Aura:UpdateFrame(frame)
assert(failures == 1 and legacy == 1)
db.native_filters = true
PitBull4_Aura:UpdateFrame(frame)
assert(failures == 2 and legacy == 1 and cleared == 1)
fail_create = false
fail_configure = true
local ok, err = PitBull4_Aura:Lorenzo121UpdateNativeFrame(frame)
assert(ok == false and err == "configure-failed" and native_frames[frame] == nil)
'''
        result = subprocess.run([lua, "-"], input=harness + hide + update + wrapper + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
