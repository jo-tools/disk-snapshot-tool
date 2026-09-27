# Release Checklist

A release is a notarized Developer ID build of the app in a signed, notarized
`.dmg`, attached to a tag of this repository on GitHub together with the source
of the bundled `qemu-img`. There is no release script and no CI — this is the
checklist.

## 1. Prepare

- [ ] `Scripts/versions.env` — bump only deliberately, and re-verify every SHA-256
      against an independent publisher. See
      [build.md](build.md#updating-qemu-or-its-dependencies).
- [ ] If a version was bumped, it is written out in four more places:
      `Disk Snapshot Tool/Resources/Credits.html`,
      [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md), [build.md](build.md)
      and the release notes below.
- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project.
- [ ] Tests green: `xcodebuild test -scheme "Disk Snapshot Tool" -destination "platform=macOS"`
- [ ] Working tree clean, and `project.pbxproj` free of any `DEVELOPMENT_TEAM`
      line Xcode may have written back in.

## 2. Archive and notarize the app

**Product ▸ Archive**, then distribute the archive from the Organizer with a
**Developer ID** identity: Xcode submits the build for notarization and exports
the notarized app. Then check it:

```sh
codesign -dv --verbose=4 "Disk Snapshot Tool.app"
codesign -d --entitlements - "Disk Snapshot Tool.app/Contents/Helpers/qemu-img"
xcrun stapler validate "Disk Snapshot Tool.app"
spctl -a -vv "Disk Snapshot Tool.app"
ls "Disk Snapshot Tool.app/Contents/Resources"
```

- The helper's entitlements must be exactly `com.apple.security.app-sandbox` and
  `com.apple.security.inherit`. A third one and it is killed at launch.
- `stapler validate` must find a ticket; if not, attach one with `xcrun stapler
  staple`. Without it an offline Mac refuses the app.
- `Contents/Resources/` must still carry `LICENSE`, `THIRD-PARTY-NOTICES.md` and
  `THIRD-PARTY-LICENSES/` — that is what the Help menu opens.

## 3. Build the .dmg

The `.dmg` is notarized with `notarytool`, which signs in to Apple with
credentials kept in the keychain under a name of your choosing. Store them once;
the command asks for the password, which is an
[app-specific password](https://support.apple.com/102654), not the Apple ID's own:

```sh
xcrun notarytool store-credentials "<profile-name>" \
    --apple-id "<apple-id>" --team-id "<team-id>"
```

Then, in the folder holding the exported app, set `PROFILE` to that name. The
file name carries no version and is the same in every release, so a link to the
latest release's `.dmg` never changes.

```sh
PROFILE="<profile-name>"
DMG="Disk-Snapshot-Tool.dmg"

mkdir dmg
ditto "Disk Snapshot Tool.app" "dmg/Disk Snapshot Tool.app"
ln -s /Applications dmg/Applications
hdiutil create -volname "Disk Snapshot Tool" -srcfolder dmg -format UDZO -ov "$DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
```

`spctl` must report `accepted` and `source=Notarized Developer ID`.

## 4. Collect the qemu-img source

The archive build left every source tarball it used in the build cache, already
verified against its pinned checksum. Copy the ones that make up `qemu-img`:

```sh
. Scripts/versions.env
DL=~/Library/Caches/ch.jo-tools.disk-snapshot-tool/qemu-img/downloads
mkdir source
cp "$DL/qemu-$QEMU_VERSION.tar.xz" "$DL/glib-$GLIB_VERSION.tar.xz" \
   "$DL/zstd-$ZSTD_VERSION.tar.gz" "$DL/glib-$GLIB_VERSION-wraps/"* source/
ls source
```

That is QEMU, GLib and Zstandard, plus what GLib's meson wraps fetched:
proxy-libintl, and PCRE2 and libffi with their wrap patches. PCRE2 and libffi are
not linked into `qemu-img`, but GLib's build needs them. `pkgconf`, `ninja` and
`tomli` are build tools and are not attached.

## 5. Publish

- [ ] Tag the commit *(`v.X.Y.Z`)* and create the GitHub release from that tag.
- [ ] Attach `Disk-Snapshot-Tool.dmg` and every file in `source/`.
- [ ] Take the checksum of the `.dmg`: `shasum -a 256 "$DMG"`
- [ ] Put the note below into the release notes, filling in the tag and that
      checksum.

```markdown
**SHA-256** of `Disk-Snapshot-Tool.dmg`: `<checksum>`

### Licensing

Disk Snapshot Tool's own source code is MIT licensed.

The bundled `qemu-img` is a separate program from the QEMU project, licensed
under **GPL-2.0-only**, with GLib, proxy-libintl and Zstandard statically linked
into it. It is built by `Scripts/build-qemu-img.sh` from the versions and
checksums pinned in `Scripts/versions.env`. Its corresponding source is attached
to this release, and the build scripts are this repository at `v.X.Y.Z`:

- https://github.com/jo-tools/disk-snapshot-tool/tree/v.X.Y.Z
- https://github.com/jo-tools/disk-snapshot-tool/blob/v.X.Y.Z/THIRD-PARTY-NOTICES.md

The attached source files were downloaded from:

- QEMU 11.1.1 — https://download.qemu.org/qemu-11.1.1.tar.xz
- GLib 2.88.0 — https://download.gnome.org/sources/glib/2.88/glib-2.88.0.tar.xz
- Zstandard 1.5.7 — https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz
- proxy-libintl 0.5 — https://github.com/frida/proxy-libintl/archive/refs/tags/0.5.tar.gz
- PCRE2 10.46 *(needed to build GLib, not linked)* — https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.46/pcre2-10.46.tar.bz2
  and wrap patch https://wrapdb.mesonbuild.com/v2/pcre2_10.46-1/get_patch
- libffi 3.5.2 *(needed to build GLib, not linked)* — https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
  and wrap patch https://wrapdb.mesonbuild.com/v2/libffi_3.5.2-1/get_patch
```

The first three URLs are in `Scripts/versions.env`, the others in GLib's
`subprojects/*.wrap` files.

GPLv2 §3 wants the corresponding source available from the same place as the
binary, and the LGPL wants GLib and proxy-libintl relinkable. Attaching the
tarballs keeps that true even if an upstream server drops an old release, and the
release's tag carries `Scripts/` and `THIRD-PARTY-LICENSES/` at the revision the
build came from. Publishing a build anywhere else needs the same files next to
the download.
