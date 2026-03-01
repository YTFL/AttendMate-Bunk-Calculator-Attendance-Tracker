# Contributing to AttendMate

Thanks for taking the time to contribute! 🎉  
AttendMate is an open-source Flutter app for Android and every contribution — big or small — is appreciated.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Submitting Code](#submitting-code)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Code Style](#code-style)
- [Commit Messages](#commit-messages)
- [Pull Request Guidelines](#pull-request-guidelines)

---

## Code of Conduct

Be respectful, constructive, and collaborative. Harassment or hostile behaviour of any kind will not be tolerated.

---

## Getting Started

1. **Fork** this repository
2. **Clone** your fork: `git clone https://github.com/<your-username>/bunk-attendance.git`
3. **Set up** the development environment (see [Development Setup](#development-setup))
4. **Create a branch** for your change: `git checkout -b fix/my-bug-fix`
5. **Make your changes**, commit, and push
6. **Open a Pull Request** against the `main` branch

---

## How to Contribute

### Reporting Bugs

Please [open an issue](../../issues/new) and include:

- A clear, descriptive title
- Steps to reproduce the bug
- What you expected vs. what actually happened
- Android version and device model
- Screenshots or screen recordings if relevant

### Suggesting Features

[Open an issue](../../issues/new) with the label `enhancement` and describe:

- The problem you're trying to solve
- Your proposed solution or idea
- Any alternatives you considered

### Submitting Code

For anything beyond a trivial fix, **open an issue first** to discuss the change before investing time in a PR. This avoids duplicate effort and ensures the idea aligns with the project direction.

---

## Development Setup

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter | ≥ 3.9.0 (stable channel) |
| Dart | ≥ 3.9.0 |
| Android Studio / VS Code | Latest |
| Android SDK | API 24+ for testing |

### Running Locally

```bash
# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run

# Analyze for issues
flutter analyze

# Format code
flutter format .
```

### Building a Release APK

```bash
flutter build apk --target-platform android-arm64
```

---

## Project Structure

```
lib/
├── main.dart                  # App entry point, theme, providers
├── features/
│   ├── attendance/            # Attendance model & provider
│   ├── calendar/              # Attendance calendar screen
│   ├── home/                  # Home screen, update dialog
│   ├── semester/              # Semester management
│   ├── settings/              # More tab, setup guide, what's new
│   └── subject/               # Subject add/edit/import screens
├── services/
│   ├── database_service.dart  # SQLite operations
│   ├── notification_service.dart
│   └── update_service.dart
└── utils/                     # Shared utilities & extensions
```

---

## Code Style

- Follow standard **Dart/Flutter conventions** (`dart format`, `flutter analyze` must pass with no issues)
- Use `const` constructors wherever possible
- Keep **UI and business logic separate** — widgets should not contain data fetching or DB calls
- State management via **Provider** (`ChangeNotifier`) — don't introduce new state management libraries
- Use `async`/`await` with proper error handling (`try`/`catch`, `mounted` checks before `setState`)
- Name things clearly — prefer descriptive names over short abbreviations

---

## Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) style:

```
<type>: <short summary>

feat: add collapsible subject cards
fix: appbar scroll tint in dark mode
chore: bump version to 1.4.7
docs: update contributing guide
refactor: extract attendance logic into service
```

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `chore`, `test`

---

## Pull Request Guidelines

- **One PR per logical change** — don't bundle unrelated fixes
- **Describe your changes** in the PR body — what, why, and how
- **Run `flutter analyze`** before submitting — PRs with analysis errors won't be merged
- **Test on a real device or emulator** (minimum API 24)
- Link to the relevant issue using `Closes #<issue-number>` in the PR description
- Keep PRs focused and reasonably sized — large PRs are harder and slower to review

---

## Questions?

Open an issue or start a discussion in the repository. Happy contributing! 🚀
