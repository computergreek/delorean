#!/bin/bash

# Backup scheduling parameters
scheduledBackupTime="07:00"
rangeStart="07:00"
rangeEnd="21:00"
# How often the app should check if an rsync happened that day in seconds (3600 seconds = 1 hour)
frequencyCheck="30"
maxDayAttemptNotification=6

# Define source directories
#SOURCES=("$HOME/Pictures" "$HOME/Documents" "$HOME/Downloads")
SOURCES=("$HOME/Pictures")

# Define destination directory
DEST="/Volumes/SFA-All/User Data/$(whoami)/"

# Log file
LOG_FILE="$HOME/delorean.log"

# Function to count failure attempts
count_failures() {
    grep -c 'Backup Failed: Network drive inaccessible' "$LOG_FILE"
}

# Check if the network drive is mounted by testing if the destination directory exists and is accessible
if [ ! -d "$DEST" ]; then
    failureCount=$(count_failures)
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup Failed: Network drive inaccessible (Failure count: $failureCount)" >> "$LOG_FILE"
    exit 1  # Exit the script with an error status
fi

# Rsync options and excludes as arrays
OPTIONS=(--archive --verbose --partial --progress --stats --delete)
EXCLUDES=(--exclude='Pictures/Photos Library.photoslibrary' --exclude='.DS_Store')

# Initialize success flag
overall_success=true

# Perform backup for each source directory
for SOURCE in "${SOURCES[@]}"; do
    rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "$SOURCE" "$DEST"
    if [ $? -ne 0 ]; then
        overall_success=false
    fi
done

# Log the overall result
if [ "$overall_success" = true ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completed successfully" >> "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup Failed: Rsync error occurred" >> "$LOG_FILE"
fi

# Copy log file to destination
cp "$LOG_FILE" "$DEST/delorean.log"

echo "Backup completed."
