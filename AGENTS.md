# Repository Guidelines

## Project Structure & Module Organization

Album RSS is an image-focused RSS client connecting directly to Miniflux and Google Reader-compatible services; it has no custom backend.

- `apps/web/`: React and Vite application. Pages, reusable components, utilities, and state live under `src/`; static assets belong in `public/`. Shared styles live in `src/styles/`.
- `packages/core-ts/`: shared article, subscription, and image models.
- `packages/providers-ts/`: RSS service adapters, authentication, and pagination.
- `contracts/`: cross-platform fixtures. `contracts/fixtures/media/*.json` are golden image-extraction cases read by both the web Vitest suite and the Swift tests.
- `apps/ios/`: native iOS app (SwiftUI, UIKit for the viewer pager and zoom). Hand-written `AlbumRSS.xcodeproj` using file-system synchronized groups, so new files under `AlbumRSS/` or `AlbumRSSUITests/` need no project edits. Minimum iOS 18; Liquid Glass on iOS 26+ with material fallbacks.
- `swift/`: one Swift package (`swift/Package.swift`) with `AlbumCore` (models, URL parsing, entry parser, masonry math, GRDB storage, `AlbumStore` state and write queue, demo data), `AlbumProviders` (Miniflux and Google Reader adapters), and `AlbumImages` (Nuke pipelines, size probe, demo art, Photos saving). The app links only these products.
- `scripts/`: local Miniflux connectivity and browser verification utilities, plus `stub-rss-server.py`, a stdlib-only Miniflux/Google Reader stand-in on `127.0.0.1:8787` for end-to-end checks.

## Build, Test, and Development Commands

Use pnpm 9.9.0 and Node matching `^22.13.0 || >=24`. Run commands from the repository root:

- `pnpm install`: install workspace dependencies.
- `pnpm dev`: start the web application at `http://localhost:5173`.
- `pnpm build`: build workspace projects with build scripts.
- `pnpm test`: run all workspace Vitest suites.
- `pnpm typecheck`: check TypeScript across workspaces.
- `pnpm lint`: run ESLint, including React Hooks rules.
- `pnpm format:check`: check Prettier formatting; `pnpm format` rewrites files.
- `pnpm --filter @album-rss/web preview`: preview the built web application.
- `swift test --package-path swift`: run the Swift unit tests on the macOS host (network is always faked).
- `xcodebuild -project apps/ios/AlbumRSS.xcodeproj -scheme AlbumRSS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build|test`: build the app or run the UI tests. UI tests launch with `--reset --demo`; `ConnectionTests` need `python3 scripts/stub-rss-server.py` running and skip otherwise.

GitHub and Swift Package resolution may need the local HTTP proxy (`https_proxy=http://127.0.0.1:7890`, and `-scmProvider system` for `xcodebuild`). Dependencies are pinned exactly (GRDB 7.11.1, Nuke 13.2.0, SwiftSoup 2.14.2); update `Package.resolved` files together with version bumps.

## Coding Style & Naming Conventions

Use strict TypeScript, explicit type-only imports, and existing workspace package boundaries. Follow `.editorconfig`: UTF-8, LF, two-space indentation; Python uses four spaces. Prettier enforces single quotes, no semicolons, trailing commas, and a 100-character print width.

Name React components in PascalCase (`GalleryCard.tsx`), hooks with `use`, and utilities in camelCase. Keep component styles in adjacent `*.module.css` files. Write human-facing documentation and comments in Chinese; agent-facing instructions in English.

Swift uses two-space indentation, Swift 6 language mode and strict concurrency. The app target defaults to `MainActor` isolation; mark plain value types that cross isolation `nonisolated`. Keep behavior in the Swift package and mirror the web implementation (`store.ts`, `providers-ts`, `parseEntry.ts`, `masonry/layout.ts`) rather than redesigning it; note intentional differences (persistent write queue, local snapshots) in docs.

## Testing Guidelines

Place Vitest tests beside implementation files as `*.test.ts`, using `describe`, `it`, and `expect`. Mock network requests in provider tests. Swift tests use Swift Testing (`@Test`, `#expect`) under each module's `Tests/` folder; inject fakes through `StoreEnvironment` and `HTTPClient` instead of hitting the network. When changing entry parsing, add a case to `contracts/fixtures/media` and run both the web and Swift suites. Cover changed behavior and regressions, especially pagination, state transitions, and layout calculations. No coverage threshold is configured. Run targeted suites with `pnpm --filter @album-rss/providers test`, then relevant workspace checks. Local integration scripts require machine-specific services and paths; inspect them before running.

## Commit & Pull Request Guidelines

The single baseline commit uses a Chinese description and establishes no recurring convention. Use Conventional Commits going forward, such as `fix(providers): correct pagination cursor`. Do not commit or push unless explicitly requested.

PRs should explain the behavior change, link relevant issues, report validation commands and results, and include screenshots for UI changes. Keep credentials and local verification artifacts out of commits.
