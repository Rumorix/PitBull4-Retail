-- Patch 099: compile public settings for Blizzard's managed AuraContainer.
-- No assigned aura, identity, ownership, duration, or reaction is read here.
local PitBull4 = _G.PitBull4
local Aura = PitBull4:GetModule("Aura")
local L = PitBull4.L

local categories = {
	all = { name = "All auras", display_when = "both" },
	dispellable = { name = "Player-dispellable auras", display_when = "both", token = "RAID_PLAYER_DISPELLABLE" },
	defensive = { name = "Big defensive buffs", display_when = "buff", token = "BIG_DEFENSIVE" },
	stealable = { name = "Stealable buffs", display_when = "buff", candidate = "isStealable" },
	["boss-role"] = { name = "Boss or role debuffs", display_when = "debuff", candidate = "isBossOrRoleAura" },
	priority = { name = "Priority debuffs", display_when = "debuff", candidate = "isPriorityAura" },
	["crowd-control"] = { name = "Crowd control debuffs", display_when = "debuff", token = "CROWD_CONTROL" },
}
local presets = {
	["native:all"] = { name = "All auras", category = "all", ownership = "all", display_when = "both" },
	["native:mine"] = { name = "Own auras only", category = "all", ownership = "mine", display_when = "both" },
	["native:other"] = { name = "Other casters' auras only", category = "all", ownership = "other", display_when = "both" },
}
for category, data in pairs(categories) do
	if category ~= "all" then
		presets["native:" .. category] = { name = data.name, category = category, ownership = "all", display_when = data.display_when }
	end
end

function Aura:IsNativeFilterID(id)
	return type(id) == "string" and id:sub(1, 7) == "native:"
end

function Aura:GetNativeFilterDefinition(id)
	if presets[id] then return presets[id], true end
	local global = self.db and self.db.profile.global
	return global and global.native_filters and global.native_filters[id], false
end

function Aura:GetNativeFilterCategoryValues(display_when)
	local values = {}
	for id, data in pairs(categories) do
		if data.display_when == "both" or data.display_when == display_when then values[id] = L[data.name] end
	end
	return values
end

function Aura:ParseNativeSpellIDs(text)
	if text == nil or text == "" then return nil, "" end
	if type(text) ~= "string" or #text > 10000 or text:find("[^%d%s,;]") then
		return nil, nil, L["Enter positive spell IDs separated by spaces, commas, or semicolons."]
	end
	local ids, ordered = {}, {}
	for token in text:gmatch("%d+") do
		local id = tonumber(token)
		if not id or id < 1 or id > 2147483647 or id ~= math.floor(id) then
			return nil, nil, L["Enter positive spell IDs separated by spaces, commas, or semicolons."]
		end
		if not ids[id] then
			ids[id] = true
			ordered[#ordered + 1] = id
			if #ordered > 250 then return nil, nil, L["Use at most 250 spell IDs per list."] end
		end
	end
	if #ordered == 0 then return nil, "" end
	table.sort(ordered)
	for i = 1, #ordered do ordered[i] = tostring(ordered[i]) end
	return ids, table.concat(ordered, ", ")
end

function Aura:GetNativeFilterValues(display_when, selected)
	local values = { [""] = L["None"] }
	local function add(id, definition, built_in)
		if not display_when or definition.display_when == "both" or definition.display_when == display_when then
			values[id] = built_in and L[definition.name] or definition.name
		end
	end
	for id, definition in pairs(presets) do add(id, definition, true) end
	local global = self.db and self.db.profile.global
	for id, definition in pairs(global and global.native_filters or {}) do
		if type(definition) == "table" and type(definition.name) == "string" then add(id, definition, false) end
	end
	if selected and not values[selected] then
		local legacy = self.filters and self.filters[selected]
		local name = legacy and legacy.display_name or selected
		local label = self:IsNativeFilterID(selected) and L["Unavailable filter: %s"] or L["Legacy filter: %s"]
		values[selected] = label:format(name)
	end
	return values
end

function Aura:GetNativeFilterSpec(id, is_buff)
	local base = is_buff and "HELPFUL" or "HARMFUL"
	local spec = { filterString = base, ownership = "all", primaryOwnership = "own", mode = "native-builtin" }
	if not self:IsNativeFilterID(id) then
		if id == "!C" or id == "!E" then
			spec.ownership, spec.mode = "mine", "native-mine"
		elseif id and id ~= "" and id ~= "!B" and id ~= "!D" and id ~= "!N" and id ~= "!P" and id ~= "!Q" then
			spec.mode = "approximate:" .. tostring(id)
		end
		spec.signature = spec.mode .. ":" .. spec.ownership
		return spec
	end
	local definition = self:GetNativeFilterDefinition(id)
	local kind = is_buff and "buff" or "debuff"
	local category = type(definition) == "table" and categories[definition.category]
	local function blocked(reason)
		spec.blocked = true
		spec.mode = "native-" .. reason .. ":" .. id
		spec.signature = spec.mode
		return spec
	end
	if type(definition) ~= "table" then return blocked("missing") end
	if not category or (definition.display_when ~= "both" and definition.display_when ~= kind)
		or (category.display_when ~= "both" and category.display_when ~= kind) then return blocked("incompatible") end
	if definition.ownership ~= "all" and definition.ownership ~= "mine" and definition.ownership ~= "other" then return blocked("invalid") end
	local include, include_text, include_error = self:ParseNativeSpellIDs(definition.include_spell_ids)
	local exclude, exclude_text, exclude_error = self:ParseNativeSpellIDs(definition.exclude_spell_ids)
	for spell_id in pairs(include or {}) do
		if exclude and exclude[spell_id] then return blocked("invalid") end
	end
	local duration = definition.max_duration or 0
	if include_error or exclude_error or type(duration) ~= "number" or duration ~= duration
		or duration < 0 or duration > 86400 then return blocked("invalid") end
	local candidates = {}
	if category.token then spec.filterString = base .. "|" .. category.token end
	if category.candidate then candidates[category.candidate] = true end
	if include then candidates.includeSpellIDs = include end
	if exclude then candidates.excludeSpellIDs = exclude end
	if duration > 0 then candidates.maxDuration = duration end
	if next(candidates) then spec.candidateFilters = candidates end
	-- Identity matching is restricted by Blizzard's unit domain. A secure macro
	-- visibility gate prevents an ignored identity list from displaying all auras.
	if include or exclude then spec.scope = is_buff and "help" or "harm" end
	spec.ownership = definition.ownership
	spec.primaryOwnership = definition.ownership == "other" and "other" or "own"
	spec.mode = "native-filter:" .. id
	spec.signature = table.concat({ id, definition.category, definition.ownership, definition.display_when,
		include_text, exclude_text, tostring(duration), spec.scope or "all" }, ":")
	return spec
end

function Aura:GetNativeFilterVisibilityDriver(unit, scope)
	if (scope ~= "help" and scope ~= "harm") or type(unit) ~= "string" or not unit:match("^[a-z][a-z0-9]*$") then return nil end
	return "[@" .. unit .. ",exists," .. scope .. "] show; hide"
end

function Aura:LayoutUsesNativeFilters(db)
	return db and db.layout and ((db.layout.buff and self:IsNativeFilterID(db.layout.buff.filter_new))
		or (db.layout.debuff and self:IsNativeFilterID(db.layout.debuff.filter_new)))
end
