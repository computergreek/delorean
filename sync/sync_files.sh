#!/bin/bash

# Backup scheduling parameters
scheduled_backup_time="12:45"   # set time for when automatic scheduled backups should occur. use 24hr
range_start="07:00"             # when backup range should start (e.g., 7:00am)
range_end="19:00"               # when backup range should end (e.g., 7:00pm)
frequency_check="3600"          # how often the app should check if an rsync happened that day in seconds (3600 seconds = 1 hour)

# Define source directories
SOURCES=("$HOME/Pictures" "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents")
#SOURCES=("$HOME/Pictures" "$HOME/Downloads" "$HOME/Documents")
#SOURCES=("$HOME/Pictures" "$HOME/Documents")

# Define destination directory
DEST="/Volumes/SFA-All/User Data/$(whoami)/"

# Check if the network drive is mounted by testing if the destination directory exists and is accessible
if [ ! -d "$DEST" ]; then
    echo "Error: Destination directory $DEST does not exist or is not accessible."
    exit 1  # Exit the script with an error status
fi

# Rsync options and excludes as arrays
OPTIONS=(--archive --verbose --partial --progress --stats --delete)
EXCLUDES=(--exclude='Pictures/Photos Library.photoslibrary' --exclude='.DS_Store')
exit_codes=""

# Perform backup for each source directory
for SOURCE in "${SOURCES[@]}"; do
    rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "$SOURCE" "$DEST"
    exit_codes="$exit_codes $(basename "$SOURCE")-error:$?"
done
echo "$(date '+%Y-%m-%d %H:%M:%S')$exit_codes" >> "$DEST/dBackup.log"


echo "Backup completed."

# basically all this is doing is running this command:
# rsync --archive --verbose --partial --progress --stats --delete --exclude="Pictures/Photos Library.photoslibrary" --exclude=".DS_Store" ~/Pictures ~/Documents "/Volumes/SFA-All/User Data/$(whoami)/"
