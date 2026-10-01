local _, ns = ...
local Auras = {}
ns.Auras = Auras

-- Built on 12.1's AuraContainer: we hand the engine a filter ("HELPFUL, only these IDs" or
-- "HARMFUL, except these IDs") and it picks and renders the auras itself. That keeps working
-- in restricted content, where addons can't read aura data at all.

local issecret = ns.issecret
local KINDS = { "buffs", "debuffs" }
local containers, signatures = {}, {}
local styled = { buffs = {}, debuffs = {} } -- per-button region tables, for restyling

local SORT = AuraContainerSortMethod and AuraContainerSortMethod.Default
local SORT_DIR = AuraContainerSortDirection and AuraContainerSortDirection.Normal

-- Countdown text is formatted engine-side (the remaining time can be secret): "45", "2m", "1h".
local formatter
local function DurationFormatter()
    if formatter ~= nil then return formatter or nil end
    formatter = false
    local R = Enum.NumericRuleFormatRounding
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and R then
        local f = C_StringUtil.CreateNumericRuleFormatter()
        if pcall(f.SetBreakpoints, f, {
            { threshold = 0, format = "%d", step = 1, rounding = R.Up },
            { threshold = 60, format = "%dm", step = 1, rounding = R.Up, components = { { div = 60 } } },
            { threshold = 61, format = "%dm", step = 1, rounding = R.Down, components = { { div = 60 } } },
            { threshold = 3600, format = "%dh", step = 1, rounding = R.Down, components = { { div = 3600 } } },
        }) then
            formatter = f
        end
    end
    return formatter or nil
end

local function StyleButton(d)
    local cfg, t = ns.db[d.kind], ns.db.text
    -- The engine creates buttons at zero size; sizing them is our job. Denied while auras
    -- are secret, so it's retried on the next restyle.
    if d.size ~= cfg.size and pcall(d.button.SetSize, d.button, cfg.size, cfg.size) then
        d.size = cfg.size
    end
    ns.Media:SetFont(d.stack, t.font, t.stackSize, t.outline)
    ns.Media:SetFont(d.duration, t.font, t.timerSize, t.outline)
    d.duration:SetShown(cfg.showTimer)
end

-- Runs once per engine-created button. Fonts must be set before the regions are handed to
-- the button, because registering them makes the engine write text straight away.
local function MakeInit(kind)
    return function(button)
        local d = { kind = kind, button = button }

        d.border = button:CreateTexture(nil, "BACKGROUND")
        d.border:SetAllPoints()
        if kind == "debuffs" then
            d.border:SetColorTexture(0.8, 0.1, 0.1, 1)
        else
            d.border:SetColorTexture(0, 0, 0, 1)
        end

        d.icon = button:CreateTexture(nil, "ARTWORK")
        d.icon:SetPoint("TOPLEFT", 1, -1)
        d.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        d.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        d.cooldown:SetAllPoints(d.icon)
        d.cooldown:SetDrawEdge(false)
        d.cooldown:SetReverse(true)
        d.cooldown:SetHideCountdownNumbers(true)

        local carrier = CreateFrame("Frame", nil, button)
        carrier:SetAllPoints()
        carrier:SetFrameLevel(d.cooldown:GetFrameLevel() + 1)
        carrier:EnableMouse(false)
        d.stack = carrier:CreateFontString(nil, "OVERLAY")
        d.stack:SetPoint("BOTTOMRIGHT", -1, 1)
        d.duration = carrier:CreateFontString(nil, "OVERLAY")
        d.duration:SetPoint("CENTER")
        StyleButton(d)

        -- Clicks off so the icons never eat clicks meant for the world; hover tooltips stay.
        pcall(button.SetMouseClickEnabled, button, false)

        button:SetIcon(d.icon)
        button:SetDurationCooldown(d.cooldown)
        button:SetApplicationCount(d.stack, {})
        if not pcall(button.SetDurationText, button, d.duration, { textFormatter = DurationFormatter() }) then
            pcall(button.SetDurationText, button, d.duration, {})
        end

        table.insert(styled[kind], d)
    end
end

-- Blizzard renamed the container layout setters mid-12.1 (SetAuraLayout* -> SetFlowLayout*).
local function CallEither(c, newName, oldName, ...)
    local f = c[newName] or c[oldName]
    if f then pcall(f, c, ...) end
end

local function Layout(cfg)
    return { elementWidth = cfg.size, elementHeight = cfg.size, elementSpacing = cfg.spacing, lineSpacing = cfg.spacing }
end

-- Anything that changes which groups exist; groups can't be removed from a container, so a
-- change here means building a fresh one.
local function Signature(cfg)
    local ids = cfg.mode == "whitelist" and cfg.list or cfg.blacklist
    return cfg.mode .. "|" .. cfg.max .. "|" .. table.concat(ids, ",")
end

local function Build(kind)
    local cfg = ns.db[kind]
    local old = containers[kind]
    if old then
        pcall(old.SetUnit, old, "none")
        old:Hide()
        containers[kind] = nil
    end

    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, ns.Skin.prd or UIParent, "CustomAuraContainerTemplate")
    if not ok then
        if not Auras.warned then
            Auras.warned = true
            ns.Print("This client has no aura containers, so buffs/debuffs can't be shown.")
        end
        return
    end

    -- Position it before anything else: the engine only processes containers with a
    -- renderable rect, and one set up unanchored silently never shows an aura.
    c:SetSize(1, 1)
    containers[kind] = c
    Auras:Anchor()
    CallEither(c, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", "BOTTOMLEFT")
    CallEither(c, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection",
        AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)

    styled[kind] = {}
    local init, layout = MakeInit(kind), Layout(cfg)
    local filter = kind == "buffs" and "HELPFUL" or "HARMFUL"
    local keys = {}
    local function addGroup(key, opts)
        opts.sortMethod, opts.sortDirection = SORT, SORT_DIR
        opts.initializeFrame, opts.layout = init, layout
        local ok, err = pcall(c.AddAuraGroup, c, key, filter, opts)
        if ok then
            keys[#keys + 1] = key
        else
            ns.Print("Couldn't set up " .. kind .. ":", err)
        end
    end
    if cfg.mode == "whitelist" then
        -- One single-slot group per spell keeps your chosen order.
        for i, id in ipairs(cfg.list) do
            addGroup("w" .. i, { maxFrameCount = 1, candidateFilters = { includeSpellIDs = { [id] = true } } })
        end
    else
        local exclude = {}
        for _, id in ipairs(cfg.blacklist) do exclude[id] = true end
        addGroup("all", { maxFrameCount = cfg.max, candidateFilters = next(exclude) and { excludeSpellIDs = exclude } or nil })
    end
    c.prtKeys = keys

    -- Unit last: the engine only registers for aura events once the container has groups.
    c:SetUnit("player")
    c:UpdateAllAuras()
    signatures[kind] = Signature(cfg)
end

-- Height kept free for the buff row. Nothing may anchor to an aura container (the engine
-- forbids it), so debuffs can't sit on the buff row directly; they anchor to the health bar
-- and skip this much space instead. Whitelists reserve one line per perRow spells; a
-- blacklist has no known count, so it reserves a single line.
local function BuffRowHeight()
    local b = ns.db.buffs
    local count = b.mode == "whitelist" and #b.list or 1
    if not b.enabled or count == 0 then return 0 end
    local lines = math.ceil(count / b.perRow)
    return b.offsetY + lines * (b.size + b.spacing) - b.spacing
end

-- Buffs sit directly on top of the health bar, debuffs above the buffs.
function Auras:Anchor()
    local parent = ns.Skin.prd or UIParent
    local anchor, point = ns.Skin.health, "TOP"
    if not anchor then
        anchor, point = UIParent, "CENTER"
    end
    local offsets = {
        buffs = ns.db.buffs.offsetY,
        debuffs = BuffRowHeight() + ns.db.debuffs.offsetY,
    }
    for kind, c in pairs(containers) do
        c:SetParent(parent)
        c:ClearAllPoints()
        c:SetPoint("BOTTOM", anchor, point, 0, offsets[kind])
    end
end

function Auras:Apply()
    if not self.ready then return end
    for _, kind in ipairs(KINDS) do
        local cfg = ns.db[kind]
        if not containers[kind] or signatures[kind] ~= Signature(cfg) then
            Build(kind)
        end
        local c = containers[kind]
        if c then
            local layout = Layout(cfg)
            for _, key in ipairs(c.prtKeys) do
                pcall(c.SetAuraGroupLayout, c, key, layout)
            end
            CallEither(c, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth",
                cfg.perRow * (cfg.size + cfg.spacing) - cfg.spacing + 0.4)
            c:SetShown(cfg.enabled)
            for _, d in ipairs(styled[kind]) do
                pcall(StyleButton, d)
            end
        end
    end
    self:Anchor()
end

function Auras:Debug()
    for _, kind in ipairs(KINDS) do
        local cfg, c = ns.db[kind], containers[kind]
        local ids = cfg.mode == "whitelist" and cfg.list or cfg.blacklist
        if not c then
            ns.Print(kind .. ": |cffff5555no container|r")
        else
            local point, rel, relPoint, x, y = c:GetPoint(1)
            ns.Print(string.format("%s: %s (%d IDs), groups %d, buttons %d, shown %s, visible %s, size %.0fx%.0f, anchored %s",
                kind, cfg.mode, #ids, #c.prtKeys, #styled[kind], tostring(c:IsShown()), tostring(c:IsVisible()),
                c:GetWidth(), c:GetHeight(), point and (point .. " to " .. (rel and rel:GetDebugName() or "?")) or "NO"))
        end
    end
end

function Auras:Init()
    self.ready = true
    self:Apply()
end

-- Show spell IDs on aura and spell tooltips so adding to a list is just "hover, read, type".
if TooltipDataProcessor and Enum.TooltipDataType then
    local function AddID(tooltip, data)
        if not data then return end
        local id = data.id
        if issecret(id) or not id then return end
        tooltip:AddLine("Spell ID: " .. id, 0.5, 0.8, 1)
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, AddID)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddID)
end
