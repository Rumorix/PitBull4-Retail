"""Exercise RefreshGroup's secure attributes with Lua 5.1 and header stubs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GroupHeaderExclusionTest(unittest.TestCase):
    def test_grouping_transitions(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "GroupHeader.lua").read_text()
        refresh = source[source.index("function GroupHeader:RefreshGroup("):
                         source.index("--- Recheck the layout of the group header")]
        harness = r'''
local GroupHeader = {}
local GROUPING_ORDER = {GROUP = "1,2", CLASS = function() return "WARRIOR,PRIEST" end,
                        ASSIGNEDROLE = function() return "TANK,HEALER,DAMAGER" end}
local DIRECTION_TO_POINT = {down = "TOP"}
local DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER = {down = -1}
local DIRECTION_TO_COLUMN_ANCHOR_POINT = {down = "LEFT"}
local GROUP_ROLES = {}
local combat, pending = false, nil
local PitBull4 = {db = {profile = {layouts = {normal = {}}}},
                 unit_group_to_headers = {raid = {}, party = {}},
                 super_unit_group_to_headers = {raid = {}, party = {}},
                 Utils = {IsWackyUnitGroup = function() return false end}}
-- Model the wrapper boundary; this does not test Blizzard combat protection.
function PitBull4:OutOfCombatWrapper(fn)
    return function(self, ...)
        if combat then pending = function() fn(self) end
        else return fn(self, ...) end
    end
end
local function build_raid_name_list_without_main_tanks(db)
    return "NonTankB,NonTankA"
end
'''
        checks = r'''
local db = {layout = "normal", unit_group = "raid", enabled = true,
            show_when = {solo = true, party = true, raid = true},
            sort_method = "NAME", sort_direction = "DESC", direction = "down",
            horizontal_spacing = 0, vertical_spacing = 0, units_per_column = 5}
local header = setmetatable({group_db = db, attributes = {}}, {__index = GroupHeader})
function header:SetAttribute(key, value) self.attributes[key] = value end
function header:IterateMembers() return function() end end
function header:IsShown() return false end
function header:Hide() end
function header:UnforceShow() end
function header:GetMaxUnits() return 40 end
function header:RefixSizeAndPosition() end
for _, mode in ipairs({"GROUP", "CLASS", "ROLE", "ASSIGNEDROLE", false}) do
    db.group_by = mode or nil
    db.exclude_main_tanks = false
    header:RefreshGroup()
    assert(header.attributes.groupBy == db.group_by)
    local order = header.attributes.groupingOrder
    db.exclude_main_tanks = true
    header:RefreshGroup()
    assert(header.attributes.groupBy == nil, "exclusion retained grouping")
    assert(header.attributes.groupingOrder == order)
    assert(header.attributes.sortMethod == "NAMELIST" and header.attributes.sortDir == "ASC")
    assert(header.attributes.nameList == "NonTankB,NonTankA")
    assert(header.attributes.groupFilter == nil)
    assert(db.group_by == (mode or nil) and header.group_by == db.group_by)
    -- Restoring the configured grouping must wait at the existing wrapper boundary.
    combat = true
    db.exclude_main_tanks = false
    header:RefreshGroup()
    assert(header.attributes.groupBy == nil)
    combat = false
    pending()
    assert(header.attributes.groupBy == db.group_by)
    assert(header.attributes.sortMethod == "NAME" and header.attributes.sortDir == "DESC")
    assert(header.attributes.nameList == nil)
end
-- Exact main-tank filters and party headers do not activate raid exclusion.
db.group_by = "CLASS"
db.exclude_main_tanks = true
db.group_filter = "MAINTANK"
header:RefreshGroup()
assert(header.attributes.groupBy == "CLASS" and header.attributes.groupFilter == "MAINTANK")
db.group_filter = nil
db.unit_group = "party"
header:RefreshGroup()
assert(header.attributes.groupBy == "CLASS" and header.attributes.sortMethod == "NAME")
'''
        result = subprocess.run([lua, "-"], input=harness + refresh + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
