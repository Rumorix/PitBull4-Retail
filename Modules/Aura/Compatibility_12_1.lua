-- PitBull4 12.1 compatibility boundary.
-- 12.1.5-P006 prepares configured boss aura containers outside combat and
-- adds a bounded frame-drag release listener. P005 audits the API surface and hardens
-- resource/identity paths; native Aura rendering and P004 movers are retained.
-- 12.1.5-P004 filters movers and restores saved group anchors after roster updates.
-- 12.1.5-P003 also rebinds pings on direct unit-editor changes.
-- 12.1.5-P002 isolates native Party method/pool surfaces from hiding hooks.
--
-- 12.1.5-P001 restarts release numbering from the complete Patch 109 build.
-- Only release metadata changes; earlier patch labels identify retained fixes.
-- Patch 038 hardens LuaTexts power formatting against Midnight secret
-- UnitPower/UnitPowerMax/UnitPowerMissing values. Stock Power, Druid mana and
-- Alternate power texts fall back to Blizzard's UnitPowerPercent path.
-- Patch 037 hardens legacy Health LuaTexts and 3D portraits against Midnight
-- secret health values and protected unit identities. Legacy raw HP percentage
-- expressions are normalized to PercentHP(unit), and stale 3D models are hidden
-- until Blizzard allows the unit identity to be bound again.
-- Patch 036 prevents the RoleIcon module from comparing or indexing with a
-- secret UnitGroupRolesAssigned() result; protected role identity is treated as
-- unavailable until Blizzard exposes a public role value.
-- Patch 035 hardens Totems against secret GetTotemInfo/GetTotemTimeLeft values.
-- Patch 034 audits the built-in Major Cooldown spell IDs, expands the public
-- cast-to-aura alias model to known mismatched active aura IDs, and removes
-- entries that do not produce a suitable helpful player aura for this module.
-- Patch 033 fixed Fortifying Brew by retaining ability/configuration spell
-- 115203 while allowing the active buff aura 120954.
-- Patch 099 restores the native Aura filter editor and scoped spell-ID lists.
-- Patch 102 makes every Retail Blizzard-frame hider passive, skips Edit Mode
-- Selection helpers, and defers all hook-driven frame API calls to a timer.
-- Patch 103 includes native texture/font-string regions in passive hiding so
-- Ready Check icons cannot bypass a transparent Blizzard frame's alpha.
-- Patch 104 observes Show/SetShown methods instead of hooking native OnShow
-- scripts, whose forbidden bindings could abort every remaining hider.
-- Patch 105 scopes repeated hiding work to dirty objects, caches unchanged
-- native aura configuration and bounds core/group polling after a hitch.
-- Patch 106 disables production core developer assertions; the optional Aura
-- debug menu and the inherited runtime update/taint protections are retained.
-- Patch 108 protects font sizing during profile transitions, deep-copies nested
-- legacy Aura options and renders selected absolute Power texts via the native sink.
-- Patch 107 makes requested Player/Party mover roots inherit parent alpha and
-- disables their input on the next-frame timer; descendants/hooks stay native.
-- Patch 098 excludes current stock LuaTexts from the legacy profile review scan
-- and distinguishes raw helper calls from safe helpers with longer names.
-- Patch 097 adds resource-bar-only callouts alongside normal self pings on the
-- rest of the Player frame. The native protocol cannot force HP/mana separately.
-- Patch 096 makes the Patch 032 player-resource ping behavior optional and
-- restores Blizzard's normal PingableUnitFrameTemplate self/unit behavior as the
-- default for the PitBull Player frame.
-- Patch 032 restores Blizzard player-resource ping callouts on PitBull player
-- frames by exposing the player-resource target marker through GetTargetInfo and
-- suppressing the radial wheel on that resource surface. Blizzard remains the
-- owner of the actual health/power values.
-- Patch 031 refreshes Blizzard-managed AuraContainers when dynamic unit tokens
-- such as target/focus keep the same token while their underlying unit changes.
-- Patch 030 restores the packaged upstream translations for PitBull4's legacy
-- interface and adds the Lorenzo diagnostics, MajorCooldownAuras, and
-- ImportantDebuffs strings to every WoW locale shipped by the addon.
-- Patch 028 defers MajorCooldownAuras protected state-driver creation and all
-- state replacement until combat lockdown ends, preventing RegisterStateDriver
-- from reaching SecureStateDriverManager:SetAttribute during combat.
-- Patch 027 hides resource-less target PowerBars through UnitPowerMax's public
-- zero sentinel and migrates existing layouts to PitBull's hide-no-power mode.
-- Patch 026 lets the exact defensive spell-ID allowlist operate in Blizzard's
-- protected HELPFUL domain instead of intersecting it with BIG_DEFENSIVE. This
-- restores valid active defensives such as Feint, Evasion and Crimson Vial.
-- A secure help-only visibility driver prevents Blizzard's intentionally
-- relaxed identity policy on hostile units from exposing unrelated buffs, and
-- a protected five-minute duration ceiling rejects long food-style buffs.
-- Patch 025's narrowly scoped local-player target-effect path for Deathmark
-- and Kingsbane remains protected by HARMFUL|PLAYER and player-frame scope.
-- Patch 024's
-- independent ImportantDebuffs tab remains the only encounter-debuff display.
-- Patch 021's protected reaction colors,
-- Patch 020's CompactRaidFrameManager
-- retry and Patch
-- 019's optional addon-owned animated yellow cooldown border remain active,
-- Patch 018's expanded public defensive candidate preset,
-- Patch 017's top-layer cooldown rendering,
-- Patch 016's flat per-class controls, centered anchor and
-- compact AFK status, Patch 015's secure-delegate unit-tooltip path,
-- Patch 014's absorb direction,
-- Patch 013's full-health absorb visibility, cooldown independence, and
-- party/raid range indication, Patch 012's independent Buffs/Debuffs selector,
-- and the earlier protected 12.1 aura renderer work. Keep all unstable 12.1
-- capability checks here so future client changes remain isolated from Aura.

local PitBull4 = _G.PitBull4
local PitBull4_Aura = PitBull4:GetModule("Aura")

local type = type
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local ipairs = ipairs
local table_insert = table.insert

local LORENZO_121_MIN_INTERFACE = 120100
local LORENZO_121_REVIEWED_SOURCE_BUILD = 70391
local aura_container_load_attempted = false

local state = {
	branch = "Midnight-12.1",
	releaseVersion = "12.1.5-P008",
	patch = 8,
	previousPatch = 7,
	reviewedSourceBuild = LORENZO_121_REVIEWED_SOURCE_BUILD,
	reviewedSourceVersion = "12.1.5.70391",
	reviewedSourceCommit = "18c6d677b605b312f3d813d498404631fb941977",
	partyPingReviewedSourceVersion = "12.1.5.70391",
	partyPingReviewedSourceCommit = "18c6d677b605b312f3d813d498404631fb941977",
	legacyAuraPath = false,
	managedAuraPrototype = true,
	nativeRendererRequested = true,
}

PitBull4_Aura.Lorenzo121 = state

local function safe_boolean_call(func, ...)
	if type(func) ~= "function" then
		return false
	end
	local ok, value = pcall(func, ...)
	return ok and value and true or false
end

local function has_function(namespace, key)
	return type(namespace) == "table" and type(namespace[key]) == "function"
end

local function try_load_aura_container()
	if aura_container_load_attempted then
		return
	end
	aura_container_load_attempted = true
	local addons = _G.C_AddOns
	if not addons or type(addons.LoadAddOn) ~= "function" then
		state.auraContainerLoadResult = "LoadAddOn unavailable"
		return
	end
	local ok, loaded, reason = pcall(addons.LoadAddOn, "Blizzard_AuraContainer")
	if not ok then
		state.auraContainerLoadResult = "error:" .. tostring(loaded)
	elseif loaded then
		state.auraContainerLoadResult = "loaded"
	else
		state.auraContainerLoadResult = "not-loaded:" .. tostring(reason)
	end
end

function PitBull4_Aura:Lorenzo121SafeCall(func, ...)
	if type(func) ~= "function" then
		return false, nil, "missing-function"
	end
	return pcall(func, ...)
end

function PitBull4_Aura:Lorenzo121RefreshCapabilities()
	local version, build, build_date, interface = GetBuildInfo()
	state.clientVersion = version
	state.clientBuild = build
	state.clientBuildNumber = tonumber(build) or 0
	state.clientBuildDate = build_date
	state.clientInterface = tonumber(interface) or 0
	state.is121OrNewer = state.clientInterface >= LORENZO_121_MIN_INTERFACE
	state.isAtLeastReviewedSourceBuild = state.clientBuildNumber >= LORENZO_121_REVIEWED_SOURCE_BUILD
	if state.is121OrNewer then
		try_load_aura_container()
	end

	local unit_auras = _G.C_UnitAuras
	state.hasLegacyGetUnitAuras = has_function(unit_auras, "GetUnitAuras")
	state.hasAuraDuration = has_function(unit_auras, "GetAuraDuration")
	state.hasAuraExpirationPredicate = has_function(unit_auras, "DoesAuraHaveExpirationTime")
	state.hasAuraDisplayCount = has_function(unit_auras, "GetAuraApplicationDisplayCount")
	state.hasAuraInstanceIDList = has_function(unit_auras, "GetUnitAuraInstanceIDs")
	state.hasAuraProviderSwitch = has_function(unit_auras, "SwitchAuraDataProvider")
	state.hasAuraProviderReset = has_function(unit_auras, "ResetAuraDataProvider")
	state.hasAuraDispelColor = has_function(unit_auras, "GetAuraDispelTypeColor")
	state.hasHiddenGroupBuffs = has_function(unit_auras, "GetHiddenGroupBuffs")
	state.hasGroupBuffVisualAlerts = has_function(unit_auras, "GetGroupBuffVisualAlerts")
	state.hasPrivateAuraAnchor = has_function(unit_auras, "AddPrivateAuraAnchor")
	state.hasRemovedPrivateAuraTrigger = has_function(unit_auras, "TriggerPrivateAuraShowDispelType")

	local addons = _G.C_AddOns
	state.auraContainerAddonLoaded = safe_boolean_call(addons and addons.IsAddOnLoaded, "Blizzard_AuraContainer")
	-- Blizzard_AuraContainer Lua now runs in a secure environment. Its mixin
	-- tables are intentionally not exported, so only exported prerequisites can
	-- be checked here. NativeContainer_12_1 validates the actual inbound methods
	-- on each newly created container and button before using that object.
	state.hasNativeFrameConstructor = type(_G.CreateFrame) == "function"
	state.hasAuraContainerSortEnums = type(_G.AuraContainerSortMethod) == "table"
		and type(_G.AuraContainerSortDirection) == "table"
	state.hasItemEnchantmentEnums = type(_G.AuraContainerItemEnchantmentSlot) == "table"
		and type(_G.AuraContainerItemEnchantmentSortMethod) == "table"
		and type(_G.CustomAuraContainerItemEnchantmentPlacement) == "table"
	state.hasFlowLayoutEnums = type(_G.AnchorUtil) == "table"
		and type(_G.AnchorUtil.FlowLayoutAxis) == "table"
		and type(_G.AnchorUtil.FlowDirection) == "table"
	state.hasCurrentDispelOptions = type(_G.Enum) == "table"
		and type(_G.Enum.CustomAuraButtonDispelTypeStealableFilter) == "table"
	state.hasForbiddenAspectEnum = type(_G.Enum) == "table" and type(_G.Enum.ForbiddenAspect) == "table"
	state.hasForbiddenAspectInheritanceEnum = type(_G.Enum) == "table" and type(_G.Enum.ForbiddenAspectInheritance) == "table"
	state.nativeAPIPrerequisitesReady = state.hasNativeFrameConstructor
		and state.hasAuraContainerSortEnums
		and state.hasItemEnchantmentEnums
		and state.hasFlowLayoutEnums
		and state.hasCurrentDispelOptions
	state.managedAuraPrototype = true
	state.legacyAuraPath = not (state.nativeRendererRequested
		and state.is121OrNewer
		and state.auraContainerAddonLoaded
		and state.nativeAPIPrerequisitesReady)
	return state
end

function PitBull4_Aura:Lorenzo121UnitsMatch(unit_a, unit_b)
	if not unit_a or not unit_b then
		return false
	end
	local checker = _G.C_Secrets and _G.C_Secrets.ShouldUnitComparisonBeSecret
	if type(checker) == "function" then
		local ok, secret = pcall(checker, unit_a, unit_b)
		if ok and secret then
			return false
		end
	end
	if type(_G.UnitIsUnit) == "function" then
		local ok, same = pcall(_G.UnitIsUnit, unit_a, unit_b)
		if ok then
			return same and true or false
		end
	end
	local ok, same = pcall(function()
		return unit_a == unit_b
	end)
	return ok and same or false
end

function PitBull4_Aura:Lorenzo121IsClient()
	self:Lorenzo121RefreshCapabilities()
	return state.is121OrNewer
end

function PitBull4_Aura:Lorenzo121UseLegacyAuraPath()
	if self.Lorenzo121NativeRendererActive then
		return not self:Lorenzo121NativeRendererActive()
	end
	return true
end

function PitBull4_Aura:Lorenzo121NormalizePrivateAuraAnchorArgs(args)
	if type(args) ~= "table" then
		return args
	end
	-- 12.1 renamed showCountdownFrame to showCooldownFrame. Populate both keys
	-- so shared code can be exercised on 12.0.7 and the 12.1 PTR.
	if args.showCooldownFrame == nil and args.showCountdownFrame ~= nil then
		args.showCooldownFrame = args.showCountdownFrame
	elseif args.showCountdownFrame == nil and args.showCooldownFrame ~= nil then
		args.showCountdownFrame = args.showCooldownFrame
	end
	if args.showCooldownEdge == nil then
		args.showCooldownEdge = false
	end
	if args.showDispelIcon == nil then
		args.showDispelIcon = false
	end
	return args
end

local function yes_no(value)
	return value and "yes" or "no"
end

function PitBull4_Aura:Lorenzo121GetStatusLines()
	self:Lorenzo121RefreshCapabilities()
	local lines = {
		"12.1.5-P008 soulShardRelayout=structural-only; profileRebind=rebuild-via-pool; nativeShardRelease=reset-without-spend-animation. Live client confirmation is pending.",
		"12.1.5-P007 soulShardTemplate=verified-native-or-bundled-fallback; numeric guards retained; partial-container cleanup is safe. Focused shard source review: Retail 12.1.5.70448. Live shard visuals are pending confirmation.",
		"12.1.5-P006 bossAuraPreparation=outside-combat configured-boss-slots; hidden prepared containers follow native visibility/events; dragRelease=GLOBAL_MOUSE_UP active-drag-only; duplicate drag starts ignored; snap backend captured at drag start. Live encounter/Bartender confirmation is pending.",
		"12.1 branch=" .. state.branch .. " release=" .. state.releaseVersion .. " patch=" .. state.patch .. " previousPatch=" .. state.previousPatch .. " legacyAuraPath=" .. yes_no(state.legacyAuraPath) .. " managedPrototype=" .. yes_no(state.managedAuraPrototype),
		"12.1 client version=" .. tostring(state.clientVersion) .. " build=" .. tostring(state.clientBuild) .. " interface=" .. tostring(state.clientInterface) .. " is121OrNewer=" .. yes_no(state.is121OrNewer),
		"12.1 source reviewedBuild=" .. tostring(state.reviewedSourceBuild) .. " clientAtLeastReviewed=" .. yes_no(state.isAtLeastReviewedSourceBuild),
		"12.1 legacy APIs GetUnitAuras=" .. yes_no(state.hasLegacyGetUnitAuras) .. " instanceIDs=" .. yes_no(state.hasAuraInstanceIDList) .. " GetAuraDuration=" .. yes_no(state.hasAuraDuration) .. " hasExpiration=" .. yes_no(state.hasAuraExpirationPredicate),
		"12.1 aura helpers displayCount=" .. yes_no(state.hasAuraDisplayCount) .. " dispelColor=" .. yes_no(state.hasAuraDispelColor) .. " providerSwitch=" .. yes_no(state.hasAuraProviderSwitch) .. " providerReset=" .. yes_no(state.hasAuraProviderReset),
		"12.1 group APIs hiddenBuffs=" .. yes_no(state.hasHiddenGroupBuffs) .. " visualAlerts=" .. yes_no(state.hasGroupBuffVisualAlerts) .. " privateAuraAnchor=" .. yes_no(state.hasPrivateAuraAnchor) .. " removedPrivateAuraTriggerStillPresent=" .. yes_no(state.hasRemovedPrivateAuraTrigger),
		"12.1 container addonLoaded=" .. yes_no(state.auraContainerAddonLoaded) .. " loadResult=" .. tostring(state.auraContainerLoadResult) .. " frameConstructor=" .. yes_no(state.hasNativeFrameConstructor),
		"12.1 enums sort=" .. yes_no(state.hasAuraContainerSortEnums) .. " itemEnchantments=" .. yes_no(state.hasItemEnchantmentEnums) .. " flowLayout=" .. yes_no(state.hasFlowLayoutEnums) .. " currentDispelOptions=" .. yes_no(state.hasCurrentDispelOptions) .. " forbiddenAspects=" .. yes_no(state.hasForbiddenAspectEnum),
		"12.1 native exported prerequisites ready=" .. yes_no(state.nativeAPIPrerequisitesReady) .. " runtime surface is validated on created protected objects.",
		"12.1.5-P005 fullApiReview reviewedClient=" .. state.reviewedSourceVersion .. " sourceCommit=" .. state.reviewedSourceCommit .. "; nativePvPDisplayInfo=" .. yes_no(UnitFrameUtil and type(UnitFrameUtil.GetUnitPvPIndicatorDisplayInfo) == "function") .. "; fontFallbackAttempts=" .. tostring(PitBull4.Controls and PitBull4.Controls.GetFontFallbackStatus and select(1, PitBull4.Controls.GetFontFallbackStatus()) or 0) .. " fontFallbackSuccesses=" .. tostring(PitBull4.Controls and PitBull4.Controls.GetFontFallbackStatus and select(2, PitBull4.Controls.GetFontFallbackStatus()) or 0) .. "; 12.1.5 API and native Aura/Selection surfaces reviewed; rejected fonts fall back to the client font without replacing saved font selections.",
		"12.1.5-P002 partyPingReviewedClient=" .. state.partyPingReviewedSourceVersion .. " sourceCommit=" .. state.partyPingReviewedSourceCommit .. "; native Party members/bars/visuals/pools have no hiding method hooks; container observers retained; existing lifecycle events reconcile cached Party visuals. Reused Player frames restore native unit-ping methods when bound to Target/Focus; native HP/mana resource callouts remain player-only. The complete current Retail API audit is listed above; live Party taint confirmation is pending.",
		"12.1.5-P005 currentApiCalls=enabled; publicNumericResources=guarded; addonEssenceOnUpdate=guarded; nativeEssenceMixin=unchanged; optionsVersion=installed-TOC; PTR 12.1.7.70424 reviewed for relevant deltas without declaring 12.1.7 support.",
		"12.1.5-P004 filteredEditModeGroups=enabled; Live counts visible filtered member frames; numeric raid filters restrict manual previews; configured filtered envelope and saved group anchor are retained; roster reconciliation runs on the next frame outside combat. Live position confirmation remains pending.",
		"12.1.5-P003 unitEditorPingRebind=enabled; changing Units > General > Unit updates the native unit attribute and reapplies Player/native ping methods once. Unchanged choices and ordinary frame updates add no ping refresh. P002 Party/hider and Aura rendering remain unchanged; live Party taint confirmation is pending.",
		"12.1 Patch 108 profileFontFallback=enabled; nestedAuraOptionCopies=independent; previewParser=bounded; stockAbsolutePower=native-current/max; absolute templates retain selected output for public or secret values accepted by SetFormattedText, with percentage fallback on query/display failure and recovery on later updates. No instance-based switch, new polling, native UnitWatch rearm or Party-N count change is added.",
		"12.1 Patch 107 playerPartyMoverFix=enabled; requested PlayerFrame/PartyFrame/CompactPartyFrame Selection roots inherit the hidden parent's alpha and stop taking mouse input; all mover writes run on the next-frame timer outside combat. Native selection alpha/shown state/fields/methods/geometry and descendants stay untouched; no mover hooks or recurring mover polling are installed. Hider diagnostics report mutedMovers/moverFailures/moverPasses.",
		"12.1 Patch 106 productionCoreChecks=" .. (PitBull4.DEBUG and "enabled" or "disabled") .. "; developer assertions are disabled in the packaged release; optional Aura diagnostics remain independent.",
		"12.1 Patch 105 updatePerformanceFix=enabled; local Blizzard visibility/input/region notifications reconcile dirty objects instead of every hidden root; overlapping alpha/tree work is consumed once; unchanged native aura configuration skips setters; core polling is bounded to one round per render frame and group polling discards missed intervals. Public counters report full/tree/input passes and native configuration passes/skips; P100-P104 taint and visibility protections remain included.",
		"12.1 Patch 104 blizzardFrameVisibilityFix=enabled; Retail visibility uses Show/SetShown post-hooks without querying or hooking native script handlers; forbidden OnShow bindings no longer abort suppression of other roots, including target, target-of-target and BuffFrame. All hook work remains deferred; P103 visual-region suppression is retained.",
		"12.1 Patch 103 readyCheckRegionFix=enabled; native texture/font-string regions use zero alpha and inherit the hidden parent's alpha; Ready Check events queue reconciliation. PitBull ReadyCheckIcon is unchanged; P102 deferred hooks and Edit Mode Selection exclusions are retained.",
		"12.1 Patch 102 editModeSelectionTaintFix=enabled; all Retail Blizzard-frame hide options preserve native lifecycle and Edit Mode Selection subtrees; hooks only queue next-frame alpha/input work. P101 Essence lifecycle and bundled Totem Drop sound are retained.",
		"12.1 Patch 100 editModeGroupTaintFix=enabled; Retail group frames use passive alpha/input suppression; Blizzard parents, member pools, events, methods and IsShown settings remain intact; rebuild reconciliation runs on the next frame outside combat.",
		"12.1 Patch 098 legacyTextScannerFix=enabled; exact current Name/Class/Health/Power/Druid mana/Alternate power presets are excluded from upgrade warnings; raw helper detection respects identifier boundaries; custom scripts remain advisory-only.",
		"12.1 Patch 099 nativeAuraFilters=enabled; editor=Modules/Aura/FilterEditor; layout=Aura/Filters; candidate lists are Blizzard-owned; identity scope=helpful-friendly/harmful-hostile; native filter failures never use unfiltered live legacy rows; combat configuration is deferred.",
		"12.1 Patch 097 playerFramePingChoice=" .. (PitBull4.GetPlayerPingBehavior and PitBull4:GetPlayerPingBehavior() or "default") .. "; bars=resource callout over HealthBar/PowerBar/DruidManaBar, normal self ping elsewhere; native HP/mana selection is Blizzard-owned, separate forced HP/mana pings are unsupported; method changes apply only out of combat.",
		"12.1 Patch 096 playerFramePingChoice=retained; Default self ping restores PingableUnitFrameTemplate behavior; optional Health / Power callout retains Patch 032 isPlayerResource behavior.",
		"12.1 Patch 095 demonicTyrantMajorCooldown=enabled; WARLOCK offensive config now includes Summon Demonic Tyrant 265187 and protected HELPFUL AuraContainer matching also accepts Demonic Power 265273 for the 15-second Tyrant active window.",
		"12.1 Patch 094 raidManagerQuarantine=superseded-on-retail; Patch 100 preserves the Blizzard manager parent/events/settings and suppresses its visual/input surface instead.",
		"12.1 Patch 093 focusIdentityAndCompoundClassColor=enabled; Focus receives a guarded Focus-only IdentityDisplay when legacy/shared layouts lack one, and restricted compound units use real class colors only when player/friend/classFile inputs are individually public, otherwise preserving the protected reaction fallback.",
		"12.1 Patch 092 dispelAnchorLocaleFix=enabled; added the four missing diagonal DispelHighlights anchor locale keys (Top left/right and Bottom left/right), eliminating AceLocale missing-entry errors in the Layout Editor.",
		"12.1 Patch 091 existingProfileUpgradeAssistant=enabled; upgraded installs with retained SavedVariables are scanned for known pre-Midnight LuaTexts, offered a dedicated pre-upgrade full-profile backup, and can explicitly migrate known stock code while custom scripts are reported for manual review only.",
		"12.1 Patch 090 legacyProfileUpgrade=enabled; top-level Profile Upgrade scans the current LuaTexts profile for known pre-Midnight stock scripts and can persist exact Name/Class/Health/Power compatibility migrations after ensuring a full safety snapshot exists; custom Name scripts are preserved.",
		"12.1 Patch 089 stableConfigPreviewEnvelope=enabled; Config Mode keeps the full configured group envelope for anchor geometry while independently limiting visible synthetic members, and child1 retains the full-grid orthogonal corner anchor across Party 1/2/3/4 and raid preview counts.",
		"12.1 Patch 088 dynamicConfigPreviewCounts=enabled; Config Mode adds exact Party 1/2/3/4 previews, computes synthetic party/raid geometry from the requested visible count before layout, and clears stale preview frames when shrinking the test roster.",
		"12.1 Patch 087 configModeGeometryIsolation=enabled; live maximum-grid SecureGroupHeader stabilization is skipped for force-shown/PitBull Config Mode previews, which retain their own raid5/10/20/40 synthetic roster geometry.",
		"12.1 Patch 086 fullGridHeaderGeometry=enabled; after Blizzard roster-dependent SecureGroupHeader layout, PitBull restores maximum-grid header dimensions and child1 full-grid anchors so centered-edge group anchors remain stable across partial rows/columns.",
		"12.1 Patch 085 stableGroupGridOrigin=enabled; wrapped SecureGroupHeader layouts keep frame 1 pinned to the full maximum-grid corner across roster-size reflows, preventing row/column recenter jumps without changing saved anchors or growth settings.",
		"12.1 Patch 084 editModeFrameInspector=enabled; PitBull Edit Mode previews start locked; click opens a per-frame inspector with classification, layout, session-only lock/unlock, and reset-to-newest-saved-position backup.",
		"12.1 Patch 083 editModeBackupRestore=enabled; Edit Mode safety controls moved to a top-level Edit Mode Backup page between Debug and Profiles; full snapshots capture the live core profile plus an independent position reference and explicitly restore unit/group geometry pre-AceDB.",
		"12.1 Patch 082 restoreAndIdentityDedupe=enabled; full-profile restore uses a dedicated StaticPopup and immediate ReloadUI after staging pre-AceDB recovery; P074 Focus identity migration now detects existing identity texts/shared layouts and cleans previously injected duplicate Class lines.",
		"12.1 Patch 081 safetyRestoreButtonFix=enabled; AceConfig restore/delete confirmations now use supported confirm=true + confirmText semantics and full restore schedules ReloadUI on the next frame after staging the pre-AceDB recovery request.",
		"12.1 Patch 080 preAceDBSafetyRestore=enabled; full restore is staged across ReloadUI and applied to raw PitBull4DB by SafetyRestoreBootstrap.lua before Main.lua creates AceDB, preventing active profile references from overriding recovery data.",
		"12.1 Patch 079 fullProfileSafetySnapshot=enabled; Safe Edit Mode first-use can store the complete current core profile plus every module namespace profile in separate PitBull4SafetyBackups SavedVariables; full restore replaces only the current profile data and ReloadUI rebuilds all AceDB references.",
		"12.1 Patch 078 safeEditModeOverlay=enabled; Edit Mode uses independent non-secure ghost movers and standalone Party/Raid previews only; real PitBull frames are never ForceShow() and PitBull Config Mode is never changed; position reference stores anchors/X/Y only.",
		"12.1 Patch 075 nativeOwnAuraSizeCompat=enabled; native PLAYER aura groups honor the classic layout my_size setting when the Patch 067 absolute ownership-size override is disabled; my_size is included in the native rebuild signature.",
		"12.1 Patch 074 focusIdentityDisplay=enabled; one-time per-profile migration mirrors the Target Lua:Class identity element into a separate Focus layout when Focus lacks an enabled identity line; existing configured Focus identity text is preserved.",
		"12.1 Patch 073 cyrillicNameFallback=enabled; public Cyrillic Lua:Name values use Blizzard\'s Russian alphabet font while preserving the configured PitBull size/outline; Latin and secret names keep the normal configured font.",
		"12.1 Patch 072 nativeCooldownDurationText=enabled; native aura duration text now prefers the Cooldown widget countdown fed directly by CustomAuraButton's protected DurationObject, with Patch 071 BaseTime text retained only as fallback.",
		"12.1 Patch 071 nativeBaseTimeDurationBinding=fallback; BaseTime binding identified the active native duration path, but live modified-aura testing showed BaseTime alone does not always match Blizzard tooltip display time.",
		"12.1 Patch 070 pausedAuraDurationModRateDetection=enabled; modified-time detection now also reads the live public DurationObject mod rate, so external aura-speed changes do not depend on a refreshed AuraData.timeMod field.",
		"12.1 Patch 069 pausedAuraDurationLongBuffBypass=enabled; modified-time long player auras bypass the legacy expirationTime/timeMod fast path so Patch 068 DurationObject BaseTime formatting can actually handle paused food/flask timers.",
		"12.1 Patch 068 pausedAuraDurationFix=enabled; time-scaled auras use DurationObject BaseTime for PitBull duration text so paused food/flask effects keep their nominal remaining time instead of expanding to multi-day RealTime values.",
		"12.1 Patch 067 auraOwnershipStyling=enabled; native AuraContainer groups are split with PLAYER/!PLAYER so own auras default to green borders and other-player auras to red borders without reading protected sourceUnit; optional own-aura absolute sizes are disabled by default.",
		"12.1 Patch 066 dispelHighlightControls=enabled; relation gating uses UnitCanAssist/UnitCanAttack through SetAlphaFromBoolean, icon anchor/X/Y/frame-level are configurable, default border thickness is 1px, and the icon is raised above LuaTexts by its own frame layer.",
		"12.1 Patch 065 bossIdentityAndDispelFrameFix=enabled; worldboss/skull identities render as ?? Boss <type>; Dispel Highlights uses a rectangular PreserveAsset border plus constrained Blizzard Icon instead of stretching BorderWithIcon over the unit frame; tint opacity is parent-controlled.",
		"12.1 Patch 064 dispelHighlights=enabled; protected AuraSlot drives full-frame Blizzard dispel tint plus BorderWithIcon; optional HARMFUL|RAID restricts highlights to debuffs the local player can dispel; addon never reads protected aura identity/type.",
		"12.1 Patch 063 publicNPCNameDedup=enabled; public NPC Class text suppresses UnitClass labels that exactly duplicate UnitName while preserving real class labels and creature type/family output.",
		"12.1 Patch 062 noResourceFallbackBackground=enabled; no-power anchor rows now keep a darker semi-opaque fallback background so Class/identity text remains readable without showing a fake 0% power fill.",
		"12.1 Patch 061 raidRuntimePerformance=enabled; HealthBar/PowerBar batching frames sleep while idle, wake only for queued unit events, coalesce same-frame repeats, and update through PitBull's UnitID-to-frame index instead of scanning every shown frame.",
		"12.1 Patch 059 restrictedLevelFormatFix=enabled; restricted UnitLevel values are forwarded to SetFormattedText with the numeric %d conversion instead of %s, preventing the approved text sink from failing and blanking the Class/identity line.",
		"12.1 Patch 058 secretLevelIdentitySinkFallback=enabled; if UnitLevel itself is secret even when the broad identity predicate is not, stock Class text switches to the approved SetFormattedText sink path so level and other renderable NPC identity fields are not silently dropped.",
		"12.1 Patch 060 noResourceTextAnchor=enabled; Hide non-power keeps an invisible PowerBar layout anchor so Lua:Class survives on resource-less NPCs while Lua:Power/0% stays hidden.",
		"12.1 Patch 057 npcIdentityNameCleanup=enabled; restricted NPC Class text omits the redundant localized UnitClass string and keeps classification+level+creature type, while player-shaped units retain class+race output.",
		"12.1 Patch 056 legacyIdentitySummaryMigration=enabled; P041-P048 stock Class scripts persisted as IdentitySummary() are migrated to IdentityDisplay(); IdentitySummary now safely returns nil when no renderable format exists.",
		"12.1 Patch 055 restrictedIdentityTextSink=enabled; restricted Class text forwards secret class/race/creature strings directly to FontString:SetFormattedText without inspecting them, while public identities retain the normal colored legacy renderer.",
		"12.1 Patch 054 directPublicIdentityRenderer=enabled; stock Class text is rendered as one prevalidated public string, uses semantic UnitLevel/UnitType tooltip fallbacks when public, preserves classification+level as a stable NPC base, and avoids silent multi-argument SetFormattedText failures.",
		"12.1 Patch 052 raidMPlusIdentityRestore=enabled; Class text keeps public classification+level, derives localized NPC class from public UnitClass classId/classFile, and forwards restricted creature type only through Blizzard-safe text sinks; open-world family-first behavior retained.",
		"12.1 Patch 051 explicitNoResourcePowerProbe=enabled; Hide non-power resolves the public primary power type and queries UnitPowerMax(unit, powerType), using only a non-secret zero sentinel to suppress empty hostile-NPC power rows.",
		"12.1 Patch 050 excludeMainTanks=enabled; normal raid headers can omit Main Tank assignments via an out-of-combat secure name whitelist while preserving configured filter/sort order; oRA3 Main Tanks are honored when available; combat changes are deferred by the existing OOC wrapper.",
		"12.1 Patch 049 restoreLegacyIdentityDisplay=enabled; publicIdentityFieldRestore=enabled; stock Class text forwards protected class/race/creature-type values directly to FontString:SetFormattedText instead of inspecting or concatenating them; public components keep legacy level/classification/color behavior.",
		"12.1 Patch 048 gracefulRestrictedIdentityText=enabled; restricted NPC identity text omits unavailable class/type fields instead of showing Unknown; public structured TooltipData UnitType may restore Blizzard-visible creature type without parsing GameTooltip text.",
		"12.1 Patch 047 restrictedNPCClassExecutionRestore=enabled; stock Class LuaTexts are no longer blanked solely by broad identity restriction; hardened field-safe rendering may use public classId/classFile, level, classification and creature type; restricted custom Class scripts fall back to IdentitySummary.",
		"12.1 Patch 045 classLuaTextRepair=enabled; SmartRace scope fixed; LuaText return forwarding expanded so legacy stock Class format strings keep all SetFormattedText arguments.",
		"12.1 Patch 044 hardenedIdentityRenderer=enabled; Class LuaTexts use secret-safe predicate wrappers for level/race/form/friend checks; any Class-slot execution failure falls back to the hardened stock renderer.",
		"12.1 Patch 042 localeStableLuaTextSlots=enabled; persisted canonical Lua:Class/Lua:Power/Lua:Health resource slot names and localized display names share the same 12.1 safety paths across locales and old profiles.",
		"12.1 Patch 041 secretSafeIdentityTexts=enabled; stock Class text uses a public-only identity summary; legacy/custom Class secret failures fall back safely; protected identities never poison the FontString Text aspect.",
		"12.1 Patch 040 powerSecretPreflight=enabled; legacy/custom raw Power/MaxPower/MissingPower LuaTexts are skipped before execution when Blizzard reports restricted power values, preventing {err} before fallback.",
		"12.1 Patch 039 genericSecretResourceTexts=enabled; resource LuaTexts are recognized by Power/Druid Mana/Alternate Power role and secret-value failures fall back to Blizzard UnitPowerPercent without relying on raw code-pattern matching.",
		"12.1 Patch 038 secretSafePowerTexts=enabled; raw UnitPower/UnitPowerMax/UnitPowerMissing values are never formatted or compared when secret; normal, druid-mana and alternate-power LuaTexts fall back to Blizzard UnitPowerPercent.",
		"12.1 Patch 037 secretSafeHealthTextsAndPortraits=enabled; legacy Percent(HP(unit),MaxHP(unit)) is normalized to PercentHP(unit); secret-health runtime fallback suppresses repeated LuaText errors; protected 3D unit identities hide stale models and retry after combat.",
		"12.1 Patch 036 secretSafeGroupRoles=enabled; secret assigned-role strings are never compared or used as table keys; RoleIcon and GroupHeader suppress role-dependent addon logic until the role is public.",
		"12.1 Patch 035 secretSafeTotems=enabled; state=issecretvalue-guard+SetAlphaFromBoolean; duration=GetTotemDuration; icon=Texture:SetTexture; secret expiry pulse/removal sound=not evaluated in Lua.",
		"12.1 Patch 034 majorCooldownSpellIdAudit=enabled; castAuraAliases=14; removedNoAura=4; config keys preserved; exact protected HELPFUL filters use public aura aliases.",
		"12.1 Patch 033 majorCooldownAuraAlias=enabled; Fortifying Brew config/cast=115203 activeBuff=120954; retained by Patch 034 alias table.",
		"12.1 Patch 032 playerResourcePing=retained-as-option; player-frame isPlayerResource health/power callout remains available through Patch 096 while default mode restores Blizzard's normal self/unit ping.",
		"12.1 Patch 031 dynamicAuraRefresh=target+focus+unit-target; native containers are explicitly re-parsed when a dynamic unit token keeps the same string across an identity change.",
		"12.1 Patch 030 locale baseline retained; locales=enUS+deDE+esES+esMX+frFR+itIT+koKR+ptBR+ruRU+zhCN+zhTW fallback=enUS.",
	}
	local health_bar_module = PitBull4:GetModule("HealthBar", true)
	if health_bar_module and health_bar_module.Lorenzo121StatusLine then
		table_insert(lines, health_bar_module:Lorenzo121StatusLine())
	end
	local visual_heal_module = PitBull4:GetModule("VisualHeal", true)
	if visual_heal_module and visual_heal_module.Lorenzo121StatusLine then
		table_insert(lines, visual_heal_module:Lorenzo121StatusLine())
	end
	local power_bar_module = PitBull4:GetModule("PowerBar", true)
	if power_bar_module and power_bar_module.Lorenzo121StatusLine then
		table_insert(lines, power_bar_module:Lorenzo121StatusLine())
	end
	local cooldown_module = PitBull4:GetModule("MajorCooldownAuras", true)
	if cooldown_module and cooldown_module.Lorenzo121StatusLine then
		table_insert(lines, cooldown_module:Lorenzo121StatusLine())
	end
	local important_debuffs_module = PitBull4:GetModule("ImportantDebuffs", true)
	if important_debuffs_module and important_debuffs_module.Lorenzo121StatusLine then
		table_insert(lines, important_debuffs_module:Lorenzo121StatusLine())
	end
	local dispel_highlights_module = PitBull4:GetModule("DispelHighlights", true)
	if dispel_highlights_module and dispel_highlights_module.Lorenzo121StatusLine then
		table_insert(lines, dispel_highlights_module:Lorenzo121StatusLine())
	end
	local hide_blizzard_module = PitBull4:GetModule("HideBlizzard", true)
	if hide_blizzard_module and hide_blizzard_module.Lorenzo121StatusLine then
		table_insert(lines, hide_blizzard_module:Lorenzo121StatusLine())
	end
	if PitBull4.Lorenzo121GroupGridStatusLine then
		table_insert(lines, PitBull4:Lorenzo121GroupGridStatusLine())
	end
	local range_module = PitBull4:GetModule("RangeFader", true)
	if range_module and range_module.Lorenzo121StatusLine then
		table_insert(lines, range_module:Lorenzo121StatusLine())
	end
	if self.Lorenzo121GetNativeStatusLines then
		local native_lines = self:Lorenzo121GetNativeStatusLines()
		for _, line in ipairs(native_lines) do
			table_insert(lines, line)
		end
	end
	return lines
end

local event_frame = CreateFrame("Frame")
event_frame:RegisterEvent("PLAYER_LOGIN")
event_frame:RegisterEvent("ADDON_LOADED")
event_frame:SetScript("OnEvent", function(_, event, addon_name)
	if event == "PLAYER_LOGIN" or addon_name == "Blizzard_AuraContainer" then
		PitBull4_Aura:Lorenzo121RefreshCapabilities()
		if event == "PLAYER_LOGIN" and PitBull4_Aura.UpdateAll then
			PitBull4_Aura:UpdateAll()
		end
	end
end)

PitBull4_Aura:Lorenzo121RefreshCapabilities()
