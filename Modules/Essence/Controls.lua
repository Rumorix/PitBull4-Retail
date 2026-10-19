
local PitBull4 = _G.PitBull4

-----------------------------------------------------------------------------

local Essence = {}
local Essence_scripts = {}

-- GetPowerRegenForPowerType can be secret even for the active player. Only
-- ordinary numbers may participate in Lua arithmetic. Keep Blizzard's normal
-- five-second animation when the client withholds the actual regeneration.
function PitBull4.Controls.GetEssenceAnimationMultiplier()
	local ok, regen = pcall(GetPowerRegenForPowerType, Enum.PowerType.Essence)
	if not ok or PitBull4.Utils.IsSecretValue(regen) or type(regen) ~= "number" or regen <= 0 or regen ~= regen or regen == math.huge then
		return 1
	end
	return 5 * regen
end

function Essence:OnUpdate()
	local multiplier = PitBull4.Controls.GetEssenceAnimationMultiplier()
	self.EssenceFilling.FillingAnim:SetAnimationSpeedMultiplier(multiplier)
	self.EssenceFilling.CircleAnim:SetAnimationSpeedMultiplier(multiplier)
end

function Essence_scripts:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(_G.POWER_TYPE_ESSENCE)
	GameTooltip:AddLine(_G.ESSENCE_TOOLTIP, nil, nil, nil, true)
	GameTooltip:Show()
end

function Essence_scripts:OnLeave()
	GameTooltip:Hide()
end

PitBull4.Controls.MakeNewControlType("EssenceIcon", "Frame", function(control)
	-- onCreate
	for k, v in pairs(Essence) do
		control[k] = v
	end
	for k, v in pairs(Essence_scripts) do
		control:SetScript(k, v)
	end

end, function(control, id)
	-- onRetrieve
	control.layoutIndex = id

end, function(control)
	-- onDelete
	control:SetScript("OnUpdate", nil)
	control.EssenceFilling.FillingAnim:Stop()
	control.EssenceFilling.CircleAnim:Stop()
	control.layoutIndex = nil

end, "EssencePointButtonTemplate")
