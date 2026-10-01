local _, ns = ...
local Skin = {}
ns.Skin = Skin

local issecret = ns.issecret
local WHITE = "Interface\\Buttons\\WHITE8X8"
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

local function Enforce(bar)
    local db = ns.db.skin
    if not db.enabled then return end
    guard = true
    bar:SetStatusBarTexture(db.texture)
    if bar.prtColorFn and db.classColor then
        bar:SetStatusBarColor(bar.prtColorFn())
    end
    guard = false
end

-- Blizzard resets texture/colour on its own updates, so re-apply ours right after.
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

local function Decorate(bar)
    local db = ns.db.skin
    if not bar.prtBg then
        bar.prtBg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
        bar.prtBg.prtOwned = true
        bar.prtBg:SetAllPoints()
        bar.prtBg:SetColorTexture(0, 0, 0, 0.6)
        bar.prtBorder = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    end
    local size, c = db.borderSize, db.borderColor
    local b = bar.prtBorder
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", -size, size)
    b:SetPoint("BOTTOMRIGHT", size, -size)
    if size > 0 then
        b:SetBackdrop({ edgeFile = WHITE, edgeSize = size })
        b:SetBackdropBorderColor(c.r, c.g, c.b, c.a or 1)
    end
    bar.prtBg:SetShown(db.enabled and db.background)
    b:SetShown(db.enabled and size > 0)
end

-- Rather than guess Blizzard's texture names, hide by role: the health container is pure
-- art, and on the bars everything in the BACKGROUND/BORDER layers is frame art. The fill and
-- heal prediction live in ARTWORK and above, so they're untouched.
local function HideTextures(frame, allLayers)
    if not frame then return end
    local fill = frame.GetStatusBarTexture and frame:GetStatusBarTexture()
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") and not region.prtOwned and region ~= fill then
            local layer = region:GetDrawLayer()
            if allLayers or layer == "BACKGROUND" or layer == "BORDER" then
                region:SetAlpha(0)
            end
        end
    end
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
    local pType = UnitPowerType("player")
    SetBarTexts(Skin.powerTexts, ns.db.skin.powerText,
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
