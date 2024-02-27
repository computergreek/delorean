#!/bin/bash

# Define source directories
#SOURCES=("$HOME/Pictures" "$HOME/Downloads" "$HOME/Documents")
SOURCES=("$HOME/Pictures" "$HOME/Documents")

# Define destination directory
DEST="/Volumes/test/$(whoami)/"

# Rsync options and excludes as arrays
OPTIONS=(--archive --verbose --partial --progress --stats --delete)
EXCLUDES=(--exclude='Pictures/Photos Library.photoslibrary' --exclude='.DS_Store')

# Perform backup for each source directory
for SOURCE in "${SOURCES[@]}"; do
    rsync "${OPTIONS[@]}" "${EXCLUDES[@]}" "$SOURCE" "$DEST"
done

echo "Backup completed."
