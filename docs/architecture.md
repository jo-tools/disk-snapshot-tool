# Architecture

A SwiftUI app with one job: list, create, apply and delete qcow2 internal
snapshots on disk images, by driving `qemu-img`.

## Layering

Dependencies point one way: **Views → State → Services → Model**.

| Folder | Holds |
|---|---|
| `App/` | The `@main` entry point, the menu bar *(`AppCommands`)*, the About panel, the root split view, and the loggers |
| `Model/` | Plain data types: `DiskImage`, `VMBundle`, `Snapshot`, `DiskGroup`, `LibraryItem`, `SidebarSelection` |
| `State/` | The two `@Observable` objects views get from the environment: `Library` *(items and persistence)* and `SidebarModel` *(selection, collapse state, derived rows)* |
| `Services/` | Stateless code that touches files, processes and user defaults: `DiskOperations`, `QemuImgService`, `UTMBundleReader`, `LibraryStore`, `SecurityScope`, `DiskLockProbe`, `DiskLockMonitor`, `DiskWatcher`, `AppliedSnapshotStore`. None of it knows `State/`: `DiskLockMonitor` is handed a closure that lists the disks |
| `Views/` | SwiftUI, split into `Sidebar/`, `SnapshotBoard/`, `Legal/` and `Shared/`; `Sidebar/OpenPanel.swift` is the one AppKit panel |
| `Resources/` | Asset catalog, the Icon Composer app icon, the string catalog `Localizable.xcstrings` and `Credits.html` |

The module defaults to `MainActor` isolation *(`SWIFT_DEFAULT_ACTOR_ISOLATION`)*,
so nothing says `@MainActor`. `QemuImgService`, `DiskLockProbe`, the decoded
`qemu-img` records and the loggers say `nonisolated` explicitly.

## qemu-img

`Services/QemuImg/QemuImgService.swift` is the only code in the app that
launches a process. It drains stdout and stderr while the child runs — a pipe
holds 64 KiB, and a disk with a few hundred snapshots prints more than that.
Everything else goes through `Services/DiskOperations.swift`, which owns the four
use cases and keeps the `DiskImage` up to date.

| Use case | Command |
|---|---|
| Read format, sizes, snapshots | `qemu-img info -U --output=json <disk>` |
| Create | `qemu-img snapshot -c <tag> <disk>` |
| Apply / revert | `qemu-img snapshot -a <id> <disk>` |
| Delete | `qemu-img snapshot -d <tag> <disk>` |

`-U` / `--force-share` is on `info` and nowhere else. Without it the snapshot list
would go blank the moment a VM starts; `info` is read-only, so sharing cannot
disturb the VM. On the three mutating commands QEMU's lock is what stands between
a mis-click and a corrupted disk.

`stderr` is mapped to a typed `QemuImgError` — `imageLocked`, `imageNotFound`,
`snapshotNotFound`, `commandFailed` — so the UI does not echo shell messages. The
patterns are the ones the bundled `qemu-img` actually prints; a running VM holds
its image with shared locks, which reads as failing to get the "write" lock.

### Snapshot identity

qcow2 identifies a snapshot by a numeric ID. The tag is a label: `qemu-img`
accepts the same tag twice and cuts a longer one at 255 bytes without a word.
So `Snapshot.id` is the qcow2 ID, and the list, the selection and Apply use it —
`snapshot -a` looks an argument up as an ID before trying it as a tag. `snapshot -d`
takes only a tag and deletes the first snapshot that carries it, so
`DiskOperations` refuses a delete unless the chosen snapshot is that first one.
The app itself never creates an ambiguous tag: `Snapshot.problem(withName:existing:)`
refuses a taken or over-long one, in the sheet and again before `snapshot -c`.

### Errors

A `DiskImage` keeps two: `readError` belongs to `refresh` and clears with the next
successful read; `operationError` belongs to create, apply and delete and stays
until dismissed or replaced by the next operation, however many refreshes the
file watcher triggers in between.

## Lock detection

Three independent layers keep the app from writing to a disk that another QEMU
process holds open — typically a running VM, but equally another `qemu-img` or
`qemu-nbd`:

1. **The UI does not offer it.** `DiskImage.canMutate` is false while the image is
   unreachable, in use, loading or not qcow2; badge and banner are defined once in
   `Views/Shared/DiskStatus.swift`. The "in use" signal comes from
   `Services/DiskLockProbe.swift`, which detects such a process without launching
   anything: QEMU holds an advisory `fcntl` lock on byte **201** of every image it
   opens *(`RAW_LOCK_SHARED_BASE + BLK_PERM_WRITE` in `block/file-posix.c`)*, and
   the probe tests that byte with `F_OFD_GETLK` — one `open`/`fcntl`/`close`, no
   extra entitlement. `DiskLockMonitor` polls every three seconds; a lock is not a
   content change, so `DiskWatcher`'s kqueue never fires for it. The poll skips a
   disk while `isLoading` is set: the app's own `qemu-img` holds the same byte.
2. **`DiskOperations` re-probes immediately before each mutation**, closing the gap
   between the last poll and the click. `isLoading` is held from that probe to the
   end of the operation, so no refresh or poll interleaves.
3. **`qemu-img` refuses on its own**, mapped to `QemuImgError.imageLocked`. This is
   the actual guarantee, and the reason layer 1 can be advisory.

Blind spots: a process that opens the file without QEMU's locks — a Finder copy,
a backup tool — goes unnoticed, and network volumes *(SMB/NFS)* may not honour
`fcntl` locks, so a busy image there can look idle. Layer 3 relies on the same
locks and shares both.

## Persistence

| What | Where |
|---|---|
| The library *(VM bundles and loose disk images, in sidebar order)* | `~/Library/Application Support/Disk Snapshot Tool/library.json` |
| Sidebar selection and collapsed rows | `UserDefaults` |
| Which snapshot was last applied to each disk | `UserDefaults`, via `AppliedSnapshotStore` |

`AppEnvironment` decides this per run. `DISK_SNAPSHOT_TOOL_STORAGE=scratch`, which
the test plan sets, keeps the library and defaults in memory and suppresses the
main window, so a test run writes neither a window frame nor saved state.

`LibraryStore` treats only a missing library.json as an empty library. A file it
cannot decode is set aside as `library-unreadable-<date>.json`; a file it cannot
read, or cannot set aside, turns saving off for the session. Either way the
empty list the app then shows never replaces the user's only copy.

A VM bundle's disks are not stored: `UTMBundleReader` re-reads the bundle's
`config.plist` on every launch, so a disk added or removed in UTM shows up without
a sync step. Only loose disk images are recorded individually.

`AppliedSnapshotStore` records the applied snapshot's name together with the disk
file's modification time, and reports it only while that mtime is unchanged and
exactly one snapshot carries the name — so the checkmark disappears once the VM
has run.

## Licensing documents

`LICENSE`, `THIRD-PARTY-NOTICES.md` and `THIRD-PARTY-LICENSES/` are copied into
`Contents/Resources` and shown in-app rather than handed to whatever application
owns `.md`: the bundled `qemu-img` is GPL-2.0-only, GLib is statically linked
under LGPL-2.1, and §6 asks for a notice in each copy of the work.
`Model/LegalDocument.swift` enumerates the documents, `Views/Legal/` renders them
in a `WindowGroup(id:for:)`, so opening one twice brings the existing window
forward. License texts are shown verbatim in a fixed-pitch font — rewrapping one
would misrepresent it.

Only the notices are Markdown, and Apple ships a parser but no renderer. So
`Views/Legal/MarkdownBlock.swift` parses nothing itself: it regroups what
`AttributedString(markdown:)` returns, a flat run of characters whose
`presentationIntent` spells out the block each run sits in, innermost first. Two
traps, both covered by tests — the intent chain has to be matched from the outside
in *(a quote is `paragraph > blockQuote`, so paragraph is the fallback and never
the first check)*, and a font on the `AttributedString` beats the `.font()`
modifier.

## Sandboxing and file access

The app is sandboxed and reaches files only through what the user opened or
dropped. `SecurityScope` wraps app-scoped security-scoped bookmarks, which is what
lets a VM added once still be there after a relaunch; every `qemu-img` invocation,
lock probe and kqueue watch runs inside `startAccessingSecurityScopedResource()`.

An item whose file cannot be reached is kept as unavailable rather than dropped —
that is what a disk on an unplugged external drive needs. Only the user removes
items. Whenever the app becomes active, and on Retry or ⌘R, an unavailable item's
bookmark is resolved again, so a reconnected drive or a file moved or renamed
while the app ran comes back without a relaunch. For a VM that also re-reads
`config.plist`, including its name.

Duplicates are judged on paths with symlinks resolved, as bookmarks resolve them.
A disk inside a listed VM counts as listed, and a VM whose disks are already
listed on their own is refused, since both would claim the same sidebar row.

The Open panel and a drop vet the filename against `DiskImageFile` before
anything else runs; `OpenPanel` does it through `NSOpenSavePanelDelegate`
because `fileImporter` can only filter by type, and `.img` shares its type with
`.dmg`. VMs of both UTM backends are read: Apple Virtualization drives carry no
`ImageType` and mark removable media `ReadOnly`.

For the helper's entitlements see [build.md](build.md#the-helpers-signature).

## Localization

English is the development language. `Resources/Localizable.xcstrings` holds
German, French, Spanish and Italian, and the project's `knownRegions` lists
them, which is also what makes AppKit localize the system menus. German is
written in the Swiss style *(ss, never ß)*, for every German reader. The
conventions and the glossary are in [CLAUDE.md](../CLAUDE.md#localization).

Xcode extracts only string literals that reach a `LocalizedStringKey` — `Text`,
`Button`, `.help` and the like. Text that travels as a `String` first is
localized where it is created, with `String(localized:)`: `Snapshot.problem`,
`DiskStatus` lines, `Availability.unavailable` reasons, `QemuImgError` and the
other error descriptions, the confirmation texts, `LegalDocument.title` and the
Open panel. Types such as `Availability` stay `Equatable` on plain strings.
A literal behind `??` is a `String`, not a key, and needs the same treatment.

Deliberately left in English: the app name, `Credits.html` *(the About panel)*,
the licensing documents, log messages, and everything that comes from outside —
VM, file and snapshot names, UTM's drive types, `qemu-img` output. Dates and
sizes go through `formatted` and `ByteCountFormatter`, which follow the locale.

A command-line build does not update the catalog; Xcode does when it builds.
Outside Xcode, `xcrun xcstringstool sync` against the build's `.stringsdata`
files does the same.

## Tests

`Disk Snapshot Tool Tests/` uses Swift Testing. The unit suites cover the pure
parts: JSON decoding, error mapping, sidebar row derivation, selection
restoration, applied-snapshot bookkeeping, `config.plist` parsing.
`MarkdownBlockTests` also parses the real `THIRD-PARTY-NOTICES.md` out of the
built bundle.

The test plan sets the language to English and the region to US: the tests run
inside the host app, which would otherwise pick the Mac's language, and some
assert English text.

`IntegrationTests` runs inside the host app, so it exercises app-scoped bookmarks
and the real bundled `qemu-img`, creating actual qcow2 images in a temporary
directory. That is only safe because the test plan sets
`DISK_SNAPSHOT_TOOL_STORAGE=scratch`.
