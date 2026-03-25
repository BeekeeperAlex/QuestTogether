local QuestTogether = _G.QuestTogether

local function NewWeakKeyTable()
	return setmetatable({}, { __mode = "k" })
end

function QuestTogether:EnsureRuntimeStateStore()
	local state = self.runtimeStateStore
	if type(state) ~= "table" then
		state = {}
		self.runtimeStateStore = state
	end

	if type(state.taskArea) ~= "table" then
		state.taskArea = {}
	end
	if type(state.taskArea.worldByQuestID) ~= "table" then
		state.taskArea.worldByQuestID = {}
	end
	if type(state.taskArea.bonusByQuestID) ~= "table" then
		state.taskArea.bonusByQuestID = {}
	end
	if state.taskArea.pendingAnnounce ~= true then
		state.taskArea.pendingAnnounce = false
	end

	if type(state.nameplate) ~= "table" then
		state.nameplate = {}
	end
	if type(state.nameplate.questStateByGuid) ~= "table" then
		state.nameplate.questStateByGuid = {}
	end
	if type(state.nameplate.questStateByUnitToken) ~= "table" then
		state.nameplate.questStateByUnitToken = {}
	end
	if type(state.nameplate.questGuidByUnitToken) ~= "table" then
		state.nameplate.questGuidByUnitToken = {}
	end
	if type(state.nameplate.titleCache) ~= "table" then
		state.nameplate.titleCache = {}
	end
	if type(state.nameplate.refreshGenerationByUnitToken) ~= "table" then
		state.nameplate.refreshGenerationByUnitToken = {}
	end
	if type(state.nameplate.refreshPendingByUnitToken) ~= "table" then
		state.nameplate.refreshPendingByUnitToken = {}
	end
	if type(state.nameplate.healthTintRefreshPendingByUnitToken) ~= "table" then
		state.nameplate.healthTintRefreshPendingByUnitToken = {}
	end
	if type(state.nameplate.healthTintRetryCountByUnitToken) ~= "table" then
		state.nameplate.healthTintRetryCountByUnitToken = {}
	end
	if type(state.nameplate.iconByUnitFrame) ~= "table" then
		state.nameplate.iconByUnitFrame = NewWeakKeyTable()
	end
	if type(state.nameplate.healthOverlayByUnitFrame) ~= "table" then
		state.nameplate.healthOverlayByUnitFrame = NewWeakKeyTable()
	end
	if type(state.nameplate.bubbleByUnitFrame) ~= "table" then
		state.nameplate.bubbleByUnitFrame = NewWeakKeyTable()
	end
	if type(state.nameplate.bubbleStateByFrame) ~= "table" then
		state.nameplate.bubbleStateByFrame = NewWeakKeyTable()
	end

	if type(state.personalBubble) ~= "table" then
		state.personalBubble = {}
	end
	if type(state.personalBubble.sliderHandlesByFrame) ~= "table" then
		state.personalBubble.sliderHandlesByFrame = NewWeakKeyTable()
	end
	if type(state.personalBubble.dialogPositionByFrame) ~= "table" then
		state.personalBubble.dialogPositionByFrame = NewWeakKeyTable()
	end

	if type(state.runtime) ~= "table" then
		state.runtime = {}
	end
	if state.runtime.pendingScheduledTaskAreaRefreshShouldAnnounce ~= true then
		state.runtime.pendingScheduledTaskAreaRefreshShouldAnnounce = false
	end
	if state.runtime.pendingDeferredNameplateQuestStateRefresh ~= true then
		state.runtime.pendingDeferredNameplateQuestStateRefresh = false
	end
	if type(state.runtime.deferredNameplateQuestStateRefreshGeneration) ~= "number" then
		state.runtime.deferredNameplateQuestStateRefreshGeneration = 0
	end
	if type(state.runtime.nameplateFullRefreshGeneration) ~= "number" then
		state.runtime.nameplateFullRefreshGeneration = 0
	end
	if type(state.runtime.deferredWorkState) ~= "table" then
		state.runtime.deferredWorkState = {}
	end
	if type(state.runtime.deferredWorkState.generations) ~= "table" then
		state.runtime.deferredWorkState.generations = {}
	end
	if type(state.runtime.deferredWorkState.entries) ~= "table" then
		state.runtime.deferredWorkState.entries = {}
	end
	if state.runtime.pendingWaypointIntent ~= nil and type(state.runtime.pendingWaypointIntent) ~= "table" then
		state.runtime.pendingWaypointIntent = nil
	end

	return state
end

function QuestTogether:GetTaskAreaStateStore(taskType)
	local state = self:EnsureRuntimeStateStore()
	if taskType == "bonus" then
		return state.taskArea.bonusByQuestID
	end
	return state.taskArea.worldByQuestID
end

function QuestTogether:ResetTaskAreaStateStore()
	local state = self:EnsureRuntimeStateStore()
	state.taskArea.worldByQuestID = {}
	state.taskArea.bonusByQuestID = {}
	state.taskArea.pendingAnnounce = false
	self:SyncLegacyRuntimeStateAliases()
	return state.taskArea
end

function QuestTogether:GetNameplateStateStore()
	return self:EnsureRuntimeStateStore().nameplate
end

function QuestTogether:ResetNameplateStateStore()
	local state = self:EnsureRuntimeStateStore()
	state.nameplate.questStateByGuid = {}
	state.nameplate.questStateByUnitToken = {}
	state.nameplate.questGuidByUnitToken = {}
	state.nameplate.titleCache = {}
	state.nameplate.refreshGenerationByUnitToken = {}
	state.nameplate.refreshPendingByUnitToken = {}
	state.nameplate.healthTintRefreshPendingByUnitToken = {}
	state.nameplate.healthTintRetryCountByUnitToken = {}
	state.nameplate.iconByUnitFrame = NewWeakKeyTable()
	state.nameplate.healthOverlayByUnitFrame = NewWeakKeyTable()
	state.nameplate.bubbleByUnitFrame = NewWeakKeyTable()
	state.nameplate.bubbleStateByFrame = NewWeakKeyTable()
	self:SyncLegacyRuntimeStateAliases()
	return state.nameplate
end

function QuestTogether:GetPersonalBubbleStateStore()
	return self:EnsureRuntimeStateStore().personalBubble
end

function QuestTogether:GetRuntimeWorkStateStore()
	return self:EnsureRuntimeStateStore().runtime
end

function QuestTogether:GetDeferredWorkStateStore()
	return self:GetRuntimeWorkStateStore().deferredWorkState
end

function QuestTogether:GetRuntimeFlag(key, fallback)
	local runtimeState = self:GetRuntimeWorkStateStore()
	local value = runtimeState[key]
	if value == nil then
		return fallback
	end
	return value
end

function QuestTogether:SetRuntimeFlag(key, value)
	local runtimeState = self:GetRuntimeWorkStateStore()
	runtimeState[key] = value
	self[key] = value
	return value
end

function QuestTogether:SetPendingWaypointIntent(intent)
	local runtimeState = self:GetRuntimeWorkStateStore()
	if type(intent) == "table" then
		runtimeState.pendingWaypointIntent = intent
	else
		runtimeState.pendingWaypointIntent = nil
	end
	self.pendingWaypointIntent = runtimeState.pendingWaypointIntent
	return runtimeState.pendingWaypointIntent
end

function QuestTogether:ResetRuntimeWorkStateStore()
	local runtimeState = self:GetRuntimeWorkStateStore()
	runtimeState.pendingWaypointIntent = nil
	runtimeState.pendingScheduledTaskAreaRefreshShouldAnnounce = false
	runtimeState.pendingDeferredNameplateQuestStateRefresh = false
	runtimeState.deferredNameplateQuestStateRefreshGeneration = 0
	runtimeState.nameplateFullRefreshGeneration = 0
	runtimeState.deferredWorkState = {
		generations = {},
		entries = {},
	}
	self:SyncLegacyRuntimeStateAliases()
	return runtimeState
end

function QuestTogether:SyncLegacyRuntimeStateAliases()
	local state = self:EnsureRuntimeStateStore()

	self.worldQuestAreaStateByQuestID = state.taskArea.worldByQuestID
	self.bonusObjectiveAreaStateByQuestID = state.taskArea.bonusByQuestID

	self.nameplateQuestTitleCache = state.nameplate.titleCache
	self.nameplateQuestStateByGuid = state.nameplate.questStateByGuid
	self.nameplateQuestStateByUnitToken = state.nameplate.questStateByUnitToken
	self.nameplateQuestGuidByUnitToken = state.nameplate.questGuidByUnitToken
	self.nameplateIconByUnitFrame = state.nameplate.iconByUnitFrame
	self.nameplateHealthOverlayByUnitFrame = state.nameplate.healthOverlayByUnitFrame
	self.nameplateBubbleByUnitFrame = state.nameplate.bubbleByUnitFrame
	self.nameplateBubbleStateByFrame = state.nameplate.bubbleStateByFrame
	self.nameplateRefreshPendingByUnitToken = state.nameplate.refreshPendingByUnitToken
	self.nameplateRefreshGenerationByUnitToken = state.nameplate.refreshGenerationByUnitToken
	self.nameplateHealthTintRefreshPendingByUnitToken = state.nameplate.healthTintRefreshPendingByUnitToken
	self.nameplateHealthTintRetryCountByUnitToken = state.nameplate.healthTintRetryCountByUnitToken

	self.personalBubbleSliderHandlesByFrame = state.personalBubble.sliderHandlesByFrame
	self.personalBubbleDialogPositionByFrame = state.personalBubble.dialogPositionByFrame

	self.pendingScheduledTaskAreaRefreshShouldAnnounce = state.runtime.pendingScheduledTaskAreaRefreshShouldAnnounce
	self.pendingDeferredNameplateQuestStateRefresh = state.runtime.pendingDeferredNameplateQuestStateRefresh
	self.deferredNameplateQuestStateRefreshGeneration = state.runtime.deferredNameplateQuestStateRefreshGeneration
	self.nameplateFullRefreshGeneration = state.runtime.nameplateFullRefreshGeneration
	self.deferredWorkState = state.runtime.deferredWorkState
	self.pendingWaypointIntent = state.runtime.pendingWaypointIntent
end

QuestTogether:EnsureRuntimeStateStore()
QuestTogether:SyncLegacyRuntimeStateAliases()
