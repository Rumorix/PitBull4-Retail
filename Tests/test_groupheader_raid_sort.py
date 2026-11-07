"""Run the real raid whitelist builder with public-value Lua 5.1 fixtures."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RaidSortTest(unittest.TestCase):
    def test_raid_whitelist_order(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "GroupHeader.lua").read_text()
        grouping = source[source.index("local GROUPING_ORDER = {}"):
                          source.index("local function position_label(")]
        builder = source[source.index("local function build_raid_name_list_without_main_tanks("):
                         source.index("function GroupHeader:RefreshGroup(")]
        setup = r'''
assert(_VERSION == "Lua 5.1")
local NUM_RAID_GROUPS, MAX_RAID_MEMBERS = 8, 40
local PitBull4 = {ClassOrder = {"MAGE", "WARRIOR"},
                  RoleOrder = {"HEALER", "TANK", "DAMAGER"}}
local oRA3, roster
local function issecretvalue() return false end
function GetNumGroupMembers() return #roster end
function GetRaidRosterInfo(i)
    local r = roster[i]
    return r.name, nil, r.subgroup, nil, nil, r.class_name,
           nil, nil, nil, r.role, nil, r.assigned_role
end
local original_sort = table.sort
local captured
table.sort = function(records, less)
    captured = less
    for _, a in ipairs(records) do
        assert(not less(a, a), "irreflexivity")
        for _, b in ipairs(records) do
            assert(not (less(a, b) and less(b, a)), "asymmetry")
            for _, c in ipairs(records) do
                if less(a, b) and less(b, c) then
                    assert(less(a, c), "transitivity")
                end
            end
        end
    end
    original_sort(records, less)
end
'''
        checks = r'''
local function member(name, group, class, role, assigned)
    return {name = name, subgroup = group, class_name = class,
            role = role, assigned_role = assigned}
end
roster = {
    member("Zulu", 2, "WARRIOR", "MAINASSIST", "TANK"),
    member("Alpha", 1, "MAGE", nil, "HEALER"),
    member("Bravo", 1, "MAGE", nil, "DAMAGER"),
    member("Alpha", 1, "MAGE", nil, "HEALER"),
    member("Unknown", 9, "UNKNOWN", "UNKNOWN", "UNKNOWN"),
    member("Tank", 1, "MAGE", "MAINTANK", "TANK"),
}
local function check(db, expected)
    assert(build_raid_name_list_without_main_tanks(db) == expected)
end
check({sort_direction = "DESC"}, "Unknown,Alpha,Bravo,Alpha,Zulu")
check({}, "Zulu,Alpha,Bravo,Alpha,Unknown")
check({sort_method = "NAME"}, "Alpha,Alpha,Bravo,Unknown,Zulu")
-- Capture and test the final roster-index tie-break for equal names.
assert(captured({name="Alpha", index=2}, {name="Alpha", index=4}))
check({sort_method = "NAME", sort_direction = "DESC"},
      "Zulu,Unknown,Bravo,Alpha,Alpha")
assert(captured({name="Alpha", index=4}, {name="Alpha", index=2}))
for _, group_by in ipairs({"GROUP", "CLASS"}) do
    check({group_by=group_by, sort_method="NAME"},
          "Alpha,Alpha,Bravo,Zulu,Unknown")
    check({group_by=group_by, sort_method="NAME", sort_direction="DESC"},
          "Unknown,Zulu,Bravo,Alpha,Alpha")
end
check({group_by="ASSIGNEDROLE", sort_method="NAME"},
      "Alpha,Alpha,Zulu,Bravo,Unknown")
check({group_by="ASSIGNEDROLE", sort_method="NAME", sort_direction="DESC"},
      "Unknown,Bravo,Zulu,Alpha,Alpha")
check({group_by="GROUP", group_filter="1", sort_direction="DESC"},
      "Alpha,Bravo,Alpha")
oRA3 = {GetSortedTanks = function() return {"Zulu"} end}
check({sort_method="NAME"}, "Alpha,Alpha,Bravo,Unknown")
oRA3 = nil

-- Exercise every grouping/method/direction on a full, deliberately mixed roster.
-- Build expected output independently with explicit lexicographic key comparisons.
roster = {}
local classes, roles = {"MAGE", "WARRIOR", "UNKNOWN"},
                       {"HEALER", "TANK", "DAMAGER", "UNKNOWN"}
for i = 1, 40 do
    roster[i] = member("Name" .. (i % 7), i % 9 + 1,
                       classes[i % 3 + 1], nil, roles[i % 4 + 1])
end
for _, group_by in ipairs({false, "GROUP", "CLASS", "ROLE", "ASSIGNEDROLE"}) do
    for _, method in ipairs({"INDEX", "NAME"}) do
        for _, direction in ipairs({"ASC", "DESC"}) do
            local expected = {}
            for i, r in ipairs(roster) do
                local rank = 999
                if group_by == "GROUP" then
                    rank = r.subgroup <= 8 and r.subgroup or 999
                elseif group_by == "CLASS" then
                    rank = ({MAGE=1, WARRIOR=2})[r.class_name] or 999
                elseif group_by == "ASSIGNEDROLE" then
                    rank = ({HEALER=1, TANK=2, DAMAGER=3})[r.assigned_role] or 999
                end
                expected[i] = {rank, method == "NAME" and r.name or "", i}
            end
            original_sort(expected, function(a, b)
                for k = 1, 3 do
                    if a[k] ~= b[k] then
                        if direction == "ASC" then return a[k] < b[k] end
                        return a[k] > b[k]
                    end
                end
                return false
            end)
            local names = {}
            for i, key in ipairs(expected) do names[i] = roster[key[3]].name end
            check({group_by=group_by, sort_method=method, sort_direction=direction},
                  table.concat(names, ","))
        end
    end
end
roster = {member("Only", 1, "MAGE")}
check({sort_direction="DESC"}, "Only")
roster[1].role = "MAINTANK"
check({}, "")
roster = {}
assert(build_raid_name_list_without_main_tanks({}) == nil)
'''
        result = subprocess.run([lua, "-"], input=setup + grouping + builder + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
