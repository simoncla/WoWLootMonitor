---@class LootMonitor
local addonName, addon = ...

-- Create the main addon table and make it globally accessible
LootMonitor = addon

-- Addon metadata
addon.name = addonName
addon.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

-- Saved variables default structure
addon.defaults = {
    -- Loot Monitor
    lootMonitorEnabled = true,
    lootMonitorShowItems = true,
    lootMonitorShowMoney = true,
    lootMonitorShowCurrency = true,
    lootMonitorShowReputation = true,
    lootMonitorMaxEntries = 8,
    
    -- Loot Monitor Duration by Quality (seconds)
    lootMonitorDurationPoor = 3,
    lootMonitorDurationCommon = 5,
    lootMonitorDurationUncommon = 10,
    lootMonitorDurationRare = 15,
    lootMonitorDurationEpic = 20,
    lootMonitorDurationLegendary = 40,
    lootMonitorDurationArtifact = 15,
    lootMonitorDurationHeirloom = 15,
    
    -- Loot Monitor Duration by Type (seconds)
    lootMonitorDurationGold = 3,
    lootMonitorDurationReputation = 15,
    lootMonitorDurationCurrency = 15,
    
    -- Loot Monitor Display Options
    lootMonitorShowCopperSilver = true, -- Show low-value money pickups
    lootMonitorShowHonor = true, -- Show honor currency
    lootMonitorShowAHPrice = true, -- Show auction house price from Auctionator/TSM
    lootMonitorFadeSlide = "right", -- Slide direction when fading: "none", "left", "right"
    lootMonitorFadeDuration = 0.5, -- Fade/slide duration in seconds (0.1 to 2.0)
}

-- Initialize saved variables
local function InitializeSavedVariables()
    if not LootMonitorDB then
        LootMonitorDB = {}
    end
    
    -- Merge defaults with saved data
    for key, value in pairs(addon.defaults) do
        if LootMonitorDB[key] == nil then
            LootMonitorDB[key] = value
        end
    end
    
    addon.db = LootMonitorDB
end

-- Print helper function
function addon:Print(...)
    local prefix = "|cff00ff00[Loot Monitor]|r"
    print(prefix, ...)
end

-- Module registration system
addon.modules = {}
addon.pendingModules = {}
addon.initialized = false

function addon:RegisterModule(name, module)
    self.modules[name] = module
    
    -- If addon is already initialized, call OnInitialize immediately
    if self.initialized then
        if module.OnInitialize then
            module:OnInitialize()
        end
    else
        -- Queue for later initialization
        table.insert(self.pendingModules, module)
    end
end

function addon:InitializeAllModules()
    self.initialized = true
    for _, module in ipairs(self.pendingModules) do
        if module.OnInitialize then
            module:OnInitialize()
        end
    end
    wipe(self.pendingModules)
end

function addon:GetModule(name)
    return self.modules[name]
end

-- Main event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            InitializeSavedVariables()
            addon:InitializeAllModules()  -- Initialize all queued modules now that db is ready
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        addon:Print("v" .. addon.version .. " loaded. Type /lm for commands.")
    end
end)
