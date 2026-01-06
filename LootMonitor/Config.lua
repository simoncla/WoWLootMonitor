---@class LootMonitor
local addonName, addon = ...

local Config = {}

-- Configuration options
local CONFIG_OPTIONS = {
    { key = "lootMonitorEnabled", label = "Enable Loot Monitor", desc = "Show visual feed of looted items and gains" },
    { key = "lootMonitorShowItems", label = "Show Items", desc = "Display looted items with icons and prices" },
    { key = "lootMonitorShowMoney", label = "Show Money", desc = "Display gold/silver/copper gains" },
    { key = "lootMonitorShowCurrency", label = "Show Currency", desc = "Display Honor, Badges, and other currency gains" },
    { key = "lootMonitorShowReputation", label = "Show Reputation", desc = "Display reputation gains with progress" },
    { key = "lootMonitorShowCopperSilver", label = "Display Copper/Silver", desc = "Show small money pickups" },
    { key = "lootMonitorShowHonor", label = "Show Honor", desc = "Display honor currency gains" },
    { key = "lootMonitorShowAHPrice", label = "Show AH Price", desc = "Display auction house price from Auctionator/TSM" },
    { type = "dropdown", key = "lootMonitorFadeSlide", label = "Fade Slide Direction", options = { "none", "left", "right" }, desc = "Direction entries slide when fading" },
    { type = "slider", key = "lootMonitorFadeDuration", label = "Fade Speed", min = 0.1, max = 2.0, step = 0.1, desc = "Duration of fade/slide animation (seconds)" },
    { type = "button", label = "Unlock Position", desc = "Click to unlock and reposition the loot monitor", action = "unlockLootMonitor" },
    { type = "header", label = "Display Duration (seconds)" },
    { type = "number", key = "lootMonitorDurationPoor", label = "Poor", color = "9d9d9d" },
    { type = "number", key = "lootMonitorDurationCommon", label = "Common", color = "ffffff" },
    { type = "number", key = "lootMonitorDurationUncommon", label = "Uncommon", color = "1eff00" },
    { type = "number", key = "lootMonitorDurationRare", label = "Rare", color = "0070dd" },
    { type = "number", key = "lootMonitorDurationEpic", label = "Epic", color = "a335ee" },
    { type = "number", key = "lootMonitorDurationLegendary", label = "Legendary", color = "ff8000" },
    { type = "number", key = "lootMonitorDurationArtifact", label = "Artifact/Currency", color = "e6cc80" },
    { type = "number", key = "lootMonitorDurationHeirloom", label = "Heirloom/Quest", color = "00ccff" },
    { type = "number", key = "lootMonitorDurationGold", label = "Gold", color = "ffd700" },
    { type = "number", key = "lootMonitorDurationReputation", label = "Reputation", color = "00ff00" },
}

-- Create the main config frame
local function CreateConfigFrame()
    -- Main frame
    local frame = CreateFrame("Frame", "LootMonitorConfigFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 550)
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
    
    -- Scroll frame for options
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(390, 1) -- Height will be set dynamically
    scrollFrame:SetScrollChild(scrollChild)
    
    frame.scrollChild = scrollChild
    frame.optionElements = {}
    
    return frame
end

-- Create a checkbox for an option
local function CreateCheckbox(parent, option, yOffset)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", 10, yOffset)
    
    checkbox.Text:SetText(option.label)
    checkbox.Text:SetFontObject("GameFontNormal")
    
    -- Description
    local desc = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", checkbox.Text, "BOTTOMLEFT", 0, -2)
    desc:SetText("|cff888888" .. option.desc .. "|r")
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
        GameTooltip:AddLine(option.desc, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", GameTooltip_Hide)
    
    return checkbox
end

-- Populate options
local function PopulateOptions(frame)
    local scrollChild = frame.scrollChild
    local yOffset = -10
    
    for _, option in ipairs(CONFIG_OPTIONS) do
        if option.type == "button" then
            -- Create a button
            local btn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
            btn:SetSize(150, 25)
            btn:SetPoint("TOPLEFT", 10, yOffset)
            btn:SetText(option.label)
            
            -- Description
            local desc = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetPoint("LEFT", btn, "RIGHT", 10, 0)
            desc:SetText("|cff888888" .. option.desc .. "|r")
            btn.desc = desc
            
            btn:SetScript("OnClick", function()
                if option.action == "unlockLootMonitor" then
                    local LootMonitorModule = addon:GetModule("LootMonitor")
                    if LootMonitorModule then
                        LootMonitorModule:ToggleMover(true)
                        -- Close config to see the mover
                        LootMonitorConfigFrame:Hide()
                    end
                end
            end)
            
            table.insert(frame.optionElements, btn)
            yOffset = yOffset - 35
        elseif option.type == "header" then
            -- Create a section header
            local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", 10, yOffset)
            header:SetText("|cffffd700" .. option.label .. "|r")
            table.insert(frame.optionElements, header)
            yOffset = yOffset - 25
        elseif option.type == "number" then
            -- Create a number input row with colored label
            local container = CreateFrame("Frame", nil, scrollChild)
            container:SetSize(180, 25)
            container:SetPoint("TOPLEFT", 10, yOffset)
            
            -- Colored label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 0, 0)
            local labelColor = option.color or "ffffff"
            label:SetText("|cff" .. labelColor .. option.label .. "|r")
            
            -- Input box
            local editBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
            editBox:SetSize(50, 20)
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
            
            table.insert(frame.optionElements, container)
            yOffset = yOffset - 28
        elseif option.type == "dropdown" then
            -- Create a dropdown-like button that cycles through options
            local container = CreateFrame("Frame", nil, scrollChild)
            container:SetSize(300, 25)
            container:SetPoint("TOPLEFT", 10, yOffset)
            
            -- Label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 0, 0)
            label:SetText(option.label .. ":")
            
            -- Dropdown button
            local dropBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
            dropBtn:SetSize(80, 22)
            dropBtn:SetPoint("LEFT", label, "RIGHT", 10, 0)
            
            local currentValue = addon.db[option.key] or option.options[1]
            dropBtn:SetText(currentValue)
            
            dropBtn:SetScript("OnClick", function(self)
                -- Cycle to next option
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
            
            -- Description
            local desc = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetPoint("LEFT", dropBtn, "RIGHT", 10, 0)
            desc:SetText("|cff888888" .. (option.desc or "") .. "|r")
            
            table.insert(frame.optionElements, container)
            yOffset = yOffset - 30
        elseif option.type == "slider" then
            -- Create a slider
            local container = CreateFrame("Frame", nil, scrollChild)
            container:SetSize(380, 30)
            container:SetPoint("TOPLEFT", 10, yOffset)
            
            -- Label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 0, 0)
            label:SetText(option.label .. ":")
            
            -- Slider
            local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
            slider:SetPoint("LEFT", label, "RIGHT", 10, 0)
            slider:SetSize(120, 16)
            slider:SetMinMaxValues(option.min or 0.1, option.max or 2.0)
            slider:SetValueStep(option.step or 0.1)
            slider:SetObeyStepOnDrag(true)
            slider:SetValue(addon.db[option.key] or 0.5)
            
            -- Hide default text
            slider.Low:SetText("")
            slider.High:SetText("")
            slider.Text:SetText("")
            
            -- Value display
            local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
            valueText:SetText(string.format("%.1fs", addon.db[option.key] or 0.5))
            
            slider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 10 + 0.5) / 10 -- Round to 1 decimal
                addon.db[option.key] = value
                valueText:SetText(string.format("%.1fs", value))
            end)
            
            table.insert(frame.optionElements, container)
            yOffset = yOffset - 35
        else
            local checkbox = CreateCheckbox(scrollChild, option, yOffset)
            table.insert(frame.optionElements, checkbox)
            yOffset = yOffset - 50
        end
    end
    
    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

function Config:Toggle()
    if not LootMonitorConfigFrame then
        local frame = CreateConfigFrame()
        PopulateOptions(frame)
    end
    
    if LootMonitorConfigFrame:IsShown() then
        LootMonitorConfigFrame:Hide()
    else
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
        -- Close the settings panel
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
