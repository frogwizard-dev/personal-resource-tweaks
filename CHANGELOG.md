# PersonalResourceTweaks

## 0.8.2

- Settings: a dropdown shows the current choice afresh whenever its page opens. The settings controls and window now come from FrogLib, shared with Frog Wizard's other add-ons.
- The list of auras on you (to pick one to add) leaves out ones the game hides from add-ons instead of failing on them.
- Combo points: a druid's form is checked safely when the game hides your power type.

## 0.8.1

### Fixes
- Fading when idle no longer fades your display at low health when the game hides your health: it now fades only once you're back at full health, and comes back the moment you're hit or start a fight.
- The mana regen strip now also starts after spells the game hides from add-ons, from the drop in your mana that comes with them.
- The cost marks on your power bar no longer cause an error when the game hides a spell's minimum cost.
- Bar text with more than six words now keeps updating.

### Under the hood
- Bar text templates, percentages, your class colour, pixel snapping and the click button are FrogLib's, shared with the other Frog Wizard add-ons (a class colour add-on's colour is used if you have one).

## 0.8.0

### Bar sizes
- Set the display's width and each bar's height exactly, in screen pixels, on the Bars page: health, power, and the mana bar druids get in forms (which otherwise matches the power bar). They go beyond Edit Mode's sliders, stay crisp whatever Edit Mode's "Size" is, and 0 keeps Edit Mode's own; "Use Edit Mode's sizes" puts them all back.
- Shift-click a setting's + or - to change it ten steps at a time.

### Combo points
- Rogues, and druids in cat form, get their combo points on the display: a row of flat points in the bars' texture, background and border (pixel, classic stone or Forever, with the same size, colour and thickness), lit as you build them on your target. Forever's display had no combo points of its own.
- Settings on the new Combo page: below or above the bars (the buffs move up to make room), the gap from the bars, the points' height, their width (0 shares the bars' width between them) and the space between them, all in screen pixels; class colour or your own, and optionally a different colour once you have them all.

## 0.7.0

### Border styles
- A choice of border on the Bars page: **Pixel** (as before: a crisp line, its size and colour yours), **Classic stone** (the grey stone border old frames and tooltips use) or **Forever** (a frame in the style of Forever's bars: a dark outline, a thin metallic rim and cut corners, crisp at any size, 1 to 3 pixels thick).

### Mana bar in forms
- The mana bar druids get in a form has text now, like the other bars (Text page, "For": "Mana bar in forms"); it starts as your mana bar's text. A new Bars setting decides when it shows: only in a form (the default; in caster form it just repeated your mana), always, or never.

### Mana regen
- After you spend mana, a thin strip fills along under your mana bar for the five seconds until your mana regen starts again, with a spark at its tip. It follows whichever bar shows your mana: the main one, or the form's mana bar while a druid is in a form. Turn it off or recolour it on the Fade & marks page.

### Options
- Listed with the rest of Frog Wizard's add-ons: under a "Frog Wizard" heading in the AddOn list, and in its own "Frog Wizard" section of Options > AddOns, whose page lists them all with a button to each one's settings.

## 0.6.0

### Power bar
- Text per power type: rage and energy get their own text (Text page, "For"), so the bar no longer shows a percent that only repeats the number. Your current power text carries over, without its percent.
- Ability cost marks: thin lines on the power bar at the cost of the abilities you choose (Heroic Strike, Revenge and Shield Block to start), so you can see at a glance what you can afford. Add or remove abilities by name or spell ID on the new Fade & marks page. A mark only shows for abilities you know that cost the power the bar is showing.

### Fade when idle
- The display fades out when you're out of combat at full health with your power at rest (rage empty, mana or energy full), and comes straight back with damage, power, combat or, optionally, a target. Set how faded it stays, or turn it off, on the Fade & marks page.

### Clicks
- Left-click the Personal Resource Display to target yourself, right-click it for your unit menu, as on the player frame. On by default; turn it off on the Bars page. It follows the display when you move or resize it, shows only when the display does (including "in combat only"), and steps aside in Edit Mode so you can still select the display there.

### Fixes
- The bar border is pixel-perfect: its size is now in screen pixels, so every side is equally thick at any UI scale or display size, instead of some sides coming out thicker or blurred.
- Works alongside ClassicUI Forever: its gold nameplate rim around the bars is now hidden while the skin is on, so the border you pick here shows cleanly. Turn the skin off and /reload to get ClassicUI's look back.
- Heal prediction and absorb shields show on the health bar again; the skin had been hiding them along with Blizzard's frame art.
- Fixed a "file not found" font error after EllesmereUI is turned off or removed while its font (Expressway) is chosen. The game's standard font is used until you pick another.

## 0.5.1

### Options
- Now listed in the game's Options > AddOns, with a button that opens its settings and a list of its slash commands.

### Fixes
- Fixed a "forbidden object" error that could appear when status-effect text updated in restricted content (for example in combat).
