# LittleSwitch Product Design Guide

LittleSwitch should feel like a focused macOS utility: compact, calm, precise,
and native. It is a working configuration surface, built with native SwiftUI.

## Sources of Truth

Use these references in order:

1. Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/),
   especially [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/),
   [Settings](https://developer.apple.com/design/human-interface-guidelines/settings),
   [Typography](https://developer.apple.com/design/human-interface-guidelines/typography),
   [Color](https://developer.apple.com/design/human-interface-guidelines/color),
   [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols),
   and [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
2. Platform SwiftUI behavior. Prefer `NavigationSplitView`, `List`, `Form`,
   `Section`, `LabeledContent`, `ContentUnavailableView`, standard controls, and
   semantic styles before introducing a custom primitive.
3. This guide and the values centralized in `SettingsLayout`.
4. [`styleguide.md`](styleguide.md) for the shared Settings charter, native
   controls, branded icons, asset provenance and license treatment.
5. Existing open-source macOS utilities such as
   [LinearMouse](https://github.com/linearmouse/linearmouse) and
   [Ice](https://github.com/jordanbaird/Ice) as implementation references only.
   Do not copy their code, assets, or product identity.

When a source conflicts with a one-off mockup, prefer the native platform behavior.

## Product Character

- **Compact.** Fit related decisions in one view while preserving
  readable labels, click targets, and clear groups.
- **Quiet hierarchy.** Structure comes from alignment, spacing, typography, and
  semantic surfaces. Avoid stacked borders, heavy shadows, gradients, and nested
  cards.
- **Operational clarity.** Show current state, pending state, progress, and failure
  close to the control that owns them.
- **Native by default.** Respect system accent, contrast, sidebar size, keyboard
  conventions, and accessibility settings. Application surfaces follow the
  system appearance and use semantic colors in both light and dark modes.
- **One obvious action.** A page may have one prominent primary action. Secondary
  actions stay bordered, menu-based, or contextual. Destructive actions are never
  visually dominant.

## Information Architecture

The settings sidebar orders destinations by responsibility:

- **General:** application startup, model naming and software updates.
- **Backends:** Providers, Web Search and Monitoring.
- **Apps:** Claude, Codex, and OpenCode.
The sidebar has seven destinations and a static LittleSwitch icon/name above them.
Use the existing application icon at 34 pt, never a project switcher. A small gap
separates settings from apps. No group headings or decorative panels. Generic
icons are `slider.horizontal.3`, `externaldrive.connected.to.line.below`, and
`globe`, followed by `waveform.path.ecg` for Monitoring. Use light-weight
monochrome outlines, with no automatic filled variant on selection.
Native List selection owns accent and focus styling.

Keep the sidebar stable across launches and restore the most recently useful
destination when practical. Use the native sidebar list style so selection is
the inset, rounded shape macOS draws everywhere else, and keep the list's own
background hidden so the style contributes its selection without its material. Its structure comes from the full-height split-view
divider, which continues through the titlebar, not
an enclosing rounded panel or ornamental border. Use the focused SwiftUI settings
split so the sidebar stays fused to the window edge instead of adopting the
floating `NavigationSplitView` treatment. Keep exactly one native navigation
toolbar item for showing and hiding it. Hide its shared Liquid Glass background
on macOS 26 and later, keep its button borderless on every supported macOS
version, and align it toward the sidebar divider. Give it explicit `Show sidebar`
and `Hide sidebar` accessibility labels. Hide row and section separators inside
the sidebar. Ordering, icons, and selection provide its structure.

Do not repeat the selected sidebar destination as a visible window title. Keep
the window title as accessibility metadata and hide its toolbar presentation.
Keep connection or pending state beside Apply in one trailing
group, with its full text always visible even in an icon-only toolbar. Pending
changes replace connection text in that group to keep the minimum size readable.
Connection status in Claude, Codex and OpenCode is text-only: omit its leading
icon, including for connected, disconnected and partial connection states.
Use a native flexible toolbar space before this group so hiding the title does
not move the actions next to the sidebar toggle.
Clip the detail column to its content bounds so scrolling rows stay below the
titlebar. Keep the sidebar divider's full-height extension independent of this
clip.
Apply and Add Provider share Codex Desktop's toolbar treatment: native SwiftUI
buttons with 13-point regular text (400), a 28-point minimum height, 8-point
horizontal padding, and 10-point continuous rounded corners. Keep a 16-point
trailing inset on the actions group. Use a transparent resting surface and a
neutral hover/pressed highlight, with subdued text and explicit disabled opacity.
Apply shows a leading `checkmark`. Add Provider keeps its `plus` icon.
Use the same 13-point regular `toolbarLabel` font for actions, pending notices,
and connection status. Keep the status unboxed and each action's hit area
independent of its hover surface. Do not add a shared glass background or accent fill.
Command-S applies the current page. Return remains the default
commit shortcut inside a provider sheet.

Every Settings destination uses `SettingsPage`, with primary section headings
above native `SettingsCard` group surfaces. Variant A in
[`styleguide.md`](styleguide.md#shared-charter-a--headings-above-cards) is the
shared guideline. Keep content centered at 640 points, with 40-point horizontal
insets and 28 points between sections. Keep toolbar actions persistent. Native
grouped Forms remain appropriate inside the separate provider editing sheet.

Web Search presents None, Firecrawl, Tavily, Brave and Exa as five square native
SwiftUI buttons with one active choice. Each 50-point square contains a centered
24-point LobeHub mono mark. None uses `nosign`. Names sit below the squares,
with an 8-point gap. The selected square uses the system accent, a white mark
and a small checkmark. Keep the row centered in the shared Settings card, with
equal 96-point choice widths and 24-point gaps. Preserve native keyboard focus,
arrow navigation, disabled states and accessible selection.
Selecting a different service clears a typed
credential and clamps its result limit. Selecting the active service preserves
typing. The API key field uses an explicit placeholder, hidden duplicate label
and leading text alignment, so “Leave blank to keep the saved key” stays inside
the field. Secure text and its accessible API key label remain native.
The connection section contains only the API key field. Omit the disclosure
and fixed endpoint details that offer no configurable choice.

Monitoring uses one scrolling page with two sections: Local access and OTLP
export. Follow the shared settings scale: 17-point medium section headings,
640-point content maximum, 40-point horizontal insets, and 28 points between
sections. Local access has one native GroupBox with no row separators. Show the
host once in the heading, then one compact row per signal with its path, a Copy
URL menu and a small switch. The menu offers HTTP and, when actually available,
HTTPS. It copies the complete URL. Copy availability follows applied settings, so pending
activation does not suggest that an endpoint is already available.

Each OTLP signal owns a native GroupBox, with 12 points between groups. Reuse
SettingsDisclosureGroupStyle for its disclosure: center the chevron and
14-point medium title in one button, with a separate status and small switch on
the right. Use a 34-point header, 20-point content indent, and spacing instead
of separators inside each group. Align authentication, interval, and level
controls on the right. Keep supporting copy directly below its section.
Inactive destinations start collapsed. Enabling opens their settings. Disabling
folds them. Users can also open an inactive destination to prepare it. Folding
preserves entered values and status polling must preserve expansion and keyboard
focus. Put Receiver URL and its field on the same row and right-align its text.
Use a plain native field with no separate background or border, matching the
provider Connection form. Let the URL use the remaining row width so it stays
readable. Token fields, authentication, export interval, and log level share
one 110-point control column on the right. Native pickers
fill that width independently of their selected label. Offer export intervals
of 5, 10, 15, or 30 seconds, and 1, 2, or 5 minutes, displaying compact labels
such as "15 s" and "1 min". Preserve any existing
non-preset interval as the current selection until another value is chosen.
A blank secure field keeps the saved token. Removal is explicit. No saved token
enters a draft. Non-secret changes survive navigation, while typed tokens clear
when leaving the pane.

Apply and Command-S persist the whole page. Keep Test export beside Apply in the
persistent toolbar. It uses only applied settings and is disabled during edits
or another operation. Show accepted time and controlled errors beside their
signal, including when its configuration is folded. Put queue size, bytes, drops
and retry details in a subordinate disclosure. Receiver acceptance does not claim
that a backend query found the data.

General contains an opt-in native switch labelled `Launch at login` with
the supporting copy “Open LittleSwitch automatically when you log in to your
Mac.” The system-reported Login Item status is the source of truth. A login launch
creates only the menu-bar application and leaves Settings hidden. When macOS
requires approval, show `Open Login Items…` without pretending the switch is
enabled.

One vocabulary covers saving across the window. `Apply` is the word for every
change that reaches disk or an external application, in Claude, Codex, OpenCode
and Web Search alike.
modal form convention owns it. An Apply control is enabled only when a draft
actually differs from what is stored, so the button itself reports whether
anything is waiting, and a section holding a draft shows the single pending
notice, `Changes are ready to apply.`, beside Apply in the fixed toolbar.

Drafts live in the coordinator, not in a pane's own state: leaving a section
must not decide whether typed settings survive. A typed credential is the one
exception and is deliberately not restored, because the field already states
that blank keeps the saved key. Script authentication follows the same rule
for its script text, and adds a `Refresh every` picker for the scheduled
re-run period. The provider row names the last script failure in orange until
a later run or save succeeds. Every path that would discard drafts, a
disconnect, a restore, quitting the app, names what is about to be lost before
asking, and the status menu marks each application that holds unapplied changes,
since that menu is where a disconnect is triggered.

General owns settings that affect the whole gateway. The gateway is loopback-only
at `127.0.0.1:11436` by design: the TLS identity's SAN pins localhost and
127.0.0.1 under the private authority, so it cannot vouch for a LAN hostname
and no network-exposure control exists.

General groups Startup, Model indicator and Software updates in shared sections,
each with its heading above one native card.
Catalog symbol uses the short explanation “Mark routed models in Claude's model
picker.” and a live `Opus ↦` preview. It is cosmetic and applies immediately.
The native menu retains None, Swap, Equilibrium, Routed and Maps to.

Providers uses stable UUID rows with the provider mark, name and endpoint,
followed by aligned status and model-count columns. Known endpoints use local
Ollama/z.ai template marks. Unknown providers use `server.rack`. Never infer a
brand from the user-editable provider name. The row opens Edit and a visible
ellipsis Menu offers Edit, Duplicate, Refresh Models and Delete. Deletion names
the provider and has Cancel plus a destructive Delete Provider action.

Duplicate opens a draft with a fresh UUID and the first available copy name,
compared without case or surrounding whitespace. Its manual key is privately
copied through SecretStore to an independent identity on Save. No saved key
enters the visible draft. Configuration is copied, runtime status is rediscovered.
Providers settings focus on provider configuration. Request activity is available
in the status menu. Capture and usage history remain independent of settings. There is no Logs destination.

The provider editor is a native grouped form with Connection, Credentials and
Capacity, then an Advanced disclosure preserving optional protocol and context
overrides. Add uses one native preset menu (local servers first). Edit and
Duplicate preserve their source configuration without the preset control.
Cancel, Test Connection and Save remain fixed below the scrolling form. Save
requires a successful test of current values, and failures preserve the draft.

The provider editor owns the configurable `Parallel requests` value. Render it
as a native Stepper in the bounded range supported by the domain and keep the
supporting copy “Shared by every model and app using this provider.” A provider
limit is one shared capacity pool, not a model-specific or application-specific
setting.

Claude uses one destination with three sections: shared model routing, Claude
Desktop settings, and Claude Code settings. Keep shared mappings in one place. The two application sections only expose behavior that belongs to that
application. Use one page-level `Apply` action beside integration status for both
integrations. Do not repeat application-level apply controls or passive
connection badges. All mapping and default-model selectors share one width and
trailing edge.

Inside the Claude destination only, the two product-card headings are `Desktop`
and `Terminal`. Keep the full product names in global menus, confirmations,
errors, status messages, accessibility descriptions, and technical
documentation.

Codex settings use the same `Model routing` grid as Claude. `Default model`
and `Approval review model` each have a leading label, an arrow and a trailing
280 pt menu, with matching 38 pt minimum row heights and column alignment.
`Same as default` follows the task default. An explicit reviewer can use any
discovered model independently of task exposure. Explain its purpose with
“Reviews requests for permissions outside the sandbox.” An unavailable explicit
reviewer remains selected, carries an explanatory warning, and disables Apply
until the user chooses an available model. Connected edits use the existing
coordinator draft and page-level Apply action.

Codex uses one destination for its shared OpenAI model catalog. Keep exactly one
exposed-model list there. OpenCode is its own destination beneath Codex: it reads
that same catalog but writes its own user-level file, so it keeps an independent
default, connection state, and transaction action, and it says so rather than
borrowing Codex's pane. When the shared catalog is pending, the OpenCode
destination directs the user to apply Codex first. Project-level OpenCode configuration may
override the global default, and all OpenCode process copy refers only to newly
started terminal sessions.

## Layout System

The code in `Sources/LittleSwitchUI/Components/Settings/SettingsLayout.swift` is the executable source
of truth for dimensions. New work should use these values instead of scattering
near-duplicates.

| Element | Standard |
| --- | ---: |
| Window, including titlebar | 1,200 × 840 pt |
| Minimum window, including titlebar | 1,200 × 840 pt |
| Sidebar | 180 pt |
| Sidebar row | 30 pt min, 4 pt extra leading inset |
| Standard detail content | 640 pt max |
| Outer detail padding | 24 pt |
| Section-to-section spacing | 18 pt |
| Card horizontal inset | 14 pt |
| Dense control row | Native intrinsic height |
| Row with supporting text | Native intrinsic height |
| Card corner radius | 10 pt |
| Standard mapping control | 280 pt |
| Mapping row | 38 pt min |

In the Claude and Codex menu tabs, Apply uses a compact keyboard-key treatment:
a 33 × 27 pt SwiftUI button with the Return symbol, a 6 pt corner radius, a fine
border, and shallow relief. Use semantic system colors and dim the disabled
state. Its accessible label remains `Apply changes`, with the tooltip
`Apply changes (Return)`. Return invokes the same action as a click, only while
the menu is open and the current tab can apply. Busy and unchanged states keep
their existing availability rules.

The status menu is 320 pt wide. Its shared 40 pt header contains three quiet
segments, Overview, Claude, and Codex, followed by a 28 pt gear. Use a neutral
selection fill and medium label weight. Reserve accent for focus and meaningful
status. Do not put a separator under the header.

The gear closes the tracking menu and opens Settings directly, preserving the
selected tab. Every tab ends with the same native footer: About LittleSwitch,
Check for Updates, then Quit LittleSwitch. Separate the footer from the tab's
content, and keep its three commands uninterrupted without a separator before
Quit. Settings has no visible footer row. Command-Comma remains available through
a hidden native command, alongside Command-Q for Quit. Hidden client content
must never handle Return.

Overview contains four uninterrupted 40 pt application rows with 20 pt brand
icon frames, 12 pt medium names, and 11 pt supporting copy on a second line.
Preserve each bundled mark's original colors, including Claude's orange.
Use native mini switches and 9 pt between row elements. They are Claude Desktop,
Claude Code, Codex, and OpenCode. Add 8 pt of space above and below the complete
application block and 4 pt between rows. Follow them with the display-only gateway
dashboard. Its first line shows only Running and Pending totals, with monospaced
digits, inside a 32 pt neutral rounded band. Put a native section separator
between the applications and this band. Its two equal-width cells contain small
activity and clock indicators, trailing counts, and one vertical divider. Keep
space stable for four digits and subdue zeros. Running animates only while work is
active, with a static accent symbol under Reduce Motion. The band remains
display-only, without capacity or provider diagnostics.

Overview puts the thirty-day token chart above the metrics. Its caption reads
Token history and 30 days at rest, above a 24 pt medium token total and a 92 pt bar
area with three date labels. The total and all six metrics cover the same plotted
period. Inspecting a day replaces them together. Below the graph, use two rows
of three equal-width metric cells. Align the first column to the graph's left
edge and the last column to its right edge, with the middle column centered.
Do not inset the metric content from those outer edges. The order is
Input tokens, Cached tokens, Output tokens, then Requests, Errors, Web searches.
Errors show only their percentage. Zero requests produce `0%`. Request values
have no unit and zero searches stay `0`. Token cells use a neutral `K/M/B` suffix,
with more precision in the large graph total. Input estimates retain the visible
"(est.)" suffix. Omit Top model, Top client, Latency and any Details disclosure.

Empty days have no fabricated bar. The baseline and geometry remain stable.
Today and the inspected day use accent, while older bars use semantic neutral
contrast. The chart supports accessibility increment/decrement and an action to
return to the thirty-day aggregate. Claude and Codex share this chart treatment:
the 24 pt total, 92 pt bar area, date labels, hover, and accessible day selection.
Shared layout values also size the native hosting frames.

The Claude and Codex tabs start with the token chart, then the same six metrics
and three-column grid as Overview, filtered to the tab's wire client. The headline
and all six metrics cover the same plotted thirty days or the inspected day.
Align the first and last columns with the graph edges. Do not repeat daily totals
in detail rows. Keep per-day chart values in the headline and accessibility value.

Preserve the existing per-client token breakdown and record failures and web
searches for every attributed request, including failures without token usage.
Old history may not contain per-client error/search counters. Show an em dash
with accessible unavailable copy when attribution cannot be established. Never
present an unknown count as zero. A global zero or a day wholly attributed to one
client can establish an exact historical count. A later request must not make a
partially recorded historical day appear complete.

Below the statistics, add 16 pt of space, a native divider, and a quiet Settings
heading. Settings use native Grid columns for the route label, a flexible arrow
column, and a 170 pt model stepper. The Grid measures the widest route label so
every arrow is centered in the remaining space before the selector. Mapping rows
are 40 pt with 4 pt between them. Labels are 12 pt medium and selectors are 28 pt
tall, with full identifiers in help and accessible Previous/Next labels. Use 12 pt
horizontal padding and 8 pt above and below the tab. Keep Apply and its Return key
in the action row beneath the settings.

Codex shows Default model and Auto-review. The review selector includes Same as
default and every configured model, including models not exposed to Codex. It
uses the same coordinator draft and Apply behavior as Settings. Keep an
unavailable explicit choice visible, disable Apply, and let the user select an
available reviewer or Same as default. Disable selection while busy or while the
model catalog is empty.

The gateway activity row remains actionless, labelled Gateway activity with help
Gateway requests and usage. Starting and unavailable states retain explicit
lifecycle copy. Usage history remains in the existing thirty-day SQLite store. Per-client insight counters extend that history without changing request routing
or retention.

Claude Desktop and Codex summarize configured custom models rather than session
traffic. Claude Desktop counts distinct valid provider/model targets across its
routes. Codex counts models exposed in its picker. Use singular copy for one model.

Use an 8-point rhythm for new spacing, with 2–6-point optical adjustments only
inside compact text or icon groups. Align labels on a common leading edge and
controls on a common trailing edge. Native `LabeledContent` owns ordinary label/control
alignment. The route Grid uses `SettingsLayout.mappingControlWidth` for a stable
picker column.

A set of preferences groups one concept rather than creating a card per row.
Let native controls and supporting copy determine row height. Section heading
placement, surface, and disclosure treatment follow variant A across
destinations, as specified in
[`styleguide.md`](styleguide.md#shared-charter-a--headings-above-cards).
Place every peer heading above its card, including Model routing, Desktop
and Terminal. Keep an arrow between each route and the model it resolves to,
and omit horizontal rules between subordinate rows. Resizing creates useful
margins rather than stretching form controls across the window. All selectors
on a screen share one visible width, including Claude's Terminal default.

Codex places "For Codex Desktop and CLI." directly below "Model routing" as
the section subtitle. Its routing and catalog headings use 17 pt medium text,
with 28 points between sections, a 640-point content maximum and 40-point
horizontal insets. The whole page scrolls together.

The catalog uses one native GroupBox per provider, separated by 12 points.
Groups start collapsed and retain their expansion across settings navigation
for the application session. Show an enabled count beside the catalog title.
Do not include a search field, Find action, or Command-F catalog shortcut.
The complete catalog is browsed through its provider disclosures.

Provider and model names align to the leading edge, with small native switches
aligned on the right. Provider names use 14 pt medium text above 13 pt model
names at weight 430. Plain lowercase names get an initial capital for display, while
mixed case, acronyms, punctuation and stored identifiers remain untouched.
Their 34 pt minimum header rows align the disclosure chevron, name and switch
on the same vertical center using an explicit `DisclosureGroupStyle`. The
chevron and provider name form one native button, separate from the selection
switch. Keep model rows at least 30 pt high, inset 20 points from the group's
content edge and free of horizontal separators. Provider counts sit
beside their switch. The switch is on when all listed models are enabled, and
the count communicates partial selection. Enabling a partial group enables all
listed models. Group actions apply atomically to all models in the provider and
keep the current default enabled. Place the Default label before its disabled
model switch. The shared visual rules are recorded in
[`styleguide.md`](styleguide.md#native-settings-design). OpenCode names the shared
catalog and links to Manage in Codex. Its pending notice appears once, with any
prerequisite shown in place.

When text or localization does not fit horizontally, adapt the composition with
`ViewThatFits`, a stacked row, or multiline supporting copy. Do not truncate
instructions that the user needs to complete a task.

## Typography

- Use the San Francisco system font through semantic SwiftUI styles whenever
  possible. Do not bundle or imitate a system font.
- The settings window has one scale, centralized in `SettingsLayout.Typography`.
  Do not write a size or a weight inline. Add a role there instead.
- The general text weight is 430, matching Codex Desktop. Row labels and model
  names use that weight at 13 pt. Ordinary actions and selected navigation
  items also use 430. Provider and disclosure titles are 14 pt medium (500).
  Reserve 500 for structural headings. Semibold has no role in a settings pane.
- Toolbar actions and status share 13 pt regular (400), following Codex's compact
  text scale. Keep the status as readable as Apply without increasing its weight.
- Supporting copy is 11.5 pt `.secondary`. Machine-readable values are 11.5 pt
  monospaced `.secondary`, the same step as the copy they sit beside.
- Peer section headings use sentence case, 17 pt medium and the primary
  foreground above their cards. The provider editing sheet retains native Form
  headers. A different container must not change a Settings section's hierarchy.
- The sidebar is 13.5 pt at weight 430 throughout. Native selection color
  reports the selected destination without increasing its text weight.
- Do not use uppercase for sentences, actions, or form labels.
- Use `.headline`, `.callout`, `.caption`, and control-relative styles when they
  produce the intended hierarchy. Avoid accumulating arbitrary pixel sizes.
- Use monospaced text only for URLs, model identifiers, ports, timestamps, JSON,
  and other machine-readable values. Use monospaced digits for changing counters.
- Use light weights for navigation and toolbar SF Symbols, independently of
  the text weight. Keep metadata at least 10.5 pt.

Hierarchy should remain understandable without color: page/section title, row
label, supporting explanation, value or control, then optional metadata.

## Color, Materials, and Icons

- Use semantic system colors such as `.primary`, `.secondary`, `.tertiary`,
  separators, and the user's control accent. Settings uses the shared
  `SettingsLayout.Palette`: anthracite `#212121` for the sidebar and near-black
  `#181818` for the detail pane in dark appearance, with native backgrounds in
  light appearance. Extend each background through its part of the titlebar
  while keeping scrolling content clipped below it. Keep cards native and
  slightly lighter than the dark detail pane. Do not introduce per-page colors.
- Reserve the accent color for selection, a primary action, focus, and meaningful
  status. Do not tint every icon or section title.
- Pair status color with a symbol and text. Green alone must never be the only
  evidence of success, nor red the only evidence of failure.
- Prefer flat semantic surfaces. Use material or vibrancy only when it represents a
  real window/navigation layer and remains legible in light, dark, and increased
  contrast modes.
- Use SF Symbols for generic actions and status. Choose a symbol by meaning, keep
  rendering mostly monochrome or hierarchical, and size it through the owning
  control. Provider or application marks may use runtime-supplied official icons.  bundled AI brand marks must follow [`styleguide.md`](styleguide.md).

## Standard Compositions

### Page and section header

A section header has a concise title, an optional one-sentence explanation, and at
most one trailing status or action group. Do not repeat the navigation title as a
large hero heading.

### Settings card

A card groups one concept. Use `SettingsCard` for a shared native surface and
consistent padding, with spacing instead of separators between rows. Place the
section heading above it and supporting help below it. Avoid a card around the
whole page, cards nested in cards, or an outline around every individual control.

### Settings row

Put the label and optional explanation on the leading side and the value/control on
the trailing side. The whole row should remain readable at minimum window width.
Use a menu picker for a compact single choice, a switch for an immediate Boolean,
a stepper for a small bounded integer, and a sheet for multi-field editing.

### Actions

- Use `.borderedProminent` for the provider sheet's transaction commit. Settings
  toolbar Apply actions use the shared transparent and rounded hover style,
  matching their peer actions.
- Use `.bordered`, menu items, or contextual actions for secondary operations.
- Put destructive actions in a context menu or confirmation flow and mark them
  with the semantic destructive role.
- Use `Save` only when the page has an explicit draft. Immediate controls should
  apply directly or clearly say that an explicit commit remains pending.
- During asynchronous work, keep the action in place, show a small progress
  indicator or changed label, disable conflicting controls, and preserve context.

## Complete State Design

Every user-facing surface must define and validate the states that apply to it:

- **Loading:** stable geometry with a progress indicator or skeleton. Never a
  misleading empty list or blank pane.
- **Empty:** `ContentUnavailableView` or an equally clear native composition with
  one explanation and, when useful, one recovery action.
- **Disabled:** visually subdued with an accessibility hint or nearby explanation
  when the reason is not obvious.
- **Pending:** show what has not yet been applied and the action that commits it.
- **Success:** update the owned state in place. Avoid celebratory alerts for routine
  saves.
- **Error:** preserve the user's input, explain what failed in product language,
  and offer a concrete retry or correction path.
- **Unavailable:** retain the last useful data when safe, distinguish stale data
  from current data, and avoid collapsing the entire page.

## Content Style

- Use sentence case for titles, labels, and buttons. Prefer verbs for actions and
  nouns for destinations.
- Be specific: “Apply changes” is better than “Continue”.
  better than “Sync”.
- Supporting copy explains consequence, not implementation. Keep it to one short
  sentence where possible.
- Avoid promotional language, exclamation marks, redundant headings, and technical
  details that do not help the current decision.
- Preserve exact provider/model identifiers and URLs. Do not prettify machine
  values in a way that makes them ambiguous.

## Accessibility and Input

- Target the macOS default 28 × 28 pt control size and never go below Apple's
  20 × 20 pt minimum. A dense row can be 44 pt high while its control remains
  comfortably clickable.
- Provide accessibility labels for icon-only actions and values/hints for controls
  whose visible state is not self-explanatory. Group decorative children instead
  of making VoiceOver traverse noise.
- Preserve logical reading and Tab order. Support keyboard-only operation,
  Command-Comma for Settings, Return for the default action, Escape for cancel, and
  standard menu shortcuts without overrides.
- Do not encode meaning only through color, hover, animation, or pointer gestures.
- Respect reduced motion, increased contrast, light/dark appearance, and the user's
  sidebar icon size. Avoid animation unless it communicates a state transition.

## Distribution and App Sandbox

`packaging/LittleSwitch.AppStore.entitlements` is the future Mac App Store sandbox
baseline. It enables App Sandbox plus outgoing client and incoming server network
access. The current Developer ID build pipeline deliberately does not sign with
that file, so adding the baseline does not silently sandbox existing releases.

The app is not yet ready for an App Store sandbox runtime. Its Claude Code, Codex,
and OpenCode integrations write user configuration below `~/.claude`, `~/.codex`,
and `~/.config`. Those accesses must move to App Store-compatible, user-authorized
file access or another approved architecture before the App Store entitlement file
is wired into a distribution build. Network client/server entitlements cover the
gateway traffic, but do not authorize those filesystem writes.

## Visual Review Checklist

Before considering a UI change complete, validate it through
the internal computer-use validation protocol and confirm:

- the page reads correctly at default, minimum, and expanded window sizes.
- labels and controls align across adjacent rows.
- no important copy truncates or overlaps.
- loading, empty, error, busy, disabled, and pending states are intentional.
- light and dark appearances use semantic contrast.
- the primary action is obvious without making the page visually loud.
- keyboard focus and the accessibility tree follow the visual hierarchy.
- screenshots contain no credential, private prompt, or unredacted traffic body.

Fix structure and shared metrics first. Do not hide a weak layout with extra blur,
opacity, borders, or shadows.
