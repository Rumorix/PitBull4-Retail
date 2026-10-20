"""Exercise the actual LuaTexts lifecycle functions with Lua 5.1 and API stubs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LuaTextsEventsTest(unittest.TestCase):
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
local offline_cache, dead_cache = {}, {}
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
module:OnHide(frame)
assert(no_update[fs] and not fs.shown)
module:AddFontString(frame, fs, "Lua:Здоровье")
assert(not no_update[fs] and fs.shown)
assert(not event_cache.UNIT_POWER_UPDATE and removals.UNIT_POWER_UPDATE == 1)
assert(event_cache.UNIT_HEALTH[fs] and registrations.UNIT_HEALTH == 1)
fs.db.events = {}
module:AddFontString(frame, fs, "Lua:Здоровье")
assert(not event_cache.UNIT_HEALTH[fs] and event_cache.UNIT_HEALTH[other])
module:RemoveFontString(other)
assert(not event_cache.UNIT_HEALTH and removals.UNIT_HEALTH == 1)
module:RemoveFontString(fs)
assert(not texts[fs] and not fs.frame)
'''
        result = subprocess.run([lua, "-"], input=protected + harness + lifecycle + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
