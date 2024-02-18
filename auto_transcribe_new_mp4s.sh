#!/bin/bash

DIRECTORY_TO_WATCH=<CHANGE_TO_YOUR_DIRECTORY>
TRANSCRIBE_SCRIPT=<CHANGE_TO_TRANSCRIBE_SCRIPT_PATH>

inotifywait --include 'mp4' -m "${DIRECTORY_TO_WATCH}" -e moved_to --format '%w%f' |
    while IFS=' ' read -r fname
    do
        [ -f "${fname}" ] && "${TRANSCRIBE_SCRIPT}" "${fname}"
    done