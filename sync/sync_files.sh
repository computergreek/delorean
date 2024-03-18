#!/bin/bash

#!/bin/bash

if [ "$1" = "config" ]; then
    echo "scheduled_backup_time=09:30"
    echo "range_start=07:00"
    echo "range_end=21:00"
    echo "frequency_check=3600"
    exit 0  # Stop the script after outputting the configuration
fi

# Backup scheduling parameters
echo scheduled_backup_time="09:30"   # set time for when automatic scheduled backups should occur. use 24hr
echo range_start="07:00"             # when backup range should start (e.g., 7:00am)
echo range_end="19:00"               # when backup range should end (e.g., 7:00pm)
echo frequency_check="3600"          # how often the app should check if an rsync happened that day in seconds (3600 seconds = 1 hour)

#echo "scheduled_backup_time=09:00"  # Use HH:mm format
#echo "range_start=07:00"  # Use HH:mm format
#echo "range_end=19:00"  # Use HH:mm format
#echo "frequency_check=3600"

# Define source directories
# SOURCES=("$HOME/Pictures" "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents")
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
