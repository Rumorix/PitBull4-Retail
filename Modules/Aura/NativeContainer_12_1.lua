-- PitBull4 12.1 native AuraContainer renderer.
--
-- Patch 008 keeps normal runtime unit-frame auras on Blizzard's protected
-- CustomAuraContainerTemplate / CustomAuraButtonTemplate path. The Patch 114
-- renderer remains available for Config Mode, older clients, and per-frame
-- fallback when the 12.1 API rejects a container configuration.

local PitBull4 = _G.PitBull4
local PitBull4_Aura = PitBull4:GetModule("Aura")

local type = type
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local next = next
local table_concat = table.concat
local table_insert = table.insert
local math_huge = math.huge
local math_max = math.max
local math_min = math.min

local native_enabled = true
local native_frames = setmetatable({}, { __mode = "k" })
local retired_states = setmetatable({}, { __mode = "k" })
local failed_frames = setmetatable({}, { __mode = "k" })
local native_generation = 0
local dynamic_refresh_count = 0
local dynamic_refresh_mark_count = 0
local dynamic_refresh_bounce_count = 0
local native_configuration_count = 0
local native_configuration_skip_count = 0
local container_surface_validated = false
local button_surface_validated = false
local native_surface_validated = false
local native_surface_error = nil

local GROUP_KEY = "pitbull"
local OWN_GROUP_KEY = "pitbull_own"
local OTHER_GROUP_KEY = "pitbull_other"
local NATIVE_COUNT_FONT_CAP_RATIO = 0.55
local NATIVE_DURATION_FONT_CAP_RATIO = 0.45
local NATIVE_BORDER_TEXTURE = [[Interface\AddOns\PitBull4\Modules\Aura\border]]

-- Patch 071 moved native AuraContainer duration text onto Blizzard's
-- DurationTextBinding path and proved that the visible runtime timer was not the
-- legacy PitBull updater. Live testing with W-47CH D0G also showed that forcing
-- DurationTimeModifier.BaseTime is not equivalent to Blizzard's tooltip display
-- time: a tooltip value of 34m could render as 4m.
--
-- Patch 072 therefore prefers the Cooldown widget's own countdown FontString.
-- CustomAuraButton already feeds that widget the protected aura DurationObject
-- through SetCooldownFromDurationObject(), so Blizzard remains responsible for
-- the live aura timing while PitBull only supplies presentation/formatting.
-- The Patch 071 BaseTime binding remains as a defensive fallback for clients
-- where the native Cooldown countdown text cannot be configured.
local native_compact_duration_formatter
local native_base_time_duration_options

local function get_native_compact_duration_formatter()
	if native_compact_duration_formatter ~= nil then
		return native_compact_duration_formatter or nil
	end

	if not C_StringUtil or not C_StringUtil.CreateSecondsFormatter then
		native_compact_duration_formatter = false
		return nil
	end

	local ok_formatter, formatter = pcall(C_StringUtil.CreateSecondsFormatter)
	if not ok_formatter or not formatter then
		native_compact_duration_formatter = false
		return nil
	end

	if formatter.SetDefaultAbbreviation and Enum and Enum.SecondsFormatterAbbreviation and Enum.SecondsFormatterAbbreviation.OneLetter then
		pcall(formatter.SetDefaultAbbreviation, formatter, Enum.SecondsFormatterAbbreviation.OneLetter)
	end
	if formatter.SetStripIntervalWhitespace then
		local whitespace = Enum and Enum.SecondsFormatterIntervalWhitespace and Enum.SecondsFormatterIntervalWhitespace.Strip
		pcall(formatter.SetStripIntervalWhitespace, formatter, whitespace ~= nil and whitespace or true)
	end
	if formatter.SetDesiredUnitCount then
		pcall(formatter.SetDesiredUnitCount, formatter, 1)
	end

	native_compact_duration_formatter = formatter
	return formatter
end

local function get_native_base_time_duration_options()
	if native_base_time_duration_options ~= nil then
		return native_base_time_duration_options or nil
	end

	if not C_DurationUtil or not C_DurationUtil.CreateDurationTextBinding
		or not Enum or not Enum.DurationTimeModifier or Enum.DurationTimeModifier.BaseTime == nil then
		native_base_time_duration_options = false
		return nil
	end

	local ok_binding, binding = pcall(C_DurationUtil.CreateDurationTextBinding)
	if not ok_binding or not binding then
		native_base_time_duration_options = false
		return nil
	end

	if binding.SetTimeModifier then
		local ok_modifier = pcall(binding.SetTimeModifier, binding, Enum.DurationTimeModifier.BaseTime)
		if not ok_modifier then
			native_base_time_duration_options = false
			return nil
		end
	end

	local formatter = get_native_compact_duration_formatter()
	if formatter and binding.SetFormatter then
		pcall(binding.SetFormatter, binding, formatter)
	end

	if binding.SetZeroDurationText then
		pcall(binding.SetZeroDurationText, binding, "")
	end

	native_base_time_duration_options = { binding = binding }
	return native_base_time_duration_options
end

local REQUIRED_CONTAINER_METHODS = {
	"SetEnabled",
	"SetUnit",
	"AddAuraGroup",
	"SetAuraGroupFilterString",
	"SetAuraGroupMaxFrameCount",
	"SetAuraGroupSortMethod",
	"SetAuraGroupLayout",
	"AddItemEnchantment",
	"SetItemEnchantmentSortMethod",
	"SetItemEnchantmentLayout",
	"SetFlowLayoutAxis",
	"SetFlowLayoutAnchorPoint",
	"SetFlowLayoutGrowthDirection",
	"SetFlowLayoutPadding",
	"SetFlowLayoutMaximumLineSize",
}

local REQUIRED_BUTTON_METHODS = {
	"SetIcon",
	"SetDurationCooldown",
	"SetDurationText",
	"SetApplicationCount",
	"AddDispelTypeTexture",
	"SetCancelAuraButtons",
	"SetTooltipAnchorPoint",
	"SetHideTooltipInCombat",
}

-- Keep Blizzard's 12.1.0.69111+ dispel-texture behavior explicit so a future
-- default change cannot silently alter PitBull's native aura presentation.
local NATIVE_DISPEL_TEXTURE_OPTIONS = {
	showAlways = false,
	showWhenHarmful = true,
	showWhenHelpful = false,
	showWithoutDispelType = false,
}

local growth_map = {
	left_up = { axis = "Horizontal", horizontal = "Left", vertical = "Up" },
	left_down = { axis = "Horizontal", horizontal = "Left", vertical = "Down" },
	right_up = { axis = "Horizontal", horizontal = "Right", vertical = "Up" },
	right_down = { axis = "Horizontal", horizontal = "Right", vertical = "Down" },
	up_left = { axis = "Vertical", horizontal = "Left", vertical = "Up" },
	up_right = { axis = "Vertical", horizontal = "Right", vertical = "Up" },
	down_left = { axis = "Vertical", horizontal = "Left", vertical = "Down" },
	down_right = { axis = "Vertical", horizontal = "Right", vertical = "Down" },
}

local control_point = {
	TOPLEFT_TOP = "BOTTOMLEFT",
	TOPRIGHT_TOP = "BOTTOMRIGHT",
	TOPLEFT_LEFT = "TOPRIGHT",
	TOPRIGHT_RIGHT = "TOPLEFT",
	BOTTOMLEFT_BOTTOM = "TOPLEFT",
	BOTTOMRIGHT_BOTTOM = "TOPRIGHT",
	BOTTOMLEFT_LEFT = "BOTTOMRIGHT",
	BOTTOMRIGHT_RIGHT = "BOTTOMLEFT",
}

local function get_object_method(object, method_name)
	if not object then
		return false, "missing-object"
	end
	local lookup_ok, method = pcall(function()
		return object[method_name]
	end)
	if not lookup_ok then
		return false, tostring(method)
	end
	if type(method) ~= "function" then
		return false, "missing-method:" .. tostring(method_name)
	end
	return true, method
end

local function call_method(object, method_name, ...)
	local method_ok, method = get_object_method(object, method_name)
	if not method_ok then
		return false, method
	end
	local ok, result = pcall(method, object, ...)
	if ok then
		return true, result
	end
	return false, tostring(result)
end

local function validate_object_surface(object, object_label, method_names)
	for _, method_name in ipairs(method_names) do
		local ok, err = get_object_method(object, method_name)
		if not ok then
			return false, object_label .. ":" .. tostring(err)
		end
	end
	return true
end

local function validate_container_surface(container)
	if container_surface_validated then
		return true
	end
	local ok, err = validate_object_surface(container, "container", REQUIRED_CONTAINER_METHODS)
	if not ok then
		native_surface_error = err
		return false, err
	end
	container_surface_validated = true
	return true
end

local function validate_button_surface(button)
	if button_surface_validated then
		return true
	end
	local ok, err = validate_object_surface(button, "button", REQUIRED_BUTTON_METHODS)
	if not ok then
		native_surface_error = err
		return false, err
	end
	button_surface_validated = true
	return true
end

local function reset_surface_validation()
	container_surface_validated = false
	button_surface_validated = false
	native_surface_validated = false
	native_surface_error = nil
end


local function get_unit_token(frame)
	if frame and type(frame.unit) == "string" and frame.unit ~= "" then
		return frame.unit
	end
	return "none"
end

local function get_native_text_rule(db, kind)
	if kind == "weapon" then
		return "weapon_buffs"
	end
	local my_rule = kind == "debuff" and "my_debuffs" or "my_buffs"
	local other_rule = kind == "debuff" and "other_debuffs" or "other_buffs"
	local enabled = db and db.cooldown_text
	-- A protected button may be reassigned between player and non-player auras,
	-- so ownership-specific styling cannot be selected from the aura record.
	-- Prefer the player's style unless only the other-aura timer is enabled.
	if enabled and not enabled[my_rule] and enabled[other_rule] then
		return other_rule
	end
	return my_rule
end

local function get_native_text_db(db, rule, text_kind)
	local rule_db = db and db.texts and db.texts[rule]
	return rule_db and rule_db[text_kind] or nil
end

local function get_native_border_db(db, kind)
	local borders = db and db.borders
	if type(borders) ~= "table" then
		return nil, nil, nil
	end
	if kind == "weapon" then
		return borders.weapon_buffs, "weapon_buffs", nil
	end

	-- The protected container owns the aura record, so addon code cannot safely
	-- distinguish the caster or relationship for every assigned button. Prefer
	-- PitBull's "my aura on a friendly unit" presentation: this restores the
	-- long-standing green own-buff border while keeping all secret data opaque.
	local rule = kind == "debuff" and "my_debuffs" or "my_buffs"
	local rule_db = borders[rule]
	return rule_db and rule_db.friend or nil, rule, "friend"
end

local function get_native_border_color(border_db)
	local profile = PitBull4_Aura.db and PitBull4_Aura.db.profile
	local global = profile and profile.global
	local colors = global and global.colors
	local color_type = border_db and border_db.color_type
	local color
	if color_type == "custom" then
		color = border_db.custom_color
	elseif color_type == "type" then
		color = colors and colors.type and colors.type.None
	else
		-- Caster and weapon-quality colors require protected per-aura metadata.
		-- Use PitBull's configured "my caster" color as the safe native fallback.
		color = colors and colors.caster and colors.caster.my
	end
	if type(color) ~= "table" then
		return 1, 1, 1, 1
	end
	return tonumber(color[1]) or 1, tonumber(color[2]) or 1, tonumber(color[3]) or 1, tonumber(color[4]) or 1
end

local function add_native_pitbull_border(button, db, kind)
	local border_db = get_native_border_db(db, kind)
	if not border_db or not border_db.enabled then
		return
	end

	-- This is deliberately not registered as a protected dispel texture. It is
	-- an always-present visual child of the protected aura button, so it follows
	-- the button's secret visibility without inspecting the assigned aura.
	local border = button:CreateTexture(nil, "BORDER")
	border:SetAllPoints(button)
	border:SetTexture(NATIVE_BORDER_TEXTURE)
	border:SetBlendMode("BLEND")
	border:SetVertexColor(get_native_border_color(border_db))
	border:Show()
end

local function ownership_style_enabled(db)
	return db and db.ownership_style and db.ownership_style.enabled and true or false
end

local function get_ownership_color(db, ownership)
	local style = db and db.ownership_style
	local color = style and (ownership == "own" and style.own_color or style.other_color)
	if type(color) ~= "table" then
		if ownership == "own" then
			return 0, 1, 0, 1
		end
		return 1, 0, 0, 1
	end
	return tonumber(color[1]) or 1, tonumber(color[2]) or 1, tonumber(color[3]) or 1, tonumber(color[4]) or 1
end

local function add_native_ownership_border(button, db, ownership)
	if not ownership_style_enabled(db) or (ownership ~= "own" and ownership ~= "other") then
		return false
	end
	local border = button:CreateTexture(nil, "BORDER")
	border:SetAllPoints(button)
	border:SetTexture(NATIVE_BORDER_TEXTURE)
	border:SetBlendMode("BLEND")
	border:SetVertexColor(get_ownership_color(db, ownership))
	border:Show()
	return true
end

local function get_ownership_icon_size(db, cfg, kind, ownership)
	local base = tonumber(cfg and cfg.size) or 16
	if ownership ~= "own" then
		return base
	end

	local style = db and db.ownership_style
	-- Patch 075: preserve the classic PitBull "Icon size for my auras"
	-- setting on the native 12.1 AuraContainer path. Patch 067 added an
	-- optional absolute ownership-size override, but the native renderer must
	-- still honor cfg.my_size whenever that explicit override is disabled.
	if style and style.different_size then
		local configured = kind == "debuff" and tonumber(style.own_debuff_size) or tonumber(style.own_buff_size)
		if configured and configured > 0 then
			return configured
		end
		-- A zero ownership override intentionally inherits the normal aura size.
		return base
	end

	local classic_my_size = tonumber(cfg and cfg.my_size)
	if classic_my_size and classic_my_size > 0 then
		return classic_my_size
	end
	return base
end

local function append_native_border_signature(parts, db, kind)
	local border_db, rule, relationship = get_native_border_db(db, kind)
	local r, g, b, a = get_native_border_color(border_db)
	parts[#parts + 1] = table_concat({
		"border",
		tostring(kind),
		tostring(rule),
		tostring(relationship),
		tostring(border_db and border_db.enabled or false),
		tostring(border_db and border_db.color_type or "none"),
		tostring(r), tostring(g), tostring(b), tostring(a),
	}, ",")
end

local function get_native_justify_h(anchor)
	if type(anchor) == "string" then
		if anchor:find("RIGHT", 1, true) then
			return "RIGHT"
		elseif anchor:find("LEFT", 1, true) then
			return "LEFT"
		end
	end
	return "CENTER"
end

local function resolve_native_text_style(owner_frame, db, kind, text_kind, icon_size)
	local rule = get_native_text_rule(db, kind)
	local text_db = get_native_text_db(db, rule, text_kind) or {}
	local fallback_anchor = text_kind == "count" and "BOTTOMRIGHT" or "TOP"
	local cap_ratio = text_kind == "count" and NATIVE_COUNT_FONT_CAP_RATIO or NATIVE_DURATION_FONT_CAP_RATIO
	local resolved_font
	local resolved_size
	if owner_frame and type(owner_frame.GetFont) == "function" then
		local ok, font, font_size = pcall(owner_frame.GetFont, owner_frame, text_db.font, text_db.size)
		if ok then
			resolved_font = font
			resolved_size = tonumber(font_size)
		end
	end
	icon_size = tonumber(icon_size) or 16
	local maximum_size = math_max(1, icon_size * cap_ratio)
	resolved_size = math_max(1, math_min(resolved_size or maximum_size, maximum_size))
	local color = type(text_db.color) == "table" and text_db.color or nil
	return {
		rule = rule,
		font = resolved_font or _G.STANDARD_TEXT_FONT,
		fontSize = resolved_size,
		anchor = type(text_db.anchor) == "string" and text_db.anchor or fallback_anchor,
		offsetX = tonumber(text_db.offset_x) or 0,
		offsetY = tonumber(text_db.offset_y) or 0,
		colorR = color and tonumber(color[1]) or 1,
		colorG = color and tonumber(color[2]) or 1,
		colorB = color and tonumber(color[3]) or 1,
		colorA = color and tonumber(color[4]) or 1,
	}
end

local function configure_native_font_string(font_string, button, owner_frame, db, kind, text_kind, icon_size)
	local style = resolve_native_text_style(owner_frame, db, kind, text_kind, icon_size)
	font_string:SetFont(style.font, style.fontSize, "OUTLINE")
	font_string:SetTextColor(style.colorR, style.colorG, style.colorB, style.colorA)
	font_string:SetShadowColor(0, 0, 0, 1)
	font_string:SetShadowOffset(0.8, -0.8)
	font_string:SetJustifyH(get_native_justify_h(style.anchor))
	font_string:ClearAllPoints()
	font_string:SetPoint(style.anchor, button, style.anchor, style.offsetX, style.offsetY)
	return style
end

local function append_native_text_style_signature(parts, owner_frame, db, kind, text_kind, icon_size)
	local style = resolve_native_text_style(owner_frame, db, kind, text_kind, icon_size)
	parts[#parts + 1] = table_concat({
		tostring(kind),
		tostring(text_kind),
		tostring(style.rule),
		tostring(style.font),
		tostring(style.fontSize),
		tostring(style.anchor),
		tostring(style.offsetX),
		tostring(style.offsetY),
		tostring(style.colorR),
		tostring(style.colorG),
		tostring(style.colorB),
		tostring(style.colorA),
	}, ",")
end

local function get_native_capabilities()
	local state = PitBull4_Aura.Lorenzo121
	if PitBull4_Aura.Lorenzo121RefreshCapabilities then
		state = PitBull4_Aura:Lorenzo121RefreshCapabilities()
	end
	return state
end

local function native_methods_ready(state)
	return state and state.nativeAPIPrerequisitesReady
		and type(_G.CreateFrame) == "function"
		and type(_G.AuraContainerSortMethod) == "table"
		and type(_G.AuraContainerSortDirection) == "table"
		and type(_G.AnchorUtil) == "table"
		and type(_G.AnchorUtil.FlowLayoutAxis) == "table"
		and type(_G.AnchorUtil.FlowDirection) == "table"
end

local function should_use_native(frame)
	if not native_enabled or not frame or frame.force_show or failed_frames[frame] then
		return false
	end
	local state = get_native_capabilities()
	return state and state.is121OrNewer and state.auraContainerAddonLoaded and native_methods_ready(state)
end

local function enum_value(container, key, fallback)
	if type(container) == "table" and container[key] ~= nil then
		return container[key]
	end
	return fallback
end

local function get_sort_method(cfg, is_buff)
	local method_name = cfg and cfg.sort_rule or "Default"
	local methods = _G.AuraContainerSortMethod
	-- PitBull's legacy/API sort rule is named Unsorted. Blizzard's 12.1 native
	-- AuraContainer exposes the equivalent stable instance order as
	-- AuraInstanceIDOnly, so a direct enum-name lookup would otherwise fall back
	-- to Default and visibly reshuffle the user's auras.
	if method_name == "Unsorted" then
		method_name = "AuraInstanceIDOnly"
	end
	local method = enum_value(methods, method_name, nil)
	if method == nil and not is_buff then
		method = enum_value(methods, "UnitFrameDebuff", nil)
	end
	return method or enum_value(methods, "Default", 0)
end

local function get_sort_direction(cfg)
	local directions = _G.AuraContainerSortDirection
	if cfg and cfg.reverse then
		return enum_value(directions, "Reverse", 1)
	end
	return enum_value(directions, "Normal", 0)
end

local function get_ownership_group_filters(cfg, is_buff)
	local spec = PitBull4_Aura:GetNativeFilterSpec(cfg and cfg.filter_new or "", is_buff)
	if spec.ownership == "mine" then return spec.filterString .. "|PLAYER", nil, spec.mode, spec end
	if spec.ownership == "other" then return spec.filterString .. "|!PLAYER", nil, spec.mode, spec end
	return spec.filterString .. "|PLAYER", spec.filterString .. "|!PLAYER", spec.mode, spec
end

local function mirror_horizontal_point(value)
	return value:gsub("LEFT", "temp"):gsub("RIGHT", "LEFT"):gsub("temp", "RIGHT")
end

local function mirror_vertical_point(value)
	return value:gsub("BOTTOM", "temp"):gsub("TOP", "BOTTOM"):gsub("temp", "TOP")
end

local function mirror_horizontal_growth(value)
	return value:gsub("left", "temp"):gsub("right", "left"):gsub("temp", "right")
end

local function mirror_vertical_growth(value)
	return value:gsub("down", "temp"):gsub("up", "down"):gsub("temp", "up")
end

local function get_effective_layout(owner_frame, cfg)
	local anchor = type(cfg and cfg.anchor) == "string" and cfg.anchor or "BOTTOMLEFT"
	local side = type(cfg and cfg.side) == "string" and cfg.side or "BOTTOM"
	local growth_name = type(cfg and cfg.growth) == "string" and cfg.growth or "right_down"
	local offset_x = tonumber(cfg and cfg.offset_x) or 0
	local offset_y = tonumber(cfg and cfg.offset_y) or 0
	local classification_db = owner_frame and owner_frame.classification_db
	local horizontal_mirror = classification_db and classification_db.horizontal_mirror and true or false
	local vertical_mirror = classification_db and classification_db.vertical_mirror and true or false

	-- Match Layout.lua exactly. Mirrored unit classifications transform the aura
	-- anchor, attachment side, growth direction, and signed offset together.
	-- The protected AuraContainer can then perform the layout without PitBull
	-- touching any assigned aura data.
	if horizontal_mirror then
		anchor = mirror_horizontal_point(anchor)
		side = mirror_horizontal_point(side)
		growth_name = mirror_horizontal_growth(growth_name)
		offset_x = -offset_x
	end
	if vertical_mirror then
		anchor = mirror_vertical_point(anchor)
		side = mirror_vertical_point(side)
		growth_name = mirror_vertical_growth(growth_name)
		offset_y = -offset_y
	end

	local growth = growth_map[growth_name]
	if not growth then
		growth_name = "right_down"
		growth = growth_map.right_down
	end
	local point = control_point[anchor .. "_" .. side] or anchor
	return {
		anchor = anchor,
		side = side,
		point = point,
		growthName = growth_name,
		growth = growth,
		offsetX = offset_x,
		offsetY = offset_y,
		horizontalMirror = horizontal_mirror,
		verticalMirror = vertical_mirror,
	}
end

local function get_maximum_line_size(owner_frame, cfg, growth)
	local width_type = cfg and cfg.width_type or "percent"
	if width_type == "fixed" then
		local value = tonumber(cfg and cfg.width)
		return value and value > 0 and value or math_huge
	end
	local percent = tonumber(cfg and cfg.width_percent) or 0.5
	if percent > 1 then
		percent = percent / 100
	end
	local side_size
	if growth.axis == "Vertical" then
		side_size = owner_frame:GetHeight()
	else
		side_size = owner_frame:GetWidth()
	end
	if not side_size or side_size <= 0 then
		return math_huge
	end
	return side_size * percent
end

local function raid_perf_suppresses(owner_frame, kind)
	return kind == "buff"
		and PitBull4_Aura.LorenzoPatch105RaidPerfActiveForUnit
		and PitBull4_Aura:LorenzoPatch105RaidPerfActiveForUnit(get_unit_token(owner_frame))
end

local function get_display_policy(owner_frame, db, kind)
	local is_buff = kind ~= "debuff"
	local show_cooldown
	local show_text
	if kind == "weapon" then
		show_cooldown = db.cooldown and db.cooldown.weapon_buffs
		show_text = db.cooldown_text and db.cooldown_text.weapon_buffs
	elseif is_buff then
		show_cooldown = db.cooldown and (db.cooldown.my_buffs or db.cooldown.other_buffs)
		show_text = db.cooldown_text and (db.cooldown_text.my_buffs or db.cooldown_text.other_buffs)
	else
		show_cooldown = db.cooldown and (db.cooldown.my_debuffs or db.cooldown.other_debuffs)
		show_text = db.cooldown_text and (db.cooldown_text.my_debuffs or db.cooldown_text.other_debuffs)
	end
	if raid_perf_suppresses(owner_frame, kind) then
		show_cooldown = false
		show_text = false
	end
	return show_cooldown and true or false, show_text and true or false
end

local function initialize_native_button(button, owner_frame, kind, ownership)
	local surface_ok, surface_err = validate_button_surface(button)
	if not surface_ok then
		error(surface_err, 0)
	end
	local db = PitBull4_Aura:GetLayoutDB(owner_frame)
	local is_buff = kind ~= "debuff"
	local cfg = is_buff and db.layout.buff or db.layout.debuff
	local size = get_ownership_icon_size(db, cfg, kind, ownership)
	local show_cooldown, show_text = get_display_policy(owner_frame, db, kind)

	button:SetSize(size, size)
	button:SetFrameLevel((owner_frame:GetFrameLevel() or 1) + 10)

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetAllPoints(button)
	if db.zoom_aura then
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	else
		icon:SetTexCoord(0, 1, 0, 1)
	end
	button:SetIcon(icon)
	if not add_native_ownership_border(button, db, ownership) then
		add_native_pitbull_border(button, db, kind)
	end

	local overlay = _G.CreateFrame("Frame", nil, button)
	overlay:SetAllPoints(button)
	overlay:SetFrameLevel(button:GetFrameLevel() + 2)

	local native_cooldown_text_active = false
	if show_cooldown or show_text then
		local cooldown = _G.CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(button)
		cooldown:SetReverse(true)
		cooldown:SetDrawEdge(false)
		if cooldown.SetDrawSwipe then
			cooldown:SetDrawSwipe(show_cooldown)
		end
		if not show_cooldown and cooldown.SetDrawBling then
			cooldown:SetDrawBling(false)
		end

		-- Keep the template's countdown hidden until the Patch 072 presentation
		-- setup succeeds. This prevents duplicate text if we need the Patch 071
		-- DurationTextBinding fallback below.
		cooldown:SetHideCountdownNumbers(true)
		cooldown.noCooldownCount = (db.suppress_occ or show_text) and true or nil

		if show_text and cooldown.GetCountdownFontString then
			if cooldown.SetMinimumCountdownDuration then
				pcall(cooldown.SetMinimumCountdownDuration, cooldown, 0)
			end
			local ok_font_string, countdown_text = pcall(cooldown.GetCountdownFontString, cooldown)
			if ok_font_string and countdown_text then
				configure_native_font_string(countdown_text, button, owner_frame, db, kind, "cooldown_text", size)
				local formatter = get_native_compact_duration_formatter()
				if formatter and cooldown.SetCountdownFormatter then
					pcall(cooldown.SetCountdownFormatter, cooldown, formatter)
				end
				cooldown:SetHideCountdownNumbers(false)
				native_cooldown_text_active = true
			end
		end

		-- CustomAuraButton owns the protected DurationObject and updates this
		-- Cooldown with SetCooldownFromDurationObject(). Do not additionally call
		-- SetUseAuraDisplayTime here: DurationObject cooldowns already carry their
		-- aura timing semantics. PitBull does not inspect, compare, or transform
		-- the aura's protected timing values.
		button:SetDurationCooldown(cooldown)
		overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	end

	local count = overlay:CreateFontString(nil, "OVERLAY")
	configure_native_font_string(count, button, owner_frame, db, kind, "count", size)
	button:SetApplicationCount(count, nil)

	if show_text and not native_cooldown_text_active then
		local duration_text = overlay:CreateFontString(nil, "OVERLAY")
		configure_native_font_string(duration_text, button, owner_frame, db, kind, "cooldown_text", size)
		-- Patch 071 fallback only. BaseTime was useful for proving the active native
		-- duration path, but live testing showed it does not match tooltip display
		-- time for all externally time-scaled auras.
		local duration_options = get_native_base_time_duration_options()
		local ok_duration = pcall(button.SetDurationText, button, duration_text, duration_options)
		if not ok_duration then
			button:SetDurationText(duration_text, nil)
		end
	end

	local dispel = button:CreateTexture(nil, "BORDER")
	dispel:SetAllPoints(button)
	button:AddDispelTypeTexture(dispel, NATIVE_DISPEL_TEXTURE_OPTIONS)

	button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0)
	button:SetHideTooltipInCombat(false)
	if db.click_through then
		button:EnableMouse(false)
	elseif get_unit_token(owner_frame) == "player" and is_buff then
		-- The protected AuraButton cancels auras and temporary weapon enchants
		-- internally without exposing the aura instance to PitBull.
		button:SetCancelAuraButtons("RightButtonUp")
	else
		button:SetCancelAuraButtons(nil)
	end
end

local function get_signature(owner_frame, db, cfg, is_buff)
	local layout = get_effective_layout(owner_frame, cfg)
	local growth = layout.growth
	local kind = is_buff and "buff" or "debuff"
	local show_cooldown, show_text = get_display_policy(owner_frame, db, kind)
	local weapon_cooldown, weapon_text = get_display_policy(owner_frame, db, "weapon")
	local icon_size = tonumber(cfg and cfg.size) or 16
	local parts = {
		kind,
		tostring(layout.point), tostring(layout.anchor), tostring(layout.side), tostring(layout.growthName),
		tostring(growth.axis), tostring(growth.horizontal), tostring(growth.vertical),
		tostring(layout.offsetX), tostring(layout.offsetY),
		tostring(layout.horizontalMirror), tostring(layout.verticalMirror),
		tostring(icon_size), tostring(cfg and cfg.my_size or 0), tostring(cfg and cfg.col_spacing or 0), tostring(cfg and cfg.row_spacing or 0),
		tostring(db.zoom_aura), tostring(db.click_through), tostring(db.suppress_occ),
		tostring(show_cooldown), tostring(show_text),
		tostring(owner_frame and get_unit_token(owner_frame) == "player"),
		tostring(is_buff and db.enabled_weapons or false),
		tostring(is_buff and weapon_cooldown or false), tostring(is_buff and weapon_text or false),
	}
	append_native_border_signature(parts, db, kind)
	local _, _, _, filter_spec = get_ownership_group_filters(cfg, is_buff)
	parts[#parts + 1] = filter_spec.signature
	if filter_spec.scope then parts[#parts + 1] = get_unit_token(owner_frame) end
	append_native_text_style_signature(parts, owner_frame, db, kind, "count", icon_size)
	if show_text then
		append_native_text_style_signature(parts, owner_frame, db, kind, "cooldown_text", icon_size)
	end
	if is_buff and get_unit_token(owner_frame) == "player" and db.enabled_weapons then
		append_native_border_signature(parts, db, "weapon")
		append_native_text_style_signature(parts, owner_frame, db, "weapon", "count", icon_size)
		if weapon_text then
			append_native_text_style_signature(parts, owner_frame, db, "weapon", "cooldown_text", icon_size)
		end
	end
	local ownership_style = db and db.ownership_style or nil
	local own_r, own_g, own_b, own_a = get_ownership_color(db, "own")
	local other_r, other_g, other_b, other_a = get_ownership_color(db, "other")
	parts[#parts + 1] = table_concat({
		"ownership", tostring(ownership_style and ownership_style.enabled or false),
		tostring(own_r), tostring(own_g), tostring(own_b), tostring(own_a),
		tostring(other_r), tostring(other_g), tostring(other_b), tostring(other_a),
		tostring(ownership_style and ownership_style.different_size or false),
		tostring(ownership_style and ownership_style.own_buff_size or 0),
		tostring(ownership_style and ownership_style.own_debuff_size or 0),
	}, ",")
	return table_concat(parts, ":")
end

local function configure_holder(holder, owner_frame, cfg)
	local layout = get_effective_layout(owner_frame, cfg)
	holder:ClearAllPoints()
	holder:SetPoint(layout.point, owner_frame, layout.anchor, layout.offsetX, layout.offsetY)
	holder:SetSize(1, 1)
	holder:SetFrameLevel((owner_frame:GetFrameLevel() or 1) + (cfg.frame_level or 9))
	return layout.point, layout
end

local function layout_options(cfg, is_buff, size_override, layout_index)
	local element_size = tonumber(size_override) or tonumber(cfg and cfg.size) or 16
	return {
		elementSpacing = tonumber(cfg and cfg.col_spacing) or 0,
		lineSpacing = tonumber(cfg and cfg.row_spacing) or 0,
		groupSpacing = 0,
		groupLineSpacing = 0,
		forceNewLine = false,
		elementWidth = element_size,
		elementHeight = element_size,
		layoutIndex = layout_index or 1,
	}
end

local function configure_container_layout(container, owner_frame, db, cfg, is_buff)
	local layout = get_effective_layout(owner_frame, cfg)
	local growth = layout.growth
	local axis = enum_value(_G.AnchorUtil.FlowLayoutAxis, growth.axis, _G.AnchorUtil.FlowLayoutAxis.Horizontal)
	local horizontal = enum_value(_G.AnchorUtil.FlowDirection, growth.horizontal, _G.AnchorUtil.FlowDirection.Right)
	local vertical = enum_value(_G.AnchorUtil.FlowDirection, growth.vertical, _G.AnchorUtil.FlowDirection.Down)
	local ok, err = call_method(container, "SetFlowLayoutAxis", axis)
	if not ok then return false, err end
	ok, err = call_method(container, "SetFlowLayoutAnchorPoint", layout.point)
	if not ok then return false, err end
	ok, err = call_method(container, "SetFlowLayoutGrowthDirection", horizontal, vertical)
	if not ok then return false, err end
	ok, err = call_method(container, "SetFlowLayoutPadding", 0, 0, 0, 0)
	if not ok then return false, err end
	ok, err = call_method(container, "SetFlowLayoutMaximumLineSize", get_maximum_line_size(owner_frame, cfg, growth))
	if not ok then return false, err end
	local kind = is_buff and "buff" or "debuff"
	local _, other_filter, _, filter_spec = get_ownership_group_filters(cfg, is_buff)
	local own_size = get_ownership_icon_size(db, cfg, kind, filter_spec.primaryOwnership)
	ok, err = call_method(container, "SetAuraGroupLayout", OWN_GROUP_KEY, layout_options(cfg, is_buff, own_size, 1))
	if not ok then return false, err end
	if other_filter then
		local other_size = get_ownership_icon_size(db, cfg, kind, "other")
		ok, err = call_method(container, "SetAuraGroupLayout", OTHER_GROUP_KEY, layout_options(cfg, is_buff, other_size, 2))
		if not ok then return false, err end
	end
	return true, nil, layout
end

local function add_weapon_enchantments(container, owner_frame, db, cfg)
	if get_unit_token(owner_frame) ~= "player" or not db.enabled_weapons then
		return false
	end
	local slots = _G.AuraContainerItemEnchantmentSlot
	if type(slots) ~= "table" or type(container.AddItemEnchantment) ~= "function" then
		return false
	end
	local options = {
		hidePermanent = false,
		initializeFrame = function(aura_button)
			initialize_native_button(aura_button, owner_frame, "weapon")
		end,
	}
	container:AddItemEnchantment(slots.MainHand, options)
	container:AddItemEnchantment(slots.OffHand, options)
	if type(_G.AuraContainerItemEnchantmentSortMethod) == "table" then
		container:SetItemEnchantmentSortMethod(
			enum_value(_G.AuraContainerItemEnchantmentSortMethod, "Slot", 0),
			enum_value(_G.AuraContainerSortDirection, "Normal", 0)
		)
	end
	if type(_G.CustomAuraContainerItemEnchantmentPlacement) == "table" then
		local item_layout = layout_options(cfg, true)
		item_layout.layoutIndex = 0
		item_layout.placement = enum_value(_G.CustomAuraContainerItemEnchantmentPlacement, "BeforeAuraGroups", 0)
		container:SetItemEnchantmentLayout(item_layout)
	end
	return true
end

local function get_group_enabled(db, is_buff)
	-- Do not write this as `is_buff and db.enabled_buffs or
	-- db.enabled_debuffs`. Lua's common and/or ternary idiom falls through to
	-- the debuff value when enabled_buffs is false. With Buffs off and Debuffs
	-- on, that made the native buff group remain enabled.
	if is_buff then
		return db.enabled_buffs
	end
	return db.enabled_debuffs
end

local function create_native_group(owner_frame, db, is_buff, state)
	local cfg = is_buff and db.layout.buff or db.layout.debuff
	local kind = is_buff and "buff" or "debuff"
	local own_filter, other_filter, filter_mode, filter_spec = get_ownership_group_filters(cfg, is_buff)
	local initially_enabled = get_group_enabled(db, is_buff) and not filter_spec.blocked
	-- Track provisional resources before API calls can reject configuration.
	-- Retirement then detaches partial containers and unregisters their scope.
	local group = { isBuff = is_buff }
	state.groups[kind] = group
	local visibility_gate, visibility_driver
	if filter_spec.scope then
		visibility_driver = PitBull4_Aura:GetNativeFilterVisibilityDriver(get_unit_token(owner_frame), filter_spec.scope)
		if not visibility_driver or type(_G.RegisterStateDriver) ~= "function" or type(_G.UnregisterStateDriver) ~= "function" then
			error("native filter secure unit scope is unavailable", 0)
		end
		visibility_gate = _G.CreateFrame("Frame", nil, owner_frame, "SecureHandlerStateTemplate")
		group.visibilityGate = visibility_gate
		visibility_gate:SetAllPoints(owner_frame)
		visibility_gate:EnableMouse(false)
		_G.RegisterStateDriver(visibility_gate, "visibility", visibility_driver)
	end
	local holder = _G.CreateFrame("Frame", nil, visibility_gate or owner_frame)
	group.holder = holder
	local point, effective_layout = configure_holder(holder, owner_frame, cfg)
	local container = _G.CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	group.container = container
	local surface_ok, surface_err = validate_container_surface(container)
	if not surface_ok then
		error(surface_err, 0)
	end
	container:SetEnabled(false)
	container:SetUnit("none")
	container:SetPoint(point, holder, point, 0, 0)
	container:SetFrameLevel(holder:GetFrameLevel())

	local own_size = get_ownership_icon_size(db, cfg, kind, filter_spec.primaryOwnership)
	local other_size = get_ownership_icon_size(db, cfg, kind, "other")
	container:AddAuraGroup(OWN_GROUP_KEY, own_filter, {
		candidateFilters = filter_spec.candidateFilters,
		maxFrameCount = is_buff and db.max_buffs or db.max_debuffs,
		initializeFrame = function(aura_button)
			initialize_native_button(aura_button, owner_frame, kind, filter_spec.primaryOwnership)
		end,
		sortMethod = get_sort_method(cfg, is_buff),
		sortDirection = get_sort_direction(cfg),
		layout = layout_options(cfg, is_buff, own_size, 1),
	})
	if other_filter then
		container:AddAuraGroup(OTHER_GROUP_KEY, other_filter, {
			candidateFilters = filter_spec.candidateFilters,
			maxFrameCount = is_buff and db.max_buffs or db.max_debuffs,
			initializeFrame = function(aura_button)
				initialize_native_button(aura_button, owner_frame, kind, "other")
			end,
			sortMethod = get_sort_method(cfg, is_buff),
			sortDirection = get_sort_direction(cfg),
			layout = layout_options(cfg, is_buff, other_size, 2),
		})
	end
	local has_weapon_enchants = is_buff and add_weapon_enchantments(container, owner_frame, db, cfg) or false
	local layout_ok, layout_err, container_layout = configure_container_layout(container, owner_frame, db, cfg, is_buff)
	if not layout_ok then
		error(layout_err, 0)
	end
	effective_layout = container_layout or effective_layout
	container:SetUnit(initially_enabled and get_unit_token(owner_frame) or "none")
	container:SetEnabled(initially_enabled and true or false)
	if initially_enabled then
		holder:Show()
		container:Show()
	else
		holder:Hide()
		container:Hide()
	end
	native_surface_validated = container_surface_validated and button_surface_validated
	native_surface_error = nil

	group.visibilityDriver = visibility_driver
	group.filterScope = filter_spec.scope
	group.filterString = own_filter
	group.otherFilterString = other_filter
	group.filterMode = filter_mode
	group.hasWeaponEnchantments = has_weapon_enchants
	group.enabled = initially_enabled and true or false
	group.effectiveLayout = effective_layout
	group.signature = get_signature(owner_frame, db, cfg, is_buff)
	return group
end

local function hide_group(group)
	if not group then
		return
	end
	-- ClearFrame and renderer fallback can detach an otherwise unchanged group.
	-- The next update must restore it instead of accepting the previous cache.
	group.configuration = nil
	if group.container then
		call_method(group.container, "SetEnabled", false)
		call_method(group.container, "SetUnit", "none")
		pcall(group.container.Hide, group.container)
	end
	if group.holder then
		pcall(group.holder.Hide, group.holder)
	end
end

local function retire_state(frame, state)
	if not state then
		return
	end
	for _, group in pairs(state.groups or {}) do
		hide_group(group)
		if group.visibilityGate then
			_G.UnregisterStateDriver(group.visibilityGate, "visibility")
			group.visibilityGate:Hide()
		end
	end
	retired_states[state] = true
	native_frames[frame] = nil
end

local function snapshot_native_states()
	local snapshot = {}
	for frame, state in pairs(native_frames) do
		snapshot[#snapshot + 1] = { frame = frame, state = state }
	end
	return snapshot
end

local function retire_all_states()
	local snapshot = snapshot_native_states()
	for index = 1, #snapshot do
		retire_state(snapshot[index].frame, snapshot[index].state)
	end
end

local function record_failure(frame, error_text)
	failed_frames[frame] = tostring(error_text or "unknown")
	local state = native_frames[frame]
	if state then
		state.lastError = failed_frames[frame]
	end
end

local function clear_failure(frame)
	failed_frames[frame] = nil
end

local function create_native_state(frame, db)
	native_generation = native_generation + 1
	local state = {
		generation = native_generation,
		groups = {},
		unit = get_unit_token(frame),
		lastError = nil,
	}
	native_frames[frame] = state
	local ok, result = pcall(function()
		create_native_group(frame, db, true, state)
		create_native_group(frame, db, false, state)
	end)
	if not ok then
		record_failure(frame, result)
		retire_state(frame, state)
		return nil, result
	end
	clear_failure(frame)
	return state
end

local function group_needs_rebuild(group, owner_frame, db, cfg, is_buff)
	return not group or group.signature ~= get_signature(owner_frame, db, cfg, is_buff)
end

local function configure_group(group, frame, db, is_buff)
	local cfg = is_buff and db.layout.buff or db.layout.debuff
	local own_filter, other_filter, filter_mode, filter_spec = get_ownership_group_filters(cfg, is_buff)
	local enabled = get_group_enabled(db, is_buff) and not filter_spec.blocked
	if not group or not group.container then
		return false, "missing-group"
	end
	local desired_unit = enabled and get_unit_token(frame) or "none"
	local max_count = is_buff and db.max_buffs or db.max_debuffs
	local sort_method = get_sort_method(cfg, is_buff)
	local sort_direction = get_sort_direction(cfg)
	local owner_width, owner_height = frame:GetWidth(), frame:GetHeight()
	local owner_level = frame:GetFrameLevel()
	local can_cache = not (_G.issecretvalue and
		(_G.issecretvalue(owner_width) or _G.issecretvalue(owner_height) or _G.issecretvalue(owner_level)))
	local cached = group.configuration
	-- The signature check has already reconciled style, filters and topology.
	-- Cache only public configuration and PitBull-owned frame geometry, never
	-- the live aura data or the protected identity behind a unit token.
	if can_cache and cached
		and cached.unit == desired_unit and cached.enabled == enabled
		and cached.maxCount == max_count and cached.sortMethod == sort_method
		and cached.sortDirection == sort_direction
		and cached.width == owner_width and cached.height == owner_height
		and cached.ownerLevel == owner_level and cached.frameLevel == cfg.frame_level
		and cached.widthType == cfg.width_type and cached.fixedWidth == cfg.width
		and cached.widthPercent == cfg.width_percent then
		native_configuration_skip_count = native_configuration_skip_count + 1
		return true
	end
	group.configuration = nil
	native_configuration_count = native_configuration_count + 1
	local _, effective_layout = configure_holder(group.holder, frame, cfg)
	if group.filterString ~= own_filter then
		local ok, err = call_method(group.container, "SetAuraGroupFilterString", OWN_GROUP_KEY, own_filter)
		if not ok then return false, err end
		group.filterString = own_filter
	end
	if group.otherFilterString and other_filter and group.otherFilterString ~= other_filter then
		local ok, err = call_method(group.container, "SetAuraGroupFilterString", OTHER_GROUP_KEY, other_filter)
		if not ok then return false, err end
		group.otherFilterString = other_filter
	end
	group.filterMode = filter_mode
	-- Keep a disabled group detached from the real unit throughout the update;
	-- assigning the unit first can briefly repopulate a previously disabled
	-- protected container before SetEnabled(false) is processed.
	local ok, err = call_method(group.container, "SetUnit", desired_unit)
	if not ok then
		return false, err
	end
	ok, err = call_method(group.container, "SetAuraGroupMaxFrameCount", OWN_GROUP_KEY, max_count)
	if not ok then return false, err end
	ok, err = call_method(group.container, "SetAuraGroupSortMethod", OWN_GROUP_KEY, sort_method, sort_direction)
	if not ok then return false, err end
	if group.otherFilterString then
		ok, err = call_method(group.container, "SetAuraGroupMaxFrameCount", OTHER_GROUP_KEY, max_count)
		if not ok then return false, err end
		ok, err = call_method(group.container, "SetAuraGroupSortMethod", OTHER_GROUP_KEY, sort_method, sort_direction)
		if not ok then return false, err end
	end
	local container_layout
	ok, err, container_layout = configure_container_layout(group.container, frame, db, cfg, is_buff)
	if not ok then
		return false, err
	end
	group.effectiveLayout = container_layout or effective_layout
	ok, err = call_method(group.container, "SetEnabled", enabled and true or false)
	if not ok then
		return false, err
	end
	if enabled then
		pcall(group.holder.Show, group.holder)
		pcall(group.container.Show, group.container)
	else
		hide_group(group)
	end
	group.enabled = enabled and true or false
	if can_cache then
		group.configuration = {
			unit = desired_unit, enabled = enabled, maxCount = max_count,
			sortMethod = sort_method, sortDirection = sort_direction,
			width = owner_width, height = owner_height, ownerLevel = owner_level,
			frameLevel = cfg.frame_level, widthType = cfg.width_type,
			fixedWidth = cfg.width, widthPercent = cfg.width_percent,
		}
	end
	return true
end

function PitBull4_Aura:Lorenzo121NativeRendererAvailable()
	local state = get_native_capabilities()
	return state and state.is121OrNewer and state.auraContainerAddonLoaded and native_methods_ready(state)
end

function PitBull4_Aura:Lorenzo121NativeRendererActive()
	return native_enabled and self:Lorenzo121NativeRendererAvailable()
end

function PitBull4_Aura:Lorenzo121GetNativeEnabled()
	return native_enabled
end

function PitBull4_Aura:Lorenzo121SetNativeEnabled(enabled)
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		PitBull4:RunOnLeaveCombat(self.Lorenzo121SetNativeEnabled, self, enabled)
		return
	end
	local was_enabled = native_enabled
	native_enabled = enabled and true or false
	if native_enabled ~= was_enabled then
		reset_surface_validation()
	end
	if not native_enabled then
		retire_all_states()
		for frame in pairs(failed_frames) do
			failed_frames[frame] = nil
		end
	end
	if self.Lorenzo121 then
		self.Lorenzo121.nativeRendererRequested = native_enabled
		self.Lorenzo121.legacyAuraPath = not native_enabled
	end
	self:UpdateAll()
end

function PitBull4_Aura:Lorenzo121RebuildNativeContainers()
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		PitBull4:RunOnLeaveCombat(self.Lorenzo121RebuildNativeContainers, self)
		return
	end
	reset_surface_validation()
	retire_all_states()
	for frame in pairs(failed_frames) do
		failed_frames[frame] = nil
	end
	self:UpdateAll()
end

function PitBull4_Aura:Lorenzo121NativeFiltersChanged()
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		PitBull4:RunOnLeaveCombat(self.Lorenzo121NativeFiltersChanged, self)
		return
	end
	-- An edited filter may repair a previously failed native configuration.
	for frame in pairs(failed_frames) do failed_frames[frame] = nil end
	self:UpdateAll()
end

function PitBull4_Aura:Lorenzo121HasNativeFailures()
	return next(failed_frames) ~= nil
end

function PitBull4_Aura:Lorenzo121NativeHandlesUnitAura(_unit)
	return self:Lorenzo121NativeRendererActive() and not self:Lorenzo121HasNativeFailures()
end

function PitBull4_Aura:Lorenzo121ShouldRunLegacyAuraTicker()
	return not self:Lorenzo121NativeRendererActive() or self:Lorenzo121HasNativeFailures()
end

local function refresh_dynamic_group(group)
	if not group or not group.enabled or not group.container then
		return false
	end
	local container = group.container
	dynamic_refresh_count = dynamic_refresh_count + 1

	-- Blizzard's managed AuraContainer marks its parse dirty through
	-- UpdateAllAuras(). In addon context this is the only combat-safe nudge.
	-- Outside combat, a Hide/Show bounce executes the intrinsic OnShow path in
	-- Blizzard's secure partition and forces an immediate re-parse of the unit.
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		local method_ok, method = get_object_method(container, "UpdateAllAuras")
		if method_ok then
			local ok = pcall(method, container)
			if ok then
				dynamic_refresh_mark_count = dynamic_refresh_mark_count + 1
				return true
			end
		end
		return false
	end

	local hide_ok = pcall(container.Hide, container)
	local show_ok = pcall(container.Show, container)
	if hide_ok and show_ok then
		dynamic_refresh_bounce_count = dynamic_refresh_bounce_count + 1
		return true
	end
	return false
end

function PitBull4_Aura:Lorenzo121RefreshDynamicNativeUnit(unit)
	if not self:Lorenzo121NativeRendererActive() or type(unit) ~= "string" then
		return
	end
	for frame, state in pairs(native_frames) do
		-- frame.unit is PitBull-owned public configuration state; do not query or
		-- compare the protected identity behind the unit token.
		if frame and frame.unit == unit and state and state.groups then
			refresh_dynamic_group(state.groups.buff)
			refresh_dynamic_group(state.groups.debuff)
		end
	end
end

function PitBull4_Aura:Lorenzo121UpdateNativeFrame(frame)
	local db = self:GetLayoutDB(frame)
	local state = native_frames[frame]
	-- All native filter/layout/secure scope mutations wait until combat ends.
	-- PLAYER_REGEN_ENABLED already calls UpdateAll and reconciles saved settings.
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		return true
	end
	if state then
		local buff_rebuild = group_needs_rebuild(state.groups.buff, frame, db, db.layout.buff, true)
		local debuff_rebuild = group_needs_rebuild(state.groups.debuff, frame, db, db.layout.debuff, false)
		if buff_rebuild or debuff_rebuild then
			retire_state(frame, state)
			state = nil
		end
	end
	if not state then
		local created, err = create_native_state(frame, db)
		if not created then
			return false, err
		end
		state = created
	end
	state.unit = get_unit_token(frame)
	local ok_buff, err_buff = configure_group(state.groups.buff, frame, db, true)
	local ok_debuff, err_debuff = configure_group(state.groups.debuff, frame, db, false)
	if not ok_buff or not ok_debuff then
		local err = err_buff or err_debuff or "native-config-failed"
		record_failure(frame, err)
		retire_state(frame, state)
		return false, err
	end
	clear_failure(frame)
	return true
end

local function is_boss_frame(frame)
	local unit = get_unit_token(frame)
	return unit:match("^boss%d+") ~= nil
end

local function should_prepare_boss_frame(frame)
	local classification = frame.classification_db
	return is_boss_frame(frame) and classification and classification.enabled
		and frame.layout and PitBull4_Aura:IsEnabled()
		and PitBull4_Aura:GetLayoutDB(frame).enabled and should_use_native(frame)
end

function PitBull4_Aura:Lorenzo121ClearNativeFrame(frame)
	if _G.InCombatLockdown and _G.InCombatLockdown() then return end
	-- An absent boss is still bound to its configured public unit token. Keep
	-- its native containers ready; the hidden owner gates their visibility and
	-- Blizzard's intrinsic OnShow registers aura events when that boss appears.
	if should_prepare_boss_frame(frame) then
		self:Lorenzo121UpdateNativeFrame(frame)
		return
	end
	local state = native_frames[frame]
	if not state then
		return
	end
	for _, group in pairs(state.groups or {}) do
		hide_group(group)
	end
end

function PitBull4_Aura:Lorenzo121PrepareNativeBossFrames()
	if _G.InCombatLockdown and _G.InCombatLockdown() then return end
	if type(PitBull4.IterateFrames) ~= "function" then return end
	for frame in PitBull4:IterateFrames(true) do
		if is_boss_frame(frame) then
			if should_prepare_boss_frame(frame) then
				self:Lorenzo121UpdateNativeFrame(frame)
			else
				self:Lorenzo121ClearNativeFrame(frame)
			end
		end
	end
end

local boss_prepare_pending = false
function PitBull4_Aura:Lorenzo121QueueBossPreparation()
	if boss_prepare_pending then return end
	if _G.InCombatLockdown and _G.InCombatLockdown() then return end
	boss_prepare_pending = true
	_G.C_Timer.After(0, function()
		boss_prepare_pending = false
		-- Frame creation/profile callbacks can run before the final unit binding.
		-- Recheck the current frames and current profile, never a saved DB table.
		PitBull4_Aura:Lorenzo121PrepareNativeBossFrames()
	end)
end

function PitBull4_Aura:OnFrameLayoutChanged(frame)
	local header = frame.header
	local classification = frame.classification_db
	local unit = classification and classification.unit
	if (header and header.super_unit_group == "boss")
		or (type(unit) == "string" and unit:match("^boss%d+")) then
		self:Lorenzo121QueueBossPreparation()
	end
end

function PitBull4_Aura:Lorenzo121RetireDisabledNativeFrames()
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		PitBull4:RunOnLeaveCombat(self.Lorenzo121RetireDisabledNativeFrames, self)
		return
	end
	if not self:IsEnabled() then
		retire_all_states()
	end
end

local legacy_update_all = PitBull4_Aura.UpdateAll
function PitBull4_Aura:UpdateAll(...)
	legacy_update_all(self, ...)
	self:Lorenzo121PrepareNativeBossFrames()
end

local legacy_on_enable = PitBull4_Aura.OnEnable
function PitBull4_Aura:OnEnable(...)
	legacy_on_enable(self, ...)
	self:Lorenzo121QueueBossPreparation()
end

local legacy_on_disable = PitBull4_Aura.OnDisable
function PitBull4_Aura:OnDisable(...)
	legacy_on_disable(self, ...)
	self:Lorenzo121RetireDisabledNativeFrames()
end

PitBull4_Aura.OnProfileChanged_funcs[#PitBull4_Aura.OnProfileChanged_funcs + 1] =
	PitBull4_Aura.Lorenzo121QueueBossPreparation

local function safe_frame_name(frame)
	local ok, name = pcall(frame.GetName, frame)
	return ok and name or "<unnamed>"
end

function PitBull4_Aura:Lorenzo121GetNativeStatusLines()
	local frame_count, container_count, approximation_count, failure_count, weapon_count = 0, 0, 0, 0, 0
	local lines = {}
	for frame, state in pairs(native_frames) do
		frame_count = frame_count + 1
		for _, group in pairs(state.groups or {}) do
			container_count = container_count + 1
			if group.hasWeaponEnchantments then
				weapon_count = weapon_count + 1
			end
			if group.filterMode and group.filterMode:match("^approximate:") then
				approximation_count = approximation_count + 1
			end
		end
		if #lines < 12 then
			local buff_layout = state.groups.buff and state.groups.buff.effectiveLayout
			local debuff_layout = state.groups.debuff and state.groups.debuff.effectiveLayout
			lines[#lines + 1] = "12.1 native frame=" .. safe_frame_name(frame)
				.. " unit=" .. tostring(frame.unit)
				.. " generation=" .. tostring(state.generation)
				.. " buffFilter=" .. tostring(state.groups.buff and state.groups.buff.filterMode)
				.. " debuffFilter=" .. tostring(state.groups.debuff and state.groups.debuff.filterMode)
				.. " buffScope=" .. tostring(state.groups.buff and state.groups.buff.filterScope or "all")
				.. " debuffScope=" .. tostring(state.groups.debuff and state.groups.debuff.filterScope or "all")
				.. " buffEnabled=" .. tostring(state.groups.buff and state.groups.buff.enabled)
				.. " debuffEnabled=" .. tostring(state.groups.debuff and state.groups.debuff.enabled)
				.. " mirrorH=" .. tostring(buff_layout and buff_layout.horizontalMirror or false)
				.. " mirrorV=" .. tostring(buff_layout and buff_layout.verticalMirror or false)
				.. " buffLayout=" .. tostring(buff_layout and buff_layout.point) .. "/" .. tostring(buff_layout and buff_layout.growthName)
				.. " debuffLayout=" .. tostring(debuff_layout and debuff_layout.point) .. "/" .. tostring(debuff_layout and debuff_layout.growthName)
		end
	end
	for frame, err in pairs(failed_frames) do
		failure_count = failure_count + 1
		if #lines < 16 then
			lines[#lines + 1] = "12.1 native failure frame=" .. safe_frame_name(frame) .. " error=" .. tostring(err)
		end
	end
	table_insert(lines, 1, "12.1 native renderer requested=" .. tostring(native_enabled)
		.. " available=" .. tostring(self:Lorenzo121NativeRendererAvailable())
		.. " runtimeSurfaceValidated=" .. tostring(native_surface_validated)
		.. " surfaceError=" .. tostring(native_surface_error)
		.. " textStyle=pitbull-capped"
		.. " borderStyle=pitbull-ownership-player-notplayer"
		.. " mirrorStyle=pitbull-effective"
		.. " sortStyle=pitbull-native-aliases"
		.. " frames=" .. tostring(frame_count)
		.. " containers=" .. tostring(container_count)
		.. " weaponContainers=" .. tostring(weapon_count)
		.. " approximateFilters=" .. tostring(approximation_count)
		.. " dynamicRefresh=" .. tostring(dynamic_refresh_count)
		.. " dynamicRefreshBounce=" .. tostring(dynamic_refresh_bounce_count)
		.. " dynamicRefreshMark=" .. tostring(dynamic_refresh_mark_count)
		.. " configurationPasses=" .. tostring(native_configuration_count)
		.. " configurationSkips=" .. tostring(native_configuration_skip_count)
		.. " failures=" .. tostring(failure_count))
	return lines
end

-- Replace only the Aura module's renderer entry points. Config Mode, older
-- clients, disabled native mode, and per-frame API failures use Patch 114.
local legacy_update_frame = PitBull4_Aura.UpdateFrame
local legacy_clear_frame = PitBull4_Aura.ClearFrame

function PitBull4_Aura:UpdateFrame(frame, ...)
	if frame.force_show and is_boss_frame(frame) then
		self:Lorenzo121ClearNativeFrame(frame)
	end
	if should_use_native(frame) then
		local ok, err = self:Lorenzo121UpdateNativeFrame(frame)
		if ok then
			-- Remove pooled legacy buttons once so both renderers cannot overlap.
			if self.ClearAuras then
				self:ClearAuras(frame)
			end
			if frame.aura_highlight then
				frame.aura_highlight = frame.aura_highlight:Delete()
			end
			return
		end
		record_failure(frame, err)
	end
	-- A native selection must never fall back to an unfiltered live legacy row.
	-- Config Mode remains a static layout preview; no filter match is inferred.
	if not frame.force_show and PitBull4_Aura:LayoutUsesNativeFilters(self:GetLayoutDB(frame)) then
		self:Lorenzo121ClearNativeFrame(frame)
		return legacy_clear_frame(self, frame, ...)
	end
	return legacy_update_frame(self, frame, ...)
end

function PitBull4_Aura:ClearFrame(frame, ...)
	self:Lorenzo121ClearNativeFrame(frame)
	return legacy_clear_frame(self, frame, ...)
end

if PitBull4_Aura.Lorenzo121 then
	PitBull4_Aura.Lorenzo121.nativeRendererRequested = native_enabled
	PitBull4_Aura.Lorenzo121.managedAuraPrototype = true
	PitBull4_Aura.Lorenzo121.legacyAuraPath = false
end
