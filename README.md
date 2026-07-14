# pkgconvert

A tool to convert Linux desktop application packages between formats.

This project was created to solve a personal problem. As a relatively new Linux user, I frequently ran into applications that were only available as `.deb` files on Fedora, or `.rpm` files on Debian-based systems. After spending too much time trying to make them work, I built this tool to simplify the process.

The goal is to help other users in the same situation — especially those newer to Linux — convert packages without needing to deal with complex packaging internals.

**This project was heavily developed using AI** (Grok and Claude).

### What It Can Convert

This tool works best with regular desktop applications.

**Most reliable conversions:**
- `.deb` ↔ `.rpm`
- `.deb` or `.rpm` to `.tar.gz` (ideal for portable archives)
- `.deb` or `.rpm` to an extracted folder

**Additional capabilities:**
- Can extract `.AppImage` and `.snap` files
- Can convert `.tar.gz` files to other formats (results may vary)

**Important Warning:**
**Only use this tool on desktop applications** — programs you launch by clicking an icon. 

**Do not** use it on system packages, drivers, services, databases, or any software your operating system depends on. Doing so can break your system. Use with caution.

---

Check your installed version any time with `./pkgconvert.sh --version`.

**Make the scripts executable first:**
```bash
chmod +x pkgconvert.sh pdkconvert-gui.sh
```

## Graphical Interface (Optional)

Prefer clicking instead of typing? Run:

```bash
./pkgconvert-gui.sh
```

It walks you through the process visually: pick a file → choose output format → review the pre-flight analysis → click Convert. The converted package is saved in the same folder as the original.

The GUI auto-detects your desktop environment (GNOME or KDE Plasma) and uses the appropriate dialog tool (`zenity` or `kdialog`).

## Complete Beginner Walkthrough

**Step 1:** Download the files from the green **Code** button (Download ZIP) and extract them. Keep `pkgconvert.sh` and `pkgconvert-gui.sh` in the same folder.

**Step 2:** Open a terminal in that folder and make the scripts executable:

```bash
chmod +x pkgconvert.sh pkgconvert-gui.sh
```

**Step 3:** Install the required tools (example for Fedora):

```bash
sudo dnf install binutils zstd rpm-build dpkg squashfs-tools cpio
```

**Step 4:** Run the tool:

- GUI: `./pkgconvert-gui.sh`
- CLI: `./pkgconvert.sh someapp.deb --to rpm`

**Step 5:** Install the resulting package (e.g. on Fedora):

```bash
sudo dnf install ./someapp-1.0.x86_64.rpm
```

If the app doesn't launch, re-run the analysis (`--info`) and install any missing dependencies it lists.

## Quick Start

```bash
chmod +x pkgconvert.sh

# Interactive mode
./pkgconvert.sh someapp.deb

# Direct conversion
./pkgconvert.sh someapp.deb --to rpm
./pkgconvert.sh someapp.rpm --to deb
./pkgconvert.sh someapp.AppImage --to tar.gz
```

## Pre-flight Analysis

Before converting, the tool analyzes the package and clearly explains potential issues such as:
- Dependency name translations for your distro
- Missing shared libraries
- Install scripts and systemd services that won't carry over
- Desktop launcher problems

This helps you understand what might need manual fixing after conversion.

## Options

| Flag                  | Description |
|-----------------------|-----------|
| `--to FORMAT`         | Output format: `tar.gz`, `deb`, `rpm`, or `dir` |
| `--distro NAME`       | Force dependency translation (`debian`, `fedora`, `opensuse`, `arch`) |
| `--info`              | Show analysis only, don't convert |
| `--yes` / `-y`        | Skip confirmation |
| `--quiet` / `-q`      | Reduce explanatory text |
| `--report`            | Auto-save failure report |
| `--version` / `-V`    | Show version |

## Requirements

```bash
# Fedora / RHEL
sudo dnf install binutils zstd rpm-build dpkg squashfs-tools cpio

# Debian / Ubuntu
sudo apt install binutils zstd rpm dpkg squashfs-tools cpio

# openSUSE
sudo zypper install binutils zstd rpm-build dpkg squashfs-tools cpio

# Arch
sudo pacman -S binutils zstd rpm-tools dpkg squashfs-tools cpio
```

## Limitations

- Dependencies are **not** automatically included in the converted package.
- Maintainer scripts and some advanced setup steps do not carry over.
- Complex or Electron-based apps may still need manual adjustments.
- This tool is designed for **desktop apps only**.

## Running the Tests

```bash
./tests/run-tests.sh
```

## Alternatives

- [`alien`](https://wiki.debian.org/Alien) — Classic deb ↔ rpm converter
- `debtap` (AUR) — For Arch Linux users

## License

MIT — feel free to use and modify as you like.
