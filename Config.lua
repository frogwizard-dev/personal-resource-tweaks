local _, ns = ...
local Config = {}
ns.Config = Config

local WIDTH, HEIGHT = 550, 760

-- The controls are FrogLib's (UI.lua); every change calls ns.Refresh().
local UI = FrogLib.UI.Kit({ refresh = function() ns.Refresh() end })
local Label, Button, Checkbox, Stepper, Dropdown, Options, ColorSwatch, TextBox, Placer =
    UI.Label, UI.Button, UI.Checkbox, UI.Stepper, UI.Dropdown, UI.Options, UI.ColorSwatch, UI.TextBox, UI.Placer
local SpellInfo, ScrollList, Fill = UI.SpellInfo, UI.ScrollList, UI.FillList

local MODES = Options("whitelist", "Whitelist: only these", "blacklist", "Blacklist: all except these")

local function Help(page, text)
    return UI.Help(page, text, WIDTH - 40)
end

-- A list row showing a spell, with its remove button.
local function SpellRow(row, id)
    local name, icon = SpellInfo(id)
    row.icon:SetTexture(icon or 134400)
    row.text:SetText((name or "Unknown spell") .. " |cff888888(" .. id .. ")|r")
    if not row.remove then
        row.remove = Button(row, "X", 24, 20)
        row.remove:SetPoint("RIGHT", -2, 0)
    end
end

function Config:BuildBars(page)
    local db = ns.db.skin
    local place = Placer()

    place(Checkbox(page, "Skin the Personal Resource Display", db, "enabled"), 30)
    place(Checkbox(page, "Class-coloured health bar", db, "classColor"), 26)
    place(Checkbox(page, "Dark background behind bars", db, "background"), 26)
    place(Dropdown(page, "Mana bar in forms", Options("form", "Only in a form", "never", "Never"), db, "altShow"), 30)
    place(Checkbox(page, "Left-click to target yourself, right-click for your menu", ns.db.clicks, "enabled"), 34)

    local bar = CreateFrame("StatusBar", nil, page)
    bar:SetSize(210, 12)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.7)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.6)
    local function UpdateBar()
        bar:SetStatusBarTexture(db.texture)
        bar:SetStatusBarColor(ns.Skin.ClassColor())
    end
    place(Dropdown(page, "Bar texture", function() return ns.Media:List("statusbar") end,
        function() return db.texture end,
        function(value) db.texture = value; UpdateBar() end), 28)
    place(bar, 34, 150)
    UpdateBar()

    place(Dropdown(page, "Border", Options("pixel", "Pixel (size and colour below)", "classic", "Classic stone",
        "forever", "Forever (cooldown manager frame)"), db, "borderStyle"), 30)
    place(Stepper(page, "Forever border thickness", 1, 3, 1, db, "frameThickness"), 28)
    place(Stepper(page, "Border size in pixels (0 = off)", 0, 6, 1, db, "borderSize"), 28)
    place(ColorSwatch(page, "Border colour", db, "borderColor"), 34)

    -- Sizes, in screen pixels; 0 is Edit Mode's. The first + starts from the bar's size now.
    place(Label(page, "Size (screen pixels; 0 = Edit Mode's)"), 22)
    local size = db.size
    local steppers = {}
    for _, entry in ipairs({ { "width", "Width", 600, 2 }, { "health", "Health bar height", 80, 1 },
        { "power", "Power bar height", 80, 1 }, { "alt", "Mana bar in forms", 80, 1 } }) do
        local key, most = entry[1], entry[3]
        steppers[#steppers + 1] = Stepper(page, entry[2], 0, most, entry[4], function() return size[key] end,
            function(value)
                if size[key] == 0 and value > 0 then value = math.min(most, ns.Skin:MeasureSize(key) + value) end
                size[key] = value
            end)
        place(steppers[#steppers], 26, 12)
    end
    local reset = Button(page, "Use Edit Mode's sizes", 180)
    reset:SetScript("OnClick", function()
        for key in pairs(size) do size[key] = 0 end
        ns.Refresh()
        for _, stepper in ipairs(steppers) do stepper:GetScript("OnShow")(stepper) end
    end)
    place(reset, 26, 12)
    place(Help(page, "Shift-click + or - for 10 at a time. Mana bar in forms at 0 matches the power bar."), 30)
    place(Help(page, "Turning the skin off fully restores Blizzard's look after a /reload."), 22)

    local debug = Button(page, "Print frame debug info", 220)
    debug:SetScript("OnClick", function() ns.Skin:Debug() end)
    place(debug, 30)
end

function Config:BuildText(page)
    local db, text = ns.db.skin, ns.db.text
    local place = Placer()

    -- The power bar's text can differ by power type; `editing` is the one shown in the boxes.
    local editing = "default"
    local POWER_TYPES = Options("default", "Mana, and any other", "RAGE", "Rage", "ENERGY", "Energy",
        "ALT", "Mana bar in forms (druids)")
    for _, bar in ipairs({ { "health", "Health bar text" }, { "power", "Power bar text" } }) do
        local key = bar[1]
        local function Slots()
            if key == "power" and editing == "ALT" then return db.altText end
            if key == "power" and editing ~= "default" then return db.powerTextFor[editing] end
            return db[key .. "Text"]
        end
        place(Label(page, bar[2]), 18)
        local boxes = {}
        if key == "power" then
            place(Dropdown(page, "For", POWER_TYPES, function() return editing end, function(value)
                editing = value
                for slot, box in pairs(boxes) do box.eb:SetText(Slots()[slot]) end
            end), 28, 12)
        end
        for _, slot in ipairs({ { "left", "Left" }, { "center", "Centre" }, { "right", "Right" } }) do
            local box = TextBox(page, slot[2], function() return Slots()[slot[1]] end,
                function(value) Slots()[slot[1]] = value end)
            boxes[slot[1]] = box
            place(box, 24, 12)
        end
        place(Stepper(page, "Edge padding", 0, 30, 1, text, key .. "Padding"), 24, 8)
        place(Stepper(page, "Vertical nudge", -10, 10, 1, text, key .. "Nudge"), 30, 8)
    end
    place(Help(page, "Type any layout using the words |cffffd100value|r, |cffffd100max|r and |cffffd100percent|r "
        .. "(|cffffd100percent.1|r for one decimal). For example: value || percent.1\nLeave it empty to hide the text."),
        44, 4)

    local sample = Label(page, "671 (100%)  The quick brown fox", "GameFontHighlight")
    local function UpdateSample()
        ns.Media:SetFont(sample, text.font, 14, text.outline)
    end
    place(Dropdown(page, "Font", function() return ns.Media:List("font") end,
        function() return text.font end,
        function(value) text.font = value; UpdateSample() end), 30)
    place(Dropdown(page, "Font outline", UI.OUTLINES, function() return text.outline end,
        function(value) text.outline = value; UpdateSample() end), 30)
    place(sample, 36, 4)
    UpdateSample()

    place(Stepper(page, "Health text size", 8, 24, 1, text, "healthSize"), 26)
    place(Stepper(page, "Power text size", 8, 24, 1, text, "powerSize"), 26)
    place(Stepper(page, "Timer text size", 8, 24, 1, text, "timerSize"), 26)
    place(Stepper(page, "Stack text size", 8, 24, 1, text, "stackSize"), 26)
end

function Config:BuildAuraPage(page, kind)
    local settings = ns.db[kind]
    local place = Placer()
    local RefreshList

    local function ActiveList()
        return settings.mode == "whitelist" and settings.list or settings.blacklist
    end

    place(Checkbox(page, "Show " .. kind, settings, "enabled"), 26)
    place(Checkbox(page, "Show countdown numbers", settings, "showTimer"), 30)
    place(Dropdown(page, "Mode", MODES, function() return settings.mode end,
        function(value) settings.mode = value; RefreshList() end), 30)
    place(Stepper(page, "Icon size", 16, 64, 2, settings, "size"), 26)
    place(Stepper(page, "Icons per row", 1, 16, 1, settings, "perRow"), 26)
    place(Stepper(page, "Max icons (blacklist)", 1, 40, 1, settings, "max"), 26)
    place(Stepper(page, "Spacing", 0, 12, 1, settings, "spacing"), 26)
    place(Stepper(page, "Vertical offset", -40, 80, 2, settings, "offsetY"), 30)

    local header = Label(page, "")
    place(header, 16)
    place(Label(page, "Tip: hover any buff or spell to see its Spell ID.", "GameFontDisableSmall"), 20)

    local list = ScrollList(page, WIDTH - 36, 138)

    local function AddID(id)
        id = tonumber(id)
        if not id then return end
        if not SpellInfo(id) then
            ns.Print("No spell with ID", id)
            return
        end
        local ids = ActiveList()
        if tContains(ids, id) then return end
        table.insert(ids, id)
        RefreshList()
        ns.Refresh()
    end

    local input = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    input:SetSize(90, 20)
    input:SetAutoFocus(false)
    input:SetNumeric(true)
    place(input, 22, 6)
    local add = Button(page, "Add ID", 70)
    add:SetPoint("LEFT", input, "RIGHT", 6, 0)
    local pick = Button(page, "Pick from my current " .. kind, 190)
    pick:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local preview = Label(page, "", "GameFontHighlightSmall")
    place(preview, 20, 6)

    input:SetScript("OnTextChanged", function(self)
        preview:SetText(SpellInfo(tonumber(self:GetText()) or 0) or "")
    end)
    input:SetScript("OnEnterPressed", function(self)
        AddID(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    add:SetScript("OnClick", function()
        AddID(input:GetText())
        input:SetText("")
    end)
    pick:SetScript("OnClick", function() Config:ShowPicker(kind, AddID) end)

    place(list, 0)

    function RefreshList()
        local ids = ActiveList()
        local ordered = settings.mode == "whitelist"
        header:SetText(ordered and "Whitelist (shown in this order)" or "Blacklist (never shown)")
        Fill(list, ids, function(row, id, i)
            SpellRow(row, id)
            if not row.down then
                row.down = Button(row, "Dn", 36, 20)
                row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
                row.up = Button(row, "Up", 36, 20)
                row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
            end
            row.up:SetShown(ordered)
            row.down:SetShown(ordered)
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #ids)
            row.remove:SetScript("OnClick", function()
                table.remove(ids, i)
                RefreshList()
                ns.Refresh()
            end)
            row.up:SetScript("OnClick", function()
                ids[i], ids[i - 1] = ids[i - 1], ids[i]
                RefreshList()
                ns.Refresh()
            end)
            row.down:SetScript("OnClick", function()
                ids[i], ids[i + 1] = ids[i + 1], ids[i]
                RefreshList()
                ns.Refresh()
            end)
        end)
    end
    RefreshList()
end

function Config:BuildPower(page)
    local fade, marks = ns.db.fade, ns.db.marks
    local place = Placer()

    place(Label(page, "Fade when idle"), 22)
    place(Checkbox(page, "Fade out when out of combat at full health with power at rest", fade, "enabled"), 26)
    place(Checkbox(page, "...but stay visible while you have a target", fade, "target"), 26, 20)
    place(Stepper(page, "Faded opacity (%)", 0, 100, 5, function() return math.floor(fade.alpha * 100 + 0.5) end,
        function(value) fade.alpha = value / 100 end), 26, 20)
    place(Help(page, "\"At rest\" is empty for rage, full for mana and energy. Any damage, power "
        .. "or combat brings it straight back, and it always shows in Edit Mode."), 40)

    local regen = ns.db.regen
    place(Label(page, "Mana regen"), 22)
    place(Checkbox(page, "Show when mana regen starts again (the five-second rule)", regen, "enabled"), 26)
    place(ColorSwatch(page, "Its colour", regen, "color"), 30, 20)

    place(Label(page, "Ability cost marks"), 22)
    place(Checkbox(page, "Mark ability costs on the power bar", marks, "enabled"), 26)
    place(ColorSwatch(page, "Mark colour", marks, "color"), 26)
    place(Stepper(page, "Mark width (pixels)", 1, 4, 1, marks, "width"), 30)
    place(Help(page, "A mark shows for each ability below that you know and that costs the power "
        .. "the bar shows, at its cost. Add one by name (as in your spellbook) or spell ID."), 32)

    local list = ScrollList(page, WIDTH - 36, 160)
    local RefreshList
    local input = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    input:SetSize(180, 20)
    input:SetAutoFocus(false)
    place(input, 28, 6)
    local add = Button(page, "Add", 60)
    add:SetPoint("LEFT", input, "RIGHT", 6, 0)
    local function Add()
        local typed = strtrim(input:GetText() or "")
        local id = tonumber(typed)
        if not id then
            local info = typed ~= "" and C_Spell.GetSpellInfo(typed)
            id = info and info.spellID
        end
        if not (id and C_Spell.GetSpellName(id)) then
            ns.Print("No spell called \"" .. typed .. "\" in your spellbook.")
            return
        end
        if tContains(marks.spells, id) then return end
        table.insert(marks.spells, id)
        input:SetText("")
        RefreshList()
        ns.Refresh()
    end
    input:SetScript("OnEnterPressed", function(self)
        Add()
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    add:SetScript("OnClick", Add)
    place(list, 0)

    function RefreshList()
        Fill(list, marks.spells, function(row, id, i)
            SpellRow(row, id)
            row.remove:SetScript("OnClick", function()
                table.remove(marks.spells, i)
                RefreshList()
                ns.Refresh()
            end)
        end)
    end
    RefreshList()
end

function Config:BuildCombo(page)
    local combo = ns.db.combo
    local place = Placer()

    place(Checkbox(page, "Show combo points (rogues, and druids in cat form)", combo, "enabled"), 30)
    place(Dropdown(page, "Position", Options("below", "Below the bars", "above", "Above the bars"),
        combo, "position"), 30)

    -- Sizes, in screen pixels, like the bars'.
    place(Label(page, "Size (screen pixels)"), 22)
    place(Stepper(page, "Height", 4, 40, 1, combo, "height"), 26, 12)
    place(Stepper(page, "Point width (0 = span)", 0, 120, 1, combo, "width"), 26, 12)
    place(Stepper(page, "Space between points", 0, 20, 1, combo, "spacing"), 26, 12)
    place(Stepper(page, "Gap from the bars", 0, 40, 1, combo, "gap"), 26, 12)
    place(Help(page, "At width 0 the points share the bars' width between them. Spaces are "
        .. "measured between the borders."), 34)

    place(Label(page, "Colour"), 22)
    place(Checkbox(page, "Class colour", combo, "classColor"), 26)
    place(ColorSwatch(page, "Own colour", combo, "color"), 30, 20)
    place(Checkbox(page, "A different colour at max points", combo, "maxEnabled"), 26)
    place(ColorSwatch(page, "Colour at max", combo, "maxColor"), 34, 20)

    place(Help(page, "The points use the Bars page's texture, background and border (style, size "
        .. "and colour). While they're on, Blizzard's own combo points under the bars are hidden; "
        .. "turning these off brings them back."), 44)
    place(Help(page, "Edit Mode's \"" .. (HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_HIDE_CLASS_INFO
        or "Hide Class Resource") .. "\" also takes away the space Blizzard keeps for its points under "
        .. "the bars, and is how to hide them in the gamepad UI, where these leave Blizzard's alone."), 44)
end

-- Lists the auras currently on you, so you can whitelist without knowing IDs.
function Config:ShowPicker(kind, onAdd)
    self.picker = UI.AuraPicker(self.frame, kind, onAdd, ns.Print)
end

function Config:Build()
    self.frame = UI.Window("PersonalResourceTweaksConfig", "PersonalResourceTweaks", WIDTH, HEIGHT, {
        { "bars", "Bars", function(page) self:BuildBars(page) end },
        { "text", "Text", function(page) self:BuildText(page) end },
        { "buffs", "Buffs", function(page) self:BuildAuraPage(page, "buffs") end },
        { "debuffs", "Debuffs", function(page) self:BuildAuraPage(page, "debuffs") end },
        { "power", "Fade & marks", function(page) self:BuildPower(page) end },
        { "combo", "Combo", function(page) self:BuildCombo(page) end },
    }, { tabWidth = 84, tabGap = 3, onSelect = function() if self.picker then self.picker:Hide() end end })
end

function Config:Toggle()
    if not self.frame then
        self:Build()
        self.frame:Show()
        return
    end
    self.frame:SetShown(not self.frame:IsShown())
end

-- Its entry in the game's Options > AddOns list (Options.lua).
FrogLib.Options.Add("PersonalResourceTweaks", ns, {
    open = function()
        if not (Config.frame and Config.frame:IsShown()) then Config:Toggle() end
    end,
    commands = {
        { "/prt", "open or close the settings" },
        { "/prt debug", "report what it finds of the Personal Resource Display" },
        { "/prt fade", "say whether the display counts as idle, and why not" },
    },
})
