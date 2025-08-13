# DeLorean – Simple Backup Utility

Simple macOS menu bar application to synchronize user data using rsync. This might not be the most elegant way to back up files, but it's simple and it works. Using a small bash script, this Swift application provides an interface to control `sync_files.sh`.

_Forked from: https://github.com/jnsdrtlf/sync/tree/master_

## Configuration

DeLorean reads its entire configuration from the `sync_files.sh` script located inside the app bundle. To customize the backup behavior, modify this script.

### Accessing the Configuration File

For deployed app:
1. Right‑click on `DeLorean.app` in Applications
2. Select “Show Package Contents”
3. Navigate to `Contents/Resources/sync_files.sh`
4. Open with a text editor (you may need admin privileges)

For development:
- Edit `delorean/sync_files.sh` in the repo, then rebuild the app.

### Configurable Variables (at the top of sync_files.sh)

Backup scheduling:
    scheduledBackupTime="09:15"    # Daily backup time (24-hour format)
    rangeStart="07:00"             # Earliest time backups can run
    rangeEnd="21:00"               # Latest time backups can run
    frequencyCheck="60"            # How often to check for backups (seconds)
    maxDayAttemptNotification=6    # Max failure notifications per day

Source directories:
    `SOURCES=("$HOME/Pictures" "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")`
Uncomment or modify example lines to customize which folders to back up:
    `#SOURCES=("$HOME/Documents" "$HOME/Downloads" "$HOME/Pictures")`
    `#SOURCES=("$HOME/Pictures" "$HOME/Downloads")`
    `#SOURCES=("$HOME/Pictures")`

Destination:
    DEST="/Volumes/SFA-All/User Data/$(whoami)/"
Change this to your network drive or backup location. `$(whoami)` automatically uses the current username.

Log file:
    LOG_FILE="$HOME/delorean.log"
Location where backup logs are stored.

### Example Customization

Back up only Documents and Pictures to a different network drive at 6 PM:
    SOURCES=("$HOME/Documents" "$HOME/Pictures")
    DEST="/Volumes/BackupDrive/Users/$(whoami)/"
    scheduledBackupTime="18:00"

## Notes for Users

- On first launch, macOS may prompt for access to Desktop, Documents, and Downloads. Click “OK/Allow” so DeLorean can back up those folders.
- Ensure the network destination is mounted and accessible before running a backup.

## Development Setup

1. Clone this repository
2. Open the Xcode project
3. Modify `delorean/sync_files.sh` as needed
4. Build and run

## Creating a PKG from the DeLorean.app file
Navigate to where your DeLorean.app is located
`cd /path/to/your/DeLorean.app/..`

Create the package
`pkgbuild --root . --identifier ufemit.delorean --version 1.0 --install-location /Applications UF-EM-DeLorean-Backup.pkg`

## License

This project is open source under the Apache License, Version 2.0.

Original work © 2019 Jonas Drotleff (Apache 2.0)  
Modifications © 2025 University of Florida (Apache 2.0)

License text: http://www.apache.org/licenses/LICENSE-2.0

AS IS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND. See the License for the specific language governing permissions and limitations under the License.

The white refresh icon is made by Cole Bemis and is part of the awesome feathericons icon set, released under the MIT License.
