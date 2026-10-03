local _, ns = ...
local Power = {}
ns.Power = Power

local issecret = ns.issecret

------------------------------------------------------------------------------
-- Fade when idle: out of combat, at full health, with your power at rest (rage empty, mana or
-- energy full) and, optionally, no target, the display fades out; anything else brings it back.
-- Values that are secret count as "not idle", so it never hides when it can't tell.
------------------------------------------------------------------------------

-- Power that sits at empty when you're resting (it builds up in combat), rather than full.
local EMPTY_AT_REST = { RAGE = true, RUNIC_POWER = true, LUNAR_POWER = true, MAELSTROM = true,
    INSANITY = true, FURY = true, PAIN = true }
local SPEED_IN, SPEED_OUT = 6, 2 -- opacity per second: back in a sixth of a second, out in half

-- Idle or not, and why not (for /prt fade). Health or power the game keeps secret is skipped
-- rather than counted against idling: out of combat both settle by themselves.
local function Idle()
    local cfg = ns.db.fade
    if InCombatLockdown() or UnitAffectingCombat("player") then return false, "in combat" end
    if cfg.target and UnitExists("target") then return false, "you have a target" end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return false, "Edit Mode is open" end
    local h, hm = UnitHealth("player"), UnitHealthMax("player")
    if not (issecret(h) or issecret(hm)) and h < hm then return false, "health isn't full" end
    local pType, token = UnitPowerType("player")
    local p, pm = UnitPower("player", pType), UnitPowerMax("player", pType)
    if not (issecret(p) or issecret(pm)) then
        if EMPTY_AT_REST[token] and p > 0 then return false, (token or "power") .. " isn't empty" end
        if not EMPTY_AT_REST[token] and p < pm then return false, (token or "power") .. " isn't full" end
    end
    return true
end

local target, current = 1, 1
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
    local prd = ns.Skin.prd
    if not prd then
        self:Hide()
        return
    end
    if current < target then
        current = math.min(target, current + elapsed * SPEED_IN)
    else
        current = math.max(target, current - elapsed * SPEED_OUT)
    end
    prd:SetAlpha(current)
    if current == target then self:Hide() end
end)

-- force: put our opacity back even if it hasn't changed (Blizzard resets it when it re-shows
-- the display).
function Power:UpdateFade(force)
    local cfg = ns.db.fade
    local want = (cfg.enabled and Idle()) and cfg.alpha or 1
    if want == target and not force then return end
    if force and ns.Skin.prd then current = ns.Skin.prd:GetAlpha() end
    target = want
    fader:Show()
end

function Power:Debug()
    local idle, why = Idle()
    local h, p = UnitHealth("player"), UnitPower("player", (UnitPowerType("player")))
    local prd = ns.Skin.prd
    ns.Print(string.format("fade %s; idle: %s%s; health %s, power %s (%s); opacity wanted %.2f, now %s.",
        ns.db.fade.enabled and "on" or "off", idle and "yes" or "no", why and (" (" .. why .. ")") or "",
        issecret(h) and "secret" or tostring(h), issecret(p) and "secret" or tostring(p),
        select(2, UnitPowerType("player")) or "?", target, prd and string.format("%.2f", prd:GetAlpha()) or "no display"))
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
            local cost = c.minCost and not issecret(c.minCost) and c.minCost > 0 and c.minCost or c.cost
            return cost
        end
    end
end

local function Snap(region)
    if region.SetRoundLayoutToNearestPixel then region:SetRoundLayoutToNearestPixel(true) end
    if region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        region:SetTexelSnappingBias(0)
    end
end

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
    local px = 768 / select(2, GetPhysicalScreenSize()) / bar:GetEffectiveScale()
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

function Power:Init()
    local ev = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED",
        "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
        ev:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER" }) do
        ev:RegisterUnitEvent(event, "player")
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "SPELLS_CHANGED" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER"
            or event == "PLAYER_ENTERING_WORLD" then
            Power:UpdateMarks()
        end
        Power:UpdateFade()
    end)
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() Power:UpdateFade() end, self)
        EventRegistry:RegisterCallback("EditMode.Exit", function() Power:UpdateFade() end, self)
    end
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
