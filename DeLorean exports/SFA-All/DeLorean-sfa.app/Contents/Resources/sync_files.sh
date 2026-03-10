#!/bin/bash
# ----------------------------------------------------------------------
# CLEANUP TRAP
# ----------------------------------------------------------------------
cleanup() {
    kill -TERM -- -$$ 2>/dev/null
    sleep 0.5
    kill -KILL -- -$$ 2>/dev/null
    [ -f "$ERROR_TEMP" ] && rm -f "$ERROR_TEMP"
    exit 130
}
trap cleanup SIGINT SIGTERM

# ----------------------------------------------------------------------
# PLIST CONFIGURATION
# ----------------------------------------------------------------------
PLIST="$HOME/Library/Preferences/com.ufemit.delorean.plist"

read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null
}

create_default_plist() {
    /usr/libexec/PlistBuddy -c "Clear dict" "$PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :scheduledBackupTime string '8:10'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :rangeStart string '07:00'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :rangeEnd string '21:00'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :frequencyCheck integer 3600" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :maxDayAttemptNotification integer 6" "$PLIST"
#    /usr/libexec/PlistBuddy -c "Add :destinationPath string '/Volumes/\$(whoami)/SYSTEM/delorean/'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :destinationPath string '/Volumes/SFA-All/User Data/\$(whoami)/'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :logFilePath string '\$HOME/delorean.log'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :sources array" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :sources:0 string '\$HOME/Pictures'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :sources:1 string '\$HOME/Documents'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :sources:2 string '\$HOME/Downloads'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :sources:3 string '\$HOME/Desktop'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns array" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:0 string 'Photos Library.photoslibrary'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:1 string '.DS_Store'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:2 string '~\$*'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:3 string '*.download'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:4 string '*.crdownload'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:5 string '*.part'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:6 string '*.icloud'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:7 string '*-shm'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:8 string '*-wal'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:9 string '*.tmp'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:10 string '._*'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:11 string '*.pkg'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:12 string '*.iso'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:13 string '*.app'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:14 string '*.pvm'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:15 string '*.pvmp'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:16 string '*.ipsw'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:17 string '*[Pp]ersonal/'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:18 string '*[Pp]ersonal*/'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:19 string '.git/'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:20 string 'node_modules/'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:21 string 'xcuserdata/'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:22 string 'DerivedData/'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:23 string '\$RECYCLE.BIN'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:24 string 'System Volume Information'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:25 string 'Thumbs.db'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:26 string 'desktop.ini'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:27 string '.Spotlight-V100'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:28 string '.Trashes'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:29 string '.fseventsd'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:30 string '.TemporaryItems'" "$PLIST"
}

# ----------------------------------------------------------------------
# LOAD CONFIGURATION
# ----------------------------------------------------------------------
if [ ! -f "$PLIST" ]; then
    create_default_plist
fi

required_keys=("scheduledBackupTime" "rangeStart" "rangeEnd" "destinationPath" "sources" "logFilePath")
for key in "${required_keys[@]}"; do
    if ! /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Configuration file missing required key: $key" >> "$HOME/delorean_config_error.log"
        exit 99
    fi
done

DEST=$(read_plist "destinationPath")
DEST=$(eval echo "$DEST")
mkdir -p "$DEST"

LOG_FILE=$(read_plist "logFilePath")
LOG_FILE=$(eval echo "$LOG_FILE")
mkdir -p "$(dirname "$LOG_FILE")"

sources_count=$(/usr/libexec/PlistBuddy -c "Print :sources" "$PLIST" 2>/dev/null | grep -c "    ")
if [ "$sources_count" -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: No source directories configured" >> "$LOG_FILE"
    exit 99
fi

SOURCES=()
for ((i=0; i<sources_count; i++)); do
    path=$(read_plist "sources:$i")
    path=$(eval echo "$path")
    SOURCES+=("$path")
done

exclude_count=$(/usr/libexec/PlistBuddy -c "Print :excludePatterns" "$PLIST" 2>/dev/null | grep -c "    ")
EXCLUDES=()
if [ "$exclude_count" -gt 0 ]; then
    for ((i=0; i<exclude_count; i++)); do
        pattern=$(read_plist "excludePatterns:$i")
        EXCLUDES+=("--exclude=$pattern")
    done
fi

# ----------------------------------------------------------------------
# RESOLVE BUNDLED RSYNC
# Must happen AFTER LOG_FILE is defined so fallback warning can be logged
# ----------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLED_RSYNC="$SCRIPT_DIR/rsync_v3.4.1"

if [ -x "$BUNDLED_RSYNC" ]; then
    RSYNC_BIN="$BUNDLED_RSYNC"
else
    RSYNC_BIN="/usr/bin/rsync"
    log_entry "Warning: Bundled rsync not found, falling back to system rsync (iconv unavailable)"
fi

# ----------------------------------------------------------------------
# SETTINGS
# ----------------------------------------------------------------------
ERROR_TEMP="$HOME/delorean_error_check.tmp"
[ -f "$ERROR_TEMP" ] && rm "$ERROR_TEMP"

# --iconv=UTF-8-MAC,UTF-8 handles NFD→NFC normalization for SMB/NTFS
# --secluded-args protects filenames with special characters from shell glob expansion
OPTIONS=(
    -rltD
    --inplace
    --verbose
    --partial
    --progress
    --stats
    --delete
    --ignore-errors
    --no-p --no-o --no-g
    --iconv=UTF-8-MAC,UTF-8
    --secluded-args
)

# ----------------------------------------------------------------------
# LOGGING FUNCTIONS
# ----------------------------------------------------------------------
log_entry() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_success() {
    local backup_type="${BACKUP_TYPE:-scheduled}"
    log_entry "Backup completed successfully ($backup_type)"
}

# ----------------------------------------------------------------------
# EXECUTION
# ----------------------------------------------------------------------
"$RSYNC_BIN" "${OPTIONS[@]}" "${EXCLUDES[@]}" "${SOURCES[@]}" "$DEST" > "$ERROR_TEMP" 2>&1
rsync_exit_code=$?

# ----------------------------------------------------------------------
# ERROR HANDLING
# exit 0  = perfect success
# exit 23 = partial transfer (some files skipped) — tolerable
# exit 24 = source files vanished during transfer — tolerable
# exit 1  = syntax/protocol error — critical
# exit 99 = configuration error — critical
# others  = network/IO failures — critical
# ----------------------------------------------------------------------
if [ "$rsync_exit_code" -eq 0 ]; then
    log_success
    rm -f "$ERROR_TEMP"
    cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
    echo "Backup completed."
    exit 0

elif [ "$rsync_exit_code" -eq 23 ] || [ "$rsync_exit_code" -eq 24 ]; then
    if grep -qE "^\[sender\] cannot convert filename:" "$ERROR_TEMP"; then
        log_success
        log_entry "Warning: Some files could not be backed up due to unsupported characters in filename"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Files that could not be backed up:" >> "$LOG_FILE"
        grep -E "^\[sender\] cannot convert filename:" "$ERROR_TEMP" \
            | sed 's/\[sender\] cannot convert filename: //' \
            | sed 's/ (Illegal byte sequence)//' \
            | head -20 >> "$LOG_FILE"
        rm -f "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        echo "Backup completed with warnings."
        exit 2
    else
        log_success
        log_entry "Warning: Some source files were unavailable during backup"
        rm -f "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        echo "Backup completed with warnings."
        exit 2
    fi

else
    # Critical failures
    case $rsync_exit_code in
        1)  log_entry "Backup Failed: rsync syntax or configuration error (exit code: 1)" ;;
        10) log_entry "Backup Failed: Network connection error (exit code: 10)" ;;
        11)
            if grep -q "No space left on device" "$ERROR_TEMP"; then
                log_entry "Backup Failed: Network drive is full (exit code: 11)"
            else
                log_entry "Backup Failed: File I/O error (exit code: 11)"
            fi
            ;;
        12) log_entry "Backup Failed: Data stream error (exit code: 12)" ;;
        30) log_entry "Backup Failed: Network timeout (exit code: 30)" ;;
        99) log_entry "Backup Failed: Configuration error (exit code: 99)" ;;
        *)  log_entry "Backup Failed: Critical error (exit code: $rsync_exit_code)" ;;
    esac
    rm -f "$ERROR_TEMP"
    cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
    echo "Backup failed."
    exit $rsync_exit_code
fi
