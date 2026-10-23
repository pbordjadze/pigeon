# Pigeon — engineering notes

An iPhone navigation app (iOS 26, Swift 6, SwiftUI) that weans you off it: each saved route gives
a little less help on every clean drive, until you drive it without help. This file is the map and
the rules.

## Map

- `Package.swift`: `PigeonCore` and `PigeonCoreTests`. The Xcode project builds PigeonCore from
  this package (local reference `..`); its iOS 26 / macOS 15 platforms are a floor.
- `Sources/PigeonCore`: the portable, dependency-free logic (builds on Linux too). `Geo` (distance,
  bearing, a local flat frame), `RouteLine` (a saved route's path; matching a point to it),
  `RouteTracker` (one drive: on the route, left it, arrived; its doc comment is the off-route rule).
- `Tests/PigeonCoreTests` (Swift Testing; `TestRoutes` lays routes and drives out in metres).
- `App/`: `Pigeon.xcodeproj` (synchronized folders: adding files needs no project edit), `Pigeon/`
  (`App/` the app and its root, `Resources/` the catalogs, privacy manifest and assets),
  `PigeonTests` (Swift Testing), `PigeonUITests` (XCTest), `Config/Info.plist` (background modes,
  export compliance; the rest is the target's `INFOPLIST_KEY_*` settings).
- `ci/` and `.github/workflows/ci.yml`: jobs `core` (Linux: PigeonCore tests, warnings, string
  catalog), `apple` (`iphone` on every push: Debug build, screenshots, unit and UI tests, Release
  check; or `compile`), `report` (`ci/report.py` writes `STATUS.md`). The scripts came from
  `pbordjadze/paint-by-number`'s `ci/` and keep its shape.
- `tools/`: `swift.sh` (SwiftPM in Docker), `strings_check.py` (its docstring is the manual).
- `PRIVACY.md`: the privacy policy, word for word what the app does (below).
- Plans, briefs and the backlog are not committed here: they live in the private
  `painting-company` repository (Pigeon is its row 121). A commit message says what changed and
  why, and cites a row by number; it quotes no one and names no one.
- No real person's routes or places (homes, addresses, coordinates from a drive) in the repository,
  its fixtures, GPX files, screenshots, commits or issues: test routes are made up or run between
  public landmarks.

## Safety (hard rules)

The owner is legally responsible for this app. When a design choice trades safety for the idea,
safety wins and the choice goes to the owner.

- Nothing to read or touch while the car moves: spoken guidance and one glanceable thing on
  screen. Controls that need reading or typing are locked while moving.
- The screen is the main surface (and CarPlay, when it comes): stages fade what it shows; the
  voice is optional and fades the same way.
- Leaving the route brings full guidance back at once and reroutes, at every stage
  (`RouteTracker` reports `.left`; it leans towards a false alarm over a missed one). A new or
  unfamiliar route starts at full guidance.
- Sketching a route from memory, when it comes, is never offered while driving.
- A change to `RouteTracker`'s thresholds or rules needs a test of the drive it changes.

## Privacy (hard rules)

No account, no server, no analytics, no ads, no third-party code. The app's own data stays on the
device. What MapKit sends to Apple (a route's start and destination when saved, a reroute, map
tiles) is in `PRIVACY.md`; a change to what leaves the phone changes `PRIVACY.md`,
`Resources/PrivacyInfo.xcprivacy` and `ShipHygieneTests` together. A required-reason API
(UserDefaults, file timestamps, disk space, boot time) adds its category and reason to the
manifest. Location is While Using only, with background updates during a drive.

## Working here (Linux, no Xcode)

| Task | Command |
| --- | --- |
| PigeonCore tests | `tools/swift.sh test` |
| String catalog check | `python3 tools/strings_check.py` |

- `App/` compiles only on CI: after editing an App Swift file, re-read it whole and check its
  imports (`MemberImportVisibility`), actor isolation at each boundary, API names and signatures
  against iOS 26 / Swift 6.2, and every call site of anything renamed.
- Compiler warnings fail CI (`ci/warnings.sh`, on the Linux and Xcode build logs; `main` has
  none): fix a new one, never silence it.
- Simulated drives: the simulator's location follows a GPX route (`xcrun simctl location`), and
  PigeonCore's tests drive `TestRoutes` fix by fix.
- Scratch output goes outside the repo. Keep a diff to what the task needs.

## App rules

- Deployment target iOS 26.0, iPhone only. Build with Xcode 26.6 (CI). Swift 6 with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency: app types are MainActor
  by default; mark pure helpers `nonisolated` and CPU-heavy async work `@concurrent`. PigeonCore
  is a separate module (nonisolated). The test targets have neither setting: suites that touch app
  types are `@MainActor`.
- `MemberImportVisibility` is enabled: every file that touches members of a type from another
  module imports that module itself (`import PigeonCore`, `import CoreLocation`, …).
- Closures handed to system APIs that call back on arbitrary threads (Core Location delegates,
  AVFoundation, NotificationCenter with a queue) must not be MainActor-isolated: form them in
  `nonisolated` code or they trap at runtime under Swift 6.
- System controls stay system controls (Liquid Glass), SF Symbols, Dynamic Type, dark mode,
  VoiceOver labels and values, Reduce Motion.
- Identity: the display name is the working name, Pigeon. The product name, the icon and the App
  Store listing are the owner's to decide; never change them unasked.
- Localization: every user-facing string of the app target lives in
  `Resources/Localizable.xcstrings` (English first), the Info.plist texts in
  `Resources/InfoPlist.xcstrings` (keyed by the plist key); PigeonCore stays English and returns
  values, not sentences. Three code forms, and nothing else: a SwiftUI literal with no
  interpolation (`Text("Done")`: the literal is the key); `String(localized: "key", defaultValue:
  "…\(x)…", comment: "…")` for an interpolation, a count or a non-SwiftUI destination (dotted keys;
  the comment says where it shows and what the arguments are); `String(localized: "literal")` for
  a plain string. `Text(someString)` is verbatim, so build such strings with the second or third
  form first. Counts are catalog plurals; distances, durations and numbers go through
  `.formatted(...)` (`Measurement` for distances, in the user's units), never concatenation. A new
  string needs its catalog entry written by hand (`"comment"`, `"extractionState": "manual"`; an
  explicit key also `localizations.en`): Xcode extracts nothing. `tools/strings_check.py` (CI)
  fails on drift. Spoken guidance is localized the same way.
- Demo scenarios: `-demo <name>` (`DemoMode`; scenarios listed on the views that render them). A
  screenshotted scenario is one `name@seconds` line of `ci/scenarios.txt` and calls
  `DemoMode.markReady()` once its content is on screen; `-dark` and `-long-text` in a name pick dark
  appearance and doubled strings. Demo code is `#if DEBUG`, and `ci/check_release.sh` fails if it
  shows up in the Release binary.
- Done means: a test for each new behaviour in the right target, a demo scenario for any new
  screen, catalog entries for its strings, VoiceOver, Dynamic Type and dark mode for every new
  control, and this file's pointers kept current. No stubs or flags hiding unfinished work.

## CI feedback loop (no Xcode locally)

1. Before a push, look at the Actions runs of both this repository and
   `pbordjadze/paint-by-number`: the 5 macOS runners are shared. One branch at a time while
   paint-by-number's `main` runs.
2. Commit, push to a branch (`git push -u origin HEAD:<branch>`; CI runs on every branch). Compile
   first: `[compile]` in a branch commit's message runs only the Debug and Release builds, the
   Release check and the warnings gate on one runner, no simulator.
3. Run `CI_BRANCH=<branch> ci/fetch.sh <sha> <outdir>` in the background; it waits for the report
   CI publishes to the ref `refs/ci-shots/<branch>` (not fetched by a clone) and unpacks it:
   `STATUS.md` (job results, failed steps, test counts, failed tests with their first message,
   scenarios that never signalled readiness, crashes), logs, `core/`, and per job `errors.txt`,
   `shots/*.png`, `*-app.log`, `test-app.log`, test results and `attachments/`.
4. Read errors and screenshots, fix, repeat. Batch fixes: a newer push to the same branch cancels
   the older run.

**Branches.** `main` is the default branch. Work on `claude/<topic>` branches and merge into
`main` once CI is green and a reviewer that didn't write the change has read
`git diff origin/main...HEAD`; the merge commit lists what the review found and what was fixed.
Docs-only commits carry `[skip ci]`; a commit message holds CI's tags (`[skip ci]`,
`[compile]`) only to mean them.

## Conventions

- Swift 6 language mode, strict concurrency. Core types are `Sendable` value types.
- Distances in metres, times in seconds, angles in degrees clockwise from north, in PigeonCore;
  the app converts for display.
- Comments explain *why*, sparingly. No dead code, no TODO litter.
