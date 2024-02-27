#!/bin/bash

# Define source directories
#SOURCES=("$HOME/Pictures" "$HOME/Downloads" "$HOME/Documents")
SOURCES=("$HOME/Pictures" "$HOME/Documents")

# Define destination directory
# DEST="/Volumes/test/$(whoami)/"
DEST="/Volumes/SFA-All/User Data/$(whoami)/"

# Rsync options and excludes as arrays
OPTIONS=(--archive --verbose --partial --progress --stats --delete)
EXCLUDES=(--exclude='Pictures/Photos Library.photoslibrary' --exclude='.DS_Store')
exit_codes=""

# Perform backup for each source directory
for SOURCE in "${SOURCES[@]}"; do
    rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "$SOURCE" "$DEST"
    exit_codes="$exit_codes $(basename "$source")-error:$?;"
done
echo "$(date '+%Y-%m-%d %H:%M:%S')$exit_codes" >> /sfa-all/user\ data/gatorlink/dBackup.log


echo "Backup completed."



# add log in DEST directory


