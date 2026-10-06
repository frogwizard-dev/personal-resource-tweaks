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

-- The rows' building blocks: FrogLib's Auras.lua. Countdown text is formatted engine-side (the
-- remaining time can be secret): "45", "2m", "1h".
local A = FrogLib.Auras

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

-- Runs once per engine-created button; the timer centred on the icon.
local function MakeInit(kind)
    return function(button)
        local d = A.InitButton(button, { border = kind == "debuffs" and { 0.8, 0.1, 0.1 } or nil, timerOnIcon = true,
            style = function(new)
                new.kind = kind
                StyleButton(new)
            end })
        table.insert(styled[kind], d)
    end
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
    A.Release(containers[kind])
    containers[kind] = nil

    local c = A.NewContainer(ns.Skin.prd or UIParent)
    if not c then
        if not Auras.warned then
            Auras.warned = true
            ns.Print("This client has no aura containers, so buffs/debuffs can't be shown.")
        end
        return
    end

    -- Position it before anything else: the engine only processes containers with a
    -- renderable rect, and one set up unanchored silently never shows an aura.
    containers[kind] = c
    Auras:Anchor()
    A.Flow(c, "BOTTOMLEFT", "RIGHT", "UP")

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

-- Buffs sit directly on top of the health bar (or on the combo points, when they're above it),
-- debuffs above the buffs.
function Auras:Anchor()
    local parent = ns.Skin.prd or UIParent
    local anchor, point = ns.Skin.health, "TOP"
    if not anchor then
        anchor, point = UIParent, "CENTER"
    end
    local combo = ns.Combo:SpaceAbove()
    local offsets = {
        buffs = combo + ns.db.buffs.offsetY,
        debuffs = combo + BuffRowHeight() + ns.db.debuffs.offsetY,
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
            A.SetLineSize(c, cfg.perRow * (cfg.size + cfg.spacing) - cfg.spacing + 0.4)
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
