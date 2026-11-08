"""Exercise the fallback raid throttle and real event handler under Lua 5.1."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AuraThrottleTest(unittest.TestCase):
    def test_trailing_refresh(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        update = (ROOT / "Modules/Aura/Update.lua").read_text()
        aura = (ROOT / "Modules/Aura/Aura.lua").read_text()
        throttle = update[update.index("local LORENZO_PATCH105_RAID_UNIT_AURA_THROTTLE"):
                          update.index("local function lorenzo_patch105_suppress")]
        handler = aura[aura.index("function PitBull4_Aura:UNIT_AURA("):
                       aura.index("function PitBull4_Aura:ClearFrame(")]
        lifecycle = aura[aura.index("function PitBull4_Aura:OnDisable()"):
                         aura.index("function PitBull4_Aura:PLAYER_ENTERING_WORLD()")]
        ticker = aura[aura.index('timerFrame:SetScript("OnUpdate"'):
                      aura.index("function PitBull4_Aura:OnEnable()")]
        harness = r'''
local now, raid, native = 0, true, false
local secret = {}
function GetTime() return now end
function IsInRaid() return raid end
function issecretvalue(value) return rawequal(value, secret) end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local function safe_unit_is_unit(a, b) return a == b or a == "raid40" end
local PitBull4_Aura = {OnProfileChanged_funcs = {}}
local frames = {{unit = "raid1", enabled = true, state = "buff"},
                {unit = "raid2", enabled = true, state = "buff"}}
local PitBull4 = {}
function PitBull4:IterateFrames()
    local i = 0
    return function() i = i + 1; return frames[i] end
end
function PitBull4_Aura:GetLayoutDB(frame) return frame end
function PitBull4_Aura:UpdateFrame(frame)
    frame.updates = (frame.updates or 0) + 1
    frame.display = frame.state
end
function PitBull4_Aura:ClearFrame(frame) frame.display = nil end
function PitBull4_Aura:UpdateAll() end
function PitBull4_Aura:UpdateWeaponEnchants() end
function PitBull4_Aura:UpdateFilters() end
function PitBull4_Aura:Lorenzo121NativeHandlesUnitAura() return native end
local timerFrame = {}
function timerFrame:Hide() end
function timerFrame:SetScript(_, callback) self.tick = callback end
local timer = 0
'''
        checks = r'''
local m, a, b = PitBull4_Aura, frames[1], frames[2]
local function event(unit) m:UNIT_AURA("UNIT_AURA", unit, secret) end
local function tick(t) now = t; timerFrame.tick(timerFrame, 0.01) end
event("raid1")
assert(a.updates == 1 and a.display == "buff")
now = 0.05; a.state = nil; event("raid1")
now = 0.09; event("raid1"); event("raid2")
assert(a.updates == 1 and b.updates == 1)
tick(0.119); assert(a.updates == 1)
tick(0.12); assert(a.updates == 2 and a.display == nil)
tick(0.13); assert(a.updates == 2)
-- Independent deadlines and current layout/binding checks.
now = 0.14; b.state = nil; event("raid2")
b.enabled = false
tick(0.21); assert(b.display == nil and b.updates == 1)
now = 0.22; event("raid1"); a.unit = "target"
tick(0.24); assert(a.updates == 2)
a.unit = "raid1"
-- Boundary events satisfy pending work without a duplicate trailing update.
m:LorenzoPatch105ClearRaidUnitAura()
now = 1; event("raid1")
now = 1.05; event("raid1")
now = 1.12; event("raid1")
local count = a.updates
tick(1.12); assert(a.updates == count)
-- Healthy native ownership is rechecked at drain time.
now = 1.15; event("raid1"); native = true
tick(1.24); assert(a.updates == count)
native = false
-- Disable, profile and performance-mode changes cancel old pending work.
for _, reset in ipairs({"OnDisable", "OnProfileChanged"}) do
    m:LorenzoPatch105ClearRaidUnitAura()
    now = now + 1; event("raid1")
    now = now + 0.05; event("raid1")
    count = a.updates; m[reset](m)
    tick(now + 0.2); assert(a.updates == count)
end
now = 5; event("raid1"); now = 5.05; event("raid1")
count = a.updates; m:LorenzoPatch105SetRaidPerformanceMode(false)
tick(5.2); assert(a.updates == count)
event("raid1"); event("raid1"); assert(a.updates == count + 2)
-- Only eligible non-player public raid tokens are throttled.
m:LorenzoPatch105SetRaidPerformanceMode(true)
for _, unit in ipairs({"party1", "player", "target", "raid40", secret}) do
    assert(not m:LorenzoPatch105ShouldThrottleRaidUnitAura(unit))
    assert(not m:LorenzoPatch105ShouldThrottleRaidUnitAura(unit))
end
raid = false
assert(not m:LorenzoPatch105ShouldThrottleRaidUnitAura("raid1"))
'''
        result = subprocess.run([lua, "-"], input=harness + throttle + handler + lifecycle + ticker + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
