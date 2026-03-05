#!/bin/bash
# ----------------------------------------------------------------------
# CLEANUP TRAP
# Ensure child processes (rsync) are terminated when this script exits
# ----------------------------------------------------------------------
cleanup() {
    kill -TERM -- -$$ 2>/dev/null
    sleep 0.5
    kill -KILL -- -$$ 2>/dev/null
    [ -f "$HOME/delorean_error_check.tmp" ] && rm "$HOME/delorean_error_check.tmp"
    exit 130
}
trap cleanup SIGINT SIGTERM

# ----------------------------------------------------------------------
# PLIST CONFIGURATION
# ----------------------------------------------------------------------
PLIST="$HOME/Library/Preferences/com.ufemit.delorean.plist"

# Function to read plist values
read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null
}

# Function to create default plist on first run
create_default_plist() {
    /usr/libexec/PlistBuddy -c "Clear dict" "$PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :scheduledBackupTime string '8:10'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :rangeStart string '07:00'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :rangeEnd string '21:00'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :frequencyCheck integer 3600" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :maxDayAttemptNotification integer 6" "$PLIST"
    # /usr/libexec/PlistBuddy -c "Add :destinationPath string '/Volumes/\$(whoami)/SYSTEM/delorean/'" "$PLIST"
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
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:10 string '*.png'" "$PLIST"
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
    /usr/libexec/PlistBuddy -c "Add :excludePatterns:31 string '._*'" "$PLIST"
}

# ----------------------------------------------------------------------
# LOAD CONFIGURATION
# ----------------------------------------------------------------------

# Check if plist exists
if [ ! -f "$PLIST" ]; then
    # First run - create default plist
    create_default_plist
fi

# Validate required keys exist
required_keys=("scheduledBackupTime" "rangeStart" "rangeEnd" "destinationPath" "sources" "logFilePath")
for key in "${required_keys[@]}"; do
    if ! /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" &>/dev/null; then
        # Log to a temporary location since we don't know LOG_FILE yet
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Configuration file missing required key: $key" >> "$HOME/delorean_config_error.log"
        exit 99  # Custom exit code for configuration errors
    fi
done

# Read configuration from plist
scheduledBackupTime=$(read_plist "scheduledBackupTime")
rangeStart=$(read_plist "rangeStart")
rangeEnd=$(read_plist "rangeEnd")
frequencyCheck=$(read_plist "frequencyCheck")
maxDayAttemptNotification=$(read_plist "maxDayAttemptNotification")

# Read and expand destination path
DEST=$(read_plist "destinationPath")
DEST=$(eval echo "$DEST")
mkdir -p "$DEST"

# Read and expand log file path
LOG_FILE=$(read_plist "logFilePath")
LOG_FILE=$(eval echo "$LOG_FILE")
mkdir -p "$(dirname "$LOG_FILE")"

# Read sources array
sources_count=$(/usr/libexec/PlistBuddy -c "Print :sources" "$PLIST" 2>/dev/null | grep -c "    ")
if [ $sources_count -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: No source directories configured" >> "$LOG_FILE"
    exit 99
fi

SOURCES=()
for ((i=0; i<$sources_count; i++)); do
    path=$(read_plist "sources:$i")
    # Expand environment variables like $HOME and $(whoami)
    path=$(eval echo "$path")
    SOURCES+=("$path")
done

# Read exclude patterns array
exclude_count=$(/usr/libexec/PlistBuddy -c "Print :excludePatterns" "$PLIST" 2>/dev/null | grep -c "    ")
EXCLUDES=()
if [ $exclude_count -gt 0 ]; then
    for ((i=0; i<$exclude_count; i++)); do
        pattern=$(read_plist "excludePatterns:$i")
        EXCLUDES+=("--exclude=$pattern")
    done
fi

# ----------------------------------------------------------------------
# HARDCODED SETTINGS (for security and simplicity)
# ----------------------------------------------------------------------
ERROR_TEMP="$HOME/delorean_error_check.tmp"
# Clean up any leftover temp file from previous interrupted run
[ -f "$ERROR_TEMP" ] && rm "$ERROR_TEMP"

# Rsync options - optimized for NTFS/SMB compatibility
#OPTIONS=(-rltD --inplace --verbose --partial --progress --stats --delete-after --ignore-errors --no-p --no-o -x-no-g)
#OPTIONS=(-rltD --inplace --verbose --partial --progress --stats --delete-after --ignore-errors --no-p --no-o --no-g)
OPTIONS=(-rltD --inplace --verbose --partial --progress --stats --delete --ignore-errors --no-p --no-o --no-g)
#OPTIONS=(-rltD --inplace --verbose --partial --progress --stats --delete-after --ignore-errors --protect-args --iconv=UTF-8-MAC,UTF-8 --no-p --no-o --no-g)
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

## ----------------------------------------------------------------------
## EXECUTION
## ----------------------------------------------------------------------
#
### Right before: rsync "${OPTIONS[@]}" ...
##echo "DEBUG: Running rsync with these options:" >> "$LOG_FILE"
##echo "OPTIONS: ${OPTIONS[@]}" >> "$LOG_FILE"
##echo "EXCLUDES: ${EXCLUDES[@]}" >> "$LOG_FILE"
##echo "SOURCES: ${SOURCES[@]}" >> "$LOG_FILE"
##echo "DEST: $DEST" >> "$LOG_FILE"
##echo "---" >> "$LOG_FILE"
##
##rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "${SOURCES[@]}" "$DEST" > "$ERROR_TEMP" 2>&1
### Run rsync, capturing ALL output to temp file for analysis
###rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "${SOURCES[@]}" "$DEST" > "$ERROR_TEMP" 2>&1
##rsync_exit_code=$?
##
### Extract ONLY errors/warnings to main log (prevents bloat)
### ": open$" matches rsync's "filename: open" error at end of line only
##grep -E "mkstempat|File name too long|Operation not permitted|: open$" "$ERROR_TEMP" | grep -v "rsync_downloader\|rsync_receiver\|rsync_sender\|io_read\|unexpected end of file\|child.*exited" >> "$LOG_FILE" 2>/dev/null || true
#
## Debug logging
#echo "DEBUG: Running rsync with these options:" >> "$LOG_FILE"
#echo "OPTIONS: ${OPTIONS[@]}" >> "$LOG_FILE"
#echo "EXCLUDES: ${EXCLUDES[@]}" >> "$LOG_FILE"
#echo "SOURCES: ${SOURCES[@]}" >> "$LOG_FILE"
#echo "DEST: $DEST" >> "$LOG_FILE"
#echo "---" >> "$LOG_FILE"
#
## Run rsync, capturing ALL output to temp file for analysis
#rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "${SOURCES[@]}" "$DEST" > "$ERROR_TEMP" 2>&1
#rsync_exit_code=$?
#
## Debug: capture full rsync output temporarily
#echo "DEBUG: rsync exit code: $rsync_exit_code" >> "$LOG_FILE"
#echo "DEBUG: Last 30 lines of rsync output:" >> "$LOG_FILE"
#tail -30 "$ERROR_TEMP" >> "$LOG_FILE"
#echo "---END DEBUG---" >> "$LOG_FILE"

# ----------------------------------------------------------------------
# EXECUTION & SELF-HEALING AUTO-EXCLUDES
# ----------------------------------------------------------------------
AUTO_EXCLUDES="$HOME/Library/Preferences/com.ufemit.delorean.autoexcludes.txt"
touch "$AUTO_EXCLUDES" # Ensure it exists

# Add the auto-excludes file to our rsync options
EXCLUDES+=("--exclude-from=$AUTO_EXCLUDES")

MAX_RETRIES=10
RETRY_COUNT=0

# Start the Retry Loop
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    
    # Run rsync
    rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "${SOURCES[@]}" "$DEST" > "$ERROR_TEMP" 2>&1
    rsync_exit_code=$?
    
    # If perfect success, break out of the loop!
    if [ $rsync_exit_code -eq 0 ]; then
        break
    fi
    
    # If we got an error, check if it was caused by a bad filename
    if grep -qE "mkstempat|File name too long|Input/output error|Operation not permitted|: open$" "$ERROR_TEMP"; then
        
        # Extract the exact filename(s) that caused the crash
        BAD_FILES=$(grep -E "mkstempat|File name too long|Input/output error|Operation not permitted|: open$" "$ERROR_TEMP" | grep -oE "(Downloads|Documents|Pictures|Desktop)/[^:]*")
        
        if [ -n "$BAD_FILES" ]; then
            log_entry "Warning: Unsupported filename detected. Auto-excluding and resuming queue (Retry $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
            
            # Append the bad files to our auto-exclude list and remove duplicates
            echo "$BAD_FILES" >> "$AUTO_EXCLUDES"
            sort -u "$AUTO_EXCLUDES" -o "$AUTO_EXCLUDES"
            
            # Increment our safety counter and loop back to run rsync again
            RETRY_COUNT=$((RETRY_COUNT+1))
            continue
        else
            # We got a filename error, but couldn't parse the name. Break to avoid infinite loop.
            break
        fi
    else
        # It's a real, critical error (network dropped, disk full). Break the loop and let standard error handling take over.
        break
    fi
done

# Extract ONLY errors/warnings to main log for visibility in delorean.log
grep -E "mkstempat|File name too long|Operation not permitted|: open$" "$ERROR_TEMP" | grep -v "rsync_downloader\|rsync_receiver\|rsync_sender\|io_read\|unexpected end of file\|child.*exited" >> "$LOG_FILE" 2>/dev/null || true

# ----------------------------------------------------------------------
# INTELLIGENT ERROR HANDLING
# ----------------------------------------------------------------------
if [ $rsync_exit_code -eq 0 ]; then
    # Perfect success
    log_success
    rm "$ERROR_TEMP"
    cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
    echo "Backup completed."
    exit 0

elif [ $rsync_exit_code -eq 23 ] || [ $rsync_exit_code -eq 24 ]; then
    # Partial failure - check if errors are tolerable
    # 23 = Partial transfer due to error
    # 24 = Source files vanished during backup
    if grep -qE "mkstempat|File name too long|Input/output error|Operation not permitted|vanished|: open$" "$ERROR_TEMP"; then
        # Tolerable errors: filesystem can't store certain filenames, or files disappeared
        # Log success first (for "Last Backup" display)
        log_success
        # Then log the warning details
        log_entry "Warning: Some files could not be backed up due to filesystem limitations"
        # Extract and log problematic filenames
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Files that could not be backed up:" >> "$LOG_FILE"
        grep -E "mkstempat|File name too long|: open$" "$ERROR_TEMP" | grep -oE "(Downloads|Documents|Pictures|Desktop)/[^:]*" | head -20 >> "$LOG_FILE"
        rm "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        # Always notify on warnings (both manual and scheduled)
        echo "Backup completed with warnings."
        exit 2
    else
        # Real partial failure (network timeout, disk issues, etc.)
        log_entry "Backup Failed: Partial transfer with critical errors (exit code: $rsync_exit_code)"
        rm "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        echo "Backup failed."
        exit $rsync_exit_code
    fi

elif [ $rsync_exit_code -eq 1 ]; then
    # Exit code 1 - check if it's just filename issues
    if grep -qE "mkstempat|File name too long|Input/output error|Operation not permitted|: open$" "$ERROR_TEMP"; then
        # Just filename problems, treat as success with warnings
        # Log success first (for "Last Backup" display)
        log_success
        # Then log the warning details
        log_entry "Warning: Some files could not be backed up due to filesystem limitations"
        # Extract and log problematic filenames
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Files that could not be backed up:" >> "$LOG_FILE"
        grep -E "mkstempat|File name too long|: open$" "$ERROR_TEMP" | grep -oE "(Downloads|Documents|Pictures|Desktop)/[^:]*" | head -20 >> "$LOG_FILE"
        rm "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        # Always notify on warnings (both manual and scheduled)
        echo "Backup completed with warnings."
        exit 2
    else
        # Real configuration/syntax error
        log_entry "Backup Failed: Configuration or syntax error (exit code: 1)"
        rm "$ERROR_TEMP"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        echo "Backup failed."
        exit 1
    fi

else
    # Catastrophic failures - provide specific error messages
    case $rsync_exit_code in
        10)
            log_entry "Backup Failed: Network connection error (exit code: 10)"
            ;;
        11)
            # Check if it's specifically a disk full error
            if grep -q "No space left on device" "$ERROR_TEMP"; then
                log_entry "Backup Failed: Network drive is full (exit code: 11)"
            else
                log_entry "Backup Failed: File I/O error (exit code: 11)"
            fi
            ;;
        12)
            log_entry "Backup Failed: Data stream error (exit code: 12)"
            ;;
        30)
            log_entry "Backup Failed: Network timeout (exit code: 30)"
            ;;
        *)
            log_entry "Backup Failed: Critical error (exit code: $rsync_exit_code)"
            ;;
    esac
    rm "$ERROR_TEMP"
    cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
    echo "Backup failed."
    exit $rsync_exit_code
fi
