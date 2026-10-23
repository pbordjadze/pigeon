# Pigeon

An iPhone navigation app that helps you learn the routes you drive, so you need it a little less each time. Work in progress.

## How it works

Save a route you drive often. Each route sits at one of four stages, and each clean drive (you
arrive without leaving the route) moves it up one: full turn-by-turn directions, then landmarks
instead of distances, then a short cue only at each turn, then silence. Leave the route at any
stage and full directions come back at once. When you can drive it in silence, the route is
yours.

## Privacy

No account, no server, no analytics, no ads. Your routes and drives stay on your iPhone. See
[PRIVACY.md](PRIVACY.md).

## Building

Swift 6, SwiftUI, iOS 26. `PigeonCore` (the route matching and guidance logic) builds and tests on
Linux: `tools/swift.sh test`. The app builds on CI; see [CLAUDE.md](CLAUDE.md).
