-- ==========================================
-- INITIALIZATION & VARIABLES
-- ==========================================
local addonName, addonTable = ...

-- Default DB structure
local defaultDB = {
    settings = { locked = false, sound = 8959 },
    timers = {},      
    stopwatches = {}  
}

local alarmSounds = {
    { name = "Raid Warning", id = 8959 },
    { name = "Ready Check", id = 8960 },
    { name = "Map Ping", id = 3175 },
    { name = "LFG Role Check", id = 12811 },
    { name = "Quest Complete", id = 618 }
}

local sessionOffset = GetServerTime() - GetTime()
local function GetAbsoluteTime()
    return GetTime() + sessionOffset
end

local activeTimers = {}
local activeStopwatches = {}
local timerCounter = 0
local stopwatchCounter = 0

local function GetUniqueTimerID()
    local id
    repeat
        timerCounter = timerCounter + 1
        id = "Timer_" .. timerCounter
    until not activeTimers[id] and (not MithrilStopwatchDB or not MithrilStopwatchDB.timers[id])
    return id
end

local function GetUniqueStopwatchID()
    local id
    repeat
        stopwatchCounter = stopwatchCounter + 1
        id = "Stopwatch_" .. stopwatchCounter
    until not activeStopwatches[id] and (not MithrilStopwatchDB or not MithrilStopwatchDB.stopwatches[id])
    return id
end

-- ==========================================
-- UI STYLING TEMPLATES & SHARED ELEMENTS
-- ==========================================
local pillBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

local inputBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

local function CreateIconButton(parent, size, texture)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn:SetNormalTexture(texture)
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:HookScript("OnMouseDown", function(self)
        self:GetNormalTexture():SetPoint("TOPLEFT", 1, -1)
        self:GetNormalTexture():SetPoint("BOTTOMRIGHT", 1, -1)
    end)
    btn:HookScript("OnMouseUp", function(self)
        self:GetNormalTexture():SetPoint("TOPLEFT", 0, 0)
        self:GetNormalTexture():SetPoint("BOTTOMRIGHT", 0, 0)
    end)
    return btn
end

local function FormatTime(seconds, includeMS)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    
    if includeMS then
        local ms = math.floor((seconds * 10) % 10)
        if h > 0 then return string.format("%02d:%02d:%02d.%d", h, m, s, ms) end
        return string.format("%02d:%02d.%d", m, s, ms)
    else
        if h > 0 then return string.format("%02d:%02d:%02d", h, m, s) end
        return string.format("%02d:%02d", m, s)
    end
end

local function ParseTime(text)
    local parts = {strsplit(":", text)}
    if #parts == 3 then
        return (tonumber(parts[1]) or 0) * 3600 + (tonumber(parts[2]) or 0) * 60 + (tonumber(parts[3]) or 0)
    elseif #parts == 2 then
        return (tonumber(parts[1]) or 0) * 60 + (tonumber(parts[2]) or 0)
    else
        return tonumber(parts[1]) or 0
    end
end

local soundDropdown = CreateFrame("Frame", "MithrilSoundDropdown", UIParent, "UIDropDownMenuTemplate")
local function OnSoundSelect(self)
    MithrilStopwatchDB.settings.sound = self.value
    PlaySound(self.value, "Master") 
end

local function InitializeDropdown(self, level)
    local info = UIDropDownMenu_CreateInfo()
    local currentSound = defaultDB.settings.sound
    if MithrilStopwatchDB and MithrilStopwatchDB.settings then
        currentSound = MithrilStopwatchDB.settings.sound
    end

    for _, sound in ipairs(alarmSounds) do
        info.text = sound.name
        info.value = sound.id
        info.func = OnSoundSelect
        info.checked = (currentSound == sound.id)
        UIDropDownMenu_AddButton(info, level)
    end
end
UIDropDownMenu_Initialize(soundDropdown, InitializeDropdown)

local function HandleRightClickMenu(self, button)
    if button == "RightButton" then
        ToggleDropDownMenu(1, nil, soundDropdown, self, 0, 0)
    end
end

-- ==========================================
-- TIMER FACTORY
-- ==========================================
local function CreateTimer(savedData)
    local id = savedData and savedData.id or GetUniqueTimerID()
    local name = savedData and savedData.name or id
    
    local frame = CreateFrame("Frame", "Mithril" .. id, UIParent, "BackdropTemplate")
    frame:SetSize(180, 26)
    frame:SetBackdrop(pillBackdrop)
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    
    if savedData and savedData.x and savedData.y then
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", savedData.x, savedData.y)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -250, 20)
    end

    local tab = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tab:SetSize(150, 20)
    tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 15, -4)
    tab:SetBackdrop(pillBackdrop)
    tab:SetBackdropColor(0, 0, 0, 0.5)
    tab:EnableMouse(true)
    frame.tab = tab
    
    local title = CreateFrame("EditBox", nil, tab)
    title:SetSize(120, 20)
    title:SetPoint("CENTER", tab, "CENTER", -5, 0)
    title:SetFontObject("GameFontNormalSmall")
    title:SetText(name)
    title:SetJustifyH("CENTER")
    title:SetAutoFocus(false)
    title:EnableMouse(false)

    local function SaveTitle()
        title:ClearFocus()
        title:EnableMouse(false)
        title:HighlightText(0, 0)
        frame.name = title:GetText()
        if frame.name == "" then
            frame.name = id
            title:SetText(id)
        end
    end

    title:SetScript("OnEnterPressed", SaveTitle)
    title:SetScript("OnEscapePressed", SaveTitle)
    title:SetScript("OnEditFocusLost", SaveTitle)

    if MithrilStopwatchDB and MithrilStopwatchDB.settings and not MithrilStopwatchDB.settings.locked then 
        frame:RegisterForDrag("LeftButton") 
        tab:RegisterForDrag("LeftButton")
    end
    
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tab:SetScript("OnDragStart", function() frame:StartMoving() end)
    tab:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    frame:SetScript("OnMouseUp", HandleRightClickMenu)
    
    tab:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            ToggleDropDownMenu(1, nil, soundDropdown, self, 0, 0)
        elseif button == "LeftButton" then
            local currentTime = GetTime()
            if currentTime - (self.lastClick or 0) < 0.3 then
                title:EnableMouse(true)
                title:SetFocus()
                title:HighlightText()
            end
            self.lastClick = currentTime
        end
    end)

    local input = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    input:SetSize(62, 20)
    input:SetPoint("LEFT", frame, "LEFT", 6, 0)
    input:SetAutoFocus(false)
    input:SetFontObject("GameFontHighlightLarge")
    input:SetText("00:00")
    input:SetBackdrop(inputBackdrop)
    input:SetBackdropColor(0, 0, 0, 0.5) 
    input:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8) 
    input:SetTextInsets(4, 0, 0, 0)
    input:HookScript("OnMouseUp", HandleRightClickMenu)

    local btnClose = CreateFrame("Button", nil, tab, "UIPanelCloseButton")
    btnClose:SetSize(22, 22)
    btnClose:SetPoint("RIGHT", tab, "RIGHT", 4, 0)

    local btnPlay = CreateIconButton(frame, 26, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    btnPlay:SetPoint("RIGHT", frame, "RIGHT", -2, 0)

    local btnAdd = CreateIconButton(frame, 14, "Interface\\PaperDollInfoFrame\\Character-Plus")
    btnAdd:SetPoint("RIGHT", btnPlay, "LEFT", -2, 0)

    frame.id = id
    frame.name = name
    frame.running = savedData and savedData.running or false
    frame.endTime = savedData and savedData.endTime or 0

    local updateLoop = CreateFrame("Frame", nil, frame)
    updateLoop:Hide()
    updateLoop:SetScript("OnUpdate", function()
        local remaining = frame.endTime - GetAbsoluteTime()
        if remaining <= 0 then
            updateLoop:Hide()
            frame.running = false
            btnPlay:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            input:SetText("00:00")
            input:EnableMouse(true)
            input:SetAlpha(1)
            PlaySound(MithrilStopwatchDB.settings.sound, "Master")
        else
            input:SetText(FormatTime(remaining, false))
        end
    end)

    if frame.running then
        local remaining = frame.endTime - GetAbsoluteTime()
        if remaining > 0 then
            input:EnableMouse(false)
            input:SetAlpha(0.6)
            btnPlay:SetNormalTexture("Interface\\TimeManager\\PauseButton")
            updateLoop:Show()
        else
            frame.running = false 
        end
    end

    btnPlay:SetScript("OnClick", function()
        if frame.running then
            frame.running = false
            updateLoop:Hide()
            btnPlay:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            input:EnableMouse(true)
            input:SetAlpha(1)
        else
            local seconds = ParseTime(input:GetText())
            if seconds > 0 then
                frame.endTime = GetAbsoluteTime() + seconds
                frame.running = true
                input:EnableMouse(false)
                input:SetAlpha(0.6)
                input:ClearFocus()
                btnPlay:SetNormalTexture("Interface\\TimeManager\\PauseButton")
                updateLoop:Show()
            end
        end
    end)

    btnAdd:SetScript("OnClick", function()
        local newFrame = CreateTimer()
        newFrame:ClearAllPoints()
        newFrame:SetPoint("TOP", frame, "BOTTOM", 0, -20)
    end)

    btnClose:SetScript("OnClick", function()
        frame:Hide()
        activeTimers[frame.id] = nil
        MithrilStopwatchDB.timers[frame.id] = nil
    end)

    activeTimers[frame.id] = frame
    return frame
end

-- ==========================================
-- STOPWATCH FACTORY
-- ==========================================
local function CreateStopwatch(savedData)
    local id = savedData and savedData.id or GetUniqueStopwatchID()
    local name = savedData and savedData.name or id
    
    local frame = CreateFrame("Frame", "Mithril" .. id, UIParent, "BackdropTemplate")
    frame:SetSize(180, 26)
    frame:SetBackdrop(pillBackdrop)
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    
    if savedData and savedData.x and savedData.y then
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", savedData.x, savedData.y)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -250, -30)
    end

    local tab = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tab:SetSize(150, 20)
    tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 15, -4)
    tab:SetBackdrop(pillBackdrop)
    tab:SetBackdropColor(0, 0, 0, 0.5)
    tab:EnableMouse(true) 
    frame.tab = tab 
    
    local title = CreateFrame("EditBox", nil, tab)
    title:SetSize(120, 20)
    title:SetPoint("CENTER", tab, "CENTER", -5, 0)
    title:SetFontObject("GameFontNormalSmall")
    title:SetText(name)
    title:SetJustifyH("CENTER")
    title:SetAutoFocus(false)
    title:EnableMouse(false)

    local function SaveTitle()
        title:ClearFocus()
        title:EnableMouse(false)
        title:HighlightText(0, 0)
        frame.name = title:GetText()
        if frame.name == "" then
            frame.name = id
            title:SetText(id)
        end
    end

    title:SetScript("OnEnterPressed", SaveTitle)
    title:SetScript("OnEscapePressed", SaveTitle)
    title:SetScript("OnEditFocusLost", SaveTitle)

    if MithrilStopwatchDB and MithrilStopwatchDB.settings and not MithrilStopwatchDB.settings.locked then 
        frame:RegisterForDrag("LeftButton") 
        tab:RegisterForDrag("LeftButton")
    end
    
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tab:SetScript("OnDragStart", function() frame:StartMoving() end)
    tab:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    tab:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            local currentTime = GetTime()
            if currentTime - (self.lastClick or 0) < 0.3 then
                title:EnableMouse(true)
                title:SetFocus()
                title:HighlightText()
            end
            self.lastClick = currentTime
        end
    end)

    local display = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    display:SetPoint("LEFT", frame, "LEFT", 10, 0)
    display:SetText("00:00.0")

    local btnClose = CreateFrame("Button", nil, tab, "UIPanelCloseButton")
    btnClose:SetSize(22, 22)
    btnClose:SetPoint("RIGHT", tab, "RIGHT", 4, 0)

    local btnPlay = CreateIconButton(frame, 26, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    btnPlay:SetPoint("RIGHT", frame, "RIGHT", -2, 0)

    local btnLap = CreateIconButton(frame, 26, "Interface\\TimeManager\\ResetButton")
    btnLap:SetPoint("RIGHT", btnPlay, "LEFT", 2, 0)

    local btnAdd = CreateIconButton(frame, 14, "Interface\\PaperDollInfoFrame\\Character-Plus")
    btnAdd:SetPoint("RIGHT", btnLap, "LEFT", -2, 0)

    frame.id = id
    frame.name = name
    frame.running = savedData and savedData.running or false
    frame.elapsed = savedData and savedData.elapsed or 0
    frame.absoluteStartTime = 0

    local updateLoop = CreateFrame("Frame", nil, frame)
    updateLoop:Hide()
    updateLoop:SetScript("OnUpdate", function()
        frame.elapsed = GetAbsoluteTime() - frame.absoluteStartTime
        display:SetText(FormatTime(frame.elapsed, true))
    end)

    if frame.running then
        frame.absoluteStartTime = savedData.absoluteStartTime
        btnPlay:SetNormalTexture("Interface\\TimeManager\\PauseButton")
        updateLoop:Show()
    elseif frame.elapsed > 0 then
        display:SetText(FormatTime(frame.elapsed, true))
    end

    btnPlay:SetScript("OnClick", function()
        if frame.running then
            frame.running = false
            updateLoop:Hide()
            btnPlay:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        else
            frame.absoluteStartTime = GetAbsoluteTime() - frame.elapsed
            frame.running = true
            btnPlay:SetNormalTexture("Interface\\TimeManager\\PauseButton")
            updateLoop:Show()
        end
    end)

    btnLap:SetScript("OnClick", function()
        if not frame.running and frame.elapsed > 0 then
            frame.elapsed = 0
            display:SetText("00:00.0")
        elseif frame.running then
            print("|cFF00FF00" .. frame.name .. " Lap:|r " .. FormatTime(frame.elapsed, true))
        end
    end)

    btnAdd:SetScript("OnClick", function()
        local newFrame = CreateStopwatch()
        newFrame:ClearAllPoints()
        newFrame:SetPoint("TOP", frame, "BOTTOM", 0, -20)
    end)

    btnClose:SetScript("OnClick", function()
        frame:Hide()
        activeStopwatches[frame.id] = nil
        MithrilStopwatchDB.stopwatches[frame.id] = nil
    end)

    activeStopwatches[frame.id] = frame
    return frame
end

-- ==========================================
-- TRACKER BUTTON SETUP
-- ==========================================
local trackerBtn = CreateFrame("Button", "MithrilTrackerButton", UIParent)
trackerBtn:SetSize(20, 20)
trackerBtn:SetFrameLevel(10)
trackerBtn:SetPoint("RIGHT", ObjectiveTrackerFrame.Header.MinimizeButton, "LEFT", -30, 0)

trackerBtn.Icon = trackerBtn:CreateTexture(nil, "ARTWORK")
trackerBtn.Icon:SetAllPoints()
trackerBtn.Icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
trackerBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
trackerBtn:GetHighlightTexture():SetBlendMode("ADD")

trackerBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Mithril Stopwatch")
    GameTooltip:AddLine("Click to toggle UI", 1, 1, 1)
    GameTooltip:Show()
end)

trackerBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

trackerBtn:SetScript("OnClick", function()
    SlashCmdList["MITHRILSTOPWATCH"]("")
end)


-- ==========================================
-- DATA MANAGEMENT & EVENT HANDLING
-- ==========================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        MithrilStopwatchDB = MithrilStopwatchDB or defaultDB
        MithrilStopwatchDB.settings = MithrilStopwatchDB.settings or defaultDB.settings
        MithrilStopwatchDB.timers = MithrilStopwatchDB.timers or {}
        MithrilStopwatchDB.stopwatches = MithrilStopwatchDB.stopwatches or {}

        for id, data in pairs(MithrilStopwatchDB.timers) do
            if not data.hidden then
                CreateTimer(data)
            end
        end

        for id, data in pairs(MithrilStopwatchDB.stopwatches) do
            if not data.hidden then
                CreateStopwatch(data)
            end
        end

    elseif event == "PLAYER_LOGOUT" then
        MithrilStopwatchDB.timers = {}
        MithrilStopwatchDB.stopwatches = {}

        for id, frame in pairs(activeTimers) do
            MithrilStopwatchDB.timers[id] = {
                id = id,
                name = frame.name,
                x = frame:GetLeft(),
                y = frame:GetBottom(),
                running = frame.running,
                endTime = frame.endTime,
                hidden = not frame:IsShown()
            }
        end

        for id, frame in pairs(activeStopwatches) do
            MithrilStopwatchDB.stopwatches[id] = {
                id = id,
                name = frame.name,
                x = frame:GetLeft(),
                y = frame:GetBottom(),
                running = frame.running,
                elapsed = frame.elapsed,
                absoluteStartTime = frame.absoluteStartTime,
                hidden = not frame:IsShown()
            }
        end
    end
end)

-- ==========================================
-- SLASH COMMANDS
-- ==========================================
SLASH_MITHRILSTOPWATCH1 = "/mithril"
SLASH_MITHRILSTOPWATCH2 = "/msw"
SlashCmdList["MITHRILSTOPWATCH"] = function(msg)
    local cmd = string.lower(string.gsub(msg, "^%s*(.-)%s*$", "%1"))
    
    if cmd == "lock" then
        MithrilStopwatchDB.settings.locked = true
        for _, frame in pairs(activeTimers) do 
            frame:RegisterForDrag() 
            frame.tab:RegisterForDrag() 
        end
        for _, frame in pairs(activeStopwatches) do 
            frame:RegisterForDrag() 
            frame.tab:RegisterForDrag() 
        end
        print("Mithril Stopwatch: UI Locked")
    elseif cmd == "unlock" then
        MithrilStopwatchDB.settings.locked = false
        for _, frame in pairs(activeTimers) do 
            frame:RegisterForDrag("LeftButton") 
            frame.tab:RegisterForDrag("LeftButton") 
        end
        for _, frame in pairs(activeStopwatches) do 
            frame:RegisterForDrag("LeftButton") 
            frame.tab:RegisterForDrag("LeftButton") 
        end
        print("Mithril Stopwatch: UI Unlocked")
    elseif cmd == "reset" then
        MithrilStopwatchDB.timers = {}
        MithrilStopwatchDB.stopwatches = {}
        ReloadUI()
    else
        local anyShown = false
        for _, frame in pairs(activeTimers) do
            if frame:IsShown() then anyShown = true break end
        end
        if not anyShown then
            for _, frame in pairs(activeStopwatches) do
                if frame:IsShown() then anyShown = true break end
            end
        end

        if anyShown then
            for _, frame in pairs(activeTimers) do frame:Hide() end
            for _, frame in pairs(activeStopwatches) do frame:Hide() end
        else
            local count = 0
            for _, frame in pairs(activeTimers) do frame:Show() count = count + 1 end
            for _, frame in pairs(activeStopwatches) do frame:Show() count = count + 1 end
            
            if count == 0 then
                CreateTimer()
                CreateStopwatch()
            end
        end
    end
end