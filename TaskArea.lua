--[[
QuestTogether Task Area Subsystem

This subsystem owns task-area truth for world quests and bonus objectives.
It resolves active area state from addon-owned quest snapshots only.
All other addon code should consume the resolver snapshot or the active
world/bonus state stores exposed here.
]]

local QuestTogether = _G.QuestTogether

local function SafeText(value, fallback)
	return QuestTogether:SafeToString(value, fallback or "")
end

local function NormalizeQuestId(addon, questId)
	if not addon then
		return nil
	end

	if addon.NormalizeQuestID then
		return addon:NormalizeQuestID(questId)
	end

	local numericQuestId = addon.SafeToNumber and addon:SafeToNumber(questId) or nil
	if not numericQuestId or numericQuestId <= 0 then
		return nil
	end

	return math.floor(numericQuestId + 0.5)
end

local function CountKeys(tableValue)
	local count = 0
	for _ in pairs(tableValue or {}) do
		count = count + 1
	end
	return count
end

local function SortedQuestIdKeys(tableValue)
	local keys = {}
	for questId in pairs(tableValue or {}) do
		keys[#keys + 1] = questId
	end
	table.sort(keys, function(a, b)
		local aNum = QuestTogether:SafeToNumber(a)
		local bNum = QuestTogether:SafeToNumber(b)
		if aNum ~= nil and bNum ~= nil then
			return aNum < bNum
		end
		return SafeText(a, "") < SafeText(b, "")
	end)
	return keys
end

local function BuildQuestLogQuestInfoIndex(addon)
	local questInfoByQuestId = {}

	if not addon then
		return questInfoByQuestId
	end

	if addon.EnsureQuestSnapshotStore then
		addon:EnsureQuestSnapshotStore()
	end

	local snapshotByQuestID = addon.GetQuestSnapshotByQuestID and addon:GetQuestSnapshotByQuestID() or nil
	local snapshotOrder = addon.GetQuestSnapshotOrder and addon:GetQuestSnapshotOrder() or nil
	for index = 1, #(snapshotOrder or {}) do
		local questID = snapshotOrder[index]
		local questInfo = snapshotByQuestID and snapshotByQuestID[questID] or nil
		if questInfo and questInfo.isHidden ~= true then
			local normalizedQuestId = NormalizeQuestId(addon, questInfo.questID or questID)
			if normalizedQuestId and not questInfoByQuestId[normalizedQuestId] then
				questInfoByQuestId[normalizedQuestId] = questInfo
			end
		end
	end

	return questInfoByQuestId
end

local function BuildTaskAreaCandidateQuestIds(addon, questInfoByQuestId)
	local candidateQuestIds = {}

	for normalizedQuestId in pairs(questInfoByQuestId or {}) do
		candidateQuestIds[normalizedQuestId] = true
	end

	return candidateQuestIds
end

local function BuildActiveTaskAreaSnapshot(taskAreaState, taskType)
	local activeByQuestId = {}
	if type(taskAreaState) ~= "table" then
		return activeByQuestId
	end

	local resolvedByQuestID = taskAreaState.resolvedByQuestID or {}
	local resolutionOrder = taskAreaState.resolutionOrder or {}
	for index = 1, #resolutionOrder do
		local questId = resolutionOrder[index]
		local resolution = resolvedByQuestID[questId]
		if type(resolution) == "table" then
			if taskType == "bonus" then
				if resolution.includeBonus then
					activeByQuestId[questId] = resolution.title
				end
			elseif resolution.includeWorld then
				activeByQuestId[questId] = resolution.title
			end
		end
	end

	return activeByQuestId
end

local function ResolveQuestAreaSignals(addon, taskType, questInfo, normalizedQuestId)
	local mapFlags = questInfo and (questInfo.isOnMap == true or questInfo.hasLocalPOI == true) and true or false
	local explicitTask = questInfo and questInfo.isTask == true or false
	local explicitWorld = questInfo and questInfo.isWorldQuest == true or false
	local taskAnnouncementType = questInfo and questInfo.taskAnnouncementType or addon:GetTaskAnnouncementType(normalizedQuestId)
	local inferredBonus = taskAnnouncementType == "bonus"

	local areaActive = false
	if taskType == "world" then
		areaActive = mapFlags
	elseif mapFlags then
		areaActive = true
	elseif explicitTask and not explicitWorld and inferredBonus then
		areaActive = true
	end

	return {
		mapFlags = mapFlags,
		areaActive = areaActive and true or false,
		taskActiveForArea = false,
		canUseTaskActiveWorldFallback = false,
	}
end

local function BuildTaskAreaResolution(addon, normalizedQuestId, questInfo)
	local title = addon:GetQuestTitle(normalizedQuestId, questInfo)
	local explicitWorld = questInfo and questInfo.isWorldQuest == true or false
	local explicitTask = questInfo and questInfo.isTask == true or false
	local fallbackWorld = addon:IsWorldQuest(normalizedQuestId)
	local isWorldQuest = explicitWorld or fallbackWorld
	local explicitBonus = questInfo and questInfo.isBonusObjective == true or false
	local fallbackBonus = addon:IsBonusObjective(normalizedQuestId)
	local isBonusObjective = isWorldQuest ~= true and (explicitBonus or fallbackBonus)
	local taskAnnouncementType = isWorldQuest and "world" or (isBonusObjective and "bonus" or nil)
	local isTask = explicitTask or isWorldQuest or isBonusObjective

	local worldSignals = ResolveQuestAreaSignals(addon, "world", questInfo, normalizedQuestId)
	local bonusSignals = ResolveQuestAreaSignals(addon, "bonus", questInfo, normalizedQuestId)

	local isWorldQuestByActiveTaskFallback = false
	if not isWorldQuest and worldSignals.canUseTaskActiveWorldFallback and not isBonusObjective then
		isWorldQuest = true
		isWorldQuestByActiveTaskFallback = true
	end

	local shouldPromoteToTask = worldSignals.areaActive == true or bonusSignals.areaActive == true
	if bonusSignals.taskActiveForArea == true then
		shouldPromoteToTask = true
	end
	if not isTask and shouldPromoteToTask then
		isTask = true
	end

	local includeWorld = isTask and worldSignals.areaActive == true and isWorldQuest == true
	local includeBonus = isTask and bonusSignals.areaActive == true and isWorldQuest ~= true

	return {
		questID = normalizedQuestId,
		title = title,
		taskAnnouncementType = taskAnnouncementType,
		explicitWorld = explicitWorld,
		fallbackWorld = fallbackWorld,
		explicitTask = explicitTask,
		explicitBonus = explicitBonus,
		fallbackBonus = fallbackBonus,
		isWorldQuest = isWorldQuest and true or false,
		isBonusObjective = includeBonus or isBonusObjective,
		isTask = isTask and true or false,
		isWorldQuestByActiveTaskFallback = isWorldQuestByActiveTaskFallback,
		includeWorld = includeWorld and true or false,
		includeBonus = includeBonus and true or false,
		worldSignals = worldSignals,
		bonusSignals = bonusSignals,
	}
end

function QuestTogether:RebuildTaskAreaResolverStore()
	local taskAreaState = self.GetTaskAreaSubsystemStateStore and self:GetTaskAreaSubsystemStateStore() or nil
	if type(taskAreaState) ~= "table" then
		return nil
	end

	local resolvedByQuestID = taskAreaState.resolvedByQuestID or {}
	local resolutionOrder = taskAreaState.resolutionOrder or {}
	wipe(resolvedByQuestID)
	wipe(resolutionOrder)

	local questInfoByQuestId = BuildQuestLogQuestInfoIndex(self)
	local candidateQuestIds = BuildTaskAreaCandidateQuestIds(self, questInfoByQuestId)

	for _, normalizedQuestId in ipairs(SortedQuestIdKeys(candidateQuestIds)) do
		local questInfo = questInfoByQuestId[normalizedQuestId]
		local resolution = BuildTaskAreaResolution(self, normalizedQuestId, questInfo)
		resolvedByQuestID[normalizedQuestId] = resolution
		resolutionOrder[#resolutionOrder + 1] = normalizedQuestId
	end

	taskAreaState.resolvedByQuestID = resolvedByQuestID
	taskAreaState.resolutionOrder = resolutionOrder
	taskAreaState.generation = (taskAreaState.generation or 0) + 1
	return taskAreaState
end

function QuestTogether:GetTaskAreaSnapshot(taskType)
	local taskAreaState = self.GetTaskAreaSubsystemStateStore and self:GetTaskAreaSubsystemStateStore() or nil
	if type(taskAreaState) ~= "table" then
		return {}
	end

	local sourceState = self.GetTaskAreaStateStore and self:GetTaskAreaStateStore(taskType) or {}
	local activeByQuestId = {}
	for questId, questTitle in pairs(sourceState) do
		local normalizedQuestId = NormalizeQuestId(self, questId)
		if normalizedQuestId then
			activeByQuestId[normalizedQuestId] = questTitle
		end
	end

	return activeByQuestId
end

function QuestTogether:GetActiveWorldQuestAreaSnapshot()
	return self:GetTaskAreaSnapshot("world")
end

function QuestTogether:GetActiveBonusObjectiveAreaSnapshot()
	return self:GetTaskAreaSnapshot("bonus")
end

function QuestTogether:RefreshTaskAreaState(taskType, shouldAnnounce)
	local configByType = {
		world = {
			enterEvent = "WORLD_QUEST_ENTERED",
			leftEvent = "WORLD_QUEST_LEFT",
			enterPrefix = "World Quest Entered: ",
			leftPrefix = "Left World Quest: ",
			debugLabel = "World quest",
		},
		bonus = {
			enterEvent = "BONUS_OBJECTIVE_ENTERED",
			leftEvent = "BONUS_OBJECTIVE_LEFT",
			enterPrefix = "Bonus Objective Entered: ",
			leftPrefix = "Left Bonus Objective: ",
			debugLabel = "Bonus objective",
		},
	}

	local config = configByType[taskType]
	if not config then
		return
	end

	local taskAreaState = self.GetTaskAreaSubsystemStateStore and self:GetTaskAreaSubsystemStateStore() or nil
	local previousStateRaw = self.GetTaskAreaStateStore and self:GetTaskAreaStateStore(taskType) or {}
	local currentStateRaw = BuildActiveTaskAreaSnapshot(taskAreaState, taskType)
	local previousState = {}
	local currentState = {}

	for questId, questTitle in pairs(previousStateRaw) do
		local normalizedQuestId = NormalizeQuestId(self, questId)
		if normalizedQuestId then
			previousState[normalizedQuestId] = questTitle
		end
	end

	for questId, questTitle in pairs(currentStateRaw) do
		local normalizedQuestId = NormalizeQuestId(self, questId)
		if normalizedQuestId then
			currentState[normalizedQuestId] = questTitle
		end
	end

	if taskAreaState and self.GetTaskAreaStateStore then
		local stateStore = self:GetTaskAreaStateStore(taskType)
		wipe(stateStore)
		for questId, questTitle in pairs(currentState) do
			stateStore[questId] = questTitle
		end
	end

	for questId, questTitle in pairs(currentState) do
		if not previousState[questId] and shouldAnnounce then
			self:PublishAnnouncementEvent(config.enterEvent, config.enterPrefix .. SafeText(questTitle, "Unknown"), questId)
		end
	end

	for questId, previousTitle in pairs(previousState) do
			if not currentState[questId] then
				local wasCompleted = self.questsCompleted[questId] ~= nil
				if shouldAnnounce and not wasCompleted then
					local questTitle = previousTitle or self:GetQuestTitle(questId)
					self:PublishAnnouncementEvent(config.leftEvent, config.leftPrefix .. SafeText(questTitle, "Unknown"), questId)
				end
			end
	end

end

function QuestTogether:RefreshWorldQuestAreaState(shouldAnnounce)
	self:RefreshTaskAreaState("world", shouldAnnounce)
end

function QuestTogether:RefreshBonusObjectiveAreaState(shouldAnnounce)
	self:RefreshTaskAreaState("bonus", shouldAnnounce)
end

function QuestTogether:ScheduleTaskAreaRefresh(shouldAnnounce, delaySeconds)
	if delaySeconds ~= nil and delaySeconds <= 0 then
		delaySeconds = nil
	end

	if self.ScheduleTaskAreaRefreshWork then
		self:ScheduleTaskAreaRefreshWork(shouldAnnounce, delaySeconds, "ScheduleTaskAreaRefresh")
		return
	end

	self:RefreshTaskAreaStates(shouldAnnounce)
end

function QuestTogether:RefreshTaskAreaStates(shouldAnnounce)
	if self.IsWorkBlocked and self:IsWorkBlocked("task_area_refresh") then
		if shouldAnnounce then
			self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", true)
		end
		self:ScheduleTaskAreaRefresh(shouldAnnounce)
		return false
	end

	local pendingAnnounce = self:GetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false)
	local resolvedShouldAnnounce = shouldAnnounce or (pendingAnnounce and true or false)
	self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false)

	self:RebuildTaskAreaResolverStore()
	self:RefreshWorldQuestAreaState(resolvedShouldAnnounce)
	self:RefreshBonusObjectiveAreaState(resolvedShouldAnnounce)
	return true
end
