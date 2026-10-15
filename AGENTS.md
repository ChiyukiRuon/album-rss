# Repository Guidelines

## Project Structure & Module Organization

Album RSS is an image-focused RSS client connecting directly to Miniflux and Google Reader-compatible services; it has no custom backend.

- `apps/web/`: React and Vite application. Pages, reusable components, utilities, and state live under `src/`; static assets belong in `public/`. Shared styles live in `src/styles/`.
- `packages/core-ts/`: shared article, subscription, and image models.
- `packages/providers-ts/`: RSS service adapters, authentication, and pagination.
- `contracts/`: schema and fixture placeholders for cross-platform compatibility.
- `apps/ios/` and `swift/`: documentation placeholders for future native development.
- `scripts/`: local Miniflux connectivity and browser verification utilities.

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

## Coding Style & Naming Conventions

Use strict TypeScript, explicit type-only imports, and existing workspace package boundaries. Follow `.editorconfig`: UTF-8, LF, two-space indentation; Python uses four spaces. Prettier enforces single quotes, no semicolons, trailing commas, and a 100-character print width.

Name React components in PascalCase (`GalleryCard.tsx`), hooks with `use`, and utilities in camelCase. Keep component styles in adjacent `*.module.css` files. Write human-facing documentation and comments in Chinese; agent-facing instructions in English.

## Testing Guidelines

Place Vitest tests beside implementation files as `*.test.ts`, using `describe`, `it`, and `expect`. Mock network requests in provider tests. Cover changed behavior and regressions, especially pagination, state transitions, and layout calculations. No coverage threshold is configured. Run targeted suites with `pnpm --filter @album-rss/providers test`, then relevant workspace checks. Local integration scripts require machine-specific services and paths; inspect them before running.

## Commit & Pull Request Guidelines

The single baseline commit uses a Chinese description and establishes no recurring convention. Use Conventional Commits going forward, such as `fix(providers): correct pagination cursor`. Do not commit or push unless explicitly requested.

PRs should explain the behavior change, link relevant issues, report validation commands and results, and include screenshots for UI changes. Keep credentials and local verification artifacts out of commits.
