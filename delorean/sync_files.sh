#!/bin/bash
 
# Backup scheduling parameters
scheduledBackupTime="09:15"
rangeStart="07:00"
rangeEnd="21:00"
# How often the app should check if an rsync happened that day in seconds (3600 seconds = 1 hour)
frequencyCheck="60"
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
mkdir -p "$(dirname "$LOG_FILE")" # Create log file directory if it doesn't exist
 
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
 
# Run single rsync command for all sources at once
rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "${SOURCES[@]}" "$DEST"
 
# Log result based on exit code
if [ $? -eq 0 ]; then
    log_success
else
    log_failure
fi
 
# Copy log file to destination
cp "$LOG_FILE" "$DEST/delorean.log"
echo "Backup completed."
