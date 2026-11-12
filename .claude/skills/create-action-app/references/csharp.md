# C# (.NET / NUI) action provider

Modeled on `ActionSampleAppCs`. Placeholders below: app `MyActionApp`,
package/app id `org.example.myactionapp`, category `Tizen.Action.Browser`,
stub base `ImplBrowser`, dlog tag `TIDL_ACTION_MYACTIONAPP`.

## Layout

```
MyActionApp/
├── MyActionApp.csproj
├── Program.cs
├── tizen-manifest.xml
├── gen/ImplBrowser.cs      # generated — do not edit
├── gen.sh
├── run.sh
├── .gitignore              # bin/  obj/
└── README.md
```

## Prerequisites

* The Tizen Action Compiler `install.sh` has been run.
* TizenFX built and installed (`./build.sh full && ./build.sh install` in `tizenfx`),
  since the build references local ref assemblies:
  `$HOME/.dotnet/packs/Samsung.Tizen.Ref.API13/13.0.0.19231/ref/net6.0`
  (adjust the version to what is installed).

## MyActionApp.csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0-tizen11.0</TargetFramework>
  </PropertyGroup>

  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
    <DebugType>portable</DebugType>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
    <DebugType>None</DebugType>
  </PropertyGroup>

</Project>
```

`gen/*.cs` is picked up by the SDK's default globbing — no explicit `Compile` item needed.

## tizen-manifest.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns="http://tizen.org/ns/packages" api-version="11.0" package="org.example.myactionapp" version="1.0.0">
  <profile name="common" />
  <ui-application appid="org.example.myactionapp"
                  exec="MyActionApp.dll"
                  type="dotnet"
                  multiple="false"
                  taskmanage="true"
                  nodisplay="false"
                  launch_mode="single"
                  api-version="11">
    <label>MyActionApp</label>
    <!-- Provider registration is per action: declare every action this app serves
         so it is listed/executable and discoverable individually. -->
    <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_GetCurrent" />
    <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_Go" />
    <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_ToCalendar" />
    <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_ToPresentation" />
  </ui-application>
  <privileges>
    <privilege>http://tizen.org/privilege/datasharing</privilege>
    <privilege>http://tizen.org/privilege/appmanager.launch</privilege>
  </privileges>
</manifest>
```

`exec` must match the produced assembly name. A headless provider can use
`<service-application ... type="dotnet">` with `Tizen.Applications.ServiceApplication`
instead; the NUI variant below is the one the sample verifies on target.

## Program.cs

```csharp
using System;
using Tizen;
using Tizen.Applications;
using Tizen.NUI;
using Tizen.NUI.BaseComponents;
using RPCPort.ImplBrowser.Stub;
using RPCPort.ImplBrowser;

namespace MyActionApp
{
    class Program : NUIApplication
    {
        internal static string LogTag = "TIDL_ACTION_MYACTIONAPP";

        class BrowserService : TizenActionBrowser.ServiceBase
        {
            public override void OnCreate()
            {
                Log.Info(LogTag, $"Client connected: Sender={Sender}, Instance={Instance}");
            }

            public override void OnTerminate()
            {
                Log.Info(LogTag, $"Client disconnected: Sender={Sender}, Instance={Instance}");
            }

            public override TizenEntityStatus Go(TizenEntityBrowser browser_ent)
            {
                Log.Info(LogTag, $"Go: Open URL=\"{browser_ent.Url}\", Title=\"{browser_ent.Title}\", Details=\"{browser_ent.Details}\"");

                TizenEntityStatus status = new TizenEntityStatus();
                status.Success = true;
                status.Reason = "";
                return status;
            }

            public override TizenEntityStatus GetCurrent(out TizenEntityBrowser result)
            {
                result = new TizenEntityBrowser();
                result.Id = "current_id";
                result.Extra = "extra";
                result.Url = "https://tizen.org";
                result.Title = "Tizen Project";
                result.Details = "Details";

                TizenEntityStatus status = new TizenEntityStatus();
                status.Success = true;
                status.Reason = "";
                return status;
            }

            // ... one override per remaining action of the category ...
        }
```

### Method signatures

Each action's method signature depends on its `.action` schema:

- **No input, no output**: `TizenEntityStatus ActionName()`
- **Input entity, no output**: `TizenEntityStatus ActionName(TizenEntityCategory input)`
- **No input, output entity**: `TizenEntityStatus ActionName(out TizenEntityCategory output)`
- **Input and output**: `TizenEntityStatus ActionName(TizenEntityCategory input, out TizenEntityCategory output)`

To find the correct signature for your category, read the generated stub:

```bash
grep "public.*TizenEntityStatus" gen/ImplBrowser.cs
```

Then implement each virtual method in `ServiceBase`, matching the exact signature. All
action methods return `TizenEntityStatus` with `Success` and `Reason` fields.

### Application startup and listener

```csharp
        private TizenActionBrowser _browser;

        protected override void OnCreate()
        {
            base.OnCreate();
            _browser = new TizenActionBrowser();
            try
            {
                _browser.Listen(typeof(BrowserService));
            }
            catch (Exception e)
            {
                Log.Error(LogTag, $"Failed to listen: {e.Message}");
                return;
            }
            Log.Info(LogTag, "TizenActionBrowser stub is listening");

            Window.Instance.BackgroundColor = Color.White;
            Window.Instance.KeyEvent += OnKeyEvent;

            TextLabel text = new TextLabel("My Action App (CS)");
            text.HorizontalAlignment = HorizontalAlignment.Center;
            text.VerticalAlignment = VerticalAlignment.Center;
            text.TextColor = Color.Blue;
            text.PointSize = 15.0f;
            text.HeightResizePolicy = ResizePolicyType.FillToParent;
            text.WidthResizePolicy = ResizePolicyType.FillToParent;
            Window.Instance.GetDefaultLayer().Add(text);
        }

        protected override void OnTerminate()
        {
            base.OnTerminate();
            _browser = null;
        }

        private void OnKeyEvent(object sender, Window.KeyEventArgs e)
        {
            if (e.Key.State == Key.StateType.Down && (e.Key.KeyPressedName == "XF86Back" || e.Key.KeyPressedName == "Escape"))
            {
                Exit();
            }
        }

        static void Main(string[] args)
        {
            var app = new Program();
            app.Run(args);
        }
    }
}
```

`Listen(typeof(BrowserService))` instantiates the service per connecting client via
reflection, so the service class needs a parameterless constructor.
`ServiceBase` is abstract: **every** action of the category must be overridden or the
class will not compile.

## gen.sh

```bash
#!/usr/bin/env bash
#
# Generates the C# TIDL interface and stub code for this sample from default-actions using actionc.
#
# Tool locations and configuration can be overridden via environment variables:
#   ACTIONC            path to the actionc binary (default: look in PATH)
#   ACTIONC_DATA_DIR   path to the directory holding the framework's actions/ and entities/
#                      (default: actionc's built-in default)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN_DIR="${SCRIPT_DIR}/gen"

find_actionc() {
  if [[ -n "${ACTIONC:-}" ]]; then echo "${ACTIONC}"; return; fi
  if command -v actionc >/dev/null 2>&1; then command -v actionc; return; fi
  if [[ -x "${HOME}/.action-tools/actionc" ]]; then echo "${HOME}/.action-tools/actionc"; return; fi
  return 1
}

ACTIONC_BIN="$(find_actionc)" || {
  echo "error: actionc not found in PATH. Please install actionc or set the ACTIONC environment variable." >&2
  exit 1
}

echo "actionc: ${ACTIONC_BIN}"
mkdir -p "${GEN_DIR}"

# Match the schemas to the attached device's tizen-action before generating; the
# compiler binaries stay as installed. Best effort: without a device or network the
# installed data is used as is.
find_actionc_sync() {
  if command -v actionc-sync >/dev/null 2>&1; then command -v actionc-sync; return; fi
  if [[ -x "${HOME}/.action-tools/actionc-sync" ]]; then echo "${HOME}/.action-tools/actionc-sync"; return; fi
  return 1
}
if ACTIONC_SYNC_BIN="$(find_actionc_sync)"; then
  "${ACTIONC_SYNC_BIN}" --quiet || echo "warning: actionc-sync failed; generating from the installed schema data" >&2
fi

echo "[1/1] actionc: generating C# Browser action stub -> gen/ImplBrowser"
( cd "${GEN_DIR}" && "${ACTIONC_BIN}" -a Tizen.Action.Browser -l C# -o ImplBrowser )

echo "Done."
echo "  generated stub:      ${GEN_DIR}/ImplBrowser.cs"
```

## run.sh

```bash
#!/usr/bin/env bash
#
# Automatically builds, deploys, and executes the MyActionApp C# test app on the device.
#
# Usage:
#   ./run.sh [-u URL] [-t TITLE] [-d DETAILS]

set -euo pipefail

URL="https://tizen.org"
TITLE="Tizen OS"
DETAILS="Rpi4 Board"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u) URL="$2"; shift 2 ;;
    -t) TITLE="$2"; shift 2 ;;
    -d) DETAILS="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== [1/5] Building Tizen C# Application (MyActionApp) ==="
dotnet build /p:TizenFxPath="${HOME}/.dotnet/packs/Samsung.Tizen.Ref.API13/13.0.0.19231/ref/net6.0" "${SCRIPT_DIR}/MyActionApp.csproj"

echo "=== [2/5] Deploying TPK to Tizen Target Board ==="
sdb install "${SCRIPT_DIR}/bin/Debug/net8.0-tizen11.0/org.example.myactionapp-1.0.0.tpk"

echo "=== [3/5] Terminating any old active service processes ==="
sdb shell "killall MyActionApp || true"

echo "=== [4/5] Executing action dynamically targeting C# Application ==="
JSON="{\"id\": 10, \"params\": { \"name\": \"Tv_Tizen.Action.Browser_Go\", \"appid\": \"org.example.myactionapp\", \"arguments\": { \"Url\": \"${URL}\", \"Title\": \"${TITLE}\", \"Details\": \"${DETAILS}\" } } }"
sdb shell "action-tool execute '${JSON}'"

echo "=== [5/5] Fetching dlog logs for TIDL_ACTION_MYACTIONAPP ==="
sdb shell "dlogutil -d TIDL_ACTION_MYACTIONAPP"
```

Run `./gen.sh` before the first build (the generated stub is normally committed, but
regenerate after any schema change).

## Critical: Verify method signatures from the generated stub

**Do NOT assume action method signatures match the examples above.** The actual signatures
are determined by the `.action` schema for each action in the category. Always inspect
the generated stub before implementing:

```bash
# After running gen.sh or actionc
grep "public.*TizenEntityStatus" gen/ImplBrowser.cs
```

Copy the exact method signature (parameter types, `out` references, count) and implement
it in your `ServiceBase` subclass. Mismatched signatures will cause:

- `does not implement interface member` compilation errors
- `cannot convert from` type errors for wrong entity types
- `The best overloaded method match has some invalid arguments` if parameter count is wrong

If you get these errors after implementing the service class, check `gen/ImplXxx.cs` for
the **exact** method signatures for your category.
