local ADDON, ns = ...

ns.defaults = {
    skin = {
        enabled = true,
        texture = "Interface\\Buttons\\WHITE8X8",
        classColor = true,
        background = true,
        borderSize = 1,
        -- "pixel" (borderSize pixels in borderColor), "classic" (the grey stone border) or
        -- "forever" (the cooldown manager's bar frame).
        borderStyle = "pixel",
        frameThickness = 1, -- the forever border: screen pixels per pixel of its art (1 to 3)
        -- Bar sizes in screen pixels, over Edit Mode's (Skin.lua); 0 keeps Edit Mode's. alt: the
        -- druid's mana bar in forms (0 = as tall as the power bar).
        size = { width = 0, health = 0, power = 0, alt = 0 },
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        -- Text templates per slot (words value, max, percent; FrogLib.Text). Empty = hidden.
        healthText = { left = "", center = "value (percent)", right = "" },
        powerText = { left = "", center = "value", right = "" },
        -- Its own text for these power types (mana and anything else use powerText). Rage and
        -- energy top out at 100, so their percent only repeats the number.
        -- The mana bar druids get in a form (Blizzard's third bar): its text, and when it shows:
        -- "always", "form" (only while your main bar isn't mana) or "never".
        altText = { left = "", center = "value", right = "" },
        altShow = "form",
        powerTextFor = {
            RAGE = { left = "", center = "value", right = "" },
            ENERGY = { left = "", center = "value", right = "" },
        },
    },
    -- Fade the display out when idle (Power.lua): out of combat, full health, power at rest
    -- and (with `target`) nothing targeted. alpha: how visible it stays.
    fade = { enabled = true, alpha = 0, target = true },
    -- Lines on the power bar at each ability's cost (Power.lua). spells: spell IDs; a mark shows
    -- for the ones you know that cost the bar's power. (Seeded once, below: as a default here,
    -- spells you remove would come back at the next login.)
    marks = { enabled = true, width = 1, color = { r = 1, g = 1, b = 1, a = 0.7 }, spells = {} },
    -- The five-second rule: a strip under your mana bar until mana regen starts again (Power.lua).
    regen = { enabled = true, color = { r = 0.55, g = 0.85, b = 1.00 } },
    -- Combo points as a row of pips in the bars' texture and border (Combo.lua). Sizes in screen
    -- pixels: width 0 spans the bars; gap is from the bars, spacing between pips (both measured
    -- between borders). position: "below" or "above" the bars. maxColor: all pips at max points.
    combo = {
        enabled = true, position = "below", gap = 3, height = 8, width = 0, spacing = 2,
        classColor = true, color = { r = 1, g = 0.82, b = 0.2 },
        maxEnabled = false, maxColor = { r = 1, g = 0.3, b = 0.2 },
    },
    text = {
        font = "Fonts\\FRIZQT__.TTF",
        outline = "OUTLINE",
        healthSize = 12,
        powerSize = 10,
        -- Left/right text distance from the bar edges, and a vertical shift for fonts that sit off-centre.
        healthPadding = 4,
        healthNudge = 0,
        powerPadding = 4,
        powerNudge = 0,
        timerSize = 12,
        stackSize = 11,
    },
    -- mode: "whitelist" shows only `list` (in order); "blacklist" shows everything except `blacklist`.
    buffs = {
        enabled = true, mode = "whitelist", list = {}, blacklist = {}, max = 16,
        size = 28, spacing = 3, perRow = 8, offsetY = 4, showTimer = true,
    },
    -- Left-click the display to target yourself, right-click for your unit menu (Clicks.lua).
    clicks = { enabled = true },
    debuffs = {
        enabled = true, mode = "blacklist", list = {}, blacklist = {}, max = 16,
        size = 24, spacing = 3, perRow = 8, offsetY = 4, showTimer = true,
    },
}

-- Midnight hides some combat values from addons ("secret values"). They can be handed to
-- Blizzard widgets for display, but not compared or used in arithmetic.
ns.issecret = FrogLib.issecret

ns.Print = FrogLib.Util.Printer("PersonalResourceTweaks", "66ccff")

local CopyDefaults = FrogLib.Util.CopyDefaults

function ns.Refresh()
    ns.Skin:Apply()
    ns.Auras:Apply()
    if ns.Clicks.initialised then ns.Clicks:Place() end
    if ns.Power.initialised then ns.Power:Apply() end
    if ns.Combo.initialised then ns.Combo:Apply() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        PersonalResourceTweaksDB = PersonalResourceTweaksDB or {}
        local db = PersonalResourceTweaksDB
        -- 0.1 stored the texture as an index into a fixed list; it's a file path now.
        if db.skin and type(db.skin.texture) ~= "string" then
            db.skin.texture = nil
        end
        -- 0.2 had on/off toggles for the border and health text.
        if db.skin then
            if db.skin.border == false then db.skin.borderSize = 0 end
            db.skin.border = nil
            if type(db.skin.healthText) == "boolean" then
                if db.skin.healthText == false then db.skin.healthFormat = "none" end
                db.skin.healthText = nil
            end
        end
        -- 0.3 picked from fixed formats; 0.4 takes a typed template.
        if db.skin then
            local templates = { none = "", value = "value", percent = "percent", both = "value (percent)" }
            if db.skin.healthFormat then db.skin.healthTemplate = templates[db.skin.healthFormat] end
            if db.skin.powerFormat then db.skin.powerTemplate = templates[db.skin.powerFormat] end
            db.skin.healthFormat, db.skin.powerFormat = nil, nil
        end
        -- 0.4 had one template per bar; 0.5 has left/center/right slots.
        if db.skin then
            if db.skin.healthTemplate then
                db.skin.healthText = { left = "", center = db.skin.healthTemplate, right = "" }
            end
            if db.skin.powerTemplate then
                db.skin.powerText = { left = "", center = db.skin.powerTemplate, right = "" }
            end
            db.skin.healthTemplate, db.skin.powerTemplate = nil, nil
        end
        -- 0.6 adds text per power type: rage and energy start as the power text without its percent.
        if db.skin and db.skin.powerText and not db.skin.powerTextFor then
            local function NoPercent(s)
                s = (s or ""):gsub("[Pp][Ee][Rr][Cc][Ee][Nn][Tt]%.?%d*", "")
                s = s:gsub("%(%s*%)", ""):gsub("^[%s|/%-]+", ""):gsub("[%s|/%-]+$", "")
                return s
            end
            local slots = {}
            for slot, s in pairs(db.skin.powerText) do slots[slot] = NoPercent(s) end
            db.skin.powerTextFor = { RAGE = CopyTable(slots), ENERGY = CopyTable(slots) }
        end
        -- 0.6 adds text to the in-form mana bar: it starts as the power text (mana's).
        if db.skin and db.skin.powerText and not db.skin.altText then
            db.skin.altText = CopyTable(db.skin.powerText)
        end
        local firstMarks = db.marks == nil
        CopyDefaults(ns.defaults, db)
        -- Heroic Strike, Revenge and Shield Block, to start with.
        if firstMarks then db.marks.spells = { 78, 6572, 2565 } end
        ns.db = db
    elseif event == "PLAYER_LOGIN" then
        ns.Skin:Init()
        ns.Auras:Init()
        ns.Clicks:Init()
        ns.Clicks.initialised = true
        ns.Power:Init()
        ns.Power.initialised = true
        ns.Combo:Init()
        ns.Combo.initialised = true
    end
end)

SLASH_PERSONALRESOURCETWEAKS1 = "/prt"
SlashCmdList.PERSONALRESOURCETWEAKS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "debug" then
        ns.Skin:Debug()
    elseif msg == "fade" then
        ns.Power:Debug()
    else
        ns.Config:Toggle()
    end
end

function PersonalResourceTweaks_OnCompartmentClick()
    ns.Config:Toggle()
end
