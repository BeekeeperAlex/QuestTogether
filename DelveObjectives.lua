--[[
QuestTogether Delve Objective Subsystem

This subsystem owns active Delve/scenario objective truth.
It reads Blizzard scenario APIs, sanitizes them into addon-owned state, and
publishes diff-based announcements plus title-cache inputs for nameplate logic.
]]

local QuestTogether = _G.QuestTogether

local DELVE_WIDGET_VISUAL_TYPE = Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.ScenarioHeaderDelves
	or 29

local function SafeText(value, fallback)
	return QuestTogether:SafeToString(value, fallback or "")
end

local function NormalizeNumber(value)
	local numericValue = QuestTogether:SafeToNumber(value)
	if numericValue == nil then
		return nil
	end
	return math.floor(numericValue + 0.5)
end

local function NormalizeBool(value)
	if QuestTogether:IsSecretValue(value) then
		return false
	end
	if type(value) == "boolean" then
		return value
	end
	local numericValue = QuestTogether:SafeToNumber(value)
	if numericValue ~= nil then
		return numericValue ~= 0
	end
	return false
end

local function IsNonEmptyString(value)
	return type(value) == "string" and value ~= ""
end

local function PrintOneShotDelveDebug(addon, key, message)
	if not addon or not addon.GetRuntimeFlag or not addon.SetRuntimeFlag then
		return
	end
	if addon:GetRuntimeFlag(key, false) then
		return
	end
	addon:SetRuntimeFlag(key, true)
	if addon.LogDebugLine then
		addon:LogDebugLine(SafeText(message, ""), {
			category = "delve",
		})
	elseif addon.AppendDebugLogLine then
		addon:AppendDebugLogLine(SafeText(message, ""))
	end
end

local function CopyCriteriaSnapshot(criteriaByID)
	local copy = {}
	for criteriaID, criteriaInfo in pairs(criteriaByID or {}) do
		if type(criteriaInfo) == "table" then
			copy[criteriaID] = {
				criteriaID = criteriaInfo.criteriaID,
				description = criteriaInfo.description,
				completed = criteriaInfo.completed == true,
				failed = criteriaInfo.failed == true,
				quantity = criteriaInfo.quantity,
				totalQuantity = criteriaInfo.totalQuantity,
				quantityString = criteriaInfo.quantityString,
			}
		end
	end
	return copy
end

local function CopyScenarioInfoRecord(scenarioInfo)
	if type(scenarioInfo) ~= "table" then
		return {}
	end
	return {
		isDelve = scenarioInfo.isDelve == true,
		scenarioID = scenarioInfo.scenarioID,
		scenarioName = scenarioInfo.scenarioName,
		stepID = scenarioInfo.stepID,
		stepTitle = scenarioInfo.stepTitle,
		headerText = scenarioInfo.headerText,
	}
end

local function GetScenarioHeaderInfo(addon, stepInfo)
	if type(stepInfo) ~= "table" then
		return nil
	end

	local widgetSetID = NormalizeNumber(stepInfo.widgetSetID)
	if not widgetSetID or not addon.API or type(addon.API.GetAllWidgetsBySetID) ~= "function" then
		return nil
	end

	local widgets = addon.API.GetAllWidgetsBySetID(widgetSetID)
	if type(widgets) ~= "table" then
		return nil
	end

	for index = 1, #widgets do
		local widget = widgets[index]
		if type(widget) == "table" and NormalizeNumber(widget.widgetType) == DELVE_WIDGET_VISUAL_TYPE then
			local widgetID = NormalizeNumber(widget.widgetID)
			if widgetID and addon.API.GetScenarioHeaderDelvesWidgetVisualizationInfo then
				local widgetInfo = addon.API.GetScenarioHeaderDelvesWidgetVisualizationInfo(widgetID)
				if type(widgetInfo) == "table" then
					local shownState = NormalizeNumber(widgetInfo.shownState)
					if Enum and Enum.WidgetShownState and shownState == Enum.WidgetShownState.Hidden then
						return nil
					end
					return {
						headerText = IsNonEmptyString(widgetInfo.headerText) and widgetInfo.headerText or nil,
						tierText = IsNonEmptyString(widgetInfo.tierText) and widgetInfo.tierText or nil,
						shownState = shownState,
					}
				end
			end
		end
	end

	return nil
end

local function BuildDelveScenarioRecord(addon, scenarioInfo, stepInfo, headerInfo)
	local scenarioID = scenarioInfo and NormalizeNumber(scenarioInfo.scenarioID) or nil
	local stepID = stepInfo and NormalizeNumber(stepInfo.stepID) or nil
	return {
		isDelve = true,
		scenarioID = scenarioID,
		scenarioName = scenarioInfo and IsNonEmptyString(scenarioInfo.name) and scenarioInfo.name or nil,
		stepID = stepID,
		stepTitle = stepInfo and IsNonEmptyString(stepInfo.title) and stepInfo.title or nil,
		headerText = headerInfo and IsNonEmptyString(headerInfo.headerText) and headerInfo.headerText or nil,
		tierText = headerInfo and IsNonEmptyString(headerInfo.tierText) and headerInfo.tierText or nil,
	}
end

local function GetDelveDisplayTitle(scenarioRecord)
	if type(scenarioRecord) ~= "table" then
		return "Delves"
	end
	return scenarioRecord.headerText or scenarioRecord.stepTitle or scenarioRecord.scenarioName or "Delves"
end

local function BuildDelveObjectiveProgressText(criteriaInfo)
	if type(criteriaInfo) ~= "table" then
		return "Unknown Delve Objective"
	end

	local description = SafeText(criteriaInfo.description, "Unknown Delve Objective")
	local quantityString = SafeText(criteriaInfo.quantityString, "")
	if quantityString ~= "" then
		return description .. ": " .. quantityString
	end

	local quantity = NormalizeNumber(criteriaInfo.quantity)
	local totalQuantity = NormalizeNumber(criteriaInfo.totalQuantity)
	if quantity and totalQuantity and totalQuantity > 0 then
		return string.format("%s: %d/%d", description, quantity, totalQuantity)
	end

	return description
end

local function BuildSanitizedScenarioCriteriaInfo(criteriaInfo)
	if type(criteriaInfo) ~= "table" then
		return nil
	end

	local criteriaID = NormalizeNumber(criteriaInfo.criteriaID)
	local description = IsNonEmptyString(criteriaInfo.description) and criteriaInfo.description or nil
	if not criteriaID or not description then
		return nil
	end

	local quantity = NormalizeNumber(criteriaInfo.quantity) or 0
	local totalQuantity = NormalizeNumber(criteriaInfo.totalQuantity) or 0
	local quantityString = IsNonEmptyString(criteriaInfo.quantityString) and criteriaInfo.quantityString or nil

	return {
		criteriaID = criteriaID,
		description = description,
		completed = NormalizeBool(criteriaInfo.completed),
		failed = NormalizeBool(criteriaInfo.failed),
		quantity = quantity,
		totalQuantity = totalQuantity,
		quantityString = quantityString,
	}
end

function QuestTogether:IsActiveDelveScenario()
	local scenarioInfo = self.API and self.API.GetScenarioInfo and self.API.GetScenarioInfo() or nil
	local stepInfo = self.API and self.API.GetScenarioStepInfo and self.API.GetScenarioStepInfo(nil) or nil
	local instanceInfo = self.API and self.API.GetInstanceInfo and self.API.GetInstanceInfo() or nil
	local difficultyID = instanceInfo and NormalizeNumber(instanceInfo.difficultyID) or nil

	if difficultyID == 208 then
			PrintOneShotDelveDebug(
				self,
				"debugDelveDetected",
				string.format(
					"detected source=difficulty208 scenario=%s step=%s difficulty=%s",
					SafeText(scenarioInfo and scenarioInfo.name, "<nil>"),
					SafeText(stepInfo and stepInfo.title, "<nil>"),
					SafeText(difficultyID, "<nil>")
			)
		)
		return true, scenarioInfo, stepInfo, GetScenarioHeaderInfo(self, stepInfo)
	end

	if self.API and self.API.HasActiveDelve and self.API.HasActiveDelve() then
			PrintOneShotDelveDebug(
				self,
				"debugDelveDetected",
				string.format(
					"detected source=HasActiveDelve scenario=%s step=%s difficulty=%s",
					SafeText(scenarioInfo and scenarioInfo.name, "<nil>"),
					SafeText(stepInfo and stepInfo.title, "<nil>"),
					SafeText(difficultyID, "<nil>")
			)
		)
		return true, scenarioInfo, stepInfo, GetScenarioHeaderInfo(self, stepInfo)
	end

	local headerInfo = GetScenarioHeaderInfo(self, stepInfo)
	if type(headerInfo) == "table" then
			PrintOneShotDelveDebug(
				self,
				"debugDelveDetected",
				string.format(
					"detected source=headerWidget scenario=%s step=%s header=%s difficulty=%s",
					SafeText(scenarioInfo and scenarioInfo.name, "<nil>"),
					SafeText(stepInfo and stepInfo.title, "<nil>"),
					SafeText(headerInfo.headerText, "<nil>"),
				SafeText(difficultyID, "<nil>")
			)
		)
		return true, scenarioInfo, stepInfo, headerInfo
	end

	return false, scenarioInfo, stepInfo, nil
end

function QuestTogether:RebuildDelveObjectiveStateStore()
	local delveState = self:GetDelveObjectiveStateStore()
	local byCriteriaID = delveState.byCriteriaID or {}
	local order = delveState.order or {}
	local titleCache = delveState.titleCache or {}
	local scenarioRecord = delveState.lastScenarioInfo or {}

	wipe(byCriteriaID)
	wipe(order)
	wipe(titleCache)
	wipe(scenarioRecord)

	local isDelve, scenarioInfo, stepInfo, headerInfo = self:IsActiveDelveScenario()
	if not isDelve then
		delveState.byCriteriaID = byCriteriaID
		delveState.order = order
		delveState.titleCache = titleCache
		delveState.lastScenarioInfo = scenarioRecord
		delveState.generation = (delveState.generation or 0) + 1
		return delveState
	end

	local sanitizedScenarioRecord = BuildDelveScenarioRecord(self, scenarioInfo, stepInfo, headerInfo)
	for key, value in pairs(sanitizedScenarioRecord) do
		scenarioRecord[key] = value
	end

	if IsNonEmptyString(sanitizedScenarioRecord.scenarioName) then
		titleCache[sanitizedScenarioRecord.scenarioName] = true
	end
	if IsNonEmptyString(sanitizedScenarioRecord.stepTitle) then
		titleCache[sanitizedScenarioRecord.stepTitle] = true
	end
	if IsNonEmptyString(sanitizedScenarioRecord.headerText) then
		titleCache[sanitizedScenarioRecord.headerText] = true
	end

	local numCriteria = stepInfo and NormalizeNumber(stepInfo.numCriteria) or 0
	for criteriaIndex = 1, numCriteria do
		local rawCriteriaInfo = self.API and self.API.GetScenarioCriteriaInfo and self.API.GetScenarioCriteriaInfo(criteriaIndex) or nil
		local criteriaInfo = BuildSanitizedScenarioCriteriaInfo(rawCriteriaInfo)
		if criteriaInfo then
			byCriteriaID[criteriaInfo.criteriaID] = criteriaInfo
			order[#order + 1] = criteriaInfo.criteriaID
		end
	end

	delveState.byCriteriaID = byCriteriaID
	delveState.order = order
	delveState.titleCache = titleCache
	delveState.lastScenarioInfo = scenarioRecord
	delveState.generation = (delveState.generation or 0) + 1
	local sampleTitles = {}
	for titleText in pairs(titleCache) do
		sampleTitles[#sampleTitles + 1] = titleText
	end
	table.sort(sampleTitles)
	if #sampleTitles > 3 then
		while #sampleTitles > 3 do
			table.remove(sampleTitles)
		end
	end
	PrintOneShotDelveDebug(
		self,
		"debugDelveSnapshotBuilt",
		string.format(
			"snapshot criteria=%d titles=%s scenario=%s step=%s",
			#order,
			table.concat(sampleTitles, "|"),
			SafeText(scenarioRecord.scenarioName, "<nil>"),
			SafeText(scenarioRecord.stepTitle, "<nil>")
		)
	)
	return delveState
end

function QuestTogether:RefreshDelveObjectiveStates(shouldAnnounce, reason)
	if self.IsWorkBlocked and self:IsWorkBlocked("delve_objective_refresh") then
		if shouldAnnounce then
			self:SetRuntimeFlag("pendingDelveObjectiveRefreshShouldAnnounce", true)
		end
		self:ScheduleDelveObjectiveRefresh(shouldAnnounce, nil, reason or "delve_objective_refresh")
		return false
	end

	local delveState = self:GetDelveObjectiveStateStore()
	local previousCriteriaByID = CopyCriteriaSnapshot(delveState.byCriteriaID)
	local previousScenarioInfo = CopyScenarioInfoRecord(delveState.lastScenarioInfo)

	self:RebuildDelveObjectiveStateStore()

	local currentCriteriaByID = delveState.byCriteriaID or {}
	local currentScenarioInfo = delveState.lastScenarioInfo or {}

	if shouldAnnounce then
		local previousWasDelve = previousScenarioInfo.isDelve == true
		local currentIsDelve = currentScenarioInfo.isDelve == true

		if not previousWasDelve and currentIsDelve then
			self:PublishAnnouncementEvent("DELVE_ENTERED", "Delve Entered: " .. GetDelveDisplayTitle(currentScenarioInfo))
		elseif previousWasDelve and not currentIsDelve then
			self:PublishAnnouncementEvent("DELVE_LEFT", "Left Delve: " .. GetDelveDisplayTitle(previousScenarioInfo))
		end

		for index = 1, #(delveState.order or {}) do
			local criteriaID = delveState.order[index]
			local currentCriteria = currentCriteriaByID[criteriaID]
			local previousCriteria = previousCriteriaByID[criteriaID]
			if type(currentCriteria) == "table" then
				local progressText = BuildDelveObjectiveProgressText(currentCriteria)
				if not previousCriteria then
					self:PublishAnnouncementEvent(
						"DELVE_OBJECTIVE_ENTERED",
						"Delve Objective Entered: " .. progressText,
						criteriaID
					)
				elseif currentCriteria.completed and previousCriteria.completed ~= true then
					self:PublishAnnouncementEvent(
						"DELVE_OBJECTIVE_COMPLETED",
						"Delve Objective Completed: " .. SafeText(currentCriteria.description, "Unknown Delve Objective"),
						criteriaID
					)
				elseif not currentCriteria.completed and self:ShouldPublishObjectiveProgress(currentCriteria.quantity) then
					if
						self:ShouldPublishObjectiveProgress(previousCriteria.quantity)
						and currentCriteria.quantity > previousCriteria.quantity
					then
						self:PublishAnnouncementEvent("DELVE_OBJECTIVE_PROGRESS", progressText, criteriaID)
					elseif previousCriteria.quantity ~= currentCriteria.quantity and previousCriteria.quantity == 0 then
						self:PublishAnnouncementEvent("DELVE_OBJECTIVE_PROGRESS", progressText, criteriaID)
					end
				end
			end
		end
	end

	if self.RefreshNameplatesForQuestStateChange then
		self:RefreshNameplatesForQuestStateChange(reason or "delve_objective_refresh")
	end

	return true
end

function QuestTogether:ScheduleDelveObjectiveRefresh(shouldAnnounce, delaySeconds, reason)
	if self.ScheduleDelveObjectiveRefreshWork then
		return self:ScheduleDelveObjectiveRefreshWork(shouldAnnounce, delaySeconds, reason or "ScheduleDelveObjectiveRefresh")
	end

	return self:RefreshDelveObjectiveStates(shouldAnnounce, reason or "ScheduleDelveObjectiveRefresh")
end

function QuestTogether:SCENARIO_UPDATE()
	self:ScheduleDelveObjectiveRefresh(true, nil, "SCENARIO_UPDATE")
end

function QuestTogether:SCENARIO_CRITERIA_UPDATE()
	self:ScheduleDelveObjectiveRefresh(true, nil, "SCENARIO_CRITERIA_UPDATE")
end

function QuestTogether:SCENARIO_COMPLETED()
	self:ScheduleDelveObjectiveRefresh(true, nil, "SCENARIO_COMPLETED")
end

function QuestTogether:SCENARIO_BONUS_OBJECTIVE_COMPLETE()
	self:ScheduleDelveObjectiveRefresh(true, nil, "SCENARIO_BONUS_OBJECTIVE_COMPLETE")
end

function QuestTogether:SCENARIO_CRITERIA_SHOW_STATE_UPDATE()
	self:ScheduleDelveObjectiveRefresh(true, nil, "SCENARIO_CRITERIA_SHOW_STATE_UPDATE")
end
