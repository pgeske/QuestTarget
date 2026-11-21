-- QuestTarget: right-click a quest or objective in Questie's tracker and pick
-- "Set as macro target". One character macro, "QuestTarget", then targets the
-- mobs and NPCs that quest needs. Drag it to an action bar once; it keeps
-- itself up to date as objectives finish, and points at the turn-in NPC once
-- the quest is complete.

local ADDON_NAME = ...
local MACRO_NAME = "QuestTarget"
local MACRO_ICON = 134400 -- INV_Misc_QuestionMark
local MAX_MACRO_LENGTH = 255
local MENU_TEXT = "Set as |cFF39c0edmacro target|r"
local CHAT_PREFIX = "|cFF39c0edQuestTarget|r: "
local EMPTY_MACRO_BODY = '/run print("QuestTarget: nothing to target. Right-click a quest in Questie\'s tracker.")'
-- A /targetexact can land on a corpse; dropping it keeps the button from re-selecting loot.
local MACRO_FOOTER = "/cleartarget [dead]"

local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
local DistanceUtils = QuestieLoader:ImportModule("DistanceUtils")
local TrackerMenu = QuestieLoader:ImportModule("TrackerMenu")
local LibDropDown = LibStub:GetLibrary("LibUIDropDownMenuQuestie-4.0")

-- Saved per character: { questId = number, objectiveIndex = number|nil }.
-- A nil objectiveIndex means "every unfinished objective of the quest".
QuestTargetDB = QuestTargetDB or {}

local pendingRefreshAfterCombat = false

local function Print(message)
    print(CHAT_PREFIX .. message)
end

---@param quest table Questie quest object
---@param objectiveIndex number
local function FindObjective(quest, objectiveIndex)
    for _, objective in pairs(quest.Objectives or {}) do
        if objective.Index == objectiveIndex then
            return objective
        end
    end
    -- Questie gives special objectives indices from 65 up, so they never clash with regular ones.
    for _, objective in pairs(quest.SpecialObjectives or {}) do
        if objective.Index == objectiveIndex then
            return objective
        end
    end
end

-- Records a creature, keeping its nearest spawn when several sources share a name.
local function AddTarget(distanceByName, name, spawns)
    local _, _, distance = DistanceUtils.GetNearestSpawn(spawns or {})
    distance = distance or math.huge
    if not distanceByName[name] or distance < distanceByName[name] then
        distanceByName[name] = distance
    end
end

-- Adds every creature an objective needs (to kill, to loot an item from, or to talk to).
-- Game objects are skipped: macros can't target them.
local function AddObjectiveTargets(objective, distanceByName)
    if objective.Completed then
        return
    end
    for _, spawn in pairs(objective.spawnList or {}) do
        local isCreature = spawn.TooltipKey and spawn.TooltipKey:sub(1, 2) == "m_"
        if isCreature and spawn.Name then
            AddTarget(distanceByName, spawn.Name, spawn.Spawns)
        end
    end
end

local function AddFinisherTargets(quest, distanceByName)
    for _, npcId in pairs(quest.Finisher and quest.Finisher.NPC or {}) do
        local npc = QuestieDB:GetNPC(npcId)
        if npc and npc.name then
            AddTarget(distanceByName, npc.name, npc.spawns)
        end
    end
end

-- Returns the creature names to target for the saved selection, nearest first.
local function CollectTargetNames(selection)
    local quest = selection.questId and QuestieDB.GetQuest(selection.questId)
    if not quest then
        return {}
    end

    local distanceByName = {}
    if quest:IsComplete() == 1 then
        AddFinisherTargets(quest, distanceByName)
    else
        local chosen = selection.objectiveIndex and FindObjective(quest, selection.objectiveIndex)
        if chosen and not chosen.Completed then
            AddObjectiveTargets(chosen, distanceByName)
        else
            -- Whole-quest selection, or the chosen objective is done: target what's left.
            for _, objective in pairs(quest.Objectives or {}) do
                AddObjectiveTargets(objective, distanceByName)
            end
            for _, objective in pairs(quest.SpecialObjectives or {}) do
                AddObjectiveTargets(objective, distanceByName)
            end
        end
    end

    local names = {}
    for name in pairs(distanceByName) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b) return distanceByName[a] < distanceByName[b] end)
    return names
end

-- Builds a macro body that fits the 255-character limit, keeping the nearest names.
local function BuildMacroBody(namesNearestFirst)
    local lines = {}
    local length = #MACRO_FOOTER
    for _, name in ipairs(namesNearestFirst) do
        local line = "/targetexact " .. name
        if length + #line + 1 > MAX_MACRO_LENGTH then
            break
        end
        table.insert(lines, line)
        length = length + #line + 1
    end
    if #lines == 0 then
        return EMPTY_MACRO_BODY
    end

    -- Each /targetexact that finds someone replaces the target, so the nearest name goes last and wins.
    local body = {}
    for i = #lines, 1, -1 do
        table.insert(body, lines[i])
    end
    table.insert(body, MACRO_FOOTER)
    return table.concat(body, "\n")
end

local function WriteMacro(body)
    local macroIndex = GetMacroIndexByName(MACRO_NAME)
    if macroIndex > 0 then
        EditMacro(macroIndex, MACRO_NAME, MACRO_ICON, body)
        return
    end
    local _, characterMacroCount = GetNumMacros()
    if characterMacroCount >= (MAX_CHARACTER_MACROS or 18) then
        Print("your character macro slots are full. Delete one so QuestTarget can create its macro.")
        return
    end
    CreateMacro(MACRO_NAME, MACRO_ICON, body, true)
    Print("created the |cFFFFFFFF" .. MACRO_NAME .. "|r macro. Open /macro, Character Specific tab, and drag it to your bar.")
end

-- Macros can't be edited in combat; the refresh then waits for combat to end.
local function RefreshMacro()
    if InCombatLockdown() then
        pendingRefreshAfterCombat = true
        return
    end
    WriteMacro(BuildMacroBody(CollectTargetNames(QuestTargetDB)))
end

local function SetSelection(questId, objectiveIndex, label)
    QuestTargetDB.questId = questId
    QuestTargetDB.objectiveIndex = objectiveIndex
    RefreshMacro()
    Print("now targeting " .. label .. ".")
end

local function ClearSelection()
    QuestTargetDB.questId = nil
    QuestTargetDB.objectiveIndex = nil
    RefreshMacro()
end

-- Questie builds its tracker menus on every right-click from these module functions,
-- so wrapping them adds our entry to each quest and objective menu.
local originalAddShowObjectivesOnMapOption = TrackerMenu.addShowObjectivesOnMapOption
TrackerMenu.addShowObjectivesOnMapOption = function(menu, quest, objective)
    originalAddShowObjectivesOnMapOption(menu, quest, objective)
    table.insert(menu, {
        text = MENU_TEXT,
        func = function()
            LibDropDown:CloseDropDownMenus()
            SetSelection(quest.Id, objective.Index, '"' .. (objective.Description or "objective") .. '"')
        end,
    })
end

local originalMinMaxQuestOption = TrackerMenu.minMaxQuestOption
TrackerMenu.minMaxQuestOption = function(menu, quest)
    table.insert(menu, {
        text = MENU_TEXT,
        func = function()
            LibDropDown:CloseDropDownMenus()
            SetSelection(quest.Id, nil, "everything for " .. (quest.name or "this quest"))
        end,
    })
    originalMinMaxQuestOption(menu, quest)
end

Questie.API.RegisterForQuestUpdates(function(questId, _, triggerReason)
    if questId ~= QuestTargetDB.questId then
        return
    end
    local reasons = Questie.API.Enums.QuestUpdateTriggerReason
    if triggerReason == reasons.QUEST_TURNED_IN or triggerReason == reasons.QUEST_ABANDONED then
        ClearSelection()
    else
        RefreshMacro()
    end
end)

local function OnAddonLoaded()
    QuestTargetDB = QuestTargetDB or {}
    -- Questie fills in quest objectives some time after login, so the first refresh waits for it.
    Questie.API.RegisterOnReady(function()
        if QuestTargetDB.questId then
            RefreshMacro()
        end
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Distances change with the zone, so the nearest names are picked again.
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == ADDON_NAME then
            eventFrame:UnregisterEvent("ADDON_LOADED")
            OnAddonLoaded()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRefreshAfterCombat then
            pendingRefreshAfterCombat = false
            RefreshMacro()
        end
    elseif QuestTargetDB.questId then
        RefreshMacro()
    end
end)

SLASH_QUESTTARGET1 = "/questtarget"
SLASH_QUESTTARGET2 = "/qtarget"
SlashCmdList.QUESTTARGET = function(argument)
    if strtrim(argument or ""):lower() == "clear" then
        ClearSelection()
        Print("cleared.")
    else
        RefreshMacro()
        Print("macro refreshed. Use |cFFFFFFFF/qtarget clear|r to stop targeting.")
    end
end
