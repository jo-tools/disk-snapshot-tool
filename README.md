# Disk Snapshot Tool
<img src="screenshots/AppIcon.png?raw=true" width="96" align="right" alt="Disk Snapshot Tool app icon">

Manage internal snapshots of qcow2 virtual disk images  
*macOS app*

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Description

A small macOS app that lists, creates, applies and deletes the **internal
snapshots** of **qcow2 virtual disk images**. Drop in any disk image — and if it
belongs to a [UTM](https://getutm.app) virtual machine, drop in the whole VM.

It works by driving `qemu-img`, which is bundled and included in the app — you
do not need to have [QEMU](https://www.qemu.org) installed manually.

![ScreenShot: Disk Snapshot Tool](screenshots/DiskSnapshotTool.png?raw=true)

### Features

- Add virtual disk images by drag and drop, or through
  *File > Open Disk Image or VM…*
- Recognises UTM virtual machines: drop a `.utm` bundle and its disks are read
  from its own configuration, so they stay in sync with UTM
- List every snapshot on a disk with its date, and — for a snapshot that carries
  one — the size of its saved RAM state
- Create, apply *(revert to)*, delete a snapshot
- Marks which snapshot the disk is currently at *(and stops marking it once the
  virtual machine has run again)*
- Detects that a virtual machine is running and disables anything that would
  write to its disk
- Takes `.qcow2`, `.img`, `.vmdk`, `.vdi`, `.vhdx`, `.qed` and `.iso`
  files, and names the format and size of each
  - Only qcow2 supports *internal* snapshots; for the others the app says so
    rather than offering a button that can only fail
- In English, German, French, Spanish and Italian, following the language set
  in macOS

> UTM 5 brings its own snapshot management.  
> This app is most useful with UTM 4, for qcow2 disk images outside UTM,
> and for anyone who prefers a small separate tool.

## About snapshots

A qcow2 **internal snapshot** is a point-in-time copy of a virtual disk image,
stored *inside that same image file*. Taking one is instant and costs almost
nothing at first; the file then grows as the live disk drifts away from the
snapshot.

Three things are worth knowing before you use them:

- **The virtual machine has to be shut down.** Not paused, not suspended — off.
  Writing to a disk image while a virtual machine has it open risks corrupting
  it, so the app does not allow it *(it detects the lock QEMU holds and disables
  the actions)*.
- **Not every format supports snapshots.** The app can snapshot what `qemu-img` can
  snapshot, and that is qcow2. A virtual machine that mixes formats will show
  some of its disks as snapshot-capable and some not.
  - In UTM, qcow2 means the **QEMU** backend. A virtual machine that uses
    **Apple Virtualization** keeps its disks as raw `.img` files: the app lists
    them, but cannot snapshot them.
- **A snapshot is not a backup.** It lives in the same file as the data it
  protects. If that file is lost or corrupted, the snapshots go with it. Keep real
  backups as well.

A snapshot can also carry the virtual machine's memory, and such an entry shows a
RAM state size here. You will rarely see one: this app always takes disk-only
snapshots, because the machine is off when they are taken. UTM writes one with
memory in it when it suspends a QEMU virtual machine.

## How to use — Examples

Both examples start from a disk that is already in the sidebar: drop its disk
image there — or, for a UTM virtual machine, its `.utm` bundle — or use
*File > Open Disk Image or VM…* in the menu bar. What you add stays in the
library, so this is done once per disk or machine.

### Try something out, then go back

1. Shut the virtual machine down in UTM.
2. Select its disk image in the sidebar.
3. Choose *Snapshot > New Snapshot…* and name it something like
   `before-update`.
4. Start the VM in UTM and do whatever you wanted to try.
5. Shut the VM down again.
6. In Disk Snapshot Tool, select the `before-update` snapshot and choose
   *Snapshot > Apply / Revert*.

The disk is back exactly as it was in step 3, and everything written since is gone.
The app asks you to confirm before it does that.

If it worked out and you want to keep the changes, delete the snapshot instead.
It costs space for as long as it is kept, because the disk keeps drifting away
from it.

### Rename a snapshot

There is no rename command, and that is not an omission: qcow2 stores a snapshot's
name as its *tag*, and neither QEMU nor `qemu-img` can change a tag in place.

You can still get there, by making a new snapshot of the same state and dropping
the old one. Say you want to rename `test1` to `clean-install`:

1. Shut the virtual machine down.
2. Create a snapshot of where you are right now — call it `temp-live`. Without
   this, step 3 would throw your current state away.
3. Select `test1` and choose *Snapshot > Apply / Revert*. The live disk is now
   that state.
4. Choose *Snapshot > New Snapshot…* and create `clean-install`. Same state,
   new name.
5. Delete `test1`.
6. Select `temp-live` and apply it to get back to where you started.
7. Delete `temp-live`.

Two caveats. The new snapshot carries *today's* date, not the original's, and if
`test1` held a saved RAM state, `clean-install` will not — this app takes disk-only
snapshots. If either matters to you, keep the original name instead.

## Requirements and Installation

Disk Snapshot Tool needs macOS 26 *(or later)*. Everything else it needs is
included in the app.

Download the `.dmg` from
[Releases](https://github.com/jo-tools/disk-snapshot-tool/releases), open it and
drag the app to your Applications folder.

## Documentation

- [docs/build.md](docs/build.md) — building from source, the bundled `qemu-img`,
  code signing
- [docs/architecture.md](docs/architecture.md) — how the app is put together
- [docs/release.md](docs/release.md) — release checklist
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) — what is bundled, under which
  licenses, and the obligations that come with redistributing a build

## License

The application's own source code is licensed under the [MIT License](LICENSE).

The bundled `qemu-img` is a separate program, launched as its own process, and is
licensed under **GPL-2.0-only**. Distributing a build therefore carries
obligations that the MIT license does not — chiefly, offering the corresponding
source and the build scripts from the same place as the download. Each release
here has that source attached. All of
it is spelled out in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## About

Disk Snapshot Tool is developed by Juerg Otter — **[jo-tools.ch](https://www.jo-tools.ch/)**.  
His other iOS/macOS app is **[Expense Tool](https://www.jo-tools.ch/expense-tool/)**
— *organize your own and shared expenses*.

Disk Snapshot Tool is not affiliated with the UTM project or with QEMU. *UTM* is a trademark of
Turing Software, LLC, *QEMU* of Fabrice Bellard.

### Contact
[![E-Mail](https://img.shields.io/static/v1?style=social&label=E-Mail&message=juerg@jo-tools.ch)](mailto:juerg@jo-tools.ch)
&emsp;&emsp;
[![Follow on Facebook](https://img.shields.io/static/v1?style=social&logo=facebook&label=Facebook&message=juerg.otter)](https://www.facebook.com/juerg.otter)
&emsp;&emsp;
[![Follow on Twitter](https://img.shields.io/twitter/follow/juergotter?style=social)](https://twitter.com/juergotter)

### Donation
Do you like this project? Does it help you? Has it saved you time and money?  
It is free — if you want to say thanks, a [message](mailto:juerg@jo-tools.ch) or a small [donation via PayPal](https://paypal.me/jotools) is always welcome.  

[![PayPal Donation to jotools](https://img.shields.io/static/v1?style=social&logo=paypal&label=PayPal&message=jotools)](https://paypal.me/jotools)
