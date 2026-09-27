# Third-Party Notices

Disk Snapshot Tool bundles one third-party executable, `qemu-img`, at
`Contents/Helpers/qemu-img`.

The binary is built from pinned upstream source by `Scripts/build-qemu-img.sh`,
using the versions and checksums in `Scripts/versions.env`. The QEMU, GLib,
proxy-libintl and Zstandard sources are built as published, without patches.

## What is bundled

| Component | Version | License | Full text |
|---|---|---|---|
| QEMU (`qemu-img` only) | 11.1.1 | GPL-2.0-**only** | [QEMU-GPL-2.0.txt](THIRD-PARTY-LICENSES/QEMU-GPL-2.0.txt), [QEMU-LICENSE.txt](THIRD-PARTY-LICENSES/QEMU-LICENSE.txt) |
| GLib (`libglib-2.0` only) | 2.88.0 | LGPL-2.1-or-later | [GLib-LGPL-2.1.txt](THIRD-PARTY-LICENSES/GLib-LGPL-2.1.txt) |
| proxy-libintl | 0.5 | LGPL-2.0-or-later | [proxy-libintl-LGPL-2.0.txt](THIRD-PARTY-LICENSES/proxy-libintl-LGPL-2.0.txt) |
| Zstandard | 1.5.7 | BSD-3-Clause (dual GPL-2.0) | [Zstandard-LICENSE.txt](THIRD-PARTY-LICENSES/Zstandard-LICENSE.txt) |

GLib, proxy-libintl and Zstandard are **statically linked** into `qemu-img`.
proxy-libintl arrives through one of GLib's meson wraps, which pin its source by
hash. Everything else the binary links — `libSystem`, `libz`, `libiconv`,
`libobjc`, CoreFoundation, Foundation, IOKit — is part of macOS and is not
redistributed.

GLib's build also compiles PCRE2 and libffi from its meson wraps, adding meson
build files to both and applying one patch to PCRE2. Neither is linked into
`qemu-img`: it uses no part of GLib that references them.

`pkgconf`, `ninja`, `meson` and `tomli` are build-time tools only. They are not
linked into the shipped binary.

These files are also copied into the application bundle, at
`Contents/Resources/`, and the Help menu shows them.

## QEMU is GPL-2.0-only

`qemu-img.c` and the qcow2 snapshot code it uses are MIT. The linked binary is
not, because `qemuutil` unconditionally includes GPL-2.0-only code:
`util/bitmap.c` (taken from the Linux kernel, "Version 2" with no "or later"),
and `util/module.c`, `util/aio-posix.c` and `util/qemu-sockets.c` (GPL-2.0 base,
only post-2012 contributions are v2-or-later).

So the shipped `qemu-img` is a **GPL-2.0-only** work. It cannot be treated as
v2-or-later, and GPLv3 §7 does not apply to it.

QEMU's `LICENSE` also states that "QEMU is a trademark of Fabrice Bellard".

## This application is not a derivative work of QEMU

Disk Snapshot Tool does not link QEMU. It launches `qemu-img` as a separate
process and communicates only through command-line arguments and standard
output. Under GPLv2 §2 ("mere aggregation") and the FSF's guidance that programs
communicating through "pipes, sockets and command-line arguments" are separate
programs, the application's own source is not a derivative work, and is licensed
under the [MIT License](LICENSE).

Distributing the binary is a separate matter, and carries the obligations below.

## Obligations when redistributing a build

GPLv2 §3 requires that recipients can obtain the complete corresponding source,
which explicitly includes "the scripts used to control compilation and
installation". GPLv2 §3 also allows this to be met by offering equivalent access
to copy the source from the same place as the binary.

Every release therefore carries, next to the download:

1. The source tarballs the build used, byte for byte: QEMU, GLib and Zstandard
   as pinned in `Scripts/versions.env`, and proxy-libintl, PCRE2 and libffi as
   pinned by GLib's wrap files, including the wrap patches. PCRE2 and libffi are
   not in `qemu-img`, but GLib's build does not complete without them.
2. This repository at the release's tag, which contains
   `Scripts/build-qemu-img.sh`, `Scripts/versions.env` and
   `THIRD-PARTY-LICENSES/`.

The release notes also name the upstream URLs of these sources. A build published
without its source attached is distributed in breach of §3.

GLib and proxy-libintl are LGPL and statically linked, so their §6 additionally
requires that recipients be able to relink `qemu-img` against a modified version.
The attached source plus the build script provides that: anyone can substitute a
modified GLib or proxy-libintl and re-run the build.

Distribution is by Developer ID signed and notarized builds. Notarization is a
signing service and attaches no terms to the recipient, who may copy, modify,
re-sign and pass on the build as GPLv2 §6 requires.
