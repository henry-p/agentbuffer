# Liquid Glass application analysis (AgentBuffer)

Date: 2026-01-19

## Source takeaways (Apple)
- Liquid Glass is a dynamic, translucent material and interaction model that keeps focus on content while controls and navigation feel alive and adaptive.
- Apply Liquid Glass primarily to the navigation/control layer that floats above content; avoid using it on the content layer itself.
- Avoid stacking glass on glass; use fills, transparency, or vibrancy for elements that sit on top of glass.
- Two variants exist: Regular (general-purpose, adaptive) and Clear (more transparent and requires a dimming layer). Do not mix them in the same surface.
- Legibility adapts to what is behind the material; small elements can flip light/dark for contrast, while large elements should avoid flips to reduce distraction.
- When glass expands (for example, menus), it should feel thicker with deeper shadows and stronger lensing.

## Current UI surfaces in this repo
- Popover window and root view: `Sources/AgentBuffer/PopoverCoordinator.swift`, `Sources/AgentBuffer/PopoverPanel.swift`, `Sources/AgentBuffer/PopoverRootController.swift`
- Main popover content: `Sources/AgentBuffer/MainPopoverController.swift`
- Settings pages and groups: `Sources/AgentBuffer/SettingsPopoverController.swift`
- Agent cards and badges: `Sources/AgentBuffer/AgentCardView.swift`
- Notification prompt window: `Sources/AgentBuffer/AgentBufferApp.swift` (notification permission prompt)
- Menu bar icon: `Sources/AgentBuffer/MenuBarRenderer.swift`

## Mapping guidelines to surfaces

### Navigation/control layer candidates (good for Liquid Glass)
- Popover background and chrome (header/footer): treat the popover as the control layer and apply Liquid Glass to its background.
- Settings topic list and detail header: can sit on the same glass plane as the popover background.
- Buttons, switches, sliders: keep these as system controls so they inherit platform glass styling automatically.

### Content layer candidates (avoid Liquid Glass)
- Agent cards: these are the content layer; keep them opaque and readable to preserve hierarchy.
- Section headers, runtime bars, and list items: keep in the content layer with standard label colors.

### Overlays and transient UI
- Notification prompt window: could use a small glass panel to feel system-native.
- Avoid Clear variant for this UI because it is not media rich and would require dimming that may reduce clarity.

## Implementation status (applied)
- Popover background is now a glass material layer (NSVisualEffectView) in `PopoverRootController`.
- The popover panel background is clear and non-opaque so the glass can show through.
- Settings groups no longer use opaque group fills; borders and separators carry grouping without stacking glass.
- Agent cards remain content-layer surfaces with slightly softened fills to sit on glass.
- Notification permission prompt uses a glass background view.
- Main/settings transitions use a short crossfade to reinforce the fluid, glassy feel.
- Settings topics/detail content crossfade inside the settings view.
- No OS fallback or legacy styling is kept.

## File-by-file opportunities
- `Sources/AgentBuffer/PopoverRootController.swift`
  - Add the glass background view and ensure it sizes to the popover.
- `Sources/AgentBuffer/PopoverPanel.swift` and `Sources/AgentBuffer/PopoverCoordinator.swift`
  - Set the panel background to clear if a glass view is used.
- `Sources/AgentBuffer/SettingsPopoverController.swift`
  - Reduce group background fill to avoid glass-on-glass stacking.
- `Sources/AgentBuffer/AgentCardView.swift`
  - Keep opaque card backgrounds; optionally refine borders or add a slight shadow for separation.
- `Sources/AgentBuffer/AgentBufferApp.swift`
  - Apply a glass background to the notification permission prompt window.

## Open questions
- Should the popover be fully glassy, or should the list area stay flat with only the header/footer using glass?
- Should the current card look remain, or should we flatten cards and rely on section separators?
- Do we want a dev toggle to compare Liquid Glass vs legacy styling on older macOS versions?
