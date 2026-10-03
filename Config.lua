local _, ns = ...
local Config = {}
ns.Config = Config

local issecret = ns.issecret
local W, H = 550, 700
local ROW_H = 26

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function Button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    return b
end

local function Checkbox(parent, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    Label(cb, text, "GameFontHighlight"):SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetChecked(get())
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked())
        ns.Refresh()
    end)
    return cb
end

local function Stepper(parent, text, min, max, step, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 24)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local minus = Button(f, "-", 24)
    minus:SetPoint("LEFT", 150, 0)
    local val = Label(f, "", "GameFontHighlight")
    val:SetWidth(40)
    val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local plus = Button(f, "+", 24)
    plus:SetPoint("LEFT", val, "RIGHT", 4, 0)

    local function refresh() val:SetText(get()) end
    local function change(d)
        set(math.max(min, math.min(max, get() + d)))
        refresh()
        ns.Refresh()
    end
    minus:SetScript("OnClick", function() change(-step) end)
    plus:SetScript("OnClick", function() change(step) end)
    f:SetScript("OnShow", refresh)
    refresh()
    return f
end

local function SpellInfo(id)
    return C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id)
end

-- Plain mouse-wheel scroll list of icon + text rows; callers add their own buttons per row.
local function ScrollList(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(w, h)
    local bg = sf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w, 1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * ROW_H)))
    end)
    sf.child, sf.rows, sf.w = child, {}, w
    return sf
end

local function Fill(sf, items, setup)
    for i, item in ipairs(items) do
        local r = sf.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, sf.child)
            r:SetSize(sf.w - 8, ROW_H)
            r:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_H - 2)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT")
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.text = Label(r, "", "GameFontHighlight")
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.text:SetWidth(sf.w - 150)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            sf.rows[i] = r
        end
        setup(r, item, i)
        r:Show()
    end
    for i = #items + 1, #sf.rows do
        sf.rows[i]:Hide()
    end
    sf.child:SetHeight(math.max(1, #items * ROW_H + 4))
    local max = math.max(0, sf.child:GetHeight() - sf:GetHeight())
    if sf:GetVerticalScroll() > max then sf:SetVerticalScroll(max) end
end

-- Blizzard's modern dropdown. groups() returns { { title = "...", items = { { name = , path = } } } }.
local function Dropdown(parent, text, groups, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(380, 26)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    dd:SetWidth(210)
    dd:SetPoint("LEFT", 150, 0)
    dd:SetupMenu(function(_, root)
        local all, count = groups(), 0
        for _, group in ipairs(all) do count = count + #group.items end
        if count > 20 then root:SetScrollMode(20 * 20) end
        for _, group in ipairs(all) do
            if group.title then root:CreateTitle(group.title) end
            for _, item in ipairs(group.items) do
                root:CreateRadio(item.name, function() return get() == item.path end, function()
                    set(item.path)
                    ns.Refresh()
                end)
            end
        end
    end)
    return f
end

local function Options(...)
    local items = {}
    for i = 1, select("#", ...), 2 do
        local path, name = select(i, ...)
        items[#items + 1] = { path = path, name = name }
    end
    local groups = { { items = items } }
    return function() return groups end
end

local OUTLINES = Options("", "None", "OUTLINE", "Outline", "THICKOUTLINE", "Thick outline")
local MODES = Options("whitelist", "Whitelist: only these", "blacklist", "Blacklist: all except these")

local function ColorSwatch(parent, text, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 24)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
    sw:SetSize(40, 18)
    sw:SetPoint("LEFT", 150, 0)
    sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    sw:SetBackdropBorderColor(1, 1, 1, 0.6)
    local function refresh()
        local c = get()
        sw:SetBackdropColor(c.r, c.g, c.b, 1)
    end
    local function apply(r, g, b)
        set(r, g, b)
        refresh()
        ns.Refresh()
    end
    sw:SetScript("OnClick", function()
        local c = get()
        local r0, g0, b0 = c.r, c.g, c.b
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0,
            swatchFunc = function() apply(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() apply(r0, g0, b0) end,
        })
    end)
    refresh()
    return f
end

-- Free-text setting that applies as you type.
local function TextBox(parent, text, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(380, 26)
    Label(f, text, "GameFontHighlight"):SetPoint("LEFT", 4, 0)
    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetSize(200, 20)
    eb:SetPoint("LEFT", 156, 0)
    eb:SetAutoFocus(false)
    eb:SetText(get())
    eb:SetScript("OnShow", function(self) self:SetText(get()) end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        set(self:GetText())
        ns.Refresh()
    end)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    f.eb = eb
    return f
end

local function Placer()
    local y = 0
    return function(w, h, x)
        w:SetPoint("TOPLEFT", x or 0, y)
        y = y - h
    end
end

function Config:BuildBars(p)
    local db = ns.db.skin
    local place = Placer()

    place(Checkbox(p, "Skin the Personal Resource Display", function() return db.enabled end, function(v) db.enabled = v end), 30)
    place(Checkbox(p, "Class-coloured health bar", function() return db.classColor end, function(v) db.classColor = v end), 26)
    place(Checkbox(p, "Dark background behind bars", function() return db.background end, function(v) db.background = v end), 26)
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
    local cc = RAID_CLASS_COLORS[class]
    local function updateBar()
        bar:SetStatusBarTexture(db.texture)
        bar:SetStatusBarColor(cc.r, cc.g, cc.b)
    end
    place(Dropdown(p, "Bar texture", function() return ns.Media:List("statusbar") end,
        function() return db.texture end,
        function(v) db.texture = v; updateBar() end), 28)
    place(bar, 34, 150)
    updateBar()

    place(Stepper(p, "Border size in pixels (0 = off)", 0, 6, 1, function() return db.borderSize end, function(v) db.borderSize = v end), 28)
    place(ColorSwatch(p, "Border colour", function() return db.borderColor end,
        function(r, g, b) db.borderColor = { r = r, g = g, b = b, a = 1 } end), 40)

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
    local POWER_TYPES = Options("default", "Mana, and any other", "RAGE", "Rage", "ENERGY", "Energy")
    for _, bar in ipairs({ { "health", "Health bar text" }, { "power", "Power bar text" } }) do
        local key = bar[1]
        local function Slots()
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

-- Lists the auras currently on you, so you can whitelist without knowing IDs.
function Config:ShowPicker(kind, onAdd)
    if InCombatLockdown() then
        ns.Print("Leave combat to browse your current auras.")
        return
    end
    local pk = self.picker
    if not pk then
        pk = CreateFrame("Frame", nil, self.frame, "BasicFrameTemplateWithInset")
        pk:SetSize(320, 420)
        pk:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 4, 0)
        pk.title = Label(pk, "")
        pk.title:SetPoint("TOP", 0, -5)
        pk.list = ScrollList(pk, 296, 370)
        pk.list:SetPoint("TOPLEFT", 12, -32)
        self.picker = pk
    end
    pk.title:SetText("Your current " .. kind)

    local filter = kind == "buffs" and "HELPFUL" or "HARMFUL"
    local items = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
        if not ok or not aura then break end
        if not issecret(aura.spellId) then
            items[#items + 1] = aura
        end
    end
    Fill(pk.list, items, function(r, aura)
        r.icon:SetTexture(aura.icon)
        r.text:SetText(aura.name .. " |cff888888(" .. aura.spellId .. ")|r")
        if not r.add then
            r.add = Button(r, "Add", 44, 20)
            r.add:SetPoint("RIGHT", -2, 0)
        end
        r.add:SetScript("OnClick", function() onAdd(aura.spellId) end)
    end)
    if #items == 0 then ns.Print("You have no " .. kind .. " right now.") end
    pk:Show()
end

function Config:Build()
    local f = CreateFrame("Frame", "PersonalResourceTweaksConfig", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Label(f, "PersonalResourceTweaks"):SetPoint("TOP", 0, -5)
    tinsert(UISpecialFrames, "PersonalResourceTweaksConfig")
    self.frame = f

    local pages, tabs = {}, {}
    local function select(key)
        for k, page in pairs(pages) do page:SetShown(k == key) end
        for k, tab in pairs(tabs) do
            if k == key then tab:LockHighlight() else tab:UnlockHighlight() end
        end
        if self.picker then self.picker:Hide() end
    end
    for i, def in ipairs({ { "bars", "Bars" }, { "text", "Text" }, { "buffs", "Buffs" }, { "debuffs", "Debuffs" },
        { "power", "Fade & marks" } }) do
        local key = def[1]
        local tab = Button(f, def[2], 100)
        tab:SetPoint("TOPLEFT", 14 + (i - 1) * 104, -30)
        tab:SetScript("OnClick", function() select(key) end)
        tabs[key] = tab
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 16, -62)
        page:SetPoint("BOTTOMRIGHT", -16, 12)
        pages[key] = page
    end

    self:BuildBars(pages.bars)
    self:BuildText(pages.text)
    self:BuildAuraPage(pages.buffs, "buffs")
    self:BuildAuraPage(pages.debuffs, "debuffs")
    self:BuildPower(pages.power)
    select("bars")
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
ns.AddOptionsPanel({
    open = function()
        if not (Config.frame and Config.frame:IsShown()) then Config:Toggle() end
    end,
    commands = {
        { "/prt", "open or close the settings" },
        { "/prt debug", "report what it finds of the Personal Resource Display" },
        { "/prt fade", "say whether the display counts as idle, and why not" },
    },
})
