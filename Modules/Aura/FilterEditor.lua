-- Patch 099: restore the Aura editor with declarative native settings.
-- Legacy global.filters remain intact; native definitions belong to the profile.
local PitBull4 = _G.PitBull4
local Aura = PitBull4:GetModule("Aura")
local L = PitBull4.L
local current_filter = "native:mine"

local function selected()
	local definition, built_in = Aura:GetNativeFilterDefinition(current_filter)
	if type(definition) ~= "table" then
		current_filter = "native:mine"
		definition, built_in = Aura:GetNativeFilterDefinition(current_filter)
	end
	return definition, built_in
end

local function refresh()
	Aura:Lorenzo121NativeFiltersChanged()
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange("PitBull4") end
end

local function trim(value)
	return value:match("^%s*(.-)%s*$")
end

local function validate_name(info, value)
	value = trim(value)
	if value == "" or #value > 80 or value:find("[%c|]") then return L["Use a unique filter name of 1 to 80 characters."] end
	for _, definition in pairs(Aura.db.profile.global.native_filters) do
		if type(definition) == "table" and type(definition.name) == "string" and definition.name:lower() == value:lower() then
			return L["Use a unique filter name of 1 to 80 characters."]
		end
	end
	return true
end

local function validate_ids(info, value)
	local ids, _, err = Aura:ParseNativeSpellIDs(value)
	if err then return err end
	local definition = selected()
	local opposite = info[#info] == "include_spell_ids" and definition.exclude_spell_ids or definition.include_spell_ids
	local other = Aura:ParseNativeSpellIDs(opposite)
	for id in pairs(ids or {}) do
		if other and other[id] then return L["A spell ID cannot appear in both lists."] end
	end
	return true
end

local function get(info)
	local key = info[#info]
	local value = selected()[key]
	if key == "max_duration" then return value or 0 end
	if key == "include_spell_ids" or key == "exclude_spell_ids" then return value or "" end
	return value
end

local function set(info, value)
	local definition, built_in = selected()
	if built_in or (_G.InCombatLockdown and _G.InCombatLockdown()) then return end
	local key = info[#info]
	if key == "include_spell_ids" or key == "exclude_spell_ids" then
		if validate_ids(info, value) ~= true then return end
		local _, canonical = Aura:ParseNativeSpellIDs(value)
		value = canonical
	end
	definition[key] = value
	if key == "display_when" and not Aura:GetNativeFilterCategoryValues(value)[definition.category] then definition.category = "all" end
	refresh()
end

local function read_only()
	local _, built_in = selected()
	return built_in or (_G.InCombatLockdown and _G.InCombatLockdown())
end

Aura.OnProfileChanged_funcs[#Aura.OnProfileChanged_funcs + 1] = function()
	current_filter = "native:mine"
end

function Aura:GetFilterEditor()
	return "filter_editor", {
		type = "group", name = L["Filter Editor"], order = 110,
		disabled = function() return _G.InCombatLockdown and _G.InCombatLockdown() end,
		args = {
			instructions = { type = "description", order = 1, fontSize = "medium", name = L["Create a named filter from a preset, then select it under Layout editor -> Aura -> Filters. Filters are saved in the current profile."] },
			limits = { type = "description", order = 2, name = L["Spell ID lists show buffs only on friendly units and debuffs only on hostile units. On other units that filtered aura row is hidden. Protected friendly debuffs can use Blizzard categories, but not arbitrary spell ID lists."] },
			runtime = { type = "description", order = 2.5, name = L["Native filters need the enabled 12.1 aura renderer. A missing or incompatible native filter hides its row. Config Mode previews placement, not filter results."] },
			current_filter = { type = "select", name = L["Current filter"], order = 3, width = "double",
				get = function() selected(); return current_filter end,
				set = function(info, value) current_filter = value end,
				values = function() local values = Aura:GetNativeFilterValues(); values[""] = nil; return values end,
			},
			new_filter = { type = "input", name = L["New filter"], order = 4, width = "double",
				desc = L["Copy the selected preset or filter under a new name."], get = function() return "" end, validate = validate_name,
				set = function(info, value)
					if validate_name(info, value) ~= true or (_G.InCombatLockdown and _G.InCombatLockdown()) then return end
					local source = selected()
					local global = Aura.db.profile.global
					local sequence = tonumber(global.next_native_filter_id) or 0
					if sequence < 0 or sequence >= 2147483647 or sequence ~= math.floor(sequence) then sequence = 0 end
					repeat sequence = sequence + 1 until not global.native_filters["native:user:" .. sequence]
					global.next_native_filter_id = sequence
					current_filter = "native:user:" .. sequence
					global.native_filters[current_filter] = {
						name = trim(value), category = source.category, ownership = source.ownership, display_when = source.display_when,
						include_spell_ids = source.include_spell_ids or "", exclude_spell_ids = source.exclude_spell_ids or "", max_duration = source.max_duration or 0,
					}
					refresh()
				end,
			},
			delete_filter = { type = "execute", name = L["Delete filter"], order = 5, disabled = read_only,
				confirm = function() return L["Delete this filter? Layouts using it will switch to None."] end,
				func = function()
					if read_only() then return end
					for _, layout in pairs(Aura.db.profile.layouts) do
						for _, kind in ipairs({ "buff", "debuff" }) do
							local cfg = layout.layout and layout.layout[kind]
							if cfg and cfg.filter_new == current_filter then cfg.filter_new = "" end
						end
					end
					Aura.db.profile.global.native_filters[current_filter] = nil
					current_filter = "native:mine"
					refresh()
				end,
			},
			preset_note = { type = "description", order = 6, hidden = function() local _, built_in = selected(); return not built_in end,
				name = L["Presets are read-only. Enter a new filter name to create an editable copy."],
			},
			settings = { type = "group", name = L["Filter settings"], order = 7, inline = true, disabled = read_only, get = get, set = set,
				args = {
					display_when = { type = "select", name = L["Aura Type"], order = 1, values = { buff = L["Buff"], debuff = L["Debuff"], both = L["Buffs and debuffs"] } },
					ownership = { type = "select", name = L["Caster selection"], order = 2, values = { all = L["All casters"], mine = L["Own auras only"], other = L["Other casters' auras only"] } },
					category = { type = "select", name = L["Blizzard category"], order = 3, width = "double", values = function() return Aura:GetNativeFilterCategoryValues(selected().display_when) end },
					include_spell_ids = { type = "input", name = L["Include spell IDs"], order = 4, width = "full", multiline = 3, validate = validate_ids,
						desc = L["Leave empty to allow all spell IDs. Use aura spell IDs, which may differ from the spellbook ability."],
					},
					exclude_spell_ids = { type = "input", name = L["Exclude spell IDs"], order = 5, width = "full", multiline = 3, validate = validate_ids },
					max_duration = { type = "range", name = L["Maximum aura duration"], order = 6, min = 0, max = 86400, softMax = 600, step = 1,
						desc = L["Maximum total duration in seconds. Zero disables this limit; this is not a remaining-time rule."],
					},
				},
			},
		},
	}
end
