local _, ns = ...
local Power = {}
ns.Power = Power

local issecret = FrogLib.issecret

------------------------------------------------------------------------------
-- Fade when idle (FrogLib.Idle): out of combat, at full health, power at rest and (optionally) no
-- target. Secret power is watched until it settles; secret health goes through the full-health gate.
------------------------------------------------------------------------------

local idle -- the watcher (Init)
-- The display's opacity: back in a sixth of a second, out in half.
local fader = FrogLib.Idle.NewFader(nil, { speedIn = 6, speedOut = 2 })

local function Evaluate()
    return idle:Evaluate({ noTarget = ns.db.fade.target, editMode = true })
end

-- force: put our opacity back even if it hasn't changed (Blizzard resets it when it re-shows
-- the display).
function Power:UpdateFade(force)
    local display = ns.Skin.display
    fader.frame = display
    if not (display and idle) then return end
    local fade = ns.db.fade
    local on, secret = false, false
    if fade.enabled then
        local _
        on, _, secret = Evaluate()
    end
    fader:SetGate((on and secret) and "player" or nil)
    fader:Set(on and fade.alpha or 1, force and "again" or nil)
end

function Power:Debug()
    if not idle then return end
    local on, why, secret = Evaluate()
    local health, power = UnitHealth("player"), UnitPower("player", (UnitPowerType("player")))
    local display = ns.Skin.display
    local now = "no display"
    if display then
        local alpha = display:GetAlpha()
        now = issecret(alpha) and "set by the game (health hidden)" or string.format("%.2f", alpha)
    end
    local token = select(2, UnitPowerType("player"))
    ns.Print(string.format("fade %s; idle: %s%s; health %s, power %s (%s); opacity wanted %.2f%s, now %s.",
        ns.db.fade.enabled and "on" or "off", on and "yes" or "no", why and (" (" .. why .. ")") or "",
        issecret(health) and "secret" or tostring(health), issecret(power) and "secret" or tostring(power),
        (not issecret(token) and token) or "?", fader.target, secret and " at full health" or "", now))
end

------------------------------------------------------------------------------
-- Cost marks: a line on the power bar at each chosen ability's cost (Revenge's 5 rage), only for
-- abilities you know that cost the bar's power, so one list serves every character and form.
------------------------------------------------------------------------------

local marks = {}

-- The ability as you know it (by name, so whichever rank you have), and what it costs in powerType.
local function Cost(id, powerType)
    local name = C_Spell.GetSpellName(id)
    local info = name and C_Spell.GetSpellInfo(name)
    if not info then return end
    for _, entry in ipairs(C_Spell.GetSpellPowerCost(info.spellID) or {}) do
        if entry.type == powerType and not issecret(entry.cost) then
            return not issecret(entry.minCost) and entry.minCost and entry.minCost > 0 and entry.minCost or entry.cost
        end
    end
end

local Snap = FrogLib.PixelSnap

function Power:UpdateMarks()
    for _, mark in ipairs(marks) do mark:Hide() end
    local settings = ns.db.marks
    local _, _, bar = ns.Skin:Find()
    if not (bar and settings.enabled) then return end
    local powerType = UnitPowerType("player")
    local max = UnitPowerMax("player", powerType)
    local width = bar:GetWidth()
    if issecret(max) or not max or max <= 0 or not width or width <= 0 then return end
    -- One screen pixel, in the bar's units; marks sit on whole pixels so they stay sharp.
    local pixel = FrogLib.Pixel(bar)
    local color = settings.color
    local shown = 0
    for _, id in ipairs(settings.spells) do
        local cost = Cost(id, powerType)
        if cost and cost > 0 and cost < max then
            shown = shown + 1
            local mark = marks[shown]
            if not mark then
                mark = bar:CreateTexture(nil, "OVERLAY", nil, 7)
                mark.prtOwned = true -- the skin hides every other unnamed texture on the bar
                Snap(mark)
                marks[shown] = mark
            end
            mark:SetColorTexture(color.r, color.g, color.b, color.a or 1)
            local x = math.floor(width * cost / max / pixel + 0.5) * pixel
            mark:ClearAllPoints()
            mark:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
            mark:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
            mark:SetWidth(pixel * settings.width)
            mark:Show()
        end
    end
end

------------------------------------------------------------------------------
-- The five-second rule: spending mana stops regen for 5 seconds, which a strip under the bar showing
-- your mana fills across. FrogLib.FSR says when they start (from the spell's cost, or your mana's drop).
------------------------------------------------------------------------------

local MANA = (Enum.PowerType and Enum.PowerType.Mana) or 0
local RULE = FrogLib.FSR.RULE
local regenAt -- when regen starts again
local fsr = FrogLib.FSR.NewWatcher(function() Power:StartRegenTimer() end)

-- The bar that shows your mana: the main one in caster form, the form's mana bar in a form.
local function ManaBar()
    local _, _, power, alt = ns.Skin:Find()
    if FrogLib.Safe(UnitPowerType("player")) == MANA then return power end
    if alt and alt:IsShown() then return alt end
end

local regen = FrogLib.FSR.NewStrip()

regen:SetScript("OnUpdate", function(self)
    local left = regenAt and (regenAt - GetTime()) or 0
    local bar = ManaBar()
    if left <= 0 or not bar or not ns.db.regen.enabled then
        self:Hide()
        return
    end
    if self.bar ~= bar then
        -- Under that bar, two pixels tall, a pixel below its edge.
        self.bar = bar
        -- On the display, not the bar: the main power bar clips anything outside its edges.
        self:SetParent(ns.Skin.display or bar:GetParent())
        self:SetFrameStrata(bar:GetFrameStrata())
        local pixel = FrogLib.Pixel(self)
        self:Place(bar, pixel, pixel)
        self:SetFrameLevel(bar:GetFrameLevel() + 5)
    end
    self:SetLeft(left)
end)

function Power:StartRegenTimer()
    if not ns.db.regen.enabled then return end
    regenAt = GetTime() + RULE
    local color = ns.db.regen.color
    regen:SetColor(color.r, color.g, color.b, 0.9)
    regen.bar = nil -- placed afresh: the mana bar may have changed
    regen:Show()
end

------------------------------------------------------------------------------
-- Starting up
------------------------------------------------------------------------------

function Power:Init()
    -- The fade: the watcher listens to your health, power, combat, target and Edit Mode itself.
    idle = FrogLib.Idle.NewWatcher({ unit = "player", events = true, onUpdate = function(kind)
        Power:UpdateFade()
        -- A health change while the fade waits on the gate: played again, so it fades smoothly
        -- once the game sees you at full health.
        if kind == "health" then fader:Replay() end
    end })
    fsr:Listen()
    -- The cost marks.
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        events:RegisterUnitEvent(event, "player")
    end
    events:SetScript("OnEvent", function() Power:UpdateMarks() end)
    self:Apply()
end

function Power:Apply()
    local display, _, bar = ns.Skin:Find()
    if display and not self.hooked then
        self.hooked = true
        display:HookScript("OnShow", function() Power:UpdateFade(true) end)
        if bar then bar:HookScript("OnSizeChanged", function() Power:UpdateMarks() end) end
    end
    self:UpdateMarks()
    self:UpdateFade(true)
end
