# Contributing to Fluent Editor

Thank you for your interest in contributing to Fluent Editor! This document covers everything you need to get started.

## Prerequisites

- **Flutter** >= 3.24.0
- **Dart** >= 3.8.0
- **Git** with submodule support

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork **with submodules**:

   ```bash
   git clone --recurse-submodules https://github.com/<your-username>/fluent-editor.git
   ```

   If you already cloned without submodules, initialize them:

   ```bash
   git submodule update --init --recursive
   ```

3. Install dependencies:

   ```bash
   flutter pub get
   ```

4. Generate serialized code (required after modifying model annotations):

   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

## Project Structure

| Directory | Description |
|---|---|
| `lib/models/` | Data models (Paragraph, Fragment, Link, FluentTable, etc.) |
| `lib/handlers/` | Input event handlers (keyboard, mouse, clipboard, IME) |
| `lib/services/` | Export/import services (DOCX, ODT, PDF, HTML, Markdown) |
| `lib/widgets/` | Flutter widgets for rendering the editor UI |
| `lib/controllers/` | Editor controller logic |
| `lib/undo_redo/` | Undo/redo manager and action types |
| `lib/cursor.dart` | Cursor and selection model |
| `lib/selection_manager.dart` | Selection state management |
| `lib/styles.dart` | Style definitions and theme |
| `lib/localization/` | Localization and labels |
| `lib/utils/` | Utility functions and helpers |
| `test/` | Unit and widget tests mirroring `lib/` structure |
| `example/` | Example app demonstrating FluentEditor usage |

## Coding Standards

- Follow the rules defined in `analysis_options.yaml` (based on `flutter_lints`).
- Run `flutter analyze` before committing — there should be **zero warnings**.
- **Never** manually edit generated files (`*.g.dart`). Modify the source and re-run `build_runner`.
- Keep the code style consistent with the existing codebase.
- Comments in English.

## Testing

- Run the full test suite before submitting a PR:

  ```bash
  flutter test
  ```

- Add tests for any new feature or bug fix. Place them in the appropriate subdirectory of `test/` mirroring the `lib/` structure.
- Use `flutter test test/<path_to_test>` to run a specific test file.

## Submitting Changes

### Branch Naming

Use descriptive branch names prefixed by the change type:

- `feat/<short-description>` — new features
- `fix/<short-description>` — bug fixes
- `docs/<short-description>` — documentation changes
- `refactor/<short-description>` — code refactoring

### Commit Messages

- Use the **imperative mood**: "Add table cell merging" (not "Added" or "Adds").
- Keep the subject line under 72 characters.
- Reference issue numbers when applicable: `Fix cursor doubling on link navigation (#42)`.

### Pull Request Checklist

Before opening a PR, make sure:

- [ ] `flutter analyze` passes with no warnings
- [ ] `flutter test` passes
- [ ] New tests are added for new functionality
- [ ] Generated code is up to date (`build_runner` was run if needed)
- [ ] `CHANGELOG.md` is updated if the change is user-facing
- [ ] The PR description explains the **what** and **why** of the change

### Pull Request Process

1. Push your branch to your fork.
2. Open a pull request against the `main` branch.
3. Provide a clear description of the changes and link any related issues.
4. Address review feedback by pushing additional commits (avoid force-pushing during review).

## Reporting Bugs

Use [GitHub Issues](https://github.com/exusr/fluent-editor/issues) to report bugs or request features.

For bug reports, include:

- **FluentEditor version** (check `pubspec.yaml`)
- **Flutter version** (`flutter --version`)
- **Platform** (web, Windows, Linux, macOS, iOS, Android)
- **Steps to reproduce**
- **Expected vs. actual behavior**
- **Minimal code sample** or error output if possible

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
