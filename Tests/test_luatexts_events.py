"""Exercise the actual LuaTexts lifecycle functions with Lua 5.1 and API stubs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LuaTextsEventsTest(unittest.TestCase):
    def test_unit_retry_sequence(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/LuaTexts/LuaTexts.lua").read_text()
        helpers = source[source.index("local compare_units\n"):
                         source.index("local first = true")]
        timers = source[source.index("-- Timed updates\n"):
                        source.index("function PitBull4_LuaTexts:OnNewLayout")]
        harness = r'''
local texts, no_update, unit_retries, to_update = {}, {}, {}, {}
local hp_cache = {}
local PitBull4_LuaTexts = {}
local timerframe = {}
function timerframe:SetScript(_, callback) self.tick = callback end
local function fix_cast_data() end
local function update_timers() end
local function update_cast_data() end
local updates = {}
local function update_text(fs, event)
    updates[fs] = (updates[fs] or 0) + 1
end
function PitBull4_LuaTexts:OnEvent(event)
    -- An immediate event-driven timer request must survive retry scheduling.
    for fs in pairs(texts) do to_update[fs] = 0 end
end
local restricted = false
function ShouldUnitComparisonBeSecret() return restricted end
function UnitIsUnit(a, b)
    if a == "alias" then return b == "target" or b == "targettarget" end
    return a == b
end
'''
        checks = r'''
local function font(unit)
    local fs = {frame = {unit = unit}}
    texts[fs] = true
    return fs
end
local target, focus, alias = font("target"), font("focus"), font("alias")
local child = font("targettarget")
local hidden = font("target")
no_update[hidden] = true
PitBull4_LuaTexts:PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED")
PitBull4_LuaTexts:PLAYER_FOCUS_CHANGED("PLAYER_FOCUS_CHANGED")
assert(not unit_retries[hidden])
local function tick(elapsed) timerframe.tick(timerframe, elapsed) end
-- Ordinary timer requests still execute before the recovery deadlines.
local before = updates[target]
tick(0.01)
assert(updates[target] == before + 1)
before = updates[target]
local alias_before, child_before = updates[alias], updates[child]
tick(0.08)
assert(updates[target] == before + 1 and updates[focus] == 3)
assert(updates[alias] == alias_before + 1, "overlapping matches must coalesce")
assert(updates[child] == child_before + 1 and not unit_retries[child])
before = updates[target]
tick(0.22)
assert(updates[target] == before + 1 and updates[focus] == 4)
assert(updates[alias] == alias_before + 2 and not next(unit_retries))
-- A later text-requested timer survives both recovery attempts.
to_update[target] = 0.5
schedule_texts_for_unit("target", 0.08)
schedule_texts_for_unit("target", 0.30)
before = updates[target]
tick(0.09)
tick(0.22)
assert(updates[target] == before + 2 and to_update[target] > 0)
tick(0.20)
assert(updates[target] == before + 3 and not to_update[target])
-- Repeated transitions reset deadlines instead of accumulating retries.
schedule_texts_for_unit("target", 0.08)
tick(0.04)
schedule_texts_for_unit("target", 0.08)
before = updates[target]
tick(0.05)
assert(updates[target] == before)
tick(0.04)
assert(updates[target] == before + 1)
-- Reassignment, hiding, and restricted comparisons discard obsolete work.
schedule_texts_for_unit("target", 0.08)
target.frame.unit = "player"
no_update[alias] = true
before = updates[target]
tick(0.09)
assert(updates[target] == before and not next(unit_retries))
target.frame.unit = "target"
schedule_texts_for_unit("target", 0.08)
restricted = true
tick(0.09)
assert(updates[target] == before and not next(unit_retries))
'''
        result = subprocess.run([lua, "-"], input=harness + helpers + timers + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_reused_subscriptions(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/LuaTexts/LuaTexts.lua").read_text()
        lifecycle = source[source.index("local function event_cache_insert("):
                           source.index("-- Handle updating after a config change")]
        protected = source[source.index("local protected_events = {"):
                           source.index("-- Provide a way to update changed events")]
        harness = r'''
local texts, no_update, event_cache = {}, {}, {}
local power_cache, hp_cache, mouseover_check_cache = {}, {}, {}
local spell_cast_cache, to_update, afk_cache, dnd_cache = {}, {}, {}, {}
local offline_cache, dead_cache, unit_retries = {}, {}, {}
local registered, registrations, removals = {}, {}, {}
local PitBull4_LuaTexts = {}
function PitBull4_LuaTexts:RegisterEvent(event, handler)
    assert(handler == "OnEvent")
    registered[event] = true
    registrations[event] = (registrations[event] or 0) + 1
end
function PitBull4_LuaTexts:UnregisterEvent(event)
    assert(not protected_events[event], "support event unregistered")
    registered[event] = nil
    removals[event] = (removals[event] or 0) + 1
end
local updates, casts = {}, 0
local function update_text(fs, event)
    updates[fs] = {event, fs.db.code}
end
local function update_cast_data(event, unit)
    assert(unit == "player")
    casts = casts + 1
end
'''
        # Declare the real support-event table before the stubs that close over it.
        checks = r'''
local module = PitBull4_LuaTexts
local frame = {unit = "player"}
local function font(events)
    return {db = {events = events, code = "health"},
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end}
end
local fs = font({UNIT_HEALTH = true, UNIT_MAXHEALTH = true,
                 PLAYER_TARGET_CHANGED = true})
local other = font({UNIT_HEALTH = true})
module:AddFontString(frame, fs, "Lua:Здоровье")
module:AddFontString(frame, other, "Other")
assert(updates[fs][1] == "_new")
spell_cast_cache[fs] = true
fs.db = {events = {UNIT_POWER_UPDATE = true, UNIT_MAXHEALTH = false}, code = "power"}
module:AddFontString(frame, fs, "Lua:Здоровье")
assert(not event_cache.UNIT_HEALTH[fs] and event_cache.UNIT_HEALTH[other])
assert(registered.UNIT_HEALTH and not removals.UNIT_HEALTH)
assert(not event_cache.UNIT_MAXHEALTH and removals.UNIT_MAXHEALTH == 1)
assert(not event_cache.PLAYER_TARGET_CHANGED and not removals.PLAYER_TARGET_CHANGED)
assert(event_cache.UNIT_POWER_UPDATE[fs] and registered.UNIT_POWER_UPDATE)
assert(updates[fs][1] == "_update" and updates[fs][2] == "power" and casts == 1)
module:AddFontString(frame, fs, "Lua:Здоровье")
assert(registrations.UNIT_POWER_UPDATE == 1 and removals.UNIT_MAXHEALTH == 1)
-- In-place edits must also reconcile, without relying on table identity.
fs.db.events.UNIT_POWER_UPDATE = false
fs.db.events.UNIT_HEALTH = true
unit_retries[fs] = {}
module:OnHide(frame)
assert(not unit_retries[fs])
assert(no_update[fs] and not fs.shown)
unit_retries[fs] = {}
module:AddFontString(frame, fs, "Lua:Здоровье")
assert(not unit_retries[fs])
assert(not no_update[fs] and fs.shown)
assert(not event_cache.UNIT_POWER_UPDATE and removals.UNIT_POWER_UPDATE == 1)
assert(event_cache.UNIT_HEALTH[fs] and registrations.UNIT_HEALTH == 1)
fs.db.events = {}
module:AddFontString(frame, fs, "Lua:Здоровье")
assert(not event_cache.UNIT_HEALTH[fs] and event_cache.UNIT_HEALTH[other])
module:RemoveFontString(other)
assert(not event_cache.UNIT_HEALTH and removals.UNIT_HEALTH == 1)
unit_retries[fs] = {}
module:RemoveFontString(fs)
assert(not unit_retries[fs])
assert(not texts[fs] and not fs.frame)
'''
        result = subprocess.run([lua, "-"], input=protected + harness + lifecycle + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
