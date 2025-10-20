# Contributing to LogoWallpaper

Thanks for your interest in improving LogoWallpaper! This guide summarizes the workflow and project conventions so changes stay easy to review and ship.

## Getting Started

- **Fork & clone** the repository, then open it with `xed .` or your preferred editor.
- **Install Xcode 15 or newer** so Swift 5.9 features and the SwiftUI previews render correctly.
- **Set the active scheme** to `LogoWallpaper` for builds and tests.

## Development Workflow

1. Create a feature branch from `main` with a descriptive name (for example, `feature/drop-zone-preview`).
2. Make focused commits; keep commit subjects imperative and under 70 characters (e.g. `Add drop-zone preview state`).
3. Run the build locally before opening a pull request:
   ```sh
   xcodebuild -scheme LogoWallpaper -destination 'platform=macOS' build
   ```
4. Add or update tests alongside your changes. Logic-focused tests belong in `LogoWallpaperTests/`; XCUI flows live in `LogoWallpaperUITests/`.
5. Execute the full test suite, especially before requesting review:
   ```sh
   xcodebuild -scheme LogoWallpaper -destination 'platform=macOS' test
   ```
6. Reference any related issues in your pull request description and summarize user-facing updates (screenshots are appreciated for UI tweaks).

## Coding Style

- Follow Swift defaults: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for values.
- Prefer `struct` value types for view models unless shared mutable state is required.
- Keep async code on the main actor when touching the UI.
- Group helpers with `// MARK:` pragmas and collapse unused imports before submitting.
- Store assets in `LogoWallpaper/Assets.xcassets`, naming sets after the brand or palette so previews stay readable.

## Feature Organization

- Place generation state within `Models/` and image utilities inside `Utils/`.
- SwiftUI views belong in `Views/` and should expose a single `body` plus private helpers for clarity.
- Document new controls in `ContentView` using concise inline comments to keep automation efforts traceable.

## Testing Expectations

- Use the new `Testing` package with descriptive `@Test` function names such as `@Test func generatesCenteredWallpaper()`.
- Cover drop handling, wallpaper sizing, and background color persistence when changes touch those areas.
- For UI scenarios, identify elements via accessibility identifiers and guard against flakiness with `waitForExistence` checks.

## Submitting a Pull Request

- Ensure your branch is rebased on the latest `main` to minimize merge conflicts.
- Include the output of `xcodebuild … test` (or relevant `make` targets) in the pull request body.
- Fill out the pull request template, noting any follow-up tasks for future contributors.
- By contributing, you agree to follow the project [Code of Conduct](CODE_OF_CONDUCT.md).

Thanks again for helping make LogoWallpaper better for everyone!
