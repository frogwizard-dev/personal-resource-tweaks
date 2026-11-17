local _, ns = ...
local Combo = {}
ns.Combo = Combo

------------------------------------------------------------------------------
-- Combo points: a row of flat pips under (or over) the bars, in their texture and border: rogues
-- always, druids in cat form. Since a Forever update the display draws its own row of them under the
-- bars too, which is hidden while ours is on.
------------------------------------------------------------------------------

local issecret = FrogLib.issecret
local Borders, NoSnap = FrogLib.Borders, FrogLib.NoSnap
local ComboKit = FrogLib.Combo -- who has them, how many, the count (FrogLib's Combo.lua)

local holder -- the row's frame, on the display; made on first use
local pips = {}
local count = 0 -- pips in use (the max)

local Pixel = FrogLib.Pixel

-- Whether this character has combo points at all (the row's space above the bars is kept for
-- them even out of cat form, so the buffs don't jump with every shift).
local HasPoints = ComboKit.Has

-- Whether the row shows now: rogues always, druids in cat form (the form with energy), and both
-- in Edit Mode so it can be seen while you place the display.
local function Wanted()
    local settings = ns.db.combo
    if not (settings.enabled and HasPoints()) then return false end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return true end
    return ComboKit.Active()
end

-- How many points you can have, and your points on your target (may be secret: widgets only).
local MaxPoints, Points = ComboKit.Max, ComboKit.Points

-- Forever's gamepad UI: changing Blizzard's frames from add-on code then taints its controls.
local function GamepadUI()
    local check = InputUtil and InputUtil.IsGamepadUIEnabled
    if not check then return false end
    local ok, on = pcall(check)
    return ok and on == true
end

-- Blizzard's own row (the display's ClassFrameContainer), hidden by alpha while ours is on: Blizzard
-- shows and hides it itself, so never Hide. Not hidden in the gamepad UI, where Edit Mode's "Hide
-- Class Resource" does the same; the player is told that once. Put back whenever ours goes off,
-- gamepad or not, as it was only ever hidden by us.
local hidBlizzard, toldGamepad = false, false

local function HideBlizzardRow(display)
    local row = display.ClassFrameContainer
    local hide = (row and ns.db.combo.enabled and HasPoints()) and true or false
    if hide == hidBlizzard then return end
    if hide and GamepadUI() then
        -- Edit Mode applies a saved "Hide Class Resource" after login: wait for its layout.
        local editMode = EditModeManagerFrame
        local laidOut = not (editMode and editMode.IsInitialized) or editMode:IsInitialized()
        if laidOut and not toldGamepad and row:IsShown() then
            toldGamepad = true
            ns.Print(string.format("In the gamepad UI, Blizzard's own combo points stay under your bars too, as "
                .. "changing Blizzard's frames there would break the gamepad controls. To see only these, tick "
                .. "\"%s\" for the Personal Resource Display in Edit Mode (druids: in cat form).",
                HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_HIDE_CLASS_INFO or "Hide Class Resource"))
        end
        return
    end
    hidBlizzard = hide
    row:SetAlpha(hide and 0 or 1)
end

-- The bars from the bottom up. The row hangs under the lowest one shown, not under the display:
-- the display keeps room below the bars for Blizzard's row even while it's hidden.
local BARS = { "AlternatePowerBar", "PowerBar", "HealthBarsContainer" }

local function LowestBar(display)
    for _, key in ipairs(BARS) do
        local bar = display[key]
        if bar and bar:IsShown() then return bar end
    end
    return display
end

-- The bottom of the lowest bar while we hide Blizzard's row, for the click button: the display's own
-- bottom still takes in that row's room, which nothing is drawn in. Nil when the display's is right.
function Combo:BarsBottom()
    local display = ns.Skin.display
    if not (hidBlizzard and display) then return end
    local bar = LowestBar(display)
    if bar ~= display then return bar:GetBottom() end
end

-- How far the border reaches outside each pip, in screen pixels, so gaps are measured between
-- borders rather than under them.
local function Outset(pixel)
    local skin = ns.db.skin
    return Borders.Reach(skin.borderStyle, { size = skin.borderSize, thickness = skin.frameThickness }, pixel)
end

-- Each pip is a status bar from index - 1 to index handed the count, which may be secret: the game
-- fills it or not. maxFill, from max - 1 to max, lights every pip only at full points.
local function MakePip(index)
    local pip = CreateFrame("Frame", nil, holder)
    pip.bg = pip:CreateTexture(nil, "BACKGROUND", nil, -8)
    pip.bg:SetAllPoints()
    pip.bg:SetColorTexture(0, 0, 0, 0.6)
    pip.fill = CreateFrame("StatusBar", nil, pip)
    pip.fill:SetAllPoints()
    pip.fill:SetMinMaxValues(index - 1, index)
    pip.maxFill = CreateFrame("StatusBar", nil, pip)
    pip.maxFill:SetAllPoints()
    pip.maxFill:SetFrameLevel(pip.fill:GetFrameLevel() + 1)
    -- The borders on a frame above both fills, as on the bars: the Forever frame's inner line
    -- sits over the fill's edge.
    local border = ns.Skin.EdgeFrame(pip)
    border:SetFrameLevel(pip.fill:GetFrameLevel() + 2)
    border.forever = Borders.Forever(border, "OVERLAY", 5)
    pip.border = border
    pip.stone = Borders.Stone(pip, 3)
    pips[index] = pip
    return pip
end

-- Texture, colours and border from the bar settings, onto each pip.
local function Style(pip)
    local skin, settings = ns.db.skin, ns.db.combo
    for _, bar in ipairs({ pip.fill, pip.maxFill }) do
        bar:SetStatusBarTexture(skin.texture)
        NoSnap(bar:GetStatusBarTexture())
    end
    if settings.classColor then
        pip.fill:SetStatusBarColor(ns.Skin.ClassColor())
    else
        pip.fill:SetStatusBarColor(settings.color.r, settings.color.g, settings.color.b)
    end
    pip.maxFill:SetStatusBarColor(settings.maxColor.r, settings.maxColor.g, settings.maxColor.b)
    pip.maxFill:SetMinMaxValues(count - 1, count)
    pip.maxFill:SetShown(settings.maxEnabled)
    pip.bg:SetShown(skin.background)
    Borders.Show({ edges = pip.border.edges, stone = pip.stone, forever = pip.border.forever }, skin.borderStyle,
        { size = skin.borderSize, color = skin.borderColor, thickness = skin.frameThickness })
end

-- The row's place and the pips' sizes, all in whole screen pixels. With no point width set, the
-- pips span the bars' width, the pixels left over going one each to the first pips.
function Combo:Layout()
    local display = ns.Skin.display
    if not (holder and display) then return end
    local settings = ns.db.combo
    local pixel = Pixel(holder)
    local outset = Outset(pixel)
    local step = settings.spacing + 2 * outset -- from one pip's edge to the next one's
    local full = math.floor(display:GetWidth() / pixel + 0.5)
    local each, extra, total
    if settings.width > 0 then
        each, extra = settings.width, 0
        total = count * each + (count - 1) * step
    else
        local room = full - (count - 1) * step
        each = math.max(1, math.floor(room / count))
        extra = math.max(0, room - each * count)
        total = full
    end
    local startX = math.floor((full - total) / 2) * pixel
    local gap = (settings.gap + 2 * outset) * pixel
    holder:ClearAllPoints()
    if settings.position == "above" then
        holder:SetPoint("BOTTOMLEFT", display, "TOPLEFT", startX, gap)
    else
        holder:SetPoint("TOPLEFT", LowestBar(display), "BOTTOMLEFT", startX, -gap)
    end
    holder:SetSize(math.max(1, total) * pixel, settings.height * pixel)
    local x = 0
    for i = 1, count do
        local pip = pips[i]
        local width = each + (i <= extra and 1 or 0)
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", holder, "TOPLEFT", x * pixel, 0)
        pip:SetSize(width * pixel, settings.height * pixel)
        Style(pip)
        x = x + width + step
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
    local display = ns.Skin.display
    if display then HideBlizzardRow(display) end
    local wanted = display and Wanted()
    if not wanted then
        if holder then holder:Hide() end
        return
    end
    if not holder then
        holder = CreateFrame("Frame", nil, display)
        -- Width and scale changes (Edit Mode, our bar sizes) and the alt bar coming and going
        -- (which moves the display's bottom) all resize the display.
        display:HookScript("OnSizeChanged", function() Combo:Layout() end)
    end
    holder:SetParent(display)
    holder:SetFrameLevel(display:GetFrameLevel() + 10)
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

-- Space the row takes above the health bar, in the display's units, for the buffs to sit over;
-- kept whenever the character has combo points, so shifting in and out of cat form doesn't move them.
function Combo:SpaceAbove()
    local display = ns.Skin.display
    local settings = ns.db and ns.db.combo
    if not (display and settings and settings.enabled and settings.position == "above" and HasPoints()) then return 0 end
    local pixel = Pixel(display)
    return (settings.gap + settings.height + 2 * Outset(pixel)) * pixel
end

function Combo:Debug()
    local points, max = Points(), UnitPowerMax("player", (Enum.PowerType and Enum.PowerType.ComboPoints) or 4)
    ns.Print(string.format("combo points: %s; showing %s; points %s of %s; %d pips; Blizzard's row %s.",
        ns.db.combo.enabled and "on" or "off", holder and holder:IsVisible() and "yes" or "no",
        issecret(points) and "secret" or tostring(points), issecret(max) and "secret" or tostring(max), count,
        hidBlizzard and "hidden" or "left alone"))
end

function Combo:Init()
    -- A form, the max or the world changed: whether it shows, and how many pips.
    ComboKit.Watch(function() Combo:Update() end, function() Combo:Apply() end)
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() Combo:Apply() end, self)
        EventRegistry:RegisterCallback("EditMode.Exit", function() Combo:Apply() end, self)
    end
    self:Apply()
end
