# Design System Rules

**Purpose:** Blueprint for building consistent, production-quality iOS UI with SwiftUI. Based on [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/).

**Platform:** iPhone only (iOS 26+, Liquid Glass)

---

## Apple HIG — Core Principles

These come directly from Apple's Human Interface Guidelines and must be followed:

1. **Clarity** — text is legible, icons are precise, adornments are subtle and appropriate
2. **Deference** — fluid motion, content fills the screen, translucency hints at more
3. **Depth** — distinct visual layers, realistic motion, touch and discoverability
4. **Consistency** — use system-provided controls, icons, text styles, and terminology
5. **Direct Manipulation** — content responds to gestures immediately with real-time feedback
6. **Feedback** — acknowledge actions through haptics, highlights, and progress indicators
7. **Metaphors** — people already know how switches, sliders, and scroll views work

---

## Navigation

- Use `NavigationStack` for all screen hierarchies
- Use `navigationTitle()` with system large title (`.large`) for primary screens
- Use `.inline` title mode for secondary/detail screens
- Use `.toolbar` for action buttons — never custom header views
- Use `NavigationLink` for push, `.sheet()` for modal, `.fullScreenCover()` for immersive flows

---

## Iconography

- Use **SF Symbols** exclusively — Apple's built-in icon library
- Match symbol weight to nearby text weight
- Use `symbolRenderingMode(.hierarchical)` for subtle depth
- Never use third-party icon libraries

---

## Typography

System text styles are the default. Custom fonts may be used for **branding** only.

### System Styles (default)

| Style | SwiftUI | Use for |
|-------|---------|---------|
| Large Title | `.largeTitle` | Primary screen titles (via `.navigationTitle`) |
| Title | `.title` | Section headers |
| Headline | `.headline` | Row titles, bold labels |
| Body | `.body` | Primary text content |
| Subheadline | `.subheadline` | Supporting text, descriptions |
| Footnote | `.footnote` | Tertiary info |
| Caption | `.caption` | Metadata, timestamps |

### Custom Typography (branding)

If using custom fonts for branding:
- Define them in a `Typography` enum or extension
- Register fonts in Info.plist under `UIAppFonts`
- Always provide a system font fallback
- Must support Dynamic Type via `@ScaledMetric` or `.dynamicTypeSize()`
- Never hard-code point sizes without Dynamic Type support

```swift
// Example: Custom brand font with Dynamic Type
extension Font {
    static let brandTitle = Font.custom("YourFont-Bold", size: 28, relativeTo: .title)
    static let brandBody = Font.custom("YourFont-Regular", size: 16, relativeTo: .body)
}
```

---

## Colors

System semantic colors are the default. Custom brand colors are allowed for identity.

### System Colors (use for all standard UI)

| Use | Color |
|-----|-------|
| Primary text | `.primary` |
| Secondary text | `.secondary` |
| Subtle text | `.tertiary` |
| Accent/tint | `.tint` / `.accentColor` |
| Destructive | `.red` |
| Backgrounds | System-managed |

### Brand Colors

- Brand violet `#7C3AED` defined as `Color.brand` in `Colors.swift`
- Warm background `#F8F2F0` defined as `Color.warmBackground` for light mode
- `Color(hex:)` helper for user-defined data (category colors from database)
- Category-tinted card backgrounds use `Color.blended(opacity:isDark:)` — 14% light, 10% dark
- Never replace system semantic colors — use brand colors alongside them
- Test in both light mode, dark mode, and increased contrast

---

## Materials & Liquid Glass (iOS 26)

- Navigation bars and toolbars get Liquid Glass automatically
- **All custom interactive surfaces** (buttons, cards, chips) must use `.glassEffect(.regular.interactive(), in: shape)` — never `.regularMaterial` for tappable elements
- `.regularMaterial` / `.ultraThinMaterial` only for non-interactive overlays (e.g., fade gradients, dimming layers)
- Never set manual background colors on navigation elements — let the system handle it

---

## Spacing

- Use SwiftUI's built-in spacing (stack defaults are usually correct)
- Section padding: `.padding()` (16pt default)
- Custom spacing: multiples of 4pt (`4, 8, 12, 16, 20, 24`)
- Prefer `VStack(spacing:)` and `HStack(spacing:)` over manual padding
- Screen edge insets: handled automatically by `List` and `Form`

---

## Layout

- Home screen uses `ScrollView` + `LazyVGrid` (2-column card grid) for visual browsing
- Detail/settings screens use `List` with `.listStyle(.insetGrouped)` or `Form`
- Use `Section` with headers/footers for grouping in lists
- Use `ContentUnavailableView` for empty states
- Use `.searchable()` for search — never custom search bars

---

## Buttons & Actions

- **Default to `.buttonStyle(.plain)`** for custom buttons — never rely on the system blue accent tint
- Style buttons explicitly with brand colors, `.glassEffect()`, or foreground/background modifiers
- Use `.borderedProminent` or `.bordered` only for system-styled form/alert buttons where the default tint is intentional
- Destructive actions: `.tint(.red)`
- Use `.buttonBorderShape(.capsule)` or `.roundedRectangle` as appropriate
- Use `.controlSize(.large)` for prominent actions
- Toolbar actions: `.toolbar { ToolbarItem { } }`

---

## Menus & Selection

- Home category filter uses horizontal scrollable pill chips (brand-colored capsules)
- Use `Menu` for compact option dropdowns where chip bar is not appropriate
- Use `Picker` for single selection from a set of options
- Use `.confirmationDialog()` for destructive action confirmation
- Use `.alert()` for simple confirmations

---

## Loading & Error States

Every view that fetches data must handle all three states:

| State | Component |
|-------|-----------|
| Loading | `ProgressView()` or `.redacted(reason: .placeholder)` |
| Error | `ContentUnavailableView` with retry button |
| Empty | `ContentUnavailableView` with SF Symbol and message |

---

## Dates & Formatting

- Use `Text(date, style: .relative)` for relative timestamps
- Use `Text(date, format:)` for specific date formats
- Never use manual `DateFormatter` unless system formatters can't express the format

---

## Gestures & Interaction

- Use `.swipeActions(edge:)` on list rows for contextual actions
- Use `.onDelete` for standard delete
- Use `.refreshable` for pull-to-refresh
- Minimum tap target: 44pt (HIG requirement)
- Use haptic feedback for significant actions (selection, success, error)

---

## Sheets & Alerts

- Use `.sheet()` for modal content
- Use `.confirmationDialog()` for action sheets
- Use `.alert()` for confirmations
- Use `.fullScreenCover()` for immersive flows (e.g., recording)

---

## Animations

- Use `.animation(.snappy, value:)` for state transitions
- Use `withAnimation(.spring)` for user-triggered changes
- Use `.transition()` for view insertion/removal
- Prefer system animation presets over custom durations

---

## Accessibility (HIG Requirement)

- All images need accessibility labels (or `.accessibilityHidden(true)` for decorative)
- System text styles + Dynamic Type = automatic text scaling
- System colors = automatic high-contrast support
- Test with VoiceOver enabled
- Use `.accessibilityLabel()` on custom controls


---

## Less Is More

- Before adding any UI element, ask: "does this add information the user doesn't already have?" If not, don't add it.
- Don't show state text (e.g., "Unassigned", "Empty", "No items") when a button or empty space already communicates it.
- Fewer elements with clear purpose beats more elements that explain each other.
---

## Self-Check

Before delivering any screen:
- [ ] Uses system text styles (or branded fonts with Dynamic Type)?
- [ ] Uses system/asset-catalog colors (not inline hex for UI)?
- [ ] SF Symbols only (no third-party icons)?
- [ ] Uses system components (List, Form, Menu, toolbar)?
- [ ] Loading, error, and empty states handled?
- [ ] Works in light mode and dark mode?
- [ ] Supports Dynamic Type?
- [ ] All tap targets ≥ 44pt?
- [ ] Accessibility labels on custom controls?
