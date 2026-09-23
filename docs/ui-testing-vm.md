# UI testing in a Tart VM

Curator's UI tests run only inside a disposable macOS VM on cameron. They never run on the Mac
someone is using. This doc covers why, how it's set up, how to run it, and what we learned
getting it working.

**Status:** working. First full pass on 2026-09-23: 6 tests, 0 failures. Everything below was
run on cameron unless marked otherwise.

Background and the shared setup: `~/Developer/Homelab/cameron/tart-ui-test-vm.md` (Changeover's
golden image, which Curator's is cloned from).

## Why a VM

XCUITest loads `XCTAutomationSupport` into **every running GUI app**, not only the app under
test. On 2026-09-12 that crashed Batty during a Changeover UI test run, taking every terminal
session with it (see `~/Developer/brennanMKE/Changeover/docs/ui-test-crash-prevention.md`).
A Tart guest is a separate macOS with its own WindowServer, apps and privacy database, so
nothing the tests load can reach the host's apps. Each run uses a fresh clone that is deleted
afterwards, so the guest never builds up permission grants either.

### What runs where

| On the host (fine) | Only in the guest |
|---|---|
| Building, and unit tests (`xcodebuild test -scheme Curator`) | UI tests (`Curator UI Tests` scheme) |
| `scripts/make-dmg.sh` | Anything that drives the app's UI automatically |
| Running Curator yourself | |

**No UI scripting on the host either.** On 2026-09-23, keystrokes sent with `osascript` /
System Events to test Curator landed in Batty instead, because Batty had become the frontmost
app. Synthetic input goes to whatever is in front, not to the app you meant. Use the VM.

## Guards

1. **Separate scheme.** The `Curator` scheme's Test action has only `CuratorTests` (unit
   tests). UI tests are in the `Curator UI Tests` scheme, which only the VM script runs.
2. **The UI test target refuses to build on a host.** `CuratorUITests` has a first build
   phase, *Refuse to build on a host Mac*. It fails unless `sysctl -n kern.hv_vmm_present` is
   `1`, which is true only inside a virtual machine. Verified on cameron (value `0`):

   ```
   error: CuratorUITests only build inside a VM. Run scripts/run-ui-tests-vm.sh.
   ** TEST BUILD FAILED **
   ```

   The error comes before any test code compiles, so even a mistaken
   `xcodebuild -scheme 'Curator UI Tests' test` on a host stops there.

## The golden image

| | |
|---|---|
| Name | `curator-uitest-golden`, stopped, only ever cloned |
| Made | 2026-09-23, `tart clone changeover-uitest-golden curator-uitest-golden` (Brennan's choice) |
| Guest | macOS 26.6.2, Xcode 27.0 at `/Applications/Xcode_27.app` |
| CPU / memory | 6 / 12288 MB (inherited) |
| Hardening | Inherited from Changeover's golden: Automation Mode needs no authentication, developer mode on, no screen lock or sleep, SSH refuses every user |
| Disk | APFS copy-on-write clone; free space was unchanged at 177 GiB after cloning |
| Access | `tart exec` only |

Don't run or change another project's golden image. Curator's is its own clone, so it can
diverge if it ever needs to.

**Rebuilding.** When Changeover's golden image is rebuilt, for example for a new Xcode, re-clone
Curator's from it:

```sh
tart delete curator-uitest-golden
tart clone changeover-uitest-golden curator-uitest-golden
```

Nothing Curator-specific is installed in the image. The build needs only Xcode.

## Running the tests

```sh
scripts/run-ui-tests-vm.sh            # offline and live tests
scripts/run-ui-tests-vm.sh --offline  # no Plex values enter the VM; live tests skip
```

Run it in the foreground of a terminal. A run takes about 90 seconds: 15 s to boot, then the
build, then about 32 s of tests. Results land in `build/ui-tests/<run-id>/`: `xcodebuild.log`
and `UITests.xcresult`.

What the script does, in order:

1. **Preflight.** Tart and the golden image exist, **no other VM is running** (Apple allows two
   macOS guests, and every project on cameron shares them and the RAM), 20 GiB of disk is free,
   and there's enough memory. If memory is short, it asks through the memory-signal protocol,
   as Changeover's script does. Clones left by killed runs are swept; the sweep matches only
   `curator-uitest-<YYYYMMDD>-<HHMMSS>-<pid>`, which can never be a golden image.
2. **Export** `git archive HEAD` into a temporary folder. The export is the last commit, never
   the working copy, so **commit before running**.
3. **Plex values.** Unless `--offline`, it reads `PLEX_URL`, `PLEX_TOKEN` and `TMDB_API_KEY`
   from the repo's `.env` and writes them as `TEST_RUNNER_CURATOR_*` variables into the export.
   See [Plex in the guest](#plex-in-the-guest).
4. **Clone and boot** headless, with the export shared **read-only**.
5. **Check** from inside the guest that Plex answers (`/identity` returns 200). If it doesn't,
   it stops right away rather than failing three tests two minutes later.
6. **Build and test** in the guest:
   `xcodebuild -scheme 'Curator UI Tests' test CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`.
   The guest has no certificates, so the build uses ad hoc signing.
7. **Results** are streamed back with `tart exec … tar`, not through the read-only share. They
   include `app-warnings.log`, the app's errors, faults and SwiftUI/AttributeGraph messages
   from the run, and `crashes/` with any Curator crash report. The script prints a count of
   SwiftUI and AppKit state-flow warnings, such as "Modifying state during view update",
   "multiple times per frame" or AttributeGraph cycles. Anything above 0 is a bug to fix,
   not noise.
8. **Cleanup** on exit: the clone is stopped and deleted, and the export, which holds the
   token, is removed.

## Plex in the guest

- **The token is never stored in the image.** It travels in the per-run export and is deleted
  with it. Inside the guest, `xcodebuild` passes `TEST_RUNNER_*` variables to the test runner
  as `CURATOR_*`, and the tests hand those to the app's launch environment.
- **Host names don't carry over.** On cameron, `joe` resolves to its Tailscale address
  (`100.119.194.55`), which the guest can't reach. The first run failed all three live tests
  that way. The script now asks Plex for its own LAN address (`GET /servers` → `address`,
  `192.168.4.103`) and gives the guest that instead.
- **No Local Network prompt blocked the app in the guest.** Connections from the VM's NAT to
  `192.168.4.103` worked without a permission prompt (2026-09-23). If that changes in a future
  macOS, the reachability check passes but the app shows *Couldn't reach the Plex server*.

## How the app supports testing

Debug builds only (`#if DEBUG` in `AppModel.forLaunch()`): when launched with
`CURATOR_UI_TEST=1`, the app uses a throwaway settings file seeded from
`CURATOR_PLEX_URL`, `CURATOR_PLEX_TOKEN` and `CURATOR_TMDB_API_KEY`. A test run never reads or
writes real settings. The tests also pass `-viewMode grid`, so the layout doesn't depend on
the last choice.

Accessibility identifiers the tests use: `poster` (each poster in the grid) and
`detailTitle` (the inspector's title).

## The tests

`CuratorUITests/CuratorUITests.swift`:

| Test | Needs Plex | Checks |
|---|---|---|
| `testFirstLaunchAsksToConnect` | no | "Connect to Plex" and Open Settings… with no settings |
| `testSettingsExplainHowToFindTheToken` | no | ⌘, opens Settings; clicking "How do I find my token?" shows the steps |
| `testUnreachableServerExplainsTheProblem` | no | A refused connection (`127.0.0.1:1`) shows the error and Try Again |
| `testRecentlyAddedShowsPostersAndDetails` | yes | Posters load; clicking one fills the inspector and shows Open in Plex |
| `testArrowKeysMoveSelectionAndSpacePreviews` | yes | → changes the selected title; Space opens the preview; Escape closes it |
| `testSearchShowsNoResultsForAnUnknownTitle` | yes | ⌘F, typing, and the No Results state |
| `testMenuBarWindowShowsItsControls` | no | The status item opens the panel with Open Curator, Settings and Quit (screenshot kept) |
| `testMenuBarWindowListsTheLatestImports` | yes | At most 5 rows, none overlapping the header or footer (screenshot kept) |
| `testTMDBKeyIsAccepted` | yes, and a TMDB key | Settings reports "TMDB key accepted" for the key from `.env` |
| `testResizingTheWindowKeepsTheAppRunning` | yes | Six slow corner drags with the inspector open; each must really resize the window and the app must keep running (the 0.0.1 crash) |

Live tests skip themselves when no Plex values are passed.

## Writing UI tests: what we learned

- **On macOS, a text's contents are its accessibility `value`, not its `label`.** The first
  version of the arrow-key test compared labels, which were empty, so it failed even though
  the selection had moved.
- **A SwiftUI `DisclosureGroup` on macOS toggles only from its small triangle.** Clicking the
  title did nothing, for the test and for people. Settings now uses `HelpDisclosure`, whose
  title is a button. SwiftUI folds that button into the disclosure triangle's accessibility
  element, so tests find it with `disclosureTriangles["…"]`, and clicking its centre hits the
  title.
- **Read the failure snapshot before changing anything.** Each failure attaches the app's
  accessibility tree:

  ```sh
  xcrun xcresulttool export attachments --path build/ui-tests/<run-id>/UITests.xcresult --output-path /tmp/att
  grep -l "Curator Settings" /tmp/att/*.txt
  ```

  Both bugs above were found this way, not by guessing.
- Harmless log noise: `[DisplayManager] Could not find any displays containing rect (inf, inf, 0.0, 0.0)`.
  The guest is headless.

## The 0.0.1 resize crash

0.0.1 crashed while resizing the window: `EXC_BREAKPOINT` from
`_postWindowNeedsUpdateConstraints` inside `_NSViewLayout`, reached through a `@State` write
flushed during layout. The poster grid wrote its width to `@State` from `onGeometryChange`,
which runs inside AppKit's layout pass. It fired on every resize frame and whenever the
inspector opened. Fixed in `0af40e0`: the width now lives in an unobserved object.

The VM run before the fix did **not** reproduce the crash; the Debug build on a 1024 × 768
display survived the resize test. So the resize test guards against a regression but isn't
proof of this fix. The fix follows the rule that geometry and layout callbacks must not write
state the view renders from.

## Verification record, 2026-09-23

| Run | Result | Notes |
|---|---|---|
| 1 | 2 passed, 4 failed | `joe` → Tailscale IP, unreachable from the guest; disclosure click didn't expand |
| 2 | 4 passed, 2 failed | LAN address from `/servers` fixed Plex; arrow test read `label` instead of `value`; disclosure still didn't expand |
| 3 | 5 passed, 1 failed | Clickable help title; test looked for a separate button that SwiftUI had merged into the triangle |
| 4 | **6 passed** | 32.3 s of tests |
| 5 (`--offline`) | 3 passed, 3 skipped | No Plex values in the VM |

After every run: no new crash reports on cameron, the same `lsappinfo` IDs for Batty, Code,
GitUp, Switchyard, LM Studio and Xcode (so none restarted), and `tart list` showed only the
golden images.

## Known limits

- One UI test run at a time on cameron, across all projects (the script refuses if a VM is
  running).
- A run takes 6 CPUs and 12 GB of memory from cameron while it runs.
- The live tests use your real library, so their data changes as you import. They check
  behavior (posters appear, selection moves, search reports none) rather than specific titles.
