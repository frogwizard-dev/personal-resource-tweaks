local _, ns = ...

-- Clicks on the Personal Resource Display: left-click targets you, right-click opens your unit
-- menu (as on the player frame).
-- A secure button sits over the display. It copies the display's place and size rather than
-- anchoring to it: anything a secure frame is anchored to becomes protected, and the display is
-- re-laid by Blizzard's own code in combat. A unit button's own "togglemenu" is gated on 12.x, so
-- right-click runs "/click" on a hidden SecureActionButton child whose togglemenu isn't (as
-- XIVPlayer does). Secure frames can only be placed and shown out of combat; the place is checked
-- once a second then, and changes made in combat wait. When the display only shows in combat (its
-- Edit Mode setting), the button does too, through a state driver.

local Clicks = {}
ns.Clicks = Clicks

local function Display() return _G.PersonalResourceDisplayFrame end

local function MakeButton()
    local b = CreateFrame("Button", "PersonalResourceTweaksClick", UIParent, "SecureUnitButtonTemplate")
    b:SetAttribute("unit", "player")
    b:SetAttribute("*type1", "target")
    b:RegisterForClicks("AnyUp")

    local menu = CreateFrame("Button", "PersonalResourceTweaksClickMenu", b, "SecureActionButtonTemplate")
    menu:SetSize(1, 1)
    menu:EnableMouse(false)
    menu:RegisterForClicks("AnyUp")
    for i = 1, 5 do menu:SetAttribute("type" .. i, "togglemenu") end
    menu:SetAttribute("useparent-unit", true)
    menu:SetAttribute("useOnKeyDown", false) -- act on the up-click whatever the key-down setting
    b:SetAttribute("*type2", "macro")
    b:SetAttribute("*macrotext2", "/click PersonalResourceTweaksClickMenu")
    b:Hide()
    return b
end

-- When the button should be up: the display's own visibility setting.
local function VisibilityRule()
    local prd = Display()
    local setting = prd and prd.GetVisibleSetting and prd:GetVisibleSetting()
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
    local prd = Display()
    -- Out of the way in Edit Mode, where clicks on the display select it to move it.
    local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
    local on = ns.db.clicks.enabled and prd ~= nil and not editing
    if not on then
        self.rule = nil
        if self.button then
            UnregisterStateDriver(self.button, "visibility")
            self.button:Hide()
        end
        return
    end
    self.button = self.button or MakeButton()
    local b = prd:GetLeft() and self.button
    if not b then return end
    -- The display's rectangle, in UIParent's terms.
    local s = prd:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local left, bottom, w, h = prd:GetLeft() * s, prd:GetBottom() * s, prd:GetWidth() * s, prd:GetHeight() * s
    local key = ("%.1f %.1f %.1f %.1f"):format(left, bottom, w, h)
    if key ~= self.placed then
        self.placed = key
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        b:SetSize(math.max(1, w), math.max(1, h))
    end
    local rule = VisibilityRule()
    if rule ~= self.rule then
        self.rule = rule
        RegisterStateDriver(b, "visibility", rule)
    end
end

function Clicks:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function() self:Place() end)
    -- The display can move (Edit Mode) or resize (its settings); a light check while out of combat.
    local t = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        if t < 1 then return end
        t = 0
        if not InCombatLockdown() then self:Place() end
    end)
    self:Place()
end
