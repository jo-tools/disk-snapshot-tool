# Documentation

Developer documentation for Disk Snapshot Tool. For what the app does and how to
use it, start at the [main README](../README.md).

- **[build.md](build.md)** — building the app and the `qemu-img` it ships, the
  build cache, code signing, the supported disk image formats.
- **[architecture.md](architecture.md)** — layering, `qemu-img`, lock detection,
  persistence, licensing documents, sandboxing and file access, localization,
  tests.
- **[release.md](release.md)** — the release checklist.

See also [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md) for what is bundled
and under which licenses.

## Repository artwork

`resources/` (lower case) holds artwork for the repository, not for the app —
it is no part of the Xcode project. The app's own resources are in
`Disk Snapshot Tool/Resources/`.

- `GitHub-SocialPreview.afdesign` — the Affinity Designer template shared by all
  jo-tools projects; `GitHub-SocialPreview.png` is exported from it and uploaded
  under the repository's *Settings > Social preview*.
- `AppIcon.svg` — the app icon flattened for layouts such as the social preview:
  `AppIcon.icon` without its glass effects, with the plate gradient converted to
  sRGB. Redraw it whenever the app icon changes.
