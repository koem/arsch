# AGENTS.md – Arsch (multiplayer card game)

Context and findings for coding agents. User-facing setup docs are in `README.md` (German).

## Layout

| Dir       | What | Tests |
|-----------|------|-------|
| `shared/` | Game rules (`lib/src/card.dart`, `lib/src/game.dart`) incl. move log, swaps, `botMove`, `botDiscard`, `timeoutMove`, JSON save/load, used by app and server | `test/game_test.dart` (28 tests) |
| `server/` | WebSocket game server, `bin/server.dart`, port from env `PORT` (default 8080); server-side bots, spectators, invite page, persistence | `test/` (11 tests, real server processes) |
| `app/`    | Flutter app (Android/iOS), `lib/` | `test/client_test.dart` (11 tests) |

The project is not a git repository.

## Toolchain (installed locally, NOT on PATH)

```bash
export PATH=~/.local/share/flutter-sdk/bin:$PATH          # Flutter stable 3.50.0, Dart 3.14.0
export ANDROID_HOME=~/.local/share/android-sdk
export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH
```

- Standalone Dart SDK 3.14.1 is also in `~/.local/share/dart-sdk-dl/dart-sdk/bin` (Flutter's bundled Dart works as well).
- Android SDK: cmdline-tools (`sdkmanager` now wraps the new `android` CLI; package names
  in `--list` use `/`, but installing with `;` works), platform-tools, `platforms;android-36`,
  `platforms;android-37.0`,
  `build-tools;37.0.0`, plus NDK + CMake pulled in by Gradle. Licenses accepted.
- JDK 21 is the system Java. `/dev/kvm` is usable by the user (ACL); `DISPLAY=:0`.
- Emulator: `emulator` + `system-images;android-36;google_apis;x86_64` installed, AVD `arsch_test` (pixel_7).
  Start: `emulator -avd arsch_test -no-snapshot-save -no-boot-anim &`, then
  `adb install -r app/build/app/outputs/flutter-apk/app-release.apk` and
  `adb shell monkey -p de.example.arsch -c android.intent.category.LAUNCHER 1`.
  Second device: AVD `arsch_test2`, start with `-port 5556`. Address the devices with `adb -s emulator-5554|5556`.
  Text input via `adb shell input` races with focus changes, so leave about 1.5 s between tap/text steps.
  Screenshot: `adb exec-out screencap -p > shot.png` (1080x2400). The emulator window is on the user's
  display, and the user may be using it, so don't send input events while they are.
- Shell gotcha: `pkill -f`/`pgrep -f` with a pattern that appears in your own command line kills
  the agent's shell (exit 144). Kill by PID, or anchor the pattern, e.g. `pgrep -f "^/tmp/arsch-server$"`.
- Not installed: Chrome, Linux desktop toolchain (clang/cmake), Xcode (iOS needs a Mac).

## Commands

```bash
cd shared && dart pub get && dart analyze && dart test
cd server && dart pub get && dart analyze && dart test && dart compile exe bin/server.dart -o /tmp/arsch-server
cd app && flutter pub get && flutter analyze && flutter build apk --release
```

- APK output: `app/build/app/outputs/flutter-apk/app-release.apk` (~50 MB, arm64/armv7/x86_64).
- First Gradle build took ~37 min (NDK/CMake downloads); incremental rebuilds ~45 s.
  Run long builds in the background.

## Minimum OS versions

Android 7.0 (minSdk 24, from Flutter's default; plugins need ≤ 24), iOS 15.0
(`IPHONEOS_DEPLOYMENT_TARGET` from `flutter create`; plugins need ≤ 13). `compileSdk = 37` is pinned in
`android/app/build.gradle.kts` because flutter_local_notifications 23 and androidx.core 1.19 need it.
It doesn't affect which devices can install the app. targetSdk is 36.

## Current status (2026-11-18)

- **Tests, all green:** `shared` 28 (incl. 200 bot-only full games, swaps, save/load), `app` 11,
  `server` 11 in `server/test/` (~5 min; each test spawns a real compiled server on a free port with its own
  temp `DATA_DIR`; helpers in `test/support.dart`; `dart_test.yaml` sets `concurrency: 1`, because parallel
  runs made the timing-sensitive tests flaky). Server test files: `lobby_test` (bots, spectators),
  `discard_test` (Arsch discard by a human and by a bot; plays real games, so it's the slowest), `turn_clock_test`
  (timeouts with `TURN_TIMEOUT=1`, cleanup), `persistence_test` (SIGTERM / kill -9 restarts, broken file),
  `http_test` (invite page, host validation, IPv4+IPv6, TLS/wss; needs `openssl`).
- Rule "Arsch tauscht" (user request, 5 players only, from round 2): the previous Arsch picks up the 2 middle
  cards, then must `discard` any 2 cards (phase `discarding`, `current` = Arsch) before play starts.
  Only the Arsch gets `pickedUp`. A bot Arsch discards its 2 lowest cards.
- Titles (user request): „Präsi“, „Vize-Präsi“, „Mitte“, „Vize-Arsch“, „Arsch“ (with hyphens; `titleFor` in shared).
- Seen working on the emulator: home screen with logo text, lobby with bots, share sheet, game screen with
  card badges + history panel + remaining-time banner, „Ich schiebe“ disabled while cards are selected,
  spectator view, app icon in the launcher, rejoin after a server restart. NOT seen on a device: background
  notification / 3-h reminder, opening an invite link from the browser (does Chrome follow the auto-redirect?),
  the result overlay with swap stars, the discard screen, and the bigger icon (after the inset fix).

## Server protocol (JSON over WebSocket)

Client → server `type`: `create{name}`, `join{name,code}`, `rejoin{code,token}`, `addBot`, `removeBot{seat}`, `discard{cards:[2 ids]}`,
`start` (host = seat 0, needs 4–5 players), `play{cards:[ids]}`, `pass`, `nextRound`, `newGame`, `abort`, `leave`.
Server → client: `joined{code,token}`, `state{...}` (per-seat view, only own `hand`), `error{message,reason?}`.

- `state` also has `players[].bot`, `spectators` (count), `spectator`, and `recent` = moves since the
  recipient's last own move this round (`[{seat,cards,endsTrick}]`, max 12). Spectators get the whole round, uncapped.
- `phase` can be `discarding` (see the rule above). During it, `play`/`pass` fail and so does `nextRound`.
- Swap (user request): each condition alone is a swap: (a) a player plays all their cards with no other
  player's *play* in between (passes are fine); (b) the previous round's Arsch finishes first. Both together
  = double swap (2 swaps, +2). Each swap gives +`swapBonus` (1). `ArschGame.swapsThisRound` (seat → 1|2),
  `swapCounts` (whole game) and `roundPoints` (last round incl. bonus) are persisted. Older saves stored
  `swapsThisRound` as a list, and that still loads. State `players[]` has `swaps`, `roundSwaps`, `roundPoints`.
  The app shows `★`/`★★`. Scores are no longer
  zero-sum: sum(scores) == sum(swaps).
- Round results (user request): the app snapshots the state when a round ends (`GameClient.lastResult`)
  and shows `ResultOverlay` (in `main.dart`, above every screen) until the player closes it, even if
  the next round or the lobby is already running. After it's closed, the game screen offers "Ergebnis" + "Nächste Runde".
- Invite link (user request): `arsch://join` only fills in the room code (and server) and never auto-joins.
  The invite page `/r/CODE` immediately redirects via JS (Android: `intent://join?...#Intent;scheme=arsch;end`,
  others: `arsch://`), and the button stays as a fallback. Host header is validated (`[A-Za-z0-9.-[]:]`), else 400.
  Not verified on a device: whether Chrome follows the auto-redirect without a tap. Verified Android App
  Links / iOS Universal Links (open app without the browser) need a real https domain + assetlinks/AASA.
- Logo: `app/assets/logo.png` (from the user, 286×300, transparent) is shown on the home screen. App icons are generated
  with `dart run flutter_launcher_icons` (config in `app/pubspec.yaml`) from `assets/icon/icon_full.png` (logo
  on #0F3D24, 1024², no alpha) and `icon_foreground.png` (adaptive foreground, logo at 60%). `adaptive_icon_foreground_inset: 0` is required, because the tool's default 16% inset made the logo tiny (~41%). Both were made with PIL.
  The iOS 1024 icon is upscaled ~3.5× from the small source, so a bigger original would look sharper. Android notifications
  use `drawable-*/ic_notification.png` (white silhouette from the logo's alpha).
- Startup: the app shows a spinner until `GameClient.init` has loaded prefs (fixes the empty name field).
- Turn clock (user request): every human turn (play or discard) has `TURN_TIMEOUT` (default 24 h). The state
  carries `turnSecondsLeft` + `reminderSecondsBefore` (relative to avoid clock skew; absent on bot turns).
  On expiry the server calls `ArschGame.timeoutMove`: pass, or the lowest single card when leading, or
  `botDiscard` when discarding. Those moves have `timedOut: true` in `recent`. The app schedules a local
  notification at deadline − `TURN_REMINDER` (default 3 h) with `zonedSchedule` (inexact, so it can be minutes late).
  It works with the app closed, but only if the app saw the turn start (no push).
- Cleanup: lobby without connected humans after 15 min. Running rounds are NEVER removed (they finish via
  timeouts + bots, and bots no longer pause when nobody is connected). roundOver/gameOver without
  connected humans are removed after `FINISHED_GAME` (default 3 days). Disconnected spectators stay listed so they can rejoin.
- Production target (user): `koem2.mooo.com:2284` (FreeDNS/afraid.org name, public IPv4 84.146.202.254 on
  2026-11-18, IP changes, so DynDNS). The app default is `ws://koem2.mooo.com:2284` (`GameClient.defaultServerUrl`; for
  emulator tests build with `--dart-define=ARSCH_SERVER=ws://10.0.2.2:8080`, or change it under Server-Einstellungen).
  The server binds dual-stack (`anyIPv6`, `v6Only: false`). Optional TLS: `TLS_CERT`/`TLS_KEY` (PEM), then `wss://`.
  Docker: `Dockerfile.server` (PORT=2284, VOLUME /data, ~11 MB, amd64), root `docker-compose.yml` (builds),
  `.dockerignore`. `dist/` holds `arsch-server.tar.gz` (`docker save`), an image-only `docker-compose.yml` and
  `INSTALL.md` for the box. Docker is installed on the dev PC (the user is in group `docker`; until re-login use `sg docker -c "..."`).
  Verified: the container passes the lobby/spectator tests and keeps rooms across `docker restart`.
- Live server on 8080: binary `/tmp/arsch-server`, `DATA_DIR=~/.local/share/arsch-data` (rooms survive restarts).
- Persistence: the server saves all rooms (players + tokens, spectators, the full `ArschGame.toJson`,
  turn deadline) to `$DATA_DIR/rooms.json` 300 ms after each change (atomic write via tmp + rename) and on
  SIGTERM/SIGINT. It loads them on start, and the turn clocks continue with their real remaining time. A broken file is
  moved aside as `rooms.json.broken-<ts>`. Docker: `DATA_DIR=/data`, `VOLUME /data`.
- Spectators get `you: -1`, `spectator: true` and no hand. Any game action from them fails with "Du schaust nur zu.".
- `join` makes you a spectator if the game is running or 5 humans are seated. In the lobby, spectators
  take free seats automatically (bots make way). Humans always sit before bots, so seat 0 (host) is human.
- Bots run on the server (`botMove` in shared, 1.2 s delay). They pause while no human is connected.
  A lobby with only bots left is deleted.
- `GET /r/CODE` returns an HTML invite page with a button to `arsch://join?code=CODE&server=<ws-url>`
  (server URL from the `Host` / `X-Forwarded-Host` / `X-Forwarded-Proto` headers). Any other GET returns a status text.

## Changes made by agents (vs. the original source)

1. `app/lib/**`: `package:flutter/material.dart` was replaced by `package:material_ui/material_ui.dart`
   (Flutter ≥3.47 deprecates the old import). Added the `material_ui: ^1.11.1` dependency.
2. Ran `flutter create --project-name arsch --org de.example --platforms android,ios .` in `app/`
   (as the README says). It generated `android/`, `ios/`, `analysis_options.yaml`, `app/README.md`, `arsch.iml`.
   The sample `test/widget_test.dart` was deleted.
3. `android/app/src/main/AndroidManifest.xml`: added the `INTERNET` permission. `flutter create`
   only puts it in the debug/profile manifests, so release builds could not reach the server.
4. Added the `flutter_lints` dev dependency (required by the generated `analysis_options.yaml`).
5. Bots, move history, card-count badges, turn alerts, share links, spectators (see above).
   - New deps: `app_links`, `share_plus`, `flutter_local_notifications`.
   - Android: an `arsch://join` intent filter, core library desugaring, `compileSdk = 37`.
   - iOS: `CFBundleURLTypes` with the `arsch` scheme in `Info.plist`.
   - New files: `app/lib/turn_alert.dart`, `app/lib/widgets/share_room.dart`, `app/test/client_test.dart`.

A backup of `app/` from before steps 2–4 is in `/tmp/arsch-app-backup` (temporary).

## Open items / gotchas

- The release APK is signed with the debug key, and the app ID is `de.example.arsch`. Both must be
  changed before publishing to a store.
- The default server URL is `ws://10.0.2.2:8080` (it reaches the host from the Android emulator).
  You can override it at runtime under „Server-Einstellungen“ or at build time with
  `--dart-define=ARSCH_SERVER=wss://…`. Production should use `wss://`.
- Cleartext `ws://` on real Android devices is untested.
- Turn notifications only work while the app process still has its WebSocket open. Android/iOS suspend
  backgrounded apps, and a closed app gets nothing. Reliable notifications need real push (FCM/APNs):
  a Firebase project, device tokens sent to the server, and the server sending pushes.
- Invite links: `http://<server>/r/CODE` is only useful to others if the server address is reachable
  for them (not `10.0.2.2`/`localhost`). Tapping the page button needs the app installed. There are no
  verified Android App Links / iOS Universal Links (they'd need a domain + `assetlinks.json` / AASA).
- `flutter pub outdated`: 2 packages have newer versions that the current constraints don't allow.
