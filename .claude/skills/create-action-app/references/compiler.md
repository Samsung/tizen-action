# Compiler, schemas, and how they map to stub code

## Binaries

| Tool | Role | Env override |
| --- | --- | --- |
| `actionc` | orchestrator: `.action` → `.tidl` → stub | `ACTIONC` (in gen.sh templates) |
| `action2tidl` | `.action`/`.entity` (JSON) → `.tidl` | `ACTIONC_ACTION2TIDL` |
| `tidlc` | `.tidl` → C / C++ / C# / JS / Dart / Rust stub & proxy | `ACTIONC_TIDLC` |
| schema data | `actions/*.action`, `entities/*.entity`, `action.seq` | `ACTIONC_DATA_DIR` |
| `actionc-sync` | fetches the schema data for the device's `tizen-action` version | `ACTIONC_DATA_REPO` (default from `data-repo.conf`) |

Installed by `./install.sh` (Linux) / `./install-macos.sh` (macOS) / `install.bat`
(Windows) into `~/.action-tools`, which is also prepended to `PATH` in `~/.bashrc` and
`~/.profile` (Linux) or `~/.zprofile` and `~/.bash_profile` (macOS).

## actionc-sync CLI

```
actionc-sync [options]
  -t, --target VERSION   tizen-action version to sync to (default: DATA_VERSION in
                         ~/.action-tools/data-repo.conf, else read off the device over sdb)
  -l, --list             versions available in the data repository
  -d, --data-dir DIR     install into DIR instead of ~/.action-tools/data
  -o, --offline          reuse the last fetch; no network
  -q, --quiet
```

Data repository layout: `<tizen-action version>/{actions,entities,action.seq}`; the
exact version directory is used, else the highest same-`<major>.<minor>` one not newer
than the device. The installed set records itself in `data/DATA_VERSION`. Windows:
`actionc-sync.bat` (wraps `actionc-sync.ps1`), same options as `-Target`, `-List`, ...

## actionc CLI

```
actionc [OPTION...]
  -l, --language=LANGUAGE   C, C++, C#, JS, Dart, ... (default: C++), passed to tidlc
  -i, --input=INPUT         custom .action file, repeatable; name must be
                            '<prefix>_<category>_<method>.action'
  -a, --action=CATEGORY     framework action category (e.g. Tizen.Action.Browser)
  -o, --output=OUTPUT       generated interface file base name (no extension)
  -e, --entity=PATH         extra .entity file or directory, repeatable
  -d, --data-dir=DIR        directory holding actions/ and entities/
      --keep-temp           keep the intermediate .tidl files and print their directory
  -v, --version
```

Examples:

```bash
actionc -a Tizen.Action.Browser -l C++ -o ImplBrowser          # framework category
actionc -i My_Custom.Action.Memo_Save.action -l C# -o ImplMemo  # custom action
actionc -i My_Custom.Action.Memo_Save.action -e ./entities -l JS -o ImplMemo
```

Output extension follows the language: `.cs`, `.h`+`.cc`, `.js`, `.dart`.
`actionc` writes relative to the current directory — `cd` into the target dir first.

Underneath, `actionc` runs (visible in its log output):

```bash
action2tidl <all entities> -o <tmp>                                   # entity .tidl files
action2tidl <category actions> -e <entities dir> -o <tmp>/<Category>.tidl
tidlc -s -l <LANG> -I <tmp> -i <tmp>/<Category>.tidl -o <Output>
```

`tidlc -s` generates the stub (provider side); `-p` would generate the proxy (caller side).

## Discovering what exists

```bash
D="${ACTIONC_DATA_DIR:-$HOME/.action-tools/data}"
grep -h '"category"' "$D"/actions/*.action | sort -u   # categories
ls "$D/actions"                                       # action names (file basenames)
ls "$D/entities"                                      # entity types
```

Categories currently shipped: `Tizen.Action.{Accessibility, App, Art, Broadcast,
Browser, Calendar, Camera, Display, Game, Health, Home, IoT, MultiView, Music, Photo,
Schedule, ScreenShare, Settings, Support, Video, Volume}` (file prefix `Tv_`) and
`Tizen.Internal.Action.View` (file prefix `Common_`).

## .action schema

```json
{
  "version": "v2",
  "name": "Tv_Tizen.Action.Browser_Go",
  "type": "tidl",
  "category": "Tizen.Action.Browser",
  "description": "open a URL in the browser",
  "allowedBackground": "true",
  "autoDispose": "false",
  "inputSchema":  { "type": "Tizen.Entity.Browser" },
  "outputSchema": { "type": "Tizen.Entity.Status" },
  "details": { "appid": "org.tizen.next-browser" }
}
```

* File name **must** be `<prefix>_<category>_<method>.action`; `<method>` becomes the
  stub method name (`Go`), and the whole basename is the action name used by
  `action-tool` and by the `action/provider` metadata.
* All actions of one category are compiled into a single TIDL interface named after
  the category (`Tizen.Action.Browser` → class `TizenActionBrowser`).

An action that returns an entity in addition to status uses an object output schema
with the reserved property names `return` (status) and `result`:

```json
"inputSchema":  { "type": "object", "properties": {} },
"outputSchema": {
  "type": "object",
  "properties": {
    "return": { "type": "Tizen.Entity.Status",  "description": "status" },
    "result": { "type": "Tizen.Entity.Browser", "description": "Result entity" }
  }
}
```

## .entity schema

```json
{
  "typeName": "Tizen.Entity.Browser",
  "description": "a web page",
  "base": "Tizen.Entity",
  "dataSchema": {
    "type": "object",
    "properties": {
      "Url":     { "type": "string", "description": "Url" },
      "Title":   { "type": "string", "description": "Title" },
      "Details": { "type": "string", "description": "Details" }
    }
  }
}
```

`base` gives inheritance — `Tizen.Entity` contributes `Id` and `Extra` to every entity,
so those are also valid `arguments` keys when executing an action.
`Tizen.Entity.Status` (`Success`, `Reason`) is the return type of every action.

## Schema → generated signature

For `Tizen.Action.Browser` (C# shown; other languages are analogous):

| Action file | Generated method |
| --- | --- |
| `Tv_Tizen.Action.Browser_Go` | `TizenEntityStatus Go(TizenEntityBrowser browser)` |
| `Tv_Tizen.Action.Browser_GetCurrent` | `TizenEntityStatus GetCurrent(out TizenEntityBrowser result)` |
| `Tv_Tizen.Action.Browser_ToCalendar` | `TizenEntityStatus ToCalendar(TizenEntityBrowser browser, out TizenEntityCalendar result)` |
| `Tv_Tizen.Action.Browser_ToPresentation` | `TizenEntityStatus ToPresentation(TizenEntityBrowser browser, out TizenEntityPresentation result)` |

Rules:

* Entity type `Tizen.Entity.MusicFile` → class `TizenEntityMusicFile`, parameter name
  `musicFile` (leaf name, lower camel case).
* An output list (e.g. `Tizen.Action.Music_FindAlbum`) becomes
  `out List<TizenEntityAlbum> result` / `std::vector<...>&`.
* Output params are `out` (C#), `&` reference (C++), and a pre-allocated object to
  mutate (JS/Dart).
* The generated file also contains every referenced entity class, so no extra imports
  beyond the stub's namespace are needed.

Per language, the stub namespace / class layout is:

| Language | Namespace / import | Stub class | Service base |
| --- | --- | --- | --- |
| C# | `RPCPort.ImplBrowser`, `RPCPort.ImplBrowser.Stub` | `TizenActionBrowser` | nested `TizenActionBrowser.ServiceBase` (abstract) |
| C++ | `rpc_port::implbrowser`, `::stub` | `TizenActionBrowser` | `TizenActionBrowser::ServiceBase` + `ServiceBase::Factory` |
| JS | global (script include) | `TizenActionBrowser extends tizen.rpcport.StubBase` | `TizenActionBrowserServiceBase` |
| Dart | `import 'ImplBrowser.dart'` | `TizenActionBrowser extends StubBase` | `ServiceBase` (abstract) |

## Triggering actions on the device

```bash
sdb shell "action-tool execute '{\"id\": 10, \"params\": { \"name\": \"<action name>\", \"appid\": \"<app id>\", \"arguments\": { <flattened input entity properties> } } }'"
```

`id` is an arbitrary caller-side request id (the samples use 10/11/12/15 to keep their
logs apart). `arguments` may be `{}` for actions with an empty input schema.
