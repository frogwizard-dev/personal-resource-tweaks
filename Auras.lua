local _, ns = ...
local Auras = {}
ns.Auras = Auras

-- Built on 12.1's AuraContainer: we hand the engine a filter ("HELPFUL, only these IDs" or
-- "HARMFUL, except these IDs") and it picks and renders the auras itself. That keeps working
-- in restricted content, where addons can't read aura data at all.

local issecret = FrogLib.issecret
local KINDS = { "buffs", "debuffs" }
local containers, signatures = {}, {}
local styled = { buffs = {}, debuffs = {} } -- per-button region tables, for restyling

local SORT = AuraContainerSortMethod and AuraContainerSortMethod.Default
local SORT_DIR = AuraContainerSortDirection and AuraContainerSortDirection.Normal

-- The rows' building blocks: FrogLib's Auras.lua. Countdown text is formatted engine-side (the
-- remaining time can be secret): "45", "2m", "1h".
local AuraKit = FrogLib.Auras

local function StyleButton(parts)
    local settings, text = ns.db[parts.kind], ns.db.text
    -- The engine creates buttons at zero size; sizing them is our job. Denied while auras
    -- are secret, so it's retried on the next restyle.
    if parts.size ~= settings.size and pcall(parts.button.SetSize, parts.button, settings.size, settings.size) then
        parts.size = settings.size
    end
    ns.Media:SetFont(parts.stack, text.font, text.stackSize, text.outline)
    ns.Media:SetFont(parts.duration, text.font, text.timerSize, text.outline)
    parts.duration:SetShown(settings.showTimer)
end

-- Runs once per engine-created button; the timer centred on the icon.
local function MakeInit(kind)
    return function(button)
        local parts = AuraKit.InitButton(button, { border = kind == "debuffs" and { 0.8, 0.1, 0.1 } or nil, timerOnIcon = true,
            style = function(new)
                new.kind = kind
                StyleButton(new)
            end })
        table.insert(styled[kind], parts)
    end
end

local function Layout(settings)
    return { elementWidth = settings.size, elementHeight = settings.size, elementSpacing = settings.spacing,
        lineSpacing = settings.spacing }
end

-- Anything that changes which groups exist; groups can't be removed from a container, so a
-- change here means building a fresh one.
local function Signature(settings)
    local ids = settings.mode == "whitelist" and settings.list or settings.blacklist
    return settings.mode .. "|" .. settings.max .. "|" .. table.concat(ids, ",")
end

local function Build(kind)
    local settings = ns.db[kind]
    AuraKit.Release(containers[kind])
    containers[kind] = nil

    local container = AuraKit.NewContainer(ns.Skin.display or UIParent)
    if not container then
        if not Auras.warned then
            Auras.warned = true
            ns.Print("This client has no aura containers, so buffs/debuffs can't be shown.")
        end
        return
    end

    -- Position it before anything else: the engine only processes containers with a
    -- renderable rect, and one set up unanchored silently never shows an aura.
    containers[kind] = container
    Auras:Anchor()
    AuraKit.Flow(container, "BOTTOMLEFT", "RIGHT", "UP")

    styled[kind] = {}
    local init, layout = MakeInit(kind), Layout(settings)
    local filter = kind == "buffs" and "HELPFUL" or "HARMFUL"
    local keys = {}
    local function AddGroup(key, options)
        options.sortMethod, options.sortDirection = SORT, SORT_DIR
        options.initializeFrame, options.layout = init, layout
        local ok, message = pcall(container.AddAuraGroup, container, key, filter, options)
        if ok then
            keys[#keys + 1] = key
        else
            ns.Print("Couldn't set up " .. kind .. ":", message)
        end
    end
    if settings.mode == "whitelist" then
        -- One single-slot group per spell keeps your chosen order.
        for i, id in ipairs(settings.list) do
            AddGroup("w" .. i, { maxFrameCount = 1, candidateFilters = { includeSpellIDs = { [id] = true } } })
        end
    else
        local exclude = {}
        for _, id in ipairs(settings.blacklist) do exclude[id] = true end
        AddGroup("all", { maxFrameCount = settings.max, candidateFilters = next(exclude) and { excludeSpellIDs = exclude } or nil })
    end
    container.prtKeys = keys

    -- Unit last: the engine only registers for aura events once the container has groups.
    container:SetUnit("player")
    container:UpdateAllAuras()
    signatures[kind] = Signature(settings)
end

-- Room kept for the buff row: nothing may anchor to an aura container, so debuffs anchor to the
-- health bar past it (a whitelist's lines from its count; a blacklist's unknown, so one line).
local function BuffRowHeight()
    local buffs = ns.db.buffs
    local count = buffs.mode == "whitelist" and #buffs.list or 1
    if not buffs.enabled or count == 0 then return 0 end
    local lines = math.ceil(count / buffs.perRow)
    return buffs.offsetY + lines * (buffs.size + buffs.spacing) - buffs.spacing
end

-- Buffs sit directly on top of the health bar (or on the combo points, when they're above it),
-- debuffs above the buffs.
function Auras:Anchor()
    local parent = ns.Skin.display or UIParent
    local anchor, point = ns.Skin.health, "TOP"
    if not anchor then
        anchor, point = UIParent, "CENTER"
    end
    local combo = ns.Combo:SpaceAbove()
    local offsets = {
        buffs = combo + ns.db.buffs.offsetY,
        debuffs = combo + BuffRowHeight() + ns.db.debuffs.offsetY,
    }
    for kind, container in pairs(containers) do
        container:SetParent(parent)
        container:ClearAllPoints()
        container:SetPoint("BOTTOM", anchor, point, 0, offsets[kind])
    end
end

function Auras:Apply()
    if not self.ready then return end
    for _, kind in ipairs(KINDS) do
        local settings = ns.db[kind]
        if not containers[kind] or signatures[kind] ~= Signature(settings) then
            Build(kind)
        end
        local container = containers[kind]
        if container then
            local layout = Layout(settings)
            for _, key in ipairs(container.prtKeys) do
                pcall(container.SetAuraGroupLayout, container, key, layout)
            end
            AuraKit.SetLineSize(container, settings.perRow * (settings.size + settings.spacing) - settings.spacing + 0.4)
            container:SetShown(settings.enabled)
            for _, parts in ipairs(styled[kind]) do
                pcall(StyleButton, parts)
            end
        end
    end
    self:Anchor()
end

function Auras:Debug()
    for _, kind in ipairs(KINDS) do
        local settings, container = ns.db[kind], containers[kind]
        local ids = settings.mode == "whitelist" and settings.list or settings.blacklist
        if not container then
            ns.Print(kind .. ": |cffff5555no container|r")
        else
            local point, relativeTo = container:GetPoint(1)
            ns.Print(string.format("%s: %s (%d IDs), groups %d, buttons %d, shown %s, visible %s, size %.0fx%.0f, anchored %s",
                kind, settings.mode, #ids, #container.prtKeys, #styled[kind], tostring(container:IsShown()),
                tostring(container:IsVisible()), container:GetWidth(), container:GetHeight(),
                point and (point .. " to " .. (relativeTo and relativeTo:GetDebugName() or "?")) or "NO"))
        end
    end
end

function Auras:Init()
    self.ready = true
    self:Apply()
end

-- Spell IDs on aura and spell tooltips, so adding one to a list is "hover, read, type".
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
