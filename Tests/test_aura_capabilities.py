"""Exercise Aura's capability rescans with Lua 5.1 and public spellbook stubs."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AuraCapabilitiesTest(unittest.TestCase):
    def test_capability_gain_and_loss(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/Aura/Filter.lua").read_text()
        capabilities = source[source.index("-- Set what types of auras you can dispel"):
                              source.index("--- Return the DB dictionary")]
        harness = r'''
local PitBull4_Aura = {}
local known = {[0] = {}, [1] = {}}
local function IsSpellKnownOrInSpellBook(id, bank)
    assert(bank == 0 or bank == 1, "unexpected spell bank")
    return known[bank][id] or false
end
'''
        checks = r'''
local module = PitBull4_Aura
local dispel, purge = module.can_dispel, module.can_purge
local function scan(expected_dispel, expected_purge)
    module:PLAYER_TALENT_UPDATE()
    assert(module.can_dispel == dispel and module.can_purge == purge,
           "exported table identity changed")
    for _, kind in ipairs({"Magic", "Disease", "Poison", "Curse", "Enrage"}) do
        assert(dispel[kind] == expected_dispel[kind], "dispel mismatch: " .. kind)
        assert(purge[kind] == expected_purge[kind], "purge mismatch: " .. kind)
    end
end
scan({}, {})
-- Gain all supported types, then lose them on the next scan.
known[0] = {[527] = true, [213634] = true, [2782] = true, [19801] = true}
scan({Magic = true, Disease = true, Poison = true, Curse = true},
     {Magic = true, Enrage = true})
scan({Magic = true, Disease = true, Poison = true, Curse = true},
     {Magic = true, Enrage = true})
known[0] = {}
scan({}, {})
-- An alternative spell continues to supply a capability after one is lost.
known[0] = {[527] = true, [4987] = true, [528] = true, [370] = true}
scan({Magic = true}, {Magic = true})
known[0] = {[4987] = true, [370] = true}
scan({Magic = true}, {Magic = true})
known[0] = {}
scan({}, {})
-- Pet spell-bank capabilities are gained and revoked independently.
known[1] = {[89808] = true, [19505] = true}
scan({Magic = true}, {Magic = true})
known[1] = {}
scan({}, {})
known[0] = {[89808] = true, [19505] = true}
scan({}, {})
'''
        result = subprocess.run([lua, "-"], input=harness + capabilities + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
