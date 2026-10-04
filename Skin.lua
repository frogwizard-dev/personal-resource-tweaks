local _, ns = ...
local Skin = {}
ns.Skin = Skin

local issecret = ns.issecret
local guard = false

-- Blizzard has moved these children around between patches, so try the known names.
-- If something isn't found, /prt debug prints the frame tree so we can add the right path.
function Skin:Find()
    local prd = _G.PersonalResourceDisplayFrame
    if not prd then return end
    local container = prd.HealthBarsContainer
    local health = (container and (container.healthBar or container.HealthBar)) or prd.healthBar or prd.HealthBar
    local power = prd.PowerBar or prd.powerBar
    local alt = prd.AlternatePowerBar
    return prd, health, power, alt
end

local function ClassColor()
    local _, class = UnitClass("player")
    local c = (C_ClassColor and C_ClassColor.GetClassColor(class)) or RAID_CLASS_COLORS[class]
    return c.r, c.g, c.b
end

-- Rather than guess texture names, hide by role. The health container is pure art. On the
-- bars, everything Blizzard draws that matters (heal prediction, absorbs, the mana cost) is
-- kept on the bar under a key, while the frame art is unnamed: Blizzard's dark backing, and
-- borders other add-ons add (ClassicUI Forever's gold plate rim). So: hide every unnamed
-- texture that isn't the fill or ours.
local function NamedRegions(frame)
    local named = {}
    for _, v in pairs(frame) do
        if type(v) == "table" and type(v.IsObjectType) == "function" then named[v] = true end
    end
    return named
end

local function HideTextures(frame, allLayers)
    if not frame then return end
    local fill = frame.GetStatusBarTexture and frame:GetStatusBarTexture()
    local named = not allLayers and NamedRegions(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") and not region.prtOwned and region ~= fill
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
    if bar.prtColorFn and db.classColor then
        bar:SetStatusBarColor(bar.prtColorFn())
    end
    guard = false
    -- Another add-on re-skinning the bar (ClassicUI Forever adds its rim, then sets its
    -- texture) lands here too, so its new art is hidden as soon as it's made.
    HideTextures(bar)
end

-- Blizzard and other add-ons reset texture/colour on their own updates, so re-apply ours
-- right after.
local function Hook(bar, colorFn)
    bar.prtColorFn = colorFn
    if bar.prtHooked then return end
    bar.prtHooked = true
    local function reapply(self)
        if not guard then Enforce(self) end
    end
    hooksecurefunc(bar, "SetStatusBarTexture", reapply)
    hooksecurefunc(bar, "SetStatusBarColor", reapply)
end

-- The border: four edges round the outside of the bar, borderSize screen pixels thick. Sizes in
-- interface units come out as fractions of a pixel at most UI and nameplate scales (and a
-- fraction gets rounded differently on each side), so each edge is sized in whole pixels and the
-- engine keeps its layout on the pixel grid, as Blizzard's own nameplate borders do.
local Borders = FrogLib.Borders

local function Snap(region)
    if region.SetRoundLayoutToNearestPixel then region:SetRoundLayoutToNearestPixel(true) end
    if region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        region:SetTexelSnappingBias(0)
    end
end

local function PlaceBorder(bar)
    local b = bar.prtBorder
    local size = ns.db.skin.borderSize
    if not b or size <= 0 then return end
    b.edges:Place(size, 0)
end

-- The other two border styles (skin.borderStyle; "pixel" is the edges above), both FrogLib's:
--   "classic": the grey stone border tooltips and old frames use, just outside the bar;
--   "forever": our Forever-style frame, on the bar over the fill's edge (thickness 1 to 3).
local function PlaceFrame(bar)
    if bar.prtFrame then bar.prtFrame:Place(ns.db.skin.frameThickness) end
end

local function Decorate(bar)
    local db = ns.db.skin
    if not bar.prtBg then
        bar.prtBg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
        bar.prtBg.prtOwned = true
        bar.prtBg:SetAllPoints()
        bar.prtBg:SetColorTexture(0, 0, 0, 0.6)
        local b = CreateFrame("Frame", nil, bar)
        b:SetAllPoints()
        Snap(b)
        b.edges = Borders.Edges(b, bar, "OVERLAY")
        for _, key in ipairs({ "top", "bottom", "left", "right" }) do Snap(b.edges[key]) end
        bar.prtBorder = b
        -- Classic: the stone border, on a frame round the bar.
        bar.prtStone = Borders.Stone(bar, 1)
        -- Forever: our Forever-style frame, on the bar itself, over the fill's edge.
        bar.prtFrame = Borders.Forever(bar, "OVERLAY", 5)
        -- The skin hides every other unnamed texture on the bar.
        for _, t in pairs(bar.prtFrame:Textures()) do t.prtOwned = true end
        -- The pixel size changes with the display's scale (Edit Mode, the nameplate scale), and
        -- the frame follows the bar's height.
        bar:HookScript("OnSizeChanged", PlaceBorder)
        bar:HookScript("OnSizeChanged", PlaceFrame)
    end
    local size, c = db.borderSize, db.borderColor
    local b = bar.prtBorder
    b.edges:SetColor(c)
    PlaceBorder(bar)
    PlaceFrame(bar)
    local style = db.borderStyle
    bar.prtBg:SetShown(db.enabled and db.background)
    b:SetShown(db.enabled and size > 0 and style == "pixel")
    bar.prtStone:SetShown(db.enabled and style == "classic")
    bar.prtFrame:SetShown(db.enabled and style == "forever")
end

local function HideBlizzardArt(prd, health, power, alt)
    HideTextures(prd.HealthBarsContainer, true)
    HideTextures(health)
    HideTextures(power)
    HideTextures(alt)
end

-- UnitHealthPercent/UnitPowerPercent return a value that may be secret, so it only ever
-- goes straight into SetFormattedText, which formats it engine-side.
local function HealthPercent()
    if UnitHealthPercent and CurveConstants then
        return UnitHealthPercent("player", true, CurveConstants.ScaleTo100)
    end
    local h, m = UnitHealth("player"), UnitHealthMax("player")
    if issecret(h) or issecret(m) or m == 0 then return 0 end
    return h / m * 100
end

local function PowerPercent(pType)
    if UnitPowerPercent and CurveConstants then
        return UnitPowerPercent("player", pType, true, CurveConstants.ScaleTo100)
    end
    local p, m = UnitPower("player", pType), UnitPowerMax("player", pType)
    if issecret(p) or issecret(m) or m == 0 then return 0 end
    return p / m * 100
end

-- Turns a template like "value | percent.1" into a format string ("%d || %.1f%%") plus the
-- order of its arguments. Words: value, max, percent (percent.1 / percent.2 for decimals).
-- "|" is doubled because a single one starts a WoW text escape.
local compiled = {}
local function Compile(template)
    local c = compiled[template]
    if c then return c end
    local args = {}
    local pattern = template:gsub("%%", "%%%%")
    pattern = pattern:gsub("||", "|") -- edit boxes store a typed "|" already doubled
    pattern = pattern:gsub("|", "||")
    pattern = pattern:gsub("(%a+)(%.?%d*)", function(word, suffix)
        local w = word:lower()
        if w == "value" or w == "max" then
            args[#args + 1] = w
            return "%d" .. suffix
        elseif w == "percent" then
            args[#args + 1] = "percent"
            local places = tonumber(suffix:match("^%.(%d)"))
            if places then return "%." .. math.min(places, 3) .. "f%%" end
            return "%d%%" .. suffix
        end
    end)
    c = { pattern = pattern, args = args }
    compiled[template] = c
    return c
end

local function SetBarText(fs, template, value, max, pct)
    if not fs then return end
    if not ns.db.skin.enabled or strtrim(template) == "" then
        fs:Hide()
        return
    end
    fs:Show()
    local c = Compile(template)
    local vals = { value = value, max = max, percent = pct }
    local a = c.args
    pcall(fs.SetFormattedText, fs, c.pattern, vals[a[1]], vals[a[2]], vals[a[3]], vals[a[4]], vals[a[5]], vals[a[6]])
end

local SLOTS = { "left", "center", "right" }

-- Each bar has three text slots, each with its own template.
local function SetBarTexts(texts, templates, value, max, pct)
    if not texts then return end
    for _, slot in ipairs(SLOTS) do
        SetBarText(texts[slot], templates[slot], value, max, pct)
    end
end

local function UpdateHealthText()
    SetBarTexts(Skin.healthTexts, ns.db.skin.healthText,
        UnitHealth("player"), UnitHealthMax("player"), HealthPercent())
end

local function UpdatePowerText()
    local pType, token = UnitPowerType("player")
    local db = ns.db.skin
    SetBarTexts(Skin.powerTexts, db.powerTextFor[token] or db.powerText,
        UnitPower("player", pType), UnitPowerMax("player", pType), PowerPercent(pType))
end

-- The third bar: Blizzard's mana bar for druids in a form (and Shadow priests), which shows
-- your mana while your main bar shows rage or energy.
local MANA = (Enum.PowerType and Enum.PowerType.Mana) or 0

local function UpdateAltText()
    if not Skin.altTexts then return end
    SetBarTexts(Skin.altTexts, ns.db.skin.altText,
        UnitPower("player", MANA), UnitPowerMax("player", MANA), PowerPercent(MANA))
end

-- Whether it should show: "always" (as Blizzard has it), "form" (only while your main bar isn't
-- mana; in caster form it just repeats it) or "never".
local function AltWanted()
    local mode = ns.db.skin.altShow
    if mode == "never" then return false end
    if mode == "form" then return UnitPowerType("player") ~= MANA end
    return true
end

-- Blizzard shows the bar whenever it re-checks it; hidden again right after when it's not wanted.
-- Shown only where Blizzard would show it (the class and spec it's for).
function Skin:UpdateAltShown()
    local alt = self.alt
    if not alt then return end
    if not alt.prtShowHooked then
        alt.prtShowHooked = true
        hooksecurefunc(alt, "Show", function(bar)
            if not AltWanted() then bar:Hide() end
        end)
    end
    local wanted = AltWanted() and alt.alternatePowerRequirementsMet and not (self.prd and self.prd.hideAltPower)
    if wanted and not alt:IsShown() then
        alt:Show()
    elseif not wanted and alt:IsShown() then
        alt:Hide()
    end
end

local function BarTexts(bar)
    local texts = {}
    for _, slot in ipairs(SLOTS) do
        local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if slot == "left" then
            fs:SetJustifyH("LEFT")
        elseif slot == "right" then
            fs:SetJustifyH("RIGHT")
        end
        texts[slot] = fs
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
    local t = ns.db.text
    for _, fs in pairs(texts) do
        ns.Media:SetFont(fs, t.font, size, t.outline)
    end
end

-- Our own bar sizes (skin.size), set over Edit Mode's each time it sets its own. In screen pixels,
-- so they stay crisp whatever Edit Mode's "Size" scale is.
local sizing, sized = false, {}

local function PixelUnit(frame)
    return (768 / select(2, GetPhysicalScreenSize())) / frame:GetEffectiveScale()
end

-- A bar's current size in screen pixels (for the settings to start from).
function Skin:MeasureSize(key)
    local prd = self.prd
    if not prd then return 0 end
    local frame = key == "width" and prd or key == "health" and prd.HealthBarsContainer
        or key == "power" and prd.PowerBar or prd.AlternatePowerBar
    if not frame then return 0 end
    local units = key == "width" and frame:GetWidth() or frame:GetHeight()
    return math.floor(units / PixelUnit(frame) + 0.5)
end

function Skin:ApplySize()
    local prd = self.prd
    if not prd or sizing then return end
    if InCombatLockdown() and prd:IsProtected() then return end -- PLAYER_REGEN_ENABLED tries again
    local s, unit = ns.db.skin.size, PixelUnit(prd)
    sizing = true
    local container, power, alt = prd.HealthBarsContainer, prd.PowerBar, prd.AlternatePowerBar
    if s.width > 0 then
        local w = s.width * unit
        prd:SetWidth(w)
        for _, f in ipairs({ container, power, alt, prd.ClassFrameContainer }) do
            if f then f:SetWidth(w) end
        end
    elseif sized.width and prd.UpdateBarWidth then
        prd:UpdateBarWidth() -- back to Edit Mode's
    end
    if s.health > 0 and container then
        container:SetHeight(s.health * unit)
    elseif sized.health and prd.UpdateSystemSettingHealthBarHeight then
        pcall(prd.UpdateSystemSettingHealthBarHeight, prd)
    end
    local altHeight = s.alt > 0 and s.alt or s.power
    if s.power > 0 and power then power:SetHeight(s.power * unit) end
    if altHeight > 0 and alt then alt:SetHeight(altHeight * unit) end
    if (sized.power and s.power == 0) or (sized.alt and altHeight == 0) then
        if prd.UpdateSystemSettingPowerBarHeight then pcall(prd.UpdateSystemSettingPowerBarHeight, prd) end
        if s.power > 0 and power then power:SetHeight(s.power * unit) end
        if altHeight > 0 and alt then alt:SetHeight(altHeight * unit) end
    end
    sized.width, sized.health, sized.power, sized.alt = s.width > 0, s.health > 0, s.power > 0, altHeight > 0
    if prd.UpdateFrameHeight then prd:UpdateFrameHeight() end
    sizing = false
end

function Skin:Apply()
    local prd, health, power, alt = self:Find()
    self.prd, self.health, self.alt = prd, health, alt
    if not prd then return end

    if not prd.prtHooked then
        prd.prtHooked = true
        prd:HookScript("OnShow", function() ns.Refresh() end)
        -- Edit Mode's size for the display is a scale, which moves the border off whole pixels.
        hooksecurefunc(prd, "SetScale", function() ns.Refresh() end)
        -- Edit Mode setting its own sizes: put ours back over them.
        for _, method in ipairs({ "UpdateBarWidth", "SetHealthBarHeight", "SetPowerBarHeight" }) do
            if prd[method] then hooksecurefunc(prd, method, function() Skin:ApplySize() end) end
        end
    end
    self:ApplySize()

    local t = ns.db.text
    if health then
        Hook(health, ClassColor)
        Decorate(health)
        Enforce(health)
        self.healthTexts = self.healthTexts or BarTexts(health)
        SetFonts(self.healthTexts, t.healthSize)
        PositionTexts(self.healthTexts, health, t.healthPadding, t.healthNudge)
        UpdateHealthText()
    end
    if power then
        self.powerTexts = self.powerTexts or BarTexts(power)
        SetFonts(self.powerTexts, t.powerSize)
        PositionTexts(self.powerTexts, power, t.powerPadding, t.powerNudge)
        UpdatePowerText()
    end
    if alt then
        self.altTexts = self.altTexts or BarTexts(alt)
        SetFonts(self.altTexts, t.powerSize)
        PositionTexts(self.altTexts, alt, t.powerPadding, t.powerNudge)
        UpdateAltText()
        self:UpdateAltShown()
    end
    for _, bar in pairs({ power, alt }) do
        Hook(bar, nil)
        Decorate(bar)
        Enforce(bar)
    end
    if ns.db.skin.enabled then
        HideBlizzardArt(prd, health, power, alt)
    end
end

function Skin:Init()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ADDON_LOADED")
    ev:RegisterEvent("UI_SCALE_CHANGED")
    ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
    ev:RegisterUnitEvent("UNIT_HEALTH", "player")
    ev:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            UpdateHealthText()
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER"
            or event == "UPDATE_SHAPESHIFT_FORM" then
            UpdatePowerText()
            UpdateAltText()
            if event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then self:UpdateAltShown() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:ApplySize()
        else
            ns.Refresh()
        end
    end)
    self:Apply()
end

function Skin:Debug()
    local prd, health, power, alt = self:Find()
    if not prd then
        ns.Print("PersonalResourceDisplayFrame NOT FOUND. Enable the Personal Resource Display in Edit Mode, then /reload.")
        return
    end
    local function name(f) return f and f:GetDebugName() or "|cffff5555not found|r" end
    ns.Print("health:", name(health))
    ns.Print("power:", name(power))
    ns.Print("alt power:", name(alt))
    ns.Print("Frame tree (textures show their layer and alpha):")
    local function walk(frame, depth)
        if depth > 4 then return end
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsObjectType("Texture") then
                print(string.format("%s- texture %s [%s] alpha %.1f", string.rep("  ", depth),
                    r:GetDebugName(), r:GetDrawLayer(), r:GetAlpha()))
            end
        end
        for _, c in ipairs({ frame:GetChildren() }) do
            print(string.rep("  ", depth) .. c:GetDebugName() .. " [" .. c:GetObjectType() .. "]")
            walk(c, depth + 1)
        end
    end
    walk(prd, 1)
    ns.Auras:Debug()
    ns.Combo:Debug()
end
