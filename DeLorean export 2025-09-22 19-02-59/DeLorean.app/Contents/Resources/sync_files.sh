#!/bin/bash

# Backup scheduling parameters
scheduledBackupTime="09:15"
rangeStart="07:00"
rangeEnd="21:00"
# How often the app should check if an rsync happened that day in seconds (3600 seconds = 1 hour)
frequencyCheck="300"
maxDayAttemptNotification=6

# Define source directories
SOURCES=("$HOME/Pictures" "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")
#SOURCES=("$HOME/Documents" "$HOME/Downloads" "$HOME/Pictures")
#SOURCES=("$HOME/Pictures" "$HOME/Downloads")
#SOURCES=("$HOME/Pictures")

# Define destination directory
DEST="/Volumes/SFA-All/User Data/$(whoami)/"
mkdir -p "$DEST" # Create destination directory if it doesn't exist

# Log file
LOG_FILE="$HOME/delorean.log"
ABORT_FLAG="$HOME/delorean_abort.flag"
mkdir -p "$(dirname "$LOG_FILE")" # Create log file directory if it doesn't exist

# Clean up any old abort flag
rm -f "$ABORT_FLAG"

# Function to count failure attempts since the last successful backup
count_failures_since_last_success() {
    awk '/Backup completed successfully/{count=0} /Backup Failed: Network drive inaccessible/{count++} END{print count}' "$LOG_FILE"
}

# Function to log a failure
log_failure() {
    failureCount=$(count_failures_since_last_success)
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup Failed: Network drive inaccessible (Failure count: $((failureCount + 1)))" >> "$LOG_FILE"
}

# Function to log a successful backup
log_success() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completed successfully" >> "$LOG_FILE"
}

# Check if the network drive is mounted by testing if the destination directory exists and is accessible
if [ ! -d "$DEST" ]; then
    log_failure
    exit 1  # Exit the script with an error status
fi

# Ensure the log file exists and has an initial entry
if [ ! -f "$LOG_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Log file created" > "$LOG_FILE"
fi

# Rsync options and excludes as arrays
OPTIONS=(--archive --verbose --partial --progress --stats --delete)
EXCLUDES=(--exclude='Pictures/Photos Library.photoslibrary' --exclude='.DS_Store')

# Initialize success flag
overall_success=true

# Perform backup for each source directory
for SOURCE in "${SOURCES[@]}"; do
    # Check for abort flag before starting each directory
    if [ -f "$ABORT_FLAG" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup Failed: User aborted" >> "$LOG_FILE"
        rm -f "$ABORT_FLAG"
        cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
        exit 0
    fi
    
    rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "$SOURCE" "$DEST"
    
    if [ $? -ne 0 ]; then
        # Check if failure was due to abort
        if [ -f "$ABORT_FLAG" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup Failed: User aborted" >> "$LOG_FILE"
            rm -f "$ABORT_FLAG"
            cp "$LOG_FILE" "$DEST/delorean.log" 2>/dev/null || true
            exit 0
        fi
        overall_success=false
    fi
done

# Clean up abort flag at end
rm -f "$ABORT_FLAG"

# Log the overall result
if [ "$overall_success" = true ]; then
    log_success
else
    # Check for abort flag one more time
    if [ -f "$ABORT_FLAG" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup Failed: User aborted" >> "$LOG_FILE"
        rm -f "$ABORT_FLAG"
    else
        log_failure
    fi
fi

# Copy log file to destination
cp "$LOG_FILE" "$DEST/delorean.log"
echo "Backup completed."
