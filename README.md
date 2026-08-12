# reproducer-rn-0862-symbolview-launch-crash

![Build](https://github.com/SpiGAndromeda/reproducer-rn-0862-symbolview-launch-crash/workflows/Pre%20Merge%20Checks/badge.svg)

A `react-native-community/reproducer-react-native` app that crashes on iOS
**Release** cold launch under `react-native` 0.86.2. The whole app is a centered
`View` holding one `Text` node and one `expo-symbols` `SymbolView`. Mounting
that single `SymbolView` is the trigger.

**10 of 10 cold launches crashed** on the measured build. The commit below this
one is the identical app on `react-native` 0.86.0, which launched **0 of 10**.

| | this commit | `HEAD~1` |
|---|---|---|
| `react-native` | 0.86.2 | 0.86.0 |
| Cold launches crashed | **10 of 10** | 0 of 10 |
| React arm64 UUID | `791C3298-6723-3FE6-B25E-4C6BD2F09175` | `61086F4A-30F5-3EA0-A72A-2C94C71C7AAC` |
| hermesvm arm64 UUID | `75872184-F738-3E5C-B47A-FD4BCE09605A` | `45EC9B08-1175-38E9-A03B-F3544286F1F1` |

`git diff HEAD~1 HEAD` is the complete regression delta: the `react-native` pin,
the five `@react-native/*` dev-dependency pins that must move in lockstep with
it, the lockfile, and this file. Nothing else. `git checkout HEAD~1` is the
working baseline.

## What crashes

Both signatures are memory-access faults, and which one a given launch produces
varies. The 10-of-10 census recorded **7 × `SIGTRAP(5)`** and
**3 × `SIGSEGV(11)`**, every one of them `domain:signal(2)` and none of them
`SIGABRT`. Reading the signal matters, because a mismatched Expo pin set also
kills the process (see below) and would otherwise be counted as a reproduction.

Crash reports collected while characterising this same crash on an
`expo prebuild` app with the same dependency set put the fault in one of two
places: the allocator on the JavaScript thread, or `RCTComponentViewFactory` on
the main thread while a Fabric mounting transaction dequeues a component view.
Both are consistent with the heap already being corrupt by the time the fault is
noticed, rather than with a missing null check at the faulting frame. The census
in this repository recorded signals rather than full reports, because macOS had
already begun throttling `.ips` writes (see `tools/crash-signature.sh`).

## The app

`ReproducerApp/App.tsx` is a centered `View` holding one `Text` node and one
`SymbolView`. Nothing else. Larger configurations — long text corpora, several
font families, navigation, reanimated animations, storage IO — were tried first
and reproduced nothing; the trigger is one Expo module view rather than
accumulated load.

`expo-symbols` renders through SF Symbols on iOS and falls back to JavaScript on
Android, so only the iOS build reproduces anything. Android is here because the
repository's CI builds it.

## What the template app needed before the crash could appear

The generated template is a bare React Native app. Converting it to Expo modules
is most of this repository's diff, and three of those changes are not obvious.
`install-expo-modules` does not support this SDK, so every step is applied by
hand.

**Expo's precompiled modules must be switched on.** `ReproducerApp/ios/Podfile`
sets `EXPO_USE_PRECOMPILED_MODULES=1`, which is the Expo prebuild default but
not the CocoaPods default. With it, `ExpoModulesCore`, `ExpoFileSystem`,
`ExpoFont` and `ExpoModulesWorklets` come from Expo as prebuilt **dynamic**
xcframeworks and are embedded in the app bundle. Without it, CocoaPods compiles
those four from source and links them statically into the app binary — and the
otherwise identical app, same versions, same `react-native` 0.86.2, same
flavor-verified prebuilt core, **crashed 0 of 10**:

| `react-native` | Expo modules | Cold launches crashed |
|---|---|---|
| 0.86.2 | precompiled, dynamic | **10 of 10** |
| 0.86.2 | built from source, static | 0 of 10 |
| 0.86.0 | precompiled, dynamic | 0 of 10 |

This is the least obvious requirement in the repository. An investigation
starting from a bare `@react-native-community/cli init` app rather than from
`expo prebuild` would conclude the bug does not exist. It also means the defect
is only reachable through Expo's shipped module binaries, not through the same
Swift compiled locally — which narrows where to look, though it does not by
itself say whether the difference is the linkage or the binaries.

**The app enters through Expo's root component.** `ReproducerApp/index.js` uses
`registerRootComponent` from `expo` rather than calling
`AppRegistry.registerComponent` directly, which is what pulls the Expo runtime
into the bundle. It registers under the module name `main`, so
`AppDelegate.swift` and `MainActivity.kt` start React Native with that name
rather than `ReproducerApp`. On its own this change did **not** make the crash
appear — it was measured at 0 of 10 while the modules were still static. It is
kept because it matches the shape the crash was originally characterised in, not
because it was shown to be necessary.

**The iOS deployment target must be raised to 16.4**, the Expo SDK 57 floor.
The `Podfile` platform line raises the pod targets only; the app target keeps
whatever the generated Xcode project carries, and at the template's 15.1 the
build fails with `compiling for iOS 15.1, but module 'Expo' has a minimum
deployment target of iOS 16.4`.

One Android change is unrelated to Expo: the Gradle wrapper is 9.3.1 rather than
the template's 9.4.1, matching what `react-native` 0.86 pairs with. On 9.4.1 the
bundled Kotlin compiler dies with an internal error while compiling the React
Native and Expo gradle plugins.

The iOS `Podfile` also sets `RCT_USE_RN_DEP` and `RCT_USE_PREBUILT_RNCORE`, so
the app links the prebuilt React core from Maven rather than building the core
from source. A source-built core is a different binary and tests a different
question.

## Versions, and why they are pinned exactly

`ReproducerApp/package.json` pins every dependency the bug depends on to an
exact version, and pins the transitive Expo modules through npm `overrides`:

| Package | Version | |
|---|---|---|
| `expo` | `57.0.8` | direct |
| `expo-symbols` | `57.0.1` | direct |
| `react` | `19.2.8` | direct |
| `react-native` | `0.86.2` | direct |
| `expo-constants` | `57.0.10` | override |
| `expo-modules-core` | `57.0.7` | override |
| `expo-file-system` | `57.0.1` | override |
| `expo-asset` | `57.0.7` | override |
| `expo-font` | `57.0.1` | override |
| `expo-keep-awake` | `57.0.1` | override |

**Install from the committed lockfile with `npm ci`.** The whole pin set is
load-bearing:

- With floating ranges the same `package.json` resolves differently over time.
  An `expo prebuild` app with the same `App.tsx` and the same 0.86.2 core, on
  this simulator, floated to `expo@57.0.12` / `expo-symbols@57.0.2` /
  `expo-modules-core@57.0.10` and crashed 0 of 20.
- A *partial* pin set is worse than none. Pinning `expo-modules-core` while its
  siblings float upward produces a build that installs and compiles cleanly and
  then dies at launch in the dynamic linker (`Symbol not found:
  _$s15ExpoModulesCore10BaseModuleC11willDestroyyyFTj`, referenced from
  `ExpoFileSystem`). That is a `SIGABRT` in the `DYLD` namespace — a different
  failure that kills the process just as thoroughly. That failure mode is only
  reachable at all because the modules are dynamically linked, which is the same
  reason the precompiled-modules switch above matters.

`expo-modules-core` 57.0.8 and later mask the crash entirely — measured on the
`expo prebuild` app as 10 of 10 at 57.0.7 against 0 of 10 at both 57.0.8 and
57.0.10, each from a full reset with the rest of the pin set held fixed — so the
pinned 57.0.7 is deliberate. That is a mask rather than a fix: it shows a newer
`expo-modules-core` stops the crash appearing *in this app*, not that the
underlying defect is gone.

Worth noting for triage: Expo SDK 57 nominates `react-native` 0.86.0 —
`expo@57.0.8` carries that version in its `bundledNativeModules.json` — so the
crashing pin is one patch above what the SDK recommends.

## Environment

Every measurement in this file was taken on:

| | |
|---|---|
| macOS | 26.5.2 |
| Xcode | 26.6 |
| CocoaPods | 1.17.0 |
| Node | 26.5.0 |
| npm | 11.17.0 |
| Simulator | iPhone 17, iOS 26.5 |

The JS engine is Hermes, and the New Architecture is the only architecture
`react-native` 0.86 ships.

## Build and census

```sh
cd ReproducerApp
npm ci
cd ios && pod install
rm -f Pods/.last_build_configuration
xcodebuild -workspace ReproducerApp.xcworkspace -scheme ReproducerApp \
  -configuration Release -sdk iphonesimulator -derivedDataPath ci-build \
  -destination 'generic/platform=iOS Simulator' build
```

The built app lands at
`ReproducerApp/ios/ci-build/Build/Products/Release-iphonesimulator/ReproducerApp.app`.
It must be a **Release** build; Debug does not reproduce it.

```sh
tools/verify-flavors.sh ReproducerApp/ios/ci-build/Build/Products/Release-iphonesimulator/ReproducerApp.app
tools/census.sh <simulator-udid> ReproducerApp/ios/ci-build/Build/Products/Release-iphonesimulator/ReproducerApp.app
tools/crash-signature.sh <simulator-udid> org.reactjs.native.example.ReproducerApp
```

Run the flavor gate before counting anything. A Release-configuration
`xcodebuild` can silently link the *debug* flavor of the prebuilt React and
hermes frameworks, and a census taken on such a build is an invalid run rather
than a result.

A single launch proves nothing in either direction. The crash is probabilistic,
so the working baseline has to survive a whole series and this state has to die
on most of one.

## Tools

### `tools/verify-flavors.sh <path-to-.app>`

Reads the arm64 UUID of `Frameworks/React.framework/React` and
`Frameworks/hermesvm.framework/hermesvm` with `dwarfdump --uuid` and classifies
each against the known release and debug artifacts. Exits non-zero on a debug
flavor or an unrecognised UUID.

### `tools/census.sh <simulator-udid> <path-to-.app> [launches]`

Reinstalls the app on the given simulator and performs 10 cold launches by
default, terminating the app before each one and checking six seconds later
whether the process is still alive. Prints a per-launch `alive` / `crashed` line
and a `crashed: N/10` total.

Do not run a heavy build concurrently with a census: the liveness check is a
fixed wait, and CPU contention can move a launch across it.

### `tools/crash-signature.sh <simulator-udid> <bundle-id> [minutes]`

Prints the termination signal the simulator recorded for each launch.
`SIGTRAP` (5) and `SIGSEGV` (11) are this crash; `SIGABRT` (6) is the
dynamic-linker failure described above and invalidates the run.

macOS stops writing `.ips` crash reports after roughly 30 identical crashes in a
day, so a crash count and a report count can legitimately disagree. This log
query is the reliable fallback, and it has to run **inside** the simulator — the
host's log store carries no records for a simulated process.

## License

MIT — see `LICENSE`.
