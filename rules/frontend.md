---
paths:
  - "**/package.json"
  - "**/vite.config.*"
  - "**/tsconfig*.json"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.jsx"
---

# React / TypeScript / Vite

## Navigation
- Use LSP for symbol navigation, imports, and type information.
- Fall back to Grep only if LSP is unavailable.

## Commands
- Prefer package manager scripts (npm run, pnpm, yarn) over ad-hoc node invocations.
- Use absolute paths. Do not `cd` into project directories to run commands.
