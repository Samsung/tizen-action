# C++ (native service app) action provider

Modeled on `ActionSampleAppCpp`. Placeholders: binary/RPM name `my-action-app`,
package/app id `org.example.myactionapp`, category `Tizen.Action.Browser`,
stub base `ImplBrowser`, dlog tag `TIDL_ACTION_MYACTIONAPP`.

## Layout

```
MyActionAppCpp/
├── CMakeLists.txt
├── gbs.conf
├── tizen-manifest.xml
├── packaging/
│   ├── my-action-app.spec
│   └── my-action-app.manifest
├── gen/ImplBrowser.h, ImplBrowser.cc   # generated — do not edit
├── src/myactionapp.cc
├── gen.sh
├── run.sh
└── README.md
```

## src/myactionapp.cc

```cpp
#include <dlog.h>
#include <service_app.h>

#include <memory>
#include <string>

#include "ImplBrowser.h"

#undef LOG_TAG
#define LOG_TAG "TIDL_ACTION_MYACTIONAPP"

namespace {

namespace browser = rpc_port::implbrowser;

// Implements the Browser action business logic for the TizenActionBrowser interface.
class BrowserService : public browser::stub::TizenActionBrowser::ServiceBase {
 public:
  BrowserService(std::string sender, std::string instance)
      : ServiceBase(std::move(sender), std::move(instance)) {}

  void OnCreate() override {
    dlog_print(DLOG_INFO, LOG_TAG, "client connected: sender=%s instance=%s",
               GetSender().c_str(), GetInstance().c_str());
  }

  void OnTerminate() override {
    dlog_print(DLOG_INFO, LOG_TAG, "client disconnected: sender=%s",
               GetSender().c_str());
  }

  browser::TizenEntityStatus Go(browser::TizenEntityBrowser browser_ent) override {
    dlog_print(DLOG_INFO, LOG_TAG, "Go: Open URL=\"%s\", Title=\"%s\", Details=\"%s\"",
               browser_ent.GetUrl().c_str(), browser_ent.GetTitle().c_str(),
               browser_ent.GetDetails().c_str());
    return browser::TizenEntityStatus(true, "");
  }

  browser::TizenEntityStatus GetCurrent(browser::TizenEntityBrowser& result) override {
    result = browser::TizenEntityBrowser("current_id", "extra", "https://tizen.org",
                                         "Tizen Project", "Details");
    return browser::TizenEntityStatus(true, "");
  }

  // ... one override per remaining action of the category ...
};
```

### Method signatures

Each action's method signature depends on its `.action` schema:

- **No input, no output**: `TizenEntityStatus ActionName()`
- **Input entity, no output**: `TizenEntityStatus ActionName(TizenEntityCategory input)`
- **No input, output entity**: `TizenEntityStatus ActionName(TizenEntityCategory& output)`
- **Input and output**: `TizenEntityStatus ActionName(TizenEntityCategory input, TizenEntityCategory& output)`

To find the correct signature for your category, read the generated stub header:

```bash
grep "virtual TizenEntityStatus" gen/ImplBrowser.h
```

Then implement each virtual method in `ServiceBase`, matching the exact signature. All
action methods return `TizenEntityStatus(success: bool, reason: string)`.

### Service lifecycle and implementation

```cpp
class BrowserFactory : public browser::stub::TizenActionBrowser::ServiceBase::Factory {
 public:
  std::unique_ptr<browser::stub::TizenActionBrowser::ServiceBase> CreateService(
      std::string sender, std::string instance) override {
    return std::make_unique<BrowserService>(std::move(sender), std::move(instance));
  }
};

std::unique_ptr<browser::stub::TizenActionBrowser> g_stub;

bool OnCreate(void* /*user_data*/) {
  g_stub = std::make_unique<browser::stub::TizenActionBrowser>();
  try {
    g_stub->Listen(std::make_shared<BrowserFactory>());
  } catch (const browser::stub::Exception& e) {
    dlog_print(DLOG_ERROR, LOG_TAG, "Failed to listen: %s", e.what());
    return false;
  }
  dlog_print(DLOG_INFO, LOG_TAG, "TizenActionBrowser stub is listening");
  return true;
}

void OnTerminate(void* /*user_data*/) { g_stub.reset(); }

void OnAppControl(app_control_h /*app_control*/, void* /*user_data*/) {}

}  // namespace

int main(int argc, char* argv[]) {
  service_app_lifecycle_callback_s cb = {};
  cb.create = OnCreate;
  cb.terminate = OnTerminate;
  cb.app_control = OnAppControl;
  return service_app_main(argc, argv, &cb, nullptr);
}
```

Entity classes expose `GetXxx()`/`SetXxx()` accessors and a positional constructor
(base-class properties `Id`, `Extra` come first). Output parameters are references.

## CMakeLists.txt

```cmake
CMAKE_MINIMUM_REQUIRED(VERSION 3.0)
PROJECT(my-action-app C CXX)

SET(TARGET_APP "my-action-app")
SET(APP_PKGID "org.example.myactionapp")

FIND_PACKAGE(PkgConfig REQUIRED)
PKG_CHECK_MODULES(SAMPLE_DEPS REQUIRED
  dlog
  rpc-port
  capi-appfw-service-application
  capi-appfw-app-common
)

ADD_EXECUTABLE(${TARGET_APP}
  ${CMAKE_CURRENT_SOURCE_DIR}/src/myactionapp.cc
  ${CMAKE_CURRENT_SOURCE_DIR}/gen/ImplBrowser.cc)

TARGET_INCLUDE_DIRECTORIES(${TARGET_APP} PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/gen
  ${SAMPLE_DEPS_INCLUDE_DIRS})
TARGET_COMPILE_OPTIONS(${TARGET_APP} PRIVATE
  ${SAMPLE_DEPS_CFLAGS_OTHER} -fPIE)
TARGET_LINK_LIBRARIES(${TARGET_APP}
  ${SAMPLE_DEPS_LIBRARIES} "-pie" "-ldl")

# The generated stub is third-party output; keep the project's strict warning
# flags (notably -Werror) from failing the build on it.
SET_SOURCE_FILES_PROPERTIES(
  ${CMAKE_CURRENT_SOURCE_DIR}/gen/ImplBrowser.cc
  PROPERTIES COMPILE_FLAGS "-Wno-error")

# Tizen package layout under the app root.
SET(PREFIX "/usr" CACHE PATH "Installation Prefix")
SET(APP_DIR ${PREFIX}/apps/${APP_PKGID})
INSTALL(TARGETS ${TARGET_APP} DESTINATION ${APP_DIR}/bin)
INSTALL(FILES ${CMAKE_CURRENT_SOURCE_DIR}/tizen-manifest.xml
        DESTINATION ${APP_DIR})
INSTALL(FILES ${CMAKE_CURRENT_SOURCE_DIR}/tizen-manifest.xml
        DESTINATION ${PREFIX}/share/packages RENAME ${APP_PKGID}.xml)
```

## tizen-manifest.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns="http://tizen.org/ns/packages" api-version="9.0" package="org.example.myactionapp" version="1.0.0">
  <profile name="common" />
  <service-application appid="org.example.myactionapp"
                       exec="my-action-app"
                       type="capp"
                       multiple="false"
                       taskmanage="false"
                       auto-restart="false"
                       on-boot="false">
    <label>my-action-app</label>
    <!-- Provider registration is per action. -->
    <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_GetCurrent" />
    <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_Go" />
    <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_ToCalendar" />
    <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_ToPresentation" />
  </service-application>
  <privileges>
    <privilege>http://tizen.org/privilege/datasharing</privilege>
    <privilege>http://tizen.org/privilege/appmanager.launch</privilege>
  </privileges>
</manifest>
```

## packaging/my-action-app.spec

```spec
Name:       my-action-app
Version:    1.0.0
Release:    1
Summary:    Tizen C++ Action Sample Application
License:    Apache-2.0
Source0:    %{name}-%{version}.tar.gz

BuildRequires: cmake
BuildRequires: pkgconfig(dlog)
BuildRequires: pkgconfig(rpc-port)
BuildRequires: pkgconfig(capi-appfw-service-application)
BuildRequires: pkgconfig(capi-appfw-app-common)

%description
Tizen C++ Action Sample Application

%prep
%setup -q

%build
%cmake .
%__make %{?_smp_mflags}

%install
%make_install

%files
%manifest packaging/my-action-app.manifest
/usr/apps/org.example.myactionapp/bin/my-action-app
/usr/apps/org.example.myactionapp/tizen-manifest.xml
/usr/share/packages/org.example.myactionapp.xml
```

## packaging/my-action-app.manifest

```xml
<manifest>
    <request>
        <domain name="_"/>
    </request>
</manifest>
```

## gbs.conf

```ini
[general]
profile = profile.action

[profile.action]
repos = repo.action_base, repo.action
buildroot = ~/GBS-ROOT-ACTION/

[repo.action_base]
url = http://download.tizen.org/snapshots/TIZEN/Tizen/Tizen-Base/reference/repos/standard/packages/

[repo.action]
url = http://download.tizen.org/snapshots/TIZEN/Tizen/Tizen-Unified/latest/repos/standard/packages/
```

## gen.sh

Identical to the C# template (including the `actionc-sync` step) except for the
language and output message:

```bash
echo "[1/1] actionc: generating C++ Browser action stub -> gen/ImplBrowser"
( cd "${GEN_DIR}" && "${ACTIONC_BIN}" -a Tizen.Action.Browser -l C++ -o ImplBrowser )
```

## run.sh

```bash
#!/usr/bin/env bash
#
# Automatically builds, deploys, and executes the my-action-app C++ test app on the device.
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

echo "=== [1/5] Building Tizen C++ Application (my-action-app) ==="
"${SCRIPT_DIR}/gen.sh"
gbs -c "${SCRIPT_DIR}/gbs.conf" build -B "${HOME}/GBS-ROOT-ACTION" -A armv7l --include-all

echo "=== [2/5] Deploying RPM to Tizen Target Board ==="
RPM_PATH=$(find "${HOME}/GBS-ROOT-ACTION/local/repos" -name "my-action-app-1.0.0-1.armv7l.rpm" -printf '%T@ %p\n' | sort -k1,1 -n | tail -1 | cut -f2- -d" ")
if [[ -z "${RPM_PATH}" ]]; then
  echo "error: Built RPM not found under ~/GBS-ROOT-ACTION/local/repos." >&2
  exit 1
fi
echo "Found RPM: ${RPM_PATH}"
sdb push "${RPM_PATH}" /tmp/
sdb shell "chmod 644 /tmp/my-action-app-1.0.0-1.armv7l.rpm && rpm -Uvh --force /tmp/my-action-app-1.0.0-1.armv7l.rpm"
sdb shell "tpk-backend -y org.example.myactionapp --preload"

echo "=== [3/5] Terminating any old active service processes ==="
sdb shell "killall my-action-app || true"

echo "=== [4/5] Executing action dynamically targeting C++ Application ==="
JSON="{\"id\": 11, \"params\": { \"name\": \"Tv_Tizen.Action.Browser_Go\", \"appid\": \"org.example.myactionapp\", \"arguments\": { \"Url\": \"${URL}\", \"Title\": \"${TITLE}\", \"Details\": \"${DETAILS}\" } } }"
sdb shell "action-tool execute '${JSON}'"

echo "=== [5/5] Fetching dlog logs for TIDL_ACTION_MYACTIONAPP ==="
sdb shell "dlogutil -d TIDL_ACTION_MYACTIONAPP"
```

`tpk-backend -y <pkgid> --preload` is what registers the RPM-installed package (and
therefore its `action/provider` metadata) with the package manager.

## Critical: Verify method signatures from the generated stub

**Do NOT assume action method signatures match the examples above.** The actual signatures
are determined by the `.action` schema for each action in the category. Always inspect
the generated header before implementing:

```bash
# After running gen.sh or actionc
grep -A 1 "virtual TizenEntityStatus" gen/ImplBrowser.h
```

Copy the exact method signature (parameter types, input vs. output references, count)
and implement it in your `ServiceBase` subclass. Mismatched signatures will cause:

- `marked 'override', but does not override` compilation errors
- `has not been declared` errors for wrong entity types
- Abstract class instantiation errors if methods don't match the pure virtual interface

If you get these errors after implementing the service class, check `gen/ImplXxx.h` for
the **exact** method signatures for your category.
