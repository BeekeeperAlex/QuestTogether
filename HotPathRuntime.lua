local QuestTogether = _G.QuestTogether

QuestTogether.runtimeRestrictionTypes = QuestTogether.runtimeRestrictionTypes or {
	combat = true,
	encounter = true,
	challenge = true,
	pvp = true,
}

if QuestTogether.GetDeferredWorkStateStore then
	QuestTogether.deferredWorkState = QuestTogether:GetDeferredWorkStateStore()
else
	QuestTogether.deferredWorkState = QuestTogether.deferredWorkState or {
		generations = {},
		entries = {},
	}
end

QuestTogether.runtimeWorkDelayByClass = QuestTogether.runtimeWorkDelayByClass or {
	quest_log_drain = 0,
	task_area_refresh = 0,
	quest_snapshot_refresh = 1,
	nameplate_quest_refresh = 0,
	nameplate_refresh = 0,
	nameplate_tint_refresh = 0.05,
	nameplate_tooltip_resolve = 0,
	waypoint_mutation = 0.2,
}

local function SafeText(value, fallback)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, fallback or "")
	end

	local ok, textValue = pcall(tostring, value)
	if ok then
		return textValue
	end

	return fallback or ""
end

local function BuildDeferredWorkKey(workClass, key)
	return tostring(workClass or "work") .. "::" .. tostring(key or "global")
end

function QuestTogether:IsRuntimeRestrictionTypeActive(restrictionType)
	local restrictionTypes = Enum and Enum.AddOnRestrictionType
	local restrictedActions = _G.C_RestrictedActions
	if not (restrictionTypes and restrictedActions and restrictedActions.GetAddOnRestrictionState) then
		return false
	end

	local restrictionEnum = nil
	local normalizedType = type(restrictionType) == "string" and string.lower(restrictionType) or nil
	if normalizedType == "combat" then
		restrictionEnum = restrictionTypes.Combat
	elseif normalizedType == "encounter" then
		restrictionEnum = restrictionTypes.Encounter
	elseif normalizedType == "challenge" then
		restrictionEnum = restrictionTypes.ChallengeMode
	elseif normalizedType == "pvp" then
		restrictionEnum = restrictionTypes.PvPMatch
	elseif normalizedType == "map" then
		restrictionEnum = restrictionTypes.Map
	end

	if restrictionEnum == nil then
		return false
	end

	local ok, state = pcall(restrictedActions.GetAddOnRestrictionState, restrictionEnum)
	return ok and state == 2
end

function QuestTogether:IsRuntimeRestricted()
	if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
		return true
	end

	for restrictionType in pairs(self.runtimeRestrictionTypes or {}) do
		if self:IsRuntimeRestrictionTypeActive(restrictionType) then
			return true
		end
	end

	return false
end

function QuestTogether:IsWorkBlocked(workClass)
	if workClass == "waypoint_mutation" then
		return self:IsRuntimeRestricted()
	end

	if workClass == "foreign_frame_mutation" then
		return self:IsRuntimeRestricted()
	end

	if workClass == "nameplate_tooltip_resolve" then
		return self:IsRuntimeRestricted()
	end

	if workClass == "nameplate_quest_refresh" or workClass == "nameplate_refresh" or workClass == "nameplate_tint_refresh" then
		return self:IsRuntimeRestricted()
	end

	if workClass == "quest_log_drain" or workClass == "task_area_refresh" or workClass == "quest_snapshot_refresh" then
		return self:IsRuntimeRestricted()
	end

	return self:IsRuntimeRestricted()
end

function QuestTogether:ScheduleDeferredWork(workClass, key, callback, delaySeconds, reason)
	if type(callback) ~= "function" then
		return false
	end

	local state = self.GetDeferredWorkStateStore and self:GetDeferredWorkStateStore() or self.deferredWorkState
	self.deferredWorkState = state
	local workKey = BuildDeferredWorkKey(workClass, key)
	local generation = (state.generations[workKey] or 0) + 1
	state.generations[workKey] = generation

	local entry = {
		workClass = workClass,
		key = key,
		callback = callback,
		delaySeconds = delaySeconds,
		reason = reason,
		generation = generation,
	}
	state.entries[workKey] = entry

	local delayFn = self.API and self.API.Delay
	local hasDelayFn = type(delayFn) == "function"
	local scheduledDelay = delaySeconds
	if scheduledDelay == nil then
		scheduledDelay = self.runtimeWorkDelayByClass[workClass] or 0
	end

	local function runEntry()
		local liveEntry = state.entries[workKey]
		if not liveEntry or liveEntry.generation ~= generation then
			return
		end
		if not self.isEnabled then
			return
		end
		if self:IsWorkBlocked(workClass) then
			-- Keep the latest entry parked until an explicit flush or later enqueue retries it.
			-- Immediate Delay stubs in tests would otherwise recurse indefinitely here.
			return
		end

		state.entries[workKey] = nil
		callback()
	end

	if not hasDelayFn or scheduledDelay <= 0 then
		runEntry()
		return true
	end

	delayFn(scheduledDelay, runEntry)
	return true
end

function QuestTogether:RunOrDeferWork(workClass, key, callback, delaySeconds, reason)
	if type(callback) ~= "function" then
		return false
	end

	if self:IsWorkBlocked(workClass) then
		self:ScheduleDeferredWork(workClass, key, callback, delaySeconds, reason)
		return false
	end

	callback()
	return true
end

function QuestTogether:FlushDeferredWork(reason)
	local state = self.GetDeferredWorkStateStore and self:GetDeferredWorkStateStore() or self.deferredWorkState
	self.deferredWorkState = state
	if not state or self:IsWorkBlocked("quest_log_drain") then
		return false
	end

	for workKey, entry in pairs(state.entries or {}) do
		if entry and type(entry.callback) == "function" then
			self:ScheduleDeferredWork(entry.workClass, entry.key, entry.callback, 0, reason or entry.reason)
		else
			state.entries[workKey] = nil
		end
	end

	return true
end

function QuestTogether:ADDON_RESTRICTION_STATE_CHANGED()
	self:Debug("ADDON_RESTRICTION_STATE_CHANGED()", "events")
	self:FlushDeferredWork("ADDON_RESTRICTION_STATE_CHANGED")
end

function QuestTogether:ScheduleQuestLogTaskDrain(reason)
	return self:ScheduleDeferredWork("quest_log_drain", "quest_log_drain", function()
		if self.DrainQueuedQuestLogTasks then
			local drainedCount = self:DrainQueuedQuestLogTasks()
			if drainedCount > 0 then
				self:Debugf("quest", "Drained queued quest log tasks reason=%s count=%d", SafeText(reason, ""), drainedCount)
			end
		end
	end, 0, reason or "quest_log_drain")
end

function QuestTogether:ScheduleTaskAreaRefreshWork(shouldAnnounce, delaySeconds, reason)
	if shouldAnnounce then
		if self.SetRuntimeFlag then
			self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", true)
		else
			self.pendingScheduledTaskAreaRefreshShouldAnnounce = true
		end
	end

	return self:ScheduleDeferredWork("task_area_refresh", "task_area_refresh", function()
		local announce = self.GetRuntimeFlag
			and (self:GetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false) and true or false)
			or (self.pendingScheduledTaskAreaRefreshShouldAnnounce and true or false)
		if self.SetRuntimeFlag then
			self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false)
		else
			self.pendingScheduledTaskAreaRefreshShouldAnnounce = false
		end
		if self.RefreshTaskAreaStates then
			self:RefreshTaskAreaStates(announce)
		end
	end, delaySeconds, reason or "task_area_refresh")
end

function QuestTogether:ScheduleQuestStateRefreshWork(reason, delaySeconds)
	return self:ScheduleDeferredWork("quest_snapshot_refresh", "quest_snapshot_refresh", function()
		if self.SetRuntimeFlag then
			self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
		else
			self.pendingDeferredNameplateQuestStateRefresh = false
		end
		if self.RefreshNameplatesForQuestStateChange then
			self:RefreshNameplatesForQuestStateChange(reason)
		end
	end, delaySeconds, reason or "quest_snapshot_refresh")
end

function QuestTogether:ScheduleNameplatePresentationRefresh(reason, delaySeconds)
	return self:ScheduleDeferredWork("nameplate_refresh", "visible_nameplates", function()
		if self.RefreshVisibleNameplates then
			self:RefreshVisibleNameplates(reason)
		end
	end, delaySeconds, reason or "nameplate_refresh")
end

function QuestTogether:ScheduleNameplateTooltipResolution(unitToken, unitGuid, delaySeconds, reason)
	local resolvedUnitToken = type(unitToken) == "string" and unitToken or "unknown"
	local workKey = resolvedUnitToken
	if type(unitGuid) == "string" and unitGuid ~= "" then
		workKey = unitGuid
	end

	return self:ScheduleDeferredWork("nameplate_tooltip_resolve", workKey, function()
		if not self.ResolveNameplateQuestStateForUnitToken then
			return
		end
		self:ResolveNameplateQuestStateForUnitToken(resolvedUnitToken, unitGuid, reason)
	end, delaySeconds, reason or "nameplate_tooltip_resolve")
end
