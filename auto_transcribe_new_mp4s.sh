#!/bin/bash

DIRECTORY_TO_WATCH=/home/rado/Videos
TRANSCRIBE_SCRIPT=/home/rado/Work/personal-projects/useful-tools/transcribe/transcribe.sh

inotifywait --include 'mp4' -m "${DIRECTORY_TO_WATCH}" -e moved_to --format '%w%f' |
    while IFS=' ' read -r fname
    do
        [ -f "${fname}" ] && "${TRANSCRIBE_SCRIPT}" "${fname}"
    done