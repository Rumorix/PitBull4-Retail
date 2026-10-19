-- Run from the repository root: lua5.1 Tests/group_header_raid_whitelist.lua
-- Executes production functions with public roster/frame stubs. Marked secret
-- sentinels test sanitization; WoW restrictions, taint and combat need in-game tests.
local source_file = assert(io.open("GroupHeader.lua", "rb"))
local source = source_file:read("*a")
source_file:close()
source = source:gsub("\r\n", "\n")

local function section(first, last)
	local start = assert(source:find(first, 1, true), first)
	local finish = assert(source:find(last, start + #first, true), last)
	return source:sub(start, finish - 1)
end

local grouping_source = section("local GROUPING_ORDER = {}", "local function position_label")
local builder_source = section("local function build_raid_name_list_without_main_tanks", "function GroupHeader:RefreshGroup")
local attributes_source = section('\tif exclude_main_tanks then\n\t\tself:SetAttribute("sortMethod"', '\t-- self:SetAttribute("template"')
local build_chunk = assert(loadstring(grouping_source .. builder_source .. "\nreturn build_raid_name_list_without_main_tanks", "@GroupHeader.lua:whitelist"))
local attributes = assert(loadstring("return function(self, exclude_main_tanks, sort_method, sort_direction, group_by)\n" .. attributes_source .. "\nend", "@GroupHeader.lua:attributes"))()

local checks = 0
local function check(condition, message)
	checks = checks + 1
	assert(condition, message)
end

local secrets = {}
local function secret()
	local value = setmetatable({}, {
		__index = function() error("restricted value indexed") end,
		__lt = function() error("restricted value ordered") end,
		__le = function() error("restricted value ordered") end,
		__concat = function() error("restricted value concatenated") end,
		__tostring = function() error("restricted value formatted") end,
	})
	secrets[value] = true
	return value
end

local function run(roster, settings, tanks)
	local records, comparator
	local environment = setmetatable({
		MAX_RAID_MEMBERS = 40,
		NUM_RAID_GROUPS = 8,
		PitBull4 = { ClassOrder = { "MAGE", "WARRIOR" }, RoleOrder = { "TANK", "HEALER", "DAMAGER" } },
		issecretvalue = function(value) return secrets[value] == true end,
		GetNumGroupMembers = function() return #roster end,
		GetRaidRosterInfo = function(index)
			local row = roster[index]
			return row.name, nil, row.subgroup, nil, nil, row.class_name, nil, nil, nil, row.role, nil, row.assigned_role
		end,
		table = setmetatable({ sort = function(values, compare)
			records, comparator = values, compare
			for _, record in ipairs(values) do
				for _, value in pairs(record) do
					check(not secrets[value], "restricted roster field reached sorting")
				end
			end
			-- Check before table.sort: an invalid comparator may otherwise overrun
			-- the sort's partition bounds before the assertion can explain the defect.
			for _, a in ipairs(values) do
				check(not compare(a, a), "comparator is not irreflexive")
				for _, b in ipairs(values) do
					check(not (compare(a, b) and compare(b, a)), "comparator is not asymmetric")
				end
			end
			table.sort(values, compare)
		end }, { __index = table }),
	}, { __index = _G })
	-- Prevent the harness from inheriting an integration from its host globals.
	environment.oRA3 = false
	if tanks then
		environment.oRA3 = { GetSortedTanks = function() return tanks end }
	end
	environment._G = environment
	setfenv(build_chunk, environment)
	local result = build_chunk()(settings or {})
	return result, records, comparator
end

local roster = {
	{ name = "Zed-Realm", subgroup = 2, class_name = "WARRIOR", role = "MAINASSIST", assigned_role = "HEALER" },
	{ name = "Alpha-Realm", subgroup = 1, class_name = "MAGE", role = "NONE", assigned_role = "DAMAGER" },
	{ name = "Beta-Realm", subgroup = 1, class_name = "WARRIOR", role = "NONE", assigned_role = "TANK" },
	{ name = "Tank-Realm", subgroup = 2, class_name = "WARRIOR", role = "MAINTANK", assigned_role = "TANK" },
	{ name = "Beta-Realm", subgroup = 1, class_name = "WARRIOR", role = "NONE", assigned_role = "TANK" },
}

local expected_indices = {
	NONE = { INDEX = { 1, 2, 3, 5 }, NAME = { 2, 3, 5, 1 } },
	GROUP = { INDEX = { 2, 3, 5, 1 }, NAME = { 2, 3, 5, 1 } },
	CLASS = { INDEX = { 2, 1, 3, 5 }, NAME = { 2, 3, 5, 1 } },
	ROLE = { INDEX = { 1, 2, 3, 5 }, NAME = { 2, 3, 5, 1 } },
	ASSIGNEDROLE = { INDEX = { 3, 5, 1, 2 }, NAME = { 3, 5, 1, 2 } },
}

for _, grouping in ipairs({ "NONE", "GROUP", "CLASS", "ROLE", "ASSIGNEDROLE" }) do
	for _, method in ipairs({ "INDEX", "NAME" }) do
		for _, direction in ipairs({ "ASC", "DESC" }) do
			local settings = { sort_method = method, sort_direction = direction }
			if grouping ~= "NONE" then settings.group_by = grouping end
			local result, records, compare = run(roster, settings)
			local expected = expected_indices[grouping][method]
			local names = {}
			for i = 1, #expected do
				local position = i
				if direction == "DESC" then position = #expected - i + 1 end
				check(records[i].index == expected[position], "group/name/index ordering or tie break changed")
				names[i] = roster[expected[position]].name
			end
			check(result == table.concat(names, ","), "whitelist output changed")
			for _, a in ipairs(records) do
				check(not compare(a, a), "comparator is not irreflexive")
				for _, b in ipairs(records) do
					check(not (compare(a, b) and compare(b, a)), "comparator is not asymmetric")
					for _, c in ipairs(records) do
						check(not (compare(a, b) and compare(b, c)) or compare(a, c), "comparator is not transitive")
					end
				end
			end
		end
	end
end

for _, field in ipairs({ "name", "subgroup", "class_name", "role", "assigned_role" }) do
	local row = { name = "Public-Realm", subgroup = 1, class_name = "MAGE", role = "NONE", assigned_role = "HEALER" }
	row[field] = secret()
	for _, grouping in ipairs({ "GROUP", "CLASS", "ROLE", "ASSIGNEDROLE" }) do
		local result, records = run({ row }, { group_by = grouping, sort_method = "NAME" })
		if field == "name" then
			check(result == "" and #records == 0, "restricted name was not omitted")
		else
			check(result == "Public-Realm" and records[1][field] == nil, "restricted field was not sanitized")
		end
		-- Exercise filter-key lookup as well as grouping and sorting.
		local filtered = run({ row }, { group_filter = "1,MAGE,NONE,HEALER", group_by = grouping })
		check(filtered == (field == "name" and "" or "Public-Realm"), "public filter alternatives were lost")
	end
end

check(run(roster, { group_filter = "1" }) == "Alpha-Realm,Beta-Realm,Beta-Realm", "numeric subgroup filter changed")
check(run(roster, { group_filter = "MAGE" }) == "Alpha-Realm", "class filter changed")
check(run(roster, { group_filter = "MAINASSIST" }) == "Zed-Realm", "role filter changed")
check(run(roster, { group_filter = "HEALER" }) == "Zed-Realm", "assigned role filter changed")
check(run(roster, {}, { "Zed", secret(), "Alpha-Realm" }) == "Beta-Realm,Beta-Realm", "oRA3 tank matching changed")
check(run({}) == nil, "empty roster behavior changed")
check(run({ roster[4] }) == "", "all-tanks roster must produce an empty whitelist")

for _, count in ipairs({ 1, 2, 40 }) do
	local members = {}
	for i = 1, count do
		members[i] = { name = string.format("Member%02d", i), subgroup = 1, class_name = "MAGE" }
	end
	for _, direction in ipairs({ "ASC", "DESC" }) do
		local _, records = run(members, { sort_method = "NAME", sort_direction = direction })
		check(#records == count, "roster size changed")
		for i, record in ipairs(records) do
			local expected = i
			if direction == "DESC" then expected = count - i + 1 end
			check(record.index == expected, "large roster order changed")
		end
	end
end

for _, grouping in ipairs({ "GROUP", "CLASS", "ROLE", "ASSIGNEDROLE" }) do
	local saved = { group_by = grouping }
	local live = { groupBy = "OLD" }
	local header = { SetAttribute = function(_, key, value) live[key] = value end }
	attributes(header, true, "NAME", "DESC", saved.group_by)
	check(live.groupBy == nil and live.sortMethod == "NAMELIST" and live.sortDir == "ASC", "exclusion attributes incorrect")
	check(saved.group_by == grouping, "saved grouping preference changed")
	attributes(header, false, "NAME", "DESC", saved.group_by)
	check(live.groupBy == grouping and live.sortMethod == "NAME" and live.sortDir == "DESC", "normal grouping not restored")
end

print(string.format("PASS: %d assertions (ordering, asymmetry, transitivity, secrecy, filters, roster sizes, groupBy)", checks))
