# Tizen Action schema data

Schema data for the Tizen Action Framework toolchain, published per
`tizen-action` version so that the installed toolchain binaries (`actionc`,
`action2tidl`, `tidlc`) can be reused while the action/entity schemas follow
the device.

> This is the `data` branch of `Samsung/tizen-action`; the toolchain itself
> lives on `main`. Keeping the schemas on their own branch lets `actionc-sync`
> shallow-clone them without the compiler binaries. The toolchain reads the
> repository URL and branch from `~/.action-tools/data-repo.conf`.

## Layout

One directory per `tizen-action` version, holding exactly what the toolchain
expects in its data directory:

```
<version>/
├── actions/*.action      # one per action
├── entities/*.entity     # one per entity type
└── action.seq            # canonical per-category action order (TIDL method ids)
```

`<version>` is the version `rpm -q tizen-action` reports on the device (for
example `1.10.2`). Nothing else at the top level is read by the toolchain.

## How the toolchain uses it

`actionc-sync` (installed by `TizenActionToolchain`) reads the device's
`tizen-action` version over `sdb`, fetches this repository, picks the matching
directory and installs it into `~/.action-tools/data`:

```bash
actionc-sync                 # match the attached device
actionc-sync --target 1.10.2  # pick a version explicitly
actionc-sync --list          # show the versions published here
```

Version matching: the directory named exactly like the device version is used
when it exists; otherwise the highest version with the same `<major>.<minor>`
that is not newer than the device. A device on a `<major>.<minor>` line with no
directory here is an error (the toolchain's `REQUIREMENTS` pins compatibility
to a minor version line).

## Publishing a version

The schemas are generated from `tizen-action-catalog` (`gen/actions`,
`gen/entities`) together with its `action.seq`. To publish the data for a
`tizen-action` release:

```bash
mkdir -p <version>
cp -R <catalog>/gen/actions <catalog>/gen/entities <version>/
cp <toolchain>/data/action.seq <version>/
git add <version> && git commit -m "Add schema data for tizen-action <version>"
```

A published directory must not change afterwards: `action.seq` fixes the TIDL
method ids that already-generated stubs depend on. A fix for an existing device
version is a new patch-level directory.
