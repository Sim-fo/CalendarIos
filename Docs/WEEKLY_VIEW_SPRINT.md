# Weekly View Sprint

## Scope
- Establish the first runnable iOS foundation around the weekly screen
- Keep the data model intentionally narrow: `Event` and `EventType`
- Avoid sync-specific fields as active logic for now

## Source of truth from Android
- `UserEvent.kt`
- `EventTypeEntity.kt`
- `MainNavigation.kt`

## Current implementation choices
- `GRDB` for local persistence
- `SwiftUI` for presentation
- `MVVM` for screen state
- Horizontal weekly layout with one card column per weekday

## Next step after this sprint
- Add a dedicated event type management screen
- Replace seeded demo data with onboarding-aware empty states
- Evolve the weekly screen toward a richer time-grid layout

