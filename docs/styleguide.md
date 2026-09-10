# LittleSwitch Style Guide

This guide defines shared native styling, typography, controls, and visual-asset
provenance in LittleSwitch. Follow it together with
[`product-design.md`](product-design.md), which defines each screen's layout and
interaction. Shared values belong in `SettingsLayout`.

## Native settings design

All settings destinations share quiet native surfaces, one type hierarchy, and
the same section and control rules. Desktop, Terminal, Model routing, Local
access, and Available models are peer sections, not separate design systems.

### Shared charter: A, Headings above cards

Variant A was selected on 2026-09-08 and is the guideline for every Settings
destination: General, Providers, Web Search, Monitoring, Claude, Codex and OpenCode.
Every peer section has a 17-point primary heading above its native card, including
Model routing, Desktop and Terminal. Provider and OTLP signal disclosures are
subordinate 14-point headings inside their own cards. Do not mix heading placement
between screens or leave routing rows without their section surface.

Use these shared native components rather than reproducing their styling in each
screen:

| Component | Responsibility |
| --- | --- |
| `SettingsPage` | One scrolling page, centered 640-point content, 40-point horizontal insets, 28-point section gaps. |
| `SettingsSection` / `SettingsSectionHeader` | Primary heading, optional subtitle 4 points below it, then 12 points before its card. |
| `SettingsCard` | One native `GroupBox` surface with consistent internal padding and trailing `LabeledContent` values, no nested cards or row dividers. |
| `SettingsMappingRow` | Leading route label, decorative arrow and a trailing 280-point native picker in a 38-point row. |
| `SettingsDisclosureGroupStyle` | Centered chevron and title, independent trailing controls, and 20-point detail indentation. |

Keep page actions in the existing toolbar. Reserve brand icons for navigation,
provider identities and the Web Search service choices. Peer section headings
remain text-only. Use one native surface tone and corner treatment throughout.
Ordinary settings rows have a 38-point minimum height. Multiline rows can grow.
Keep supporting copy below its owning card and 12 points between repeated cards.

Toolbar actions share `SettingsToolbarActions` on every screen. Keep 12 points
between status and actions, and add a 16-point trailing inset inside the native
toolbar item. Apply, Add Provider and their peer actions use Codex Desktop's
toolbar treatment: 13-point regular text (400), a 28-point minimum height,
8-point horizontal padding, and continuous 10-point rounded corners. Keep
4 points between the label and its 16-point icon slot. The button is transparent
at rest. A neutral highlight appears on hover (8% white in dark appearance,
8% black in light) and increases to 12% while pressed. Disabled actions use
40% opacity and do not highlight on hover. Keep the native button's full hit
area, keyboard behavior and accessible name. Apply has a leading `checkmark`,
Add Provider keeps `plus`, and Restore settings uses `arrow.uturn.backward`.
Status text and actions share `Typography.toolbarLabel`: the same 13-point
regular font. Do not use the smaller supporting-copy role for toolbar notices
or increase the action's size or weight. The status stays unboxed.
The rounded background belongs to each button's hover
state. Do not restore a shared toolbar glass surface or a permanent capsule.
Claude, Codex and OpenCode connection status uses text only, with no leading
symbol. Keep the existing connected/disconnected colors and partial connection
labels such as "Desktop connected" and "Terminal connected".

Keep the toolbar action row and every custom disclosure inside an explicit
accessibility container with `.accessibilityElement(children: .contain)`.
Each button, status, switch and input must retain its own accessible name. The section or toolbar label must not replace its children's names. Verify
the names through macOS accessibility as well as SwiftUI's native controls.

All visible menu selectors on one screen share the same width, control size,
height, and trailing edge. Size them for the longest useful selected value,
independently of which option is currently selected. Claude's Terminal default
uses the same 280-point column as its routing selectors. Codex and OpenCode
model selectors also use 280 points. Monitoring's short-value selectors use
110 points. General's Catalog symbol uses a 160-point column.
`settingsMenuPicker(width:)` applies native flexible button sizing
on macOS 26 and later so the visible control fills that width. A borderless URL
field can use the remaining row width. It is not a menu selector.

### Hierarchy and spacing

- Open Settings at 1,200 × 840 points and use that same minimum window size,
  including the titlebar. Subtract the shared titlebar height for the SwiftUI
  content minimum, and let the hosting controller propagate that minimum to
  AppKit. Do not add a competing window constraint. Keep every page centered at
  the shared content maximum.
- Clip the detail column below the titlebar, keeping scrolled text clear of
  toolbar actions and preserving the sidebar's full-height divider.
- Keep model routing above the catalog. Place "For Codex Desktop and CLI."
  directly below "Model routing", with 4 points between title and subtitle.
- Use the system font: 17 pt medium for peer section titles, 14 pt medium for
  provider names, 13 pt at weight 430 for model names, and 11.5 pt secondary text for
  descriptions and counts. Peer section titles use the primary foreground.  a different SwiftUI container must not change their hierarchy.
- Sidebar labels use 13.5 pt at weight 430, including the selected destination.
  Native selection color conveys the state without adding bold text.
  Generic sidebar SF Symbols use light-weight
  monochrome outlines, including the unfilled provider drive and `globe` for
  Web Search. Do not let selection substitute a filled symbol. Brand marks
  retain their original artwork.
- Keep the content at most 640 points wide on every Settings page, with 40-point
  horizontal insets and 28 points between peer sections.
- Keep an arrow between each route label and its native picker. Its enclosing
  card uses the same surface as Desktop and Terminal.
  Selectors retain the shared 280-point width and 38-point row minimum.
- Scroll the page as one surface. Keep supporting copy directly below its group,
  and allow it to wrap at the minimum window size.

### General font weight rule

The baseline for application body text, labels, values and ordinary actions is
**430**, matching Codex Desktop's bundled electron CSS
(`--vscode-font-weight: 430`). Keep **500** for structural headings only.
Toolbar text is a deliberate lighter role: **13 pt regular (400)** for both
actions and status, as selected during visual feedback on 2026-09-09.
Do not make Apply, Add Provider, a selected navigation item, or an ordinary
field label medium or semibold merely because it is actionable or selected.
Use size, position, spacing and semantic foregrounds to express hierarchy.
Native system menus and SF Symbols retain their platform-specific font roles.

`SettingsLayout.Typography` applies 430 through the system font descriptor's
public OpenType `wght` variation axis. This keeps San Francisco and its native
optical sizing, without bundling a font or approximating 430 with Light or
Medium. Reuse the shared roles throughout Settings. Toolbar status uses
`toolbarLabel`, while in-page descriptions use `supporting`.
Symbol weight is independent: navigation and toolbar outlines remain
light, while brand artwork is unchanged.

The toolbar surface reference is Codex's Share action, which uses its `ghost`
color and `toolbar` size. Its rounded surface in the reference screenshot is a
hover state. Codex Desktop's bundled CSS sets the default body size to 14 px
and its compact `text-sm` size to 13 px. LittleSwitch uses that compact scale
for all toolbar text, with native regular weight to keep status and actions
visually balanced. These values follow the reference client’s bundled
CSS and component definitions on 2026-09-09.

### Provider groups and names

- Use one `SettingsCard` per provider, with 12 points between
  groups. Never add a card, border, gradient, or shadow
  around each model.
- Start providers collapsed. Retain their expansion while navigating settings
  during the current application session.
- Give the header a 34-point minimum height and each model a 30-point minimum.
  An explicit `DisclosureGroupStyle` centers the chevron and provider name in
  one native button. The selection switch is a separate control on the right.
- Indent model content by 20 points from the group's content edge. Keep all
  switches aligned and omit horizontal separators between models.
- Give plain lowercase provider labels an initial capital in presentation:
  `example` appears as **Example**. Preserve existing mixed case, acronyms,
  punctuation, and technical names, such as **OpenAI**, **oMLX**, and **z.ai**.
  Never apply title case to every word or change stored names, IDs, routing
  values, URLs, or model identifiers such as `example/large`.
- Put the enabled count next to the group switch. Keep "Default" before the
  protected model's disabled switch. Partial selection remains explicit through
  its count. A group action keeps the default model available.

### Catalog navigation

- The Available models header contains its title and the enabled count only.
  Do not include Find, a search field, or a Command-F search shortcut.
- Browse the complete catalog through provider disclosures. Group switches
  act on all models from that provider and preserve the default model.
- Keep headings and counts readable when space narrows. Stack that text when
  necessary.

### Monitoring sections and disclosures

- Apply the same section typography, 640-point maximum content width,
  40-point horizontal insets, and 28-point section spacing to Monitoring.
- Keep Local access in one `SettingsCard`, with the host in its
  section heading. Use compact rows without separators, with Copy URL and a
  small native switch on the right.
- Give Metrics and Logs their own `SettingsCard`, separated by 12
  points beneath the OTLP export section heading. Reuse
  `SettingsDisclosureGroupStyle` for a centered chevron and 14-point medium
  title, a 34-point header, and an independent status and switch on the right.
- Indent expanded fields by 20 points. Keep Receiver URL and its field on one
  row. Use a plain native text field without a separate background or border,
  matching the provider Connection form, with its text aligned right. Preserve
  native editing, selection, keyboard focus, and the accessible field name.
  Let the borderless URL use the remaining row width so long addresses stay
  readable.
- Give token fields, authentication, export interval, and log level one shared
  110-point control column on the right. Their visible controls must
  fill the column, regardless of the selected text. Use
  `monitoringControlColumn()` to apply native flexible button sizing on macOS
  26 and later, retaining the native frame behavior on earlier systems. Use
  spacing instead of horizontal rules between settings.
- Present the export interval as a finite menu: 5, 10, 15, or 30 seconds, and
  1, 2, or 5 minutes. Display compact units, such as "15 s" and "1 min", and
  keep the full duration available to accessibility. Keep an existing
  non-preset value visible as the current
  selection until the person chooses a preset. Never round or overwrite it
  merely by opening settings.
- Preserve Monitoring's expansion behavior: enabled destinations open,
  disabled destinations start folded, and an inactive destination can be
  opened for preparation. Keep delivery status visible when fields are folded.
  Subordinate delivery details use the same disclosure style with a compact
  24-point header and supporting typography.
- Keep supporting copy beneath its section and Test export beside Apply in
  the persistent toolbar.

### Materials and references

Use the shared `SettingsLayout.Palette` for the Settings window background.
In dark appearance, the sidebar is anthracite `#212121` and the detail pane is
near-black `#181818`. Continue each column's background through the transparent
titlebar. Only the background extends there, never scrolling content. Native
`GroupBox` cards remain slightly lighter than the detail pane.
These neutral values follow the Codex Desktop reference palette on 2026-09-08: `gray-800` is `#212121`, and its main
`color-background-surface` uses `gray-900`, `#181818`. Reuse the palette values,
not Codex's web layout or translucency implementation.
In light appearance, retain native `controlBackgroundColor` for the sidebar and
`textBackgroundColor` for the detail pane. Resolve colors dynamically when the
system appearance changes. Never force a dark appearance.

Use semantic foregrounds and native group surfaces in both appearances.
Keep the system accent for selection and meaningful controls. Material effects
belong to the navigation and control layers. Do not put glass behind every row.
Use native `Picker`, `Toggle`, `Button`, and text inputs, retaining keyboard
behavior and accessibility labels.

Apple's [SwiftUI design guidance](https://developer.apple.com/videos/play/wwdc2025/323/),
[native button sizing](https://developer.apple.com/documentation/swiftui/view/buttonsizing(_:)),
[search guidance](https://developer.apple.com/documentation/swiftui/adding-a-search-interface-to-your-app),
and [AppKit material guidance](https://developer.apple.com/videos/play/wwdc2025/310/)
are the platform references. [Luminare](https://github.com/MrKai77/Luminare) is a
visual reference for cohesive macOS components, not a LittleSwitch dependency.
Introduce a library only when a specific native component gap justifies it.

## Icon source hierarchy

Choose an icon from the first applicable source:

1. **SF Symbols for generic interface meaning.** Actions, status, navigation,
   files, networking, terminals, and settings use a semantic SF Symbol. Do not
   replace a standard platform symbol with vendor artwork.
2. **Runtime application icons for installed apps.** When the UI identifies a
   specific application installed on the Mac, load its icon at runtime through
   AppKit. A runtime icon is not copied into the LittleSwitch bundle.
3. **LobeHub Icons for bundled AI brands.** When a recognizable provider,
   model, or AI product mark must ship in the bundle, use
   [LobeHub Icons](https://lobehub.com/icons) as the canonical source. Do not copy
   the equivalent asset from another application's repository.

Canonical catalog pages include:

- [Anthropic](https://lobehub.com/icons/anthropic)
- [Claude](https://lobehub.com/icons/claude)
- [Claude Code](https://lobehub.com/icons/claudecode)
- [Codex](https://lobehub.com/icons/codex)
- [OpenAI](https://lobehub.com/icons/openai)
- [Ollama](https://lobehub.com/icons/ollama)
- [OpenCode](https://lobehub.com/icons/opencode)
- [Firecrawl](https://lobehub.com/icons/firecrawl)
- [Tavily](https://lobehub.com/icons/tavily)

Search the same catalog before adding any future provider or application mark.

The Claude family navigation uses LobeHub's Claude color mark, while the Claude
Code status menu uses its Claude Code color mark. Both bundled
translations are pinned to commit `4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75`.
Codex uses LobeHub's OpenAI mono knot from the same pinned commit, shared by
settings navigation and the status menu. Its AppKit template image follows the
owning control's foreground in light, dark and selected states.
The OpenCode settings section and status menu use LobeHub's OpenCode mono mark
with the current semantic foreground color, pinned to the same commit. The
web-search provider is selected with square native buttons, each with a large
LobeHub monochrome template mark and its name below. Its connection heading uses the same
text-only treatment as other section headings. Ollama and z.ai provider rows use LobeHub mono
marks from the same pinned commit, rendered as AppKit template images. Unknown
endpoints use a generic SF Symbol.

## Native implementation

LittleSwitch remains a native Swift application. Do not add LobeHub's React,
React Native, or JavaScript packages. Translate only the required SVG geometry
into a small native SwiftUI view or include a focused static asset when a native
translation would reduce fidelity.

For every bundled LobeHub mark:

- preserve the upstream view box, geometry, fill rule, and official color.
- use the monochrome variant only when the surrounding native control requires a
  semantic tint.
- keep decorative geometry hidden from accessibility and give the owning row or
  control a useful accessibility label.
- record the LobeHub catalog URL, repository source path, and pinned commit in a
  source comment.
- keep the implementation isolated in a single-purpose file instead of embedding
  paths in a general-purpose view.

Do not redraw a vendor mark from memory, use a screenshot as source material, or
mix geometry from multiple icon collections.

## LittleSwitch application icon

The LittleSwitch application icon is an original light monochrome asset. Its
canonical editable source is `packaging/AppIcon.svg`. The native build derives
`AppIcon.icns` through `tools/generate-app-icon.sh` instead of storing a vendor
mark or a hand-edited raster as the source of truth.

The mark uses two vertically offset rounded modules. Each contains one circular
indicator and one opposing vertical arrow. Keep the modules independent with no
connector between them. Do not add provider marks, product initials, text, or
vendor colors.

The menu-bar mark carries the application icon's two capsule modules at a
deliberately lighter density. Its native source is
`Sources/LittleSwitchUI/MenuBar/StatusItemIcon.swift`: an 18-point canvas holding two
7.5 x 15-point capsules, offset with each indicator at its own end, drawn with a
1-point stroke. One module is filled with its indicator knocked out of it, the
other is outlined around a filled indicator. Together they fill 17 of the
canvas's 18 points, so the mark holds its rank beside the system's own menu-bar
symbols, and every edge falls on a half point so the glyph rasterizes without a
soft pixel at 2x. Do not add a background, text, provider mark, connector, or the
application icon's arrows: none of them survive at 18 points.

The mark carries exactly two states, and they report one thing: whether any
application currently routes through LittleSwitch. Nothing moves between them,
the fill travels. `idle` fills the left module, `active` fills the right one, so
the mark's mass throws over the way a switch does. Request counts, pending
changes, and errors belong to the menu, never to the glyph.

The renderer must return an AppKit template image so macOS supplies the foreground
treatment for the current menu-bar surface and highlighted state. The owning
status-item button exposes `LittleSwitch` once through its accessibility label and
tooltip. The decorative paths do not expose separate accessibility elements.

## Native select boxes

All dropdown interactions use SwiftUI `Picker` with
`.settingsMenuPicker(width:)`. The modifier owns `.pickerStyle(.menu)` and the
regular control size so select boxes keep the same native height and interaction
throughout the app.

Width is selected once per screen: model selectors use the shared 280-point
mapping width, including Claude's Terminal default, Monitoring uses 110
points, and General uses 160 points. Apply the width to the control itself, retaining the native leading
label through `LabeledContent` where needed. The visible background fills that
width regardless of the selected option. `LabeledContent` and the shared routing
grid retain native control heights and label alignment.
Segmented controls remain compact because they represent tabs or mode switches,
not dropdown/select-box interactions.

Keep every picker's accessible name even when its visual label is hidden. Do not
replace native pickers with custom drawing or gesture-only controls.

## Web Search provider choices

Use the approved variant 2: a centered row of square native SwiftUI `Button`
controls inside the shared `SettingsCard`. The “Search provider” heading stays
above the card, following charter A. Keep None, Firecrawl, Tavily and Brave in
that order, with exactly one selected choice.

- Squares are 50 × 50 points with a 10-point corner radius. Marks are 24 points.
  This reduces the approved icon treatment by approximately 30% while keeping
  names at their normal reading size.
- Each choice occupies 96 points, with 24 points between choices. The row has
  8-point vertical insets.
- Names sit 8 points below their squares, using the shared 13-point row label.
- The selected square uses the system accent, a white mark and a small white
  checkmark in its upper trailing corner. Its name uses the primary foreground.
- Other squares use a subtle semantic fill, primary marks and secondary names.
  Keep the bundled mark geometry intact. None uses the `nosign` SF Symbol.
- The square and name form one clickable button. Preserve native keyboard focus,
  Space activation, left/right navigation, disabled states and selected
  accessibility traits. Hide decorative marks from accessibility.

Dimensions live in `SettingsLayout.SearchProvider`. The connection heading names
the selected service using the shared section typography. Selection continues to
edit the draft. Apply remains the commit action.

## Licensing and trademarks

[LobeHub Icons](https://github.com/lobehub/lobe-icons) is MIT licensed. Any
bundled translation must retain the complete LobeHub copyright and MIT permission
notice in `THIRD_PARTY_NOTICES.md`. That file ships in the application bundle and
is the authoritative notice for manually translated LobeHub assets.

The MIT license covers LobeHub's icon implementation. It does not transfer
ownership of vendor names or trademarks. Use marks only to identify compatible
products and providers. Do not imply endorsement, alter a mark into LittleSwitch
branding, or use a vendor mark as the application icon.

## Review checklist

Before accepting a new or changed icon, verify that:

- the source follows the hierarchy above.
- bundled brand geometry matches the pinned LobeHub source.
- the source comment and `THIRD_PARTY_NOTICES.md` remain complete.
- the app bundle contains the notice but no JavaScript icon dependency.
- light, dark, increased-contrast, small-sidebar, and menu-bar presentations stay
  legible.
- accessibility exposes the product or action once, without announcing decorative
  path elements.
- repository tests cover provenance and packaging.
