#!/bin/bash

#  backupCheck.sh
#  sync
#
#  Created by Kostantinos Korominas on 2/27/24.
#  Copyright © 2024 Jonas Drotleff. All rights reserved.

# Check if this is an automated run (argument passed to the script)
if [ "$1" == "automated" ]; then
    # Define the log file where the last backup date is recorded (same as your sync_files.sh)
    LOG_FILE="/Volumes/SFA-All/User Data/$(whoami)/dBackup.log"

    # Check if a backup was already done today
    if grep -q $(date '+%Y-%m-%d') "$LOG_FILE"; then
        echo "Automated backup already completed for today."
        exit 0
    fi

    # Check if the current time is within working hours (7 AM to 7 PM)
    HOUR=$(date '+%H')
    if [ "$HOUR" -lt 7 ] || [ "$HOUR" -gt 19 ]; then
        echo "Outside of working hours for automated backup."
        exit 0
    fi
fi

# Proceed with the backup by calling sync_files.sh from the same directory
/bin/bash "$(dirname "$0")/sync_files.sh"
