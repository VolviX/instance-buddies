-- InstanceBuddies - World of Warcraft Classic Era Addon
-- Tracks instance runs with group members for shared history analysis
-- Author: VolviX 
-- Contact: (Discord: cembingol, X: cembingool, In-game: Maddjones-Soulseeker)

InstanceBuddies = {}
local IB = InstanceBuddies

-- Global state variables
IB.inInstance = false       -- Tracks if player is currently in an instance
IB.currentRun = nil         -- Active run data while in instance

-- UI pagination settings
IB.currentPage = 1
IB.entriesPerPage = 10

-- Search functionality
IB.searchTerm = ""          -- Current search query
IB.filteredRuns = nil       -- Cached search results

-- Performance optimization throttles
local recordGroupInfoThrottle = 0    -- Prevents spam recording of group changes
local searchDebounceTimer = nil      -- Delays search execution for better UX

-- Main UI Frame
function IB:CreateMainFrame()
    if self.mainFrame then 
        if self.mainFrame:IsShown() then
            self:CleanupTooltips()  -- Prevent memory leaks
            self.mainFrame:Hide()
        else
            self.currentPage = 1    -- Reset pagination on reopen
            self:UpdateMainFrame()
            self.mainFrame:Show()
        end
        return 
    end
    
    -- Main window setup
    local frame = CreateFrame("Frame", "InstanceBuddiesMainFrame", UIParent)
    frame:SetSize(825, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Instance Buddies")
    title:SetTextColor(1, 1, 1)
    
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(60, 25)
    closeBtn:SetPoint("TOPRIGHT", -15, -15)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() 
        IB:CleanupTooltips()  -- Essential for memory management
        frame:Hide() 
    end)
    
    -- Party history section - shows shared runs with current group members
    local partySection = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partySection:SetPoint("TOP", 0, -45)
    partySection:SetWidth(800)
    partySection:SetJustifyH("CENTER")
    partySection:SetTextColor(0.8, 0.8, 1)
    
    -- Tooltip infrastructure for detailed shared history
    local tooltip = CreateFrame("Frame", nil, frame)
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetSize(500, 300)  -- Dynamic sizing applied later
    tooltip:Hide()
    
    local tooltipBg = tooltip:CreateTexture(nil, "BACKGROUND")
    tooltipBg:SetAllPoints()
    tooltipBg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    
    local tooltipBorder = tooltip:CreateTexture(nil, "BORDER")
    tooltipBorder:SetAllPoints()
    tooltipBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
    tooltipBorder:SetPoint("TOPLEFT", -1, 1)
    tooltipBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    
    local tooltipContent = CreateFrame("Frame", nil, tooltip)
    tooltipContent:SetPoint("TOPLEFT", 5, -5)
    tooltipContent:SetPoint("BOTTOMRIGHT", -5, 5)
    
    tooltip.content = tooltipContent
    tooltip.rows = {}
    
    -- Search functionality
    local searchFrame = CreateFrame("Frame", nil, frame)
    searchFrame:SetPoint("TOPLEFT", 15, -70)
    searchFrame:SetPoint("TOPRIGHT", -15, -70)
    searchFrame:SetHeight(30)
    
    local searchLabel = searchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("LEFT", 0, 0)
    searchLabel:SetText("Search")
    searchLabel:SetTextColor(0.7, 0.7, 0.7)
    
    local searchBox = CreateFrame("EditBox", nil, searchFrame, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetText(IB.searchTerm)
    
    -- Scrollable content area for run history
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", 15, -105)
    scrollFrame:SetPoint("BOTTOMRIGHT", -15, 80)  -- Space reserved for pagination/contact
    
    local contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(scrollFrame:GetWidth(), 1)  -- Height calculated dynamically
    scrollFrame:SetScrollChild(contentFrame)
    
    -- Contact information
    local contactText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contactText:SetPoint("BOTTOMLEFT", 15, 47)
    contactText:SetPoint("BOTTOMRIGHT", -15, 47)
    contactText:SetJustifyH("CENTER")
    contactText:SetText("For bug reports and feature requests, please contact me via:\n Discord (cembingol), X (cembingool), or in-game (Maddjones-Soulseeker)\n\n <3")
    contactText:SetTextColor(0.7, 0.7, 0.7)
    
    -- Pagination controls
    local paginationFrame = CreateFrame("Frame", nil, frame)
    paginationFrame:SetPoint("BOTTOMLEFT", 15, 15)
    paginationFrame:SetPoint("BOTTOMRIGHT", -15, 15)
    paginationFrame:SetHeight(30)
    
    local prevBtn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    prevBtn:SetSize(100, 25)
    prevBtn:SetPoint("LEFT", 0, 0)
    prevBtn:SetText("Previous Page")
    prevBtn:SetScript("OnClick", function()
        if IB.currentPage > 1 then
            IB.currentPage = IB.currentPage - 1
            IB:UpdateMainFrame()
        end
    end)
    
    local nextBtn = CreateFrame("Button", nil, paginationFrame, "UIPanelButtonTemplate")
    nextBtn:SetSize(100, 25)
    nextBtn:SetPoint("RIGHT", 0, 0)
    nextBtn:SetText("Next Page")
    nextBtn:SetScript("OnClick", function()
        -- Safe database access with fallback
        local runs = IB.filteredRuns or (InstanceBuddiesDB and InstanceBuddiesDB.runs) or {}
        local totalRuns = #runs
        local totalPages = math.ceil(totalRuns / IB.entriesPerPage)
        if IB.currentPage < totalPages then
            IB.currentPage = IB.currentPage + 1
            IB:UpdateMainFrame()
        end
    end)
    
    local pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageText:SetPoint("BOTTOM", 0, 15)
    pageText:SetTextColor(1, 1, 1)
    
    -- Enable dragging for better UX
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    -- Store UI components for later access
    frame.scrollFrame = scrollFrame
    frame.contentFrame = contentFrame
    frame.runRows = {}
    frame.paginationFrame = paginationFrame
    frame.prevBtn = prevBtn
    frame.nextBtn = nextBtn
    frame.pageText = pageText
    frame.partySection = partySection
    frame.tooltip = tooltip
    frame.searchBox = searchBox
    frame.searchFrame = searchFrame
    self.mainFrame = frame
    
    -- Search with debouncing to prevent excessive filtering during typing
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            IB.searchTerm = self:GetText()
            
            -- Clean up previous timer to prevent memory leaks
            if searchDebounceTimer then
                searchDebounceTimer:SetScript("OnUpdate", nil)
                searchDebounceTimer:Hide()
                searchDebounceTimer = nil
            end
            
            -- Delay search execution for better performance
            searchDebounceTimer = CreateFrame("Frame")
            local startTime = GetTime()
            searchDebounceTimer:SetScript("OnUpdate", function(timerFrame)
                if GetTime() - startTime >= 0.3 then -- 300ms delay
                    IB:PerformSearch()
                    timerFrame:SetScript("OnUpdate", nil)
                    timerFrame:Hide()
                end
            end)
        end
    end)
    
    -- Enable ESC key to close window
    table.insert(UISpecialFrames, "InstanceBuddiesMainFrame")
    
    self:PerformSearch()  -- Initialize with current data
    frame:Show()
end

-- Returns class-appropriate color codes for character names
function IB:GetClassColor(class)
    local colors = {
        WARRIOR = "|cFFC79C6E",
        PALADIN = "|cFFF58CBA", 
        HUNTER = "|cFFABD473",
        ROGUE = "|cFFFFF569",
        PRIEST = "|cFFFFFFFF",
        SHAMAN = "|cFF0070DE",
        MAGE = "|cFF69CCF0",
        WARLOCK = "|cFF9482C9",
        DRUID = "|cFFFF7D0A"
    }
    return colors[class] or "|cFFFFFFFF"
end

-- Converts server timestamps to human-readable relative time strings
function IB:FormatTimestamp(timestamp)
    if not timestamp then return "|cFFFFFF00Unknown|r" end
    
    local currentTime = GetServerTime()
    local timeDiff = currentTime - timestamp
    
    local dateTable = date("*t", timestamp)
    local currentDate = date("*t", currentTime)
    
    local timeStr = string.format("%02d:%02d", dateTable.hour, dateTable.min)
    
    -- Today
    if dateTable.yday == currentDate.yday and dateTable.year == currentDate.year then
        return "|cFFFFFF00Today " .. timeStr .. "|r"
    -- Yesterday (handles year boundaries correctly)
    elseif timeDiff < 86400 * 2 then
        local yesterdayTime = currentTime - 86400
        local yesterdayDate = date("*t", yesterdayTime)
        if dateTable.yday == yesterdayDate.yday and dateTable.year == yesterdayDate.year then
            return "|cFFFFFF00Yesterday " .. timeStr .. "|r"
        end
    end
    -- This week
    if timeDiff < 86400 * 7 then
        local dayName = date("%A", timestamp)
        return "|cFFFFFF00" .. dayName .. " " .. timeStr .. "|r"
    -- Older dates
    else
        return "|cFFFFFF00" .. date("%d.%m.%Y", timestamp) .. " " .. timeStr .. "|r"
    end
end

-- Converts group data hash table to sorted array for consistent display order
function IB:GetSortedGroupMembers(groupData)
    if not groupData then return {} end
    
    local members = {}
    for name, data in pairs(groupData) do
        if name ~= UnitName("player") then -- Exclude player from group list
            table.insert(members, {
                name = name,
                level = data.level or 0,
                class = data.classEnglish or "UNKNOWN",
                partySlot = data.partySlot or 999 -- High value sorts unknown slots last
            })
        end
    end
    
    -- Sort by party slot first (maintains party1-4 order), then level, then name
    table.sort(members, function(a, b)
        if a.partySlot == b.partySlot then
            if a.level == b.level then
                return a.name < b.name
            end
            return a.level > b.level
        end
        return a.partySlot < b.partySlot
    end)
    
    return members
end

-- Get current party/raid members (excluding player)
function IB:GetCurrentGroupMembers()
    local members = {}
    
    if IsInRaid() then
        -- Handle raid groups
        for i = 1, 40 do
            local name = UnitName("raid" .. i)
            local class, classEnglish = UnitClass("raid" .. i)
            if name and name ~= "Unknown" and name ~= UnitName("player") then
                table.insert(members, {
                    name = name,
                    class = classEnglish or "UNKNOWN"
                })
            end
        end
    elseif IsInGroup() then
        -- Handle party groups
        for i = 1, 5 do
            local name = UnitName("party" .. i)
            local class, classEnglish = UnitClass("party" .. i)
            if name and name ~= "Unknown" and name ~= UnitName("player") then
                table.insert(members, {
                    name = name,
                    class = classEnglish or "UNKNOWN"
                })
            end
        end
    end
    
    return members
end

-- Analyzes current group members against dungeon history to find shared runs
function IB:GetGroupDungeonHistory()
    local currentMembers = self:GetCurrentGroupMembers()
    if #currentMembers == 0 then
        return nil -- No group or empty group
    end
    
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs then
        return nil
    end
    
    -- Initialize counters for each current group member
    local memberCounts = {}
    for _, member in ipairs(currentMembers) do
        memberCounts[member.name] = {
            count = 0,
            class = member.class
        }
    end
    
    -- Count historical runs for each current member
    for _, run in ipairs(InstanceBuddiesDB.runs) do
        if run.groupData then
            for memberName, _ in pairs(run.groupData) do
                if memberCounts[memberName] then
                    memberCounts[memberName].count = memberCounts[memberName].count + 1
                end
            end
        end
    end
    
    -- Build result array (only members with shared history)
    local history = {}
    for name, data in pairs(memberCounts) do
        if data.count > 0 then
            table.insert(history, {
                name = name,
                count = data.count,
                class = data.class
            })
        end
    end
    
    -- Sort by run count (most runs first), then alphabetically
    table.sort(history, function(a, b)
        if a.count == b.count then
            return a.name < b.name
        end
        return a.count > b.count
    end)
    
    return history
end

-- Retrieves detailed shared run data for tooltip display (limited to last 20)
function IB:GetSharedRunsForTooltip()
    local currentMembers = self:GetCurrentGroupMembers()
    if #currentMembers == 0 then
        return {}
    end
    
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs then
        return {}
    end
    
    -- Create lookup table for faster searching
    local currentMemberNames = {}
    for _, member in ipairs(currentMembers) do
        currentMemberNames[member.name] = member.class
    end
    
    -- Find runs containing any current group member
    local sharedRuns = {}
    for _, run in ipairs(InstanceBuddiesDB.runs) do
        if run.groupData then
            local runMembers = {}
            for memberName, _ in pairs(run.groupData) do
                if currentMemberNames[memberName] then
                    table.insert(runMembers, {
                        name = memberName,
                        class = currentMemberNames[memberName]
                    })
                end
            end
            
            if #runMembers > 0 then
                table.insert(sharedRuns, {
                    instanceName = run.instanceName,
                    enteredTime = run.enteredTime,
                    sharedMembers = runMembers
                })
            end
        end
    end
    
    -- Limit results to prevent tooltip overflow
    local maxRuns = 20
    if #sharedRuns > maxRuns then
        local limitedRuns = {}
        for i = 1, maxRuns do
            table.insert(limitedRuns, sharedRuns[i])
        end
        sharedRuns = limitedRuns
    end
    
    return sharedRuns
end

-- Show the shared runs tooltip
function IB:ShowPartyTooltip()
    if not self.mainFrame or not self.mainFrame.tooltip then return end
    
    local tooltip = self.mainFrame.tooltip
    local sharedRuns = self:GetSharedRunsForTooltip()
    
    if #sharedRuns == 0 then return end
    
    -- Properly destroy existing tooltip rows to prevent memory leaks
    for _, row in pairs(tooltip.rows) do
        row:Hide()
        row:SetParent(nil)
        row:ClearAllPoints()
    end
    tooltip.rows = {}
    
    -- Add title
    local title = tooltip.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Shared Dungeon History")
    title:SetTextColor(1, 1, 0.5) -- Yellow title
    table.insert(tooltip.rows, title)
    
    local yOffset = -25
    local rowHeight = 16
    
    -- Add each shared run
    for i, run in ipairs(sharedRuns) do
        local row = tooltip.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 5, yOffset)
        row:SetJustifyH("LEFT")
        
        -- Build member list with class colors
        local memberParts = {}
        for _, member in ipairs(run.sharedMembers) do
            local classColor = self:GetClassColor(member.class)
            table.insert(memberParts, string.format("%s%s|r", classColor, member.name))
        end
        
        -- Format: "Today 15:23 - Maraudon - with PlayerX, PlayerY"
        local timeStr = self:FormatTimestamp(run.enteredTime)
        local memberStr = table.concat(memberParts, ", ")
        local text = string.format("%s - |cFF00BFFF%s|r - with %s", 
            timeStr, run.instanceName or "Unknown", memberStr)
        
        row:SetText(text)
        row:SetTextColor(1, 1, 1)
        table.insert(tooltip.rows, row)
        
        yOffset = yOffset - rowHeight
    end
    
    -- Calculate tooltip size
    local width = 500
    local height = math.abs(yOffset) + 15 -- Add some padding
    height = math.min(height, 400) -- Cap maximum height
    height = math.max(height, 80)  -- Minimum height
    
    tooltip:SetSize(width, height)
    
    -- Clear any existing positioning
    tooltip:ClearAllPoints()
    
    -- Position tooltip near cursor but keep on screen
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x = x / scale
    y = y / scale
    
    -- Adjust position to keep tooltip on screen
    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()
    
    if x + width > screenWidth then
        x = screenWidth - width - 10
    end
    if y - height < 0 then
        y = height + 10
    end
    
    tooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 10, y - 10)
    tooltip:Show()
end

-- Hide the shared runs tooltip
function IB:HidePartyTooltip()
    if not self.mainFrame or not self.mainFrame.tooltip then return end
    
    local tooltip = self.mainFrame.tooltip
    tooltip:Hide()
    tooltip:ClearAllPoints() -- Clear positioning for next show
end

-- Show the group members tooltip for truncated lists
function IB:ShowGroupMembersTooltip(members, anchorFrame)
    if not self.mainFrame or not members or #members == 0 then return end
    
    -- Create or reuse group tooltip
    if not self.mainFrame.groupTooltip then
        local tooltip = CreateFrame("Frame", nil, self.mainFrame)
        tooltip:SetFrameStrata("TOOLTIP")
        tooltip:Hide()
        
        -- Tooltip background
        local tooltipBg = tooltip:CreateTexture(nil, "BACKGROUND")
        tooltipBg:SetAllPoints()
        tooltipBg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
        
        -- Tooltip border
        local tooltipBorder = tooltip:CreateTexture(nil, "BORDER")
        tooltipBorder:SetAllPoints()
        tooltipBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
        tooltipBorder:SetPoint("TOPLEFT", -1, 1)
        tooltipBorder:SetPoint("BOTTOMRIGHT", 1, -1)
        
        -- Tooltip content frame
        local tooltipContent = CreateFrame("Frame", nil, tooltip)
        tooltipContent:SetPoint("TOPLEFT", 5, -5)
        tooltipContent:SetPoint("BOTTOMRIGHT", -5, 5)
        
        tooltip.content = tooltipContent
        tooltip.rows = {}
        self.mainFrame.groupTooltip = tooltip
    end
    
    local tooltip = self.mainFrame.groupTooltip
    
    -- Properly destroy existing tooltip rows to prevent memory leaks
    for _, row in pairs(tooltip.rows) do
        row:Hide()
        row:SetParent(nil)
        row:ClearAllPoints()
    end
    tooltip.rows = {}
    
    -- Add title
    local title = tooltip.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Group Members")
    title:SetTextColor(1, 1, 0.5) -- Yellow title
    table.insert(tooltip.rows, title)
    
    local yOffset = -25
    local rowHeight = 16
    
    -- Add each group member
    for _, member in ipairs(members) do
        local row = tooltip.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row:SetPoint("TOPLEFT", 5, yOffset)
        row:SetJustifyH("LEFT")
        
        -- Format: "54 PlayerName" with class color
        local classColor = self:GetClassColor(member.class)
        local text = string.format("|cFF888888%d|r %s%s|r", member.level, classColor, member.name)
        
        row:SetText(text)
        row:SetTextColor(1, 1, 1)
        table.insert(tooltip.rows, row)
        
        yOffset = yOffset - rowHeight
    end
    
    -- Calculate tooltip size
    local width = 200
    local height = math.abs(yOffset) + 15 -- Add some padding
    height = math.max(height, 60)  -- Minimum height
    
    tooltip:SetSize(width, height)
    
    -- Clear any existing positioning
    tooltip:ClearAllPoints()
    
    -- Position tooltip near cursor but keep on screen
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x = x / scale
    y = y / scale
    
    -- Adjust position to keep tooltip on screen
    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()
    
    if x + width > screenWidth then
        x = screenWidth - width - 10
    end
    if y - height < 0 then
        y = height + 10
    end
    
    tooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 10, y - 10)
    tooltip:Show()
end

-- Hide the group members tooltip
function IB:HideGroupMembersTooltip()
    if not self.mainFrame or not self.mainFrame.groupTooltip then return end
    
    local tooltip = self.mainFrame.groupTooltip
    tooltip:Hide()
    tooltip:ClearAllPoints() -- Clear positioning for next show
end

-- Multi-keyword search across instance names, player names, and group members
function IB:FilterRuns(searchTerm)
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs then
        return {}
    end
    
    if not searchTerm or searchTerm == "" then
        return InstanceBuddiesDB.runs
    end
    
    -- Split search into individual keywords for AND logic
    local keywords = {}
    for keyword in string.gmatch(string.lower(searchTerm), "%S+") do
        table.insert(keywords, keyword)
    end
    
    if #keywords == 0 then
        return InstanceBuddiesDB.runs
    end
    
    local filteredRuns = {}
    
    -- Each run must match ALL keywords to be included
    for _, run in ipairs(InstanceBuddiesDB.runs) do
        local matchesAll = true
        
        for _, keyword in ipairs(keywords) do
            local foundMatch = false
            
            -- Search in instance name
            if run.instanceName and string.find(string.lower(run.instanceName), keyword, 1, true) then
                foundMatch = true
            end
            
            -- Search in main player name
            if not foundMatch and run.playerName and string.find(string.lower(run.playerName), keyword, 1, true) then
                foundMatch = true
            end
            
            -- Search in group member names
            if not foundMatch and run.groupData then
                for memberName, _ in pairs(run.groupData) do
                    if string.find(string.lower(memberName), keyword, 1, true) then
                        foundMatch = true
                        break
                    end
                end
            end
            
            -- Fail if this keyword wasn't found anywhere in this run
            if not foundMatch then
                matchesAll = false
                break
            end
        end
        
        if matchesAll then
            table.insert(filteredRuns, run)
        end
    end
    
    return filteredRuns
end

-- Executes search and refreshes UI (called after debounce delay)
function IB:PerformSearch()
    self.filteredRuns = self:FilterRuns(self.searchTerm)
    self.currentPage = 1 -- Reset to first page when search changes
    self:UpdateMainFrame()
end

-- Update the current party section
function IB:UpdatePartySection()
    if not self.mainFrame or not self.mainFrame.partySection then return end
    
    local history = self:GetGroupDungeonHistory()
    local partySection = self.mainFrame.partySection
    
    -- First, clear any existing hover handlers
    partySection:SetScript("OnEnter", nil)
    partySection:SetScript("OnLeave", nil)
    partySection:EnableMouse(false)
    
    if not history then
        -- Not in a group
        partySection:SetText("Join a group to see your dungeon history with them!")
    elseif #history == 0 then
        -- In a group but no shared history
        partySection:SetText("No shared dungeon history with your current party members.")
    else
        -- Has shared history - build the message
        local historyParts = {}
        for _, member in ipairs(history) do
            local classColor = self:GetClassColor(member.class)
            local runText = member.count == 1 and "run" or "runs"
            table.insert(historyParts, string.format("%d %s with %s%s|r", 
                member.count, runText, classColor, member.name))
        end
        
        local message = "Group history: " .. table.concat(historyParts, ", ") .. " |cFF888888(hover for details)|r"
        partySection:SetText(message)
        
        -- Enable hover tooltip for shared history
        partySection:EnableMouse(true)
        partySection:SetScript("OnEnter", function()
            IB:ShowPartyTooltip()
        end)
        partySection:SetScript("OnLeave", function()
            IB:HidePartyTooltip()
        end)
    end
end

function IB:UpdateMainFrame()
    if not self.mainFrame or not self.mainFrame.contentFrame then return end
    
    -- Safety check for database
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs then
        InstanceBuddiesDB = { runs = {} }
    end
    
    -- Safety check for entriesPerPage
    if not self.entriesPerPage or self.entriesPerPage <= 0 then
        self.entriesPerPage = 10
    end
    
    -- Update the party section first
    self:UpdatePartySection()
    
    -- Clear existing rows
    for _, row in pairs(self.mainFrame.runRows) do
        for _, element in pairs(row) do
            element:Hide()
        end
    end
    self.mainFrame.runRows = {}
    
    -- Get the appropriate run list (filtered or full)
    local runs = self.filteredRuns or InstanceBuddiesDB.runs
    local runCount = #runs
    local rowHeight = 20
    local startY = -10
    
    -- Calculate pagination
    local totalPages = math.ceil(runCount / self.entriesPerPage)
    if self.currentPage > totalPages then
        self.currentPage = math.max(1, totalPages)
    end
    
    local startIndex = (self.currentPage - 1) * self.entriesPerPage + 1
    local endIndex = math.min(startIndex + self.entriesPerPage - 1, runCount)
    
    -- Fixed pixel positions for perfect alignment
    local positions = {
        number = 0,      -- "1)"
        time = 30,        -- "Today 15:23"
        player = 150,     -- "50 Maddjones"
        dungeon = 250,    -- "Maraudon"
        group = 400       -- "54 Megarah, 44 Stibilibo ..."
    }
    
    if runCount == 0 then
        local noDataText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noDataText:SetPoint("TOP", 0, startY)
        noDataText:SetJustifyH("CENTER")
        noDataText:SetWidth(800)
        
        -- Different message for search vs no data
        if self.searchTerm and self.searchTerm ~= "" then
            noDataText:SetText("No results found for: \"" .. self.searchTerm .. "\"\n\nTry different keywords or clear the search.")
        else
            noDataText:SetText("No instance runs recorded yet.\n\nEnter an instance with a group to start tracking your adventures!\n\nThe addon will automatically detect when you enter and leave instances.")
        end
        
        noDataText:SetTextColor(1, 1, 1)
        table.insert(self.mainFrame.runRows, {noDataText})
        
        -- Hide pagination controls and search when no data
        self.mainFrame.paginationFrame:Hide()
        self.mainFrame.searchFrame:Hide()
    else
        -- Show pagination controls and search
        self.mainFrame.paginationFrame:Show()
        self.mainFrame.searchFrame:Show()
        
        local displayIndex = 1
        for i = startIndex, endIndex do
            local run = runs[i]
            if run then
                local yPos = startY - ((displayIndex-1) * rowHeight)
                local row = {}
                
                -- Row number (global index)
                local numberText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                numberText:SetPoint("TOPLEFT", positions.number, yPos)
                numberText:SetText(string.format("%d)", i))
                numberText:SetTextColor(1, 1, 1)
                table.insert(row, numberText)
                
                -- Time
                local timeText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                timeText:SetPoint("TOPLEFT", positions.time, yPos)
                timeText:SetText(self:FormatTimestamp(run.enteredTime))
                table.insert(row, timeText)
                
                -- Player level and name combined (same spacing as group members)
                local playerText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                playerText:SetPoint("TOPLEFT", positions.player, yPos)
                playerText:SetText(string.format("|cFF888888%d|r %s%s|r", 
                    run.playerLevel or 0, 
                    self:GetClassColor(run.playerClass), 
                    run.playerName or "Unknown"))
                table.insert(row, playerText)
                
                -- Dungeon name (prominent)
                local dungeonText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dungeonText:SetPoint("TOPLEFT", positions.dungeon, yPos)
                dungeonText:SetText(string.format("|cFF00BFFF%s|r", run.instanceName or "Unknown"))
                table.insert(row, dungeonText)
                
                -- Group members (convert from key-value to display format)
                local groupMembers = {}
                local sortedMembers = self:GetSortedGroupMembers(run.groupData)
                
                for _, member in ipairs(sortedMembers) do
                    local classColor = self:GetClassColor(member.class)
                    local memberStr = string.format("|cFF888888%d|r %s%s|r", member.level, classColor, member.name)
                    table.insert(groupMembers, memberStr)
                end
                
                if #groupMembers > 0 then
                    local groupText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    groupText:SetPoint("TOPLEFT", positions.group, yPos)
                    
                    -- Check if we need to truncate the group list
                    if #sortedMembers > 4 then
                        -- Show first 4 members + "..."
                        local truncatedMembers = {}
                        for i = 1, 4 do
                            table.insert(truncatedMembers, groupMembers[i])
                        end
                        local displayText = table.concat(truncatedMembers, "|cFF888888,|r ") .. "|cFF888888, ...|r"
                        groupText:SetText(displayText)
                        
                        -- Store full member list for tooltip and enable mouse events
                        local fullMemberList = sortedMembers
                        groupText:EnableMouse(true)
                        groupText:SetScript("OnEnter", function(self)
                            IB:ShowGroupMembersTooltip(fullMemberList, self)
                        end)
                        groupText:SetScript("OnLeave", function()
                            IB:HideGroupMembersTooltip()
                        end)
                    else
                        -- Show all members normally
                        groupText:SetText(table.concat(groupMembers, "|cFF888888,|r "))
                        groupText:EnableMouse(false)
                        groupText:SetScript("OnEnter", nil)
                        groupText:SetScript("OnLeave", nil)
                    end
                    
                    table.insert(row, groupText)
                end
                
                table.insert(self.mainFrame.runRows, row)
                displayIndex = displayIndex + 1
            end
        end
        
        -- Update pagination controls
        self.mainFrame.prevBtn:SetEnabled(self.currentPage > 1)
        self.mainFrame.nextBtn:SetEnabled(self.currentPage < totalPages)
        
        if totalPages > 1 then
            self.mainFrame.pageText:SetText(string.format("Page %d of %d", self.currentPage, totalPages))
        else
            self.mainFrame.pageText:SetText("Page 1 of 1")
        end
    end
    
    -- Update content frame height
    local displayedRuns = math.min(self.entriesPerPage, runCount > 0 and (endIndex - startIndex + 1) or 0)
    local totalHeight = math.max(200, (displayedRuns + 1) * rowHeight + 50)
    self.mainFrame.contentFrame:SetHeight(totalHeight)
end

-- Validates and stores group member data with edge case handling
local function AddToGroupData(unit, groupData, partySlot)
    local level = UnitLevel(unit)
    local name = UnitName(unit)
    
    -- WoW API sometimes returns "Unknown" for players out of range
    if name == "Unknown" or not name then
        return
    end
    
    local class, classEnglish = UnitClass(unit)
    
    if level and name then
        if not groupData[name] then
            groupData[name] = {}
        end
        
        -- Only update with valid data to avoid overwriting good info with bad
        if level and (not groupData[name].level or level > 0) then
            groupData[name].level = level
        end
        if classEnglish and (not groupData[name].classEnglish or classEnglish ~= "") then
            groupData[name].classEnglish = classEnglish
        end
        
        -- Store slot for party ordering (0=player, 1-4=party, 1-40=raid)
        if partySlot and (not groupData[name].partySlot or partySlot > 0) then
            groupData[name].partySlot = partySlot
        end
    end
end

-- Called when player enters an instance - initializes run tracking
function IB:OnEnteredInstance()
    local instanceName = GetInstanceInfo()
    
    if not instanceName then return end
    
    self.inInstance = true
    
    -- Create run record with all current player data
    self.currentRun = {
        instanceName = instanceName,
        playerName = UnitName("player"),
        playerLevel = UnitLevel("player"),
        playerClass = select(2, UnitClass("player")),
        enteredTime = GetServerTime(),
        groupData = {}
    }
    
    self:RecordGroupMembers()
end

-- Called when player leaves an instance - finalizes and stores run data
function IB:OnLeftInstance()
    if not self.currentRun then return end
    
    self.inInstance = false
    
    -- Capture final group state before saving
    self:RecordGroupMembers()
    
    -- Ensure database exists before writing to it
    if not InstanceBuddiesDB then
        InstanceBuddiesDB = { runs = {} }
    end
    if not InstanceBuddiesDB.runs then
        InstanceBuddiesDB.runs = {}
    end
    
    -- Insert at beginning for newest-first ordering
    table.insert(InstanceBuddiesDB.runs, 1, self.currentRun)
    
    self.currentRun = nil
end

-- Records current group composition (throttled to prevent spam)
function IB:RecordGroupMembers()
    if not self.currentRun then return end
    
    -- Throttle to prevent excessive calls during group changes
    if (GetServerTime() - recordGroupInfoThrottle) < 2 then
        return
    end
    recordGroupInfoThrottle = GetServerTime()
    
    if not self.currentRun.groupData then
        self.currentRun.groupData = {}
    end
    
    -- Different APIs for different group types
    if IsInRaid() then
        for i = 1, 40 do
            AddToGroupData("raid" .. i, self.currentRun.groupData, i)
        end
    elseif IsInGroup() then
        for i = 1, 5 do
            AddToGroupData("party" .. i, self.currentRun.groupData, i)
        end
    else
        return  -- Solo - no group data to record
    end
end

-- Event system - handles WoW client events for instance detection and addon lifecycle
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")  
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local args = {...}
    local success, errorMsg = pcall(function()
        if event == "ADDON_LOADED" then
            local addonName = args[1]
            if addonName == "InstanceBuddies" then
                if not InstanceBuddiesDB then
                    InstanceBuddiesDB = {
                        runs = {}
                    }
                end
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Delay needed because IsInInstance() is unreliable immediately after login/teleport
            local delayFrame = CreateFrame("Frame")
            local startTime = GetTime()
            delayFrame:SetScript("OnUpdate", function(self)
                if GetTime() - startTime >= 1 then
                    local inInstance, instanceType = IsInInstance()
                    
                    -- Only track party/raid instances, not battlegrounds or arenas
                    if inInstance and (instanceType == "party" or instanceType == "raid") then
                        if not IB.inInstance then
                            IB:OnEnteredInstance()
                        end
                    elseif IB.inInstance then
                        IB:OnLeftInstance()
                    end
                    
                    -- Clean up timer frame to prevent memory leaks
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                    self = nil
                end
            end)
        elseif event == "PLAYER_LEAVING_WORLD" then
            -- Handle logout/disconnect while in instance
            if IB.inInstance then
                IB:OnLeftInstance()
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            -- Update group data when party/raid composition changes
            if IB.inInstance and IB.currentRun then
                IB:RecordGroupMembers()
            end
            
            -- Refresh party history display if UI is open
            if IB.mainFrame and IB.mainFrame:IsShown() then
                IB:UpdatePartySection()
            end
        end
    end)
    
    -- Log any errors but don't crash the addon
    if not success then
        -- Silently handle errors to avoid chat spam
    end
end)

-- Slash command registration for multiple aliases
SLASH_INSTANCEBUDDIES1 = "/instancebuddies"
SLASH_INSTANCEBUDDIES2 = "/ib"
SLASH_INSTANCEBUDDIES3 = "/ibuddies"
SlashCmdList["INSTANCEBUDDIES"] = function(msg)
    IB:CreateMainFrame()
end

print("|cFF00FF00InstanceBuddies|r dungeon tracker loaded! Use /ib, /ibuddies, or /instancebuddies to view history.")

-- Memory management - destroys tooltip FontString objects to prevent accumulation
function IB:CleanupTooltips()
    if self.mainFrame then
        if self.mainFrame.tooltip and self.mainFrame.tooltip.rows then
            for _, row in pairs(self.mainFrame.tooltip.rows) do
                if row then
                    row:Hide()
                    row:SetParent(nil)
                    row:ClearAllPoints()
                end
            end
            self.mainFrame.tooltip.rows = {}
        end
        
        if self.mainFrame.groupTooltip and self.mainFrame.groupTooltip.rows then
            for _, row in pairs(self.mainFrame.groupTooltip.rows) do
                if row then
                    row:Hide()
                    row:SetParent(nil)
                    row:ClearAllPoints()
                end
            end
            self.mainFrame.groupTooltip.rows = {}
        end
    end
end 