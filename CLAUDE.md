# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A macOS SwiftUI app that manages the internal snapshots of qcow2 virtual disk
images by driving a bundled `qemu-img`. Any disk image comes first; a UTM
virtual machine's `.utm` bundle is recognised and its disks read from its
configuration. Swift 6, module-wide `MainActor` isolation, Swift Testing. No
third-party Swift dependencies — none are wanted.

The app's name and artwork carry nothing of UTM's: the icons are drawn for this
project, and the sidebar marks a VM bundle with the word "UTM", not the logo.
Keep it that way — derived artwork would bring back a licence and a trademark
question.

Read these rather than re-deriving them:

- [docs/architecture.md](docs/architecture.md) — layering, the `qemu-img` choke
  point, lock detection, persistence, tests
- [docs/build.md](docs/build.md) — the bundled `qemu-img` build, signing, weak
  imports, bumping versions
- [docs/release.md](docs/release.md) — release checklist and the GPL duty
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) — licensing facts

## Build and test

```sh
xcodebuild -scheme "Disk Snapshot Tool" -configuration Debug build
xcodebuild test -scheme "Disk Snapshot Tool" -destination "platform=macOS"
```

The first build compiles QEMU and GLib; later builds reuse the cached helper.
Prefer the Xcode MCP tools when they are available.

If `test` fails with "code object is not signed at all" in
`PlugIns/Disk Snapshot Tool Tests.xctest`, a plain build ran after a test build
and left the test bundle unsigned inside the app. Delete that `.xctest` from the
build products and run the tests again.

## Invariants — do not break these by accident

Each of these cost real debugging once. Where a linked doc holds the reasoning,
what follows is the short form.

- **`qemu-img` is launched only from `QemuImgService`.** Nothing else in the app
  starts a process; test fixtures may run the helper directly. New use cases go
  through `DiskOperations`.
- **A snapshot is identified by its qcow2 ID, not its tag.** Tags need not be
  unique, and qcow2 silently cuts them at 255 bytes. Apply passes the ID, which
  `snapshot -a` looks up first. `snapshot -d` takes only a tag and deletes the
  first snapshot carrying it, so a delete is refused unless the chosen snapshot
  is that first one. New tags are refused when taken or too long
  (`Snapshot.problem(withName:existing:)`).
- **`-U` / `--force-share` belongs on `info` and nowhere else.** On
  `snapshot -c/-a/-d`, QEMU's lock is the last thing standing between a mis-click
  and a corrupted disk. Never pass it there.
- **The helper's entitlements are exactly two**, `app-sandbox` and `inherit`.
  A third one breaks sandbox inheritance and the helper is killed at launch. This
  is why `Scripts/embed-qemu.sh` signs it explicitly instead of letting Xcode do
  it.
- **`QEMU_IMG_MACOS_MIN` follows the app's deployment target, never below it.**
  A lower target widens the weak-import window, and a weak-imported symbol is a
  segfault at runtime rather than an error. Do not remove
  `-Werror=unguarded-availability-new` or `-Wl,-no_weak_imports` to make a build
  pass.
- **Checksums in `versions.env` are verified against an independent publisher**,
  not computed from whatever the download returned. A mismatch fails the build and
  is never downgraded to a warning.
- **Tests never touch real user data.** The test plan sets
  `DISK_SNAPSHOT_TOOL_STORAGE=scratch`; the host app is the real app, so without
  that a test run would rewrite the user's library. A scratch run keeps the
  library and defaults in memory and opens no window, so it writes nothing to
  the container.
- **Reject invalid input at the earliest point.** A drag is accepted or refused
  synchronously, before any probe could run, so the filename is vetted then —
  no drop badge for a file that would only be rejected afterwards. The Open
  panel applies the same rule through its delegate (`OpenPanel`), which is why
  it is not SwiftUI's `fileImporter`: that filters by type, and `.img` shares
  its type with `.dmg`.
- **`qcow2` is the only format that can hold snapshots.** Verified against QEMU's
  source: it is the only local driver implementing `bdrv_snapshot_create`. `raw`
  is a fallback, not an identification — `qemu-img` reports anything it does not
  recognise as raw.
- **`DEVELOPMENT_TEAM` stays out of `project.pbxproj`.** It lives in
  `Config/Signing.xcconfig`, overridable through the gitignored
  `Config/Signing.local.xcconfig`. A pbxproj build setting overrides an xcconfig,
  so a team written back by Xcode's Signing tab silently defeats it — revert such
  diffs. Do not make ad-hoc the default: an ad-hoc signature changes on every
  build, which makes macOS re-prompt to open the app each time.
- **The About panel is the system's.** Its credits come from
  `Resources/Credits.html`, which macOS reads by itself. Do not use
  `CommandGroup(replacing: .appInfo)` to do the same thing by hand — that costs
  the menu item its system icon and behaviour.
- **Licensing documents open in-app**, never by handing the file to another
  application. See `Views/Legal/`.
- **Every UI string is localized, in all five languages.** English is the source;
  German, French, Spanish and Italian live in `Resources/Localizable.xcstrings`.
  A new or changed string is not done until it has all four translations. Text
  that travels as a `String` (errors, status reasons, confirmation texts) is
  built with `String(localized:)` where it is created, because Xcode extracts
  only literals. See [architecture.md](docs/architecture.md#localization).
- **The app name stays "Disk Snapshot Tool" in every language.** It is marked
  *do not translate* in the catalog, and a translation that contains it keeps
  it verbatim.
- **The test plan pins the language to English.** The tests run inside the host
  app, which would otherwise follow the Mac's language, and some assert English
  text.

## Sidebar quirks worth remembering

Per-row `onDrop` and `onGeometryChange` modifiers kill List selection. The working
arrangement is `onDrag(preview:)` on the row plus a List-level `onDrop`, and the
drag preview needs a resolved colour because drag images render without the
window's appearance.

## Localization

- **Whole sentences as keys.** Never piece a UI string together from fragments
  (a noun plus " in Finder"); write each variant out, as `RevealButtons` does.
  Counts go into the sentence as an interpolated integer, which gives the key
  plural variations.
- **Not translated:** the app name, *UTM*, *QEMU*, *qemu-img*, *qcow2* and the
  other format names, *Finder*; VM, file and snapshot names; `qemu-img` output;
  log messages; `Credits.html` and the licensing documents.
- **Menu paths in text use the localized macOS menu names**: *File* is *Ablage*,
  *Fichier*, *Archivo*, *File*.
- **German is written in the Swiss style**: always *ss*, never *ß*; guillemets
  «…»; *Sie* or impersonal wording. There is one German localization (`de`), so
  this applies to readers in Germany and Austria too. System-supplied menu items
  (such as *Schließen*) come from macOS and are out of our hands.
- **French, Spanish and Italian** address the user formally or impersonally
  (*vous*, *usted*, infinitive). French uses « … » and a narrow no-break space
  before *?* *!* *;*, a no-break space before *:*. Spanish and Italian use «…».
- **Glossary.** *snapshot*: Snapshot, instantané, instantánea, istantanea.
  *Disk image*: Disk-Image, image disque, imagen de disco, immagine disco.
  *VM bundle*: VM-Paket, paquet de la VM, paquete de la VM, pacchetto VM.
  *Reveal in Finder*: Im Finder zeigen, Afficher dans le Finder, Mostrar en
  Finder, Mostra nel Finder.

## Conventions

- **English** in code, comments and documentation. UI strings are written in
  English and translated in the string catalog; see *Localization* above.
- **Terminology.** A VM's disk is a *virtual disk image* where it is first
  introduced or could be mistaken for something else, and plain *disk image* or
  *disk* after that. One added on its own rather than through its VM is a
  *loose disk image*. The release `.dmg` is never called a disk image — that
  name belongs to the thing the app works on.
- **Spelling.** British in comments and documentation (*behaviour*, *colour*,
  *recognise*). *License* keeps the spelling the documents themselves use.
- **UI copy.** Menu items, buttons and alert titles are in title case
  (*Remove from List?*). Text that points at a menu item quotes it exactly, as
  *File > Open Disk Image or VM…*.
- **Comments only where the code cannot speak for itself**: a non-obvious
  decision, a trap, an external fact such as QEMU's behaviour. No comments that
  restate the code, no history, and each rationale once, where the decision is
  made.
- **No explicit `@MainActor`.** It is the module default
  (`SWIFT_DEFAULT_ACTOR_ISOLATION`); code that must run elsewhere says
  `nonisolated`.
- Commit subjects use the existing prefixes: `feat:`, `fix:`, `ui:`, `build:`,
  `docs:`, `refactor:`, `chore:`.
- `README.md` is for people visiting the repository. Internals belong in `docs/`.
  Do not grow the README back into a developer document.
- `resources/` (lower case) is repository artwork, not app resources — see
  [docs/README.md](docs/README.md#repository-artwork). A change to the app icon
  is carried over into `resources/AppIcon.svg`.
