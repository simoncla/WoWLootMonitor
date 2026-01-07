---@class LootMonitor
local addonName, addon = ...

-- Localize frequently used functions
local floor = math.floor
local abs = math.abs

local Config = {}

-- Tab definitions with their options
local TABS = {
    {
        name = "General",
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        options = {
            { key = "lootMonitorEnabled", label = "Enable Loot Monitor", desc = "Show visual feed of looted items and gains" },
            { type = "button", label = "Unlock Position", desc = "Click to unlock and reposition the loot monitor", action = "unlockLootMonitor" },
            { type = "button", label = "Simulate Events", desc = "Add test entries to preview the monitor", action = "simulateEvents" },
            { type = "button", label = "Session Summary", desc = "View session statistics (gold, rep, top items, GPH)", action = "sessionSummary" },
            { type = "header", label = "Animation Settings" },
            { type = "dropdown", key = "lootMonitorFadeSlide", label = "Fade Slide Direction", options = { "none", "left", "right" }, desc = "Direction entries slide when fading" },
            { type = "slider", key = "lootMonitorFadeDuration", label = "Fade Speed", min = 0.1, max = 2.0, step = 0.1, desc = "Duration of fade/slide animation (seconds)" },
        }
    },
    {
        name = "Filtering",
        icon = "Interface\\Icons\\Spell_ChargePositive",
        options = {
            { type = "header", label = "Item Quality Filters" },
            { type = "header_sub", label = "Toggle to show/hide, set display duration (seconds)" },
            { type = "filter", toggleKey = "lootMonitorShowPoor", durationKey = "lootMonitorDurationPoor", label = "Poor", color = "9d9d9d" },
            { type = "filter", toggleKey = "lootMonitorShowCommon", durationKey = "lootMonitorDurationCommon", label = "Common", color = "ffffff" },
            { type = "filter", toggleKey = "lootMonitorShowUncommon", durationKey = "lootMonitorDurationUncommon", label = "Uncommon", color = "1eff00" },
            { type = "filter", toggleKey = "lootMonitorShowRare", durationKey = "lootMonitorDurationRare", label = "Rare", color = "0070dd" },
            { type = "filter", toggleKey = "lootMonitorShowEpic", durationKey = "lootMonitorDurationEpic", label = "Epic", color = "a335ee" },
            { type = "filter", toggleKey = "lootMonitorShowLegendary", durationKey = "lootMonitorDurationLegendary", label = "Legendary", color = "ff8000" },
            { type = "filter", toggleKey = "lootMonitorShowArtifact", durationKey = "lootMonitorDurationArtifact", label = "Artifact/Currency", color = "e6cc80" },
            { type = "filter", toggleKey = "lootMonitorShowHeirloom", durationKey = "lootMonitorDurationHeirloom", label = "Heirloom/Quest", color = "00ccff" },
            { type = "header", label = "Other Filters" },
            { type = "filter", toggleKey = "lootMonitorShowMoney", durationKey = "lootMonitorDurationGold", label = "Gold", color = "ffd700" },
            { type = "filter", toggleKey = "lootMonitorShowCurrency", durationKey = "lootMonitorDurationCurrency", label = "Currency", color = "e6cc80" },
            { type = "filter", toggleKey = "lootMonitorShowReputation", durationKey = "lootMonitorDurationReputation", label = "Reputation", color = "00ff00" },
            { type = "header", label = "Additional Options" },
            { key = "lootMonitorShowAHPrice", label = "Show AH Price", desc = "Display auction house price from Auctionator/TSM" },
            { key = "lootMonitorShowTransmogStar", label = "Show Transmog Star", desc = "Pink star on items with uncollected appearances" },
            { type = "header", label = "Gold Alert" },
            { type = "header_sub", label = "Alert when high-value items are looted (based on AH price)" },
            { type = "number", key = "lootMonitorGoldAlertThreshold", label = "Threshold (gold)", color = "ffd700" },
            { key = "lootMonitorGoldAlert", label = "Enable Gold Glow", desc = "Golden glow on high-value items" },
            { key = "lootMonitorGoldAlertSound", label = "Play Alert Sound", desc = "Play a ding sound for high-value items" },
        }
    },
}

-- Store for content elements to properly clear them
local contentElements = {}

-- Create the main config frame
local function CreateConfigFrame()
    -- Main frame
    local frame = CreateFrame("Frame", "LootMonitorConfigFrame", UIParent, "BackdropTemplate")
    frame:SetSize(550, 480)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    
    -- Make it closeable with Escape
    tinsert(UISpecialFrames, "LootMonitorConfigFrame")
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("|cff00ff00Loot Monitor|r Configuration")
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    
    -- Left sidebar for tabs (vertical)
    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 15, -50)
    sidebar:SetPoint("BOTTOMLEFT", 15, 15)
    sidebar:SetWidth(110)
    sidebar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sidebar:SetBackdropColor(0, 0, 0, 0.3)
    sidebar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    
    -- Content area (scroll frame for options)
    local contentArea = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
    contentArea:SetPoint("BOTTOMRIGHT", -15, 15)
    contentArea:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    contentArea:SetBackdropColor(0, 0, 0, 0.3)
    contentArea:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, contentArea, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() - 10)
    scrollChild:SetHeight(1) -- Height will be set dynamically
    scrollFrame:SetScrollChild(scrollChild)
    
    frame.sidebar = sidebar
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild
    frame.tabs = {}
    frame.currentTab = 1
    
    return frame
end

-- Create a checkbox for an option
local function CreateCheckbox(parent, option, yOffset)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", 5, yOffset)
    
    checkbox.Text:SetText(option.label)
    checkbox.Text:SetFontObject("GameFontNormal")
    
    -- Description on same line, after label
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("LEFT", checkbox.Text, "RIGHT", 8, 0)
    desc:SetText("|cff888888" .. (option.desc or "") .. "|r")
    desc:SetJustifyH("LEFT")
    checkbox.desc = desc
    
    checkbox.optionKey = option.key
    checkbox:SetChecked(addon.db[option.key])
    
    checkbox:SetScript("OnClick", function(self)
        addon.db[self.optionKey] = self:GetChecked()
        addon:Print(option.label .. ":", self:GetChecked() and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
    end)
    
    -- Tooltip on hover
    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(option.label, 1, 1, 1)
        if option.desc then
            GameTooltip:AddLine(option.desc, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", GameTooltip_Hide)
    
    return checkbox, desc
end

-- Create vertical tab button
local function CreateTabButton(parent, tabIndex, tabData, onClick)
    local tabWidth = 100
    local tabHeight = 32
    local yOffset = -10 - ((tabIndex - 1) * (tabHeight + 5))
    
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(tabWidth, tabHeight)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
    
    -- Background
    tab:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    
    -- Icon
    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture(tabData.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tab.icon = icon
    
    -- Text
    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    text:SetText(tabData.name)
    tab.text = text
    
    tab.tabIndex = tabIndex
    tab.isSelected = false
    
    -- Update appearance based on selection state
    tab.UpdateAppearance = function(self)
        if self.isSelected then
            self:SetBackdropColor(0.15, 0.4, 0.15, 0.9)
            self:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
            self.text:SetTextColor(1, 1, 1)
        else
            self:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
            self:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)
            self.text:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    
    tab:SetScript("OnClick", function(self)
        onClick(self.tabIndex)
    end)
    
    tab:SetScript("OnEnter", function(self)
        if not self.isSelected then
            self:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end)
    
    tab:SetScript("OnLeave", function(self)
        self:UpdateAppearance()
    end)
    
    tab:UpdateAppearance()
    
    return tab
end

-- Clear all content elements
local function ClearContentElements()
    for _, element in ipairs(contentElements) do
        if element.Hide then element:Hide() end
        if element.SetParent then element:SetParent(nil) end
    end
    wipe(contentElements)
end

-- Populate options for a specific tab
local function PopulateTabOptions(scrollChild, tabData)
    -- Clear existing content
    ClearContentElements()
    
    -- Also clear any children that might have been created
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Clear font strings
    for _, region in ipairs({scrollChild:GetRegions()}) do
        if region:GetObjectType() == "FontString" then
            region:SetText("")
            region:Hide()
        end
    end
    
    local yOffset = -10
    
    for _, option in ipairs(tabData.options) do
        if option.type == "button" then
            -- Create a button
            local btn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
            btn:SetSize(130, 24)
            btn:SetPoint("TOPLEFT", 5, yOffset)
            btn:SetText(option.label)
            
            -- Description
            local desc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetPoint("LEFT", btn, "RIGHT", 10, 0)
            desc:SetText("|cff888888" .. option.desc .. "|r")
            
            btn:SetScript("OnClick", function()
                if option.action == "unlockLootMonitor" then
                    local LootMonitorModule = addon:GetModule("LootMonitor")
                    if LootMonitorModule then
                        LootMonitorModule:ToggleMover(true)
                        LootMonitorConfigFrame:Hide()
                    end
                elseif option.action == "simulateEvents" then
                    local LootMonitorModule = addon:GetModule("LootMonitor")
                    if LootMonitorModule and LootMonitorModule.SimulateEvents then
                        LootMonitorModule:SimulateEvents()
                    end
                elseif option.action == "sessionSummary" then
                    local LootMonitorModule = addon:GetModule("LootMonitor")
                    if LootMonitorModule and LootMonitorModule.ToggleSessionSummary then
                        LootMonitorModule:ToggleSessionSummary()
                        LootMonitorConfigFrame:Hide()
                    end
                end
            end)
            
            table.insert(contentElements, btn)
            table.insert(contentElements, desc)
            yOffset = yOffset - 32
            
        elseif option.type == "header" then
            -- Add extra spacing before headers (except the first one)
            if yOffset < -10 then
                yOffset = yOffset - 12
            end
            -- Create a section header
            local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", 5, yOffset)
            header:SetText("|cffffd700" .. option.label .. "|r")
            table.insert(contentElements, header)
            yOffset = yOffset - 20
            
        elseif option.type == "header_sub" then
            -- Create a sub-header (smaller, grey) - always under the title
            local subHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            subHeader:SetPoint("TOPLEFT", 5, yOffset)
            subHeader:SetText("|cff888888" .. option.label .. "|r")
            table.insert(contentElements, subHeader)
            yOffset = yOffset - 16
            
        elseif option.type == "filter" then
            -- Create a filter row with toggle checkbox and duration input
            local container = CreateFrame("Frame", nil, scrollChild)
            container:SetSize(380, 24)
            container:SetPoint("TOPLEFT", 5, yOffset)
            
            -- Toggle checkbox
            local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
            checkbox:SetSize(22, 22)
            checkbox:SetPoint("LEFT", 0, 0)
            checkbox:SetChecked(addon.db[option.toggleKey] ~= false) -- Default to true if nil
            
            checkbox:SetScript("OnClick", function(self)
                addon.db[option.toggleKey] = self:GetChecked()
            end)
            
            -- Colored label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
            local labelColor = option.color or "ffffff"
            label:SetText("|cff" .. labelColor .. option.label .. "|r")
            
            -- Duration input
            local editBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
            editBox:SetSize(40, 18)
            editBox:SetPoint("LEFT", label, "RIGHT", 12, 0)
            editBox:SetAutoFocus(false)
            editBox:SetNumeric(true)
            editBox:SetMaxLetters(4)
            editBox:SetText(tostring(addon.db[option.durationKey] or 10))
            
            editBox:SetScript("OnEnterPressed", function(self)
                local value = tonumber(self:GetText()) or 10
                addon.db[option.durationKey] = value
                self:ClearFocus()
            end)
            editBox:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(addon.db[option.durationKey] or 10))
                self:ClearFocus()
            end)
            
            -- Seconds label
            local secLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            secLabel:SetPoint("LEFT", editBox, "RIGHT", 4, 0)
            secLabel:SetText("|cff888888sec|r")
            
            table.insert(contentElements, container)
            yOffset = yOffset - 26
            
        elseif option.type == "number" then
            -- Create a number input row with colored label
            local container = CreateFrame("Frame", nil, scrollChild)
            container:SetSize(200, 24)
            container:SetPoint("TOPLEFT", 5, yOffset)
            
            -- Colored label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 0, 0)
            local labelColor = option.color or "ffffff"
            label:SetText("|cff" .. labelColor .. option.label .. "|r")
            
            -- Input box
            local editBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
            editBox:SetSize(45, 18)
            editBox:SetPoint("LEFT", label, "RIGHT", 10, 0)
            editBox:SetAutoFocus(false)
            editBox:SetNumeric(true)
            editBox:SetMaxLetters(4)
            editBox:SetText(tostring(addon.db[option.key] or 10))
            
            editBox:SetScript("OnEnterPressed", function(self)
                local value = tonumber(self:GetText()) or 10
                addon.db[option.key] = value
                self:ClearFocus()
            end)
            editBox:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(addon.db[option.key] or 10))
                self:ClearFocus()
            end)
            
            table.insert(contentElements, container)
            yOffset = yOffset - 26
            
        elseif option.type == "dropdown" then
            -- Create a dropdown-like button that cycles through options
            local container = CreateFrame("Frame", nil, scrollChild)
            container:SetSize(380, 24)
            container:SetPoint("TOPLEFT", 5, yOffset)
            
            -- Label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 0, 0)
            label:SetText(option.label .. ":")
            
            -- Dropdown button
            local dropBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
            dropBtn:SetSize(70, 20)
            dropBtn:SetPoint("LEFT", label, "RIGHT", 10, 0)
            
            local currentValue = addon.db[option.key] or option.options[1]
            dropBtn:SetText(currentValue)
            
            dropBtn:SetScript("OnClick", function(self)
                local currentIdx = 1
                for i, opt in ipairs(option.options) do
                    if opt == addon.db[option.key] then
                        currentIdx = i
                        break
                    end
                end
                local nextIdx = (currentIdx % #option.options) + 1
                addon.db[option.key] = option.options[nextIdx]
                self:SetText(addon.db[option.key])
            end)
            
            table.insert(contentElements, container)
            yOffset = yOffset - 28
            
        elseif option.type == "slider" then
            -- Create a slider
            local container = CreateFrame("Frame", nil, scrollChild)
            container:SetSize(380, 28)
            container:SetPoint("TOPLEFT", 5, yOffset)
            
            -- Label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 0, 0)
            label:SetText(option.label .. ":")
            
            -- Slider
            local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
            slider:SetPoint("LEFT", label, "RIGHT", 10, 0)
            slider:SetSize(100, 16)
            slider:SetMinMaxValues(option.min or 0.1, option.max or 2.0)
            slider:SetValueStep(option.step or 0.1)
            slider:SetObeyStepOnDrag(true)
            slider:SetValue(addon.db[option.key] or 0.5)
            
            slider.Low:SetText("")
            slider.High:SetText("")
            slider.Text:SetText("")
            
            -- Value display
            local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
            valueText:SetText(string.format("%.1fs", addon.db[option.key] or 0.5))
            
            slider:SetScript("OnValueChanged", function(self, value)
                value = floor(value * 10 + 0.5) / 10
                addon.db[option.key] = value
                valueText:SetText(string.format("%.1fs", value))
            end)
            
            table.insert(contentElements, container)
            yOffset = yOffset - 32
            
        else
            -- Default: checkbox
            local checkbox, desc = CreateCheckbox(scrollChild, option, yOffset)
            table.insert(contentElements, checkbox)
            table.insert(contentElements, desc)
            yOffset = yOffset - 28
        end
    end
    
    -- Update scroll child height
    scrollChild:SetHeight(abs(yOffset) + 20)
end

-- Switch to a specific tab
local function SwitchToTab(frame, tabIndex)
    frame.currentTab = tabIndex
    
    -- Update tab appearances
    for i, tab in ipairs(frame.tabs) do
        tab.isSelected = (i == tabIndex)
        tab:UpdateAppearance()
    end
    
    -- Populate options for the selected tab
    PopulateTabOptions(frame.scrollChild, TABS[tabIndex])
    
    -- Reset scroll position
    frame.scrollFrame:SetVerticalScroll(0)
end

-- Initialize tabs
local function InitializeTabs(frame)
    for i, tabData in ipairs(TABS) do
        local tab = CreateTabButton(frame.sidebar, i, tabData, function(index)
            SwitchToTab(frame, index)
        end)
        table.insert(frame.tabs, tab)
    end
    
    -- Default to first tab
    SwitchToTab(frame, 1)
end

function Config:Toggle()
    if not LootMonitorConfigFrame then
        local frame = CreateConfigFrame()
        InitializeTabs(frame)
    end
    
    if LootMonitorConfigFrame:IsShown() then
        LootMonitorConfigFrame:Hide()
    else
        -- Refresh current tab when opening
        SwitchToTab(LootMonitorConfigFrame, LootMonitorConfigFrame.currentTab)
        LootMonitorConfigFrame:Show()
    end
end

function Config:OnInitialize()
    -- Also add to Interface Options (Settings panel)
    local panel = CreateFrame("Frame")
    panel.name = "Loot Monitor"
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff00ff00Loot Monitor|r")
    
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Visual feed of looted items, currency, reputation, and gold gains")
    
    local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openButton:SetSize(200, 30)
    openButton:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    openButton:SetText("Open Loot Monitor Config")
    openButton:SetScript("OnClick", function()
        Config:Toggle()
        if Settings and Settings.CloseUI then
            Settings.CloseUI()
        elseif InterfaceOptionsFrame then
            InterfaceOptionsFrame:Hide()
        end
    end)
    
    -- Register with the new Settings API (10.0+) or legacy
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(panel)
    end
end

-- Register the module
addon:RegisterModule("Config", Config)

-- Expose toggle function globally for keybinds
function LootMonitor_ToggleConfig()
    Config:Toggle()
end
