EllesmereUI HoverCast Cheatsheet 1.0.0

A read-only companion addon for EllesmereUI Raid Frames HoverCast bindings.
It does not require Clique and does not modify or register options with EllesmereUI.
EllesmereUI and EllesmereUI Raid Frames are required dependencies.

Features
- Shows active specialization and global bindings from EllesmereUI's HoverCast system.
- Includes spells, target/menu actions, macros, items, class presets, and trinkets.
- Shows friendly and enemy spells when a key has both.
- Spell tooltips, cooldown overlays, and cooldown numbers.
- Drag rows to change their displayed order while unlocked.
- Shows a live accent-colored insertion line while a row is being reordered.
- Movable panel, lock button, and compact visual settings menu.
- Key text is always allocated enough width before spell names are clipped.
- Uses EllesmereUI's accent, font, background, and border styling when available.
- Registers safe accent/widget refresh callbacks so EllesmereUI theme changes are reapplied live.
- Uses EllesmereUI's native styled-button factory for Lock/Unlock and Visual Settings.
- Does not inject a third-party page into EllesmereUI's internal module navigation.
- Displays full modifier names (for example, Shift+M1 and Alt+M1).
- Main panel border is hidden by default and can be restored in Visual Settings.
- Border thickness/brightness sliders were removed; the optional border is a clean fixed 1px.
- Keybind color can use the EllesmereUI accent, player class color, or a custom color picker.
- EllesmereUI styling is reapplied after login so the initial key color matches later refreshes.
- Includes a custom HoverCast icon for WoW's AddOns list.
- Optional combat suppression for binding and panel-button tooltips (enabled by default).

Commands
/hccs show
/hccs hide
/hccs refresh
/hccs lock
/hccs resetorder
/hccs config
/hccs debug

Notes
- Both normal unit-frame bindings and bindings set to "Only Cast on Actual Units" are shown.
- Disabled bindings are omitted.
- If bindings are edited while this panel is open, use /hccs refresh.
