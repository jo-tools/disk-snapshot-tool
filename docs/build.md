# Building from Source

```sh
git clone https://github.com/jo-tools/disk-snapshot-tool.git
cd disk-snapshot-tool
```

Open `Disk Snapshot Tool.xcodeproj` in Xcode and build. Nothing has to be installed
first: no Swift packages, no CocoaPods, no Homebrew, no UTM. The one third-party
component, `qemu-img`, is built from pinned upstream source as part of the build.

- Xcode 27 or later
- Network access on the first build only
- About 1.6 GB of disk space per build tree in the cache

The first build downloads about 150 MB of source and compiles GLib and QEMU, and
that takes a while; progress appears in the build log as `note: [qemu-img] …`
lines. Every build after that reuses the cache and is quick. Debug builds are
single-architecture, Release and Archive builds universal arm64 + x86_64.

## Code signing

Signing settings live in [`Config/Signing.xcconfig`](../Config/Signing.xcconfig),
not in `project.pbxproj`. They use an *Apple Development* identity and the
maintainer's team. Building without that team takes one command:

```sh
cd /path/to/disk-snapshot-tool
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

That file is gitignored and picked up through an `#include?`. As shipped it sets
`LOCAL_CODE_SIGN_IDENTITY = -`, so the build is ad-hoc signed and needs no Apple
developer account.

Picking a team in Xcode's *Signing & Capabilities* tab writes `DEVELOPMENT_TEAM`
back into `project.pbxproj`, which overrides the xcconfig. Revert that diff.

## The build cache

```
~/Library/Caches/ch.jo-tools.disk-snapshot-tool/qemu-img/
```

Outside DerivedData, so *Clean Build Folder* leaves it alone, and outside the
project, to keep a multi-gigabyte tree out of Time Machine and Spotlight and
because this project's path contains spaces, which GNU autotools cannot handle.
`QEMU_IMG_BUILD_ROOT` overrides the location.

`embed-qemu.sh` runs the build with `env -i`, passing on only `HOME`, `TMPDIR`,
`DEVELOPER_DIR`, `QEMU_IMG_BUILD_ROOT`, a system `PATH` and `LANG`. Xcode
exports every build setting, and make, meson and configure read the environment:
zstd's Makefile takes Xcode's `BUILD_DIR` as its object directory, and in an
archive that path contains spaces (`ArchiveIntermediates/Disk Snapshot Tool/`).
If a new step needs another variable, pass it on explicitly.

The cache key is `Scripts/versions.env` plus `Scripts/build-qemu-img.sh`, without
their whole-line comments and blank lines — and deliberately not the architecture
list, so switching between a Debug build and an archive does not force a rebuild.
Each key gets its own tree of about 1.6 GB and old ones are never pruned; delete
the directory to reclaim the space or to force a clean rebuild.

Every step writes a stamp once it has finished, and a later build skips only
stamped steps, so an interrupted build picks up where it stopped. `downloads/`
holds the pinned tarballs and, under `downloads/glib-<version>-wraps/`, the ones
GLib's meson wraps fetch; meson verifies those against the hashes in GLib's own wrap files.

## What the bundled qemu-img contains

| Component | Version | Upstream | License |
|---|---|---|---|
| QEMU *(`qemu-img` only)* | 11.1.1 | https://download.qemu.org/ | GPL-2.0-only |
| GLib *(`libglib-2.0` only)* | 2.88.0 | https://download.gnome.org/sources/glib/ | LGPL-2.1-or-later |
| proxy-libintl | 0.5 *(GLib's meson wrap)* | https://github.com/frida/proxy-libintl | LGPL-2.0-or-later |
| Zstandard | 1.5.7 | https://github.com/facebook/zstd | BSD-3-Clause |

All of them are statically linked, and the binary links no third-party dylibs at
all. GLib's build also compiles PCRE2 and libffi from its wraps, but neither ends
up in `qemu-img`: nothing it uses references GLib's regex code or GObject, so the
linker never pulls them out of the static archives. `nm` on the binary finds no
`pcre2` or `ffi_` symbol. The build checks for `LC_RPATH` entries and for `otool -L` dependencies
outside `/usr/lib/` and `/System/Library/`, and fails if that ever changes. For
the licensing consequences see [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

### Disk image formats

Built with the local format drivers — qcow2, raw, VMDK, VDI, VHDX, VPC, QED,
Parallels and LUKS — and without the network ones *(curl, libssh, NFS, rbd,
iSCSI)*, which keeps the binary and the license surface small.

Only qcow2 can hold snapshots: in QEMU 11.1 it is the only local driver
implementing `bdrv_snapshot_create`, and on anything else `qemu-img snapshot -c`
returns *Operation not supported*. The other drivers are in so the app can
*identify* a format; without them `qemu-img` probes every unrecognised file as
`raw`. That also makes `raw` a fallback rather than an identification, which is
why added files are vetted by filename as well *(`DiskImageFile.extensions`)*.

## Weak imports

An API that the SDK declares but the deployment target predates is weak-imported:
it links, resolves to NULL at runtime, and segfaults when called. Three settings
turn that into a build failure instead, and none of them may be removed to make a
build pass:

- **`QEMU_IMG_MACOS_MIN`** *(`versions.env`)* follows the app's deployment target
  and never goes below it. The helper inherits the app's sandbox and cannot run
  anywhere else, so a lower target buys nothing and only widens the window.
- **`-Werror=unguarded-availability-new`** fails the compile at the call site.
- **`-Wl,-no_weak_imports`** fails the link if one gets past the compiler.

meson needs one more step. Its `cc.has_function()` declares the symbol itself
instead of using the real header, which discards the availability attribute, so
the probe answers YES for an API that will be NULL at runtime.
`scrub_too_new_defines()` in `build-qemu-img.sh` deletes those `HAVE_*` defines
from GLib's generated `config.h` before anything is compiled against it. Extend
its list when a new SDK adds another such function.

## The helper's signature

`Scripts/embed-qemu.sh` installs `qemu-img` at `Contents/Helpers/qemu-img` and
signs it explicitly instead of letting Xcode do it. Its entitlements are exactly
`com.apple.security.app-sandbox` and `com.apple.security.inherit`, so it runs
inside the app's sandbox. Any third entitlement — Xcode injects
`com.apple.security.get-task-allow` into Debug builds — breaks that inheritance
and the helper is killed at launch. The script re-reads the signed entitlements
afterwards and fails the build if they are anything else.

Because of `inherit`, the installed helper cannot be run from a terminal: without
a sandboxed parent it aborts with SIGTRAP *(exit code 133)*. That is the
entitlement working. To check the binary itself, run the unsigned one the build
produced:

```sh
"$(ls -t ~/Library/Caches/ch.jo-tools.disk-snapshot-tool/qemu-img/*/qemu-img-* | head -1)" --version
```

That is the newest of the `qemu-img-<arch>` binaries the build keeps, one per
architecture set and cache key.

The app target also needs `ENABLE_USER_SCRIPT_SANDBOXING = NO`: the build phase
needs network access on the first run and writes to the cache outside the build
directory.

## Updating QEMU or its dependencies

Edit `Scripts/versions.env`. Any change there changes the cache key and forces a
rebuild.

- **Python.** The build runs `/usr/bin/python3`, the Python that comes with
  Xcode's developer tools *(3.9.6 as of Xcode 27)*. QEMU 11.1.1's `configure`
  needs >= 3.9; newer QEMU asks for more *(master: >= 3.12)*. A QEMU bump
  therefore has to be checked against the Python the current Xcode provides —
  one reason the version is pinned rather than tracked. Once Xcode's Python is
  3.11 or later, the `tomli` workaround in `versions.env` can go.
- **Checksums.** Every SHA-256 in `versions.env` was cross-checked against an
  independent publisher — upstream's own checksum file, or Homebrew's pinned
  value — rather than computed from the download. Do the same when bumping. A
  mismatch fails the build and is never downgraded to a warning.

No upstream source is patched. If that ever changes, the patch needs to be
committed to this repository next to the build scripts, so every tag carries
it, and [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md) has to say which
files it changes — GPLv2 §2(a) asks for a prominent notice.

## Tests

The test plan runs the suites inside the host app, which is how the integration
tests get a real sandbox and the real bundled `qemu-img`. It sets
`DISK_SNAPSHOT_TOOL_STORAGE=scratch`, so a run never reads or rewrites your own
library.

```sh
xcodebuild test -scheme "Disk Snapshot Tool" -destination "platform=macOS"
```
