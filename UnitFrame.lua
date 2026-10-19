local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

-- luacheck: globals ChatFontNormal ClickCastHeader SecureButton_GetModifiedUnit

local DEBUG = PitBull4.DEBUG
local expect = PitBull4.expect
local frames_to_anchor = PitBull4.frames_to_anchor

-- CONSTANTS ----------------------------------------------------------------

local MODULE_UPDATE_ORDER = {
	"bar",
	"secret_bar",
	"bar_provider",
	"indicator",
	"text_provider",
	"custom_text",
	"custom",
	"fader",
}

-- Handles hiding and showing singleton unit frames.  Please no tabs in this code if you edit it.
-- WoW can't render tabs in FontStrings and it makes the errors from this code look awful.
local Singleton_OnAttributeChanged = [[
  if name ~= "state-pb4visibility" and name ~= "state-unitexists" and name ~= "config_mode" then return end

  if name ~= "state-pb4visibility" then
    -- Replace the value with the state handler state if we weren't called
    -- on its state change
    value = self:GetAttribute("state-pb4visibility")
  end

  if self:GetAttribute("config_mode") then
    self:Show()
  elseif value == "show" then
    self:Show()
  elseif value == "hide" then
    self:Hide()
  else
    if self:GetAttribute("state-unitexists") then
      self:Show()
    else
      self:Hide()
    end
  end
]]

-- Configure ping behavior for the local PitBull Player frame.
--
-- Patch 032 intentionally turned the complete Player frame into Blizzard's
-- player-resource ping surface. That restored health/power callouts, but it also
-- replaced the normal self/unit ping everywhere on the frame. Patch 096 keeps
-- both behaviors and makes the choice profile-scoped.
-- Patch 097 adds a mixed mode: only the resource bar rectangles request the
-- native resource callout, while the rest delegates to the original self ping.
--
-- The original PingableUnitFrameTemplate methods are captured before PitBull
-- overrides them so "Default self ping" can restore Blizzard's normal behavior
-- without trying to reproduce the ping target in addon code. The optional
-- resource mode only supplies the public player GUID and isPlayerResource marker;
-- Blizzard remains responsible for reading/rendering live health and power.
-- The native protocol has one shared resource flag, not separate HP/mana flags.
local function GetConfiguredPlayerPingBehavior()
	local db = PitBull4.db and PitBull4.db.profile
	local behavior = db and db.player_frame_ping_behavior
	if behavior == "resource" or behavior == "bars" then
		return behavior
	end
	return "default"
end

function PitBull4:GetPlayerPingBehavior()
	return GetConfiguredPlayerPingBehavior()
end

local function CaptureDefaultPlayerPingMethods(frame)
	if frame.lorenzo_player_ping_defaults_captured then
		return
	end
	frame.lorenzo_player_ping_defaults_captured = true
	frame.lorenzo_default_GetTargetInfo = frame.GetTargetInfo or false
	frame.lorenzo_default_GetAllowRadialWheel = frame.GetAllowRadialWheel or false
end

local function RestoreDefaultPlayerPingMethods(frame)
	local get_target_info = frame.lorenzo_default_GetTargetInfo
	local get_allow_radial = frame.lorenzo_default_GetAllowRadialWheel
	frame.GetTargetInfo = get_target_info ~= false and get_target_info or nil
	frame.GetAllowRadialWheel = get_allow_radial ~= false and get_allow_radial or nil
	frame.lorenzo_player_resource_ping = false
end

local PLAYER_RESOURCE_PING_BAR_IDS = { "HealthBar", "PowerBar", "DruidManaBar" }

local function IsMouseOverPlayerResourceBar(frame)
	for i = 1, #PLAYER_RESOURCE_PING_BAR_IDS do
		local bar = frame[PLAYER_RESOURCE_PING_BAR_IDS[i]]
		if bar then
			-- Use the full addon-owned bar rectangle, including its empty part.
			-- Never inspect the fill texture, live health, or live power values.
			local visible = bar:IsVisible()
			if not (_G.issecretvalue and _G.issecretvalue(visible)) and visible then
				local mouse_over = bar:IsMouseOver()
				if not (_G.issecretvalue and _G.issecretvalue(mouse_over)) and mouse_over then
					return true
				end
			end
		end
	end
	return false
end

local function GetPlayerResourcePingTargetInfo(frame)
	local target_info = frame.lorenzo_player_resource_target_info
	if not target_info then
		target_info = { isPlayerResource = true }
		frame.lorenzo_player_resource_target_info = target_info
	end
	target_info.guid = UnitGUID("player")
	return target_info
end

local function GetBarAwarePlayerPingTargetInfo(frame)
	if IsMouseOverPlayerResourceBar(frame) then
		return GetPlayerResourcePingTargetInfo(frame)
	end

	local original = frame.lorenzo_default_GetTargetInfo
	if original then
		return original(frame)
	end
	return {}
end

local function GetBarAwarePlayerAllowRadialWheel(frame)
	if IsMouseOverPlayerResourceBar(frame) then
		return false
	end

	local original = frame.lorenzo_default_GetAllowRadialWheel
	if original then
		return original(frame)
	end
	return true
end

local function ApplyPlayerPingBehavior(frame, unit)
	if unit ~= "player" then
		-- A profile/layout may reuse a former Player frame for Target/Focus.
		-- Drop only our previous Player override; ordinary targets retain their
		-- exact native template methods and forward their current unit GUID.
		if frame.lorenzo_player_ping_defaults_captured then
			RestoreDefaultPlayerPingMethods(frame)
		end
		return
	end

	CaptureDefaultPlayerPingMethods(frame)

	local behavior = GetConfiguredPlayerPingBehavior()
	if behavior == "default" then
		RestoreDefaultPlayerPingMethods(frame)
		return
	end

	if behavior == "bars" then
		frame.GetTargetInfo = GetBarAwarePlayerPingTargetInfo
		frame.GetAllowRadialWheel = GetBarAwarePlayerAllowRadialWheel
		frame.lorenzo_player_resource_ping = false
	else
		frame.GetTargetInfo = GetPlayerResourcePingTargetInfo
		frame.GetAllowRadialWheel = function()
			return false
		end
		frame.lorenzo_player_resource_ping = true
	end
end

function PitBull4:RefreshPlayerPingBehavior()
	if InCombatLockdown() then
		-- Avoid changing methods on a protected unit button during combat.
		self:RunOnLeaveCombat(self.RefreshPlayerPingBehavior, self)
		return
	end

	for frame in self:IterateSingletonFrames(true) do
		local classification_db = frame.classification_db
		if classification_db then
			ApplyPlayerPingBehavior(frame, classification_db.unit)
		end
	end
end

--- Make a singleton unit frame.
-- @param classification the classification of the Unit Frame
-- @usage local frame = PitBull4:MakeSingletonFrame("Player")
function PitBull4:MakeSingletonFrame(classification)
	if DEBUG then
		expect(classification, 'typeof', 'string')
	end

	local classification_db = PitBull4.db.profile.units[classification]
	if not classification_db then
		error(("Bad argument #1 to `MakeSingletonFrame'.  %q is not a singleton classification"):format(tostring(classification)),2)
	end

	local unit = classification_db.unit

	local id = PitBull4.Utils.GetBestUnitID(unit)
	if not PitBull4.Utils.IsSingletonUnitID(id) then
		error(("Bad unit set on Singleton Classification %q.  %q is not a singleton UnitID"):format(tostring(classification),tostring(unit)), 2)
	end
	unit = id

	local frame_name = "PitBull4_Frames_" .. classification
	local frame = _G[frame_name]

	if not frame then
		frame = CreateFrame("Button", frame_name, UIParent, "SecureUnitButtonTemplate,SecureHandlerBaseTemplate,PingableUnitFrameTemplate")

		frame:WrapScript(frame, "OnAttributeChanged", Singleton_OnAttributeChanged)
		frame.is_singleton = true

		frame.classification = classification
		frame.classification_db = classification_db

		frame.is_wacky = PitBull4.Utils.IsWackyUnitGroup(unit)

		self:ConvertIntoUnitFrame(frame)

		frame:SetAttribute("unit", unit)
	elseif frame.classification_db ~= classification_db then
		-- Previously deleted frame being reused, set the classification_db
		-- to its new classification_db.
		frame.classification_db = classification_db
	end

	frame:Activate()

	frame:RefreshLayout()

	frame:UpdateGUID(UnitGUID(unit))

	for frame_to_anchor, relative_to in pairs(frames_to_anchor) do
		local relative_frame = PitBull4.Utils.GetRelativeFrame(relative_to)
		if relative_frame == frame then
			frame_to_anchor:RefixSizeAndPosition()
		end
	end
end
PitBull4.MakeSingletonFrame = PitBull4:OutOfCombatWrapper(PitBull4.MakeSingletonFrame)

--- A Unit Frame created by PitBull4
-- @class table
-- @name UnitFrame
-- @field is_singleton whether the Unit Frame is a singleton or member
-- @field classification the classification of the Unit Frame
-- @field classification_db the database table for the Unit Frame's classification
-- @field layout the layout of the Unit Frame's classification
-- @field unit the UnitID of the Unit Frame. Can be nil.
-- @field guid the current GUID of the Unit Frame. Can be nil.
-- @field overlay an overlay frame for texts to be placed on.
local UnitFrame = {}
local SingletonUnitFrame = {}
local MemberUnitFrame = {}
PitBull4.UnitFrame = UnitFrame
PitBull4.SingletonUnitFrame = SingletonUnitFrame
PitBull4.MemberUnitFrame = MemberUnitFrame

local UnitFrame__scripts = {}
local SingletonUnitFrame__scripts = {}
local MemberUnitFrame__scripts = {}
PitBull4.UnitFrame__scripts = UnitFrame__scripts
PitBull4.SingletonUnitFrame__scripts = SingletonUnitFrame__scripts
PitBull4.MemberUnitFrame__scripts = MemberUnitFrame__scripts

function UnitFrame:ProxySetAttribute(key, value)
	if self:GetAttribute(key) ~= value then
		self:SetAttribute(key, value)
		return true
	end
end

-- Only listen for global releases while a PitBull drag is active. Another
-- overlay can receive the local mouse-up instead of the unit button.
local drag_release
local drag_owner, drag_stop
local function on_drag_release(_, _, button)
	if button == "LeftButton" and drag_owner then
		drag_stop(drag_owner)
	end
end

function PitBull4:BeginFrameDrag(frame, stop)
	if drag_owner == frame then return false end
	if drag_owner then
		drag_stop(drag_owner)
	end
	drag_owner, drag_stop = frame, stop
	if not drag_release then
		drag_release = CreateFrame("Frame")
		drag_release:SetScript("OnEvent", on_drag_release)
	end
	drag_release:RegisterEvent("GLOBAL_MOUSE_UP")
	return true
end

function PitBull4:EndFrameDrag(frame)
	if drag_owner ~= frame then return end
	drag_owner, drag_stop = nil, nil
	drag_release:UnregisterEvent("GLOBAL_MOUSE_UP")
end

local moving_frame, moving_sticky
function SingletonUnitFrame__scripts:OnDragStart()
	local db = PitBull4.db.profile
	if db.lock_movement or InCombatLockdown() then
		return
	end
	if not PitBull4:BeginFrameDrag(self, SingletonUnitFrame__scripts.OnDragStop) then return end

	self:StartMoving()
	moving_frame = self
	moving_sticky = db.frame_snap and LibStub("LibSimpleSticky-1.0") or nil

	if moving_sticky then
		-- stop thing is to make WoW move the frame the initial few pixels between
		-- OnMouseDown and OnDragStart
		self:StopMovingOrSizing()

		moving_sticky:StartMoving(self, PitBull4.all_frames_list, 0, 0, 0, 0)
	end
end

function SingletonUnitFrame__scripts:OnDragStop()
	if moving_frame ~= self then return end
	moving_frame = nil
	PitBull4:EndFrameDrag(self)
	local sticky = moving_sticky
	moving_sticky = nil
	if sticky then
		sticky:StopMoving(self)
	else
		self:StopMovingOrSizing()
	end

	local db = self.classification_db
	local anchor = db.anchor
	local relative_frame = PitBull4.Utils.GetRelativeFrame(db.relative_to)
	local relative_point = db.relative_point

	local ui_scale = UIParent:GetEffectiveScale()
	local scale = self:GetEffectiveScale() / ui_scale

	local x, y
	if anchor == "TOPLEFT" then
		x, y = self:GetLeft(), self:GetTop()
	elseif anchor == "TOPRIGHT" then
		x, y = self:GetRight(), self:GetTop()
	elseif anchor == "BOTTOMLEFT" then
		x, y = self:GetLeft(), self:GetBottom()
	elseif anchor == "BOTTOMRIGHT" then
		x, y = self:GetRight(), self:GetBottom()
	elseif anchor == "CENTER" then
		x, y = self:GetCenter()
	elseif anchor == "TOP" then
		x = self:GetCenter()
		y = self:GetTop()
	elseif anchor == "BOTTOM" then
		x = self:GetCenter()
		y = self:GetBottom()
	elseif anchor == "LEFT" then
		x, y = self:GetCenter()
		x = self:GetLeft()
	elseif anchor == "RIGHT" then
		x, y = self:GetCenter()
		x = self:GetRight()
	end
	x, y = x * scale, y * scale

	local scale2 = relative_frame:GetEffectiveScale() / ui_scale
	local x2,y2
	if relative_point == "TOPLEFT" then
		x2, y2 = relative_frame:GetLeft(), relative_frame:GetTop()
	elseif relative_point == "TOPRIGHT" then
		x2, y2 = relative_frame:GetRight(), relative_frame:GetTop()
	elseif relative_point == "BOTTOMLEFT" then
		x2, y2 = relative_frame:GetLeft(), relative_frame:GetBottom()
	elseif relative_point == "BOTTOMRIGHT" then
		x2, y2 = relative_frame:GetRight(), relative_frame:GetBottom()
	elseif relative_point == "CENTER" then
		x2, y2 = relative_frame:GetCenter()
	elseif relative_point == "TOP" then
		x2 = relative_frame:GetCenter()
		y2 = relative_frame:GetTop()
	elseif relative_point == "BOTTOM" then
		x2 = relative_frame:GetCenter()
		y2 = relative_frame:GetBottom()
	elseif relative_point == "LEFT" then
		x2, y2 = relative_frame:GetCenter()
		x2 = relative_frame:GetLeft()
	elseif relative_point == "RIGHT" then
		x2, y2 = relative_frame:GetCenter()
		x2 = relative_frame:GetRight()
	end
	x2, y2 = x2 * scale2, y2 * scale2

	x = x - x2
	y = y - y2

	db.position_x = x
	db.position_y = y

	LibStub("AceConfigRegistry-3.0"):NotifyChange("PitBull4")

	self:RefreshLayout()
end

function SingletonUnitFrame__scripts:OnMouseUp(button)
	if button == "LeftButton" then
		return SingletonUnitFrame__scripts.OnDragStop(self)
	end
end

function SingletonUnitFrame:PLAYER_REGEN_DISABLED()
	if moving_frame then
		SingletonUnitFrame__scripts.OnDragStop(moving_frame)
	end
end

function UnitFrame__scripts:OnEnter()
	if self.unit and UnitExists(self.unit) then
		local tooltip = self.classification_db.tooltip
		if tooltip == "always" or (tooltip == "ooc" and not InCombatLockdown()) then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			-- SetUnit is a Blizzard secure tooltip delegate in 12.1. Execute only
			-- that delegate and never recolor GameTooltipTextLeft1 from addon code:
			-- touching the global line leaves PitBull taint behind, which later makes
			-- Blizzard's UnitIsPVP color rule fail for a secret target identity.
			local secure_call = _G.securecallfunction
			local ok
			if type(secure_call) == "function" then
				ok = pcall(secure_call, GameTooltip.SetUnit, GameTooltip, self.unit)
			else
				ok = pcall(GameTooltip.SetUnit, GameTooltip, self.unit)
			end
			if not ok then
				GameTooltip:Hide()
			end
		end
	end

	PitBull4:RunFrameScriptHooks("OnEnter", self)
end

function UnitFrame__scripts:OnLeave()
	GameTooltip:Hide()

	PitBull4:RunFrameScriptHooks("OnLeave", self)
end

function UnitFrame__scripts:OnAttributeChanged(key, value)
	if key == "unit" or key == "unitsuffix" then
		local new_unit = PitBull4.Utils.GetBestUnitID(SecureButton_GetModifiedUnit(self, "LeftButton")) or nil

		local updated = false
		local old_unit = self.unit

		-- As of 4.0.3 the the unit watch state handler no longer calls OnShow
		-- when the frame is already visible.  So you can't use that to detect
		-- that the unit on a frame has changed.  So we need to check for the
		-- GUID changing here.  However, if the frame is not shown we can't update
		-- the GUID or it hoses the update system.  So only update the GUID if
		-- we're already visible if we're not then the unit watch will update it
		-- normally.
		if self:IsVisible() then
			local guid = new_unit and UnitGUID(new_unit) or nil
			if issecretvalue(guid) or guid ~= self.guid then
				self.unit = new_unit -- Make sure unit is set before updates happen.
				updated = true
				self:UpdateGUID(guid)
			end
		end

		if old_unit == new_unit then
			return
		end

		-- debug assertion to help try and track down ticket 475.
		-- if DEBUG then
		-- 	if not new_unit then
		-- 		expect(self.guid, '==', nil)
		-- 	end
		-- end

		if old_unit then
			PitBull4.unit_id_to_frames[old_unit][self] = nil
			PitBull4.unit_id_to_frames_with_wacky[old_unit][self] = nil
		end

		self.unit = new_unit
		if new_unit then
			PitBull4.unit_id_to_frames[new_unit][self] = true
			PitBull4.unit_id_to_frames_with_wacky[new_unit][self] = true
			if self.is_singleton then
				local is_wacky = PitBull4.Utils.IsWackyUnitGroup(new_unit)
				self.is_wacky = is_wacky
				if is_wacky then
					if not PitBull4.wacky_frames[self] then
						PitBull4.wacky_frames[self] = true
						PitBull4.num_wacky_frames = PitBull4.num_wacky_frames + 1
					end
					PitBull4.non_wacky_frames[self] = nil
				else
					if PitBull4.wacky_frames[self] then
						PitBull4.num_wacky_frames = PitBull4.num_wacky_frames - 1
						PitBull4.wacky_frames[self] = nil
					end
					PitBull4.non_wacky_frames[self] = true
				end
			end
		end

		if not updated then
			self:Update(false)
		end
	elseif key == "state-unitexists" then
		if value then
			UnitFrame__scripts.OnShow(self)
		else
			UnitFrame__scripts.OnHide(self)
		end
	end
end

function UnitFrame__scripts:OnShow()
	if self.unit then
		local guid = UnitGUID(self.unit)
		if self.is_wacky or issecretvalue(guid) or guid ~= self.guid then
			self:UpdateGUID(guid)
		end
	end

	self:SetAlpha(PitBull4:GetFinalFrameOpacity(self))

	if not self.force_show then
		-- Force an update to fix the frame if the unit info wasn't ready (ticket 1251)
		PitBull4:ScheduleTimer(self.UpdateLayout, 0.5, self, true)
		PitBull4:ScheduleTimer(self.UpdateLayout, 2, self, true)
	end
end

function UnitFrame__scripts:OnHide()
	self:GetScript("OnDragStop")(self)

	local force_show = self.force_show
	-- Clear the guid without causing an update unless the frame
	-- is force_shown in which case force an update.
	self:UpdateGUID(nil, force_show and true or false)
	if force_show then
		-- Nothing more to do the frame isn't really being hidden
		return
	end

	-- Iterate the modules and call their OnHide function to tell them
	-- a frame was hidden.  They may very well be changing the frame and
	-- causing layout changes.  However, since the frame is hidden we
	-- do not track this or cause layout updates to happen.  They'll
	-- happen when the frame is shown again anyway.  Skip calling OnHide
	-- when dont_update is set becuase we're only temporarily hiding the
	-- frame for RefreshGroup().
	if not self.dont_update then
		for _, module_type in ipairs(MODULE_UPDATE_ORDER) do
			for _, module in PitBull4:IterateModulesOfType(module_type) do
				module:OnHide(self)
			end
		end
	end
end

-- Ugly hack function to allow running RegisterForClicks in cata.
-- This function is currently missing from the RestrictedFrames environment.
-- Frames created in combat won't have the ability to use the right click
-- menu on them until you leave combat the next time when this function runs.
local function register_for_clicks_helper(frame, clicks)
	frame:RegisterForClicks(clicks)
end
register_for_clicks_helper = PitBull4:OutOfCombatWrapper(register_for_clicks_helper)

-- SecureGroupHeader children can be created while reloading the UI during an
-- existing encounter. Blizzard briefly loads the UI before combat lockdown is
-- re-applied, so perform the normal clamp immediately whenever lockdown is not
-- active. Only children genuinely created after lockdown has resumed are queued
-- for the first safe out-of-combat update.
local lorenzo_pending_member_clamps = setmetatable({}, { __mode = "k" })

local function lorenzo_apply_member_clamp(frame)
	lorenzo_pending_member_clamps[frame] = nil
	if frame and frame.SetClampedToScreen and not InCombatLockdown() then
		frame:SetClampedToScreen(true)
	end
end

local function lorenzo_initialize_member_clamp(frame)
	if not InCombatLockdown() then
		frame:SetClampedToScreen(true)
		return
	end

	if lorenzo_pending_member_clamps[frame] then
		return
	end

	lorenzo_pending_member_clamps[frame] = true
	PitBull4:RunOnLeaveCombat(lorenzo_apply_member_clamp, frame)
end

--- Add the proper functions and scripts to a SecureUnitButton, as well as some various initialization.
-- @param frame a Button which inherits from SecureUnitButton
-- @param isExampleFrame whether the button is an example frame, thus not a real unit frame
-- @usage PitBull4:ConvertIntoUnitFrame(frame)
function PitBull4:ConvertIntoUnitFrame(frame, isExampleFrame)
	if DEBUG then
		expect(frame, 'typeof', 'frame')
		expect(frame, 'frametype', 'Button')
		expect(isExampleFrame, 'typeof', 'nil;boolean')
	end

	self.all_frames[frame] = true
	table.insert(self.all_frames_list, frame)

	self.classification_to_frames[frame.classification][frame] = true

	if frame.is_wacky then
		self.wacky_frames[frame] = true
		PitBull4.num_wacky_frames = PitBull4.num_wacky_frames + 1
	else
		self.non_wacky_frames[frame] = true
	end

	if frame.is_singleton then
		self.singleton_frames[frame] = true
	else
		self.member_frames[frame] = true
	end

	local overlay = PitBull4.Controls.MakeFrame(frame)
	frame.overlay = overlay
	overlay:SetFrameLevel(frame:GetFrameLevel() + 17)

	for k, v in pairs(UnitFrame__scripts) do
		frame:HookScript(k, v)
	end

	for k, v in pairs(frame.is_singleton and SingletonUnitFrame__scripts or MemberUnitFrame__scripts) do
		frame:HookScript(k, v)
	end

	for k, v in pairs(UnitFrame) do
		frame[k] = v
	end

	for k, v in pairs(frame.is_singleton and SingletonUnitFrame or MemberUnitFrame) do
		frame[k] = v
	end

	if not isExampleFrame then
		if frame:CanChangeAttribute() then
			frame:SetAttribute("*type1", "target")
			frame:SetAttribute("*type2", "togglemenu")
			if frame.is_singleton then
				frame:SetMovable(true)
			end
			frame:RegisterForDrag("LeftButton")
			frame:RegisterForClicks("AnyUp")
		elseif not ClickCastHeader then
			-- if we can't set attributes directly and Clique isn't running
			-- then RegisterForClicks upon leaving combat.  Works around
			-- the lack of RegisterForClicks in the RestrictedFrames environment
			-- for cata.
			register_for_clicks_helper(frame, "AnyUp")
		end
	end
	frame:RefreshVehicle()

	if frame.is_singleton or isExampleFrame then
		frame:SetClampedToScreen(true)
	else
		-- During an in-combat UI reload this normally still executes in the short
		-- pre-lockdown loading window. Frames created later in the encounter are
		-- safely completed after combat instead of issuing a protected call.
		lorenzo_initialize_member_clamp(frame)
	end

	if frame.is_singleton then
		if not frame.classification_db.click_through then
			-- Only enable click casting if the frame isn't click_through.
			_G.ClickCastFrames[frame] = true
		end
	else
		if not ClickCastHeader then
			-- member unit frames are handled differently in cata.
			-- See the initialConfigFunction attribute on the GroupHeader.
			_G.ClickCastFrames[frame] = true
		end
	end
end

-- we store layout_db instead of layout, since if a new profile comes up, it'll be a distinct table
local seen_layout_dbs = setmetatable({}, {__mode='k'})
PitBull4.seen_layout_dbs = seen_layout_dbs

--- Reheck the toggleForVehicle attribute for the unit frame
-- @usage frame:RefreshVehicle()
function UnitFrame:RefreshVehicle()
	local classification_db = self.classification_db
	if not classification_db then
		return
	end

	local config_value = classification_db.vehicle_swap
	if self:CanChangeAttribute() then
		self:SetAttribute("pb4-vehicleswap", config_value)
		if self:ProxySetAttribute("toggleForVehicle", config_value) and self.unit then
			PitBull4:UNIT_ENTERED_VEHICLE(nil, self.unit)
		end
	end
end

--- Recheck the layout of the unit frame, make sure it's up to date, and update the frame.
-- @usage frame:RefreshLayout()
function UnitFrame:_RefreshLayout()
	local old_layout = self.layout

	local classification_db = self.classification_db
	if not classification_db then
		return
	end

	local layout = classification_db.layout
	self.layout = layout
	self.layout_db = PitBull4.db.profile.layouts[layout]
	if not seen_layout_dbs[self.layout_db] then
		seen_layout_dbs[self.layout_db] = true
		PitBull4:CallMethodOnModules("OnNewLayout", layout)
	end

	self:SetClickThroughState(classification_db.click_through)
	if self.is_singleton then
		-- RefreshLayout is already out-of-combat. Rebind both new and reused
		-- singleton frames here, including unit changes made in the editor.
		ApplyPlayerPingBehavior(self, classification_db.unit)
	end

	self:RefixSizeAndPosition()
	self:UpdateConfigAnchorLine()

	if old_layout then
		self:Update(true, true)
	end
	-- Layout changes also affect hidden frames whose unit has never existed.
	PitBull4:CallMethodOnModules("OnFrameLayoutChanged", self)
end
UnitFrame.RefreshLayout = PitBull4:OutOfCombatWrapper(UnitFrame._RefreshLayout)

-- Set the frame as able to be clicked through or not.
-- @usage frame:SetClickThroughState(true)
function SingletonUnitFrame:SetClickThroughState(state)
	local mouse_state = not not self:IsMouseEnabled()
	if (not state) ~= mouse_state then
		_G.ClickCastFrames[self] = not mouse_state
		self:EnableMouse(not mouse_state)
	end
	-- Mouse handling and the native ping receiver can get out of sync when a
	-- frame is reused or another click-cast integration changes input state.
	-- Reconcile the attribute even if EnableMouse already has the desired value.
	local receiver = self:GetAttribute("ping-receiver")
	local desired_receiver = not state or nil
	if (_G.issecretvalue and _G.issecretvalue(receiver)) or receiver ~= desired_receiver then
		self:SetAttribute("ping-receiver", desired_receiver)
	end
end
SingletonUnitFrame.SetClickThroughState= PitBull4:OutOfCombatWrapper(SingletonUnitFrame.SetClickThroughState)

--- Reset the size and position of the unit frame.
-- @usage frame:RefixSizeAndPosition()
function SingletonUnitFrame:RefixSizeAndPosition()
	local layout_db = self.layout_db
	local classification_db = self.classification_db

	self:SetWidth(layout_db.size_x * classification_db.size_x)
	self:SetHeight(layout_db.size_y * classification_db.size_y)
	self:SetScale(layout_db.scale * classification_db.scale)
	self:SetFrameStrata(layout_db.strata)
	self:SetFrameLevel(layout_db.level)

	-- Check if the frame we will be anchoring to exists and if not
	-- delay setting the anchor until it does.
	local rel_to = classification_db.relative_to
	local rel_frame, rel_type = PitBull4.Utils.GetRelativeFrame(rel_to)
	if not rel_frame then
		frames_to_anchor[self] = rel_to
		if rel_type == "~" then
			PitBull4.anchor_timer:Show()
		end
		return
	else
		frames_to_anchor[self] = nil
	end

	local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
	self:ClearAllPoints()
	if rel_type == "f" then
		rel_frame:AnchorFrameToFirstUnit(self, classification_db.anchor, classification_db.relative_point, classification_db.position_x / scale, classification_db.position_y / scale)
	else
		self:SetPoint(classification_db.anchor, rel_frame, classification_db.relative_point, classification_db.position_x / scale, classification_db.position_y / scale)
	end
end
SingletonUnitFrame.RefixSizeAndPosition = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.RefixSizeAndPosition)

--- Activate the unit frame.
-- This handles UnitWatch and the custom StateDriver
-- @usage frame:Activate()
function SingletonUnitFrame:Activate()
	RegisterUnitWatch(self, true)
	RegisterAttributeDriver(self, "state-pb4visibility", "[petbattle] hide; default")
end
SingletonUnitFrame.Activate = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.Activate)

--- Deactivate the unit frame.
-- This handles UnitWatch and the custom StateDriver
-- @usage frame:Deactivate()
function SingletonUnitFrame:Deactivate()
	UnregisterUnitWatch(self)
	UnregisterAttributeDriver(self, "state-pb4visibility")
	self:SetAttribute("state-pb4visibility", nil)
	self:SetAttribute("state-unitexists", nil)
	self:Hide()
end
SingletonUnitFrame.Deactivate = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.Deactivate)

function SingletonUnitFrame:ForceShow()
	if not self.force_show then
		self.force_show = true
		self:SetAttribute("config_mode", true)
	end
end
SingletonUnitFrame.ForceShow = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.ForceShow)

function SingletonUnitFrame:UnforceShow()
	if not self.force_show then
		return
	end
	self.force_show = nil
	self:SetAttribute("config_mode", nil)

	-- If we're visible force an udpate so everything is properly in a
	-- non-config mode state
	if self:IsVisible() then
		self:Update()
	end
	PitBull4:CallMethodOnModules("OnFrameLayoutChanged", self)
end
SingletonUnitFrame.UnforceShow = PitBull4:OutOfCombatWrapper(SingletonUnitFrame.UnforceShow)

function UnitFrame:RecheckConfigMode()
	if PitBull4.config_mode and self.classification_db.enabled then
		self:ForceShow()
	else
		self:UnforceShow()
	end
	self:Update(true, true)
	self:UpdateConfigAnchorLine()
end

--- Visually show a line connecting anchored frames
function UnitFrame:UpdateConfigAnchorLine()
	if not self.is_singleton then return end
	local db = self.classification_db
	if not self.force_show or not db then
		if self.anchor_line then
			self.anchor_line:Hide()
		end
		return
	end

	local relative_frame, relative_type = PitBull4.Utils.GetRelativeFrame(db.relative_to)
	if relative_type ~= "0" then -- UIParent
		if not self.anchor_line then
			local line = self:CreateLine(nil, "BACKGROUND", nil, -2)
			line:SetThickness(4)
			line:SetTexture([[Interface/Artifacts/_Artifacts-DependencyBar-Fill]])
			line:SetHorizTile(true)
			line:SetIgnoreParentAlpha(true)
			line:SetIgnoreParentScale(true)
			self.anchor_line = line
		end
		self.anchor_line:SetStartPoint(db.anchor, self)
		self.anchor_line:SetEndPoint(db.relative_point, relative_frame)
		self.anchor_line:Show()
	elseif self.anchor_line then
		self.anchor_line:Hide()
	end
end
UnitFrame.UpdateConfigAnchorLine = PitBull4:OutOfCombatWrapper(UnitFrame.UpdateConfigAnchorLine)

function UnitFrame:Rename(name)
	local old_name = self.classification
	if old_name == name then
		return
	end

	-- Look for groups and units that are anchored to this frame and update their
	-- relative_to reference, there is no need to actually update the anchors
	-- because the frame will already be anchored properly and changing the
	-- name won't break the anchor.
	for group, group_db in pairs(PitBull4.db.profile.groups) do
		local rel_to = group_db.relative_to
		local rel_type = rel_to:sub(1,1)
		if rel_type == "S" then
			local rel_name = rel_to:sub(2)
			if rel_name == old_name then
				group_db.relative_to = rel_type .. name
			end
		end
	end
	for unit, unit_db in pairs(PitBull4.db.profile.units) do
		local rel_to = unit_db.relative_to
		local rel_type = rel_to:sub(1,1)
		if rel_type == "S" then
			local rel_name = rel_to:sub(2)
			if rel_name == old_name then
				unit_db.relative_to = rel_type .. name
			end
		end
	end

	local old_frame_name = "PitBull4_Frames_" .. old_name
	local new_frame_name = "PitBull4_Frames_" .. name

	PitBull4.classification_to_frames[old_name][self] = nil
	PitBull4.classification_to_frames[name][self] = true
	_G[old_frame_name] = nil
	_G[new_frame_name] = self
	self.classification = name
end

local LibSharedMedia = LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT, DEFAULT_FONT_SIZE = ChatFontNormal:GetFont()

--- Get the font of the unit frame.
-- @param font_override nil or the LibSharedMedia name of a font
-- @param size_multiplier how much to multiply the default font size by. Defaults to 1.
-- @return path to the font
-- @return size of the font
-- @usage local font, size = frame:GetFont(db.font, db.size)
-- frame.MyModule:SetFont(font, size)
function UnitFrame:GetFont(font_override, size_multiplier)
	-- AceDB removes defaults from the old profile before every frame has rebound
	-- its layout reference. Keep font rendering safe during that transition.
	local layout_db = self.layout_db or {}
	local classification_db = self.classification_db or {}
	local font
	if LibSharedMedia then
		font = LibSharedMedia:Fetch("font", font_override or layout_db.font or "")
	end
	local layout_size = type(layout_db.font_size) == "number" and layout_db.font_size or 1
	local classification_size = type(classification_db.font_multiplier) == "number" and classification_db.font_multiplier or 1
	local multiplier = type(size_multiplier) == "number" and size_multiplier or 1
	return font or DEFAULT_FONT, (DEFAULT_FONT_SIZE or 14) * layout_size * multiplier * classification_size
end

--- Update all details about the UnitFrame, possibly after a GUID change
-- @param same_guid whether the previous GUID is the same as the current, at which point is less crucial to update
-- @param update_layout whether to update the layout no matter what
-- @usage frame:Update()
-- @usage frame:Update(true)
-- @usage frame:Update(false, true)
function UnitFrame:Update(same_guid, update_layout)
	if self.dont_update then
		return
	end

	local classification_db = self.classification_db
	if not classification_db or not self.layout_db then
		-- Possibly unused frame made for another profile
		return
	end

	-- Update the unit if it changed, only applicable to singleton units,
	-- member units don't have a configured unit but a unit_group and
	-- the unit is set by the SecureGroupHeaderTemplate instead.
	if self.is_singleton then
		self:ProxySetAttribute("unit", classification_db.unit)
	end

	if self.guid == nil and not self.force_show then
		if self.populated then
			self.populated = nil

			for _, module in PitBull4:IterateEnabledModules() do
				module:Clear(self)
			end
		end
		return
	end
	self.populated = true

	local changed = update_layout
	for _, module_type in ipairs(MODULE_UPDATE_ORDER) do
		for _, module in PitBull4:IterateModulesOfType(module_type) do
			changed = module:Update(self, true, same_guid) or changed
		end
	end

	if changed then
		self:UpdateLayout(false)
	end
end

--- Check the guid of the Unit Frame, if it is changed, then update the frame.
-- @param guid result from UnitGUID(unit)
-- @param update when true force an update even if the guid isn't changed, but is non-nil, when false never cause an update and when update is empty or nil let the function decide on its own if an update is needed.
-- @usage frame:UpdateGUID(UnitGUID(frame.unit))
-- @usage frame:UpdateGUID(UnitGUID(frame.unit), true)
function UnitFrame:UpdateGUID(guid, update)
	-- if DEBUG then
	-- 	expect(guid, 'typeof', 'string;nil')
	-- end

	-- if the guids are the same, cut out, but don't if it's a wacky unit that has a guid.
	if update ~= true and not issecretvalue(guid) and not issecretvalue(self.guid) and self.guid == guid and not (guid and self.is_wacky) then
		return
	end
	local old_guid = self.guid
	self.guid = guid
	if update ~= false then
		if issecretvalue(guid) or issecretvalue(old_guid) then
			self:Update(not self.is_wacky)
		else
			self:Update(old_guid == guid)
		end
	end
end

local function iter(frame, id)
	local func, t = PitBull4:IterateEnabledModules()
	local module
	id, module = func(t, id)
	if id == nil then
		return nil
	end
	if not frame[id] then
		return iter(frame, id)
	end
	return id, frame[id], module
end

--- Iterate over all controls on this frame
-- @usage for id, control, module in PitBull4.IterateControls() do
--     doSomethingWith(control)
-- end
-- @return iterator which returns the id, control, and module
function UnitFrame:IterateControls()
	return iter, self, nil
end

local iters = setmetatable({}, {__index=function(iters, module_type)
	local function iter(frame, id)
		local func, t = PitBull4:IterateModulesOfType(module_type)
		local module
		id, module = func(t, id)
		if id == nil then
			return nil
		end
		if not frame[id] then
			return iter(frame, id)
		end
		return id, frame[id], module
	end
	iters[module_type] = iter
	return iter
end})

--- Iterate over all controls on this frame of the given type
-- @param module_type one of "bar", "indicator", "custom"
-- @usage for id, control, module in PitBull4.IterateControlsOfType("bar") do
--     doSomethingWith(control)
-- end
-- @return iterator which returns the id, control, and module
function UnitFrame:IterateControlsOfType(module_type)
	return iters[module_type], self, nil
end
