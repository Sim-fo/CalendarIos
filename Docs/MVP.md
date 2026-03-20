# Calendar iOS MVP

## Included in v1
- Weekly view as the primary screen
- Local persistence with GRDB/SQLite
- Event CRUD from the weekly screen
- Event types with seeded defaults
- Localized date/time formatting
- Basic dark/light adaptive SwiftUI styling

## Explicitly deferred
- Firebase sync
- Google Drive backup
- Push notifications
- Ads
- Tutorials
- Birthdays
- Trackers
- Clients
- Todo list
- Advanced weekly interactions such as drag, resize, and copy mode

## First vertical slice
1. App shell and dependency wiring
2. GRDB database queue and migrations
3. `Event` and `EventType` domain models
4. Weekly data loading for the current week
5. Create/edit/delete flow from a sheet editor

## Definition of done for the first build
- The app opens into the weekly screen
- The current week is visible with 7 day columns
- Events are loaded from SQLite
- The user can create, edit, and delete an event
- Seeded event types are available for new events

