"""Exercise native-container lifecycle with Lua 5.1 mocks (not WoW protection)."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ImportantDebuffsInitializationTest(unittest.TestCase):
    def test_initialization_lifecycle(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/ImportantDebuffs/ImportantDebuffs.lua").read_text()
        harness = r'''
local module = setmetatable({}, {__index = function() return function() end end})
PitBull4 = {L = setmetatable({}, {__index = function(_, k) return k end})}
function PitBull4:NewModule() return module end
local db
function module:SetDefaults(value) db = value end
function module:GetLayoutDB() return db end
local combat = false
function InCombatLockdown() return combat end
AuraContainerSortMethod = {}
AuraContainerSortDirection = {}
AnchorUtil = {FlowLayoutAxis = {}, FlowDirection = {}}
local objects, attempts = {}, 0
local fail_at
local methods = {}
function methods:GetFrameLevel() return 1 end
function methods:Hide() self.hidden = true end
function methods:Show() self.hidden = false end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetUnit(value) self.unit = value end
function methods:AddAuraGroup()
    if fail_at == "group" then error("group failed") end
end
function CreateFrame(kind)
    assert(not combat, "construction in combat")
    attempts = attempts + 1
    if kind == "AuraContainer" and fail_at == "create" then error("create failed") end
    local obj = setmetatable({kind = kind}, {__index = function(_, key)
        return methods[key] or function() end
    end})
    objects[#objects + 1] = obj
    return obj
end
local frame = {unit = "party1", GetFrameLevel = methods.GetFrameLevel}
function module:UpdateAll() self:UpdateFrame(frame) end
'''
        checks = r'''
module:OnEnable()
combat = true
module:UpdateFrame(frame)
module:UpdateFrame(frame)
assert(attempts == 0, "initial creation was not deferred")
combat = false
module:PLAYER_REGEN_ENABLED()
assert(attempts == 2)
local first_holder, first_container = objects[1], objects[2]
combat = true
module:UpdateFrame(frame)
assert(attempts == 2 and first_container.enabled)
db.icon_size = 40
module:UpdateFrame(frame)
assert(attempts == 2 and first_container.enabled and not first_holder.hidden,
       "layout replacement retired active display in combat")
combat = false
fail_at = "group"
module:PLAYER_REGEN_ENABLED()
assert(attempts == 4)
assert(objects[3].hidden and objects[4].hidden and not objects[4].enabled)
assert(objects[4].unit == "none", "partial container retained unit")
module:UpdateFrame(frame)
assert(attempts == 4, "failure retried on ordinary update")
fail_at = nil
module:PLAYER_REGEN_ENABLED()
assert(attempts == 6 and objects[6].enabled, "same signature did not recover")
-- A failure before a container exists still hides the partial holder.
db.icon_size = 41
fail_at = "create"
module:UpdateFrame(frame)
assert(attempts == 8 and objects[7].hidden)
module:UpdateFrame(frame)
assert(attempts == 8)
-- Missing prerequisites remain cached between explicit retry events.
db.icon_size = 42
AnchorUtil = nil
module:UpdateFrame(frame)
module:UpdateFrame(frame)
assert(attempts == 8)
assert(module:Lorenzo121StatusLine():find("failures=1", 1, true))
module:PLAYER_REGEN_ENABLED()
module:UpdateFrame(frame)
assert(attempts == 8)
AnchorUtil = {FlowLayoutAxis = {}, FlowDirection = {}}
fail_at = nil
module:ADDON_LOADED("ADDON_LOADED", "Blizzard_AuraContainer")
assert(attempts == 10 and objects[#objects].enabled)
-- Retired complete states remain reusable without constructing duplicates.
db.icon_size = 30
module:UpdateFrame(frame)
assert(attempts == 10 and first_container.enabled and not first_holder.hidden)
'''
        result = subprocess.run([lua, "-"], input=harness + source + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
