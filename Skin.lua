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
local EDGES = { "Top", "Bottom", "Left", "Right" }

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
    -- size pixels, in the border's own units.
    local t = size * (768 / select(2, GetPhysicalScreenSize())) / b:GetEffectiveScale()
    local e = b.edges
    e.Top:ClearAllPoints()
    e.Top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -t, 0)
    e.Top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", t, 0)
    e.Top:SetHeight(t)
    e.Bottom:ClearAllPoints()
    e.Bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -t, 0)
    e.Bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", t, 0)
    e.Bottom:SetHeight(t)
    e.Left:ClearAllPoints()
    e.Left:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 0)
    e.Left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, 0)
    e.Left:SetWidth(t)
    e.Right:ClearAllPoints()
    e.Right:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 0)
    e.Right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, 0)
    e.Right:SetWidth(t)
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
        b.edges = {}
        for _, key in ipairs(EDGES) do
            local edge = b:CreateTexture(nil, "OVERLAY")
            Snap(edge)
            b.edges[key] = edge
        end
        bar.prtBorder = b
        -- The pixel size changes with the display's scale (Edit Mode, the nameplate scale).
        bar:HookScript("OnSizeChanged", PlaceBorder)
    end
    local size, c = db.borderSize, db.borderColor
    local b = bar.prtBorder
    for _, edge in pairs(b.edges) do edge:SetColorTexture(c.r, c.g, c.b, c.a or 1) end
    PlaceBorder(bar)
    bar.prtBg:SetShown(db.enabled and db.background)
    b:SetShown(db.enabled and size > 0)
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

function Skin:Apply()
    local prd, health, power, alt = self:Find()
    self.prd, self.health = prd, health
    if not prd then return end

    if not prd.prtHooked then
        prd.prtHooked = true
        prd:HookScript("OnShow", function() ns.Refresh() end)
        -- Edit Mode's size for the display is a scale, which moves the border off whole pixels.
        hooksecurefunc(prd, "SetScale", function() ns.Refresh() end)
    end

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
    ev:SetScript("OnEvent", function(_, event)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            UpdateHealthText()
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
            UpdatePowerText()
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
end
