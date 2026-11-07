"""Run CombatText with Lua 5.1 stubs; secret sentinels model rejected payloads."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CombatTextSecretsTest(unittest.TestCase):
    def test_secret_payloads_and_preview(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("Lua 5.1 is required")
        source = (ROOT / "Modules/CombatText/CombatText.lua").read_text()
        harness = r'''
COMBATFEEDBACK_FADEINTIME = 1
COMBATFEEDBACK_HOLDTIME = 1
COMBATFEEDBACK_FADEOUTTIME = 1
local module = setmetatable({}, {__index = function() return function() end end})
function module:GetFont() return "font", 12 end
local timer = {Hide = function(self) self.shown = false end,
               Show = function(self) self.shown = true end,
               SetScript = function() end}
function CreateFrame() return timer end
local fs = {size_modifier = 1, writes = 0}
function fs:SetText(text) self.text = text; self.writes = self.writes + 1 end
function fs:GetText() return self.text end
function fs:SetFont() end
function fs:SetTextColor() end
function fs:SetAlpha(alpha) self.alpha = alpha end
local frame = {unit = "target", CombatText = fs}
PitBull4 = {L = setmetatable({}, {__index = function(_, key) return key end})}
function PitBull4:NewModule() return module end
local iterations = 0
function PitBull4:IterateFramesForUnitID(unit)
    iterations = iterations + 1
    local done = false
    return function() if not done then done = true; return frame end end
end
function UnitExists() return false end
local group = false
function UnitInAnyGroup() return group end
local now = 0
function GetTime() return now end
CombatFeedbackText = {IMMUNE = "Immune", BLOCK = "Block", ABSORB = "Absorb"}
local secret = setmetatable({}, {
    __unm = function() error("secret arithmetic") end,
    __tostring = function() error("secret conversion") end,
    __lt = function() error("secret comparison") end,
})
function issecretvalue(value) return rawequal(value, secret) end
'''
        checks = r'''
local function event(kind, flags, amount, school)
    module:UNIT_COMBAT("UNIT_COMBAT", "target", kind, flags or "", amount or 10, school or 4)
end
for _, kind in ipairs({"WOUND", "HEAL", "ENERGIZE", "IMMUNE"}) do
    local args = {"target", kind, "CRITICAL", 10, 4}
    for i = 1, 5 do
        local saved = args[i]
        args[i] = secret
        local writes, calls = fs.writes, iterations
        module:UNIT_COMBAT("UNIT_COMBAT", unpack(args))
        assert(fs.writes == writes and iterations == calls, "secret event was processed")
        args[i] = saved
    end
end
fs.text = secret
module:UpdateFrame(frame)
assert(rawequal(fs.text, secret))
frame.force_show = true
module:UpdateFrame(frame)
assert(fs.text == "123")
frame.force_show = false
module:UpdateFrame(frame)
assert(fs.text == "")
event("WOUND", "CRITICAL")
assert(fs.text == "-10" and fs.size_modifier == 1.5 and timer.shown)
module:UpdateFrame(frame)
assert(fs.text == "-10")
event("WOUND", "ABSORB", 0)
assert(fs.text == "Absorb" and fs.size_modifier == 0.75)
event("HEAL", "CRITICAL")
assert(fs.text == "+10" and fs.size_modifier == 1.3)
event("ENERGIZE")
assert(fs.text == "10" and fs.size_modifier == 1)
event("IMMUNE")
assert(fs.text == "Immune")
event("BLOCK")
assert(fs.text == "Block")
-- Secret group membership must not enter a Lua branch or write combat text.
group = secret
local saved_writes, saved_text = fs.writes, fs.text
event("WOUND", "", 15, 4)
assert(fs.writes == saved_writes and fs.text == saved_text, "secret group result was used")
group = false
event("WOUND", "", 15, 4)
assert(fs.text == "-15", "public group result stopped working")
now = 1.5
module:UpdateAlphas()
assert(fs.alpha == 0.6)
now = 4
module:UpdateAlphas()
assert(fs.alpha == 0 and not timer.shown)
-- Preserve compatibility when the optional predicate is absent.
issecretvalue = nil
event("HEAL")
assert(fs.text == "+10")
module:UpdateFrame(frame)
assert(fs.text == "+10")
'''
        result = subprocess.run([lua, "-"], input=harness + source + checks,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
