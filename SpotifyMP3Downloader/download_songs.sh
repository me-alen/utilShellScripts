#!/bin/bash

while IFS= read -r url; do
    spotdl "$url" --format mp3 --output "{artist} - {title}.mp3"
    sleep 20
done < pendingDownload.txt