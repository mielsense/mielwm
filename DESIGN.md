# Design

How mielwm looks and moves, and where each value lives in the code. Everything mielwm draws should look like it came with macOS: Settings follows System Settings on macOS 26, and the overview's panels follow Spotlight and the volume HUD. [CONTRIBUTING.md](CONTRIBUTING.md) has the rules for changing the code.

## Where it lives

The design values are in [Sources/mielwm/Design](Sources/mielwm/Design):

- [Design.swift](Sources/mielwm/Design/Design.swift) holds the values: type, spacing, radii, fills, icon tile colours, the key cap recipe, motion and materials.
- [Components.swift](Sources/mielwm/Design/Components.swift) builds the shared views from them: `IconTile`, `PaneHeader`, `SettingsRow`, `VisualPicker`, `KeyCaps`, `StatusBadge` and `SearchField`.
- [MiniDesktop.swift](Sources/mielwm/Design/MiniDesktop.swift) draws the small desktops and windows in thumbnails and diagrams.

Use a value from `Design` instead of a literal, and a component instead of a one-off view. When nothing fits, add the value to `Design.swift` with a comment that says where it's used.

## Four surfaces, one set of values

mielwm draws on four surfaces, with three drawing technologies. They share the values in `Design`, so a change to one value reaches all of them.

| Surface | Drawn with | Code |
| --- | --- | --- |
| Settings, onboarding, About, sheets | SwiftUI, from `Design` and the components | `Sources/mielwm/*Pane.swift`, `SettingsWindow.swift`, `Onboarding.swift` |
| The overview's HUD, live and in `mielwm snapshot` | SwiftUI over the Metal canvas, `Design` values times the HUD scale. Snapshots use the solid material, since Liquid glass only draws on screen. | `Sources/mielwm/ChromeViews.swift`, `OverlayChrome.swift` |
| Notices over the desktop | AppKit drawing from `Design` values | `Sources/mielwm/NoticeDrawing.swift`, `NoticePanel.swift` |
| Window names, workspace pills and empty-workspace messages on the canvas | Core Text into Metal textures, after the lens so text never bends | `Sources/MielRender/TagPainter.swift` |

`PaletteMetrics` in [Sources/MielCore/HUD.swift](Sources/MielCore/HUD.swift) sizes the search panel and the key hints, and the camera uses the same numbers to keep the canvas clear of them.

## Type

SF Pro only, through `Font.system` and `NSFont.systemFont`. Nothing is ever all caps.

| Use | Size | Weight | Value |
| --- | ---: | --- | --- |
| A pane's name in its header | 22 pt | semibold | `Design.headerTitle` |
| A row's title, body text | 13 pt | regular | `Design.row`, `Design.rowSize` |
| Text under a row, labels under thumbnails | 11 pt | regular | `Design.secondary`, `Design.secondarySize` |

Regular is the default. Semibold marks a title or the chosen option in a `VisualPicker`. Medium appears only in `StatusBadge` and in the snapshot HUD's key caps. The overview's HUD scales every size by the HUD scale setting.

## Spacing

Spacing steps by 4 points: `Design.Space.xs` 4, `s` 8, `m` 12, `xl` 20 and `xxl` 24. A gap of 10 is written `Design.Space.s + 2`, so it's easy to find.

## Shapes

Every corner is continuous, `style: .continuous` in SwiftUI.

- `Design.Radius.group`, 12, is a grouped box of rows and the header card.
- `Design.Radius.thumbnail`, 8, is a thumbnail in a visual picker.
- `Design.Radius.control`, 6, is a button, a field or a key cap.
- `Design.Radius.tile(size)` is an icon tile's radius, 22.5% of its size.
- Inside a capsule or a panel, an inner shape's radius is the outer radius minus the padding, so the curves share a centre. The HUD and the notices follow this.

## Fills, not lines

Surfaces separate by fill, not by strokes. A grouped box, the header card and a thumbnail's backdrop use `Design.groupFill`, the system's quaternary fill. With Increase Contrast on, `Design.edge(_:)` adds the system separator colour around filled shapes.

## Colour

- Settings uses the system accent colour, so it follows System Settings > Appearance.
- The overview and the notices use the accent from the `navigator:accent` setting. The default, `auto`, takes the system accent, and falls back to mielwm orange, `#ff6b1a`. Text on the accent turns dark only when the accent is very light, by the WCAG contrast formula in `RGB.wantsDarkText`.
- Text uses the system's label colours, so it follows light and dark.
- Icon tiles use `Design.Tint`, Apple's tile colours: gray, graphite, blue, indigo, cyan, green, orange and red. They look the same in light and dark.

## Icon tiles

`IconTile` draws a white SF Symbol on a coloured tile, the way System Settings draws its icons. The tile has a soft shade from top to bottom and a faint highlight along its inner edge. At header size it also gets a soft shadow.

- Sizes are `Design.Tile.sidebar` 20, `row` 24 and `header` 48.
- The glyph fills 62% of the tile.
- An app's own icon goes in as an image, drawn as it is.
- Tiles are hidden from VoiceOver, because the row's title already says what it is.

## Key caps

Shortcuts look the same everywhere they appear: the Keyboard pane, the menu's hints, onboarding, the notices and the overview's HUD. `Design.KeyCap` holds the recipe and `KeyCaps` draws it.

- Glyphs are SF Pro 13 pt regular with 1 point of tracking. Modifiers come in the system's order, ⌃⌥⇧⌘, then the key.
- Text is the primary colour at 85% at rest, and secondary when there's no shortcut ("None").
- The cap is a continuous rectangle with radius 6, 8 points of padding across and 3 down, at least 22 points tall.
- The fill is the primary colour at 5% at rest and 9% on hover, with no stroke. On glass the fill is 12%, because 5% disappears against the backdrop.
- While recording, the cap has no fill, a 1.5 point accent ring and a 3 point accent halo at 25%, with "Type shortcut" in secondary.

## Materials

What floats over content is made of one of three materials:

- **Liquid glass**, Apple's glass on macOS 26 and later. It bends the edges of what is behind it. Notices use `NSGlassEffectView`, and SwiftUI views use `glassEffect`.
- **Frosted**, the blurred HUD material, `NSVisualEffectView` with `.hudWindow`. It's what every Mac before macOS 26 shows. Frosted panels draw their own shadow.
- **Solid**, the window background colour. With Reduce Transparency on, every panel turns solid.

The Glass style setting in Settings > Appearance, `appearance:glass` in the config file, chooses between Liquid glass and Frosted for the overview and the notices. `Look.liquid` decides what actually shows. Liquid glass needs the setting, macOS 26 and Reduce Transparency off. Anywhere else, a stored `liquid` shows as frosted. `Design.ChromeMaterial.current(_:)` in `Design/Design.swift` turns that into one of the three materials. The notices and the HUD's `chromeMaterial` both use it, so they always match.

In Settings, `glassSurface(_:in:)` draws a floating surface in Liquid glass or the regular material, following the same setting.

## Motion

Motion is short and never in the way. Controls change at once, with no animation.

- Changing pane cross-fades in 0.15 seconds, `Design.paneChange`.
- A drawing that follows a value, like the gaps diagram, uses a 0.3 second spring with no bounce, `Design.follow`.
- The camera flies between workspaces on Core's springs. The speed comes from the animation speed setting.

## Accessibility

mielwm follows the system's display settings, read from System Settings > Accessibility > Display.

- **Reduce Motion.** The camera cuts instead of flying. A pane change becomes a 0.1 second fade, and drawings that follow a value jump to it.
- **Reduce Transparency.** Every panel in the overview and every notice turns solid.
- **Increase Contrast.** Filled shapes in Settings get an edge, panels in the overview get a 1 point outline, and secondary text in the notices turns primary.

For VoiceOver:

- A pane's header reads as one heading, with its name and summary combined.
- A visual picker reads each option by name and marks the chosen one as selected.
- Every search field has a label that says what it searches.
- Decorative pieces, like icon tiles, are hidden.

## Text

The [writing rules](CONTRIBUTING.md#writing) apply to every word in the app. On top of them:

- Sentence case everywhere: window titles, buttons, menu items, row titles and headings.
- Name things the way the docs do. "Liquid glass", "stack", "workspace", "overview".
- A row's title names the setting. A line under it, when there is one, says what changes or what it needs: "Liquid glass needs macOS 26."
- A status is one or two words in its colour, in a `StatusBadge`: "Allowed", "Not allowed", "Installed".
