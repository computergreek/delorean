
# DeLorean – Simple Backup Utility
Simple macOS menu bar application to synchronize user data to a network drive using rsync. Using a small bash script, this Swift application provides a menu bar interface to control `sync_files.sh`.

> _Forked from: https://github.com/jnsdrtlf/sync/tree/master_

---

## What's New in v1.3

- **Bundled rsync 3.4.1** — DeLorean now ships with a self-contained rsync 3.4.1 binary (arm64) compiled from source, replacing macOS's built-in openrsync. This resolves crash-on-transfer issues caused by openrsync's incompatibility with SMB/NTFS network drives.
- **Emoji & special character handling** — Files with emoji or multi-byte Unicode characters in their filenames are now skipped gracefully instead of crashing the entire backup queue. Skipped filenames are logged for visibility.
- **iconv support** — rsync is invoked with `--iconv=UTF-8-MAC,UTF-8` to handle macOS NFD→NFC Unicode normalization when writing to SMB/NTFS destinations. Accented characters (e.g. `café.docx`) now transfer correctly.
- **Plist-based configuration** — All backup settings (schedule, sources, destination, exclusion patterns) are now managed via `~/Library/Preferences/com.ufemit.delorean.plist`, enabling IT management through Jamf Configuration Profiles. A default plist is auto-generated on first run if none exists.
- **Network drive pre-check** — The Swift app now checks whether the destination network volume is mounted before invoking the backup script, eliminating false-failure notification spam when the drive is simply unavailable.
- **Improved notification logic** — Scheduled backups complete silently on success. Manual backups notify the user on completion. Both notify on failure or warnings.
- **Robust error handling** — Exit codes 23 (partial transfer) and 24 (source files vanished) are correctly treated as warnings rather than critical failures. The log clearly distinguishes between success, warnings, and genuine failures.
- **Cleaner logging** — Log output is scoped to meaningful events. Skipped filenames, deletions context, and failure reasons are surfaced clearly without verbose rsync transfer noise.

---

## Architecture

**Frontend:** A Swift application (`AppDelegate.swift`, `StatusMenuController.swift`) handling the menu bar UI, user notifications, network drive availability checks, and scheduled backup timers.

**Backend:** A Bash script (`sync_files.sh`) executed by the Swift app, using the bundled rsync 3.4.1 binary to perform file mirroring and logging to `~/delorean.log`.

**Configuration:** `~/Library/Preferences/com.ufemit.delorean.plist` — managed manually or via Jamf Configuration Profiles.

---

## Configuration

DeLorean reads all configuration from its plist file at:
`~/Library/Preferences/com.ufemit.delorean.plist`

A default plist with standard settings is automatically created on first run. IT administrators can push a custom plist via Jamf before first launch to override defaults.

### Configurable Keys

| Key | Type | Default | Description |
|---|---|---|---|
| `scheduledBackupTime` | String | `"8:10"` | Daily backup time (24-hour, `HH:mm`) |
| `rangeStart` | String | `"07:00"` | Earliest time backups can run |
| `rangeEnd` | String | `"21:00"` | Latest time backups can run |
| `frequencyCheck` | Integer | `3600` | How often (seconds) to check schedule |
| `maxDayAttemptNotification` | Integer | `6` | Days without backup before overdue alert |
| `destinationPath` | String | `/Volumes/SFA-All/User Data/$(whoami)/` | Backup destination |
| `logFilePath` | String | `$HOME/delorean.log` | Log file location |
| `sources` | Array | Desktop, Documents, Downloads, Pictures | Source directories to back up |
| `excludePatterns` | Array | See defaults | rsync exclude patterns |

### Modifying Configuration

**For Jamf-managed deployments:** Push a Configuration Profile with your desired plist values before DeLorean first runs.

**For development/testing:** Edit the plist directly:
```bash
/usr/libexec/PlistBuddy -c "Set :scheduledBackupTime '09:00'" \
  ~/Library/Preferences/com.ufemit.delorean.plist
```

---

## Notes for Users

### ⚠️ First-Time Setup

After installing DeLorean, grant it Full Disk Access:

#### macOS Ventura (13.0+) / Sonoma (14.0+) / Sequoia (15.0+):
1. Open **System Settings**
2. Click **Privacy & Security** in the sidebar
3. Scroll down and click **Full Disk Access**
4. Click **(+)**, navigate to `/Applications/DeLorean.app`, click **Open**
5. Toggle the switch next to DeLorean to **ON**
6. Quit and restart DeLorean

**Without this permission, DeLorean may not be able to access all folders in your user profile.**

- macOS will prompt for access to Desktop, Documents, and Downloads on first launch — click Allow.
- The network destination drive must be mounted before backup attempts.
- DeLorean automatically launches at login to perform scheduled backups.

### Known Limitations

- Files with emoji or multi-byte Unicode characters in their **filenames** cannot be transferred to SMB/NTFS destinations due to encoding conversion limitations. These files are skipped gracefully and listed in `~/delorean.log`.
- Files with accented Latin characters (e.g. `café.docx`) transfer correctly.
- **Apple Silicon (arm64) only.** The bundled rsync 3.4.1 binary is compiled for arm64. Intel Macs are not supported.

### System Requirements

- **macOS 13.5 (Ventura) or later**
- Apple Silicon (M-series) Mac
- Network drive mounted at backup time

---

### Rebuilding the rsync Binary

If you need to recompile rsync from source (e.g. for a newer version):

```bash
# On a Mac with Homebrew installed:
brew install popt openssl@3

curl -O https://download.samba.org/pub/rsync/rsync-3.4.1.tar.gz
tar -xzf rsync-3.4.1.tar.gz
cd rsync-3.4.1

./configure \
    --prefix=/tmp/rsync_build \
    --with-included-popt \
    --with-included-zlib \
    --disable-debug \
    --enable-iconv \
    --disable-openssl \
    --disable-xxhash \
    --disable-zstd \
    --disable-lz4 \
    CFLAGS="-arch arm64 -I/opt/homebrew/include" \
    LDFLAGS="-arch arm64 -L/opt/homebrew/lib"

make -j$(sysctl -n hw.logicalcpu)

# Verify: should show only /usr/lib/ dependencies
otool -L rsync

# Verify: should list iconv in capabilities
./rsync --version | grep iconv
```

Replace `Resources/rsync_v3.4.1` in the Xcode project with the new binary and update the version reference in `sync_files.sh`.

---

## Creating a PKG Installer

### Using Packages (GUI — Recommended)
1. Download [Packages](http://s.sudre.free.fr/Software/Packages/about.html)
2. Create a new project
3. Add `DeLorean.app` with install location `/Applications`
4. Build the installer package

### Using pkgbuild (Command Line)
```bash
cd /path/to/your/DeLorean.app/..
pkgbuild --root . \
  --identifier ufemit.delorean \
  --version 1.3 \
  --install-location /Applications \
  UF-EM-DeLorean-Backup-1.3.pkg
```

### Gatekeeper Note
DeLorean is not currently signed or notarized. On first install, Gatekeeper must be bypassed manually, or cleared with:
```bash
xattr -cr /Applications/DeLorean.app
```

---

## License

This project is open source under the Apache License, Version 2.0.

Original work © 2019 Jonas Drotleff (Apache 2.0)
Modifications © 2025 University of Florida (Apache 2.0)

License text: http://www.apache.org/licenses/LICENSE-2.0

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND. See the License for the specific language governing permissions and limitations under the License.

The white refresh icon is made by Cole Bemis and is part of the [Feather Icons](https://feathericons.com) icon set, released under the MIT License.