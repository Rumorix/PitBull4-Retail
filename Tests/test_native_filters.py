"""Exercise the public-settings compiler with Lua 5.1, without WoW APIs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeFiltersTest(unittest.TestCase):
    def test_supported_and_unsupported_selections(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/Aura/NativeFilters_12_1.lua").read_text()
        harness = r'''
local aura = {db = {profile = {global = {native_filters = {}}}}}
PitBull4 = {L = setmetatable({}, {__index = function(_, k) return k end})}
function PitBull4:GetModule() return aura end
'''
        checks = r'''
-- A restrictive compound rule and its references must remain untouched.
local rule = {filter_type = "Meta", filters = {"spell-list", "@H"}, operators = {"&"}}
aura.filters = {custom = rule, ["spell-list"] = {filter_type = "Name"}}
local refs, ops = rule.filters, rule.operators
for _, buff in ipairs({true, false}) do
    for _, id in ipairs({"custom", "missing", "@H", "!B", "!C", "!D", "!E", "!M", "!N", "!P", "!Q"}) do
        local spec = aura:GetNativeFilterSpec(id, buff)
        assert(spec.blocked and spec.mode == "unsupported-legacy:" .. id, id)
        assert(spec.signature:find(id, 1, true))
    end
    for _, id in ipairs({"", "native:all", "native:mine", "native:other"}) do
        local spec = aura:GetNativeFilterSpec(id, buff)
        assert(not spec.blocked and spec.filterString == (buff and "HELPFUL" or "HARMFUL"))
        local expected = id == "native:mine" and "mine" or id == "native:other" and "other" or "all"
        assert(spec.ownership == expected)
    end
    assert(not aura:GetNativeFilterSpec(nil, buff).blocked)
    assert(aura:GetNativeFilterSpec("native:missing", buff).blocked)
end
assert(aura.filters.custom == rule and rule.filters == refs and rule.operators == ops)
assert(refs[1] == "spell-list" and refs[2] == "@H" and ops[1] == "&")
assert(aura:GetNativeFilterValues("buff", "custom").custom == "Legacy filter: custom")
local definitions = aura.db.profile.global.native_filters
definitions["native:test"] = {name = "Test", category = "all", ownership = "mine",
    display_when = "buff", include_spell_ids = "123, 456", exclude_spell_ids = "789", max_duration = 30}
local spec = aura:GetNativeFilterSpec("native:test", true)
assert(not spec.blocked and spec.scope == "help" and spec.ownership == "mine")
assert(spec.candidateFilters.includeSpellIDs[123] and spec.candidateFilters.includeSpellIDs[456])
assert(spec.candidateFilters.excludeSpellIDs[789] and spec.candidateFilters.maxDuration == 30)
assert(aura:GetNativeFilterSpec("native:test", false).blocked)
definitions["native:test"].exclude_spell_ids = "123"
assert(aura:GetNativeFilterSpec("native:test", true).blocked)
assert(not aura:GetNativeFilterSpec("native:defensive", true).blocked)
assert(aura:GetNativeFilterSpec("native:defensive", false).blocked)
assert(aura:GetNativeFilterSpec("native:dispellable", false).filterString == "HARMFUL|RAID_PLAYER_DISPELLABLE")
assert(aura:GetNativeFilterSpec("native:priority", false).candidateFilters.isPriorityAura)
'''
        result = subprocess.run([lua, "-"], input=harness + source + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
