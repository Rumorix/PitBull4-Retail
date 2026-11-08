"""Exercise the raid whitelist helper with Lua 5.1 and mocked secret roles."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GroupHeaderRolesTest(unittest.TestCase):
    def test_role_sanitization(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "GroupHeader.lua").read_text()
        helper = source[source.index("local function build_raid_name_list_without_main_tanks("):
                        source.index("function GroupHeader:RefreshGroup(")]
        harness = r'''
local MAX_RAID_MEMBERS = 40
local GROUPING_ORDER = {ROLE = "MAINTANK,MAINASSIST",
                       ASSIGNEDROLE = function() return "TANK,HEALER,DAMAGER" end}
local roster, secrets = {}, {}
function GetNumGroupMembers() return #roster end
function GetRaidRosterInfo(index) return unpack(roster[index], 1, 12) end
function issecretvalue(value) return secrets[value] or false end
local function member(name, role, assigned)
    return {name, 0, 1, 80, "Mage", "MAGE", nil, nil, nil, role, nil, assigned}
end
'''
        checks = r'''
local function expect(expected, config)
    local actual = build_raid_name_list_without_main_tanks(config or {})
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
expect(nil)
roster = {member("Tank", "MAINTANK", "TANK"),
          member("Assist", "MAINASSIST", "HEALER"), member("Unknown")}
expect("Assist,Unknown")
expect("Assist", {group_filter = "HEALER"})
expect("Assist", {group_filter = "MAINASSIST"})
expect("Assist,Unknown", {group_filter = "1"})
expect("Assist,Unknown", {group_filter = "MAGE"})
expect("Unknown,Assist", {sort_method = "NAME", sort_direction = "DESC"})
-- Flag recognizable strings so accidental comparisons/indexing have observable
-- effects. These are predicate mocks, not actual WoW restricted values.
secrets = {MAINTANK = true}
expect("Tank,Assist,Unknown")
expect("", {group_filter = "MAINTANK"})
expect("Tank", {group_filter = "TANK"})
expect("Assist,Tank,Unknown", {group_by = "ROLE"})
secrets = {TANK = true}
roster = {member("Unknown", nil, "TANK"), member("Healer", nil, "HEALER")}
expect("Unknown,Healer")
expect("", {group_filter = "TANK"})
expect("Healer,Unknown", {group_by = "ASSIGNEDROLE"})
secrets = {MAINTANK = true, TANK = true}
roster = {member("Hidden-Realm", "MAINTANK", "TANK"), member("Public", nil, "HEALER")}
expect("Hidden-Realm,Public")
expect("", {group_filter = "MAINTANK,TANK"})
expect("Public,Hidden-Realm", {group_by = "ASSIGNEDROLE"})
-- Public oRA3 assignments still exclude a tank when roster roles are unknown.
oRA3 = {GetSortedTanks = function() return {"Hidden"} end}
expect("Public")
oRA3.GetSortedTanks = function() return {"Hidden-Realm"} end
expect("Public")
'''
        result = subprocess.run([lua, "-"], input=harness + helper + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
