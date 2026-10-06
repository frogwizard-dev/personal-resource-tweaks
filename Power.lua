local _, ns = ...
local Power = {}
ns.Power = Power

local issecret = ns.issecret

------------------------------------------------------------------------------
-- Fade when idle (FrogLib.Idle): out of combat, at full health, with your power at rest (rage
-- empty, mana or energy full) and, optionally, no target, the display fades out; anything else
-- brings it back. Power the game keeps secret is watched instead: out of combat it ticks until
-- it's full or empty and then stops, so a few quiet seconds mean it's settled. Health the game
-- keeps secret goes through FrogLib's full-health gate: the game itself reads it, and the display
-- only fades at full health (waiting for it to settle faded it at low health too).
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
    local prd = ns.Skin.prd
    fader.frame = prd
    if not (prd and idle) then return end
    local cfg = ns.db.fade
    local on, secret = false, false
    if cfg.enabled then
        local _
        on, _, secret = Evaluate()
    end
    fader:SetGate((on and secret) and "player" or nil)
    fader:Set(on and cfg.alpha or 1, force and "again" or nil)
end

function Power:Debug()
    if not idle then return end
    local on, why, secret = Evaluate()
    local h, p = UnitHealth("player"), UnitPower("player", (UnitPowerType("player")))
    local prd = ns.Skin.prd
    local now = "no display"
    if prd then
        local a = prd:GetAlpha()
        now = issecret(a) and "set by the game (health hidden)" or string.format("%.2f", a)
    end
    local token = select(2, UnitPowerType("player"))
    ns.Print(string.format("fade %s; idle: %s%s; health %s, power %s (%s); opacity wanted %.2f%s, now %s.",
        ns.db.fade.enabled and "on" or "off", on and "yes" or "no", why and (" (" .. why .. ")") or "",
        issecret(h) and "secret" or tostring(h), issecret(p) and "secret" or tostring(p),
        (not issecret(token) and token) or "?", fader.target, secret and " at full health" or "", now))
end

------------------------------------------------------------------------------
-- Cost marks: a thin line on the power bar at the cost of each chosen ability (Revenge's 5 rage,
-- Heroic Strike's 15), so you can see at a glance what you can afford. Only for abilities you
-- know that cost the power the bar shows, so one list serves every character and form.
------------------------------------------------------------------------------

local marks = {}

-- The ability as you know it (by name, so whichever rank you have), and what it costs in pType.
local function Cost(id, pType)
    local name = C_Spell.GetSpellName(id)
    local info = name and C_Spell.GetSpellInfo(name)
    if not info then return end
    for _, c in ipairs(C_Spell.GetSpellPowerCost(info.spellID) or {}) do
        if c.type == pType and not issecret(c.cost) then
            local cost = not issecret(c.minCost) and c.minCost and c.minCost > 0 and c.minCost or c.cost
            return cost
        end
    end
end

local Snap = FrogLib.PixelSnap

function Power:UpdateMarks()
    for _, mark in ipairs(marks) do mark:Hide() end
    local cfg = ns.db.marks
    local _, _, bar = ns.Skin:Find()
    if not (bar and cfg.enabled) then return end
    local pType = UnitPowerType("player")
    local max = UnitPowerMax("player", pType)
    local width = bar:GetWidth()
    if issecret(max) or not max or max <= 0 or not width or width <= 0 then return end
    -- One screen pixel, in the bar's units; marks sit on whole pixels so they stay sharp.
    local px = FrogLib.Pixel(bar)
    local c = cfg.color
    local n = 0
    for _, id in ipairs(cfg.spells) do
        local cost = Cost(id, pType)
        if cost and cost > 0 and cost < max then
            n = n + 1
            local mark = marks[n]
            if not mark then
                mark = bar:CreateTexture(nil, "OVERLAY", nil, 7)
                mark.prtOwned = true -- the skin hides every other unnamed texture on the bar
                Snap(mark)
                marks[n] = mark
            end
            mark:SetColorTexture(c.r, c.g, c.b, c.a or 1)
            local x = math.floor(width * cost / max / px + 0.5) * px
            mark:ClearAllPoints()
            mark:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
            mark:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
            mark:SetWidth(px * cfg.width)
            mark:Show()
        end
    end
end

------------------------------------------------------------------------------
-- Mana regen (the five-second rule): spending mana stops your regen for 5 seconds. A thin
-- strip under whichever bar shows your mana fills across those 5 seconds, a spark at its tip,
-- and goes when regen starts again. FrogLib.FSR says when it starts: from the cost of the spell
-- cast (spell data, not your mana, which the game may keep secret), or, for a spell the game
-- keeps secret, from the drop in your mana that comes with it.
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

local regen = CreateFrame("Frame")
regen:Hide()
regen.strip = regen:CreateTexture(nil, "OVERLAY")
regen.spark = regen:CreateTexture(nil, "OVERLAY", nil, 1)
regen.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
regen.spark:SetBlendMode("ADD")

regen:SetScript("OnUpdate", function(self)
    local left = regenAt and (regenAt - GetTime()) or 0
    local bar = ManaBar()
    if left <= 0 or not bar or not ns.db.regen.enabled then
        self:Hide()
        return
    end
    if self.bar ~= bar then
        -- Under that bar, two pixels tall, just below its edge.
        self.bar = bar
        -- On the display, not the bar: the main power bar clips anything outside its edges.
        self:SetParent(ns.Skin.prd or bar:GetParent())
        self:SetFrameStrata(bar:GetFrameStrata())
        local px = FrogLib.Pixel(self)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -px)
        self:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -px)
        self:SetHeight(px * 2)
        self:SetFrameLevel(bar:GetFrameLevel() + 5)
        self.spark:SetSize(px * 8, px * 10)
    end
    local width = (1 - left / RULE) * self:GetWidth()
    self.strip:ClearAllPoints()
    self.strip:SetPoint("TOPLEFT")
    self.strip:SetPoint("BOTTOMLEFT")
    self.strip:SetWidth(math.max(0.01, width))
    self.spark:ClearAllPoints()
    self.spark:SetPoint("CENTER", self, "LEFT", width, 0)
end)

function Power:StartRegenTimer()
    if not ns.db.regen.enabled then return end
    regenAt = GetTime() + RULE
    local c = ns.db.regen.color
    regen.strip:SetColorTexture(c.r, c.g, c.b, 0.9)
    regen.spark:SetVertexColor(c.r, c.g, c.b)
    regen.bar = nil -- placed afresh: the mana bar may have changed
    regen:Show()
end

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
    local ev = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
        ev:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        ev:RegisterUnitEvent(event, "player")
    end
    ev:SetScript("OnEvent", function() Power:UpdateMarks() end)
    self:Apply()
end

function Power:Apply()
    local prd, _, bar = ns.Skin:Find()
    if prd and not self.hooked then
        self.hooked = true
        prd:HookScript("OnShow", function() Power:UpdateFade(true) end)
        if bar then bar:HookScript("OnSizeChanged", function() Power:UpdateMarks() end) end
    end
    self:UpdateMarks()
    self:UpdateFade(true)
end
