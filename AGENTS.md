# Repository Guidelines

## Project Structure & Module Organization
Source lives in `src/`. `main.zig` bootstraps the executable and imports the reusable module exposed through `root.zig`. Domain code is grouped under `src/components/` for gameplay features and `src/ecs/` for entity-system primitives. Build scripts sit in `build.zig` and `build.zig.zon`. Generated artifacts land in `zig-out/`; keep it ignored from commits.

## Build, Test, and Development Commands
- `zig build`: compiles the project and installs artifacts into `zig-out/`.
- `zig build run -- <args>`: builds (if needed) and executes the app with optional runtime arguments.
- `zig build test`: runs both module and executable test suites defined in `build.zig`.
Use `zig build -h` to inspect additional targets or to override `-Doptimize` and `-Dtarget` when cross-compiling.

## Coding Style & Naming Conventions
Run `zig fmt src` before submitting to ensure canonical formatting (Zig defaults to 4-space indentation). Prefer `CamelCase` for struct/enum names, `snake_case` for functions, and uppercase with underscores for compile-time constants. Keep files focused: ECS primitives in `src/ecs/`, gameplay components in `src/components/`, and public exports declared or re-exported through `root.zig` for downstream imports.

## Testing Guidelines
Author tests using Zig `test` blocks colocated with the code they validate. Choose descriptive test names (e.g., `test "component registry registers once"`). Run the full suite with `zig build test` before every pull request; aim to cover new control flow branches and error paths. If run-time args influence behavior, add scenario notes to the PR so reviewers can reproduce locally with `zig build run -- ...`.

## Commit & Pull Request Guidelines
Follow the existing history: short, lowercase, present-tense summaries (`component registry`). Group related changes into a single commit; split refactors from behavioral updates where practical. Pull requests should include: purpose statement, outline of major code paths touched, validation notes (tests, manual steps), and linked issues or design docs when available. Add screenshots or clips if gameplay or rendering changes are made.

## Configuration Notes
Zig dependencies are declared in `build.zig.zon`. When adding packages, note version hashes and document any required environment variables or shader assets in the PR body. Use `.env.example` (if added later) to illustrate runtime configuration without leaking secrets.
