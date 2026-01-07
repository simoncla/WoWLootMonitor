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

-- Gold Alert constants
local GOLD_ALERT_DEFAULT_THRESHOLD = 500 -- Default threshold in gold
local GOLD_ALERT_SOUND = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON -- Subtle ding sound

-- Get gold alert threshold in copper
local function GetGoldAlertThreshold()
    local goldThreshold = addon.db.lootMonitorGoldAlertThreshold or GOLD_ALERT_DEFAULT_THRESHOLD
    return goldThreshold * 10000 -- Convert gold to copper
end

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

-- Session tracking data
local sessionData = {
    totalGoldLiquid = 0,      -- Raw gold looted (in copper)
    totalItemValue = 0,       -- Sum of AH prices for items (in copper)
    totalReputation = 0,      -- Sum of all reputation gained
    sessionStartTime = nil,   -- Timestamp when session began
    topItems = {},            -- Array of {name, value, link, icon} for tracking valuable items
}

-- Session summary UI state
local sessionSummaryShown = false
local sessionSummaryCard = nil

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
    
    -- Transmog star overlay (pink star for uncollected appearances)
    row.transmogStar = row:CreateTexture(nil, "OVERLAY")
    row.transmogStar:SetSize(16, 16)
    row.transmogStar:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 2, 2)
    row.transmogStar:SetAtlas("auctionhouse-icon-favorite")
    row.transmogStar:SetVertexColor(1, 0.4, 0.7, 1) -- Pink tint
    row.transmogStar:Hide() -- Hidden by default
    
    -- Gold Alert glow overlay (golden glow for high-value items)
    -- Primary glow - soft outer glow
    row.goldGlow = row:CreateTexture(nil, "ARTWORK", nil, -1)
    row.goldGlow:SetSize(ICON_SIZE + 24, ICON_SIZE + 24)
    row.goldGlow:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.goldGlow:SetTexture("Interface\\Cooldown\\star4")
    row.goldGlow:SetVertexColor(1, 0.82, 0, 0.9) -- Gold color
    row.goldGlow:SetBlendMode("ADD")
    row.goldGlow:Hide()
    
    -- Secondary glow - rotating sparkle
    row.goldGlowSpin = row:CreateTexture(nil, "ARTWORK", nil, -2)
    row.goldGlowSpin:SetSize(ICON_SIZE + 20, ICON_SIZE + 20)
    row.goldGlowSpin:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.goldGlowSpin:SetTexture("Interface\\Cooldown\\starburst")
    row.goldGlowSpin:SetVertexColor(1, 0.85, 0.2, 0.7)
    row.goldGlowSpin:SetBlendMode("ADD")
    row.goldGlowSpin:Hide()
    
    -- Animation group for primary glow pulse
    row.goldGlowAnim = row.goldGlow:CreateAnimationGroup()
    row.goldGlowAnim:SetLooping("REPEAT")
    
    local scaleUp = row.goldGlowAnim:CreateAnimation("Scale")
    scaleUp:SetScale(1.15, 1.15)
    scaleUp:SetDuration(0.4)
    scaleUp:SetOrder(1)
    scaleUp:SetSmoothing("IN_OUT")
    
    local scaleDown = row.goldGlowAnim:CreateAnimation("Scale")
    scaleDown:SetScale(0.87, 0.87) -- 1/1.15 to return to original
    scaleDown:SetDuration(0.4)
    scaleDown:SetOrder(2)
    scaleDown:SetSmoothing("IN_OUT")
    
    -- Animation group for spinning sparkle
    row.goldGlowSpinAnim = row.goldGlowSpin:CreateAnimationGroup()
    row.goldGlowSpinAnim:SetLooping("REPEAT")
    
    local rotation = row.goldGlowSpinAnim:CreateAnimation("Rotation")
    rotation:SetDegrees(360)
    rotation:SetDuration(4)
    rotation:SetOrder(1)
    
    -- Main text (item name / currency name / rep name)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0) -- Centered by default
    row.text:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    
    -- Subtext (ilvl, stats, progress)
    row.subtext = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subtext:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
    row.subtext:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    row.subtext:SetJustifyH("LEFT")
    row.subtext:SetWordWrap(false)
    
    -- Helper function to update text layout based on whether subtext exists
    row.UpdateTextLayout = function(self)
        self.text:ClearAllPoints()
        if self.subtext:GetText() and self.subtext:GetText() ~= "" then
            -- Dual line: text at top, subtext at bottom
            self.text:SetPoint("TOPLEFT", self.icon, "TOPRIGHT", 8, -2)
            self.text:SetPoint("RIGHT", self, "RIGHT", -80, 0)
        else
            -- Single line: center vertically
            self.text:SetPoint("LEFT", self.icon, "RIGHT", 8, 0)
            self.text:SetPoint("RIGHT", self, "RIGHT", -80, 0)
        end
    end
    
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
    row.hasGoldAlert = false
    
    return row
end

-- Play gold alert sound and show glow effect
local function TriggerGoldAlert(row)
    if not row then return end
    
    -- Show gold glows
    row.goldGlow:Show()
    row.goldGlow:SetAlpha(0.9)
    row.goldGlowAnim:Play()
    
    row.goldGlowSpin:Show()
    row.goldGlowSpin:SetAlpha(0.7)
    row.goldGlowSpinAnim:Play()
    
    row.hasGoldAlert = true
    
    -- Play sound (only if enabled)
    if addon.db.lootMonitorGoldAlertSound ~= false then
        -- Use a reliable coin/money sound
        PlaySoundFile(567428, "Master") -- LOOTWINDOW_COIN_SOUND
    end
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
    -- Reset gold alert state
    row.goldGlow:Hide()
    row.goldGlowAnim:Stop()
    row.goldGlowSpin:Hide()
    row.goldGlowSpinAnim:Stop()
    row.hasGoldAlert = false
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

-- Format compact money with a single tint color (for AH prices)
local function FormatMoneyTinted(copper, color)
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local copperRemain = copper % 100
    
    return string.format("|cff%s%dg %ds %dc|r", color, gold, silver, copperRemain)
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

-- Check if an item has an uncollected transmog appearance
local function IsUncollectedTransmog(itemLink)
    if not itemLink then return false end
    if not addon.db.lootMonitorShowTransmogStar then return false end
    
    local itemID = GetItemIDFromLink(itemLink)
    if not itemID then return false end
    
    -- Check if the item is transmogable (has an appearance)
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if not appearanceID then return false end
    
    -- Check if player already has this transmog
    local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
    
    return not hasTransmog
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

-- Quality toggle setting keys
local QUALITY_TOGGLE_KEYS = {
    [0] = "lootMonitorShowPoor",
    [1] = "lootMonitorShowCommon",
    [2] = "lootMonitorShowUncommon",
    [3] = "lootMonitorShowRare",
    [4] = "lootMonitorShowEpic",
    [5] = "lootMonitorShowLegendary",
    [6] = "lootMonitorShowArtifact",
    [7] = "lootMonitorShowHeirloom",
    [8] = "lootMonitorShowHeirloom", -- Quest items use heirloom toggle
}

-- Check if an item quality is enabled
local function IsQualityEnabled(quality)
    local key = QUALITY_TOGGLE_KEYS[quality or 1]
    if not key then return true end
    -- Default to true if setting is nil
    return addon.db[key] ~= false
end

-- Add a new entry
local function AddEntry(entryType, data)
    if not addon.db.lootMonitorEnabled then return end
    
    -- Initialize session start time on first entry
    if not sessionData.sessionStartTime then
        sessionData.sessionStartTime = GetTime()
    end
    
    -- Check type-specific toggles
    if entryType == "money" and addon.db.lootMonitorShowMoney == false then return end
    if entryType == "currency" and addon.db.lootMonitorShowCurrency == false then return end
    if entryType == "reputation" and addon.db.lootMonitorShowReputation == false then return end
    
    -- For items, check quality-specific toggle
    if entryType == "item" then
        -- Get item quality first to check if it's enabled
        local _, _, itemQuality = C_Item.GetItemInfo(data.itemLink)
        if itemQuality and not IsQualityEnabled(itemQuality) then return end
    end
    
    local row = AcquireEntryRow(mainFrame)
    
    row.createdTime = GetTime()
    row.entryType = entryType
    
    if entryType == "item" then
        local itemName, itemLink, itemQuality, itemLevel, _, _, _, itemEquipLoc, _, itemIcon, sellPrice = C_Item.GetItemInfo(data.itemLink)
        
        if itemName then
            row.icon:SetTexture(itemIcon)
            row.itemLink = itemLink
            
            -- Check for uncollected transmog appearance
            if IsUncollectedTransmog(itemLink) then
                row.transmogStar:Show()
            else
                row.transmogStar:Hide()
            end
            row.itemQuality = itemQuality
            
            local qualityColor = QUALITY_COLORS[itemQuality] or "ffffff"
            local quantityStr = data.quantity > 1 and (data.quantity .. "x ") or ""
            row.text:SetText(quantityStr .. "|cff" .. qualityColor .. itemName .. "|r")
            
            -- Build subtext with ilvl and stats (only for equippable items: Armor=4, Weapon=2)
            local subParts = {}
            local _, _, _, _, _, itemClassID = C_Item.GetItemInfoInstant(data.itemLink)
            local isEquippable = itemClassID == 2 or itemClassID == 4 -- Weapon or Armor
            if isEquippable and itemLevel and itemLevel > 1 then
                table.insert(subParts, "|cffffcc00ilvl: " .. itemLevel .. "|r")
            end
            
            local stats = GetItemStatsSummary(itemLink)
            if stats ~= "" then
                table.insert(subParts, stats)
            end
            
            row.subtext:SetText(table.concat(subParts, " "))
            row:UpdateTextLayout()
            
            -- Build price display (vendor + AH)
            local priceLines = {}
            
            -- Vendor price
            if sellPrice and sellPrice > 0 then
                local totalVendor = sellPrice * data.quantity
                table.insert(priceLines, FormatMoneyCompact(totalVendor))
            end
            
            -- Auction House price (from Auctionator or TSM)
            local totalAH = nil
            if addon.db.lootMonitorShowAHPrice ~= false then
                local ahPrice, ahSource = GetAuctionPrice(itemLink)
                if ahPrice and ahPrice > 0 then
                    totalAH = ahPrice * data.quantity
                    table.insert(priceLines, FormatMoneyTinted(totalAH, "5ce1e6"))
                end
            end
            
            -- Gold Alert: Check if AH price exceeds threshold
            if totalAH and totalAH >= GetGoldAlertThreshold() and addon.db.lootMonitorGoldAlert ~= false then
                TriggerGoldAlert(row)
            end
            
            -- Track session item value
            if totalAH and totalAH > 0 then
                sessionData.totalItemValue = sessionData.totalItemValue + totalAH
                -- Track top items
                table.insert(sessionData.topItems, {
                    name = itemName,
                    value = totalAH,
                    link = itemLink,
                    icon = itemIcon,
                })
                -- Sort and keep only top 3
                table.sort(sessionData.topItems, function(a, b) return a.value > b.value end)
                while #sessionData.topItems > 3 do
                    table.remove(sessionData.topItems)
                end
            end
            
            row.rightText:SetText(table.concat(priceLines, "\n"))
        else
            -- Item info not cached, try again after a delay
            C_Timer.After(0.5, function()
                if row and row:IsShown() then
                    local name2, link2, quality2, ilvl2, _, _, _, equipLoc2, _, icon2, price2 = C_Item.GetItemInfo(data.itemLink)
                    if name2 then
                        row.icon:SetTexture(icon2)
                        row.itemLink = link2
                        row.itemQuality = quality2
                        
                        -- Check for uncollected transmog appearance
                        if IsUncollectedTransmog(link2) then
                            row.transmogStar:Show()
                        else
                            row.transmogStar:Hide()
                        end
                        
                        local qColor = QUALITY_COLORS[quality2] or "ffffff"
                        local qStr = data.quantity > 1 and (data.quantity .. "x ") or ""
                        row.text:SetText(qStr .. "|cff" .. qColor .. name2 .. "|r")
                        
                        local sub = {}
                        local _, _, _, _, _, itemClassID2 = C_Item.GetItemInfoInstant(data.itemLink)
                        local isEquippable2 = itemClassID2 == 2 or itemClassID2 == 4 -- Weapon or Armor
                        if isEquippable2 and ilvl2 and ilvl2 > 1 then
                            table.insert(sub, "|cffffcc00ilvl: " .. ilvl2 .. "|r")
                        end
                        row.subtext:SetText(table.concat(sub, " "))
                        row:UpdateTextLayout()
                        
                        -- Build price display (vendor + AH)
                        local priceLines = {}
                        if price2 and price2 > 0 then
                            table.insert(priceLines, FormatMoneyCompact(price2 * data.quantity))
                        end
                        local totalAH2 = nil
                        if addon.db.lootMonitorShowAHPrice ~= false then
                            local ahPrice2 = GetAuctionPrice(link2)
                            if ahPrice2 and ahPrice2 > 0 then
                                totalAH2 = ahPrice2 * data.quantity
                                table.insert(priceLines, FormatMoneyTinted(totalAH2, "5ce1e6"))
                            end
                        end
                        
                        -- Gold Alert: Check if AH price exceeds threshold
                        if totalAH2 and totalAH2 >= GetGoldAlertThreshold() and addon.db.lootMonitorGoldAlert ~= false then
                            TriggerGoldAlert(row)
                        end
                        
                        -- Track session item value (delayed callback)
                        if totalAH2 and totalAH2 > 0 then
                            sessionData.totalItemValue = sessionData.totalItemValue + totalAH2
                            -- Track top items
                            table.insert(sessionData.topItems, {
                                name = name2,
                                value = totalAH2,
                                link = link2,
                                icon = icon2,
                            })
                            -- Sort and keep only top 3
                            table.sort(sessionData.topItems, function(a, b) return a.value > b.value end)
                            while #sessionData.topItems > 3 do
                                table.remove(sessionData.topItems)
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
            row:UpdateTextLayout()
            row.transmogStar:Hide()
        end
        
    elseif entryType == "money" then
        row.transmogStar:Hide()
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        row.text:SetText("|cffffd700Money|r")
        row.subtext:SetText("")
        row.rightText:SetText(FormatMoneyCompact(data.amount))
        row:UpdateTextLayout()
        row.itemLink = nil
        
        -- Track session gold
        sessionData.totalGoldLiquid = sessionData.totalGoldLiquid + data.amount
        
    elseif entryType == "currency" then
        row.transmogStar:Hide()
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
            row:UpdateTextLayout()
            row.rightText:SetText("")
        end
        row.itemLink = nil
        
    elseif entryType == "reputation" then
        row.transmogStar:Hide()
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
        row:UpdateTextLayout()
        row.rightText:SetText("")
        row.itemLink = nil
        
        -- Track session reputation
        if data.amount > 0 then
            sessionData.totalReputation = sessionData.totalReputation + data.amount
        end
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
    moverInstructions:SetText("Drag to reposition")
    
    -- Lock button
    local lockButton = CreateFrame("Button", nil, mover, "BackdropTemplate")
    lockButton:SetSize(50, 40)
    lockButton:SetPoint("RIGHT", mover, "RIGHT", -8, 0)
    lockButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    lockButton:SetBackdropColor(0.2, 0.6, 0.2, 1)
    lockButton:SetBackdropBorderColor(0.4, 1, 0.4, 1)
    
    local lockText = lockButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockText:SetPoint("CENTER", lockButton, "CENTER", 0, 0)
    lockText:SetText("|cffffffffLock|r")
    
    lockButton:SetScript("OnClick", function()
        LootMonitorModule:ToggleMover(false)
        -- Open config menu
        local ConfigModule = addon:GetModule("Config")
        if ConfigModule then
            ConfigModule:Toggle()
        end
    end)
    lockButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.8, 0.3, 1)
    end)
    lockButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.6, 0.2, 1)
    end)
    
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

-- Create Session Summary Card
local function CreateSessionSummaryCard(parent)
    local card = CreateFrame("Frame", "LootMonitorSessionCard", parent, "BackdropTemplate")
    card:SetSize(FRAME_WIDTH - 10, 420)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -5)
    card:SetBackdrop({
        bgFile = "Interface\\QUESTFRAME\\QuestBG",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 420,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    card:SetBackdropColor(1, 1, 1, 1)
    card:SetBackdropBorderColor(0.6, 0.5, 0.35, 1)
    
    -- Header
    local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", card, "TOP", 0, -20)
    header:SetText("|cff4a3728Session Summary|r")
    
    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, card, "BackdropTemplate")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    closeBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    closeBtn:SetBackdropColor(0.3, 0.1, 0.1, 0.9)
    closeBtn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
    
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeText:SetText("|cffffffffX|r")
    
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.2, 0.2, 1)
        self:SetBackdropBorderColor(0.8, 0.4, 0.4, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.1, 0.1, 0.9)
        self:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
    end)
    closeBtn:SetScript("OnClick", function()
        LootMonitorModule:ToggleSessionSummary()
    end)
    
    -- Session Duration
    card.duration = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.duration:SetPoint("TOP", header, "BOTTOM", 0, -5)
    card.duration:SetText("Session: 00:00:00")
    
    -- Divider line
    local divider = card:CreateTexture(nil, "ARTWORK")
    divider:SetSize(FRAME_WIDTH - 40, 1)
    divider:SetPoint("TOP", card.duration, "BOTTOM", 0, -10)
    divider:SetColorTexture(0.4, 0.5, 0.7, 0.5)
    
    -- Total Gold Section
    local goldLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -15)
    goldLabel:SetText("|cffffff00Total Gold Gained|r")
    
    card.goldValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.goldValue:SetPoint("TOPLEFT", goldLabel, "BOTTOMLEFT", 10, -5)
    card.goldValue:SetText("0g 0s 0c")
    
    card.goldBreakdown = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.goldBreakdown:SetPoint("TOPLEFT", card.goldValue, "BOTTOMLEFT", 0, -3)
    card.goldBreakdown:SetText("Liquid: 0g | Items: 0g")
    
    -- Reputation Section
    local repLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    repLabel:SetPoint("TOPLEFT", card.goldBreakdown, "BOTTOMLEFT", -10, -15)
    repLabel:SetText("|cff00ff00Total Reputation Gained|r")
    
    card.repValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.repValue:SetPoint("TOPLEFT", repLabel, "BOTTOMLEFT", 10, -5)
    card.repValue:SetText("0")
    
    -- Top Items Section
    local itemsLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemsLabel:SetPoint("TOPLEFT", card.repValue, "BOTTOMLEFT", -10, -15)
    itemsLabel:SetText("|cffa335eeTop 3 Valuable Items|r")
    
    -- Create item rows
    card.itemRows = {}
    local yOffset = -25
    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, card)
        row:SetSize(FRAME_WIDTH - 60, 30)
        row:SetPoint("TOPLEFT", itemsLabel, "BOTTOMLEFT", 5, yOffset)
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -70, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetText("--")
        
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.value:SetJustifyH("RIGHT")
        row.value:SetText("")
        
        row.itemLink = nil
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        card.itemRows[i] = row
        yOffset = yOffset - 32
    end
    
    -- GPH Section
    local gphLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gphLabel:SetPoint("TOPLEFT", card.itemRows[3], "BOTTOMLEFT", -5, -15)
    gphLabel:SetText("|cffffd700Gold Per Hour (GPH)|r")
    
    card.gphValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.gphValue:SetPoint("TOPLEFT", gphLabel, "BOTTOMLEFT", 10, -5)
    card.gphValue:SetText("0g/hr")
    
    -- Reset Button
    local resetBtn = CreateFrame("Button", nil, card, "BackdropTemplate")
    resetBtn:SetSize(100, 24)
    resetBtn:SetPoint("BOTTOM", card, "BOTTOM", 0, 15)
    resetBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    resetBtn:SetBackdropColor(0.4, 0.2, 0.2, 1)
    resetBtn:SetBackdropBorderColor(0.8, 0.4, 0.4, 1)
    
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
    resetText:SetText("|cffffffffReset Session|r")
    
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.3, 0.3, 1)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.2, 0.2, 1)
    end)
    resetBtn:SetScript("OnClick", function()
        LootMonitorModule:ResetSession()
    end)
    
    card:Hide() -- Hidden by default
    
    return card
end

-- Initialize session start time
local function InitializeSession()
    if not sessionData.sessionStartTime then
        sessionData.sessionStartTime = GetTime()
    end
end

-- Reset session data
function LootMonitorModule:ResetSession()
    sessionData.totalGoldLiquid = 0
    sessionData.totalItemValue = 0
    sessionData.totalReputation = 0
    sessionData.sessionStartTime = GetTime()
    wipe(sessionData.topItems)
    
    -- Update the summary card if visible
    if sessionSummaryCard and sessionSummaryShown then
        LootMonitorModule:UpdateSessionSummary()
    end
    
    addon:Print("Session data has been reset.")
end

-- Format time duration
local function FormatDuration(seconds)
    local hours = floor(seconds / 3600)
    local mins = floor((seconds % 3600) / 60)
    local secs = floor(seconds % 60)
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

-- Format large numbers nicely
local function FormatLargeNumber(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fk", num / 1000)
    else
        return tostring(num)
    end
end

-- Calculate GPH (gold per hour) in copper
local function GetEstimatedGPH()
    if not sessionData.sessionStartTime then return 0 end
    
    local elapsed = GetTime() - sessionData.sessionStartTime
    if elapsed < 1 then return 0 end
    
    local totalGold = sessionData.totalGoldLiquid + sessionData.totalItemValue
    local hoursElapsed = elapsed / 3600
    
    return floor(totalGold / hoursElapsed)
end

-- Update session summary card with current data
function LootMonitorModule:UpdateSessionSummary()
    if not sessionSummaryCard then return end
    
    -- Duration
    local elapsed = 0
    if sessionData.sessionStartTime then
        elapsed = GetTime() - sessionData.sessionStartTime
    end
    sessionSummaryCard.duration:SetText("Session: " .. FormatDuration(elapsed))
    
    -- Total Gold
    local totalGold = sessionData.totalGoldLiquid + sessionData.totalItemValue
    sessionSummaryCard.goldValue:SetText(FormatMoneyCompact(totalGold))
    
    local liquidGold = floor(sessionData.totalGoldLiquid / 10000)
    local itemGold = floor(sessionData.totalItemValue / 10000)
    sessionSummaryCard.goldBreakdown:SetText(string.format("|cffc0c0c0Liquid: %dg | Items: %dg|r", liquidGold, itemGold))
    
    -- Reputation
    sessionSummaryCard.repValue:SetText("|cff00ff00+" .. sessionData.totalReputation .. "|r")
    
    -- Top Items
    for i = 1, 3 do
        local row = sessionSummaryCard.itemRows[i]
        local item = sessionData.topItems[i]
        
        if item then
            row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(item.name or "Unknown")
            row.value:SetText(FormatMoneyShort(item.value) or "")
            row.itemLink = item.link
            row:Show()
        else
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText("|cff666666-- Empty --|r")
            row.value:SetText("")
            row.itemLink = nil
            row:Show()
        end
    end
    
    -- GPH
    local gph = GetEstimatedGPH()
    local gphGold = floor(gph / 10000)
    sessionSummaryCard.gphValue:SetText(string.format("|cffffd700%s g/hr|r", FormatLargeNumber(gphGold)))
end

-- Toggle between loot feed and session summary
function LootMonitorModule:ToggleSessionSummary()
    if not mainFrame then return end
    
    -- Initialize session if not started
    InitializeSession()
    
    -- Create card if it doesn't exist
    if not sessionSummaryCard then
        sessionSummaryCard = CreateSessionSummaryCard(mainFrame)
    end
    
    sessionSummaryShown = not sessionSummaryShown
    
    if sessionSummaryShown then
        -- Hide all entry rows
        for _, row in ipairs(entries) do
            row:Hide()
        end
        
        -- Update and show summary card
        LootMonitorModule:UpdateSessionSummary()
        sessionSummaryCard:Show()
    else
        -- Hide summary card
        sessionSummaryCard:Hide()
        
        -- Show entry rows again
        for _, row in ipairs(entries) do
            row:Show()
        end
        LootMonitorModule:RepositionEntries()
    end
end

-- Check if mover is shown
function LootMonitorModule:IsMoverShown()
    return mainFrame and mainFrame.mover and mainFrame.mover:IsShown()
end

-- Simulate events for testing positioning and appearance
function LootMonitorModule:SimulateEvents()
    -- Temporarily bypass the enabled check
    local wasEnabled = addon.db.lootMonitorEnabled
    local wasItemsEnabled = addon.db.lootMonitorShowItems
    local wasMoneyEnabled = addon.db.lootMonitorShowMoney
    local wasCurrencyEnabled = addon.db.lootMonitorShowCurrency
    local wasRepEnabled = addon.db.lootMonitorShowReputation
    
    addon.db.lootMonitorEnabled = true
    addon.db.lootMonitorShowItems = true
    addon.db.lootMonitorShowMoney = true
    addon.db.lootMonitorShowCurrency = true
    addon.db.lootMonitorShowReputation = true
    
    -- Add varied test entries with staggered timing for visual effect
    -- Epic item (purple)
    AddEntry("item", { itemLink = "|cffa335ee|Hitem:50818::::::::70:::::|h[Shadowmourne]|h|r", quantity = 1 })
    
    -- Rare item (blue)
    C_Timer.After(0.15, function()
        AddEntry("item", { itemLink = "|cff0070dd|Hitem:19019::::::::70:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r", quantity = 1 })
    end)
    
    -- Uncommon item (green) with quantity
    C_Timer.After(0.3, function()
        AddEntry("item", { itemLink = "|cff1eff00|Hitem:2589::::::::70:::::|h[Linen Cloth]|h|r", quantity = 20 })
    end)
    
    -- Common item (white)
    C_Timer.After(0.45, function()
        AddEntry("item", { itemLink = "|cffffffff|Hitem:6948::::::::70:::::|h[Hearthstone]|h|r", quantity = 1 })
    end)
    
    -- Money
    C_Timer.After(0.6, function()
        AddEntry("money", { amount = 2500000 }) -- 250g
    end)
    
    -- Currency (Honor)
    C_Timer.After(0.75, function()
        AddEntry("currency", { currencyID = 1792, quantity = 500 })
    end)
    
    -- Reputation
    C_Timer.After(0.9, function()
        AddEntry("reputation", { factionName = "Dornogal", amount = 250, current = 2500, max = 12500 })
    end)
    
    -- Restore original settings
    C_Timer.After(1.0, function()
        addon.db.lootMonitorEnabled = wasEnabled
        addon.db.lootMonitorShowItems = wasItemsEnabled
        addon.db.lootMonitorShowMoney = wasMoneyEnabled
        addon.db.lootMonitorShowCurrency = wasCurrencyEnabled
        addon.db.lootMonitorShowReputation = wasRepEnabled
    end)
    
    addon:Print("Simulated test entries added to Loot Monitor")
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
        
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        -- Parse the reputation message directly from chat
        -- This works for all reputation types including Warband reputations
        local msg = ...
        local factionName, amount = LootMonitorModule:ParseReputationMessage(msg)
        
        if factionName and amount and amount ~= 0 then
            AddEntry("reputation", {
                factionName = factionName,
                amount = amount,
                current = nil,
                max = nil,
                icon = nil
            })
        end
    end
end

-- Parse reputation gain/loss message from CHAT_MSG_COMBAT_FACTION_CHANGE
-- Handles formats like:
-- "Your reputation with FACTION has increased by AMOUNT."
-- "Your Warband's reputation with FACTION increased by AMOUNT."
-- "Reputation with FACTION increased by AMOUNT."
function LootMonitorModule:ParseReputationMessage(msg)
    if not msg then return nil, nil end
    
    -- Pattern to extract faction name and amount
    -- Try "increased by X" pattern first
    local factionName, amount = msg:match("reputation with (.+) .-increased.-by (%d+)")
    if factionName and amount then
        return factionName, tonumber(amount)
    end
    
    -- Try "decreased by X" pattern
    factionName, amount = msg:match("reputation with (.+) .-decreased.-by (%d+)")
    if factionName and amount then
        return factionName, -tonumber(amount)
    end
    
    -- Fallback: Try simpler patterns for different message formats
    -- "Reputation with FACTION increased/decreased by AMOUNT"
    factionName, amount = msg:match("[Rr]eputation with ([^%d]+) increased by (%d+)")
    if factionName and amount then
        return factionName:gsub("%s+$", ""), tonumber(amount) -- Trim trailing spaces
    end
    
    factionName, amount = msg:match("[Rr]eputation with ([^%d]+) decreased by (%d+)")
    if factionName and amount then
        return factionName:gsub("%s+$", ""), -tonumber(amount)
    end
    
    return nil, nil
end

function LootMonitorModule:OnInitialize()
    -- Create the main frame
    mainFrame = CreateMainFrame()
    
    -- Register events
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
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
