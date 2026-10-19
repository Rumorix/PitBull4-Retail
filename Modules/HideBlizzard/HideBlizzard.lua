
local PitBull4 = _G.PitBull4
local L = PitBull4.L

-----------------------------------------------------------------------------
-- luacheck: no global

local PitBull4_HideBlizzard = PitBull4:NewModule("HideBlizzard")

PitBull4_HideBlizzard:SetModuleType("custom")
PitBull4_HideBlizzard:SetName(L["Hide Blizzard frames"])
PitBull4_HideBlizzard:SetDescription(L["Hide Blizzard frames that are no longer needed."])
PitBull4_HideBlizzard:SetDefaults({}, {
	player = true,
	runebar = true,
	party = true,
	raid = false,
	target = true,
	focus = true,
	castbar = true,
	aura = false,
	altpower = false,
	boss = false,
	arena = false,
})

function PitBull4_HideBlizzard:OnEnable()
	self:RegisterEvent("ADDON_LOADED")
	self:UpdateFrames()
end

function PitBull4_HideBlizzard:OnDisable()
	self:UpdateFrames()
end

function PitBull4_HideBlizzard:OnProfileChanged()
	self:UpdateFrames()
end

function PitBull4_HideBlizzard:ADDON_LOADED(_, addon)
	if addon == "Blizzard_ArenaUI" or addon == "Blizzard_CompactRaidFrames"
		or addon == "Blizzard_UnitFrame" or addon == "Blizzard_EditMode"
		or addon == "Blizzard_BuffFrame" then
		self:UpdateFrames()
		if self.LorenzoQueueHiddenFrameRefresh then
			self:LorenzoQueueHiddenFrameRefresh()
		end
	end
end

local hiders = {}
local currently_hidden = {}
local reload_needed = false

function PitBull4_HideBlizzard:UpdateFrames()
	for name in pairs(hiders) do
		if self:IsEnabled() and self.db.profile.global[name] then
			if not currently_hidden[name] then
				currently_hidden[name] = not hiders[name](self)
			end
		elseif currently_hidden[name] and not reload_needed then
			reload_needed = true
			self:Print(L["Showing hidden frames requires reloading the UI."])
			LibStub("AceConfigRegistry-3.0"):NotifyChange("PitBull4")
		end
	end
end
PitBull4_HideBlizzard.UpdateFrames = PitBull4:OutOfCombatWrapper(PitBull4_HideBlizzard.UpdateFrames)

-----------------------------------------------------------------------------

local noop = function() end
local hide_frame = PitBull4:OutOfCombatWrapper(function(self) self:Hide() end)

local hidden_frame = CreateFrame("Frame")
hidden_frame:Hide()

-----------------------------------------------------------------------------

local function simple_hook_frames(...)
	for i = 1, select("#", ...) do
		local frame = select(i, ...)
		if frame then
			frame:UnregisterAllEvents()
			frame:HookScript("OnShow", hide_frame)
			frame:Hide()
		elseif PitBull4.DEBUG then
			geterrorhandler()(("PitBull4_HideBlizzard: Invalid simple frame at index %d"):format(i))
		end
	end
end

local function hook_frames(raw, ...)
	for i = 1, select("#", ...) do
		local frame = select(i, ...)
		if frame then
			UnregisterUnitWatch(frame)
			frame:UnregisterAllEvents()
			frame:Hide()

			if frame.manabar then frame.manabar:UnregisterAllEvents() end
			if frame.healthbar then frame.healthbar:UnregisterAllEvents() end
			if frame.spellbar then frame.spellbar:UnregisterAllEvents() end
			if frame.powerBarAlt then frame.powerBarAlt:UnregisterAllEvents() end

			if raw then
				frame.Show = noop
			else
				frame:SetParent(hidden_frame)
				frame:HookScript("OnShow", hide_frame)
			end
		elseif PitBull4.DEBUG then
			geterrorhandler()(("PitBull4_HideBlizzard: Invalid frame at index %d"):format(i))
		end
	end
end

-----------------------------------------------------------------------------

local retail_passive_visibility = _G.WOW_PROJECT_MAINLINE ~= nil
	and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE
local hide_retail_frames

if retail_passive_visibility then
	-- Patch 102: every Retail hider preserves Blizzard's frame lifecycle. Hooks
	-- only enqueue work, including SetAlpha/Show: Edit Mode hides selections
	-- inside secureexecuterange before broadcasting its Exit callback.
	-- Keep all bookkeeping outside Blizzard frame/pool tables. Selection
	-- subtrees stay outside traversal and hook installation. Patch 107 only
	-- changes parent-alpha inheritance and input on requested Player/Party
	-- mover roots, on this addon's next-frame timer outside combat.
	local roots = {
		player = { "PlayerFrame", "PetFrame" },
		runebar = { "RuneFrame", "WarlockPowerFrame", "MonkHarmonyBarFrame", "PaladinPowerBarFrame", "MageArcaneChargesFrame", "EssencePlayerFrame" },
		party = { "PartyFrame", "CompactPartyFrame" },
		raid = { "CompactRaidFrameManager", "CompactRaidFrameContainer" },
		target = { "TargetFrame", "ComboFrame", "TargetFrameToT" },
		focus = { "FocusFrame", "FocusFrameToT" },
		castbar = { "PlayerCastingBarFrame", "PetCastingBarFrame" },
		aura = { "BuffFrame" },
		altpower = { "PlayerPowerBarAlt" },
		boss = { "BossTargetFrameContainer" },
		arena = { "ArenaEnemyFramesContainer", "ArenaEnemyPrepFramesContainer", "ArenaEnemyMatchFramesContainer", "ArenaPrepFrames", "ArenaEnemyFrames", "CompactArenaFrame" },
	}
	local requested = {}
	for kind in pairs(roots) do requested[kind] = false end
	local hooked_frames = setmetatable({}, { __mode = "k" })
	local hooked_regions = setmetatable({}, { __mode = "k" })
	local party_objects = setmetatable({}, { __mode = "k" })
	local hooked_pools = setmetatable({}, { __mode = "k" })
	local edit_selections = setmetatable({}, { __mode = "k" })
	local muted_movers = setmetatable({}, { __mode = "k" })
	local failed_movers = setmetatable({}, { __mode = "k" })
	local alpha_busy = setmetatable({}, { __mode = "k" })
	local alpha_pending = setmetatable({}, { __mode = "k" })
	local tree_pending = setmetatable({}, { __mode = "k" })
	local input_pending = setmetatable({}, { __mode = "k" })
	local input_busy = setmetatable({}, { __mode = "k" })
	local parent_alpha_busy = setmetatable({}, { __mode = "k" })
	local refresh_counts = { full = 0, trees = 0, inputs = 0, frames = 0, regions = 0, movers = 0, partyUnhooked = 0 }
	local timer_pending, discovery_pending, combat_pending, edit_callbacks_installed = false, false, false, false
	local party_alpha_pending = false
	local arena_generator_hooked = false
	local any_requested = false
	local queue_refresh, schedule_refresh
	local function suppression_requested()
		return any_requested
	end

	local function visit_roots(kind, callback)
		local found = false
		local function visit(frame)
			if frame then
				found = true
				callback(frame)
			end
		end
		for _, name in ipairs(roots[kind]) do visit(_G[name]) end
		if kind == "player" then
			visit(_G.PlayerFrameAlternateManaBar or _G.AlternatePowerBar)
		elseif kind == "castbar" and not _G.PlayerCastingBarFrame then
			visit(_G.CastingBarFrame)
		elseif kind == "aura" then
			visit(_G.TemporaryEnchantFrame or _G.DebuffFrame)
		elseif kind == "boss" then
			for i = 1, (_G.MAX_BOSS_FRAMES or 5) do visit(_G["Boss" .. i .. "TargetFrame"]) end
		end
		return found
	end

	local function force_transparent(frame)
		if alpha_busy[frame] or edit_selections[frame] or (frame.IsForbidden and frame:IsForbidden()) then
			return
		end
		-- Do not read/compare GetAlpha() or the SetAlpha() hook's argument. Both
		-- can contain protected values; the visual override is always a constant.
		if hooked_regions[frame] then
			-- A known visual region must inherit its invisible parent even while
			-- native animation alpha changes without calling SetAlpha in Lua.
			-- Only public constants are written; no inheritance flag is read.
			parent_alpha_busy[frame] = true
			frame:SetIgnoreParentAlpha(false)
			parent_alpha_busy[frame] = nil
		end
		alpha_busy[frame] = true
		frame:SetAlpha(0)
		alpha_busy[frame] = nil
	end

	local function queue_alpha(frame)
		if alpha_busy[frame] or edit_selections[frame] then return end
		-- No frame API call here: this can run inside a secure Edit Mode iterator.
		-- The original SetAlpha argument is neither read nor retained.
		alpha_pending[frame] = true
		schedule_refresh(false)
	end
	local function drain_alpha_pending(seen)
		for frame in pairs(alpha_pending) do
			alpha_pending[frame] = nil
			if not seen or not seen[frame] then force_transparent(frame) end
		end
	end
	local function drain_party_alpha(seen)
		if not party_alpha_pending then return end
		party_alpha_pending = false
		-- Party members/bars/regions are unhooked. Lifecycle events reconcile the
		-- cached public objects once, including known Ready Check visuals in
		-- combat. Tree discovery and input changes still wait for combat end.
		for object in pairs(party_objects) do
			if not seen or not seen[object] then force_transparent(object) end
		end
	end

	local input_methods = { "EnableMouse", "EnableMouseWheel", "SetMouseClickEnabled", "SetMouseMotionEnabled" }
	local visibility_methods = { "Show", "SetShown" }
	local function queue_tree(frame)
		-- Patch 105: a local Show/SetShown does not invalidate every hidden root.
		-- Only retain the public object reference; no frame API runs in the hook.
		tree_pending[frame] = true
		schedule_refresh(false)
	end
	local function queue_input(frame)
		if input_busy[frame] then return end
		input_pending[frame] = true
		schedule_refresh(false)
	end
	local function suppress_input(frame)
		if edit_selections[frame] or (frame.IsForbidden and frame:IsForbidden()) then return end
		input_busy[frame] = true
		for _, method in ipairs(input_methods) do
			if frame[method] then frame[method](frame, false) end
		end
		input_busy[frame] = nil
	end
	local function suppress_region(region, seen, party_tree)
		if seen[region] then return end
		if not region.SetAlpha or not region.SetIgnoreParentAlpha
			or (region.IsForbidden and region:IsForbidden()) then return end
		seen[region] = true
		if party_tree then party_objects[region] = true end
		refresh_counts.regions = refresh_counts.regions + 1
		-- GetChildren does not include textures/font strings. In particular,
		-- native Ready Check regions can bypass their transparent parent.
		if not hooked_regions[region] then
			hooked_regions[region] = true
			if party_tree then
				refresh_counts.partyUnhooked = refresh_counts.partyUnhooked + 1
			else
				hooksecurefunc(region, "SetAlpha", function() queue_alpha(region) end)
				if region.Show then
					hooksecurefunc(region, "Show", function() queue_alpha(region) end)
				end
				hooksecurefunc(region, "SetIgnoreParentAlpha", function()
					if not parent_alpha_busy[region] then
						queue_alpha(region)
					end
				end)
			end
		end
		-- Preserve native Show/Hide and animations. Inheriting the zero-alpha
		-- parent also hides native animation alpha which bypasses SetAlpha hooks.
		force_transparent(region)
	end

	local function suppress_requested_mover(frame, selection)
		if not selection or failed_movers[selection] then return end
		local requested_mover = (requested.player and frame == _G.PlayerFrame)
			or (requested.party and (frame == _G.PartyFrame or frame == _G.CompactPartyFrame))
		if not requested_mover then return end
		if (selection.IsForbidden and selection:IsForbidden()) or not selection.SetIgnoreParentAlpha then
			return
		end
		-- Blizzard's native Selection template ignores the parent's zero alpha.
		-- Its ordinary highlight/selection/exit logic does not reset this flag.
		-- Write only a constant inheritance flag: retain its own alpha, shown
		-- state, geometry, scripts and native Selection fields/methods. Never
		-- traverse descendants or run selection APIs inside a native hook.
		local ok = pcall(selection.SetIgnoreParentAlpha, selection, false)
		if not ok then
			failed_movers[selection] = true
			return
		end
		-- A transparent mover must not consume clicks over the PitBull ghost.
		-- All work here is reached only by out-of-combat tree reconciliation.
		for _, method in ipairs(input_methods) do
			if selection[method] and not pcall(selection[method], selection, false) then
				failed_movers[selection] = true
			end
		end
		muted_movers[selection] = true
		refresh_counts.movers = refresh_counts.movers + 1
	end

	local function suppress_tree(frame, seen, party_tree)
		if seen[frame] or edit_selections[frame] or (frame.IsForbidden and frame:IsForbidden()) then
			return
		end
		seen[frame] = true
		local party_root = requested.party and (frame == _G.PartyFrame or frame == _G.CompactPartyFrame)
		party_tree = party_tree or party_root or party_objects[frame]
		if party_tree then party_objects[frame] = true end
		refresh_counts.frames = refresh_counts.frames + 1
		local selection = frame.Selection
		-- Remember superseded selections too: Blizzard may retain an old helper
		-- as a child after installing its replacement. Neither subtree is ours.
		if selection then edit_selections[selection] = true end
		if not hooked_frames[frame] then
			hooked_frames[frame] = true
			-- P002: leave native Party member/bar method lookup untouched. Their
			-- Show path runs immediately before UnitFrameHealthBar_Update, and
			-- pooled Setup stores native OnEvent callbacks for later roster events.
			-- The parent stays transparent; existing roster/ready/Edit Mode
			-- events discover new children without hooking their native methods.
			if party_tree and not party_root then
				refresh_counts.partyUnhooked = refresh_counts.partyUnhooked + 1
			else
				hooksecurefunc(frame, "SetAlpha", function() queue_alpha(frame) end)
				-- Patch 104: an accessible frame can still forbid script bindings.
				-- Observe visibility methods without querying or hooking OnShow.
				-- Ignore their arguments and perform all frame work on the next frame.
				for _, method in ipairs(visibility_methods) do
					if frame[method] then
						hooksecurefunc(frame, method, function()
							queue_alpha(frame)
							queue_tree(frame)
						end)
					end
				end
				for _, method in ipairs(input_methods) do
					if frame[method] then
						hooksecurefunc(frame, method, function()
							queue_input(frame)
						end)
					end
				end
			end
		end
		force_transparent(frame)
		-- Transparent protected buttons must not consume clicks or hover input.
		-- Mouse configuration and hook installation are strictly out of combat.
		suppress_input(frame)
		suppress_requested_mover(frame, selection)
		if frame.GetRegions then
			local regions = { frame:GetRegions() }
			for _, region in ipairs(regions) do suppress_region(region, seen, party_tree) end
		end
		local children = { frame:GetChildren() }
		for _, child in ipairs(children) do
			if child ~= selection then suppress_tree(child, seen, party_tree) end
		end
	end

	local function install_lifecycle_callbacks()
		PitBull4_HideBlizzard:RegisterEvent("PLAYER_ENTERING_WORLD", "LorenzoQueueHiddenFrameRefresh")
		PitBull4_HideBlizzard:RegisterEvent("GROUP_ROSTER_UPDATE", "LorenzoQueueHiddenFrameRefresh")
		PitBull4_HideBlizzard:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "LorenzoQueueHiddenFrameRefresh")
		PitBull4_HideBlizzard:RegisterEvent("PLAYER_TALENT_UPDATE", "LorenzoQueueHiddenFrameRefresh")
		PitBull4_HideBlizzard:RegisterEvent("READY_CHECK", "LorenzoQueueHiddenFrameRefresh")
		PitBull4_HideBlizzard:RegisterEvent("READY_CHECK_CONFIRM", "LorenzoQueueHiddenFrameRefresh")
		PitBull4_HideBlizzard:RegisterEvent("READY_CHECK_FINISHED", "LorenzoQueueHiddenFrameRefresh")
		if not edit_callbacks_installed and _G.EventRegistry then
			edit_callbacks_installed = true
			-- Only enqueue work: do not configure pooled members inside Blizzard's
			-- Edit Mode enter/exit/reset stack. The next-frame pass sees the new tree.
			_G.EventRegistry:RegisterCallback("EditMode.Enter", queue_refresh, PitBull4_HideBlizzard)
			_G.EventRegistry:RegisterCallback("EditMode.Exit", queue_refresh, PitBull4_HideBlizzard)
		end
	end

	local function refresh_hidden_frames(discover)
		if not suppression_requested() then return end
		-- This function is called only by our next-frame timer. Constant alpha
		-- writes and region alpha inheritance on already hooked objects work in
		-- combat; input, discovery and new hooks remain deferred until combat ends.
		-- Alpha animations do not require rescanning the entire native frame tree.
		if not discover and not next(tree_pending) and not next(input_pending) then
			drain_alpha_pending()
			drain_party_alpha()
			return
		end
		if InCombatLockdown() then
			drain_alpha_pending()
			drain_party_alpha()
			combat_pending = true
			PitBull4_HideBlizzard:RegisterEvent("PLAYER_REGEN_ENABLED", "LorenzoQueueHiddenFrameRefresh")
			return
		end
		combat_pending = false
		PitBull4_HideBlizzard:UnregisterEvent("PLAYER_REGEN_ENABLED")
		local seen = {}
		if discover then
			refresh_counts.full = refresh_counts.full + 1
			install_lifecycle_callbacks()
			for kind in pairs(roots) do
				if requested[kind] then
					visit_roots(kind, function(frame) suppress_tree(frame, seen) end)
				end
			end
			-- Party members/pools/RefreshMembers remain unhooked. Existing
			-- container hooks and lifecycle events discover replacement members.
			if requested.arena then
				local arena = _G.CompactArenaFrame
				if arena and arena.UpdateVisibility and not hooked_pools[arena] then
					hooked_pools[arena] = true
					hooksecurefunc(arena, "UpdateVisibility", queue_refresh)
				end
				if not arena_generator_hooked and _G.CompactArenaFrame_Generate then
					arena_generator_hooked = true
					hooksecurefunc("CompactArenaFrame_Generate", queue_refresh)
				end
			end
		end
		for frame in pairs(tree_pending) do
			tree_pending[frame] = nil
			if not seen[frame] then
				refresh_counts.trees = refresh_counts.trees + 1
				suppress_tree(frame, seen)
			end
		end
		for frame in pairs(input_pending) do
			input_pending[frame] = nil
			if not seen[frame] then
				refresh_counts.inputs = refresh_counts.inputs + 1
				suppress_input(frame)
			end
		end
		-- A tree pass already restored alpha on its frames and visual regions.
		-- Consume overlapping animation notifications without writing it twice.
		drain_alpha_pending(seen)
		drain_party_alpha(seen)
	end

	schedule_refresh = function(discover)
		if not suppression_requested() then return end
		if discover then discovery_pending = true end
		if timer_pending then return end
		timer_pending = true
		C_Timer.After(0, function()
			local discover_now = discovery_pending
			discovery_pending = false
			timer_pending = false
			refresh_hidden_frames(discover_now)
		end)
	end
	queue_refresh = function()
		if requested.party then party_alpha_pending = true end
		schedule_refresh(true)
	end

	function PitBull4_HideBlizzard:LorenzoQueueHiddenFrameRefresh()
		queue_refresh()
	end

	function PitBull4_HideBlizzard:LorenzoRefreshHiddenFrames()
		queue_refresh()
	end

	hide_retail_frames = function(kind)
		-- Like the inherited hiders, this remains in effect until Reload UI when
		-- disabled. Do not restore frame input midway through a protected rebuild.
		requested[kind] = true
		any_requested = true
		queue_refresh()
		if visit_roots(kind, noop) then return end
		return true -- Retry when Blizzard's load-on-demand frames become available.
	end

	function PitBull4_HideBlizzard:Lorenzo121StatusLine()
		local mover_count, mover_failures = 0, 0
		for _ in pairs(muted_movers) do mover_count = mover_count + 1 end
		for _ in pairs(failed_movers) do mover_failures = mover_failures + 1 end
		local party_taint = "unavailable"
		if type(_G.issecurevariable) == "function" then
			local fields = {}
			local function inspect(object, key, label)
				local ok, secure, source = pcall(_G.issecurevariable, object, key)
				if not ok then
					fields[#fields + 1] = label .. ":query-failed"
				elseif secure == false then
					local public_source = type(source) == "string"
						and (not _G.issecretvalue or not _G.issecretvalue(source))
					fields[#fields + 1] = label .. ":" .. (public_source and source or "unknown")
				end
			end
			-- On-demand only: inspect taint metadata, never values/scripts or
			-- native health getters. Useful when a different addon/load path
			-- contaminated the callback/unit field despite unhooked Party objects.
			inspect(_G, "UnitFrame_Update", "UnitFrame_Update")
			inspect(_G, "UnitFrameHealthBar_Update", "UnitFrameHealthBar_Update")
			inspect(_G, "UnitHealthMax", "UnitHealthMax")
			local party = _G.PartyFrame
			if party then
				for i = 1, 4 do
					local key = "MemberFrame" .. i
					local member = party[key]
					if member then
						inspect(member, "OnEvent", key .. ".OnEvent")
						inspect(member, "unit", key .. ".unit")
						local health = member.HealthBarContainer and member.HealthBarContainer.HealthBar or member.HealthBar
						if health then
							inspect(health, "unit", key .. ".HealthBar.unit")
							inspect(health, "unitFrame", key .. ".HealthBar.unitFrame")
						end
					end
				end
			end
			party_taint = #fields > 0 and table.concat(fields, ",") or "none-observed"
		end
		return "12.1 hideBlizzard frameVisibility=passive-alpha preservedBlizzardLifecycle=yes hookWork=next-frame editSelections=shallow-player-party moverHooks=none selectionDescendants=untouched visualRegions=alpha-and-parent showHooks=methods refreshScope=dirty-objects"
			.. " partyMethodHooks=container-only partyPoolHooks=none partyObjectsUnhooked=" .. refresh_counts.partyUnhooked
			.. " partyTaintFields=" .. party_taint
			.. " mutedMovers=" .. mover_count .. " moverFailures=" .. mover_failures .. " moverPasses=" .. refresh_counts.movers
			.. " player=" .. (requested.player and "hidden" or "default")
			.. " classResource=" .. (requested.runebar and "hidden" or "default")
			.. " party=" .. (requested.party and "hidden" or "default")
			.. " raid=" .. (requested.raid and "hidden" or "default")
			.. " target=" .. (requested.target and "hidden" or "default")
			.. " focus=" .. (requested.focus and "hidden" or "default")
			.. " castbar=" .. (requested.castbar and "hidden" or "default")
			.. " aura=" .. (requested.aura and "hidden" or "default")
			.. " altpower=" .. (requested.altpower and "hidden" or "default")
			.. " boss=" .. (requested.boss and "hidden" or "default")
			.. " arena=" .. (requested.arena and "hidden" or "default")
			.. " nextFramePending=" .. (timer_pending and "yes" or "no")
			.. " discoveryPending=" .. ((discovery_pending or next(tree_pending)) and "yes" or "no")
			.. " inputPending=" .. (next(input_pending) and "yes" or "no")
			.. " combatPending=" .. (combat_pending and "yes" or "no")
			.. " fullPasses=" .. refresh_counts.full
			.. " treePasses=" .. refresh_counts.trees
			.. " inputPasses=" .. refresh_counts.inputs
			.. " walkedFrames=" .. refresh_counts.frames
			.. " walkedRegions=" .. refresh_counts.regions
	end
end

-----------------------------------------------------------------------------

function hiders:player()
	if retail_passive_visibility then
		return hide_retail_frames("player")
	end
	if ClassicExpansionAtLeast(LE_EXPANSION_CATACLYSM) then
		hook_frames(false, PlayerFrame, PlayerFrameAlternateManaBar or AlternatePowerBar)
	else
		hook_frames(false, PlayerFrame)
	end
	-- BuffFrame_Update()
	-- BuffFrame needs an inital update, but calling directly will taint things
	PlayerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	PlayerFrame:RegisterEvent("UNIT_ENTERING_VEHICLE")
	PlayerFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
	PlayerFrame:RegisterEvent("UNIT_EXITING_VEHICLE")
	PlayerFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
	PlayerFrame:SetMovable(true)
	PlayerFrame:SetUserPlaced(true)
	PlayerFrame:SetDontSavePosition(true)

	hook_frames(false, PetFrame) -- this should be parented to PlayerFrame, but people say it has started showing again?
end

if retail_passive_visibility or ClassicExpansionAtLeast(LE_EXPANSION_CATACLYSM) then
	function hiders:runebar()
		if retail_passive_visibility then
			return hide_retail_frames("runebar")
		end
		simple_hook_frames(RuneFrame, WarlockPowerFrame, MonkHarmonyBarFrame, PaladinPowerBarFrame, MageArcaneChargesFrame, EssencePlayerFrame)
	end
end

function hiders:party()
	if retail_passive_visibility then
		return hide_retail_frames("party")
	end
	if PartyFrame then
		hook_frames(false, PartyFrame)
		for memberFrame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
			if memberFrame.HealthBarContainer then -- XXX wow_tww
				hook_frames(false, memberFrame, memberFrame.HealthBarContainer.HealthBar, memberFrame.ManaBar)
			else
				hook_frames(false, memberFrame, memberFrame.HealthBar, memberFrame.ManaBar)
			end
		end
		PartyFrame.PartyMemberFramePool:ReleaseAll()
	else
		for i = 1, MAX_PARTY_MEMBERS do
			local name = "PartyMemberFrame" .. i
			hook_frames(false, _G[name], _G[name .. "HealthBar"], _G[name .. "ManaBar"])
		end
	end

	UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")

	if CompactPartyFrame then
		hook_frames(false, CompactPartyFrame)
	end
end

if retail_passive_visibility then
	function hiders:raid()
		return hide_retail_frames("raid")
	end
else
	local raid_hide_pending = false
	local raid_manager_quarantined = false
	local raid_hide_hooks_installed = false
	local hide_raid

	local function raid_hiding_enabled()
		return PitBull4_HideBlizzard:IsEnabled()
			and PitBull4_HideBlizzard.db.profile.global.raid
	end

	local function queue_raid_hide_after_combat()
		if raid_hide_pending then
			return
		end

		-- Blizzard may try to re-show/re-expand CompactRaidFrameManager from
		-- roster/world/Edit Mode update paths while combat lockdown is active.
		-- Once Patch 094 has quarantined the manager under hidden_frame it stays
		-- effectively invisible even if Blizzard calls Show() in combat; this
		-- retry only restores the manager's explicit hidden/settings state later.
		raid_hide_pending = true
		PitBull4_HideBlizzard:RegisterEvent(
			"PLAYER_REGEN_ENABLED",
			"LorenzoHideRaidManagerAfterCombat"
		)
	end

	function PitBull4_HideBlizzard:LorenzoHideRaidManagerAfterCombat()
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if not raid_hide_pending then
			return
		end

		raid_hide_pending = false
		if raid_hiding_enabled() then
			hide_raid()
		end
	end

	function PitBull4_HideBlizzard:LorenzoReassertRaidManagerHide()
		if raid_hiding_enabled() then
			hide_raid()
		end
	end

	hide_raid = function()
		if not CompactRaidFrameManager then
			return false
		end
		if InCombatLockdown() then
			queue_raid_hide_after_combat()
			return raid_manager_quarantined
		end
		if raid_hide_pending then
			-- A safe out-of-combat callback can arrive just before the regen event.
			-- Consume the queued retry here so the manager is still hidden once.
			raid_hide_pending = false
			PitBull4_HideBlizzard:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end

		-- Patch 094: do not merely react to Blizzard showing the manager. Parent
		-- the complete manager under PitBull's permanently hidden frame. Blizzard
		-- can still run its normal Show/Expand/update code, but the manager and its
		-- children remain effectively invisible even if that happens in combat.
		-- Disabling Hide Blizzard already requires a UI reload, which restores the
		-- original XML parent cleanly.
		CompactRaidFrameManager:UnregisterAllEvents()
		if CompactRaidFrameContainer then
			CompactRaidFrameContainer:UnregisterAllEvents()
		end
		CompactRaidFrameManager:Hide()
		if CompactRaidFrameManager:GetParent() ~= hidden_frame then
			CompactRaidFrameManager:SetParent(hidden_frame)
		end
		raid_manager_quarantined = CompactRaidFrameManager:GetParent() == hidden_frame

		local raid_shown = CompactRaidFrameManager_GetSetting("IsShown")
		if raid_shown and raid_shown ~= "0" then
			CompactRaidFrameManager_SetSetting("IsShown", "0")
		end
		return true
	end

	local function install_raid_hide_hooks()
		if raid_hide_hooks_installed then
			return
		end
		raid_hide_hooks_installed = true

		-- UpdateShown calls Show() whenever Blizzard considers ally frames active.
		hooksecurefunc("CompactRaidFrameManager_UpdateShown", function()
			if raid_hiding_enabled() then
				hide_raid()
			end
		end)

		-- The manager can also be explicitly expanded without UpdateShown. Keep
		-- the quarantine authoritative across that path as well.
		if _G.CompactRaidFrameManager_Expand then
			hooksecurefunc("CompactRaidFrameManager_Expand", function()
				if raid_hiding_enabled() then
					hide_raid()
				end
			end)
		end

		-- CUF/Edit Mode/profile code may set IsShown back to a truthy value. The
		-- callback runs after Blizzard's setter and restores PitBull's preference.
		if _G.CompactRaidFrameManager_SetSetting then
			hooksecurefunc("CompactRaidFrameManager_SetSetting", function(setting_name, value)
				if setting_name == "IsShown" and value ~= "0" and value ~= 0 and value ~= false and raid_hiding_enabled() then
					hide_raid()
				end
			end)
		end
	end

	function hiders:raid()
		if not CompactRaidFrameManager then
			-- Blizzard_CompactRaidFrames isn't loaded
			return true
		end

		install_raid_hide_hooks()
		hide_raid()
		if CompactRaidFrameContainer then
			CompactRaidFrameContainer:HookScript("OnShow", hide_raid)
		end
		CompactRaidFrameManager:HookScript("OnShow", hide_raid)

		-- Reassert after the two main lifecycle transitions that commonly rebuild
		-- Blizzard group UI state. These calls are harmless once quarantined and
		-- queue themselves if combat lockdown is active.
		PitBull4_HideBlizzard:RegisterEvent("PLAYER_ENTERING_WORLD", "LorenzoReassertRaidManagerHide")
		PitBull4_HideBlizzard:RegisterEvent("GROUP_ROSTER_UPDATE", "LorenzoReassertRaidManagerHide")
	end

	function PitBull4_HideBlizzard:Lorenzo121StatusLine()
		return "12.1 hideBlizzard raidManagerQuarantine="
			.. (raid_manager_quarantined and "yes" or "no")
			.. " hiddenParent=" .. ((CompactRaidFrameManager and CompactRaidFrameManager:GetParent() == hidden_frame) and "yes" or "no")
			.. " retry=PLAYER_REGEN_ENABLED pending=" .. (raid_hide_pending and "yes" or "no")
	end
end

function hiders:target()
	if retail_passive_visibility then return hide_retail_frames("target") end
	hook_frames(false, TargetFrame, ComboFrame, TargetFrameToT)
end

function hiders:focus()
	if retail_passive_visibility then return hide_retail_frames("focus") end
	hook_frames(false, FocusFrame, FocusFrameToT)
end

function hiders:castbar()
	if retail_passive_visibility then return hide_retail_frames("castbar") end
	hook_frames(true, PlayerCastingBarFrame or CastingBarFrame, PetCastingBarFrame)
end

function hiders:aura()
	if retail_passive_visibility then return hide_retail_frames("aura") end
	hook_frames(false, BuffFrame, TemporaryEnchantFrame or DebuffFrame)
end

function hiders:altpower()
	if retail_passive_visibility then return hide_retail_frames("altpower") end
	hook_frames(false, PlayerPowerBarAlt)
end

function hiders:boss()
	if retail_passive_visibility then return hide_retail_frames("boss") end
	for i = 1, MAX_BOSS_FRAMES do
		local name = "Boss" .. i .. "TargetFrame"
		if _G[name].TargetFrameContent then -- retail
			if _G[name].TargetFrameContent.TargetFrameContentMain.HealthBarsContainer then -- XXX wow_tww
				hook_frames(false, _G[name], _G[name].TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar, _G[name].TargetFrameContent.TargetFrameContentMain.ManaBar)
			else
				hook_frames(false, _G[name], _G[name].TargetFrameContent.TargetFrameContentMain.HealthBar, _G[name].TargetFrameContent.TargetFrameContentMain.ManaBar)
			end
		else -- classic
			hook_frames(false, _G[name], _G[name .. "HealthBar"], _G[name .. "ManaBar"])
		end
	end
end

do
	-- XXX untested
	local function hide_arena()
		hooksecurefunc(CompactArenaFrame, "UpdateVisibility", function(self)
			if InCombatLockdown() then return end
			if PitBull4_HideBlizzard:IsEnabled() and PitBull4_HideBlizzard.db.profile.global.arena then
				self:SetParent(hidden_frame)
			end
		end)
	end

	function hiders:arena()
		if retail_passive_visibility then return hide_retail_frames("arena") end
		if not ArenaEnemyFramesContainer and not ArenaEnemyFrames then
			return true
		end

		if ArenaEnemyFramesContainer then -- retail bg flag carriers
			hook_frames(true, ArenaEnemyFramesContainer, ArenaEnemyPrepFramesContainer, ArenaEnemyMatchFramesContainer)
		elseif ArenaEnemyFrames then -- classic
			hook_frames(false, ArenaPrepFrames, ArenaEnemyFrames)
		end

		-- retail
		if CompactArenaFrame then
			hide_arena()
		elseif CompactArenaFrame_Generate then
			hooksecurefunc(CompactArenaFrame_Generate, hide_arena)
		end
	end
end

-----------------------------------------------------------------------------

PitBull4_HideBlizzard:SetGlobalOptionsFunction(function(self)
	local function get(info)
		local id = info[#info]
		return self.db.profile.global[id]
	end
	local function set(info, value)
		local id = info[#info]
		self.db.profile.global[id] = value
		self:UpdateFrames()
	end
	local function hidden(info)
		return not self:IsEnabled()
	end

	return 'player', {
		type = 'toggle',
		name = L["Player"],
		desc = L["Hide the standard player frame."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'runebar', {
		type = 'toggle',
		name = L["Class power bar"],
		desc = L["Hides the class resource bar attached to your player frame."],
		get = get,
		set = set,
		disabled = not (retail_passive_visibility or ClassicExpansionAtLeast(LE_EXPANSION_CATACLYSM)),
		hidden = hidden,
	}, 'party', {
		type = 'toggle',
		name = L["Party"],
		desc = L["Hide the standard party frames."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'raid', {
		type = 'toggle',
		name = L["Raid"],
		desc = L["Hide the standard raid manager and raid frames and party frames (when set to use raid style in blizzard interface options)."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'target', {
		type = 'toggle',
		name = L["Target"],
		desc = L["Hide the standard target frame."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'focus', {
		type = 'toggle',
		name = L["Focus"],
		desc = L["Hide the standard focus frame."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'castbar', {
		type = 'toggle',
		name = L["Cast bar"],
		desc = L["Hides the standard cast bar."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'aura', {
		type = 'toggle',
		name = L["Buffs/debuffs"],
		desc = L["Hides the standard buff/debuff frame in the top-right corner of the screen."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'altpower', {
		type = 'toggle',
		name = L["Alternate power"],
		desc = L["Hides the standard alternate power bar shown in some encounters and quests."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'boss', {
		type = 'toggle',
		name = L["Boss"],
		desc = L["Hides the standard boss frames."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'arena', {
		type = 'toggle',
		name = L["Arena"],
		desc = L["Hide the standard arena frames."],
		get = get,
		set = set,
		hidden = hidden,
	}, 'sep', {
		type = 'header',
		name = '',
		order = -2,
		hidden = function() return not self:IsEnabled() or not reload_needed end,
	}, 'reloadui', {
		type = 'execute',
		name = 'Reload UI',
		order = -1,
		func = function() C_UI.Reload() end,
		hidden = function() return not reload_needed end,
	}
end)
