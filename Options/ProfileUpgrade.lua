local _G = _G
local PitBull4 = _G.PitBull4
local L = PitBull4.L

-- Patch 091: remember whether SavedVariables already existed before this addon
-- load. This lets the compatibility assistant distinguish an upgraded install
-- from a genuinely fresh PitBull setup without relying on a version string that
-- older profiles never stored.
local raw_db_at_load = _G.PitBull4DB
local HAD_EXISTING_CONFIG_AT_LOAD = type(raw_db_at_load) == "table" and (
	(type(raw_db_at_load.profiles) == "table" and next(raw_db_at_load.profiles) ~= nil)
	or (type(raw_db_at_load.profileKeys) == "table" and next(raw_db_at_load.profileKeys) ~= nil)
	or (type(raw_db_at_load.namespaces) == "table" and next(raw_db_at_load.namespaces) ~= nil)
)

local ASSISTANT_GENERATION = 1
local session_deferred_profiles = {}
local callbacks_registered = false
local assistant_callback_owner = {}

local function get_luatexts_module()
	return PitBull4:GetModule("LuaTexts", true)
end

local function get_scan()
	local module = get_luatexts_module()
	if not module or type(module.ScanLegacyProfileCompatibility) ~= "function" then
		return nil
	end
	return module:ScanLegacyProfileCompatibility()
end

local function get_upgrade_store(create)
	local root = _G.PitBull4SafetyBackups
	if type(root) ~= "table" and create then
		root = { version = 2, profiles = {} }
		_G.PitBull4SafetyBackups = root
	end
	if type(root) ~= "table" then
		return nil
	end
	if type(root.profile_upgrade) ~= "table" and create then
		root.profile_upgrade = {
			version = 1,
			snapshots = {},
			assistant = {},
		}
	end
	local store = root.profile_upgrade
	if type(store) ~= "table" then
		return nil
	end
	if type(store.snapshots) ~= "table" and create then store.snapshots = {} end
	if type(store.assistant) ~= "table" and create then store.assistant = {} end
	return store
end

local function notify_options()
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry and PitBull4.Options and PitBull4.Options.IsRegistered and PitBull4.Options.IsRegistered() then
		registry:NotifyChange("PitBull4")
	end
end

local function get_profile_name()
	return PitBull4.db and PitBull4.db:GetCurrentProfile() or nil
end

local function get_assistant_state(create)
	local store = get_upgrade_store(create)
	local profile_name = get_profile_name()
	if not store or not profile_name then return nil end
	if type(store.assistant[profile_name]) ~= "table" and create then
		store.assistant[profile_name] = {}
	end
	return store.assistant[profile_name]
end

local function set_assistant_state(state_name)
	local state = get_assistant_state(true)
	if not state then return end
	state.generation = ASSISTANT_GENERATION
	state.state = state_name
	state.updated_at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or ""
end

function PitBull4:GetProfileUpgradeSafetySnapshot()
	local store = get_upgrade_store(false)
	local profile_name = get_profile_name()
	return store and store.snapshots and profile_name and store.snapshots[profile_name] or nil
end

function PitBull4:HasProfileUpgradeSafetySnapshot()
	return type(self:GetProfileUpgradeSafetySnapshot()) == "table"
end

function PitBull4:CreateProfileUpgradeSafetySnapshot()
	if InCombatLockdown() then
		return false, "backup unavailable while in combat"
	end
	if type(self.CaptureCurrentProfileSafetySnapshot) ~= "function" then
		return false, "snapshot helper unavailable"
	end
	local snapshot, namespace_count, err = self:CaptureCurrentProfileSafetySnapshot(91)
	if not snapshot then
		return false, err or "snapshot creation failed"
	end
	local store = get_upgrade_store(true)
	if not store then
		return false, "backup store unavailable"
	end
	snapshot.kind = "profile_upgrade"
	snapshot.reason = "pre-midnight compatibility"
	store.snapshots[snapshot.profile_name] = snapshot
	set_assistant_state("backup_created")
	notify_options()
	return true, namespace_count
end

function PitBull4:DeleteProfileUpgradeSafetySnapshot()
	local store = get_upgrade_store(false)
	local profile_name = get_profile_name()
	if not store or not store.snapshots or not profile_name or not store.snapshots[profile_name] then
		return false
	end
	store.snapshots[profile_name] = nil
	notify_options()
	return true
end

function PitBull4:RestoreProfileUpgradeSafetySnapshot()
	if InCombatLockdown() then
		return false, "restore unavailable while in combat"
	end
	local snapshot = self:GetProfileUpgradeSafetySnapshot()
	local profile_name = get_profile_name()
	if type(snapshot) ~= "table" or type(snapshot.profile) ~= "table" or not profile_name then
		return false, "pre-upgrade backup missing or invalid"
	end
	local root = _G.PitBull4SafetyBackups
	if type(root) ~= "table" then
		return false, "backup store unavailable"
	end
	root.pending_restore = {
		profile_name = profile_name,
		source = "profile_upgrade",
		requested_at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "",
		patch = 91,
	}
	local reload_ui = _G.ReloadUI
	if type(reload_ui) ~= "function" then
		root.pending_restore = nil
		return false, "ReloadUI is unavailable"
	end
	self:Printf(L["Pre-upgrade PitBull backup restore staged for profile '%s'; reloading UI now..."], profile_name)
	reload_ui()
	return true
end

local function open_profile_upgrade_page()
	local dialog = LibStub("AceConfigDialog-3.0", true)
	if not dialog then return end
	dialog:Open("PitBull4")
	dialog:SelectGroup("PitBull4", "profile_upgrade")
end

local function review_description(scan)
	if not scan or (scan.review or 0) == 0 then
		return L["No custom LuaTexts requiring manual pre-Midnight compatibility review were detected."]
	end
	local lines = {
		L["Custom LuaTexts flagged for manual review: %d (Name: %d, Class: %d, Health: %d, Power: %d)"]:format(
			scan.review or 0,
			scan.review_name or 0,
			scan.review_class or 0,
			scan.review_health or 0,
			scan.review_power or 0
		),
	}
	local limit = math.min(#(scan.review_items or {}), 8)
	for i = 1, limit do
		local item = scan.review_items[i]
		lines[#lines + 1] = ("- %s / %s (%s)"):format(tostring(item.layout or "?"), tostring(item.element or "?"), tostring(item.category or "?"))
	end
	if (scan.review or 0) > limit then
		lines[#lines + 1] = L["...and %d more."]:format((scan.review or 0) - limit)
	end
	return table.concat(lines, "\n")
end

local function scan_description()
	local profile_name = get_profile_name() or "?"
	local scan = get_scan()
	if not scan then
		return L["LuaTexts is unavailable, so this profile cannot be scanned for legacy text compatibility right now."]
	end
	return L["Current profile: %s\nKnown legacy stock LuaTexts: %d (Name: %d, Class: %d, Health: %d, Power: %d)\nCustom/pre-Midnight LuaTexts for manual review: %d"]:format(
		profile_name,
		scan.total or 0,
		scan.name or 0,
		scan.class or 0,
		scan.health or 0,
		scan.power or 0,
		scan.review or 0
	)
end

local function backup_status()
	local snapshot = PitBull4:GetProfileUpgradeSafetySnapshot()
	if snapshot then
		return L["Pre-upgrade backup: %s (%d module namespaces)"]:format(snapshot.created_at or L["unknown time"], snapshot.namespace_count or 0)
	end
	return L["Pre-upgrade backup: none"]
end

local function perform_known_upgrade()
	local module = get_luatexts_module()
	if not module or type(module.UpgradeLegacyProfileCompatibility) ~= "function" then
		PitBull4:Printf(L["Profile upgrade failed: LuaTexts is unavailable."])
		return false
	end

	-- Never overwrite a pre-upgrade recovery point automatically. If none exists,
	-- create one immediately before the first migration.
	if not PitBull4:HasProfileUpgradeSafetySnapshot() then
		local ok, detail = PitBull4:CreateProfileUpgradeSafetySnapshot()
		if not ok then
			PitBull4:Printf(L["Profile upgrade aborted because a pre-upgrade backup could not be created: %s"], tostring(detail or "unknown error"))
			return false
		end
	end

	local result = module:UpgradeLegacyProfileCompatibility()
	if not result or (result.total or 0) == 0 then
		PitBull4:Printf(L["No known legacy profile settings required an upgrade."])
		set_assistant_state("reviewed")
		return false
	end

	set_assistant_state("upgraded")
	PitBull4:Printf(L["Profile upgrade complete: %d LuaTexts updated (Name: %d, Class: %d, Health: %d, Power: %d)."], result.total or 0, result.name or 0, result.class or 0, result.health or 0, result.power or 0)
	if (result.review or 0) > 0 then
		PitBull4:Printf(L["%d custom/pre-Midnight LuaText(s) were detected and intentionally left unchanged for manual review."], result.review)
	end
	if _G.ReloadUI then
		_G.ReloadUI()
	end
	return true
end

StaticPopupDialogs["PITBULL4_PROFILE_UPGRADE_RESTORE"] = {
	text = L["Restore the dedicated pre-upgrade PitBull backup for profile '%s'? All current changes to this profile since that backup will be overwritten and the UI will reload immediately."],
	button1 = L["Restore"],
	button2 = CANCEL,
	OnAccept = function(_, data)
		if not data or data.profile_name ~= get_profile_name() then return end
		local ok, err = PitBull4:RestoreProfileUpgradeSafetySnapshot()
		if not ok then
			PitBull4:Printf(L["Pre-upgrade backup restore failed: %s"], tostring(err or "unknown error"))
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PITBULL4_LEGACY_PROFILE_DETECTED"] = {
	text = L["PitBull detected an existing profile '%s' with %d pre-Midnight compatibility candidate(s). Create a dedicated pre-upgrade backup and review them now?"],
	button1 = L["Backup & review"],
	button2 = L["Later"],
	button3 = L["Don't ask again"],
	OnAccept = function(_, data)
		if not data or data.profile_name ~= get_profile_name() then return end
		local ok, detail = PitBull4:CreateProfileUpgradeSafetySnapshot()
		if not ok then
			PitBull4:Printf(L["Pre-upgrade backup could not be created: %s"], tostring(detail or "unknown error"))
			return
		end
		local scan = get_scan() or data.scan
		if scan and (scan.total or 0) > 0 then
			StaticPopup_Show("PITBULL4_LEGACY_PROFILE_UPGRADE_OFFER", scan.total or 0, scan.review or 0, { profile_name = data.profile_name, scan = scan })
		else
			set_assistant_state("reviewed")
			open_profile_upgrade_page()
		end
	end,
	OnCancel = function(_, data)
		if data and data.profile_name then
			session_deferred_profiles[data.profile_name] = true
		end
	end,
	OnAlt = function()
		set_assistant_state("dismissed")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PITBULL4_LEGACY_PROFILE_UPGRADE_OFFER"] = {
	text = L["Backup created. PitBull can safely update %d known legacy LuaText(s). %d custom/pre-Midnight LuaText(s) will be left unchanged for review."],
	button1 = L["Upgrade known code"],
	button2 = L["Review first"],
	button3 = L["Later"],
	OnAccept = function(_, data)
		if not data or data.profile_name ~= get_profile_name() then return end
		perform_known_upgrade()
	end,
	OnCancel = function()
		set_assistant_state("reviewed")
		open_profile_upgrade_page()
	end,
	OnAlt = function()
		set_assistant_state("offered")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function maybe_offer_legacy_profile_assistant()
	if not HAD_EXISTING_CONFIG_AT_LOAD or InCombatLockdown() then return end
	local profile_name = get_profile_name()
	if not profile_name then return end
	if session_deferred_profiles[profile_name] then return end
	local state = get_assistant_state(false)
	if state and state.generation == ASSISTANT_GENERATION then
		return
	end
	if _G.StaticPopup_Visible and _G.StaticPopup_Visible("PITBULL4_SAFE_EDIT_MODE_REFERENCE_BACKUP") then
		if C_Timer and C_Timer.After then
			C_Timer.After(2, maybe_offer_legacy_profile_assistant)
		end
		return
	end
	local scan = get_scan()
	if not scan then return end
	local candidates = (scan.total or 0) + (scan.review or 0)
	if candidates <= 0 then
		set_assistant_state("clean")
		return
	end
	StaticPopup_Show("PITBULL4_LEGACY_PROFILE_DETECTED", profile_name, candidates, { profile_name = profile_name, scan = scan })
end

local function schedule_legacy_profile_assistant()
	if not HAD_EXISTING_CONFIG_AT_LOAD then return end
	if C_Timer and C_Timer.After then
		C_Timer.After(2.5, maybe_offer_legacy_profile_assistant)
	else
		maybe_offer_legacy_profile_assistant()
	end
end

local event_frame = CreateFrame("Frame")
event_frame:RegisterEvent("PLAYER_LOGIN")
event_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
event_frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if PitBull4.db and type(PitBull4.db.RegisterCallback) == "function" and not callbacks_registered then
			callbacks_registered = true
			assistant_callback_owner.OnProfileChanged = schedule_legacy_profile_assistant
			PitBull4.db.RegisterCallback(assistant_callback_owner, "OnProfileChanged")
			PitBull4.db.RegisterCallback(assistant_callback_owner, "OnProfileCopied", "OnProfileChanged")
		end
		schedule_legacy_profile_assistant()
	elseif event == "PLAYER_REGEN_ENABLED" then
		schedule_legacy_profile_assistant()
	end
end)

function PitBull4.Options.get_profile_upgrade_options()
	return {
		type = "group",
		name = L["Profile Upgrade"],
		desc = L["Scan and update known legacy PitBull profile data for Midnight 12.1 compatibility without resetting layouts or visual settings."],
		childGroups = "tree",
		args = {
			intro = {
				type = "description",
				name = L["Known stock pre-Midnight LuaTexts can be upgraded automatically. Custom scripts that look potentially incompatible are reported for review but are never rewritten automatically."],
				order = 1,
				width = "full",
			},
			backup_header = {
				type = "header",
				name = L["Pre-upgrade safety backup"],
				order = 5,
			},
			backup_status = {
				type = "description",
				name = backup_status,
				order = 6,
				width = "full",
			},
			create_backup = {
				type = "execute",
				name = L["Create / update pre-upgrade backup"],
				desc = L["Save a dedicated full snapshot of the current PitBull profile before compatibility changes. This backup is separate from Edit Mode Backup snapshots."],
				order = 7,
				disabled = function() return InCombatLockdown() end,
				confirm = function()
					if PitBull4:HasProfileUpgradeSafetySnapshot() then
						return L["Replace the existing dedicated pre-upgrade backup with the current profile state?"]
					end
				end,
				func = function()
					local ok, detail = PitBull4:CreateProfileUpgradeSafetySnapshot()
					if ok then
						PitBull4:Printf(L["Pre-upgrade PitBull backup saved for profile '%s' (%d module namespaces)."], get_profile_name() or "", detail or 0)
					else
						PitBull4:Printf(L["Pre-upgrade backup could not be created: %s"], tostring(detail or "unknown error"))
					end
				end,
			},
			restore_backup = {
				type = "execute",
				name = L["Restore pre-upgrade backup"],
				desc = L["Restore the complete profile state captured before compatibility changes. The restore is applied before AceDB initializes on the following UI reload."],
				order = 8,
				disabled = function() return InCombatLockdown() or not PitBull4:HasProfileUpgradeSafetySnapshot() end,
				func = function()
					StaticPopup_Show("PITBULL4_PROFILE_UPGRADE_RESTORE", get_profile_name(), nil, { profile_name = get_profile_name() })
				end,
			},
			delete_backup = {
				type = "execute",
				name = L["Delete pre-upgrade backup"],
				order = 9,
				disabled = function() return not PitBull4:HasProfileUpgradeSafetySnapshot() end,
				confirm = true,
				confirmText = L["Delete the dedicated pre-upgrade backup for the current profile?"],
				func = function() PitBull4:DeleteProfileUpgradeSafetySnapshot() end,
			},
			status_header = {
				type = "header",
				name = L["Compatibility scan"],
				order = 10,
			},
			status = {
				type = "description",
				name = scan_description,
				order = 11,
				width = "full",
			},
			review = {
				type = "description",
				name = function() return review_description(get_scan()) end,
				order = 12,
				width = "full",
			},
			upgrade = {
				type = "execute",
				name = L["Upgrade known legacy code"],
				desc = L["Apply only known-safe Midnight 12.1 compatibility migrations. Custom/pre-Midnight scripts flagged for review are never modified automatically."],
				order = 20,
				disabled = function()
					if InCombatLockdown() then return true end
					local scan = get_scan()
					return not scan or (scan.total or 0) == 0
				end,
				confirm = true,
				confirmText = L["Upgrade the known legacy LuaTexts in the current profile? A dedicated pre-upgrade backup will be created automatically if one does not already exist. Custom scripts are left unchanged."],
				func = perform_known_upgrade,
			},
		},
	}
end
