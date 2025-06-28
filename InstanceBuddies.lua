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

-- View mode management
IB.currentView = "pastRuns"  -- "pastRuns", "likes", "dislikes"

-- Search functionality
IB.searchTerm = ""          -- Current search query
IB.filteredRuns = nil       -- Cached search results for runs
IB.filteredLikes = nil      -- Cached search results for likes
IB.filteredDislikes = nil   -- Cached search results for dislikes

-- Performance optimization throttles
local recordGroupInfoThrottle = 0    -- Prevents spam recording of group changes
local searchDebounceTimer = nil      -- Delays search execution for better UX

-- Main UI Frame
function IB:CreateMainFrame()
    if self.mainFrame then 
        if self.mainFrame:IsShown() then
            self:CleanupTooltips()  -- Prevent memory leaks
            -- Close voting frame if open
            if self.votingFrame then
                self.votingFrame:Hide()
                self.votingFrame = nil
            end
            self.mainFrame:Hide()
        else
            self.currentPage = 1    -- Reset pagination on reopen
            self.currentView = "pastRuns"  -- Reset to past runs view
            self.searchTerm = ""    -- Clear search on reopen
            self.mainFrame.searchBox:SetText("")  -- Clear search box display
            self:PerformSearch()    -- Regenerate filtered results and update display
            self.mainFrame:Show()
        end
        return 
    end
    
    -- Main window setup
    local frame = CreateFrame("Frame", "InstanceBuddiesMainFrame", UIParent)
    frame:SetSize(825, 450)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    
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
        -- Close voting frame if open
        if IB.votingFrame then
            IB:CleanupVotingFrame()
        end
        frame:Hide() 
    end)
    
    -- Navigation buttons at top-left
    local pastRunsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pastRunsBtn:SetSize(80, 25)
    pastRunsBtn:SetPoint("TOPLEFT", 15, -15)
    pastRunsBtn:SetText("Past Runs")
    pastRunsBtn:SetScript("OnClick", function()
        IB.currentView = "pastRuns"
        IB.currentPage = 1
        -- Clear other filtered data
        IB.filteredLikes = nil
        IB.filteredDislikes = nil
        IB:PerformSearch()
    end)
    
    local likesBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    likesBtn:SetSize(60, 25)
    likesBtn:SetPoint("LEFT", pastRunsBtn, "RIGHT", 5, 0)
    likesBtn:SetText("Likes")
    likesBtn:SetScript("OnClick", function()
        IB.currentView = "likes"
        IB.currentPage = 1
        -- Clear other filtered data
        IB.filteredRuns = nil
        IB.filteredDislikes = nil
        IB:PerformSearch()
    end)
    
    local dislikesBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dislikesBtn:SetSize(70, 25)
    dislikesBtn:SetPoint("LEFT", likesBtn, "RIGHT", 5, 0)
    dislikesBtn:SetText("Dislikes")
    dislikesBtn:SetScript("OnClick", function()
        IB.currentView = "dislikes"
        IB.currentPage = 1
        -- Clear other filtered data
        IB.filteredRuns = nil
        IB.filteredLikes = nil
        IB:PerformSearch()
    end)
    
    -- Party history section - shows shared runs with current group members (two lines)
    local partyHistoryLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partyHistoryLine:SetPoint("TOP", 0, -45)
    partyHistoryLine:SetWidth(800)
    partyHistoryLine:SetJustifyH("CENTER")
    partyHistoryLine:SetTextColor(0.8, 0.8, 1)
    
    local socialStatusLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    socialStatusLine:SetPoint("TOP", 0, -62)
    socialStatusLine:SetWidth(800)
    socialStatusLine:SetJustifyH("CENTER")
    socialStatusLine:SetTextColor(0.8, 0.8, 1)
    
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
    searchFrame:SetPoint("TOPLEFT", 15, -85)
    searchFrame:SetPoint("TOPRIGHT", -15, -85)
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
    scrollFrame:SetPoint("TOPLEFT", 15, -120)
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
        -- Get the appropriate data list based on current view (same logic as UpdateMainFrame)
        local dataList
        if IB.currentView == "pastRuns" then
            dataList = IB.filteredRuns or (InstanceBuddiesDB and InstanceBuddiesDB.runs) or {}
        elseif IB.currentView == "likes" then
            dataList = IB.filteredLikes or IB:GetLikesData() or {}
        elseif IB.currentView == "dislikes" then
            dataList = IB.filteredDislikes or IB:GetDislikesData() or {}
        else
            dataList = {}
        end
        
        local totalItems = #dataList
        local totalPages = math.ceil(totalItems / IB.entriesPerPage)
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
    frame.partyHistoryLine = partyHistoryLine
    frame.socialStatusLine = socialStatusLine
    frame.tooltip = tooltip
    frame.searchBox = searchBox
    frame.searchFrame = searchFrame
    frame.pastRunsBtn = pastRunsBtn
    frame.likesBtn = likesBtn
    frame.dislikesBtn = dislikesBtn
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
    
    -- Handle ESC key manually to respect voting frame hierarchy
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            -- Only close main frame if voting frame isn't open
            if not IB.votingFrame then
                IB:CleanupTooltips()
                frame:Hide()
                -- Only consume ESC when we actually handle it
                self:SetPropagateKeyboardInput(false)
            else
                -- Voting frame is open, let it handle ESCAPE
                self:SetPropagateKeyboardInput(true)
            end
        else
            -- Allow other keys to pass through
            self:SetPropagateKeyboardInput(true)
        end
    end)
    frame:EnableKeyboard(true)
    
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

-- Get social status (likes/dislikes) for current group members
function IB:GetGroupSocialStatus()
    local currentMembers = self:GetCurrentGroupMembers()
    if #currentMembers == 0 then
        return {}
    end
    
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs then
        return {}
    end
    
    -- Track all votes for each member to detect mixed votes
    local memberVotes = {}
    for _, member in ipairs(currentMembers) do
        memberVotes[member.name] = {
            class = member.class,
            hasLike = false,
            hasDislike = false,
            latestVote = nil,
            latestTimestamp = 0
        }
    end
    
    -- Search through all runs to find votes for current group members
    for _, run in ipairs(InstanceBuddiesDB.runs) do
        if run.groupData then
            for memberName, memberData in pairs(run.groupData) do
                -- Check if this member is in current group and has a vote
                if memberVotes[memberName] and memberData.voteType then
                    local runTimestamp = run.enteredTime or 0
                    
                    -- Track what types of votes this member has
                    if memberData.voteType == "like" then
                        memberVotes[memberName].hasLike = true
                    elseif memberData.voteType == "dislike" then
                        memberVotes[memberName].hasDislike = true
                    end
                    
                    -- Keep track of latest vote for fallback
                    if runTimestamp > memberVotes[memberName].latestTimestamp then
                        memberVotes[memberName].latestVote = memberData.voteType
                        memberVotes[memberName].latestTimestamp = runTimestamp
                    end
                end
            end
        end
    end
    
    -- Build result array (only members with votes)
    local socialStatus = {}
    for name, data in pairs(memberVotes) do
        if data.hasLike or data.hasDislike then
            local voteType
            if data.hasLike and data.hasDislike then
                voteType = "mixed" -- Both likes and dislikes
            else
                voteType = data.latestVote -- Single type of vote
            end
            
            table.insert(socialStatus, {
                name = name,
                class = data.class,
                voteType = voteType
            })
        end
    end
    
    -- Sort by vote type (mixed first, then dislikes, then likes), then alphabetically
    table.sort(socialStatus, function(a, b)
        if a.voteType == b.voteType then
            return a.name < b.name
        end
        -- Priority: mixed > dislike > like
        local priorities = {mixed = 1, dislike = 2, like = 3}
        return (priorities[a.voteType] or 999) < (priorities[b.voteType] or 999)
    end)
    
    return socialStatus
end





-- Hide the shared runs tooltip
function IB:HidePartyTooltip()
    if not self.mainFrame or not self.mainFrame.tooltip then return end
    
    local tooltip = self.mainFrame.tooltip
    tooltip:Hide()
    tooltip:ClearAllPoints() -- Clear positioning for next show
end

-- Show the unified tooltip with both group history and vote details
function IB:ShowUnifiedTooltip()
    if not self.mainFrame or not self.mainFrame.tooltip then return end
    
    local tooltip = self.mainFrame.tooltip
    local currentMembers = self:GetCurrentGroupMembers()
    
    if #currentMembers == 0 then return end
    
    -- Collect all shared run data with vote information
    local sharedData = {}
    
    if InstanceBuddiesDB and InstanceBuddiesDB.runs then
        -- Create lookup table for current members
        local currentMemberLookup = {}
        for _, member in ipairs(currentMembers) do
            currentMemberLookup[member.name] = member.class
        end
        
        -- Search through all runs for shared data
        for _, run in ipairs(InstanceBuddiesDB.runs) do
            if run.groupData then
                -- Find current group members in this run
                local runMembers = {}
                for memberName, memberData in pairs(run.groupData) do
                    if currentMemberLookup[memberName] then
                        table.insert(runMembers, {
                            name = memberName,
                            class = currentMemberLookup[memberName],
                            level = memberData.level or 0,
                            voteType = memberData.voteType,
                            notes = memberData.voteNote
                        })
                    end
                end
                
                -- Add entries for each shared member in this run
                for _, member in ipairs(runMembers) do
                    table.insert(sharedData, {
                        timestamp = run.enteredTime,
                        instanceName = run.instanceName,
                        memberName = member.name,
                        memberClass = member.class,
                        memberLevel = member.level,
                        voteType = member.voteType,
                        notes = member.notes
                    })
                end
            end
        end
    end
    
    if #sharedData == 0 then return end
    
    -- Sort by timestamp (most recent first), then alphabetically by member name
    table.sort(sharedData, function(a, b)
        if a.timestamp == b.timestamp then
            return a.memberName < b.memberName
        end
        return a.timestamp > b.timestamp
    end)
    
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
    title:SetText("Group History & Social Status")
    title:SetTextColor(1, 1, 0.5) -- Yellow title
    table.insert(tooltip.rows, title)
    
    local yOffset = -25
    local rowHeight = 16
    
    -- Add each shared run entry
    for i, data in ipairs(sharedData) do
        -- Limit to prevent tooltip overflow
        if i > 20 then
            local moreRow = tooltip.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            moreRow:SetPoint("TOPLEFT", 5, yOffset)
            moreRow:SetText(string.format("|cFF888888... and %d more entries|r", #sharedData - 20))
            table.insert(tooltip.rows, moreRow)
            yOffset = yOffset - rowHeight
            break
        end
        
        local row = tooltip.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 5, yOffset)
        row:SetJustifyH("LEFT")
        row:SetWidth(490)
        
        local memberClassColor = self:GetClassColor(data.memberClass or "UNKNOWN")
        local timeStr = self:FormatTimestamp(data.timestamp)
        
        -- Build the base text with timestamp, instance, level, and name
        local text = string.format("%s - |cFF00BFFF%s|r - |cFF888888%d|r %s%s|r", 
            timeStr or "Unknown time",
            data.instanceName or "Unknown",
            data.memberLevel or 0,
            memberClassColor or "|cFFFFFFFF",
            data.memberName or "Unknown"
        )
        
        -- Add vote status and notes only if there's a vote
        if data.voteType then
            local voteStatus = ""
            if data.voteType == "like" then
                voteStatus = " |cFF00FF00(liked)|r"
            elseif data.voteType == "dislike" then
                voteStatus = " |cFFFF0000(disliked)|r"
            end
            
            -- Add vote status
            text = text .. voteStatus
            
            -- Add notes section for voted players
            local notesText, notesColor
            if data.notes and data.notes ~= "" then
                notesText = data.notes
                notesColor = "|cFFCCCCCC" -- Light gray for actual notes
            else
                notesText = "no notes"
                notesColor = "|cFF888888" -- Darker gray for "no notes"
            end
            
            text = text .. string.format(" - %s%s|r", notesColor, notesText)
        end
        
        row:SetText(text)
        row:SetTextColor(1, 1, 1)
        table.insert(tooltip.rows, row)
        
        yOffset = yOffset - rowHeight
    end
    
    -- Calculate tooltip size
    local width = 550
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
    
    -- Sort by entry timestamp (newest first) for consistency
    table.sort(filteredRuns, function(a, b)
        return (a.enteredTime or 0) > (b.enteredTime or 0)
    end)
    
    return filteredRuns
end

-- Executes search and refreshes UI (called after debounce delay)
function IB:PerformSearch()
    if self.currentView == "pastRuns" then
        self.filteredRuns = self:FilterRuns(self.searchTerm)
    elseif self.currentView == "likes" then
        self.filteredLikes = self:FilterVotes(self.searchTerm, "like")
    elseif self.currentView == "dislikes" then
        self.filteredDislikes = self:FilterVotes(self.searchTerm, "dislike")
    end
    self.currentPage = 1 -- Reset to first page when search changes
    self:UpdateMainFrame()
end

-- Update the current party section (two-line approach)
function IB:UpdatePartySection()
    if not self.mainFrame or not self.mainFrame.partyHistoryLine or not self.mainFrame.socialStatusLine then return end
    
    local history = self:GetGroupDungeonHistory()
    local partyHistoryLine = self.mainFrame.partyHistoryLine
    local socialStatusLine = self.mainFrame.socialStatusLine
    
    -- Clear any existing hover handlers from both lines
    partyHistoryLine:SetScript("OnEnter", nil)
    partyHistoryLine:SetScript("OnLeave", nil)
    partyHistoryLine:EnableMouse(false)
    socialStatusLine:SetScript("OnEnter", nil)
    socialStatusLine:SetScript("OnLeave", nil)
    socialStatusLine:EnableMouse(false)
    
    if not history then
        -- Not in a group
        partyHistoryLine:SetText("Join a group to see your shared history with them!")
        socialStatusLine:SetText("")
        return
    end
    
    -- Get social status for current group members
    local socialStatus = self:GetGroupSocialStatus()
    
    -- Build history line
    if #history > 0 then
        local historyParts = {}
        for _, member in ipairs(history) do
            local classColor = self:GetClassColor(member.class)
            local runText = member.count == 1 and "run" or "runs"
            table.insert(historyParts, string.format("%d %s with %s%s|r", 
                member.count, runText, classColor, member.name))
        end
        
        local historyMessage = "Group history: " .. table.concat(historyParts, ", ") .. " |cFF888888(hover for details)|r"
        partyHistoryLine:SetText(historyMessage)
        
        -- Always enable hover tooltip for shared history when there's history
        partyHistoryLine:EnableMouse(true)
        partyHistoryLine:SetScript("OnEnter", function()
            IB:ShowUnifiedTooltip()
        end)
        partyHistoryLine:SetScript("OnLeave", function()
            IB:HidePartyTooltip()
        end)
    else
        partyHistoryLine:SetText("No shared history with your current group.")
    end
    
    -- Build social status line
    if #socialStatus > 0 then
        local statusParts = {}
        for _, status in ipairs(socialStatus) do
            local classColor = self:GetClassColor(status.class)
            local statusText, statusColor
            if status.voteType == "mixed" then
                statusText = "(mixed)"
                statusColor = "|cFFFFFF00" -- Yellow for mixed
            elseif status.voteType == "like" then
                statusText = "(liked)"
                statusColor = "|cFF00FF00" -- Green for liked
            else -- dislike
                statusText = "(disliked)"
                statusColor = "|cFFFF0000" -- Red for disliked
            end
            table.insert(statusParts, string.format("%s%s|r %s%s|r", 
                classColor, status.name, statusColor, statusText))
        end
        
        local socialMessage = "Social status: " .. table.concat(statusParts, ", ") .. " |cFF888888(hover for details)|r"
        socialStatusLine:SetText(socialMessage)
        
        -- Enable hover tooltip for social status
        socialStatusLine:EnableMouse(true)
        socialStatusLine:SetScript("OnEnter", function()
            IB:ShowUnifiedTooltip()
        end)
        socialStatusLine:SetScript("OnLeave", function()
            IB:HidePartyTooltip()
        end)
    else
        socialStatusLine:SetText("Your social status will show up here!")
    end
end

-- Properly cleanup voting frame and all child elements to prevent memory leaks
function IB:CleanupVotingFrame()
    if not self.votingFrame then return end
    
    local frame = self.votingFrame
    
    -- Clean up member checkboxes and their labels
    if frame.memberCheckboxes then
        for memberName, checkbox in pairs(frame.memberCheckboxes) do
            -- Clear scripts to remove event handlers
            checkbox:SetScript("OnClick", nil)
            checkbox:SetScript("OnEnter", nil)
            checkbox:SetScript("OnLeave", nil)
            
            -- Hide and clear positioning
            checkbox:Hide()
            checkbox:ClearAllPoints()
            checkbox:SetParent(nil)
        end
        -- Clear the checkboxes table
        for k in pairs(frame.memberCheckboxes) do
            frame.memberCheckboxes[k] = nil
        end
        frame.memberCheckboxes = nil
    end
    
    -- Clean up member labels
    if frame.memberLabels then
        for memberName, label in pairs(frame.memberLabels) do
            -- Hide and clear positioning
            label:Hide()
            label:ClearAllPoints()
            label:SetParent(nil)
        end
        -- Clear the labels table
        for k in pairs(frame.memberLabels) do
            frame.memberLabels[k] = nil
        end
        frame.memberLabels = nil
    end
    
    -- Clean up notes box
    if frame.notesBox then
        frame.notesBox:SetScript("OnEnterPressed", nil)
        frame.notesBox:SetScript("OnTextChanged", nil)
        frame.notesBox:ClearFocus()
        frame.notesBox:Hide()
        frame.notesBox:ClearAllPoints()
        frame.notesBox:SetParent(nil)
        frame.notesBox = nil
    end
    
    -- Clean up all frame scripts and event handlers
    frame:SetScript("OnKeyDown", nil)
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)
    frame:EnableKeyboard(false)
    frame:EnableMouse(false)
    
    -- Hide and clear the main frame
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)
    
    -- Clear the reference
    self.votingFrame = nil
end

-- Create and show the voting frame for a specific run
function IB:ShowVotingFrame(run)
    if not run then return end
    
    -- Close existing voting frame if open
    if self.votingFrame then
        self:CleanupVotingFrame()
    end
    
    -- Main voting frame
    local frame = CreateFrame("Frame", "InstanceBuddiesVotingFrame", UIParent)
    frame:SetSize(350, 260)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)  -- Above main frame
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.95)
    
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.3, 0.3, 0.3, 1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Vote on Group Members")
    title:SetTextColor(1, 1, 1)
    
    -- Instance info
    local instanceInfo = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instanceInfo:SetPoint("TOP", 0, -35)
    instanceInfo:SetText(string.format("%s - |cFF00BFFF%s|r", 
        self:FormatTimestamp(run.enteredTime),
        run.instanceName or "Unknown"))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(50, 20)
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() 
        self:CleanupVotingFrame()
    end)
    
    -- Party members selection area
    local membersLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    membersLabel:SetPoint("TOPLEFT", 15, -65)
    membersLabel:SetText("Select group members to vote on:")
    membersLabel:SetTextColor(1, 1, 1)
    
    -- Scrollable area for party member checkboxes
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", 15, -85)
    scrollFrame:SetPoint("TOPRIGHT", -15, -85)
    scrollFrame:SetHeight(85)
    
    local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints()
    scrollBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)
    
    local contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(contentFrame)
    
    -- Create checkboxes for each party member
    local memberCheckboxes = {}
    local memberLabels = {}
    local sortedMembers = self:GetSortedGroupMembers(run.groupData)
    local yOffset = -5
    
    for i, member in ipairs(sortedMembers) do
        local checkbox = CreateFrame("CheckButton", nil, contentFrame, "UICheckButtonTemplate")
        checkbox:SetSize(16, 16)
        checkbox:SetPoint("TOPLEFT", 10, yOffset)
        
        local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
        label:SetText(string.format("%s%s|r", self:GetClassColor(member.class), member.name))
        
        memberCheckboxes[member.name] = checkbox
        memberLabels[member.name] = label
        yOffset = yOffset - 20
    end
    
    -- Update content frame height
    contentFrame:SetHeight(math.max(80, math.abs(yOffset) + 10))
    
    -- Notes area
    local notesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLabel:SetPoint("TOPLEFT", 15, -175)
    notesLabel:SetText("Notes (optional):")
    notesLabel:SetTextColor(1, 1, 1)
    
    local notesBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    notesBox:SetSize(320, 20)
    notesBox:SetPoint("TOPLEFT", 15, -195)
    notesBox:SetMultiLine(false)
    notesBox:SetAutoFocus(false)
    notesBox:SetMaxLetters(200)
    
    -- Vote buttons
    local likeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    likeBtn:SetSize(80, 25)
    likeBtn:SetPoint("TOPLEFT", 50, -230)
    likeBtn:SetText("Like")
    likeBtn:SetScript("OnClick", function()
        local selectedMembers = {}
        for memberName, checkbox in pairs(memberCheckboxes) do
            if checkbox:GetChecked() then
                table.insert(selectedMembers, memberName)
            end
        end
        if #selectedMembers > 0 then
            self:SubmitVote(run, selectedMembers, "like", notesBox:GetText())
        end
        self:CleanupVotingFrame()
    end)
    
    local dislikeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dislikeBtn:SetSize(80, 25)
    dislikeBtn:SetPoint("TOPRIGHT", -50, -230)
    dislikeBtn:SetText("Dislike")
    dislikeBtn:SetScript("OnClick", function()
        local selectedMembers = {}
        for memberName, checkbox in pairs(memberCheckboxes) do
            if checkbox:GetChecked() then
                table.insert(selectedMembers, memberName)
            end
        end
        if #selectedMembers > 0 then
            self:SubmitVote(run, selectedMembers, "dislike", notesBox:GetText())
        end
        self:CleanupVotingFrame()
    end)
    
    -- Initially disable buttons and notes since no members are selected
    likeBtn:SetEnabled(false)
    dislikeBtn:SetEnabled(false)
    notesBox:SetEnabled(false)
    
    -- Handle Enter key to submit vote (focus on Like button)
    notesBox:SetScript("OnEnterPressed", function()
        notesBox:ClearFocus()
        -- Auto-click Like button if any members are selected
        local anySelected = false
        for _, checkbox in pairs(memberCheckboxes) do
            if checkbox:GetChecked() then
                anySelected = true
                break
            end
        end
        if anySelected then
            likeBtn:Click()
        end
    end)
    
    -- Function to update button states based on checkbox selection
    local function updateButtonStates()
        local anySelected = false
        for _, checkbox in pairs(memberCheckboxes) do
            if checkbox:GetChecked() then
                anySelected = true
                break
            end
        end
        
        -- Enable/disable buttons and notes based on selection (same pattern as pagination buttons)
        likeBtn:SetEnabled(anySelected)
        dislikeBtn:SetEnabled(anySelected)
        notesBox:SetEnabled(anySelected)
    end
    
    -- Add click handlers to checkboxes for multi-selection behavior
    for memberName, checkbox in pairs(memberCheckboxes) do
        checkbox:SetScript("OnClick", function(self)
            -- Allow multiple selections - no need to deselect others
            updateButtonStates()
        end)
    end
    
    -- Enable dragging
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    -- Store references
    frame.memberCheckboxes = memberCheckboxes
    frame.memberLabels = memberLabels
    frame.notesBox = notesBox
    self.votingFrame = frame
    
    -- Handle ESC key manually to close voting frame first
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            -- Check if any input box is focused - if so, let ESCAPE reach the input to clear focus
            local searchBoxFocused = IB.mainFrame and IB.mainFrame.searchBox and IB.mainFrame.searchBox:HasFocus()
            local notesBoxFocused = frame.notesBox and frame.notesBox:HasFocus()
            
            if searchBoxFocused or notesBoxFocused then
                -- Let ESCAPE reach the focused input box
                self:SetPropagateKeyboardInput(true)
            else
                -- No input focused, close voting frame
                IB:CleanupVotingFrame()
                self:SetPropagateKeyboardInput(false)  -- Block ESC from propagating further
            end
        else
            self:SetPropagateKeyboardInput(true)   -- Allow other keys to pass through to game
        end
    end)
    frame:EnableKeyboard(true)
    
    frame:Show()
end

-- Updates navigation button states based on current view
function IB:UpdateNavigationButtons()
    if not self.mainFrame then return end
    
    -- Enable/disable buttons based on current view
    self.mainFrame.pastRunsBtn:SetEnabled(self.currentView ~= "pastRuns")
    self.mainFrame.likesBtn:SetEnabled(self.currentView ~= "likes") 
    self.mainFrame.dislikesBtn:SetEnabled(self.currentView ~= "dislikes")
end

-- Multi-keyword search across vote data by scanning through runs
function IB:FilterVotes(searchTerm, voteType)
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs then
        return {}
    end
    
    -- Collect all votes of the specified type from runs
    local votesOfType = {}
    for _, run in ipairs(InstanceBuddiesDB.runs) do
        if run.groupData then
            -- Get member names and sort them for consistent iteration order
            local memberNames = {}
            for memberName, memberData in pairs(run.groupData) do
                if memberData.voteType == voteType then
                    table.insert(memberNames, memberName)
                end
            end
            
            -- Sort member names alphabetically for consistent ordering within same run
            table.sort(memberNames)
            
            -- Process members in sorted order
            for _, memberName in ipairs(memberNames) do
                local memberData = run.groupData[memberName]
                -- Create vote-like object for compatibility
                local voteObj = {
                    targetMembers = {memberName},
                    voteType = voteType,
                    notes = memberData.voteNote,
                    instanceName = run.instanceName,
                    runTimestamp = run.enteredTime,
                    runPlayerName = run.playerName,
                    memberClass = memberData.classEnglish,
                    memberLevel = memberData.level
                }
                table.insert(votesOfType, voteObj)
            end
        end
    end
    
    if not searchTerm or searchTerm == "" then
        -- Sort by run timestamp (newest first), then alphabetically by member name
        table.sort(votesOfType, function(a, b)
            local aTime = a.runTimestamp or 0
            local bTime = b.runTimestamp or 0
            if aTime == bTime then
                -- Secondary sort: alphabetical by member name
                local aName = (a.targetMembers and a.targetMembers[1]) or ""
                local bName = (b.targetMembers and b.targetMembers[1]) or ""
                return aName < bName
            end
            return aTime > bTime
        end)
        return votesOfType
    end
    
    -- Split search into individual keywords for AND logic
    local keywords = {}
    for keyword in string.gmatch(string.lower(searchTerm), "%S+") do
        table.insert(keywords, keyword)
    end
    
    if #keywords == 0 then
        table.sort(votesOfType, function(a, b)
            local aTime = a.runTimestamp or 0
            local bTime = b.runTimestamp or 0
            if aTime == bTime then
                -- Secondary sort: alphabetical by member name
                local aName = (a.targetMembers and a.targetMembers[1]) or ""
                local bName = (b.targetMembers and b.targetMembers[1]) or ""
                return aName < bName
            end
            return aTime > bTime
        end)
        return votesOfType
    end
    
    local filteredVotes = {}
    
    -- Each vote must match ALL keywords to be included
    for _, vote in ipairs(votesOfType) do
        local matchesAll = true
        
        for _, keyword in ipairs(keywords) do
            local foundMatch = false
            
            -- Search in instance name
            if vote.instanceName and string.find(string.lower(vote.instanceName), keyword, 1, true) then
                foundMatch = true
            end
            
            -- Search in target member names
            if not foundMatch and vote.targetMembers then
                for _, memberName in ipairs(vote.targetMembers) do
                    if string.find(string.lower(memberName), keyword, 1, true) then
                        foundMatch = true
                        break
                    end
                end
            end
            
            -- Search in notes
            if not foundMatch and vote.notes and string.find(string.lower(vote.notes), keyword, 1, true) then
                foundMatch = true
            end
            
            -- Search in run player name
            if not foundMatch and vote.runPlayerName and string.find(string.lower(vote.runPlayerName), keyword, 1, true) then
                foundMatch = true
            end
            
            -- Fail if this keyword wasn't found anywhere in this vote
            if not foundMatch then
                matchesAll = false
                break
            end
        end
        
        if matchesAll then
            table.insert(filteredVotes, vote)
        end
    end
    
    -- Sort by run timestamp (newest first), then alphabetically by member name
    table.sort(filteredVotes, function(a, b)
        local aTime = a.runTimestamp or 0
        local bTime = b.runTimestamp or 0
        if aTime == bTime then
            -- Secondary sort: alphabetical by member name
            local aName = (a.targetMembers and a.targetMembers[1]) or ""
            local bName = (b.targetMembers and b.targetMembers[1]) or ""
            return aName < bName
        end
        return aTime > bTime
    end)
    
    return filteredVotes
end

-- Gets formatted likes data for display by scanning through runs
function IB:GetLikesData()
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs then
        return {}
    end
    
    local likesData = {}
    
    -- Iterate through all runs to collect likes
    for _, run in ipairs(InstanceBuddiesDB.runs) do
        if run.groupData then
            -- Get member names and sort them for consistent iteration order
            local memberNames = {}
            for memberName, memberData in pairs(run.groupData) do
                if memberData.voteType == "like" then
                    table.insert(memberNames, memberName)
                end
            end
            
            -- Sort member names alphabetically for consistent ordering within same run
            table.sort(memberNames)
            
            -- Process members in sorted order
            for _, memberName in ipairs(memberNames) do
                local memberData = run.groupData[memberName]
                -- Create vote-like object for compatibility with existing display code
                local voteObj = {
                    targetMembers = {memberName},
                    voteType = "like",
                    notes = memberData.voteNote,
                    instanceName = run.instanceName,
                    runTimestamp = run.enteredTime,
                    runPlayerName = run.playerName,
                    -- Add member data for easier access
                    memberClass = memberData.classEnglish,
                    memberLevel = memberData.level
                }
                table.insert(likesData, voteObj)
            end
        end
    end
    
    -- Sort by run timestamp (newest first), then alphabetically by member name
    table.sort(likesData, function(a, b)
        local aTime = a.runTimestamp or 0
        local bTime = b.runTimestamp or 0
        if aTime == bTime then
            -- Secondary sort: alphabetical by member name
            local aName = (a.targetMembers and a.targetMembers[1]) or ""
            local bName = (b.targetMembers and b.targetMembers[1]) or ""
            return aName < bName
        end
        return aTime > bTime
    end)
    
    return likesData
end

-- Gets formatted dislikes data for display by scanning through runs
function IB:GetDislikesData()
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs then
        return {}
    end
    
    local dislikesData = {}
    
    -- Iterate through all runs to collect dislikes
    for _, run in ipairs(InstanceBuddiesDB.runs) do
        if run.groupData then
            -- Get member names and sort them for consistent iteration order
            local memberNames = {}
            for memberName, memberData in pairs(run.groupData) do
                if memberData.voteType == "dislike" then
                    table.insert(memberNames, memberName)
                end
            end
            
            -- Sort member names alphabetically for consistent ordering within same run
            table.sort(memberNames)
            
            -- Process members in sorted order
            for _, memberName in ipairs(memberNames) do
                local memberData = run.groupData[memberName]
                -- Create vote-like object for compatibility with existing display code
                local voteObj = {
                    targetMembers = {memberName},
                    voteType = "dislike",
                    notes = memberData.voteNote,
                    instanceName = run.instanceName,
                    runTimestamp = run.enteredTime,
                    runPlayerName = run.playerName,
                    -- Add member data for easier access
                    memberClass = memberData.classEnglish,
                    memberLevel = memberData.level
                }
                table.insert(dislikesData, voteObj)
            end
        end
    end
    
    -- Sort by run timestamp (newest first), then alphabetically by member name
    table.sort(dislikesData, function(a, b)
        local aTime = a.runTimestamp or 0
        local bTime = b.runTimestamp or 0
        if aTime == bTime then
            -- Secondary sort: alphabetical by member name
            local aName = (a.targetMembers and a.targetMembers[1]) or ""
            local bName = (b.targetMembers and b.targetMembers[1]) or ""
            return aName < bName
        end
        return aTime > bTime
    end)
    
    return dislikesData
end

-- Gets class-colored target member names with level for vote display
function IB:GetColoredTargetMembers(vote)
    if not vote.targetMembers or #vote.targetMembers == 0 then
        return {}
    end
    
    local coloredMembers = {}
    
    -- Color each target member using embedded class data and level
    for _, memberName in ipairs(vote.targetMembers) do
        local memberClass = vote.memberClass  -- Class is now embedded in vote object
        local memberLevel = vote.memberLevel or 0  -- Level is now embedded in vote object
        
        -- Apply class color or default to white
        local classColor = memberClass and self:GetClassColor(memberClass) or "|cFFFFFFFF"
        -- Format: level (gray) + name (class colored) - like "54 Megarah"
        table.insert(coloredMembers, string.format("|cFF888888%d|r %s%s|r", memberLevel, classColor, memberName))
    end
    
    return coloredMembers
end

-- Removes a vote from the run's groupData and updates the display without reordering
function IB:RemoveVote(voteToRemove)
    if not InstanceBuddiesDB or not InstanceBuddiesDB.runs or not voteToRemove then
        return
    end
    
    -- Find the run and remove the vote from the member's data
    for _, run in ipairs(InstanceBuddiesDB.runs) do
        if run.enteredTime == voteToRemove.runTimestamp and 
           run.instanceName == voteToRemove.instanceName then
            
            -- Find the member and remove vote data
            if voteToRemove.targetMembers and #voteToRemove.targetMembers > 0 then
                local memberName = voteToRemove.targetMembers[1]  -- Since we only vote on one member at a time now
                if run.groupData and run.groupData[memberName] then
                    run.groupData[memberName].voteType = nil
                    run.groupData[memberName].voteNote = nil
                    break
                end
            end
        end
    end
    
    -- Remove from filtered data directly to preserve ordering
    local currentDataList
    if self.currentView == "likes" then
        currentDataList = self.filteredLikes or self:GetLikesData()
        self.filteredLikes = currentDataList -- Ensure we have a filtered list to work with
    elseif self.currentView == "dislikes" then
        currentDataList = self.filteredDislikes or self:GetDislikesData()
        self.filteredDislikes = currentDataList -- Ensure we have a filtered list to work with
    else
        currentDataList = {}
    end
    
    -- Find and remove the vote from the filtered list
    for i = #currentDataList, 1, -1 do
        local vote = currentDataList[i]
        if vote.runTimestamp == voteToRemove.runTimestamp and 
           vote.instanceName == voteToRemove.instanceName and
           vote.targetMembers and #vote.targetMembers > 0 and
           vote.targetMembers[1] == voteToRemove.targetMembers[1] then
            table.remove(currentDataList, i)
            break
        end
    end
    
    -- Update the filtered data reference
    if self.currentView == "likes" then
        self.filteredLikes = currentDataList
    elseif self.currentView == "dislikes" then
        self.filteredDislikes = currentDataList
    end
    
    -- Smart pagination logic
    local itemCountAfterRemoval = #currentDataList
    if itemCountAfterRemoval > 0 then
        local totalPages = math.ceil(itemCountAfterRemoval / self.entriesPerPage)
        
        -- If current page is now invalid (no items on this page), go to previous page
        if self.currentPage > totalPages then
            self.currentPage = math.max(1, totalPages)
        end
        -- Otherwise, stay on the current page
    else
        -- No items left, reset to page 1
        self.currentPage = 1
    end
    
    -- Refresh the display (ordering is preserved)
    self:UpdateMainFrame()
end

-- Stores vote data directly in the run's groupData
function IB:SubmitVote(run, selectedMembers, voteType, notes)
    if not run or not selectedMembers or #selectedMembers == 0 or not voteType then
        return
    end
    
    -- Ensure database structure exists
    if not InstanceBuddiesDB then
        InstanceBuddiesDB = { runs = {} }
    end
    if not InstanceBuddiesDB.runs then
        InstanceBuddiesDB.runs = {}
    end
    
    -- Find the actual run in the database and update it
    local targetRun = nil
    for _, dbRun in ipairs(InstanceBuddiesDB.runs) do
        if dbRun.enteredTime == run.enteredTime and 
           dbRun.instanceName == run.instanceName and 
           dbRun.playerName == run.playerName then
            targetRun = dbRun
            break
        end
    end
    
    if not targetRun then
        print("|cFFFF0000InstanceBuddies:|r Error: Could not find run to vote on")
        return
    end
    
    -- Apply vote to each selected member in the run's groupData
    for _, memberName in ipairs(selectedMembers) do
        if targetRun.groupData and targetRun.groupData[memberName] then
            targetRun.groupData[memberName].voteType = voteType
            targetRun.groupData[memberName].voteNote = notes and notes ~= "" and notes or nil
        end
    end
    
    -- Clear filtered data to refresh from database
    if self.currentView == "likes" then
        self.filteredLikes = nil
    elseif self.currentView == "dislikes" then
        self.filteredDislikes = nil
    end
    
    -- Refresh the current view to show the updated vote
    if self.mainFrame and self.mainFrame:IsShown() then
        self:PerformSearch()
    end
end

function IB:UpdateMainFrame()
    if not self.mainFrame or not self.mainFrame.contentFrame then return end
    
    -- Safety check for database
    if not InstanceBuddiesDB then
        InstanceBuddiesDB = { runs = {} }
    end
    if not InstanceBuddiesDB.runs then
        InstanceBuddiesDB.runs = {}
    end
    
    -- Safety check for entriesPerPage
    if not self.entriesPerPage or self.entriesPerPage <= 0 then
        self.entriesPerPage = 10
    end
    
    -- Update navigation button states
    self:UpdateNavigationButtons()
    
    -- Update the party section for all views (this is a main feature)
    self:UpdatePartySection()
    
    -- Clear existing rows
    for _, row in pairs(self.mainFrame.runRows) do
        for _, element in pairs(row) do
            element:Hide()
        end
    end
    self.mainFrame.runRows = {}
    
    -- Get the appropriate data list based on current view
    local dataList
    if self.currentView == "pastRuns" then
        dataList = self.filteredRuns or InstanceBuddiesDB.runs
    elseif self.currentView == "likes" then
        dataList = self.filteredLikes or self:GetLikesData()
    elseif self.currentView == "dislikes" then
        dataList = self.filteredDislikes or self:GetDislikesData()
    else
        dataList = {}
    end
    local runs = dataList
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
        dungeon = 265,    -- "Maraudon"
        group = 400       -- "54 Megarah, 44 Stibilibo ..."
    }
    
    if runCount == 0 then
        local noDataText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noDataText:SetPoint("TOP", 0, startY)
        noDataText:SetJustifyH("CENTER")
        noDataText:SetWidth(800)
        
        -- Different message based on current view and search state
        if self.searchTerm and self.searchTerm ~= "" then
            noDataText:SetText("No results found for: \"" .. self.searchTerm .. "\"\n\nTry different keywords or clear the search.")
        else
            -- Different messages for each view
            if self.currentView == "pastRuns" then
                noDataText:SetText("No instance runs recorded yet.\n\nEnter an instance with a group to start tracking your adventures!\n\nThe addon will automatically record your run once it's been completed.")
            elseif self.currentView == "likes" then
                noDataText:SetText("No likes given yet.\n\nVote on group members from your past runs to start building your like history!\n\nUse the '+' button next to group members in Past Runs to vote.")
            elseif self.currentView == "dislikes" then
                noDataText:SetText("No dislikes given yet.\n\nVote on group members from your past runs to start building your dislike history!\n\nUse the '+' button next to group members in Past Runs to vote.")
            end
        end
        
        noDataText:SetTextColor(1, 1, 1)
        table.insert(self.mainFrame.runRows, {noDataText})
        
        -- Hide pagination controls when no results
        self.mainFrame.paginationFrame:Hide()
        if self.mainFrame.pageText then
            self.mainFrame.pageText:Hide()
        end
        
        -- Search visibility logic based on view and data availability
        if self.currentView == "pastRuns" then
            -- Only hide search when there's truly no data in the database (not just no search results)
            if not self.searchTerm or self.searchTerm == "" then
                -- No data at all - hide search
                self.mainFrame.searchFrame:Hide()
            else
                -- Search returned no results but database has data - keep search visible
                self.mainFrame.searchFrame:Show()
            end
        elseif self.currentView == "likes" then
            -- Hide search if no likes data exists and no search term
            local allLikes = self:GetLikesData()
            if (#allLikes == 0) and (not self.searchTerm or self.searchTerm == "") then
                self.mainFrame.searchFrame:Hide()
            else
                self.mainFrame.searchFrame:Show()
            end
        elseif self.currentView == "dislikes" then
            -- Hide search if no dislikes data exists and no search term
            local allDislikes = self:GetDislikesData()
            if (#allDislikes == 0) and (not self.searchTerm or self.searchTerm == "") then
                self.mainFrame.searchFrame:Hide()
            else
                self.mainFrame.searchFrame:Show()
            end
        end
    else
        -- Show pagination controls and search
        self.mainFrame.paginationFrame:Show()
        self.mainFrame.searchFrame:Show()
        
        local displayIndex = 1
        for i = startIndex, endIndex do
            local item = runs[i]
            if item then
                local yPos = startY - ((displayIndex-1) * rowHeight)
                local row = {}
                
                -- Row number (global index)
                local numberText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                numberText:SetPoint("TOPLEFT", positions.number, yPos)
                numberText:SetText(string.format("%d)", i))
                numberText:SetTextColor(1, 1, 1)
                table.insert(row, numberText)
                
                if self.currentView == "pastRuns" then
                    -- Display logic for run records
                    local run = item
                    
                    -- Time
                    local timeText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    timeText:SetPoint("TOPLEFT", positions.time, yPos)
                    timeText:SetText(self:FormatTimestamp(run.enteredTime))
                    table.insert(row, timeText)
                    
                    -- Player level and name combined
                    local playerText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    playerText:SetPoint("TOPLEFT", positions.player, yPos)
                    playerText:SetText(string.format("|cFF888888%d|r %s%s|r", 
                        run.playerLevel or 0, 
                        self:GetClassColor(run.playerClass), 
                        run.playerName or "Unknown"))
                    table.insert(row, playerText)
                    
                    -- Dungeon name
                    local dungeonText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    dungeonText:SetPoint("TOPLEFT", positions.dungeon, yPos)
                    dungeonText:SetText(string.format("|cFF00BFFF%s|r", run.instanceName or "Unknown"))
                    table.insert(row, dungeonText)
                    
                    -- Group members
                    local groupMembers = {}
                    local sortedMembers = self:GetSortedGroupMembers(run.groupData)
                    
                    for _, member in ipairs(sortedMembers) do
                        local classColor = self:GetClassColor(member.class)
                        local memberStr = string.format("|cFF888888%d|r %s%s|r", member.level, classColor, member.name)
                        table.insert(groupMembers, memberStr)
                    end
                    
                    if #groupMembers > 0 then
                        -- Vote button
                        local voteButton = CreateFrame("Button", nil, self.mainFrame.contentFrame, "UIPanelButtonTemplate")
                        voteButton:SetSize(15, 12)
                        voteButton:SetPoint("TOPLEFT", positions.group, yPos)
                        voteButton:SetText("+")
                        voteButton:SetScript("OnClick", function()
                            IB:ShowVotingFrame(run)
                        end)
                        table.insert(row, voteButton)
                        
                        local groupText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        groupText:SetPoint("TOPLEFT", positions.group + 20, yPos)
                        
                        if #sortedMembers > 4 then
                            local truncatedMembers = {}
                            for j = 1, 4 do
                                table.insert(truncatedMembers, groupMembers[j])
                            end
                            local displayText = table.concat(truncatedMembers, "|cFF888888,|r ") .. "|cFF888888, ...|r"
                            groupText:SetText(displayText)
                            
                            local fullMemberList = sortedMembers
                            groupText:EnableMouse(true)
                            groupText:SetScript("OnEnter", function(self)
                                IB:ShowGroupMembersTooltip(fullMemberList, self)
                            end)
                            groupText:SetScript("OnLeave", function()
                                IB:HideGroupMembersTooltip()
                            end)
                        else
                            groupText:SetText(table.concat(groupMembers, "|cFF888888,|r "))
                            groupText:EnableMouse(false)
                            groupText:SetScript("OnEnter", nil)
                            groupText:SetScript("OnLeave", nil)
                        end
                        
                        table.insert(row, groupText)
                    end
                    
                else
                    -- Display logic for vote records (likes/dislikes)
                    -- Order: timestamp, instanceName, targetMembers[], notes
                    local vote = item
                    
                    -- Time (use run timestamp, not vote timestamp)
                    local timeText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    timeText:SetPoint("TOPLEFT", positions.time, yPos)
                    timeText:SetText(self:FormatTimestamp(vote.runTimestamp))
                    table.insert(row, timeText)
                    
                    -- Instance name
                    local instanceText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    instanceText:SetPoint("TOPLEFT", positions.player, yPos)
                    instanceText:SetText(string.format("|cFF00BFFF%s|r", vote.instanceName or "Unknown"))
                    table.insert(row, instanceText)
                    
                    -- Target members with class colors
                    local memberText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    memberText:SetPoint("TOPLEFT", positions.dungeon, yPos)
                    if vote.targetMembers and #vote.targetMembers > 0 then
                        local coloredMembers = self:GetColoredTargetMembers(vote)
                        memberText:SetText(table.concat(coloredMembers, "|cFF888888,|r "))
                    else
                        memberText:SetText("Unknown")
                    end
                    table.insert(row, memberText)
                    
                    -- Remove button (small button to delete the vote)
                    local removeButton = CreateFrame("Button", nil, self.mainFrame.contentFrame, "UIPanelButtonTemplate")
                    removeButton:SetSize(15, 12)
                    removeButton:SetPoint("TOPLEFT", positions.group, yPos)
                    removeButton:SetText("x")
                    removeButton:SetScript("OnClick", function()
                        IB:RemoveVote(vote)
                    end)
                    table.insert(row, removeButton)
                    
                    -- Notes
                    local notesText = self.mainFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    notesText:SetPoint("TOPLEFT", positions.group + 20, yPos)  -- Offset by button width + small margin
                    if vote.notes and vote.notes ~= "" then
                        notesText:SetText(string.format("|cFFCCCCCC\"%s\"|r", vote.notes))
                    else
                        notesText:SetText("|cFF888888  no notes|r")
                    end
                    table.insert(row, notesText)
                end
                
                table.insert(self.mainFrame.runRows, row)
                displayIndex = displayIndex + 1
            end
        end
        
        -- Update pagination controls - only show when there are 2+ pages
        if totalPages > 1 then
            self.mainFrame.prevBtn:Show()
            self.mainFrame.nextBtn:Show()
            self.mainFrame.pageText:Show()
            
            self.mainFrame.prevBtn:SetEnabled(self.currentPage > 1)
            self.mainFrame.nextBtn:SetEnabled(self.currentPage < totalPages)
            self.mainFrame.pageText:SetText(string.format("Page %d of %d", self.currentPage, totalPages))
        else
            if self.mainFrame.prevBtn then self.mainFrame.prevBtn:Hide() end
            if self.mainFrame.nextBtn then self.mainFrame.nextBtn:Hide() end
            if self.mainFrame.pageText then self.mainFrame.pageText:Hide() end
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
            groupData[name] = {
                voteType = nil,  -- Initialize vote fields
                voteNote = nil
            }
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
        
        -- Initialize vote fields if they don't exist (for existing data compatibility)
        if groupData[name].voteType == nil then
            groupData[name].voteType = nil
        end
        if groupData[name].voteNote == nil then
            groupData[name].voteNote = nil
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

print("|cFF00FF00InstanceBuddies|r loaded! Use /ib, /ibuddies, or /instancebuddies to view your instance history.")

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