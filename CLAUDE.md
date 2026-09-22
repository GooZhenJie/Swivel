# CLAUDE.md — Swivel (GooZhenJie fork)

Guidance for agents working in this checkout. Read this before touching anything.

## What this checkout is

A fork of [jspanji/Swivel](https://github.com/jspanji/Swivel) (macOS menu bar app that switches
Claude Desktop accounts) carrying three local commits. It is the app the owner actually runs, not
a scratch clone.

| Remote | URL | Push |
|---|---|---|
| `upstream` | jspanji/Swivel | **disabled** (`set-url --push DISABLED`) — never re-enable |
| `origin` | GooZhenJie/Swivel | allowed |

Working branch: **`feature/auto-mirror-on-switch`**. `main` tracks `upstream/main` and must stay
untouched. Never commit to `main`.

## The local commits

| Commit | What it does |
|---|---|
| `feat(switch): run cc-mirror after each switch and show its result` | `SessionMirror.swift` runs `~/bin/cc-mirror-sessions --quiet` between restoring the target profile and launching Claude, and records the result for the popover |
| `feat(switch): point Claude Usage at the profile of the same name` | `UsageTrackerSync.swift` repoints the Claude Usage menu bar app after Claude launches |
| `chore(build): disable Sparkle automatic checks in local builds` | `SUEnableAutomaticChecks=false` in `build-app.sh` |

Fork-owned files (upstream never touches them): `Sources/SwivelCore/SessionMirror.swift`,
`Sources/SwivelCore/UsageTrackerSync.swift`, `Tests/SwivelCoreTests/SessionMirrorTests.swift`,
`Tests/SwivelCoreTests/UsageTrackerSyncTests.swift`, this file, `AGENTS.md`.

Everything else is upstream code with small insertions. **Keep insertions minimal and localized** —
that is what keeps rebases cheap. Conflict-prone spots:

- `ProfileManager.swift` — two calls inside `switchTo()`, two record accessors
- `PopoverRootView.swift` — two rows in `body`, two groups of computed properties
- `build-app.sh` — the `SUEnableAutomaticChecks` key in the generated Info.plist

## Runtime dependencies outside this repo

| Dependency | Detail |
|---|---|
| `~/bin/cc-mirror-sessions` | The executed copy of the mirror script. **Not** `/Volumes/T9/Documents/www/cc-mirror-sessions` — that clone is for review only. `~/bin` is on the internal disk so it works when the T9 drive is unplugged |
| `/usr/bin/python3` | Hardcoded in `SessionMirror.swift`. System Python is **3.9.6**, and a GUI app gets no pyenv/homebrew PATH. Anything the mirror script uses must stay 3.9-compatible |
| Claude Usage app | Bundle id `HamedElfayome.Claude-Usage`. Profiles live in its UserDefaults under `profiles_v3` (JSON array with `id`/`name`), active one under `activeProfileId` |
| `usage-profile-map.json` | Optional, at `~/Library/Application Support/Swivel/usage-profile-map.json`. Maps Swivel profile name → Claude Usage profile name. Unneeded today: both apps use `Personal` and `RAS` |

Pairing is **by profile name, never by hardcoded UUID**. Do not reintroduce UUIDs into the code.

Result records the popover reads:

- `~/Library/Application Support/Swivel/session-mirror.json`
- `~/Library/Application Support/Swivel/usage-tracker.json`

## Build, test, install

Tests (the bare `./run-tests.sh` **fails** on this machine — Command Line Tools only, so the
swift-testing interop dylib is not on the default rpath; this is an environment issue, not a
regression):

```bash
./run-tests.sh -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

Build and install: prefer `swivel-update --reinstall` (see below). Manually, `./build-app.sh` writes
`build/Swivel.app`; installing means quitting the running app, replacing `/Applications/Swivel.app`,
and reopening it. Never use `./build-app.sh --install` — it `rm -rf`s the installed app instead of
moving it to the Trash.

Builds here are **ad-hoc signed** (no Developer ID on this machine). That is expected. Consequences:

- The reported version is whatever `build-app.sh` hardcodes (1.1.0), which can read older than the
  official release. Ignore it.
- Automatic update checks are off **on purpose**: an upstream release installed by Sparkle would
  silently replace this build and drop all three commits. Do not re-enable them, and do not tell the
  owner to use "Check for Updates…".
- After every rebuild the app must be reinstalled, or `/Applications` keeps running the old binary.
  Nothing will warn about this.

## Updating from upstream

Use the wrapper, which refuses to run on a dirty tree or the wrong branch:

```bash
swivel-update              # fetch, rebase, test, build, install
swivel-update --reinstall  # also rebuild when upstream has nothing new
swivel-update --push       # additionally force-with-lease push to origin
```

It lives at `~/bin/swivel-update`. Pushing is opt-in because a rebase rewrites hashes.

**On a rebase conflict: stop.** The script leaves the rebase in progress and builds nothing. Report
which files conflict and what each side changed, then let the owner decide. Do not pick a side, do
not use `-X ours/theirs`, do not `--abort` without being asked.

## Verification obligations

The 37 tests cover parsing, name matching, record round-trips and the mirror subprocess contract.
They do **not** cover:

- the popover rows rendering (SwiftUI layout)
- the Claude Usage side effects — quit, write `activeProfileId`, relaunch

A green build or a green test run is therefore **not** evidence that a switch works. Verify a real
switch instead:

```bash
log show --last 30m --info --predicate 'subsystem == "com.swivel.app"' | grep -E "SessionMirror|UsageTrackerSync"
```

and check the two popover rows (`Code sync ✓ …`, `Usage tracker → …`). A switch quits and relaunches
Claude Desktop, which closes the owner's current Claude Code conversation — say so before asking for
one, and never trigger a switch unprompted.

## House rules that apply here

- Never push to `upstream`, never open a PR against upstream without being asked. If a PR is ever
  wanted, the two feature commits need an opt-out setting first, the Sparkle commit and these docs
  must be dropped, and `CONTRIBUTING.md` requires one change per PR plus a manual test plan.
- No AI attribution in commit messages, no `Co-Authored-By: Claude`, no "Generated with" footers.
- Commit messages follow Conventional Commits as specified in
  `/Volumes/T9/Documents/www/rasa-projects/.cursorrules`; read that file before writing one.
- No code comments unless the owner explicitly asks for them.
- Confirm before side effects: deploys, pushes, installs over the running app, and anything touching
  another app's data.

## Related

`/Volumes/T9/Documents/www/cc-mirror-sessions` — the mirror script this fork calls. It has its own
`CLAUDE.md`; read it before changing anything about the mirror behavior.
