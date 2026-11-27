# AuthLens design system

## Principles and scope

Build new screens from existing shared components. Navigation changes location, tabs change associated content, filters constrain evidence, and buttons perform operations. Keep SAP identity/account/directory evidence distinct. Preserve exact technical identifiers, local-only handling and readable light/dark themes.

This consolidates the existing React/TypeScript/Vite/Tailwind application rather than introducing another framework. Color customization, saved theme presets, module classifications, source parsing, review decisions and comparison evidence sets are unchanged. The integrated reference is **Settings → APPLICATION → Component Library**.

## Branding source assets

All built-in branding sources live in [`assets/branding/`](../../assets/branding/), with roles listed in
[`manifest.json`](../../assets/branding/manifest.json):

| File | Use |
| --- | --- |
| `logo.png` | Brand Assets v2 transparent 1024 px application/header/sign-in logo; existing sign-in container is 80 CSS px |
| `app.png` | Supplied transparent 512 px README/application image |
| `favicon.ico` | Supplied browser icon: 16, 32 and 48 px |
| `apple-touch-icon.png` | Supplied transparent 180 px bookmark/touch icon |
| `app.ico` | Supplied Windows icon: 16, 24, 32, 48, 64, 128 and 256 px |
| `icon-192.png` | Supplied 192 px web application icon |
| `icon-maskable-512.png` | Supplied 512 px maskable icon, including its approved background/safe margin |
| `site.webmanifest` | Single application manifest; reuses `app.png` for 512 px and does not override theme/background colors |

Replace these source files at the same paths to update branding; preserve valid formats and the multi-size ICO contract. No application code
change is required. The seven images are byte-identical selections from Brand Assets v2: `branding/authlens-transparent-1024.png`,
`branding/authlens-512.png`, `windows/AuthLens.ico`, and `web/favicon.ico`, `web/icon-180.png`, `web/icon-192.png`, `web/icon-maskable-512.png`.
They supersede the previous image bytes at stable names, without aliases or duplicate copies. The transparent mask is approximate/raster-derived;
inspect edges on both backgrounds and readability at small sizes before deployment. Preserve square proportions and transparency.
There is no editable SVG master. Supplied dark/light background previews are not needed for the application; use the same transparent mark in both themes.

The Vite branding plugin reads the asset-role manifest and serves/emits all seven web assets directly from canonical sources for development and
production. There are no checked-in frontend copies. The .NET API embeds the production UI for both Server and Desktop; both executable projects
and both Inno Setup scripts consume `assets/branding/app.ico`. The Desktop window extracts that embedded executable icon. Existing custom uploaded
header/report logos are user data and are unaffected. A configured organization logo continues to override the built-in header logo.
Report image fixtures are synthetic validation inputs, not application branding. Desktop shortcuts inherit the Desktop EXE icon; the Server
Service Manager shortcut explicitly uses the Server EXE icon rather than PowerShell's. The Service Manager itself is a console tool.
PDF/DOCX rendering consumes only the frozen user-selected report logo; when none is supplied it does not substitute a built-in image.
No report/logo settings, frozen evidence or custom uploaded images are rewritten by replacing the application assets.

The supplied preview backgrounds, original concept and duplicate PNG sizes stay outside the repository and production bundles.
The single web manifest merges the supplied name/display/icon metadata with the application's root start URL/scope/id. Its reference colors are
intentionally omitted: Brand Assets v2 does not change any application palette, CSS variable, light/dark behavior, navigation style, typography or spacing.
No service worker or offline data cache is introduced; manifest metadata is not an offline-support promise. Existing authorization still applies.

The former product-specific asset paths are not compatibility interfaces; no redirects or duplicate aliases are retained. An already-installed release keeps its embedded images until deliberately
updated; changing repository branding never changes a running service. Validate with `node --test scripts/tests/branding.test.mjs`, the frontend
production build, affected .NET build/installer tests and native Inno compilation when available. The canonical Windows `.\build.ps1` command
also runs `scripts/verify-branding.mjs`: all seven canonical ICO frame payloads must exist in both published EXEs
and both Setup EXEs, and canonical web images must occur byte-for-byte in both embedded UIs and in frontend output. Its report is stored at
`build/branding-verification.json` inside the unique build directory. Single-file compression stays disabled; stale embedded images fail verification.

Brand Assets v2 focused Windows verification: the frontend production build/type check, six branding Node tests, both synthetic
Inno compilations (including PE icon-resource inspection), and the Desktop/direct-dependency build passed. Both built apphosts contain
all seven approved ICO frames. Isolated Edge checks verify embedded web bytes/manifest MIME type and capture sign-in at 390/1280 px,
the application header in both themes, and a light/dark icon contact sheet. Existing theme/token/style files and README logo markup
are unchanged. Contact-sheet image URLs are separate from Edge's special favicon cache; no production cache policy is changed.
The supplied mark retains generous internal spacing: the silhouette is visible at 16 px but fine person/shield details are limited.
No optical small-size replacement, cropping or mask correction was invented. The inspected 64–96 px logo preserves its aspect ratio
and has no obvious mask halo in the captured application views; this does not replace native Explorer, taskbar, shortcut or browser-tab
GUI acceptance. No installed application was updated, and no full release package was rebuilt for this source integration.

Windows Explorer, Start Menu and taskbar may retain cached icons after an upgrade. Relaunch the application, unpin/re-pin a stale shortcut or sign
out/in if needed; do not delete icon-cache files or add cache-reset behavior to Setup. Browser tabs may need a reload/cache refresh. Native
window/taskbar, installed shortcuts, actual 16/24/32 px rendering, high-DPI and browser bookmark appearance still require manual GUI acceptance.

## Token ownership

`frontend/src/styles/tokens.css` owns default palette values and shared dimensions. `frontend/src/lib/theme.ts` remains authoritative for validated user palettes, derived colors, readable foregrounds and System appearance. Its existing CSS property contract is preserved; aliases resolve live values rather than copying a preset. `styles/components.css` owns canonical component styles and compatibility classes. `index.css` retains domain layouts, calendar/combobox placement, module/editor presentation and responsive source arrangements.

| Purpose | Tokens |
| --- | --- |
| App, surface, elevated background | `--bg`, `--surface`, `--surface2`; aliases `--color-background`, `--color-surface`, `--color-elevated` |
| Text, secondary, muted, borders | `--text`, `--text2`, `--muted`, `--border`; corresponding `--color-*` aliases |
| Branding and action | `--primary` / `--on-primary` for navbar; accessible action `--accent2` / `--on-accent2`; `--color-action` alias |
| Hover/focus | `--hover`, `--focus`; `--color-hover`, `--color-focus` aliases |
| Semantic states | `--success`, `--warning`, `--error`, `--info`, `--error-bg`, `--info-bg`; danger alias `--color-danger` |
| Spacing | `--space-1/2/3/4/5/6/8`: 4/8/12/16/20/24/32 px |
| Typography | `--font-ui`, `--font-code`; title 20 px, section 16 px, body 14 px, label/table header 13 px, metadata 12 px |
| Radius | Control 8 px, card 12 px, popover 10 px, badge 4 px |
| Controls | `--control-height`: 42 px; compact: 34 px; icon default: 42 px square; copy target: 32 px, 42 px on coarse pointers |
| Floating surfaces | `--elevation`; popover borders/background use surface/text tokens |

Tailwind's font families reference the same CSS font tokens. Existing scale utilities remain useful for layout; new components should prefer the shared dimensions. Specialty choices such as icon-picker tiles, matrices and long evidence tables have deliberate domain-specific geometry.

SAP module colors remain independent of general theme colors. Do not substitute a success/warning color for a classification color, or interpret a module color as risk.

## Actions and interaction states

Canonical `Button` supports primary, secondary, outline, ghost and destructive variants; default, compact and icon sizes; loading and disabled states. Loading disables the operation and exposes `aria-busy`. Every icon-only action uses `IconButton` with a required accessible label. Tooltips also work on keyboard focus and dismiss on Escape; they are supplemental labels, not the only accessible name.

Primary actions use the derived accessible action foreground. Secondary/outline are routine operations, ghost reduces chrome, and destructive is reserved for deletion. Clearing filters is neutral. Hover uses theme tokens; active action feedback is a small press translation; selection uses explicit bottom-border/pressed state rather than relying solely on color. Focus-visible is a two-pixel ring with spacing. Reduced-motion preferences remain honored.

`settings-secondary-button`, `settings-control` and `settings-icon-button` are compatibility aliases in the canonical stylesheet, not independent designs. Remaining Settings actions use the shared default size; compact buttons explicitly override that default. Do not copy long utility strings into new screens.

## Forms, tables and feedback

`FormField` associates the actual control ID with its label and keeps help/error descriptions out of the accessible name. `Input`, `SearchInput`, `Select` and `Combobox` share dimensions. Select owns its chevron; callers must not add another. On touch input (`pointerType` `touch`) Select leaves the platform picker alone instead of opening its custom popup, so iOS Safari never shows two lists (BUG-011). Searchable controls use the existing portal combobox, not native datalists. Multi-value transaction entry remains the existing `TransactionFilter` with shared chips and operator buttons; no redundant generic MultiSelect was introduced.

Date entry remains `NorwegianDateInput`, with Norwegian labels, Monday-first floating calendar, keyboard navigation and DD.MM.YYYY entry. ISO date-only comparison and SAP maximum-date semantics remain unchanged.

`DataTable` provides a focusable overflow region, caption and shared table styling; specialized existing tables retain their domain JSX and inherit the same header, spacing, hover and row-divider rules. Role identifiers remain single-line, copyable and horizontally scrollable within their own control. Horizontal scrolling is confined to the table region, never required for the whole page.

`StatusBadge` owns generic tone presentation. `AccountStatus`, `AssignmentStatus`, `StatusPill` and `SourceBadge` keep their domain-specific labels and rules. Lock indicators preserve their established neutral unlocked/unknown and red locked appearance. AD status is not SAP validity. Loading, empty, notification and evidence-disclosure components use semantic text and icons.

## Error presentation

Connection and session problems are reported once, at application level, by `SessionNotice`; views whose data cannot load show the compact `session-empty` state from `QueryState` or `ErrorState` and never repeat the message or its actions. Other request errors stay local to the view that issued them.

## Choosing the right summary component

| Need | Use |
| --- | --- |
| One prominent figure to scan or drill into | `Kpi` (a few per view, never a wall of tiles) |
| Secondary metrics and operational facts | `InfoList` and `InfoRow`: plain rows, a full-row button when they filter or navigate |
| A distribution or proportion backed by data | A chart with readable labels and tooltips; no invented trends. Secondary explanations go in an `InfoTip` popover; neutral parts are gray, never the accent color; share-based health uses the central `lib/health.ts` thresholds with semantic tokens and always shows the number |
| A progress bar (`StackedBar`, `InfoRow` progress) | Always visible: the track has a border and a neutral fill so 0% reads as an empty bar; segments carry semantic tones and the percentage is also shown as text |
| A status label (Enabled, Disabled, Static, Dynamic, Loaded, review states) | `EnabledBadge`, `ModeBadge`, `SourceBadge` and `StatusBadge` from `Shared`: one wording, tone and Lucide icon per state (Enabled check, Disabled slashed circle, Static lock, Dynamic refresh). Internal enum values (`directory_match`, `missing_email`) pass through `sentenceCase` in `lib/labels.ts`; no lowercase enum reaches the interface |
| A zero count in a KPI or information row | Always neutral: `Kpi` and `InfoRow` coerce warning, danger and success tones to neutral for a zero value (`calmZero`) |
| The tone of a KPI figure | Pages name the metric or review state, never a colour: `kpiTone(metric, value)` and `stateTone(state, value)` in `lib/kpiTone.ts` map meaning to tone. Informational totals and enabled definitions are neutral; potential conflicts, pending, outdated, rejected and removal states are warning (never a confirmed violation); overdue actions are danger; completed, approved, accepted and verified are success. Add a new metric to that file instead of choosing a tone on the page |
| Keyboard focus | One ring from tokens (`--focus-width`, `--focus-offset`, `--focus-radius`): solid, 2 px, always rounded. Inset only where a container clips the ring (tab strips, table rows); tabs use the same ring instead of a bottom bar; plain elements with square corners get the shared radius while focused |
| Detailed, comparable records | A table (zebra, hover and selected states) |
| Compact status or classification | A badge or pill |
| An exact technical identifier | A codeblock (`RoleIdentifier`): the name on one line inside its box, never wrapped and never scrolled; the copy control stays beside it and copies the exact value. Layouts such as the role card grid adapt their column count; a name that still does not fit ends in an ellipsis and the full name stays in the tooltip and the accessible name. The font size is fixed, so the geometry never changes with hover, focus or a sidebar transition. Tables and matrices keep their own horizontal scrolling |

Identifiers are never given soft-wrap opportunities. Module icons carry no hover ring; only real controls get hover and focus treatments. Expand and collapse controls use one glyph: right when collapsed, down when expanded (`DisclosureChevron`, and the same control for native `details`), with the 34 px compact hit area shared with icon buttons.

## Disclosure and selection states

Every `details/summary` uses one compact chevron control (24 px box, its own hover background, rotates when open); the summary text has no hover fill. Selected rows and active tiles use a subtle full border or primary tint, so selection never shifts layout, and zebra rows, hover and selection stay distinguishable. The multi-select toolbar shows Select all, Clear and Close as three bordered buttons.

## Capitalization and terminology

Product names stay in Title Case: main navigation, page and section titles, SoD workspace views and the decision names (Activity Review, Role Assignment Review, Risk Acceptance). Table headers, buttons, field labels, filter labels, helper text and chips use sentence case. Official SAP terms keep their SAP spelling, for example **SAP User Group**, **Release Group**, **Release Strategy**, T-code and Risk ID. Use the same label for the same concept on every page.

## Text wrapping (BUG-10, after RC4)

Labels (role categories and module names, KPI and chart labels, option names, group names, headings, metadata values) wrap at whole words with
`overflow-wrap: break-word`: a label's minimum width is its longest word, so layouts cannot squeeze "Management" into "Managemen / t"; a single word
longer than its box still breaks. Technical values (paths, hashes, transaction lists, raw CSV cells, technical details) keep
`overflow-wrap: anywhere`. SAP identifiers are never wrapped or hyphenated (`RoleIdentifier` ends a name that does not fit in an ellipsis with the full value in the tooltip; the copy button writes the exact
value). No automatic hyphenation is applied, so no arbitrary hyphens appear in Norwegian or English text. Sidebars do not hide overflow: their
children are constrained to the sidebar width (BUG-09, reopened and fixed for identifiers; see the acceptance tracker).

## Responsive rules

Desktop navbar utilities are compact icons on one row where space permits. At narrower widths, primary navigation gets its own row with visible destination labels. Utility accessible names remain available to touch assistive technology. User panels become one column; comparison filters go from five to three/two/one; compact summary counts wrap without becoming large KPI cards. Existing settings-sidebar behavior and source/table breakpoints are retained.

Prefer shared responsive classes before adding another page-specific breakpoint. Validate labels, chevrons, focus rings, floating panels and table scrolling at 375, 800, 1280 and 1600 px in both themes.

The application header uses a full-label modal navigation drawer below 1024 px and retains desktop navigation above that boundary. Its compact
profile icon keeps a tooltip and accessible name; viewport-bounded menus open the existing profile/session controls. Settings switches to a labelled
section Select below 768 px. Toolbars wrap rather than hiding actions, and dense matrices/tables keep deliberate internal scrolling. A phone view
does not replace the full matrix with a reduced data subset. Responsive acceptance also checks 360, 390, 768, 1024 and 1440 px, both themes,
drawer focus/scroll isolation, Escape/outside/route dismissal, profile keyboard interaction and horizontal page overflow.

See [Component Library](COMPONENTS.md), [Navigation patterns](NAVIGATION.md) and [validation tracker](../validation/README.md).

## Refresh evidence surfaces

Refresh banners use semantic success/error backgrounds and a neutral unchanged state. Error styling describes failed operations, not intentionally disabled modules. Modal surfaces use the same elevation, surface, border, spacing and radius tokens as anchored popovers. Source cards keep technical information expandable within the relevant source; record-level evidence stays inside private report dialogs.


## Clean interaction states

Shared controls use background changes, borders and crisp two-pixel focus outlines.
Blurred elevation and colored glow are removed in both themes; autofill masking is
an inset fill, not a focus effect. Popovers remain portal-positioned with opaque
surfaces and visible borders. Navigation uses a shared strip implementation while
preserving distinct link and tab semantics. Secondary navigation has a subtle
bottom-border hover state rather than a large background treatment.

Page titles use the shared icon-led header. Saved Filter Save/Clear actions share
an equal-width two-column row. Source metadata uses full-width facts rather than
nested two-column cards. Comparison's B-only category uses `--comparison-b`, an alias of the theme's
error/red color; shared and A-only reuse success/information. Category colors do
not imply a security finding. Single-role
zebra backgrounds cover the whole contiguous row with outer-list rounding only;
hover leaves those surfaces unchanged. Identifiers remain exact, single-line and
copyable, with contained horizontal scrolling instead of arbitrary wrapping. Focus
remains a visible outline.

Dialogs share --dialog-backdrop with stronger theme-aware dimming and no blur. Spinners share --spinner-duration (1.4 seconds); reduced-motion mode removes their rotation without delaying operations. Navigation reserves bottom-border hover/active indicators; a separate focus-visible outline remains for keyboard users. Structural table separators remain.

## Tailwind-first styling contract

Tailwind 3.4 is the primary choice for new and migrated presentation. The runtime
pipeline remains configuration → CSS variables → semantic Tailwind utilities →
shared React components. `canvas`, `surface`, `elevated`, `content`, `secondary`,
`muted`, `line`, `action`, `hover` and `focus` map to the existing theme variables;
`rounded-control`, `rounded-card` and `min-h-control` map to shared dimensions.
These values update with runtime themes and custom branding.

Order utilities as layout, size, spacing, typography, colors, interaction and
responsive variants. Prefer standard spacing scales. Shared component contracts,
complex evidence tables, browser-specific rules and measured portal positioning
remain legitimate CSS. Validated runtime colors and isolated draft theme tokens
remain legitimate inline styles. Remove migrated selectors rather than stacking
new overrides on top of them; no new styling dependency is required.

Secondary navigation and content tabs reserve a transparent bottom border, coloring
it with the primary action color on selection and contrasting text color on hover
without changing geometry. Focus uses a separate visible
outline. Technical identifiers always retain a neutral code border; module colors
belong to module metadata, not identifier status. Comparison selection uses a full
outline rather than a bottom-only shadow.
