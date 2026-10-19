local _G = _G
local PitBull4 = _G.PitBull4

-- luacheck: globals oRA3 ClickCastHeader SecureButton_GetModifiedUnit RAID_CLASS_COLORS

local DEBUG = PitBull4.DEBUG
local expect = PitBull4.expect
local deep_copy = PitBull4.Utils.deep_copy
local frames_to_anchor = PitBull4.frames_to_anchor

local MAX_PARTY_MEMBERS =  _G.MAX_PARTY_MEMBERS
local MAX_PARTY_MEMBERS_WITH_PLAYER = MAX_PARTY_MEMBERS + 1
local MAX_RAID_MEMBERS = _G.MAX_RAID_MEMBERS
local MAX_BOSS_FRAMES = _G.MAX_BOSS_FRAMES
local MEMBERS_PER_RAID_GROUP = _G.MEMBERS_PER_RAID_GROUP
local NUM_RAID_GROUPS = _G.NUM_RAID_GROUPS
local NUM_CLASSES = #CLASS_SORT_ORDER
local MINIMUM_EXAMPLE_GROUP = 2

-- Patch 088: return an exact synthetic preview count for Config Mode modes
-- that request one. Plain "party" keeps the historical full-party preview.
local function get_config_preview_limit(config_mode, super_unit_group)
	if type(config_mode) ~= "string" then
		return nil
	end

	if super_unit_group == "party" then
		local num = config_mode:match("^party([1-4])$")
		if num then
			return tonumber(num)
		end
	elseif super_unit_group == "raid" then
		if config_mode == "raid" then
			return MEMBERS_PER_RAID_GROUP
		end
		local num = config_mode:match("^raid(%d+)$")
		if num then
			return tonumber(num)
		end
	end

	return nil
end

local GROUP_ROLES = {
	TANK = TANK,
	HEALER = HEALER,
	DAMAGER = DAMAGER,
	NONE = NONE,
}

-- lock to prevent the SecureGroupHeader_Update for doing unnecessary
-- work when running ForceShow
local in_force_show = false

--- Make a group header.
-- @param group the name for the group. Also acts as a unique identifier.
-- @usage local header = PitBull4:MakeGroupHeader("Monkey")
function PitBull4:MakeGroupHeader(group)
	if DEBUG then
		expect(group, 'typeof', 'string')
	end

	local group_db = PitBull4.db.profile.groups[group]
	local pet_based = group_db.unit_group:match("pet") and true
	local group_based = group_db.unit_group:match("^party") or group_db.unit_group:match("^raid")
	local use_pet_header = pet_based and group_db.use_pet_header
	local header_name

	if not group_based then
		header_name = "PitBull4_EnemyGroups_"..group
	elseif use_pet_header then
		header_name = "PitBull4_PetGroups_" .. group
	else
		header_name = "PitBull4_Groups_" .. group
	end

	local header = _G[header_name]
	if not header then
		local template
		if group_based then
			if use_pet_header then
				template = "SecureGroupPetHeaderTemplate"
			else
				template = "SecureGroupHeaderTemplate"
			end
		else
			template = "SecureFrameTemplate"
		end
		header = CreateFrame("Frame", header_name, UIParent, template)
		header:Hide() -- it will be shown later and attributes being set won't cause lag

		header.name = group
		header.group_db = group_db
		header.group_based = group_based

		self:ConvertIntoGroupHeader(header)
	elseif header.group_db ~= group_db then
		-- If the frame already exists and the group_db doesn't already match the one
		-- we expect it to be then it's a recreated frame from one we've previously
		-- deleted so we need to set the group_db and force an update.
		header.group_db = group_db
		header:RefreshGroup()
	end

	header:UpdateShownState()

	for frame, relative_to in pairs(frames_to_anchor) do
		local relative_frame = PitBull4.Utils.GetRelativeFrame(relative_to)
		if relative_frame == header then
			frame:RefixSizeAndPosition()
		end
	end
end
PitBull4.MakeGroupHeader = PitBull4:OutOfCombatWrapper(PitBull4.MakeGroupHeader)

--- Swap the group from a Normal and Pet Group Header.
-- @param group the name for the group.
-- @usage PitBull4:SwapGroupTemplate("Monkey")
-- Note that the use_pet_header setting for the group_db is expected to already
-- be set to the value you're going to.
function PitBull4:SwapGroupTemplate(group)
	if DEBUG then
		expect(group, 'typeof', 'string')
	end

	local old_header = self.name_to_header[group]
	local group_db = PitBull4.db.profile.groups[group]
	local group_based = group_db.unit_group:match("^party") or group_db.unit_group:match("^raid")

	if not group_db.enabled then
		return
	end

	old_header.group_db = deep_copy(group_db)
	old_header.group_db.enabled = false
	old_header:RefreshGroup()
	old_header:UpdateShownState()
	old_header:RecheckConfigMode()

	local pet_based = not not group_db.unit_group:match("pet") -- this feels dirty
	local use_pet_header = pet_based and group_db.use_pet_header

	local new_name
	if not group_based then
		new_name = "PitBull4_EnemyGroups_"..group
	elseif use_pet_header then
		new_name = "PitBull4_PetGroups_"..group
	else
		new_name = "PitBull4_Groups_"..group
	end
	local new_header = _G[new_name]

	if not new_header then
		-- Doesn't exist so make it.
		self:MakeGroupHeader(group)
		new_header = _G[new_name]
	else
		-- already exists so jump through the hoops to reactive it.
		self.name_to_header[group] = new_header
		new_header.group_db = group_db
		new_header:RefreshGroup()
		new_header:UpdateShownState()
	end

	new_header:RecheckConfigMode()
end
PitBull4.SwapGroupTemplate = PitBull4:OutOfCombatWrapper(PitBull4.SwapGroupTemplate)

local GroupHeader = {}
PitBull4.GroupHeader = GroupHeader
local GroupHeader__scripts = {}
PitBull4.GroupHeader__scripts = GroupHeader__scripts

local MemberUnitFrame = PitBull4.MemberUnitFrame
local MemberUnitFrame__scripts = PitBull4.MemberUnitFrame__scripts

--- Force an update on the group header.
-- This is just a wrapper for SecureGroupHeader_Update.
-- @param force the update to happen now
-- @usage header:Update()
function GroupHeader:Update(force)
	local shown = self:IsShown()
	-- We can't directly call SecureGroupHeader_Update so we just
	-- set an attribute back to iself.  Calling SecureGroupHeader_Update
	-- directly taints the entire template system and is very bad.
	if not shown and force then
		self:Show()
	end
	self:SetAttribute("maxColumns",self:GetAttribute("maxColumns"))
	if not shown and force then
		self:Hide()
	end
end
GroupHeader.Update = PitBull4:OutOfCombatWrapper(GroupHeader.Update)

--- Send :Update to all member frames.
-- @args ... the arguments to send along with :Update
-- @usage header:UpdateMembers(true, true)
function GroupHeader:UpdateMembers(...)
	for _, frame in self:IterateMembers() do
		frame:Update(...)
	end
end

function GroupHeader:ProxySetAttribute(key, value)
	if self:GetAttribute(key) ~= value then
		self:SetAttribute(key, value)
		return not not self:IsVisible()
	end
end

function GroupHeader:UpdateShownState()
	local group_db = self.group_db
	if not group_db or not group_db.enabled then
		PitBull4:RemoveGroupFromStateHeader(self)
	else
		PitBull4:AddGroupToStateHeader(self)
	end
end
GroupHeader.UpdateShownState = PitBull4:OutOfCombatWrapper(GroupHeader.UpdateShownState)

local DIRECTION_TO_POINT = {
	down_right = "TOP",
	down_left = "TOP",
	up_right = "BOTTOM",
	up_left = "BOTTOM",
	right_down = "LEFT",
	right_up = "LEFT",
	left_down = "RIGHT",
	left_up = "RIGHT",
}

local DIRECTION_TO_GROUP_ANCHOR_POINT = {
	down_right = "TOPLEFT",
	down_left = "TOPRIGHT",
	up_right = "BOTTOMLEFT",
	up_left = "BOTTOMRIGHT",
	right_down = "TOPLEFT",
	right_up = "BOTTOMLEFT",
	left_down = "TOPRIGHT",
	left_up = "BOTTOMRIGHT",
}

local DIRECTION_TO_COLUMN_ANCHOR_POINT = {
	down_right = "LEFT",
	down_left = "RIGHT",
	up_right = "LEFT",
	up_left = "RIGHT",
	right_down = "TOP",
	right_up = "BOTTOM",
	left_down = "TOP",
	left_up = "BOTTOM",
}

local DIRECTION_TO_HORIZONTAL_SPACING_MULTIPLIER = {
	down_right = 1,
	down_left = -1,
	up_right = 1,
	up_left = -1,
	right_down = 1,
	right_up = 1,
	left_down = -1,
	left_up = -1,
}

local DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER = {
	down_right = -1,
	down_left = -1,
	up_right = 1,
	up_left = 1,
	right_down = -1,
	right_up = 1,
	left_down = -1,
	left_up = 1,
}

local POINT_TO_HORIZONTAL_MULTIPLIER = {
	TOP = 0,
	BOTTOM = 0,
	LEFT = 1,
	RIGHT = -1,
	TOPLEFT = 1,
	TOPRIGHT = -1,
	BOTTOMLEFT = 1,
	BOTTOMRIGHT = -1,
	CENTER = 0,
}

local POINT_TO_VERTICAL_MULTIPLIER = {
	TOP = -1,
	BOTTOM = 1,
	LEFT = 0,
	RIGHT = 0,
	TOPLEFT = -1,
	TOPRIGHT = -1,
	BOTTOMLEFT = 1,
	BOTTOMRIGHT = 1,
	CENTER = 0,
}

local GROUPING_ORDER = {}
do
	local t = {}
	for i = 1, NUM_RAID_GROUPS do
		t[i] = i..""
	end
	GROUPING_ORDER.GROUP = table.concat(t, ",")
end
GROUPING_ORDER.CLASS = function()
	return table.concat(PitBull4.ClassOrder, ",")
end
GROUPING_ORDER.ASSIGNEDROLE = function()
	return table.concat(PitBull4.RoleOrder, ",")
end

local function position_label(self, label)
	label:ClearAllPoints()
	local group_db = self.group_db
	if group_db.direction:match("down") then
		label:SetPoint("BOTTOM", self, "TOP", 0, group_db.vertical_spacing)
	else
		label:SetPoint("TOP", self, "BOTTOM", 0, -group_db.vertical_spacing)
	end
end

-- Offsets used to be stored between the center of the screen and the center
-- of the group frame, while the frames anchor point varied based on the
-- growth direction of the frame.  So the offset from the actual anchor point
-- was calculated as needed.  Now we store the the actual offsets and only
-- recalculate if the anchor point is being determined by the growth direction.
-- This function converts the existing offsets to the new format.
function PitBull4:MigrateGroupAnchorToNewFormat(group_db, layout_db)
	local scale = layout_db.scale * group_db.scale / UIParent:GetEffectiveScale()
	local direction = group_db.direction
	local unit_width = layout_db.size_x * group_db.size_x
	local unit_height = layout_db.size_y * group_db.size_y
	local x_diff = unit_width / 2 * -DIRECTION_TO_HORIZONTAL_SPACING_MULTIPLIER[direction]
	local y_diff = unit_height / 2 * -DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER[direction]

	group_db.position_x = (group_db.position_x / scale + x_diff) * scale
	group_db.position_y = (group_db.position_y / scale + y_diff) * scale
end

-- Handles adjusting the offsets for when the growth direction changes.
function PitBull4:AdjustGroupAnchorForDirectionChange(group_db, new_direction)
	-- If the anchor is set explicitly then changing the direction does not require
	-- a recalculation of the anchor offsets.
	if group_db.anchor ~= "" then return end
	local old_direction = group_db.direction
	local layout_db = self.db.profile.layouts[group_db.layout]
	local scale = layout_db.scale * group_db.scale
	local unit_width = layout_db.size_x * group_db.size_x
	local unit_height = layout_db.size_y * group_db.size_y

	-- Calculate the difference from the current anchor point to the center
	local x_diff = unit_width / 2 * DIRECTION_TO_HORIZONTAL_SPACING_MULTIPLIER[old_direction]
	local y_diff = unit_height / 2 * DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER[old_direction]

	-- Calculate the difference from the center to the new anchor point
	x_diff = x_diff + unit_width / 2 * -DIRECTION_TO_HORIZONTAL_SPACING_MULTIPLIER[new_direction]
	y_diff = y_diff + unit_height / 2 * -DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER[new_direction]

	-- Adjust the offset to the new anchor point
	group_db.position_x = (group_db.position_x / scale + x_diff) * scale
	group_db.position_y = (group_db.position_y / scale + y_diff) * scale
end

-- Anchors a frame to the first frame within the group.  The first frame probably will
-- not exist when we need to do the anchoring.  So we need to calculate where the frame
-- would exist and adjust our offsets accordingly so we can simulate anchoring to the frame
-- even though we're really anchoring to the group header itself.
function GroupHeader:AnchorFrameToFirstUnit(frame, anchor, rel_point, x, y)
	local growth_point = self:GetAttribute("point")
	if rel_point:find(growth_point, 1, false) then
		-- The relative point is on the edge we're growing away from so we
		-- do not need to calculate the offset.
		frame:SetPoint(anchor, self, rel_point, x,  y)
	else
		-- The relative point is not on the edge we're growing away from
		-- so we must calculate the offset to the other edge of the unit frame
		local group_db = self.group_db
		local layout = group_db.layout
		local layout_db = PitBull4.db.profile.layouts[layout]
		local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local unit_width = layout_db.size_x * group_db.size_x / scale
		local unit_height = layout_db.size_y * group_db.size_y / scale
		local direction = group_db.direction

		if growth_point == "TOP" or growth_point == "BOTTOM" then
			if rel_point:find("LEFT", 1, false) then
				x = x - (unit_width / 2)
				if rel_point == "LEFT" then
					y = y + (unit_height/ 2 * DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER[direction])
				end
			elseif rel_point:find("RIGHT", 1, false) then
				x = x + (unit_width / 2)
				if rel_point == "RIGHT" then
					y = y + (unit_height / 2 * DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER[direction])
				end
			end
		elseif growth_point == "LEFT" or growth_point == "RIGHT" then
			if rel_point:find("TOP", 1, false) then
				y = y + (unit_height / 2)
				if rel_point == "TOP" then
					x = x + (unit_width / 2 * DIRECTION_TO_HORIZONTAL_SPACING_MULTIPLIER[direction])
				end
			elseif  rel_point:find("BOTTOM", 1, false) then
				y = y - (unit_height / 2)
				if rel_point == "BOTTOM" then
					x = x + (unit_width / 2 * DIRECTION_TO_HORIZONTAL_SPACING_MULTIPLIER[direction])
				end
			end
		end

		if growth_point == "TOP" and rel_point:find("BOTTOM", 1, false) then
			y = y - unit_height
		elseif growth_point == "BOTTOM" and rel_point:find("TOP", 1, false) then
			y = y + unit_height
		elseif growth_point == "LEFT" and rel_point:find("RIGHT", 1, false) then
			x = x + unit_width
		elseif growth_point == "RIGHT" and rel_point:find("LEFT", 1, false) then
			x = x - unit_width
		end

		if rel_point == "CENTER" then
			if growth_point == "BOTTOM" or growth_point == "TOP" then
				y = y + (unit_height / 2 * DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER[direction])
			else  -- growth_point == "LEFT" or growth_point == "RIGHT"
				x = x + (unit_width / 2 * DIRECTION_TO_HORIZONTAL_SPACING_MULTIPLIER[direction])
			end
		end

		frame:SetPoint(anchor, self, growth_point, x, y)
	end
end

--- Reset the size and position of the group header.  More accurately,
-- the scale and the position since size is set dynamically.
-- @usage header:RefixSizeAndPosition()
function GroupHeader:RefixSizeAndPosition()
	local group_db = self.group_db
	local layout = group_db.layout
	local layout_db = PitBull4.db.profile.layouts[layout]
	local updated = false

	self:SetScale(layout_db.scale * group_db.scale)
	self:SetFrameStrata(layout_db.strata)
	self:SetFrameLevel(layout_db.level - 1) -- 1 less than what the unit frame will be at

	-- Calculate the  width and height of the group when the number of units
	-- returned from GetMaxUnits() exist.  Use this to cause config mode to
	-- behave this way.
	local unit_width = layout_db.size_x * group_db.size_x
	local unit_height = layout_db.size_y * group_db.size_y
	local max = self:GetMaxUnits()
	local super_unit_group = self.super_unit_group
	local config_mode = PitBull4.config_mode

	updated = self:ProxySetAttribute('unitWidth',unit_width) or updated
	updated = self:ProxySetAttribute('unitHeight',unit_height) or updated
	updated = self:ProxySetAttribute('clickThrough',group_db.click_through) or updated

	-- Patch 089: keep the header's positioning envelope at the classification's
	-- full configured capacity, even when Config Mode shows only a smaller
	-- synthetic roster. The visible preview count is handled separately in
	-- ApplyConfigModeState(). Shrinking this envelope to 1/2/10 visible units
	-- makes centered-edge anchors (LEFT/RIGHT/TOP/BOTTOM) move as the preview
	-- count crosses a row/column boundary.

	local units_per_column = group_db.units_per_column
	local num_columns
	if units_per_column and max > units_per_column then
		num_columns = math.ceil(max / units_per_column)
	else
		units_per_column = max
		num_columns = 1
	end
	local point = self:GetAttribute("point") or "TOP"
	local x_offset_mult = POINT_TO_HORIZONTAL_MULTIPLIER[point]
	local y_offset_mult = POINT_TO_VERTICAL_MULTIPLIER[point]
	local x_mult, y_mult = math.abs(x_offset_mult), math.abs(y_offset_mult)
	local x_offset = self:GetAttribute("xOffset") or 0
	local y_offset = self:GetAttribute("yOffset") or 0
	local column_spacing = self:GetAttribute("columnSpacing") or 0
	local col_point = self:GetAttribute("columnAnchorPoint")
	local col_x_mult = POINT_TO_HORIZONTAL_MULTIPLIER[col_point]
	local col_y_mult = POINT_TO_VERTICAL_MULTIPLIER[col_point]
	local width = x_mult * (units_per_column - 1) * unit_width + ((units_per_column - 1) * (x_offset * x_offset_mult)) + unit_width
	local height = y_mult * (units_per_column - 1) * unit_height + ((units_per_column - 1) * (y_offset * y_offset_mult)) + unit_height
	if num_columns > 1 then
		width = width + ((num_columns - 1) * math.abs(col_x_mult) * (width + column_spacing))
		height = height + ((num_columns - 1) * math.abs(col_y_mult) * (height + column_spacing))
	end

	-- Set minimum width and height.  If we don't do this then
	-- SecureTemplates will calculate the size dynamically and these
	-- dimensions will end up being set to 0.1 if there are no units to
	-- display.  This causes the positioning of the group header to move
	-- and results in group frames that jump when someone joins the group
	-- from where they were in config mode.  It also will make the frames
	-- that are anchored to the entire group to behave differently in config
	-- mode from actual use.
	updated = self:ProxySetAttribute("minWidth",math.max(width,0.1)) or updated
	updated = self:ProxySetAttribute("minHeight",math.max(height,0.1)) or updated

	if not updated then
		-- Update absolutely must be called at least once to ensure the GroupHeader
		-- frame size is recalculated.
		self:Update(true)
	end

	if not self.group_based then
		self:ConfigureChildren()
	end

	if not self:RestoreConfiguredGroupAnchor() then return end
	self:StabilizeGroupGridGeometry()
end

-- Share the saved-anchor restoration with deferred roster reconciliation.
-- This path does not refresh unit assignments or call a native header update.
function GroupHeader:RestoreConfiguredGroupAnchor()
	if InCombatLockdown() then return false end
	local group_db = self.group_db
	if not group_db then return false end
	-- Check if the frame we will be anchoring to exists and if not
	-- delaying setting the anchor until it does.
	local rel_to = group_db.relative_to
	local rel_frame, rel_type = PitBull4.Utils.GetRelativeFrame(rel_to)
	if not rel_frame then
		frames_to_anchor[self] = rel_to
		if rel_type == "~" then
			PitBull4.anchor_timer:Show()
		end
		return false
	else
		frames_to_anchor[self] = nil
	end

	local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local anchor = group_db.anchor
	if anchor == "" then
		anchor = DIRECTION_TO_GROUP_ANCHOR_POINT[group_db.direction]
	end

	self:ClearAllPoints()
	if rel_type == "f" then
		rel_frame:AnchorFrameToFirstUnit(self, anchor, group_db.relative_point, group_db.position_x / scale, group_db.position_y / scale)
	else
		self:SetPoint(anchor, rel_frame, group_db.relative_point, group_db.position_x / scale, group_db.position_y / scale)
	end

	return true
end

--- Recheck the group-based settings of the group header, including sorting, position, what units are shown.
-- @param dont_refresh_children don't call :RefreshLayout on the child frames
-- @usage header:RefreshGroup()
-- Patch 050: build an ordered secure name whitelist for normal raid headers
-- that excludes players assigned as Main Tanks. SecureGroupHeaderTemplate has
-- inclusion filters but no native negation operator, so exclusion is expressed
-- as a nameList prepared out of combat. This keeps protected unit assignment in
-- Blizzard's secure header while avoiding addon-side mutation in combat.
local function build_raid_name_list_without_main_tanks(group_db)
	local num_members = _G.GetNumGroupMembers and _G.GetNumGroupMembers() or 0
	if num_members <= 0 then
		return nil
	end

	local ora_main_tanks = nil
	if oRA3 and oRA3.GetSortedTanks then
		local tanks = oRA3:GetSortedTanks()
		if tanks and #tanks > 0 then
			ora_main_tanks = {}
			for _, tank_name in ipairs(tanks) do
				if not issecretvalue(tank_name) then
					ora_main_tanks[tank_name] = true
				end
			end
		end
	end

	local filter_tokens = nil
	if group_db.group_filter then
		filter_tokens = {}
		for token in group_db.group_filter:gmatch("[^,]+") do
			filter_tokens[token] = true
			local number = tonumber(token)
			if number then
				filter_tokens[number] = true
			end
		end
	end

	local records = {}
	for index = 1, math.min(num_members, MAX_RAID_MEMBERS) do
		local name, _, subgroup, _, _, class_name, _, _, _, role, _, assigned_role = _G.GetRaidRosterInfo(index)
		-- Roster identity fields may be restricted independently. Keep secrets out
		-- of name matching, filter keys, grouping ranks and the sort comparator.
		if issecretvalue(name) then name = nil end
		if issecretvalue(subgroup) then subgroup = nil end
		if issecretvalue(class_name) then class_name = nil end
		local public_role, public_assigned_role
		if not issecretvalue(role) then public_role = role end
		if not issecretvalue(assigned_role) then public_assigned_role = assigned_role end
		if name then
			local is_main_tank = public_role == "MAINTANK"
			if not is_main_tank and ora_main_tanks then
				is_main_tank = ora_main_tanks[name] or false
				if not is_main_tank then
					local short_name = name:match("^[^-]+")
					is_main_tank = short_name and ora_main_tanks[short_name] or false
				end
			end

			if not is_main_tank then
				local passes_filter = true
				if filter_tokens then
					passes_filter = filter_tokens[subgroup] or filter_tokens[class_name] or (public_role and filter_tokens[public_role]) or (public_assigned_role and filter_tokens[public_assigned_role]) or false
				end
				if passes_filter then
					records[#records + 1] = {
						name = name,
						index = index,
						subgroup = subgroup,
						class_name = class_name,
						role = public_role,
						assigned_role = public_assigned_role,
					}
				end
			end
		end
	end

	local group_by = group_db.group_by
	local sort_method = group_db.sort_method or "INDEX"
	local sort_direction = group_db.sort_direction or "ASC"
	local grouping_order = GROUPING_ORDER[group_by]
	if type(grouping_order) == "function" then
		grouping_order = grouping_order()
	end
	local group_rank = {}
	if grouping_order then
		local rank = 1
		for token in grouping_order:gmatch("[^,]+") do
			group_rank[token] = rank
			local number = tonumber(token)
			if number then group_rank[number] = rank end
			rank = rank + 1
		end
	end

	local function grouping_value(record)
		if group_by == "GROUP" then return record.subgroup end
		if group_by == "CLASS" then return record.class_name end
		if group_by == "ROLE" then return record.role end
		if group_by == "ASSIGNEDROLE" then return record.assigned_role end
	end

	table.sort(records, function(a, b)
		if group_by then
			local ar = group_rank[grouping_value(a)] or 999
			local br = group_rank[grouping_value(b)] or 999
			if ar ~= br then
				if sort_direction == "DESC" then return ar > br end
				return ar < br
			end
		end
		if sort_method == "NAME" then
			if a.name ~= b.name then
				if sort_direction == "DESC" then return a.name > b.name end
				return a.name < b.name
			end
		end
		if sort_direction == "DESC" then return a.index > b.index end
		return a.index < b.index
	end)

	local names = {}
	for i, record in ipairs(records) do
		names[i] = record.name
	end
	return table.concat(names, ",")
end


function GroupHeader:RefreshGroup(dont_refresh_children)
	local group_db = self.group_db

	local layout = group_db.layout
	self.layout = layout

	local layout_db = PitBull4.db.profile.layouts[layout]
	self.layout_db = layout_db

	self.dont_update = true
	for _, frame in self:IterateMembers() do
		frame.dont_update = true
	end

	local is_shown = self:IsShown()
	self:Hide()

	local force_show = self.force_show
	self:UnforceShow()

	-- Wipe all the points on the member frames before doing
	-- the work below.  SecureGroupHeader's code does not
	-- do this for us as it should so if you change directions
	-- the frames can break since they'll end up with conflicting
	-- anchors.
	for _, member in self:IterateMembers() do
		member:ClearAllPoints()
	end

	local enabled = group_db.enabled
	local unit_group = group_db.unit_group
	local party_based = unit_group:sub(1, 5) == "party"
	local group_based = party_based or unit_group:sub(1, 4) == "raid"
	local include_player = party_based and group_db.include_player
	local show_when = group_db.show_when
	local show_solo = show_when.solo
	if group_based then
		show_solo = include_player and show_solo
	end
	local group_filter = group_based and group_db.group_filter or nil
	local sort_direction = group_db.sort_direction
	local sort_method = group_db.sort_method
	local group_by = group_db.group_by
	local exclude_main_tanks = group_based and not party_based and group_db.exclude_main_tanks and group_filter ~= "MAINTANK"
	local name_list = nil
	-- If using oRA3, override the MAINTANK groupFilter and use oRA3's tanks (even if empty)
	if group_filter == "MAINTANK" and oRA3 then
		local main_tanks = oRA3:GetSortedTanks()
		name_list = table.concat(main_tanks, ",")
	elseif exclude_main_tanks then
		name_list = build_raid_name_list_without_main_tanks(group_db)
	end

	local changed_units = self.unit_group ~= unit_group or self.include_player ~= include_player or self.show_solo ~= show_solo or self.group_filter ~= group_filter or self.sort_direction ~= sort_direction or self.sort_method ~= sort_method or self.group_by ~= group_by or self.name_list ~= name_list or self.exclude_main_tanks ~= exclude_main_tanks or self.group_based ~= group_based

	if changed_units then
		local old_unit_group = self.unit_group
		local old_super_unit_group = self.super_unit_group
		self.unit_group = unit_group
		self.group_based = group_based
		self.include_player = include_player
		self.show_solo = show_solo
		self.group_filter = group_filter
		self.sort_direction = sort_direction
		self.sort_method = sort_method
		self.group_by = group_db.group_by
		self.name_list = name_list
		self.exclude_main_tanks = exclude_main_tanks
		if DEBUG then
			expect(unit_group, 'typeof', 'string')
		end

		if party_based then
			self.super_unit_group = "party"
			self.unitsuffix = unit_group:sub(6)
			self:SetAttribute("showRaid", nil)
			self:SetAttribute("showParty", true)
			self:SetAttribute("showPlayer", include_player and true or nil)
			self:SetAttribute("showSolo", show_solo and true or nil)
			self:SetAttribute("groupFilter", nil)
			if group_filter then
				local first = (","):split(group_filter)
				if GROUP_ROLES[first] then
					self:SetAttribute("groupFilter", group_filter)
				end
			end
		elseif not group_based then
			self:UnregisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
			self:UnregisterEvent("UPDATE_BATTLEFIELD_STATUS")
			if unit_group:sub(1, 4) == "boss" then
				self.super_unit_group = "boss"
				self.unitsuffix = unit_group:sub(5)
				self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
			elseif unit_group:sub(1, 5) == "arena" then
				self.super_unit_group = "arena"
				self.unitsuffix = unit_group:sub(6)
				self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
			end
		else
			self.super_unit_group = "raid"
			self.unitsuffix = unit_group:sub(5)
			self:SetAttribute("showParty", nil)
			self:SetAttribute("showPlayer", nil)
			self:SetAttribute("showSolo", nil)
			self:SetAttribute("showRaid", true)
			if name_list then
				self:SetAttribute("groupFilter", nil)
				self:SetAttribute("nameList", name_list)
			else
				self:SetAttribute("groupFilter", group_filter)
				self:SetAttribute("nameList", nil)
			end
		end
		if self.unitsuffix == "" then
			self.unitsuffix = nil
		end
		self:SetAttribute("unitsuffix", self.unitsuffix)

		local is_wacky = PitBull4.Utils.IsWackyUnitGroup(unit_group)
		self.is_wacky = is_wacky

		if old_unit_group then
			PitBull4.unit_group_to_headers[old_unit_group][self] = nil
			PitBull4.super_unit_group_to_headers[old_super_unit_group][self] = nil
		end

		for _, frame in self:IterateMembers() do
			frame:SetAttribute("unitsuffix", self.unitsuffix)
			frame.is_wacky = is_wacky
		end
		PitBull4.unit_group_to_headers[unit_group][self] = true
		PitBull4.super_unit_group_to_headers[self.super_unit_group][self] = true
	end

	local direction = group_db.direction
	local point = DIRECTION_TO_POINT[direction]

	self:SetAttribute("point", point)
	if point == "LEFT" or point == "RIGHT" then
		self:SetAttribute("xOffset", group_db.horizontal_spacing * DIRECTION_TO_HORIZONTAL_SPACING_MULTIPLIER[direction])
		self:SetAttribute("yOffset", 0)
		self:SetAttribute("columnSpacing", group_db.vertical_spacing)
	else
		self:SetAttribute("xOffset", 0)
		self:SetAttribute("yOffset", group_db.vertical_spacing * DIRECTION_TO_VERTICAL_SPACING_MULTIPLIER[direction])
		self:SetAttribute("columnSpacing", group_db.horizontal_spacing)
	end
	if self.label then
		position_label(self, self.label)
	end
	if exclude_main_tanks then
		self:SetAttribute("sortMethod", "NAMELIST")
		self:SetAttribute("sortDir", "ASC")
		self:SetAttribute("groupBy", nil)
	else
		self:SetAttribute("sortMethod", sort_method)
		self:SetAttribute("sortDir", sort_direction)
		self:SetAttribute("groupBy", group_by)
	end
	-- self:SetAttribute("template", ClickCastHeader and "ClickCastUnitTemplate,PitBull4_UnitTemplate" or "PitBull4_UnitTemplate")
	self:SetAttribute("template", "PitBull4_UnitTemplate")
	self:SetAttribute("templateType", "Button")
	local order = GROUPING_ORDER[group_db.group_by]
	if type(order) == "function" then
		order = order()
	end
	self:SetAttribute("groupingOrder", order)
	self:SetAttribute("unitsPerColumn", group_db.units_per_column)
	self:SetAttribute("maxColumns", self:GetMaxUnits())
	self:SetAttribute("startingIndex", 1)
	self:SetAttribute("columnAnchorPoint", DIRECTION_TO_COLUMN_ANCHOR_POINT[direction])
	self:SetAttribute("useOwnerUnit", 1)

	-- Set the attributes for the StateHeader to know when to show and hide this
	-- group
	for k,v in pairs(show_when) do
		local value = enabled and v
		if group_based then
			if k == "solo" then
				value = enabled and show_solo and party_based
			elseif k == "party" then
				value = value and party_based
			end
		end
		self:SetAttribute(k, value)
	end

	self:RefixSizeAndPosition()

	if is_shown then
		self:Show()
	end

	if force_show then
		self:ForceShow()
	end

	for _, frame in self:IterateMembers() do
		frame.dont_update = nil
	end
	self.dont_update = nil

	if changed_units and not dont_refresh_children then
		for _, frame in self:IterateMembers() do
			frame:RefreshLayout()
		end
	end
end
GroupHeader.RefreshGroup = PitBull4:OutOfCombatWrapper(GroupHeader.RefreshGroup)

--- Recheck the layout of the group header, refreshing the layout of all members.
-- @param dont_refresh_children don't call :RefreshLayout on the child frames
-- @usage header:RefreshLayout()
function GroupHeader:RefreshLayout(dont_refresh_children)
	self:RefixSizeAndPosition()
	self:UpdateConfigAnchorLine()

	if not dont_refresh_children then
		for _, frame in self:IterateMembers() do
			frame:RefreshLayout()
		end
	end
end
GroupHeader.RefreshLayout = PitBull4:OutOfCombatWrapper(GroupHeader.RefreshLayout)

--- Initialize a member frame. This should be called once per member frame immediately following the frame's creation.
-- @usage header:InitializeConfigFunction()
function GroupHeader:InitialConfigFunction()
	-- Since Cataclysm, the frame is not passed into us but the new
	-- GroupHeader does set the 1..n array slots to the frames.
	-- Since this function is only called on the creation of a new
	-- frame the newest frame will always be the last array slot
	local frame = self[#self]

	frame.header = self
	frame.is_singleton = false
	frame.classification = self.name
	frame.classification_db = self.group_db
	frame.is_wacky = self.is_wacky

	local layout = self.group_db.layout
	frame.layout = layout

	PitBull4:ConvertIntoUnitFrame(frame)

	if frame:CanChangeAttribute() then
		if self.unitsuffix then
			frame:ProxySetAttribute("unitsuffix", self.unitsuffix)
		end

		local layout_db = PitBull4.db.profile.layouts[layout]
		frame.layout_db = layout_db

		frame:ProxySetAttribute("initial-width", layout_db.size_x * self.group_db.size_x)
		frame:ProxySetAttribute("initial-height", layout_db.size_y * self.group_db.size_y)
		frame:ProxySetAttribute("initial-unitWatch", true)
	end

	frame:_RefreshLayout() -- Normally protected by an OutOfCombatWrapper
end

local function should_show_header(config_mode, header)
	if not config_mode then
		return false
	end

	if config_mode == "solo" then
		return header.show_solo
	end

	if header.group_based and (config_mode == "party" or config_mode:match("^party[1-4]$")) and header.super_unit_group ~= "party" then
		return false
	end

	return true
end

function GroupHeader:RecheckConfigMode()
	if self.group_db.enabled and should_show_header(PitBull4.config_mode, self) then
		self:ForceShow()
	else
		self:UnforceShow()
	end
	self:UpdateConfigAnchorLine()
end

--- Force unit frames to be created on the group header, even if those units don't exist.
-- @usage header:ForceUnitFrameCreation()
function GroupHeader:ForceUnitFrameCreation()
	local num = self:GetMaxUnits()
	if self[num] then
		return
	end
	local rehide = false
	local maxColumns = self:GetAttribute("maxColumns")
	local unitsPerColumn = self:GetAttribute("unitsPerColumn")
	local startingIndex = self:GetAttribute("startingIndex")

	if unitsPerColumn and num > unitsPerColumn then
		self:ProxySetAttribute("maxColumns", num / unitsPerColumn)
	else
		self:ProxySetAttribute("maxColumns", 1)
		self:ProxySetAttribute("unitsPerColumn", num)
	end
	if not self:IsShown() then
		self:Show()
		rehide = true
	end
	self:SetAttribute("startingIndex", -num + 1) -- Not proxied to ensure an Update happens

	self:ProxySetAttribute("maxColumns", maxColumns)
	self:ProxySetAttribute("unitsPerColumn", unitsPerColumn)
	self:SetAttribute("startingIndex", startingIndex) -- Not proxied to ensure an Update happens

	if rehide then
		self:Hide()
	end

	-- this is done because the previous hack can mess up some unit references
	for _, frame in self:IterateMembers() do
		local unit = SecureButton_GetModifiedUnit(frame, "LeftButton")
		if unit ~= frame.unit then
			frame.unit = unit
			frame:Update()
		end
	end
end
GroupHeader.ForceUnitFrameCreation = PitBull4:OutOfCombatWrapper(GroupHeader.ForceUnitFrameCreation)

-- Patch 086: keep the live SecureGroupHeader geometry identical to the
-- maximum configured grid, not merely the currently populated roster.
--
-- Blizzard's SecureGroupHeader only honors minWidth/minHeight when no units are
-- displayed. As soon as at least one unit exists, it recalculates the header
-- size from the currently displayed rows/columns. With a centered edge anchor
-- such as LEFT/RIGHT/TOP/BOTTOM this moves the first visible row/column when
-- the roster crosses the unitsPerColumn boundary. Reapply both the full-grid
-- header dimensions and the first child's full-grid corner anchors after each
-- secure header update.
function GroupHeader:StabilizeGroupGridGeometry()
	if not self.group_based or not self.group_db or not self.group_db.enabled then
		return
	end

	-- Patch 087: Config Mode has its own synthetic roster/layout path in
	-- ApplyConfigModeState(). Never force live maximum-grid geometry onto those
	-- preview frames; doing so mixes two incompatible frame counts (for example
	-- a raid10 preview with the live raid maximum) and displaces the preview.
	if self.force_show or PitBull4.config_mode then
		return
	end

	local group_db = self.group_db
	local layout_db = PitBull4.db.profile.layouts[group_db.layout]
	if not layout_db then
		return
	end

	local max_units = self:GetMaxUnits()
	local units_per_column = group_db.units_per_column
	local num_columns
	if units_per_column and max_units > units_per_column then
		num_columns = math.ceil(max_units / units_per_column)
	else
		units_per_column = max_units
		num_columns = 1
	end
	if not units_per_column or units_per_column < 1 then
		return
	end

	local unit_width = layout_db.size_x * group_db.size_x
	local unit_height = layout_db.size_y * group_db.size_y
	local point = self:GetAttribute("point") or "TOP"
	local x_offset_mult = POINT_TO_HORIZONTAL_MULTIPLIER[point]
	local y_offset_mult = POINT_TO_VERTICAL_MULTIPLIER[point]
	if x_offset_mult == nil or y_offset_mult == nil then
		return
	end
	local x_mult, y_mult = math.abs(x_offset_mult), math.abs(y_offset_mult)
	local x_offset = self:GetAttribute("xOffset") or 0
	local y_offset = self:GetAttribute("yOffset") or 0
	local column_spacing = self:GetAttribute("columnSpacing") or 0
	local column_anchor_point = self:GetAttribute("columnAnchorPoint")
	local col_x_mult = POINT_TO_HORIZONTAL_MULTIPLIER[column_anchor_point] or 0
	local col_y_mult = POINT_TO_VERTICAL_MULTIPLIER[column_anchor_point] or 0

	local width = x_mult * (units_per_column - 1) * unit_width + ((units_per_column - 1) * (x_offset * x_offset_mult)) + unit_width
	local height = y_mult * (units_per_column - 1) * unit_height + ((units_per_column - 1) * (y_offset * y_offset_mult)) + unit_height
	if num_columns > 1 then
		width = width + ((num_columns - 1) * math.abs(col_x_mult) * (width + column_spacing))
		height = height + ((num_columns - 1) * math.abs(col_y_mult) * (height + column_spacing))
	end

	-- SecureGroupHeader_Update has already completed when this runs, so restore
	-- the maximum-grid dimensions that PitBull calculated for the classification.
	self:SetWidth(math.max(width, 0.1))
	self:SetHeight(math.max(height, 0.1))

	-- Recreate the exact anchors Blizzard uses when the maximum grid spans more
	-- than one row/column. child1 is the authoritative secure-header child ref;
	-- self[1] is retained as a compatibility fallback.
	local first = self:GetAttribute("child1") or self[1]
	if not first then
		return
	end
	first:ClearAllPoints()
	first:SetPoint(point, self, point, 0, 0)
	if num_columns > 1 and column_anchor_point then
		first:SetPoint(column_anchor_point, self, column_anchor_point, 0, 0)
	end
end
GroupHeader.StabilizeGroupGridGeometry = PitBull4:OutOfCombatWrapper(GroupHeader.StabilizeGroupGridGeometry)

local function hook_SecureGroupHeader_Update()
	hook_SecureGroupHeader_Update = nil
	local function hook(self)
		if not PitBull4.all_headers[self] then
			return
		end

		-- Config Mode owns its synthetic frame geometry completely. Do not apply
		-- the live-grid stabilization to force-shown preview headers.
		if self.force_show then
			PitBull4:ScheduleTimer(self.ApplyConfigModeState, 0, self)
			return
		end

		-- Live group header only: restore the full configured grid after Blizzard
		-- finishes its roster-dependent layout.
		if self.group_based then
			self:StabilizeGroupGridGeometry()
		end
	end
	hooksecurefunc("SecureGroupHeader_Update", hook)
	hooksecurefunc("SecureGroupPetHeader_Update", hook)
end

-- Install the observation after FrameXML has completed loading. The immediate
-- path covers normal startup; PLAYER_LOGIN is a fallback for unusual load order.
local function install_secure_group_header_hook()
	if hook_SecureGroupHeader_Update and _G.SecureGroupHeader_Update and _G.SecureGroupPetHeader_Update then
		hook_SecureGroupHeader_Update()
	end
end
if C_Timer and C_Timer.After then
	C_Timer.After(0, install_secure_group_header_hook)
else
	install_secure_group_header_hook()
end
local stable_grid_hook_frame = CreateFrame("Frame")
stable_grid_hook_frame:RegisterEvent("PLAYER_LOGIN")
stable_grid_hook_frame:RegisterEvent("GROUP_ROSTER_UPDATE")
local roster_grid_pending, roster_grid_timer_pending = false, false
local roster_grid_passes, roster_grid_headers = 0, 0
local function queue_roster_grid_reconcile()
	roster_grid_pending = true
	if InCombatLockdown() then
		stable_grid_hook_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if roster_grid_timer_pending then return end
	roster_grid_timer_pending = true
	C_Timer.After(0, function()
		roster_grid_timer_pending = false
		if InCombatLockdown() then
			stable_grid_hook_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
			return
		end
		roster_grid_pending = false
		stable_grid_hook_frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if PitBull4.config_mode then return end
		roster_grid_passes = roster_grid_passes + 1
		for header in PitBull4:IterateHeaders(true) do
			local group_db = header.group_db
			if header.group_based and group_db and group_db.enabled and not header.force_show then
				header:StabilizeGroupGridGeometry()
				header:RestoreConfiguredGroupAnchor()
				roster_grid_headers = roster_grid_headers + 1
			end
		end
	end)
end
function PitBull4:Lorenzo121GroupGridStatusLine()
	return "12.1 groupGrid rosterReconcile=next-frame savedAnchor=restored capacity=configured-filtered"
		.. " pending=" .. (roster_grid_pending and "yes" or "no")
		.. " passes=" .. roster_grid_passes .. " headers=" .. roster_grid_headers
end
stable_grid_hook_frame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		install_secure_group_header_hook()
		self:UnregisterEvent("PLAYER_LOGIN")
	elseif event == "GROUP_ROSTER_UPDATE" or (event == "PLAYER_REGEN_ENABLED" and roster_grid_pending) then
		queue_roster_grid_reconcile()
	end
end)

-- utility function for ApplyConfigModeState
local function fill_table(tbl, ...)
	for i = 1, select('#', ...), 1 do
		local key = select(i, ...)
		key = tonumber(key) or strtrim(key)
		tbl[key] = i
	end
end

-- utility function for ApplyConfigModeState
local function double_fill_table(tbl, ...)
	fill_table(tbl, ...)
	for i = 1, select('#', ...), 1 do
		local key = select(i, ...)
		tbl[i] = strtrim(key)
	end
end

-- utility function for ApplyConfigModeState, it doctors
-- up some data so don't reuse this elsewhere
local function get_public_roster_name(unit)
	local name, server = UnitName(unit)
	if issecretvalue(name) then name = nil end
	if issecretvalue(server) then server = nil end
	return name, server
end

local function get_group_roster_info(super_unit_group, index)
	local _, unit, name, subgroup, class_name, role, server, assigned_role
	if super_unit_group == "raid" then
		unit = "raid"..index
		name, _, subgroup, _, _, class_name, _, _, _, role, _, assigned_role = GetRaidRosterInfo(index)
	elseif super_unit_group == "boss" then
		unit = "boss"..index
		if UnitExists(unit) then
			name = get_public_roster_name(unit)
			_, class_name = UnitClass(unit)
			subgroup = 1
		end
	elseif super_unit_group == "arena" then
		unit = "arena"..index
		if UnitExists(unit) then
			name, server = get_public_roster_name(unit)
			if name and server and server ~= "" then
				name = name.."-"..server
			end
			_, class_name = UnitClass(unit)
			subgroup = 1
		end
	else
		if index > 0 then
			unit = "party"..index
		else
			unit = "player"
		end
		if UnitExists(unit) then
			name, server = get_public_roster_name(unit)
			if name and server and server ~= "" then
				name = name.."-"..server
			end
			_, class_name = UnitClass(unit)
			-- The UnitInParty and UnitInRaid checks are an ugly workaround for thee
			-- You are not in a party bug that Blizzard created.
			if not PitBull4.leaving_world and (UnitInAnyGroup(unit)) then
				if GetPartyAssignment("MAINTANK", unit) then
					role = "MAINTANK"
				elseif GetPartyAssignment("MAINASSIST", unit) then
					role = "MAINASSIST"
				end
			end
			assigned_role = UnitGroupRolesAssigned(unit)
			subgroup = 1
		end
	end

	-- Midnight 12.1 may protect assigned-role identity. Never let a secret role
	-- reach token-table indexing, filtering, or addon-owned grouping logic.
	if issecretvalue(name) then name = nil end
	if issecretvalue(class_name) then class_name = nil end
	if issecretvalue(role) then role = nil end
	if issecretvalue(subgroup) then subgroup = nil end
	if issecretvalue(assigned_role) then assigned_role = nil end
	class_name = class_name or "!"
	subgroup = subgroup or 0

	-- return some bogus data to get our fake unit ids to sort where we want.
	if not name then
		name = string.format("~%02d",index)
		subgroup = 0
		class_name = '!'
	end

	return unit, name, subgroup, class_name, role, assigned_role
end

-- utility function for ApplyConfigModeState
-- Give a point return the opposite point and which axes the point
-- depends on.
local function get_relative_point_anchor(point)
	point = point:upper()
	if point == "TOP" then
		return "BOTTOM", 0, -1
	elseif point == "BOTTOM" then
		return "TOP", 0, 1
	elseif point == "LEFT" then
		return "RIGHT", 1, 0
	elseif point =="RIGHT" then
		return "LEFT", -1, 0
	elseif point == "TOPLEFT" then
		return "BOTTOMRIGHT", 1, -1
	elseif point == "TOPRIGHT" then
		return "BOTTOMLEFT", -1, -1
	elseif point == "BOTTOMLEFT" then
		return "TOPRIGHT", 1, 1
	elseif point == "BOTTOMRIGHT" then
		return "TOPLEFT", -1, 1
	else
		return "CENTER", 0, 0
	end
end

-- Tables used by ApplyConfigModeState
local sorting_table = {}
local token_table = {}
local grouping_table = {}
local temp_table = {}

-- utility function for ApplyConfigModeState
local function sort_on_group_with_names(a, b)
	local order1 = token_table[ grouping_table[a] ]
	local order2 = token_table[ grouping_table[b] ]
	if order1 then
		if not order2 then
			return true
		else
			if order1 == order2 then
				return sorting_table[a] < sorting_table[b]
			else
				return order1 < order2
			end
		end
	else
		if order2 then
			return false
		else
			return sorting_table[a] < sorting_table[b]
		end
	end
end

-- utility function for ApplyConfigModeState
local function sort_on_group_with_ids(a, b)
	local order1 = token_table[ grouping_table[a] ]
	local order2 = token_table[ grouping_table[b] ]
	if order1 then
		if not order2 then
			return true
		else
			if order1 == order2 then
				return tonumber(a:match("%d+") or -1) < tonumber(b:match("%d+") or -1)
			else
				return tonumber(order1) < tonumber(order2)
			end
		end
	else
		if order2 then
			return false
		else
			return tonumber(a:match("%d+") or -1) < tonumber(b:match("%d+") or -1)
		end
	end
end

-- utility function for ApplyConfigModeState
local function sort_on_names(a, b)
	return sorting_table[a] < sorting_table[b]
end

-- utility function for ApplyConfigModeState
local function sort_on_name_list(a, b)
	return token_table[ sorting_table[a] ] < token_table[ sorting_table[b] ]
end

-- ApplyConfigModeState adjusts the member frames of a GroupHeader to allow
-- them to function in config mode. It generates a bunch of fake unit ids
-- for frames being show in config mode.  It also positions the frames. It's
-- largely a rework of SecureGroupHeader_Update for our purposes.  We need to
-- generate unit ids in roughly the same order that the group header would for
-- real frames but we want the fake units to always be after the real units.
-- Sadly that makes this code pretty downright ugly.
function GroupHeader:ApplyConfigModeState()
	if not self.force_show then
		return
	end

	local old_ignore = self:SetAttribute("_ignore")
	self:SetAttribute("_ignore", "applyConfigModeState")

	wipe(sorting_table)

	local super_unit_group = self.super_unit_group
	local config_mode = PitBull4.config_mode
	local start, finish, step = 1, self:GetMaxUnits(true), 1

	if self.include_player then
		-- start at 0 for the player
		start = 0
		finish = finish - 1 -- GetMaxUnits already accounts for include_player
	end


	local name_list = self:GetAttribute("nameList")
	local group_filter = self:GetAttribute("groupFilter")
	local sort_method = self:GetAttribute("sortMethod")
	local group_by = self:GetAttribute("groupBy")
	local sort_dir = self:GetAttribute("sortDir")

	if not group_filter and not name_list then
		group_filter = "1,2,3,4,5,6,7,8"
	end


	if group_filter then
		local strict_filtering = self:GetAttribute("strictFiltering")

		-- Add in our bogus group and class to the group filter.
		group_filter = group_filter..',0,!'

		-- filter by a list of group numbers and/or classes
		fill_table(wipe(token_table), strsplit(",", group_filter))

		if strict_filtering then
			fill_table(token_table, "MAINTANK", "MAINASSIST", "TANK", "HEALER", "DAMAGER", "NONE")
		end

		for i = start, finish, 1 do
			local unit, name, subgroup, class_name, role, assigned_role = get_group_roster_info(super_unit_group, i)

			if name and (not strict_filtering
				and (token_table[subgroup] or token_table[class_name] or (role and token_table[role]) or token_table[assigned_role])) -- non-strict filtering
				or (token_table[subgroup] and token_table[class_name] and ((role and token_table[role]) or token_table[assigned_role])) -- strict filtering
				then
				sorting_table[#sorting_table+1] = unit
				sorting_table[unit] = name
				if group_by == "GROUP" then
					grouping_table[unit] = subgroup
				elseif group_by == "CLASS" then
					grouping_table[unit] = class_name
				elseif group_by == "ROLE" then
					grouping_table[unit] = role
				elseif group_by == "ASSIGNEDROLE" then
					grouping_table[unit] = assigned_role
				end
			end
		end

		if group_by then
			local grouping_order = self:GetAttribute("groupingOrder")

			-- Add in our bogus group token onto the grouping_order
			local bogus_group = 0
			if group_by == "CLASS" then
				bogus_group = '!'
			end
			grouping_order = grouping_order..','..bogus_group

			double_fill_table(wipe(token_table), strsplit(",", grouping_order:gsub("%s+", "")))
			if sort_method == "NAME" then
				table.sort(sorting_table, sort_on_group_with_names)
			else
				table.sort(sorting_table, sort_on_group_with_ids)
			end
		elseif sort_method == "NAME" then -- sort by ID by default
			table.sort(sorting_table, sort_on_names)
		end
	else
		--filtering via a list of names
		double_fill_table(wipe(token_table), strsplit(",", name_list))
		for i = start, finish, 1 do
			local unit, name = get_group_roster_info(super_unit_group, i)
			if token_table[name] then
				sorting_table[#sorting_table+1] = unit
				sorting_table[unit] = name
			end
		end
		if sort_method == "NAME" then
			table.sort(sorting_table, sort_on_names)
		elseif sort_method == "NAMELIST" then
			table.sort(sorting_table, sort_on_name_list)
		end
	end

	-- setup to actually set the units on the frames.
	-- From here on out the code is roughly borrowed
	-- from configureChildren.  However, we shortcut
	-- startingIndex to always be 1.  If we ever
	-- configure the startingIndex to be something else
	-- this code will have to be adjusted.
	local point = self:GetAttribute("point") or "TOP" --default anchor point of "TOP"
	local relative_point, x_offset_mult, y_offset_mult = get_relative_point_anchor(point)
	local x_multiplier, y_multiplier = abs(x_offset_mult), abs(y_offset_mult)
	local x_offset = self:GetAttribute("xOffset") or 0
	local y_offset = self:GetAttribute("yOffset") or 0
	local column_spacing = self:GetAttribute("columnSpacing") or 0
	local units_per_column = self:GetAttribute("unitsPerColumn")

	-- Patch 089: Config Mode has two independent geometries:
	--   1) the full header envelope used for the saved group anchor, and
	--   2) the currently requested number of visible synthetic members.
	-- Keep child1 pinned to the full-grid corner whenever the configured group
	-- can wrap, even if this preview currently occupies only one row/column.
	local envelope_max = self:GetMaxUnits()
	local envelope_units_per_column = units_per_column
	local envelope_num_columns = 1
	if envelope_units_per_column and envelope_units_per_column > 0 and envelope_max > envelope_units_per_column then
		envelope_num_columns = min(ceil(envelope_max / envelope_units_per_column), (self:GetAttribute("maxColumns") or envelope_max))
	end

	local num_displayed = #sorting_table
	local preview_limit = get_config_preview_limit(config_mode, super_unit_group)
	if preview_limit and preview_limit < num_displayed then
		num_displayed = preview_limit
	end
	local filtered_max = self:GetMaxUnits()
	if filtered_max < num_displayed then
		num_displayed = filtered_max
	end

	local num_columns
	if units_per_column and num_displayed > units_per_column then
		num_columns = min( ceil(num_displayed / units_per_column), (self:GetAttribute("maxColumns") or 1) )
	else
		units_per_column = num_displayed
		num_columns = 1
	end

	start, finish = 1, num_displayed
	if sort_dir == "DESC" then
		start, finish, step = finish, start, -1
	end

	local column_anchor_point, column_rel_point, colx_multi, coly_multi
	if num_columns > 1 or envelope_num_columns > 1 then
		column_anchor_point = self:GetAttribute("columnAnchorPoint")
		if column_anchor_point then
			column_rel_point, colx_multi, coly_multi = get_relative_point_anchor(column_anchor_point)
		end
	end

	local frame_num = 0
	local column_num = 1
	local column_unit_count = 0
	local current_anchor = self
	for i = start, finish, step do
		frame_num = frame_num + 1
		column_unit_count = column_unit_count + 1
		if column_unit_count > units_per_column then
			column_unit_count = 1
			column_num = column_num + 1
		end

		local frame = self[frame_num]
		if not frame then
			break
		end
		if frame_num == 1 then
			frame:SetPoint(point, current_anchor, point, 0, 0)
			-- Use the full configured grid, not only the visible preview, to
			-- decide whether child1 needs the orthogonal corner anchor. For a
			-- 2x2 party grid this keeps Party-1/2 at the same top edge as 3/4.
			if envelope_num_columns > 1 and column_anchor_point then
				frame:SetPoint(column_anchor_point, current_anchor, column_anchor_point, 0, 0)
			end
		elseif column_unit_count == 1 then
			local child_num = frame_num - units_per_column
			local column_anchor = self[child_num]
			frame:SetPoint(column_anchor_point, column_anchor, column_rel_point, colx_multi * column_spacing, coly_multi * column_spacing)
		else
			frame:SetPoint(point, current_anchor, relative_point, x_multiplier * x_offset, y_multiplier * y_offset)
		end

		local old_unit = frame:GetAttribute("unit")
		local unit = sorting_table[i]
		frame:SetAttribute("unit", unit)
		if old_unit ~= unit then
			frame:Update()
		end

		current_anchor = frame
	end

	-- Patch 088: when switching from a larger preview (for example Party - 4)
	-- to a smaller one, clear synthetic units from the no-longer-used frames.
	-- Otherwise those frames can remain visible from the previous Config Mode.
	for i = frame_num + 1, #self do
		local frame = self[i]
		if frame then
			local old_unit = frame:GetAttribute("unit")
			if old_unit then
				frame:SetAttribute("unit", nil)
				frame:Update()
			end
		end
	end

	self:SetAttribute("_ignore", old_ignore)
end
GroupHeader.ApplyConfigModeState = PitBull4:OutOfCombatWrapper(GroupHeader.ApplyConfigModeState)

local ipairs_upto_num
do
	local ipairs_helpers = setmetatable({}, {__index=function(self, num)
		local f = function(t, i)
			i = i + 1
			if i > num then
				return nil
			end

			local v = t[i]
			if v == nil then
				return nil
			end

			return i, v
		end
		self[num] = f
		return f
	end})
	function ipairs_upto_num(t, num)
		return ipairs_helpers[num], t, 0
	end
end

local function get_filter_type_count(...)
	local start = select(1, ...)
	return tonumber(start) and true or false, select('#', ...)
end

function GroupHeader:GetMaxUnits(ignore_filters)
	if self.super_unit_group == "raid" then
		if not ignore_filters and self.group_db then
			local group_filter = self.group_db.group_filter
			if group_filter then
				-- If we're filtering by raid group we may not need all 40
				-- units for this group header.
				local by_raid_group,count = get_filter_type_count(strsplit(",",group_filter))
				if by_raid_group then
					return MEMBERS_PER_RAID_GROUP * count
				end
			end
		end

		-- Everything else we're gonna have to go by max.
		return MAX_RAID_MEMBERS
	elseif self.super_unit_group == "boss" then
		return MAX_BOSS_FRAMES
	elseif self.super_unit_group == "arena" then
		return MAX_PARTY_MEMBERS_WITH_PLAYER
	else
		if self.include_player then
			return MAX_PARTY_MEMBERS_WITH_PLAYER
		else
			return MAX_PARTY_MEMBERS
		end
	end
end

local make_set
do
	local set = {}
	function make_set(...)
		wipe(set)
		local n = select('#', ...)
		for i = 1, n do
			set[select(i, ...)] = true
		end

		return set, n
	end
end

function GroupHeader:IterateMembers(guess_num)
	local max_units = self:GetMaxUnits()
	local num
	if guess_num then
		local config_mode = PitBull4.config_mode
		if config_mode and not self.group_based then
			num = 5
		elseif config_mode == "solo" then
			num = self.include_player and 1 or 0
		elseif config_mode == "party" then
			num = self.include_player and MAX_PARTY_MEMBERS_WITH_PLAYER or MAX_PARTY_MEMBERS
		elseif type(config_mode) == "string" and config_mode:match("^party[1-4]$") then
			num = tonumber(config_mode:sub(6))
		elseif type(config_mode) == "string" then
			if config_mode == "raid" then
				num = 5
			else
				num = tonumber(config_mode:match("^raid(%d+)$")) or max_units
			end
			-- check filters

			local filter = self.group_filter
			if not filter then
				-- do nothing, all is shown
			elseif filter == "" then
				-- all is hidden for some reason
				num = 0
			else
				local set, count = make_set((","):split(filter))
				local start = next(set)
				if start == "MAINTANK" or start == "MAINASSIST" then
					num = MINIMUM_EXAMPLE_GROUP
				elseif RAID_CLASS_COLORS[start] then
					num = math.ceil(num * count / NUM_CLASSES)
					if num < MINIMUM_EXAMPLE_GROUP then
						num = MINIMUM_EXAMPLE_GROUP
					end
				elseif tonumber(start) then
					local count = 0
					for i = 1, num / MEMBERS_PER_RAID_GROUP do
						if set[i..""] then
							count = count + 1
						end
					end
					num = count * MEMBERS_PER_RAID_GROUP
				end
			end
		end
	end

	if not num or num > max_units then
		num = max_units
	end
	return ipairs_upto_num(self, num)
end

function GroupHeader:ForceShow()
	in_force_show = true
	if not self.force_show then
		if hook_SecureGroupHeader_Update then
			hook_SecureGroupHeader_Update()
		end
		self.force_show = true
		self:ForceUnitFrameCreation()
		self:RefixSizeAndPosition()
		if not self.label then
			local label = self:CreateFontString(self:GetName() .. "_Label", "OVERLAY", "ChatFontNormal")
			self.label = label
			local font, size, modifier = label:GetFont()
			label:SetFont(font, size * 1.5, modifier)
			label:SetText(self.name)
			position_label(self, label)
		end
		self.label:Show()
	end

	-- Always make sure that the members ForceShow() is called. Patch 088 also
	-- unforces frames beyond the selected synthetic preview count so changing
	-- Party - 4 -> Party - 2 updates immediately without stale members.
	local shown = 0
	for _, frame in self:IterateMembers(true) do
		shown = shown + 1
		frame:ForceShow()
		frame:Update(true, true)
	end
	for i = shown + 1, #self do
		local frame = self[i]
		if frame and frame.force_show then
			frame:UnforceShow()
		end
	end
	in_force_show = false
end
GroupHeader.ForceShow = PitBull4:OutOfCombatWrapper(GroupHeader.ForceShow)

function GroupHeader:UnforceShow()
	if not self.force_show then
		return
	end
	self.force_show = nil
	self.label:Hide()
	for _, frame in ipairs(self) do
		frame:UnforceShow()
	end
end
GroupHeader.UnforceShow = PitBull4:OutOfCombatWrapper(GroupHeader.UnforceShow)

function GroupHeader:Rename(name)
	local old_name = self.name
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
		if rel_type == "g" or rel_type == "f" then
			local rel_name = rel_to:sub(2)
			if rel_name == old_name then
				group_db.relative_to = rel_type .. name
			end
		end
	end
	for unit, unit_db in pairs(PitBull4.db.profile.units) do
		local rel_to = unit_db.relative_to
		local rel_type = rel_to:sub(1,1)
		if rel_type == "g" or rel_type == "f" then
			local rel_name = rel_to:sub(2)
			if rel_name == old_name then
				unit_db.relative_to = rel_type .. name
			end
		end
	end

	local pet_based = not not self.group_db.unit_group:match("pet") -- this feels dirty
	local use_pet_header = pet_based and self.group_db.use_pet_header
	local group_based = self.group_db.group_based
	local prefix
	if not group_based then
		prefix = "PitBull4_EnemyGroups_"
	elseif use_pet_header then
		prefix = "PitBull4_PetGroups_"
	else
		prefix = "PitBull4_Groups_"
	end

	local old_header_name = prefix .. old_name
	local new_header_name = prefix .. name

	PitBull4.name_to_header[old_name] = nil
	PitBull4.name_to_header[name] = self
	_G[old_header_name] = nil
	_G[new_header_name] = self
	self.name = name
	if self.label then
		self.label:SetText(name)
	end

	for i, frame in ipairs(self) do
		frame.classification = name
	end
end

function GroupHeader:ClearFrames()
	-- Clears the frames over a 10 minute period.  Starting from the
	-- end working our way to the front
	local clear_index = self.clear_index
	-- Frames will have no guid at this point so Update == Clear
	self[clear_index]:Update()
	clear_index = clear_index - 1
	if clear_index > 0 then
		local max_units = self:GetMaxUnits()
		if clear_index > max_units then
			max_units = clear_index + 1
		end
		local delay = 600 / (max_units - 1)
		self.clear_index = clear_index
		self.clear_timer = PitBull4:ScheduleTimer(self.ClearFrames, delay, self)
	else
		self.clear_index = nil
		self.clear_timer = nil
	end
end

function GroupHeader__scripts:OnHide()
	if self.dont_update then return end
	-- Remove any existing timer so we don't just grow timers endlessly.
	local clear_timer = self.clear_timer
	if clear_timer then
		PitBull4:CancelTimer(clear_timer)
	end
	-- Start clearing the frames in 5 minutes.
	self.clear_index = #self
	self.clear_timer = PitBull4:ScheduleTimer(self.ClearFrames, 300, self)
end

function GroupHeader__scripts:OnShow()
	if self.dont_update then return end
	local clear_timer = self.clear_timer
	if clear_timer then
		PitBull4:CancelTimer(clear_timer, true)
		self.clear_timer = nil
		self.clear_index = nil
	end

	if not self.force_show then
		-- Force a SecureGroupHeader_Update to fix the listing if unit info wasn't ready on join (ticket 1251)
		PitBull4:ScheduleTimer(self.Update, 1, self)
	end
end

local moving_frame, moving_member, moving_sticky
function MemberUnitFrame__scripts:OnDragStart()
	local db = PitBull4.db.profile
	if db.lock_movement or InCombatLockdown() then
		return
	end
	if not PitBull4:BeginFrameDrag(self, MemberUnitFrame__scripts.OnDragStop) then return end

	local header = self.header
	moving_frame = header
	moving_member = self
	moving_sticky = db.frame_snap and LibStub("LibSimpleSticky-1.0") or nil

	if moving_sticky then
		moving_sticky:StartMoving(header, PitBull4.all_frames_list, 0, 0, 0, 0)
	else
		header:StartMoving()
	end
end

function MemberUnitFrame__scripts:OnDragStop()
	local header = self.header
	if moving_frame ~= header then return end
	moving_frame = nil
	PitBull4:EndFrameDrag(moving_member)
	moving_member = nil
	local sticky = moving_sticky
	moving_sticky = nil

	if sticky then
		sticky:StopMoving(header)
	else
		header:StopMovingOrSizing()
	end

	local db = header.group_db
	local anchor = db.anchor
	if anchor == "" then
		anchor = DIRECTION_TO_GROUP_ANCHOR_POINT[db.direction]
	end
	local relative_frame = PitBull4.Utils.GetRelativeFrame(db.relative_to)
	local relative_point = db.relative_point
	local frame = header[1]

	local ui_scale = UIParent:GetEffectiveScale()
	local scale = frame:GetEffectiveScale() / ui_scale

	local x, y
	if anchor == "TOPLEFT" then
		x, y = frame:GetLeft(), frame:GetTop()
	elseif anchor == "TOPRIGHT" then
		x, y = frame:GetRight(), frame:GetTop()
	elseif anchor == "BOTTOMLEFT" then
		x, y = frame:GetLeft(), frame:GetBottom()
	elseif anchor == "BOTTOMRIGHT" then
		x, y = frame:GetRight(), frame:GetBottom()
	elseif anchor == "CENTER" then
		x, y = frame:GetCenter()
	elseif anchor == "TOP" then
		x = frame:GetCenter()
		y = frame:GetTop()
	elseif anchor == "BOTTOM" then
		x = frame:GetCenter()
		y = frame:GetBottom()
	elseif anchor == "LEFT" then
		x, y = frame:GetCenter()
		x = frame:GetLeft()
	elseif anchor == "RIGHT" then
		x, y = frame:GetCenter()
		x = frame:GetRight()
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

	db.position_x = x - x2
	db.position_y = y - y2

	LibStub("AceConfigRegistry-3.0"):NotifyChange("PitBull4")

	header:RefreshLayout(true)
end

function MemberUnitFrame__scripts:OnMouseUp(button)
	if button == "LeftButton" then
		return MemberUnitFrame__scripts.OnDragStop(self)
	end
end

function MemberUnitFrame:PLAYER_REGEN_DISABLED()
	if moving_frame then
		MemberUnitFrame__scripts.OnDragStop(moving_member)
	end
end

local clickcast_register = [[
  local button = self:GetFrameRef("pb4_temp")
  local clickcast_header = self:GetFrameRef("clickcast_header")
  if clickcast_header:GetAttribute("clickcast_register") then
    clickcast_header:SetAttribute("clickcast_button",button)
    clickcast_header:RunAttribute("clickcast_register")
  end
]]

local clickcast_unregister = [[
  local button = self:GetFrameRef("pb4_temp")
  local clickcast_header = self:GetFrameRef("clickcast_header")
  if clickcast_header:GetAttribute("clickcast_unregister") then
    clickcast_header:SetAttribute("clickcast_button",button)
    clickcast_header:RunAttribute("clickcast_unregister")
  end
]]

-- Set the frame as able to be clicked through or not.
-- @usage frame:SetClickThroughState(true)
function MemberUnitFrame:SetClickThroughState(state)
	local mouse_state = not not self:IsMouseEnabled()
	if (not state) ~= mouse_state then
		if ClickCastHeader then
			local header = self:GetParent()
			SecureHandlerSetFrameRef(header, "pb4_temp", self)
			SecureHandlerExecute(header, not mouse_state and clickcast_register or clickcast_unregister)
		end
		self:EnableMouse(not mouse_state)
		self:SetAttribute("ping-receiver", not mouse_state or nil)
	end
end
MemberUnitFrame.SetClickThroughState = PitBull4:OutOfCombatWrapper(MemberUnitFrame.SetClickThroughState)

--- Reset the size of the unit frame, not position as that is handled through the group header.
-- @usage frame:RefixSizeAndPosition()
function MemberUnitFrame:RefixSizeAndPosition()
	if not self:CanChangeProtectedState() then return end
	local layout_db = self.layout_db
	local classification_db = self.classification_db

	self:SetWidth(layout_db.size_x * classification_db.size_x)
	self:SetHeight(layout_db.size_y * classification_db.size_y)
end

function MemberUnitFrame:ForceShow()
	if not self.force_show then
		self.force_show = true

		-- Continue to watch the frame but do the hiding and showing ourself
		UnregisterUnitWatch(self)
		RegisterUnitWatch(self, true)
	end

	-- Always make sure the frame is shown even if we think it already is
	self:Show()
end
MemberUnitFrame.ForceShow = PitBull4:OutOfCombatWrapper(MemberUnitFrame.ForceShow)

function MemberUnitFrame:UnforceShow()
	if not self.force_show then
		return
	end
	self.force_show = nil

	-- Ask the SecureStateDriver to show/hide the frame for us
	UnregisterUnitWatch(self)
	RegisterUnitWatch(self)

	-- If we're visible force an update so everything is properly in a
	-- non-config mode state
	if self:IsVisible() then
		self:Update()
	end
	PitBull4:CallMethodOnModules("OnFrameLayoutChanged", self)
end
MemberUnitFrame.UnforceShow = PitBull4:OutOfCombatWrapper(MemberUnitFrame.UnforceShow)

--- Visually show a line connecting anchored frames
function GroupHeader:UpdateConfigAnchorLine()
	local db = self.group_db
	if not self.force_show or not db then
		if self.anchor_line then
			self.anchor_line:Hide()
		end
		return
	end

	local anchor = db.anchor
	if anchor == "" then
		anchor = DIRECTION_TO_GROUP_ANCHOR_POINT[db.direction]
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
		self.anchor_line:SetStartPoint(anchor, self)
		self.anchor_line:SetEndPoint(db.relative_point, relative_frame)
		self.anchor_line:Show()
	elseif self.anchor_line then
		self.anchor_line:Hide()
	end
end
GroupHeader.UpdateConfigAnchorLine = PitBull4:OutOfCombatWrapper(GroupHeader.UpdateConfigAnchorLine)


local initialConfigFunction = [[
    local header = self:GetParent()
    local unitsuffix = header:GetAttribute("unitsuffix")
    if unitsuffix then
      self:SetAttribute("unitsuffix", unitsuffix)
    end
    self:SetWidth(header:GetAttribute("unitWidth"))
    self:SetHeight(header:GetAttribute("unitHeight"))
    RegisterUnitWatch(self)
    self:SetAttribute("*type1", "target")
    self:SetAttribute("*type2", "togglemenu")
    local click_through = header:GetAttribute("clickThrough")
    if not click_through then
      -- Verify important the CallMethod is done BEFORE the frame is
      -- registered with Clique so that Clique can override our click
      -- registrations.
      header:CallMethod("InitialConfigFunction")
      -- Support for Clique
      local clickcast_header = header:GetFrameRef("clickcast_header")
      if clickcast_header then
        clickcast_header:SetAttribute("clickcast_button", self)
        clickcast_header:RunAttribute("clickcast_register")
      end
    else
      self:EnableMouse(false)
      -- Very important that the CallMethod is done AFTER the mouse is
      -- potentially disabled above because otherwise it will create a
      -- stack overflow.
      header:CallMethod("InitialConfigFunction")
    end
]]

local function header_OnEvent(self, event, arg1)
	if not self:IsShown() then return end

	if event == "UPDATE_BATTLEFIELD_STATUS" and GetBattlefieldStatus(arg1) ~= "active" then
	 return
	end

	for _, frame in self:IterateMembers() do
		local unit = frame.unit
		if unit and (UnitExists(unit) or UnitIsVisible(unit)) then
			frame:UpdateGUID(UnitGUID(unit), true)
		else
			frame:UpdateGUID(nil)
		end
	end
end

local function frame_OnEvent(self, event, unit)
	if event == "ARENA_OPPONENT_UPDATE" and unit ~= self.unit then
		return
	end

	if UnitExists(self.unit) or UnitIsVisible(self.unit) then
		self:UpdateGUID(UnitGUID(self.unit), true)
	end
end

local function frame_OnUpdate(self, elapsed)
	self.elapsed = self.elapsed + elapsed
	if self.elapsed < 0.5 then return end
	-- One current-state poll is enough after a hitch; carrying missed intervals
	-- would turn this 0.5 second fallback into a poll on every render frame.
	self.elapsed = self.elapsed % 0.5

	if UnitExists(self.unit) or UnitIsVisible(self.unit) then
		self:UpdateGUID(UnitGUID(self.unit))
	end
end

local function frame_OnAttributeChanged(self, key, value)
	if key ~= "unit" and key ~= "unitsuffix" then return end

	local old_unit = self.unit
	local new_unit = PitBull4.Utils.GetBestUnitID(SecureButton_GetModifiedUnit(self, "LeftButton")) or nil
	if old_unit == new_unit then
		return
	end

	if old_unit then
		PitBull4.unit_id_to_frames[old_unit][self] = nil
		PitBull4.unit_id_to_frames_with_wacky[old_unit][self] = nil

		self:SetScript("OnUpdate", nil)
		self:UnregisterEvent("UNIT_NAME_UPDATE")
		self:UnregisterEvent("ARENA_OPPONENT_UPDATE")
		self:UnregisterEvent("UNIT_TARGETABLE_CHANGED")
		self:UnregisterEvent("UNIT_TARGET")
		self:UnregisterEvent("UNIT_PET")

		self.unit = nil
		self.guid = nil
	end

	if new_unit then
		self.unit = new_unit
		self.guid = UnitGUID(new_unit)

		PitBull4.unit_id_to_frames[new_unit][self] = true
		PitBull4.unit_id_to_frames_with_wacky[new_unit][self] = true

		if new_unit:match("^arena") then
			-- not an actual unit event :(
			self:RegisterEvent("ARENA_OPPONENT_UPDATE")
		end
		self:RegisterUnitEvent("UNIT_NAME_UPDATE", new_unit)
		self:RegisterUnitEvent("UNIT_TARGETABLE_CHANGED", new_unit)

		local unitsuffix = self:GetAttribute("unitsuffix")
		if unitsuffix then
			local is_pet = unitsuffix:match("pet")
			local event_unit = is_pet and new_unit.."pet" or new_unit

			if unitsuffix:match("target") then
				self:RegisterUnitEvent("UNIT_TARGET", event_unit)
				self.elapsed = 0.5
				self:SetScript("OnUpdate", frame_OnUpdate)
			end
			if is_pet then
				self:RegisterUnitEvent("UNIT_PET", event_unit, new_unit)
			end
		end
	end

	self:Update(false)
end

--- Add the proper functions and scripts to a SecureGroupHeaderTemplate or SecureGroupPetHeaderTemplate, as well as some initialization.
-- @param header a Frame which inherits from SecureGroupHeaderTemplate or SecureGroupPetHeaderTemplate
-- @usage PitBull4:ConvertIntoGroupHeader(header)
function PitBull4:ConvertIntoGroupHeader(header)
	if DEBUG then
		expect(header, 'typeof', 'frame')
		expect(header, 'frametype', 'Frame')
	end

	self.all_headers[header] = true
	self.name_to_header[header.name] = header

	for k, v in pairs(GroupHeader__scripts) do
		header:HookScript(k, v)
	end

	for k, v in pairs(GroupHeader) do
		header[k] = v
	end

	if ClickCastHeader then
		SecureHandlerSetFrameRef(header, "clickcast_header", ClickCastHeader)
	end

	if header.group_based then
		-- this is done to pass self in properly
		function header.initialConfigFunction(...)
			return header:InitialConfigFunction(...)
		end
		header:SetAttribute("initialConfigFunction", initialConfigFunction)
	else
		-- enemy groups are not run from a SecureGroupHeader
		header:SetScript("OnEvent", header_OnEvent)
	end

	header:RefreshGroup(true)

	header:SetMovable(true)
end


--- Create child frames for an enemy group header and finish configuring them.
-- @usage header:ConfigureChildren()
function GroupHeader:ConfigureChildren()
	if not self.group_db.enabled then return end

	wipe(sorting_table)
	local start, finish, step = 1, self:GetMaxUnits(), 1
	local super_unit_group = self.super_unit_group
	for i = start, finish, step do
		sorting_table[#sorting_table + 1] = super_unit_group .. i
	end

	local point = self:GetAttribute("point") or "TOP"
	local relative_point, x_offset_mult, y_offset_mult = get_relative_point_anchor(point)
	local x_multiplier, y_multiplier = abs(x_offset_mult), abs(y_offset_mult)
	local x_offset = self:GetAttribute("xOffset") or 0
	local y_offset = self:GetAttribute("yOffset") or 0
	local sort_dir = self:GetAttribute("sortDir") or "ASC"
	local column_spacing = self:GetAttribute("columnSpacing") or 0
	local units_per_column = self:GetAttribute("unitsPerColumn")
	local num_displayed = #sorting_table
	local num_columns
	if units_per_column and num_displayed > units_per_column then
		num_columns = min( ceil(num_displayed / units_per_column), (self:GetAttribute("maxColumns") or 1) )
	else
		units_per_column = num_displayed
		num_columns = 1
	end

	if sort_dir == "DESC" then
		start, finish, step = finish, start, -1
	end

	local column_anchor_point, column_rel_point, colx_multi, coly_multi
	if num_columns > 1 then
		column_anchor_point = self:GetAttribute("columnAnchorPoint")
		column_rel_point, colx_multi, coly_multi = get_relative_point_anchor(column_anchor_point)
	end

	local frame_num = 0
	local column_num = 1
	local column_unit_count = 0
	local current_anchor = self
	for i = start, finish, step do
		frame_num = frame_num + 1
		column_unit_count = column_unit_count + 1
		if column_unit_count > units_per_column then
			column_unit_count = 1
			column_num = column_num + 1
		end

		local frame = self[frame_num]
		if not frame then
			-- make a singleton unit frame and tack it onto our header
			local frame_name = self:GetName() .. "UnitButton" .. frame_num
			frame = CreateFrame("Button", frame_name, self, self:GetAttribute("template"))

			frame:Hide()
			frame:EnableMouse(false) -- start disabled so the state change registers the button with Clique

			self[frame_num] = frame
			self:InitialConfigFunction()

			frame:SetScript("OnEvent", frame_OnEvent)
			frame:SetScript("OnAttributeChanged", frame_OnAttributeChanged) -- overwrite the UnitFrame__scripts handler

			frame:WrapScript(frame, "OnAttributeChanged", [[
        if name == "config_mode" and self:GetAttribute("config_mode") then
          self:Show()
        end
      ]])

			RegisterUnitWatch(frame)
		end

		if frame_num == 1 then
			frame:SetPoint(point, current_anchor, point, 0, 0)
			if column_anchor_point then
				frame:SetPoint(column_anchor_point, current_anchor, column_anchor_point, 0, 0)
			end
		elseif column_unit_count == 1 then
			local column_anchor = self[frame_num - units_per_column]
			frame:SetPoint(column_anchor_point, column_anchor, column_rel_point, colx_multi * column_spacing, coly_multi * column_spacing)
		else
			frame:SetPoint(point, current_anchor, relative_point, x_multiplier * x_offset, y_multiplier * y_offset)
		end

		local unit = sorting_table[i]
		frame:SetAttribute("unit", unit)

		local classification_db = frame.classification_db
		if classification_db then
			frame:SetClickThroughState(classification_db.click_through)
		end

		current_anchor = frame
	end

	local frame_width = self[1]:GetWidth()
	local frame_height = self[1]:GetHeight()
	if num_displayed > 0 then
		local width = x_multiplier * (units_per_column - 1) * frame_width + ( (units_per_column - 1) * (x_offset * x_offset_mult) ) + frame_width
		local height = y_multiplier * (units_per_column - 1) * frame_height + ( (units_per_column - 1) * (y_offset * y_offset_mult) ) + frame_height

		if column_num > 1 then
			width = width + ( (column_num - 1) * abs(colx_multi) * (width + column_spacing) )
			height = height + ( (column_num - 1) * abs(coly_multi) * (height + column_spacing) )
		end

		self:SetWidth(width)
		self:SetHeight(height)
	else
		local min_width = self:GetAttribute("minWidth") or (y_multiplier * frame_width)
		local min_height = self:GetAttribute("minHeight") or (x_multiplier * frame_height)
		self:SetWidth( max(min_width, 0.1) )
		self:SetHeight( max(min_height, 0.1) )
	end
end
GroupHeader.ConfigureChildren = PitBull4:OutOfCombatWrapper(GroupHeader.ConfigureChildren)
