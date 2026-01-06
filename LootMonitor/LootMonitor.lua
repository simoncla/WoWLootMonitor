---@class LootMonitor
local addonName, addon = ...

-- Localize frequently used functions
local floor = math.floor

local LootMonitorModule = {}

-- Constants
local QUALITY_COLORS = {
    [0] = "9d9d9d", -- Poor (gray)
    [1] = "ffffff", -- Common (white)
    [2] = "1eff00", -- Uncommon (green)
    [3] = "0070dd", -- Rare (blue)
    [4] = "a335ee", -- Epic (purple)
    [5] = "ff8000", -- Legendary (orange)
    [6] = "e6cc80", -- Artifact (light gold)
    [7] = "00ccff", -- Heirloom (cyan)
    [8] = "00ccff", -- WoW Token (cyan)
}

local ENTRY_HEIGHT = 50
local ICON_SIZE = 40
local FRAME_WIDTH = 350
local MAX_VISIBLE_ENTRIES = 8

-- Quality to setting key mapping
local QUALITY_DURATION_KEYS = {
    [0] = "lootMonitorDurationPoor",
    [1] = "lootMonitorDurationCommon",
    [2] = "lootMonitorDurationUncommon",
    [3] = "lootMonitorDurationRare",
    [4] = "lootMonitorDurationEpic",
    [5] = "lootMonitorDurationLegendary",
    [6] = "lootMonitorDurationArtifact",
    [7] = "lootMonitorDurationHeirloom",
    [8] = "lootMonitorDurationHeirloom", -- Quest items use heirloom timing
}

-- Get duration for an entry based on type and quality
local function GetEntryDuration(entryType, quality)
    if entryType == "item" then
        local key = QUALITY_DURATION_KEYS[quality or 1]
        return addon.db[key] or 10
    elseif entryType == "money" then
        return addon.db.lootMonitorDurationGold or 3
    elseif entryType == "reputation" then
        return addon.db.lootMonitorDurationReputation or 15
    elseif entryType == "currency" then
        return addon.db.lootMonitorDurationCurrency or 15
    end
    return 10 -- Default fallback
end

-- Tracked currencies (we'll track changes between updates)
local previousCurrencies = {}

-- Main frame
local mainFrame
local entries = {}
local entryPool = {}

-- Create an entry row
local function CreateEntryRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(FRAME_WIDTH - 20, ENTRY_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0, 0, 0, 0.6)
    row:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    
    -- Icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 5, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Trim icon borders
    
    -- Main text (item name / currency name / rep name)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -4)
    row.text:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    
    -- Subtext (ilvl, stats, progress)
    row.subtext = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subtext:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
    row.subtext:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    row.subtext:SetJustifyH("LEFT")
    row.subtext:SetWordWrap(false)
    
    -- Right text (price / quantity)
    row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.rightText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.rightText:SetJustifyH("RIGHT")
    
    -- Enable mouse for tooltips
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    row.createdTime = 0
    row.entryType = nil
    row.itemLink = nil
    row.itemQuality = nil
    
    return row
end

-- Get or create an entry row from pool
local function AcquireEntryRow(parent)
    local row = table.remove(entryPool)
    if not row then
        row = CreateEntryRow(parent)
    end
    row:SetParent(parent)
    row:SetAlpha(1) -- Reset alpha
    row.fadeOffset = 0 -- Reset slide offset
    row:Show()
    return row
end

-- Return entry to pool
local function ReleaseEntryRow(row)
    row:Hide()
    row:SetParent(nil)
    row.itemLink = nil
    row.fadeOffset = 0 -- Reset slide offset
    table.insert(entryPool, row)
end

-- Format money string
local function FormatMoney(copper)
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local copperRemain = copper % 100
    
    local str = ""
    if gold > 0 then
        str = str .. "|cffffd700" .. gold .. "g|r "
    end
    if silver > 0 or gold > 0 then
        str = str .. "|cffc0c0c0" .. silver .. "s|r "
    end
    str = str .. "|cffeda55f" .. copperRemain .. "c|r"
    
    return str
end

-- Format compact money (for right side)
local function FormatMoneyCompact(copper)
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local copperRemain = copper % 100
    
    return string.format("|cffffd700%dg|r |cffc0c0c0%ds|r |cffeda55f%dc|r", gold, silver, copperRemain)
end

-- Format compact money (short version for AH price)
local function FormatMoneyShort(copper)
    if not copper or copper <= 0 then return nil end
    
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    
    if gold >= 1000 then
        return string.format("|cffffd700%.1fk|r", gold / 1000)
    elseif gold > 0 then
        return string.format("|cffffd700%dg|r", gold)
    elseif silver > 0 then
        return string.format("|cffc0c0c0%ds|r", silver)
    else
        return string.format("|cffeda55f%dc|r", copper)
    end
end

-- Get item ID from item link
local function GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local itemID = itemLink:match("item:(%d+)")
    return tonumber(itemID)
end

-- Get auction house price from supported addons (Auctionator, TSM)
local function GetAuctionPrice(itemLink)
    if not itemLink then return nil end
    
    local itemID = GetItemIDFromLink(itemLink)
    if not itemID then return nil end
    
    -- Try Auctionator first
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local success, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "LootMonitor", itemID)
        if success and price and price > 0 then
            return price, "Auctionator"
        end
    end
    
    -- Try TSM
    if TSM_API and TSM_API.GetCustomPriceValue then
        -- TSM uses item strings like "i:12345"
        local itemString = "i:" .. itemID
        local success, price = pcall(TSM_API.GetCustomPriceValue, "DBMarket", itemString)
        if success and price and price > 0 then
            return price, "TSM"
        end
        -- Try region market value as fallback
        success, price = pcall(TSM_API.GetCustomPriceValue, "DBRegionMarketAvg", itemString)
        if success and price and price > 0 then
            return price, "TSM"
        end
    end
    
    return nil, nil
end

-- Get item stats summary
local function GetItemStatsSummary(itemLink)
    local stats = {}
    local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
    
    if not tooltipData then return "" end
    
    -- Parse tooltip for key stats
    for _, line in ipairs(tooltipData.lines or {}) do
        local text = line.leftText or ""
        
        -- Look for notable stats
        if text:match("Leech") then
            table.insert(stats, "|cff00ff00Leech|r")
        elseif text:match("Avoidance") then
            table.insert(stats, "|cff00ff00Avoidance|r")
        elseif text:match("Indestructible") then
            table.insert(stats, "|cff00ff00Indestructible|r")
        elseif text:match("Speed") and not text:match("Attack Speed") then
            table.insert(stats, "|cff00ff00Speed|r")
        end
        
        -- Check for sockets
        if text:match("Socket") then
            table.insert(stats, "|cffff00ffSocket|r")
        end
    end
    
    return table.concat(stats, " ")
end

-- Add a new entry
local function AddEntry(entryType, data)
    if not addon.db.lootMonitorEnabled then return end
    
    -- Check type-specific toggles
    if entryType == "item" and not addon.db.lootMonitorShowItems then return end
    if entryType == "money" and not addon.db.lootMonitorShowMoney then return end
    if entryType == "currency" and not addon.db.lootMonitorShowCurrency then return end
    if entryType == "reputation" and not addon.db.lootMonitorShowReputation then return end
    
    
    local row = AcquireEntryRow(mainFrame)
    
    row.createdTime = GetTime()
    row.entryType = entryType
    
    if entryType == "item" then
        local itemName, itemLink, itemQuality, itemLevel, _, _, _, _, _, itemIcon, sellPrice = C_Item.GetItemInfo(data.itemLink)
        
        if itemName then
            row.icon:SetTexture(itemIcon)
            row.itemLink = itemLink
            row.itemQuality = itemQuality
            
            local qualityColor = QUALITY_COLORS[itemQuality] or "ffffff"
            local quantityStr = data.quantity > 1 and (data.quantity .. "x ") or ""
            row.text:SetText(quantityStr .. "|cff" .. qualityColor .. itemName .. "|r")
            
            -- Build subtext with ilvl and stats
            local subParts = {}
            if itemLevel and itemLevel > 1 then
                table.insert(subParts, "|cffffcc00ilvl: " .. itemLevel .. "|r")
            end
            
            local stats = GetItemStatsSummary(itemLink)
            if stats ~= "" then
                table.insert(subParts, stats)
            end
            
            row.subtext:SetText(table.concat(subParts, " "))
            
            -- Build price display (vendor + AH)
            local priceLines = {}
            
            -- Vendor price
            if sellPrice and sellPrice > 0 then
                local totalVendor = sellPrice * data.quantity
                table.insert(priceLines, FormatMoneyCompact(totalVendor))
            end
            
            -- Auction House price (from Auctionator or TSM)
            if addon.db.lootMonitorShowAHPrice then
                local ahPrice, ahSource = GetAuctionPrice(itemLink)
                if ahPrice and ahPrice > 0 then
                    local totalAH = ahPrice * data.quantity
                    table.insert(priceLines, "|cff00ffff" .. FormatMoneyCompact(totalAH) .. "|r")
                end
            end
            
            row.rightText:SetText(table.concat(priceLines, "\n"))
        else
            -- Item info not cached, try again after a delay
            C_Timer.After(0.5, function()
                if row and row:IsShown() then
                    local name2, link2, quality2, ilvl2, _, _, _, _, _, icon2, price2 = C_Item.GetItemInfo(data.itemLink)
                    if name2 then
                        row.icon:SetTexture(icon2)
                        row.itemLink = link2
                        row.itemQuality = quality2
                        local qColor = QUALITY_COLORS[quality2] or "ffffff"
                        local qStr = data.quantity > 1 and (data.quantity .. "x ") or ""
                        row.text:SetText(qStr .. "|cff" .. qColor .. name2 .. "|r")
                        
                        local sub = {}
                        if ilvl2 and ilvl2 > 1 then
                            table.insert(sub, "|cffffcc00ilvl: " .. ilvl2 .. "|r")
                        end
                        row.subtext:SetText(table.concat(sub, " "))
                        
                        -- Build price display (vendor + AH)
                        local priceLines = {}
                        if price2 and price2 > 0 then
                            table.insert(priceLines, FormatMoneyCompact(price2 * data.quantity))
                        end
                        if addon.db.lootMonitorShowAHPrice then
                            local ahPrice2 = GetAuctionPrice(link2)
                            if ahPrice2 and ahPrice2 > 0 then
                                table.insert(priceLines, "|cff00ffff" .. FormatMoneyCompact(ahPrice2 * data.quantity) .. "|r")
                            end
                        end
                        row.rightText:SetText(table.concat(priceLines, "\n"))
                    end
                end
            end)
            
            -- Temporary display
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.text:SetText(data.itemLink)
            row.subtext:SetText("")
            row.rightText:SetText("")
        end
        
    elseif entryType == "money" then
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        row.text:SetText("|cffffd700Money|r")
        row.subtext:SetText("")
        row.rightText:SetText(FormatMoneyCompact(data.amount))
        row.itemLink = nil
        
    elseif entryType == "currency" then
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(data.currencyID)
        if currencyInfo then
            row.icon:SetTexture(currencyInfo.iconFileID)
            
            local quantityStr = data.quantity > 0 and ("+" .. data.quantity .. "x ") or (data.quantity .. "x ")
            local color = data.quantity > 0 and "00ff00" or "ff0000"
            row.text:SetText("|cff" .. color .. quantityStr .. "|r|cffffffff" .. currencyInfo.name .. "|r")
            
            -- Show current/max
            local progressText = ""
            if currencyInfo.maxQuantity and currencyInfo.maxQuantity > 0 then
                progressText = string.format("(|cffffff00%d|r / |cffffff00%d|r)", currencyInfo.quantity, currencyInfo.maxQuantity)
            else
                progressText = string.format("(|cffffff00%d|r)", currencyInfo.quantity)
            end
            row.subtext:SetText(progressText)
            row.rightText:SetText("")
        end
        row.itemLink = nil
        
    elseif entryType == "reputation" then
        row.icon:SetTexture(data.icon or "Interface\\Icons\\Achievement_Reputation_01")
        
        local color = data.amount > 0 and "00ff00" or "ff0000"
        local sign = data.amount > 0 and "+" or ""
        row.text:SetText("|cff" .. color .. sign .. data.amount .. "|r " .. data.factionName .. " Rep")
        
        -- Show progress if available
        if data.current and data.max then
            row.subtext:SetText(string.format("(|cffffff00%d|r / |cffffff00%d|r)", data.current, data.max))
        else
            row.subtext:SetText("")
        end
        row.rightText:SetText("")
        row.itemLink = nil
    end
    
    -- Insert at top
    table.insert(entries, 1, row)
    
    -- Remove excess entries
    while #entries > (addon.db.lootMonitorMaxEntries or MAX_VISIBLE_ENTRIES) do
        local oldRow = table.remove(entries)
        ReleaseEntryRow(oldRow)
    end
    
    -- Reposition all entries
    LootMonitorModule:RepositionEntries()
end

-- Reposition all entries
function LootMonitorModule:RepositionEntries()
    local yOffset = 0
    for i, row in ipairs(entries) do
        row:ClearAllPoints()
        local xOffset = row.fadeOffset or 0
        row:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", xOffset, yOffset)
        yOffset = yOffset - ENTRY_HEIGHT - 5
    end
end

-- Parse loot message - extract item link directly
local function ParseLootMessage(msg)
    -- Look for item links in the message: |cff......|Hitem:...|h[...]|h|r
    -- Match item link pattern
    local itemLink = msg:match("(|c%x+|Hitem:[^|]+|h%[.-%]|h|r)")
    
    if not itemLink then
        -- Try alternative format without color
        itemLink = msg:match("(|Hitem:[^|]+|h%[.-%]|h)")
    end
    
    if not itemLink then
        return nil, 1
    end
    
    -- Check for quantity (e.g., x5 or x20 after the link)
    local quantity = msg:match("|h|rx(%d+)") or msg:match("|rx(%d+)")
    
    return itemLink, tonumber(quantity) or 1
end

-- Parse money message
local function ParseMoneyMessage(msg)
    local gold = tonumber(msg:match("(%d+) Gold")) or 0
    local silver = tonumber(msg:match("(%d+) Silver")) or 0
    local copper = tonumber(msg:match("(%d+) Copper")) or 0
    
    return (gold * 10000) + (silver * 100) + copper
end

-- Slide distance constant
local SLIDE_DISTANCE = 100 -- Pixels to slide during fade

-- Update fade for entries (called frequently for smooth animation)
local function UpdateEntryFade(elapsed)
    local currentTime = GetTime()
    local needsReposition = false
    local slideDirection = addon.db.lootMonitorFadeSlide or "right"
    
    for i = #entries, 1, -1 do
        local row = entries[i]
        local age = currentTime - row.createdTime
        
        -- Get duration based on entry type and quality
        local displayDuration = GetEntryDuration(row.entryType, row.itemQuality)
        
        if age > displayDuration then
            -- Start fading
            local fadeDuration = addon.db.lootMonitorFadeDuration or 0.5
            local fadeProgress = (age - displayDuration) / fadeDuration
            local fadeAlpha = 1 - fadeProgress
            
            if fadeAlpha <= 0 then
                table.remove(entries, i)
                ReleaseEntryRow(row)
                needsReposition = true
            else
                row:SetAlpha(fadeAlpha)
                
                -- Calculate slide offset
                if slideDirection == "right" then
                    row.fadeOffset = fadeProgress * SLIDE_DISTANCE
                elseif slideDirection == "left" then
                    row.fadeOffset = -(fadeProgress * SLIDE_DISTANCE)
                else
                    row.fadeOffset = 0
                end
                needsReposition = true
            end
        else
            row:SetAlpha(1)
            row.fadeOffset = 0
        end
    end
    
    if needsReposition then
        LootMonitorModule:RepositionEntries()
    end
end

-- Create main frame (invisible anchor for entries)
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "LootMonitorFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, 500)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -50, 0)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false) -- Don't block mouse when not over entries
    
    -- Create mover anchor frame (visible when unlocked)
    local mover = CreateFrame("Frame", "LootMonitorMover", frame, "BackdropTemplate")
    mover:SetSize(FRAME_WIDTH, 60)
    mover:SetPoint("TOP", frame, "TOP", 0, 0)
    mover:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    mover:SetBackdropColor(0.1, 0.4, 0.1, 0.8)
    mover:SetBackdropBorderColor(0, 1, 0, 1)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function() frame:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        addon.db.lootMonitorPosition = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    
    -- Mover title text
    local moverTitle = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    moverTitle:SetPoint("CENTER", mover, "CENTER", 0, 10)
    moverTitle:SetText("|cff00ff00Loot Monitor|r")
    
    -- Mover instructions
    local moverInstructions = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moverInstructions:SetPoint("CENTER", mover, "CENTER", 0, -10)
    moverInstructions:SetText("Drag to reposition | Type /lm lock to lock")
    
    mover:Hide() -- Hidden by default
    frame.mover = mover
    
    -- Restore saved position
    if addon.db.lootMonitorPosition then
        local pos = addon.db.lootMonitorPosition
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    
    frame:Show() -- Always shown, entries show/hide themselves
    
    return frame
end

-- Toggle mover visibility
function LootMonitorModule:ToggleMover(unlock)
    if not mainFrame then return end
    
    if unlock then
        mainFrame.mover:Show()
        addon:Print("Loot Monitor unlocked. Drag to reposition, then type |cff00ff00/lm lock|r to lock.")
    else
        mainFrame.mover:Hide()
        addon:Print("Loot Monitor locked.")
    end
end

-- Check if mover is shown
function LootMonitorModule:IsMoverShown()
    return mainFrame and mainFrame.mover and mainFrame.mover:IsShown()
end

-- Event handlers
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    if event == "CHAT_MSG_LOOT" then
        local msg, _, _, _, playerName, _, _, _, _, _, _, playerGUID = ...
        
        -- Check if this is our own loot
        -- Method 1: Compare GUID
        local isOurLoot = (playerGUID == UnitGUID("player"))
        
        -- Method 2: Check if message says "You receive" or "You loot"
        if not isOurLoot then
            isOurLoot = msg:match("^You ") ~= nil
        end
        
        -- Method 3: Compare player name (with or without realm)
        if not isOurLoot and playerName then
            local myName = UnitName("player")
            isOurLoot = (playerName == myName) or (playerName == "") or playerName:match("^" .. myName .. "%-")
        end
        
        if isOurLoot then
            local itemLink, quantity = ParseLootMessage(msg)
            if itemLink then
                AddEntry("item", { itemLink = itemLink, quantity = quantity })
            end
        end
        
    elseif event == "CHAT_MSG_MONEY" then
        local msg = ...
        local amount = ParseMoneyMessage(msg)
        if amount > 0 then
            AddEntry("money", { amount = amount })
        end
        
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        local currencyID, quantity, quantityChange = ...
        if currencyID and quantityChange and quantityChange ~= 0 then
            AddEntry("currency", { currencyID = currencyID, quantity = quantityChange })
        end
        
    elseif event == "COMBAT_TEXT_UPDATE" then
        local messageType, factionName, amount = ...
        if messageType == "FACTION" and factionName and amount then
            -- Get faction info
            local factionID
            for i = 1, GetNumFactions() do
                local name, _, _, _, _, _, _, _, _, _, _, _, _, id = GetFactionInfo(i)
                if name == factionName then
                    factionID = id
                    break
                end
            end
            
            local current, max
            if factionID then
                local factionData = C_Reputation.GetFactionDataByID(factionID)
                if factionData then
                    current = factionData.currentReactionThreshold and 
                              (factionData.currentStanding - factionData.currentReactionThreshold) or factionData.currentStanding
                    max = factionData.nextReactionThreshold and 
                          (factionData.nextReactionThreshold - factionData.currentReactionThreshold) or nil
                end
            end
            
            AddEntry("reputation", {
                factionName = factionName,
                amount = amount,
                current = current,
                max = max,
                icon = nil -- Could look up faction icon if desired
            })
        end
        
    elseif event == "UPDATE_FACTION" then
        -- Could be used for tracking all rep changes
    end
end

function LootMonitorModule:OnInitialize()
    -- Create the main frame
    mainFrame = CreateMainFrame()
    
    -- Register events
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    eventFrame:RegisterEvent("COMBAT_TEXT_UPDATE")
    eventFrame:SetScript("OnEvent", OnEvent)
    
    -- Start fade timer (faster tick for smooth animation)
    C_Timer.NewTicker(0.03, UpdateEntryFade) -- ~30fps for smooth fading
    
    -- Slash command for testing
    SLASH_LOOTMONITORTEST1 = "/lmtest"
    SlashCmdList["LOOTMONITORTEST"] = function(msg)
        -- Add test entries
        AddEntry("reputation", { factionName = "Iskaara Tuskarr", amount = 80, current = 80, max = 3000 })
        AddEntry("currency", { currencyID = 1792, quantity = 500 }) -- Honor
        AddEntry("money", { amount = 2000000 }) -- 200g
        -- Test item using Hearthstone (common item everyone has info for)
        AddEntry("item", { itemLink = "|cffffffff|Hitem:6948::::::::70:::::|h[Hearthstone]|h|r", quantity = 1 })
        addon:Print("Added test entries to Loot Monitor")
    end
    
    -- Slash command for lock/unlock
    SLASH_LOOTMONITOR1 = "/lm"
    SLASH_LOOTMONITOR2 = "/lootmonitor"
    SlashCmdList["LOOTMONITOR"] = function(msg)
        local cmd = msg:lower():trim()
        if cmd == "unlock" or cmd == "move" then
            LootMonitorModule:ToggleMover(true)
        elseif cmd == "lock" then
            LootMonitorModule:ToggleMover(false)
        elseif cmd == "toggle" or cmd == "" then
            -- Open config if available, otherwise toggle mover
            local ConfigModule = addon:GetModule("Config")
            if ConfigModule then
                ConfigModule:Toggle()
            else
                LootMonitorModule:ToggleMover(not LootMonitorModule:IsMoverShown())
            end
        elseif cmd == "test" then
            SlashCmdList["LOOTMONITORTEST"]("")
        else
            addon:Print("Loot Monitor commands:")
            addon:Print("  /lm - Open configuration")
            addon:Print("  /lm unlock - Unlock to reposition")
            addon:Print("  /lm lock - Lock position")
            addon:Print("  /lm toggle - Toggle lock state")
            addon:Print("  /lm test - Add test entries")
        end
    end
end

-- Register the module
addon:RegisterModule("LootMonitor", LootMonitorModule)
