#!/bin/bash

# Backup scheduling parameters
scheduledBackupTime="09:30"
rangeStart="07:00"
rangeEnd="21:00"
frequencyCheck="320" # How often the app should check if an rsync happened that day in seconds (3600 seconds = 1 hour)

# Define source directories
#SOURCES=("$HOME/Pictures" "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents")
#SOURCES=("$HOME/Pictures" "$HOME/Downloads" "$HOME/Documents")
SOURCES=("$HOME/Pictures" "$HOME/Documents")


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
