local ADDON, ns = ...

ns.defaults = {
    skin = {
        enabled = true,
        texture = "Interface\\Buttons\\WHITE8X8",
        classColor = true,
        background = true,
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        -- Text templates per slot; see Compile in Skin.lua. Empty = hidden.
        healthText = { left = "", center = "value (percent)", right = "" },
        powerText = { left = "", center = "value", right = "" },
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
    debuffs = {
        enabled = true, mode = "blacklist", list = {}, blacklist = {}, max = 16,
        size = 24, spacing = 3, perRow = 8, offsetY = 4, showTimer = true,
    },
}

-- Midnight hides some combat values from addons ("secret values"). They can be handed to
-- Blizzard widgets for display, but not compared or used in arithmetic.
ns.issecret = issecretvalue or function() return false end

function ns.Print(...)
    print("|cff66ccffPersonalResourceTweaks|r:", ...)
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.Refresh()
    ns.Skin:Apply()
    ns.Auras:Apply()
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
        CopyDefaults(ns.defaults, db)
        ns.db = db
    elseif event == "PLAYER_LOGIN" then
        ns.Skin:Init()
        ns.Auras:Init()
    end
end)

SLASH_PERSONALRESOURCETWEAKS1 = "/prt"
SlashCmdList.PERSONALRESOURCETWEAKS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "debug" then
        ns.Skin:Debug()
    else
        ns.Config:Toggle()
    end
end

function PersonalResourceTweaks_OnCompartmentClick()
    ns.Config:Toggle()
end
