# PersonalResourceTweaks

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
