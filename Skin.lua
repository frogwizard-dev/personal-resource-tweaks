local _, ns = ...
local Skin = {}
ns.Skin = Skin

local issecret = FrogLib.issecret
local guard = false

-- What we keep about Blizzard's bars lives here, never on the bars themselves (a key of an add-on's on a frame of
-- Blizzard's is read by its own code as the add-on's).
Skin.owned = setmetatable({}, { __mode = "k" }) -- [texture] = ours, on one of Blizzard's bars (never hidden by us)
local owned = Skin.owned
local colorFns = setmetatable({}, { __mode = "k" }) -- [bar] = its colour, or false
local hooked = setmetatable({}, { __mode = "k" })   -- [bar] = its texture and colour are watched
local decor = setmetatable({}, { __mode = "k" })    -- [bar] = { bg, border, stone, frame }, ours on it
local showHooked = setmetatable({}, { __mode = "k" })
local displayHooked = false

-- Blizzard has moved these children around between patches, so try the known names.
-- If something isn't found, /prt debug prints the frame tree so we can add the right path.
function Skin:Find()
    local display = _G.PersonalResourceDisplayFrame
    if not display then return end
    local container = display.HealthBarsContainer
    local health = (container and (container.healthBar or container.HealthBar)) or display.healthBar or display.HealthBar
    local power = display.PowerBar or display.powerBar
    local alt = display.AlternatePowerBar
    return display, health, power, alt
end

-- Your class colour (FrogLib.Color's: a class colour add-on's first); white if it can't tell.
function Skin.ClassColor()
    local _, class = UnitClass("player")
    local r, g, b = FrogLib.Color.Class(class)
    if r then return r, g, b end
    return 1, 1, 1
end

-- Blizzard keeps what matters on a bar (heal prediction, absorbs, the mana cost) under a key, and
-- its frame art unnamed, as do other add-ons' borders: so every unnamed texture but the fill goes.
local function NamedRegions(frame)
    local named = {}
    for _, value in pairs(frame) do
        if type(value) == "table" and type(value.IsObjectType) == "function" then named[value] = true end
    end
    return named
end

local function HideTextures(frame, allLayers)
    if not frame then return end
    local fill = frame.GetStatusBarTexture and frame:GetStatusBarTexture()
    local named = not allLayers and NamedRegions(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") and not owned[region] and region ~= fill
            and (allLayers or not named[region]) then
            region:SetAlpha(0)
        end
    end
end

local function Enforce(bar)
    local db = ns.db.skin
    if not db.enabled then return end
    guard = true
    bar:SetStatusBarTexture(db.texture)
    if colorFns[bar] and db.classColor then
        bar:SetStatusBarColor(colorFns[bar]())
    end
    guard = false
    -- Another add-on re-skinning the bar (ClassicUI Forever adds its rim, then sets its
    -- texture) lands here too, so its new art is hidden as soon as it's made.
    HideTextures(bar)
end

-- Blizzard and other add-ons reset texture/colour on their own updates, so re-apply ours
-- right after.
local function Hook(bar, GetColor)
    colorFns[bar] = GetColor or false
    if hooked[bar] then return end
    hooked[bar] = true
    local function Reapply(self)
        if not guard then Enforce(self) end
    end
    hooksecurefunc(bar, "SetStatusBarTexture", Reapply)
    hooksecurefunc(bar, "SetStatusBarColor", Reapply)
end

-- The borders (FrogLib's): the pixel edges, borderSize screen pixels thick, sized in whole pixels
-- and kept on the pixel grid (as Blizzard's nameplate borders are), the classic stone, or Forever.
local Borders = FrogLib.Borders

local Snap = FrogLib.PixelSnap

-- A frame over `parent` holding pixel-snapped edges round `around` (itself if not given); the bars
-- and the combo pips have them.
function Skin.EdgeFrame(parent, around)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    Snap(frame)
    frame.edges = Borders.Edges(frame, around or frame, "OVERLAY")
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do Snap(frame.edges[key]) end
    return frame
end

local function PlaceBorder(bar)
    local ours = decor[bar]
    local size = ns.db.skin.borderSize
    if not ours or size <= 0 then return end
    ours.border.edges:Place(size, 0)
end

local function PlaceFrame(bar)
    local ours = decor[bar]
    if ours then ours.frame:Place(ns.db.skin.frameThickness) end
end

local function Decorate(bar)
    local db = ns.db.skin
    local ours = decor[bar]
    if not ours then
        ours = {}
        decor[bar] = ours
        ours.bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
        owned[ours.bg] = true
        ours.bg:SetAllPoints()
        ours.bg:SetColorTexture(0, 0, 0, 0.6)
        ours.border = Skin.EdgeFrame(bar, bar)
        -- Classic: the stone border, on a frame round the bar.
        ours.stone = Borders.Stone(bar, 1)
        -- Forever: our Forever-style frame, on the bar itself, over the fill's edge.
        ours.frame = Borders.Forever(bar, "OVERLAY", 5)
        -- The skin hides every other unnamed texture on the bar.
        for _, texture in pairs(ours.frame:Textures()) do owned[texture] = true end
        -- The pixel size changes with the display's scale (Edit Mode, the nameplate scale), and
        -- the frame follows the bar's height.
        bar:HookScript("OnSizeChanged", PlaceBorder)
        bar:HookScript("OnSizeChanged", PlaceFrame)
    end
    local size, color = db.borderSize, db.borderColor
    ours.border.edges:SetColor(color)
    PlaceBorder(bar)
    PlaceFrame(bar)
    local style = db.borderStyle
    ours.bg:SetShown(db.enabled and db.background)
    ours.border:SetShown(db.enabled and size > 0 and style == "pixel")
    ours.stone:SetShown(db.enabled and style == "classic")
    ours.frame:SetShown(db.enabled and style == "forever")
end

local function HideBlizzardArt(display, health, power, alt)
    HideTextures(display.HealthBarsContainer, true)
    HideTextures(health)
    HideTextures(power)
    HideTextures(alt)
end

-- The bar texts: templates (FrogLib.Text's words value, max, percent). The values (FrogLib.Unit's)
-- may be secret: they only ever go into SetFormattedText, which formats them engine-side.
local values = {}
local function SetBarText(text, template, value, max, percent)
    if not text then return end
    if not ns.db.skin.enabled then
        text:Hide()
        return
    end
    values.value, values.max, values.percent = value, max, percent
    FrogLib.Text.Set(text, template, values)
    values.value, values.max, values.percent = nil, nil, nil
end

local SLOTS = { "left", "center", "right" }

-- Each bar has three text slots, each with its own template.
local function SetBarTexts(texts, templates, value, max, percent)
    if not texts then return end
    for _, slot in ipairs(SLOTS) do
        SetBarText(texts[slot], templates[slot], value, max, percent)
    end
end

local function UpdateHealthText()
    SetBarTexts(Skin.healthTexts, ns.db.skin.healthText,
        UnitHealth("player"), UnitHealthMax("player"), FrogLib.Unit.HealthPercent("player"))
end

local function UpdatePowerText()
    local powerType, token = UnitPowerType("player")
    local db = ns.db.skin
    SetBarTexts(Skin.powerTexts, db.powerTextFor[token] or db.powerText,
        UnitPower("player", powerType), UnitPowerMax("player", powerType), FrogLib.Unit.PowerPercent("player", powerType))
end

-- The third bar: Blizzard's mana bar for druids in a form (and Shadow priests), which shows
-- your mana while your main bar shows rage or energy.
local MANA = (Enum.PowerType and Enum.PowerType.Mana) or 0

local function UpdateAltText()
    if not Skin.altTexts then return end
    SetBarTexts(Skin.altTexts, ns.db.skin.altText,
        UnitPower("player", MANA), UnitPowerMax("player", MANA), FrogLib.Unit.PowerPercent("player", MANA))
end

-- Whether it should show: "form" (only while your main bar isn't mana) or "never". Since a Forever
-- update Blizzard shows it only in a form too; showing it in caster form would mean forcing it
-- against Blizzard's own updates. A hidden power type leaves it to Blizzard.
local function AltWanted()
    if ns.db.skin.altShow == "never" then return false end
    local powerType = UnitPowerType("player")
    return issecret(powerType) or powerType ~= MANA
end

-- Blizzard shows the bar whenever it re-checks it; hidden again right after when it's not wanted (as EllesmereUI
-- hides a button the game keeps showing). Shown only where Blizzard would show it (the class and spec it's for).
-- Never while the display is protected in combat: that waits for the fight's end (ApplySize's event).
local function CanChange(frame)
    return not (InCombatLockdown() and frame:IsProtected())
end

function Skin:UpdateAltShown()
    local alt = self.alt
    if not alt or not CanChange(alt) then return end
    if not showHooked[alt] then
        showHooked[alt] = true
        hooksecurefunc(alt, "Show", function(bar)
            if not AltWanted() and CanChange(bar) then bar:Hide() end
        end)
    end
    local wanted = AltWanted() and alt.alternatePowerRequirementsMet and not (self.display and self.display.hideAltPower)
    if wanted and not alt:IsShown() then
        alt:Show()
    elseif not wanted and alt:IsShown() then
        alt:Hide()
    end
end

local function BarTexts(bar)
    local texts = {}
    for _, slot in ipairs(SLOTS) do
        local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if slot == "left" then
            text:SetJustifyH("LEFT")
        elseif slot == "right" then
            text:SetJustifyH("RIGHT")
        end
        texts[slot] = text
    end
    return texts
end

local function PositionTexts(texts, bar, padding, nudge)
    texts.left:ClearAllPoints()
    texts.left:SetPoint("LEFT", bar, "LEFT", padding, nudge)
    texts.center:ClearAllPoints()
    texts.center:SetPoint("CENTER", bar, "CENTER", 0, nudge)
    texts.right:ClearAllPoints()
    texts.right:SetPoint("RIGHT", bar, "RIGHT", -padding, nudge)
end

local function SetFonts(texts, size)
    local settings = ns.db.text
    for _, text in pairs(texts) do
        ns.Media:SetFont(text, settings.font, size, settings.outline)
    end
end

-- Our own bar sizes (skin.size), set over Edit Mode's each time it sets its own. In screen pixels,
-- so they stay crisp whatever Edit Mode's "Size" scale is.
local sizing, sized = false, {}

local PixelUnit = FrogLib.Pixel

-- A bar's current size in screen pixels (for the settings to start from).
function Skin:MeasureSize(key)
    local display = self.display
    if not display then return 0 end
    local frame = key == "width" and display or key == "health" and display.HealthBarsContainer
        or key == "power" and display.PowerBar or display.AlternatePowerBar
    if not frame then return 0 end
    local units = key == "width" and frame:GetWidth() or frame:GetHeight()
    return math.floor(units / PixelUnit(frame) + 0.5)
end

function Skin:ApplySize()
    local display = self.display
    if not display or sizing then return end
    if InCombatLockdown() and display:IsProtected() then return end -- PLAYER_REGEN_ENABLED tries again
    local sizes, unit = ns.db.skin.size, PixelUnit(display)
    sizing = true
    local container, power, alt = display.HealthBarsContainer, display.PowerBar, display.AlternatePowerBar
    if sizes.width > 0 then
        local width = sizes.width * unit
        display:SetWidth(width)
        for _, frame in ipairs({ container, power, alt, display.ClassFrameContainer }) do
            if frame then frame:SetWidth(width) end
        end
    elseif sized.width and display.UpdateBarWidth then
        display:UpdateBarWidth() -- back to Edit Mode's
    end
    if sizes.health > 0 and container then
        container:SetHeight(sizes.health * unit)
    elseif sized.health and display.UpdateSystemSettingHealthBarHeight then
        pcall(display.UpdateSystemSettingHealthBarHeight, display)
    end
    local altHeight = sizes.alt > 0 and sizes.alt or sizes.power
    if sizes.power > 0 and power then power:SetHeight(sizes.power * unit) end
    if altHeight > 0 and alt then alt:SetHeight(altHeight * unit) end
    if (sized.power and sizes.power == 0) or (sized.alt and altHeight == 0) then
        if display.UpdateSystemSettingPowerBarHeight then pcall(display.UpdateSystemSettingPowerBarHeight, display) end
        if sizes.power > 0 and power then power:SetHeight(sizes.power * unit) end
        if altHeight > 0 and alt then alt:SetHeight(altHeight * unit) end
    end
    sized.width, sized.health, sized.power, sized.alt = sizes.width > 0, sizes.health > 0, sizes.power > 0, altHeight > 0
    if display.UpdateFrameHeight then display:UpdateFrameHeight() end
    sizing = false
end

function Skin:Apply()
    local display, health, power, alt = self:Find()
    self.display, self.health, self.alt = display, health, alt
    if not display then return end

    if not displayHooked then
        displayHooked = true
        display:HookScript("OnShow", function() ns.Refresh() end)
        -- Edit Mode's size for the display is a scale, which moves the border off whole pixels.
        hooksecurefunc(display, "SetScale", function() ns.Refresh() end)
        -- Edit Mode setting its own sizes: put ours back over them.
        for _, method in ipairs({ "UpdateBarWidth", "SetHealthBarHeight", "SetPowerBarHeight" }) do
            if display[method] then hooksecurefunc(display, method, function() Skin:ApplySize() end) end
        end
    end
    self:ApplySize()

    local text = ns.db.text
    if health then
        Hook(health, Skin.ClassColor)
        Decorate(health)
        Enforce(health)
        self.healthTexts = self.healthTexts or BarTexts(health)
        SetFonts(self.healthTexts, text.healthSize)
        PositionTexts(self.healthTexts, health, text.healthPadding, text.healthNudge)
        UpdateHealthText()
    end
    if power then
        self.powerTexts = self.powerTexts or BarTexts(power)
        SetFonts(self.powerTexts, text.powerSize)
        PositionTexts(self.powerTexts, power, text.powerPadding, text.powerNudge)
        UpdatePowerText()
    end
    if alt then
        self.altTexts = self.altTexts or BarTexts(alt)
        SetFonts(self.altTexts, text.powerSize)
        PositionTexts(self.altTexts, alt, text.powerPadding, text.powerNudge)
        UpdateAltText()
        self:UpdateAltShown()
    end
    for _, bar in pairs({ power, alt }) do
        Hook(bar, nil)
        Decorate(bar)
        Enforce(bar)
    end
    if ns.db.skin.enabled then
        HideBlizzardArt(display, health, power, alt)
    end
end

function Skin:Init()
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("UI_SCALE_CHANGED")
    events:RegisterEvent("DISPLAY_SIZE_CHANGED")
    events:RegisterUnitEvent("UNIT_HEALTH", "player")
    events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            UpdateHealthText()
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER"
            or event == "UPDATE_SHAPESHIFT_FORM" then
            UpdatePowerText()
            UpdateAltText()
            if event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then self:UpdateAltShown() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:ApplySize()
            self:UpdateAltShown()
        else
            ns.Refresh()
        end
    end)
    self:Apply()
end

function Skin:Debug()
    local display, health, power, alt = self:Find()
    if not display then
        ns.Print("PersonalResourceDisplayFrame NOT FOUND. Enable the Personal Resource Display in Edit Mode, then /reload.")
        return
    end
    local function Name(frame) return frame and frame:GetDebugName() or "|cffff5555not found|r" end
    ns.Print("health:", Name(health))
    ns.Print("power:", Name(power))
    ns.Print("alt power:", Name(alt))
    ns.Print("Frame tree (textures show their layer and alpha):")
    local function Walk(frame, depth)
        if depth > 4 then return end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:IsObjectType("Texture") then
                local alpha = region:GetAlpha() -- secret if the game hides it (the display's gated fade)
                print(string.format("%s- texture %s [%s] alpha %s", string.rep("  ", depth),
                    region:GetDebugName(), region:GetDrawLayer(), issecret(alpha) and "hidden" or string.format("%.1f", alpha)))
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            print(string.rep("  ", depth) .. child:GetDebugName() .. " [" .. child:GetObjectType() .. "]")
            Walk(child, depth + 1)
        end
    end
    Walk(display, 1)
    ns.Auras:Debug()
    ns.Combo:Debug()
end
