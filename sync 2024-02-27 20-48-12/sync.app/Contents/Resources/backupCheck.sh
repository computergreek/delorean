#!/bin/bash

# Define the specific time you want the backup to happen
backup_hour=09
backup_minute=00

# Define the start and end hours for the backup range
range_start=07
range_end=19

# Get the current hour and minute
current_hour=$(date '+%H')
current_minute=$(date '+%M')

# Check if this is an automated run (argument passed to the script)
if [ "$1" == "automated" ]; then
    # Define the log file where the last backup date is recorded (same as your sync_files.sh)
    LOG_FILE="/Volumes/SFA-All/User Data/$(whoami)/dBackup.log"

    # Check if a backup was already done today
    if grep -q $(date '+%Y-%m-%d') "$LOG_FILE"; then
        echo "Automated backup already completed for today."
        exit 0
    fi

    # Check if the current time is within the specified backup range
    if [ "$current_hour" -lt "$range_start" ] || [ "$current_hour" -gt "$range_end" ]; then
        echo "Outside of backup hours range."
        exit 0
    fi

    # Check if the current time matches the specified backup time
    if [ "$current_hour" -ne "$backup_hour" ] || [ "$current_minute" -ne "$backup_minute" ]; then
        echo "It is not the scheduled backup time yet."
        exit 0
    fi
fi

# Proceed with the backup by calling sync_files.sh from the same directory
/bin/bash "$(dirname "$0")/sync_files.sh"
