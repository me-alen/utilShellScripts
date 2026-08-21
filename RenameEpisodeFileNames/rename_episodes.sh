#!/bin/bash

# Check if directory is passed
if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/your/files"
  exit 1
fi

TARGET_DIR="$1"

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory '$TARGET_DIR' not found."
  exit 1
fi

cd "$TARGET_DIR" || exit

for file in *; do
  [[ -f "$file" ]] || continue

  # Match episode code SxxExx (case-insensitive)
  if [[ $file =~ ([Ss][0-9]{2}[Ee][0-9]{2}) ]]; then
    episode_code="${BASH_REMATCH[1]}"

    # Extract everything before the episode code as the show name
    prefix="${file%%"$episode_code"*}"

    # Clean up show name:
    # - Trim trailing dots, spaces, underscores
    # - Replace spaces, underscores with dots
    # - Remove any non-alphanumeric/dot characters
    showname=$(echo "$prefix" | sed -E 's/[._ ]+/\./g' | sed -E 's/\.*$//' | sed -E 's/[^A-Za-z0-9.]+//g')

    # Work out the extension, if there is one. The text after the last dot only
    # counts as an extension when it actually looks like one and isn't the
    # episode code itself, so "NoExtensionFile.S02E02" and "ShowNameS02E02"
    # are treated as having no extension instead of repeating part of the name.
    ext=""
    if [[ $file == *.* ]]; then
      candidate="${file##*.}"
      if [[ $candidate != "$episode_code" && $candidate =~ ^[A-Za-z0-9]{1,8}$ ]]; then
        ext="$candidate"
      fi
    fi

    # Join the parts, skipping any that are empty. A file named just "S04E09.mkv"
    # has no show name, so it keeps that name instead of becoming hidden.
    newname="$episode_code"
    [[ -n $showname ]] && newname="$showname.$newname"
    [[ -n $ext ]] && newname="$newname.$ext"

    if [[ $newname == "$file" ]]; then
      echo "✅ Already named correctly: $file"
    else
      mv -v "$file" "$newname"
    fi
  else
    echo "⚠️  Episode code not found in: $file"
  fi
done
