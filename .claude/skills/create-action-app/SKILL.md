---
name: create-action-app
description: Scaffold a Tizen Action Framework provider app (C#, C++, JavaScript, or Dart/Flutter) with the actionc/action2tidl/tidlc compiler - generates the TIDL service stub from an .action category, writes the app entry point, manifest with per-action provider metadata, and gen.sh/run.sh build-deploy-test scripts. Use when asked to create/add an action provider app, an action sample app, implement an action category, register an app as an action provider, or generate action stubs with actionc.
---

# Creating a Tizen Action provider app

An **action provider app** implements one action category (e.g. `Tizen.Action.Browser`)
as an rpc-port TIDL *stub*. The Action Framework (`action-tool`, the action service)
acts as the *proxy* and calls into the app.

Pipeline: `.action`/`.entity` JSON schemas → **action2tidl** → `.tidl` → **tidlc** → language stub.
**actionc** drives both steps; only call `action2tidl`/`tidlc` directly when debugging.

Reference implementations to mirror (siblings of this repo, if present):
`ActionSampleAppCs`, `ActionSampleAppCpp`, `ActionSampleAppJs`, `ActionSampleAppDart`.

## Step 1 — Check the compiler is installed and sync the schemas

```bash
command -v actionc || ls ~/.action-tools/actionc     # else run ./install.sh in this repo
actionc -v
actionc-sync        # schemas matching the attached device's tizen-action (or --target X.Y.Z)
```

`actionc` resolves `ACTIONC_DATA_DIR` (default `~/.action-tools/data`),
`ACTIONC_ACTION2TIDL`, `ACTIONC_TIDLC`. If the shell profile has not been reloaded,
export them explicitly or fall back to `~/.action-tools/...` (see gen.sh templates).

`actionc-sync` fetches the action/entity schemas for the device's `tizen-action` version
from the data repository in `~/.action-tools/data-repo.conf` into `~/.action-tools/data`;
the compiler ships no schemas, so nothing compiles until it has run once. Without a device, pass
`--target <version>` or set `DATA_VERSION` in that conf; without network, `--offline`
reuses the last fetch. Every `gen.sh`
runs it first (best effort) so stubs always match the device.

## Step 2 — Settle the inputs

Ask the user only for what is missing; pick sensible defaults otherwise.

| Input | Default / how to derive |
| --- | --- |
| Language | ask: `C#` / `C++` / `JS` / `Dart` |
| Action category | ask; must exist in the data dir (see below) |
| App name | `ActionSampleApp<Lang>`-style, or the user's name |
| Package/app id | `org.example.<lowercasedappname>` (Web app: `<pkgid>.<AppName>`) |
| dlog tag | `TIDL_ACTION_<APPNAME>` — used for every log line and for `dlogutil` |
| Stub output base | `Impl<CategoryLeaf>`, e.g. `ImplBrowser` |

List the available categories and the exact action names of one category:

```bash
D="${ACTIONC_DATA_DIR:-$HOME/.action-tools/data}"
grep -h '"category"' "$D"/actions/*.action | sort -u          # all categories
ls "$D/actions" | grep -F '.Browser_' | sed 's/\.action$//'   # action names of a category
```

The **action name** is the file basename without `.action` and keeps its profile prefix
(`Tv_Tizen.Action.Browser_Go`, `Common_Tizen.Internal.Action.View_FindById`); the
`-a` option takes the **category** without the prefix (`Tizen.Action.Browser`).

Read `references/compiler.md` for the `.action`/`.entity` schema, custom (`-i`/`-e`)
actions, and how schemas map onto stub method signatures.

## Step 3 — Generate the stub

Run `actionc` **from the directory the stub belongs in** (it writes relative to cwd):

```bash
cd gen && actionc -a Tizen.Action.Browser -l C# -o ImplBrowser
```

`-l` values: `C#`, `C++`, `JS`, `Dart`. Add `--keep-temp` to inspect the intermediate
`.tidl`. Output lands in `gen/` (C#, C++), `js/` (Web), `lib/` (Flutter).

Never hand-edit generated stubs — regenerate via `gen.sh`.

## Step 4 — Scaffold the project

Follow the per-language reference, which contains the full file set (project/build
files, entry point, manifest, `gen.sh`, `run.sh`) ready to adapt:

* `references/csharp.md` — .NET NUI app, `dotnet build`, `.tpk` via `sdb install`
* `references/cpp.md` — service app, CMake + GBS, `.rpm` push + `tpk-backend --preload`
* `references/javascript.md` — Tizen Web app, `tizen build-web`/`package`, `.wgt`
* `references/dart.md` — Flutter-tizen app, `flutter-tizen build tpk`

Every app needs three things to work:

1. **Implement the service base.** Subclass the generated `ServiceBase` and override
   `OnCreate`/`OnTerminate` plus one method per action. C#/C++ use PascalCase action
   names (`Go`, `GetCurrent`); JS/Dart prefix with `on` (`onGo`, `onGetCurrent`).
   Actions return `TizenEntityStatus` (`Success`, `Reason`); an action with an output
   entity also takes a `result` out-parameter to fill in.
2. **Listen on app start**, and log with the app's dlog tag so `dlogutil` can verify.
   The rpc-port name equals the interface class name (`TizenActionBrowser`).
3. **Register as provider per action** — one metadata entry per action name, not one
   for the category:

   ```xml
   <metadata key="http://tizen.org/metadata/action/provider" value="Tv_Tizen.Action.Browser_Go" />
   ```

   (`tizen-manifest.xml` for C#/C++/Dart, `<tizen:metadata .../>` in `config.xml` for Web.)
   Privileges: `http://tizen.org/privilege/datasharing` and `.../appmanager.launch`.

## Step 5 — Build, deploy, verify

Give the app a `run.sh` that does build → install → restart → execute → dlog, matching
the samples. The action is triggered on the device with `action-tool`:

```bash
sdb shell "action-tool execute '{\"id\": 10, \"params\": { \"name\": \"Tv_Tizen.Action.Browser_Go\", \"appid\": \"org.example.myactionapp\", \"arguments\": { \"Url\": \"https://tizen.org\", \"Title\": \"Tizen OS\", \"Details\": \"Rpi4 Board\" } } }'"
sdb shell "dlogutil -d TIDL_ACTION_MYACTIONAPP"
```

`arguments` are the flattened properties of the action's input entity (including
inherited ones such as `Id`/`Extra` from `Tizen.Entity`).

Without a device, stop after `gen.sh` plus a host-side compile check where one exists
(`dotnet build`, `cmake`) and say plainly that on-target verification was not run.

## Step 6 — Document it

Add a `README.md` shaped like the samples': project structure, prerequisites
(`./install.sh` of the Tizen Action Compiler, plus TizenFX for C#), automated run, then
the manual build / deploy / execute / dlog steps.

## Gotchas

* Generated stub code is excluded from strict warning flags in the C++ sample
  (`-Wno-error` on `gen/ImplBrowser.cc`) — keep that when copying CMake settings.
* A Web app must set `background-support="enable"` and an `app-control` `<tizen:src>`
  with `reload="disable"`, otherwise the listening stub dies or reloads on relaunch.
* `actionc` fails with `no action files for category '...'` when the category name is
  wrong or `ACTIONC_DATA_DIR` points somewhere without `actions/`.
* `actionc-sync` fails with `no schema data for tizen-action X.Y.Z` when the data
  repository has no directory for that `<major>.<minor>` line; `--list` shows what exists.
  A stub generated from the wrong schema version is rejected by the device at runtime.
* Keep the manifest `exec`/`type` consistent with the build output
  (`.dll` + `dotnet`, binary + `capp`).
