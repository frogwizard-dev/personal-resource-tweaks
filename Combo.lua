local _, ns = ...
local Combo = {}
ns.Combo = Combo

------------------------------------------------------------------------------
-- Combo points: a row of flat pips under (or over) the bars, in the bars' texture and border.
-- Forever's display has no class resource of its own (its Camelot code turns the class frame
-- off, and the modern combo point bars aren't loaded), so the pips are ours, drawn from the
-- same numbers Blizzard's target frame uses: GetComboPoints("player", "target") out of
-- UnitPowerMax's combo points. Rogues always; druids only in cat form, where they have them.
--
-- The count may be a secret value, so it's never compared: each pip is a status bar running
-- from i - 1 to i, handed the count as its value, which the game fills (count >= i) or leaves
-- empty (count <= i - 1). The colour at max works the same way: a second bar on every pip,
-- from max - 1 to max, fills only when you have them all.
------------------------------------------------------------------------------

local issecret = ns.issecret
local Borders, NoSnap, Snap = FrogLib.Borders, FrogLib.NoSnap, FrogLib.PixelSnap
local C = FrogLib.Combo -- who has them, how many, the count (FrogLib's Combo.lua)

local holder -- the row's frame, on the display; made on first use
local pips = {}
local count = 0 -- pips in use (the max)

local Pixel = FrogLib.Pixel

-- Your class colour (FrogLib.Color's: a class colour add-on's first); white if it can't tell.
local function ClassColor()
    local _, class = UnitClass("player")
    local r, g, b = FrogLib.Color.Class(class)
    if r then return r, g, b end
    return 1, 1, 1
end

-- Whether this character has combo points at all (the row's space above the bars is kept for
-- them even out of cat form, so the buffs don't jump with every shift).
local HasPoints = C.Has

-- Whether the row shows now: rogues always, druids in cat form (the form with energy), and both
-- in Edit Mode so it can be seen while you place the display.
local function Wanted()
    local cfg = ns.db.combo
    if not (cfg.enabled and HasPoints()) then return false end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return true end
    return C.Active()
end

-- How many points you can have, and your points on your target (may be secret: widgets only).
local MaxPoints, Points = C.Max, C.Points

-- How far the border reaches outside each pip, in screen pixels, so gaps are measured between
-- borders rather than under them.
local function Outset(px)
    local s = ns.db.skin
    return Borders.Reach(s.borderStyle, { size = s.borderSize, thickness = s.frameThickness }, px)
end

local function MakePip(i)
    local pip = CreateFrame("Frame", nil, holder)
    pip.bg = pip:CreateTexture(nil, "BACKGROUND", nil, -8)
    pip.bg:SetAllPoints()
    pip.bg:SetColorTexture(0, 0, 0, 0.6)
    pip.fill = CreateFrame("StatusBar", nil, pip)
    pip.fill:SetAllPoints()
    pip.fill:SetMinMaxValues(i - 1, i)
    pip.maxFill = CreateFrame("StatusBar", nil, pip)
    pip.maxFill:SetAllPoints()
    pip.maxFill:SetFrameLevel(pip.fill:GetFrameLevel() + 1)
    -- The borders on a frame above both fills, as on the bars: the Forever frame's inner line
    -- sits over the fill's edge.
    local b = CreateFrame("Frame", nil, pip)
    b:SetAllPoints()
    b:SetFrameLevel(pip.fill:GetFrameLevel() + 2)
    Snap(b)
    b.edges = Borders.Edges(b, b, "OVERLAY")
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do Snap(b.edges[key]) end
    b.forever = Borders.Forever(b, "OVERLAY", 5)
    pip.border = b
    pip.stone = Borders.Stone(pip, 3)
    pips[i] = pip
    return pip
end

-- Texture, colours and border from the bar settings, onto each pip.
local function Style(pip)
    local s, cfg = ns.db.skin, ns.db.combo
    for _, bar in ipairs({ pip.fill, pip.maxFill }) do
        bar:SetStatusBarTexture(s.texture)
        NoSnap(bar:GetStatusBarTexture())
    end
    if cfg.classColor then
        pip.fill:SetStatusBarColor(ClassColor())
    else
        pip.fill:SetStatusBarColor(cfg.color.r, cfg.color.g, cfg.color.b)
    end
    pip.maxFill:SetStatusBarColor(cfg.maxColor.r, cfg.maxColor.g, cfg.maxColor.b)
    pip.maxFill:SetMinMaxValues(count - 1, count)
    pip.maxFill:SetShown(cfg.maxEnabled)
    pip.bg:SetShown(s.background)
    Borders.Show({ edges = pip.border.edges, stone = pip.stone, forever = pip.border.forever }, s.borderStyle,
        { size = s.borderSize, color = s.borderColor, thickness = s.frameThickness })
end

-- The row's place and the pips' sizes, all in whole screen pixels. With no point width set, the
-- pips span the bars' width, the pixels left over going one each to the first pips.
function Combo:Layout()
    local prd = ns.Skin.prd
    if not (holder and prd) then return end
    local cfg = ns.db.combo
    local px = Pixel(holder)
    local out = Outset(px)
    local step = cfg.spacing + 2 * out -- from one pip's edge to the next one's
    local full = math.floor(prd:GetWidth() / px + 0.5)
    local each, extra, total
    if cfg.width > 0 then
        each, extra = cfg.width, 0
        total = count * each + (count - 1) * step
    else
        local room = full - (count - 1) * step
        each = math.max(1, math.floor(room / count))
        extra = math.max(0, room - each * count)
        total = full
    end
    local x0 = math.floor((full - total) / 2) * px
    local gap = (cfg.gap + 2 * out) * px
    holder:ClearAllPoints()
    if cfg.position == "above" then
        holder:SetPoint("BOTTOMLEFT", prd, "TOPLEFT", x0, gap)
    else
        holder:SetPoint("TOPLEFT", prd, "BOTTOMLEFT", x0, -gap)
    end
    holder:SetSize(math.max(1, total) * px, cfg.height * px)
    local x = 0
    for i = 1, count do
        local pip = pips[i]
        local w = each + (i <= extra and 1 or 0)
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", holder, "TOPLEFT", x * px, 0)
        pip:SetSize(w * px, cfg.height * px)
        Style(pip)
        x = x + w + step
    end
end

-- Lights the pips: the count straight into each one's status bar.
function Combo:Update()
    if not (holder and holder:IsShown()) then return end
    local points = Points()
    for i = 1, count do
        pips[i].fill:SetValue(points)
        pips[i].maxFill:SetValue(points)
    end
end

function Combo:Apply()
    local prd = ns.Skin.prd
    local wanted = prd and Wanted()
    if not wanted then
        if holder then holder:Hide() end
        return
    end
    if not holder then
        holder = CreateFrame("Frame", nil, prd)
        -- Width and scale changes (Edit Mode, our bar sizes) and the alt bar coming and going
        -- (which moves the display's bottom) all resize the display.
        prd:HookScript("OnSizeChanged", function() Combo:Layout() end)
    end
    holder:SetParent(prd)
    holder:SetFrameLevel(prd:GetFrameLevel() + 10)
    count = MaxPoints()
    for i = 1, count do
        local pip = pips[i] or MakePip(i)
        pip:Show()
    end
    for i = count + 1, #pips do pips[i]:Hide() end
    holder:Show()
    self:Layout()
    self:Update()
end

-- Space the row takes above the health bar, in the display's units, for the buffs to sit over.
-- Kept whenever the character has combo points, so shifting in and out of cat form doesn't
-- move them.
function Combo:SpaceAbove()
    local prd = ns.Skin.prd
    local cfg = ns.db and ns.db.combo
    if not (prd and cfg and cfg.enabled and cfg.position == "above" and HasPoints()) then return 0 end
    local px = Pixel(prd)
    return (cfg.gap + cfg.height + 2 * Outset(px)) * px
end

function Combo:Debug()
    local p, m = Points(), UnitPowerMax("player", (Enum.PowerType and Enum.PowerType.ComboPoints) or 4)
    ns.Print(string.format("combo points: %s; showing %s; points %s of %s; %d pips.",
        ns.db.combo.enabled and "on" or "off", holder and holder:IsVisible() and "yes" or "no",
        issecret(p) and "secret" or tostring(p), issecret(m) and "secret" or tostring(m), count))
end

function Combo:Init()
    -- A form, the max or the world changed: whether it shows, and how many pips.
    C.Watch(function() Combo:Update() end, function() Combo:Apply() end)
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() Combo:Apply() end, self)
        EventRegistry:RegisterCallback("EditMode.Exit", function() Combo:Apply() end, self)
    end
    self:Apply()
end
