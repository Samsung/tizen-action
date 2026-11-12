# Dart (Flutter for Tizen) action provider

Modeled on `ActionSampleAppDart`. Placeholders: project `my_action_app_dart`,
app id `org.example.myactionappdart`, category `Tizen.Action.Browser`,
stub base `ImplBrowser`, dlog tag `TIDL_ACTION_MYACTIONAPP`.

Requires a `flutter-tizen` checkout and the `tizen_rpc_port` plugin.

## Layout

```
MyActionAppDart/
├── pubspec.yaml
├── lib/ImplBrowser.dart   # generated — do not edit
├── lib/main.dart
├── tizen/tizen-manifest.xml
├── gen.sh
├── build.sh
├── run.sh
└── README.md
```

Start from `flutter-tizen create`, then add the stub and the RPC wiring.

## pubspec.yaml (relevant part)

```yaml
environment:
  sdk: ^3.12.1

dependencies:
  flutter:
    sdk: flutter
  tizen_rpc_port:
    path: /path/to/plugins/packages/tizen_rpc_port
```

The generated Dart stub imports `tizen_rpc_port` (`StubBase`, `Port`, `Parcel`); point
the path at a local plugin checkout or use the published package if it is new enough.

## lib/main.dart (RPC parts)

```dart
import 'package:flutter/material.dart';
import 'ImplBrowser.dart';

class BrowserService extends ServiceBase {
  BrowserService(super.sender, super.instance);

  @override
  Future<void> onCreate() async {
    AppState.addLog('Client connected: Sender=$sender, Instance=$instance');
  }

  @override
  Future<void> onTerminate() async {
    AppState.addLog('Client disconnected: Sender=$sender, Instance=$instance');
  }

  @override
  Future<TizenEntityStatus> onGo(TizenEntityBrowser browser) async {
    AppState.addLog('onGo triggered: Url="${browser.Url}", Title="${browser.Title}"');
    return TizenEntityStatus()
      ..Success = true
      ..Reason = '';
  }

  @override
  Future<TizenEntityStatus> onGetCurrent(TizenEntityBrowser result) async {
    result.Url = 'https://tizen.org';
    result.Title = 'Tizen Project';
    result.Details = 'Details';
    return TizenEntityStatus()
      ..Success = true
      ..Reason = '';
  }

  // ... one handler per remaining action of the category ...
}
```

### Method signatures

Each action's method signature (as a handler method) depends on its `.action` schema.
Handler names are `on` + PascalCase action name (`onGo`, `onGetCurrent`, etc.), and all
return `Future<TizenEntityStatus>`:

- **No input, no output**: `Future<TizenEntityStatus> onActionName()` (no parameters)
- **Input entity, no output**: `Future<TizenEntityStatus> onActionName(TizenEntityCategory entity)` (entity passed as parameter)
- **No input, output entity**: `Future<TizenEntityStatus> onActionName(TizenEntityCategory result)` (entity passed as mutable reference)
- **Input and output**: `Future<TizenEntityStatus> onActionName(TizenEntityCategory entity, TizenEntityCategory result)` (both passed)

To find the correct signature for your category, read the generated stub:

```bash
# After running gen.sh or actionc
grep "Future<TizenEntityStatus> on[A-Z]" lib/ImplBrowser.dart
```

Then implement each handler in `BrowserService`, matching the exact signature. All
handlers return `TizenEntityStatus()` with `Success` and `Reason` fields set.

### Startup and listening

Start the stub from `initState` (or any one-shot init path):

```dart
TizenActionBrowser? _stub;

Future<void> _startService() async {
  try {
    _stub = TizenActionBrowser(
        (String sender, String instance) => BrowserService(sender, instance));
    await _stub!.listen();
    AppState.addLog('Listening on port "TizenActionBrowser"');
  } catch (e) {
    AppState.addLog('Listen failed: $e');
  }
}
```

Dart handlers are `async` and return `Future<TizenEntityStatus>`. Logging via `print()`
reaches dlog, so prefix lines with the app's tag (`print('[TIDL_ACTION_MYACTIONAPP] …')`)
to keep `dlogutil | grep` working. The sample mirrors state into `ValueNotifier`s that
drive an on-screen dashboard.

## tizen/tizen-manifest.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest package="org.example.myactionappdart" version="1.0.0" api-version="6.5" xmlns="http://tizen.org/ns/packages">
    <profile name="common"/>
    <ui-application appid="org.example.myactionappdart" exec="Runner.dll" type="dotnet" multiple="false" nodisplay="false" taskmanage="true">
        <label>MyActionAppDart</label>
        <icon>ic_launcher.png</icon>
        <metadata key="http://tizen.org/metadata/prefer_dotnet_aot" value="true"/>
        <metadata key="http://tizen.org/metadata/prefer_nuget_cache" value="true"/>
        <!-- Register per action, like the C#/C++/JS samples do. The Dart sample
             still carries a single category-level entry, which is the older form. -->
        <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_GetCurrent"/>
        <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_Go"/>
        <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_ToCalendar"/>
        <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_ToPresentation"/>
    </ui-application>
    <feature name="http://tizen.org/feature/screen.size.all"/>
    <privileges>
        <privilege>http://tizen.org/privilege/datasharing</privilege>
        <privilege>http://tizen.org/privilege/appmanager.launch</privilege>
    </privileges>
</manifest>
```

## gen.sh

```bash
#!/usr/bin/env bash
#
# Generates the Dart TIDL interface and stub code for this sample from default-actions using actionc.

set -euo pipefail

GEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
ACTIONC_BIN="${ACTIONC:-actionc}"

if ! command -v "${ACTIONC_BIN}" >/dev/null 2>&1; then
  if [ -f "${HOME}/.action-tools/actionc" ]; then
    ACTIONC_BIN="${HOME}/.action-tools/actionc"
  else
    echo "error: actionc not found." >&2
    exit 1
  fi
fi

echo "actionc: ${ACTIONC_BIN}"
mkdir -p "${GEN_DIR}"

# Match the schemas to the attached device's tizen-action before generating; the
# compiler binaries stay as installed. Best effort: without a device or network the
# installed data is used as is.
ACTIONC_SYNC_BIN="$(command -v actionc-sync 2>/dev/null || true)"
if [ -z "${ACTIONC_SYNC_BIN}" ] && [ -x "${HOME}/.action-tools/actionc-sync" ]; then
  ACTIONC_SYNC_BIN="${HOME}/.action-tools/actionc-sync"
fi
if [ -n "${ACTIONC_SYNC_BIN}" ]; then
  "${ACTIONC_SYNC_BIN}" --quiet || echo "warning: actionc-sync failed; generating from the installed schema data" >&2
fi

echo "[1/1] actionc: generating Dart Browser action stub -> lib/ImplBrowser.dart"
# Always run actionc from GEN_DIR so that output goes directly to lib/
cd "${GEN_DIR}" && "${ACTIONC_BIN}" -a Tizen.Action.Browser -l Dart -o ImplBrowser

echo "Done."
```

## build.sh

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

FLUTTER_BIN="${FLUTTER_TIZEN:-$HOME/flutter-tizen/bin/flutter-tizen}"
APP_ID="org.example.myactionappdart"

log() { echo -e "\033[1;34m[MyActionAppDart]\033[0m $*"; }
die() { echo -e "\033[1;31m[MyActionAppDart] error:\033[0m $*" >&2; exit 1; }

build_pkg() {
  log "Building TPK..."
  "$FLUTTER_BIN" build tpk --debug
  local tpk
  tpk="$(ls -t build/tizen/tpk/*.tpk 2>/dev/null | head -1)"
  [ -n "$tpk" ] || die "no .tpk produced"
  log "Packaged: $tpk"
}

install_tpk() {
  local tpk
  tpk="$(ls -t build/tizen/tpk/*.tpk 2>/dev/null | head -1)"
  [ -n "$tpk" ] || die "no .tpk found; run './build.sh' first"
  log "Installing $tpk on target"
  sdb install "$tpk"
}

launch_app() { log "Launching $APP_ID"; sdb shell "launch_app $APP_ID"; }

case "${1:-all}" in
  all|build) build_pkg ;;
  install)   install_tpk ;;
  run)       install_tpk; launch_app ;;
  clean)     "$FLUTTER_BIN" clean ;;
  *)         die "unknown command '$1' (use: all|build|install|run|clean)" ;;
esac

log "done."
```

## run.sh

```bash
#!/usr/bin/env bash
#
# Automatically builds, deploys, and executes the MyActionAppDart test app on the device.

set -euo pipefail

URL="https://tizen.org"
TITLE="Tizen OS"
DETAILS="Rpi4 Board"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u) URL="$2"; shift 2 ;;
    -t) TITLE="$2"; shift 2 ;;
    -d) DETAILS="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== [1/3] Building and Deploying Tizen Dart Application ==="
"$SCRIPT_DIR/build.sh" run

echo "Waiting 5 seconds for Dart application to initialize and listen on RPC port..."
sleep 5

echo "=== [2/3] Executing action dynamically targeting Dart Application ==="
JSON='{"id": 15, "params": { "name": "Tv_Tizen.Action.Browser_Go", "appid": "org.example.myactionappdart", "arguments": { "Url": "'"$URL"'", "Title": "'"$TITLE"'", "Details": "'"$DETAILS"'" } } }'
sdb shell "action-tool execute '$JSON'"

echo "=== [3/3] Fetching dlog logs ==="
sdb shell "dlogutil -d | grep -i TIDL_ACTION_MYACTIONAPP"
```

Like the Web app, a Flutter provider must be running before `action-tool execute`.

## Critical: Verify method signatures from the generated stub

**Do NOT assume action handler signatures match the examples above.** The actual signatures
are determined by the `.action` schema for each action in the category. Always inspect
the generated stub before implementing:

```bash
# After running gen.sh or actionc
grep "Future<TizenEntityStatus> on[A-Z]" lib/ImplBrowser.dart
```

Copy the exact handler signature (parameter types and count) and implement it in your
`BrowserService` class, matching the exact signature. All handlers must return
`Future<TizenEntityStatus>` with `Success` and `Reason` fields set. Mismatched signatures
will cause:

- Handler never being called (wrong method signature)
- `NoSuchMethodError: the getter 'Url' was called on null` if parameters don't match
- `type '_Future<TizenEntityStatus>' is not a subtype of type 'Future<TizenEntityStatus>'`
  if return type is mismatched

If actions are not being triggered or handlers are throwing runtime errors, check
`lib/ImplXxx.dart` for the **exact** handler signatures for your category.
