local _, ns = ...

-- Clicks on the Personal Resource Display: left-click targets you, right-click opens your unit menu.
-- FrogLib.Secure's button copies the display's place and size rather than anchoring to it (a frame a
-- secure one is anchored to turns protected, and Blizzard re-lays the display in combat). It's placed
-- out of combat, checked once a second, and a state driver follows the display's visibility setting.

local Clicks = {}
ns.Clicks = Clicks

local function Display() return _G.PersonalResourceDisplayFrame end

local function MakeButton()
    return (FrogLib.Secure.UnitButton("PersonalResourceTweaksClick", "player"))
end

-- When the button should be up: the display's own visibility setting.
local function VisibilityRule()
    local display = Display()
    local setting = display and display.GetVisibleSetting and display:GetVisibleSetting()
    local modes = Enum.PersonalResourceDisplayVisibleSetting
    if modes and setting == modes.InCombat then return "[combat] show; hide" end
    if modes and modes.Hidden and setting == modes.Hidden then return "hide" end
    return "show"
end

function Clicks:Place()
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = nil
    local display = Display()
    -- Out of the way in Edit Mode, where clicks on the display select it to move it.
    local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
    local on = ns.db.clicks.enabled and display ~= nil and not editing
    if not on then
        self.rule = nil
        if self.button then
            UnregisterStateDriver(self.button, "visibility")
            self.button:Hide()
        end
        return
    end
    self.button = self.button or MakeButton()
    local button = display:GetLeft() and self.button
    if not button then return end
    -- The display's rectangle, in UIParent's terms; down to the bars only while our combo points hide
    -- Blizzard's, whose room the display keeps (Combo.lua).
    local scale = display:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local top, bottom = display:GetTop(), ns.Combo:BarsBottom() or display:GetBottom()
    local left, width = display:GetLeft() * scale, display:GetWidth() * scale
    local height = (top - bottom) * scale
    bottom = bottom * scale
    local key = ("%.1f %.1f %.1f %.1f"):format(left, bottom, width, height)
    if key ~= self.placed then
        self.placed = key
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        button:SetSize(math.max(1, width), math.max(1, height))
    end
    local rule = VisibilityRule()
    if rule ~= self.rule then
        self.rule = rule
        RegisterStateDriver(button, "visibility", rule)
    end
end

function Clicks:Init()
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function() self:Place() end)
    -- The display can move (Edit Mode) or resize (its settings); a light check while out of combat.
    local waited = 0
    events:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 1 then return end
        waited = 0
        if not InCombatLockdown() then self:Place() end
    end)
    self:Place()
end
