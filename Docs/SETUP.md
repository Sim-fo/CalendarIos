# Setup

## Current state
- The repository now contains a SwiftUI + GRDB starter scaffold
- The app is organized around a weekly-first flow
- Persistence currently covers only `Event` and `EventType`

## Important note
- `xcodegen` is not installed in the current environment
- Because of that, `project.yml` is prepared, but the `.xcodeproj` file has not been generated automatically here

## Generate the Xcode project
1. Install `xcodegen`
2. Run `xcodegen generate` inside `CalendarIos`
3. Open the generated `CalendarIos.xcodeproj`

## First expected app behavior
- App opens on weekly view
- Seeded sample events appear for the current week
- You can add, edit, and delete events

## Next implementation step
- Replace the simple card-based weekly layout with a time-grid weekly timeline
- Add a dedicated event type management screen
- Add tests for migrations and repository CRUD
