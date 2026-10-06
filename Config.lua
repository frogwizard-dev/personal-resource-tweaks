local _, ns = ...
local Config = {}
ns.Config = Config

local W, H = 550, 760

-- The controls are FrogLib's (UI.lua); every change calls ns.Refresh().
local UI = FrogLib.UI.Kit({ refresh = function() ns.Refresh() end })
local Label, Button, Checkbox, Stepper, Dropdown, Options, ColorSwatch, TextBox, Placer =
    UI.Label, UI.Button, UI.Checkbox, UI.Stepper, UI.Dropdown, UI.Options, UI.ColorSwatch, UI.TextBox, UI.Placer
local SpellInfo, ScrollList, Fill = UI.SpellInfo, UI.ScrollList, UI.FillList

local OUTLINES = Options("", "None", "OUTLINE", "Outline", "THICKOUTLINE", "Thick outline")
local MODES = Options("whitelist", "Whitelist: only these", "blacklist", "Blacklist: all except these")

function Config:BuildBars(p)
    local db = ns.db.skin
    local place = Placer()

    place(Checkbox(p, "Skin the Personal Resource Display", function() return db.enabled end, function(v) db.enabled = v end), 30)
    place(Checkbox(p, "Class-coloured health bar", function() return db.classColor end, function(v) db.classColor = v end), 26)
    place(Checkbox(p, "Dark background behind bars", function() return db.background end, function(v) db.background = v end), 26)
    place(Dropdown(p, "Mana bar in forms", Options("form", "Only in a form", "always", "Always",
        "never", "Never"), function() return db.altShow end, function(v) db.altShow = v end), 30)
    place(Checkbox(p, "Left-click to target yourself, right-click for your menu",
        function() return ns.db.clicks.enabled end, function(v) ns.db.clicks.enabled = v end), 34)

    local bar = CreateFrame("StatusBar", nil, p)
    bar:SetSize(210, 12)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.7)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.6)
    local _, class = UnitClass("player")
    local function updateBar()
        bar:SetStatusBarTexture(db.texture)
        local r, g, b = FrogLib.Color.Class(class)
        bar:SetStatusBarColor(r or 1, g or 1, b or 1)
    end
    place(Dropdown(p, "Bar texture", function() return ns.Media:List("statusbar") end,
        function() return db.texture end,
        function(v) db.texture = v; updateBar() end), 28)
    place(bar, 34, 150)
    updateBar()

    place(Dropdown(p, "Border", Options("pixel", "Pixel (size and colour below)", "classic", "Classic stone",
        "forever", "Forever (cooldown manager frame)"), function() return db.borderStyle end,
        function(v) db.borderStyle = v end), 30)
    place(Stepper(p, "Forever border thickness", 1, 3, 1, function() return db.frameThickness end,
        function(v) db.frameThickness = v end), 28)
    place(Stepper(p, "Border size in pixels (0 = off)", 0, 6, 1, function() return db.borderSize end, function(v) db.borderSize = v end), 28)
    place(ColorSwatch(p, "Border colour", function() return db.borderColor end,
        function(r, g, b) db.borderColor = { r = r, g = g, b = b, a = 1 } end), 34)

    -- Sizes, in screen pixels; 0 is Edit Mode's. The first + starts from the bar's size now.
    place(Label(p, "Size (screen pixels; 0 = Edit Mode's)"), 22)
    local size = db.size
    local steppers = {}
    for _, def in ipairs({ { "width", "Width", 600, 2 }, { "health", "Health bar height", 80, 1 },
        { "power", "Power bar height", 80, 1 }, { "alt", "Mana bar in forms", 80, 1 } }) do
        local key = def[1]
        steppers[#steppers + 1] = Stepper(p, def[2], 0, def[3], def[4], function() return size[key] end,
            function(v)
                if size[key] == 0 and v > 0 then v = math.min(def[3], ns.Skin:MeasureSize(key) + v) end
                size[key] = v
            end)
        place(steppers[#steppers], 26, 12)
    end
    local reset = Button(p, "Use Edit Mode's sizes", 180)
    reset:SetScript("OnClick", function()
        for k in pairs(size) do size[k] = 0 end
        ns.Refresh()
        for _, st in ipairs(steppers) do st:GetScript("OnShow")(st) end
    end)
    place(reset, 26, 12)
    local sizeNote = Label(p, "Shift-click + or - for 10 at a time. Mana bar in forms at 0 matches the power bar.",
        "GameFontDisableSmall")
    sizeNote:SetWidth(W - 40)
    sizeNote:SetJustifyH("LEFT")
    place(sizeNote, 30)

    local note = Label(p, "Turning the skin off fully restores Blizzard's look after a /reload.", "GameFontDisableSmall")
    note:SetWidth(W - 40)
    note:SetJustifyH("LEFT")
    place(note, 22)

    local dbg = Button(p, "Print frame debug info", 220)
    dbg:SetScript("OnClick", function() ns.Skin:Debug() end)
    place(dbg, 30)
end

function Config:BuildText(p)
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
        place(Label(p, bar[2]), 18)
        local boxes = {}
        if key == "power" then
            place(Dropdown(p, "For", POWER_TYPES, function() return editing end, function(v)
                editing = v
                for slot, box in pairs(boxes) do box.eb:SetText(Slots()[slot]) end
            end), 28, 12)
        end
        for _, slot in ipairs({ { "left", "Left" }, { "center", "Centre" }, { "right", "Right" } }) do
            local box = TextBox(p, slot[2], function() return Slots()[slot[1]] end,
                function(v) Slots()[slot[1]] = v end)
            boxes[slot[1]] = box
            place(box, 24, 12)
        end
        place(Stepper(p, "Edge padding", 0, 30, 1, function() return text[key .. "Padding"] end,
            function(v) text[key .. "Padding"] = v end), 24, 8)
        place(Stepper(p, "Vertical nudge", -10, 10, 1, function() return text[key .. "Nudge"] end,
            function(v) text[key .. "Nudge"] = v end), 30, 8)
    end
    local help = Label(p, "Type any layout using the words |cffffd100value|r, |cffffd100max|r and |cffffd100percent|r "
        .. "(|cffffd100percent.1|r for one decimal). For example: value || percent.1\nLeave it empty to hide the text.",
        "GameFontDisableSmall")
    help:SetWidth(W - 40)
    help:SetJustifyH("LEFT")
    place(help, 44, 4)

    local sample = Label(p, "671 (100%)  The quick brown fox", "GameFontHighlight")
    local function updateSample()
        ns.Media:SetFont(sample, text.font, 14, text.outline)
    end
    place(Dropdown(p, "Font", function() return ns.Media:List("font") end,
        function() return text.font end,
        function(v) text.font = v; updateSample() end), 30)
    place(Dropdown(p, "Font outline", OUTLINES, function() return text.outline end,
        function(v) text.outline = v; updateSample() end), 30)
    place(sample, 36, 4)
    updateSample()

    place(Stepper(p, "Health text size", 8, 24, 1, function() return text.healthSize end, function(v) text.healthSize = v end), 26)
    place(Stepper(p, "Power text size", 8, 24, 1, function() return text.powerSize end, function(v) text.powerSize = v end), 26)
    place(Stepper(p, "Timer text size", 8, 24, 1, function() return text.timerSize end, function(v) text.timerSize = v end), 26)
    place(Stepper(p, "Stack text size", 8, 24, 1, function() return text.stackSize end, function(v) text.stackSize = v end), 26)
end

function Config:BuildAuraPage(p, kind)
    local cfg = ns.db[kind]
    local place = Placer()
    local refreshList

    local function ActiveList()
        return cfg.mode == "whitelist" and cfg.list or cfg.blacklist
    end

    place(Checkbox(p, "Show " .. kind, function() return cfg.enabled end, function(v) cfg.enabled = v end), 26)
    place(Checkbox(p, "Show countdown numbers", function() return cfg.showTimer end, function(v) cfg.showTimer = v end), 30)
    place(Dropdown(p, "Mode", MODES, function() return cfg.mode end,
        function(v) cfg.mode = v; refreshList() end), 30)
    place(Stepper(p, "Icon size", 16, 64, 2, function() return cfg.size end, function(v) cfg.size = v end), 26)
    place(Stepper(p, "Icons per row", 1, 16, 1, function() return cfg.perRow end, function(v) cfg.perRow = v end), 26)
    place(Stepper(p, "Max icons (blacklist)", 1, 40, 1, function() return cfg.max end, function(v) cfg.max = v end), 26)
    place(Stepper(p, "Spacing", 0, 12, 1, function() return cfg.spacing end, function(v) cfg.spacing = v end), 26)
    place(Stepper(p, "Vertical offset", -40, 80, 2, function() return cfg.offsetY end, function(v) cfg.offsetY = v end), 30)

    local header = Label(p, "")
    place(header, 16)
    place(Label(p, "Tip: hover any buff or spell to see its Spell ID.", "GameFontDisableSmall"), 20)

    local list = ScrollList(p, W - 36, 138)

    local function AddID(id)
        id = tonumber(id)
        if not id then return end
        if not SpellInfo(id) then
            ns.Print("No spell with ID", id)
            return
        end
        local ids = ActiveList()
        for _, v in ipairs(ids) do
            if v == id then return end
        end
        table.insert(ids, id)
        refreshList()
        ns.Refresh()
    end

    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(90, 20)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    place(eb, 22, 6)
    local add = Button(p, "Add ID", 70)
    add:SetPoint("LEFT", eb, "RIGHT", 6, 0)
    local pick = Button(p, "Pick from my current " .. kind, 190)
    pick:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local preview = Label(p, "", "GameFontHighlightSmall")
    place(preview, 20, 6)

    eb:SetScript("OnTextChanged", function(self)
        preview:SetText(SpellInfo(tonumber(self:GetText()) or 0) or "")
    end)
    eb:SetScript("OnEnterPressed", function(self)
        AddID(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    add:SetScript("OnClick", function()
        AddID(eb:GetText())
        eb:SetText("")
    end)
    pick:SetScript("OnClick", function() Config:ShowPicker(kind, AddID) end)

    place(list, 0)

    function refreshList()
        local ids = ActiveList()
        local ordered = cfg.mode == "whitelist"
        header:SetText(ordered and "Whitelist (shown in this order)" or "Blacklist (never shown)")
        Fill(list, ids, function(r, id, i)
            local name, icon = SpellInfo(id)
            r.icon:SetTexture(icon or 134400)
            r.text:SetText((name or "Unknown spell") .. " |cff888888(" .. id .. ")|r")
            if not r.remove then
                r.remove = Button(r, "X", 24, 20)
                r.remove:SetPoint("RIGHT", -2, 0)
                r.down = Button(r, "Dn", 36, 20)
                r.down:SetPoint("RIGHT", r.remove, "LEFT", -2, 0)
                r.up = Button(r, "Up", 36, 20)
                r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
            end
            r.up:SetShown(ordered)
            r.down:SetShown(ordered)
            r.up:SetEnabled(i > 1)
            r.down:SetEnabled(i < #ids)
            r.remove:SetScript("OnClick", function()
                table.remove(ids, i)
                refreshList()
                ns.Refresh()
            end)
            r.up:SetScript("OnClick", function()
                ids[i], ids[i - 1] = ids[i - 1], ids[i]
                refreshList()
                ns.Refresh()
            end)
            r.down:SetScript("OnClick", function()
                ids[i], ids[i + 1] = ids[i + 1], ids[i]
                refreshList()
                ns.Refresh()
            end)
        end)
    end
    refreshList()
end

function Config:BuildPower(p)
    local fade, marks = ns.db.fade, ns.db.marks
    local place = Placer()

    place(Label(p, "Fade when idle"), 22)
    place(Checkbox(p, "Fade out when out of combat at full health with power at rest",
        function() return fade.enabled end, function(v) fade.enabled = v end), 26)
    place(Checkbox(p, "...but stay visible while you have a target",
        function() return fade.target end, function(v) fade.target = v end), 26, 20)
    place(Stepper(p, "Faded opacity (%)", 0, 100, 5, function() return math.floor(fade.alpha * 100 + 0.5) end,
        function(v) fade.alpha = v / 100 end), 26, 20)
    local note = Label(p, "\"At rest\" is empty for rage, full for mana and energy. Any damage, power "
        .. "or combat brings it straight back, and it always shows in Edit Mode.", "GameFontDisableSmall")
    note:SetWidth(W - 40)
    note:SetJustifyH("LEFT")
    place(note, 40)

    local regen = ns.db.regen
    place(Label(p, "Mana regen"), 22)
    place(Checkbox(p, "Show when mana regen starts again (the five-second rule)",
        function() return regen.enabled end, function(v) regen.enabled = v end), 26)
    place(ColorSwatch(p, "Its colour", function() return regen.color end,
        function(r, g, b) regen.color = { r = r, g = g, b = b } end), 30, 20)

    place(Label(p, "Ability cost marks"), 22)
    place(Checkbox(p, "Mark ability costs on the power bar",
        function() return marks.enabled end, function(v) marks.enabled = v end), 26)
    place(ColorSwatch(p, "Mark colour", function() return marks.color end,
        function(r, g, b) marks.color = { r = r, g = g, b = b, a = marks.color.a or 0.7 } end), 26)
    place(Stepper(p, "Mark width (pixels)", 1, 4, 1, function() return marks.width end,
        function(v) marks.width = v end), 30)
    local help = Label(p, "A mark shows for each ability below that you know and that costs the power "
        .. "the bar shows, at its cost. Add one by name (as in your spellbook) or spell ID.", "GameFontDisableSmall")
    help:SetWidth(W - 40)
    help:SetJustifyH("LEFT")
    place(help, 32)

    local list = ScrollList(p, W - 36, 160)
    local refresh
    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(180, 20)
    eb:SetAutoFocus(false)
    place(eb, 28, 6)
    local add = Button(p, "Add", 60)
    add:SetPoint("LEFT", eb, "RIGHT", 6, 0)
    local function Add()
        local text = strtrim(eb:GetText() or "")
        local id = tonumber(text)
        if not id then
            local info = text ~= "" and C_Spell.GetSpellInfo(text)
            id = info and info.spellID
        end
        if not (id and C_Spell.GetSpellName(id)) then
            ns.Print("No spell called \"" .. text .. "\" in your spellbook.")
            return
        end
        for _, v in ipairs(marks.spells) do
            if v == id then return end
        end
        table.insert(marks.spells, id)
        eb:SetText("")
        refresh()
        ns.Refresh()
    end
    eb:SetScript("OnEnterPressed", function(self)
        Add()
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    add:SetScript("OnClick", Add)
    place(list, 0)

    function refresh()
        Fill(list, marks.spells, function(r, id, i)
            local name, icon = SpellInfo(id)
            r.icon:SetTexture(icon or 134400)
            r.text:SetText((name or "Unknown spell") .. " |cff888888(" .. id .. ")|r")
            if not r.remove then
                r.remove = Button(r, "X", 24, 20)
                r.remove:SetPoint("RIGHT", -2, 0)
            end
            r.remove:SetScript("OnClick", function()
                table.remove(marks.spells, i)
                refresh()
                ns.Refresh()
            end)
        end)
    end
    refresh()
end

function Config:BuildCombo(p)
    local cfg = ns.db.combo
    local place = Placer()

    place(Checkbox(p, "Show combo points (rogues, and druids in cat form)",
        function() return cfg.enabled end, function(v) cfg.enabled = v end), 30)
    place(Dropdown(p, "Position", Options("below", "Below the bars", "above", "Above the bars"),
        function() return cfg.position end, function(v) cfg.position = v end), 30)

    -- Sizes, in screen pixels, like the bars'.
    place(Label(p, "Size (screen pixels)"), 22)
    place(Stepper(p, "Height", 4, 40, 1, function() return cfg.height end,
        function(v) cfg.height = v end), 26, 12)
    place(Stepper(p, "Point width (0 = span)", 0, 120, 1, function() return cfg.width end,
        function(v) cfg.width = v end), 26, 12)
    place(Stepper(p, "Space between points", 0, 20, 1, function() return cfg.spacing end,
        function(v) cfg.spacing = v end), 26, 12)
    place(Stepper(p, "Gap from the bars", 0, 40, 1, function() return cfg.gap end,
        function(v) cfg.gap = v end), 26, 12)
    local sizeNote = Label(p, "At width 0 the points share the bars' width between them. Spaces are "
        .. "measured between the borders.", "GameFontDisableSmall")
    sizeNote:SetWidth(W - 40)
    sizeNote:SetJustifyH("LEFT")
    place(sizeNote, 34)

    place(Label(p, "Colour"), 22)
    place(Checkbox(p, "Class colour", function() return cfg.classColor end,
        function(v) cfg.classColor = v end), 26)
    place(ColorSwatch(p, "Own colour", function() return cfg.color end,
        function(r, g, b) cfg.color = { r = r, g = g, b = b } end), 30, 20)
    place(Checkbox(p, "A different colour at max points", function() return cfg.maxEnabled end,
        function(v) cfg.maxEnabled = v end), 26)
    place(ColorSwatch(p, "Colour at max", function() return cfg.maxColor end,
        function(r, g, b) cfg.maxColor = { r = r, g = g, b = b } end), 34, 20)

    local note = Label(p, "The points use the Bars page's texture, background and border (style, size "
        .. "and colour). Forever's display has no combo points of its own, so turning them off "
        .. "leaves it as Blizzard has it.", "GameFontDisableSmall")
    note:SetWidth(W - 40)
    note:SetJustifyH("LEFT")
    place(note, 44)
end

-- Lists the auras currently on you, so you can whitelist without knowing IDs.
function Config:ShowPicker(kind, onAdd)
    self.picker = UI.AuraPicker(self.frame, kind, onAdd, ns.Print)
end

function Config:Build()
    self.frame = UI.Window("PersonalResourceTweaksConfig", "PersonalResourceTweaks", W, H, {
        { "bars", "Bars", function(p) self:BuildBars(p) end },
        { "text", "Text", function(p) self:BuildText(p) end },
        { "buffs", "Buffs", function(p) self:BuildAuraPage(p, "buffs") end },
        { "debuffs", "Debuffs", function(p) self:BuildAuraPage(p, "debuffs") end },
        { "power", "Fade & marks", function(p) self:BuildPower(p) end },
        { "combo", "Combo", function(p) self:BuildCombo(p) end },
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
