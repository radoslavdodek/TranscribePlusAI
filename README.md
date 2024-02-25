# Transcribe Video/Audio File and Process Transcription Using OpenAI

## Prerequisites

The following command line tools need to be installed:

- git (https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- Python 3 (https://www.python.org)

## Installation

- Clone this repository to a local directory:

  ```shell
  git clone git@github.com:radoslavdodek/TranscribePlusAI.git
  cd TranscribePlusAI
  ```

- Set `OPENAI_API_KEY` environment variable (You can create an API KEY here: https://platform.openai.com/api-keys). You
  can do so in `~/.zshrc` or `~/.bashrc` file:
  ```sh
  export OPENAI_API_KEY="<YOUR_KEY>"
  ```
- Install python virtual environment and required python packages:
  ```sh
  ./setup.sh
  ```

## Usage

Here's how to use the command on mp3 or mp4 files:

```shell
./transcribe_plus_ai.sh "<YOUR_FILE_PATH>"
```

If you're working with mp4 file, the command will first convert it to mp3 file.
Then, it will use the AWS Transcribe API to create a transcription of the audio.
This transcription will be stored in a file named `<YOUR_FILE_PATH>.transcription`
(the file extension can be configured in `CONFIG.yaml` file).

After the transcription is created, a Python script will run to further process this content.
It will use the prompt specified in the `PROMPT_TEMPLATE.txt` file.
The results of this process will be saved in a file named `<YOUR_FILE_PATH>.output`
(the file extension can be configured in `CONFIG.yaml` file).

### Watch for new mp4 files in the directory

If you would like to automatically call this script when a new mp4 file is added to a specific directory,
you can configure it as follows (valid for Ubuntu):

- Create new file called `auto_transcribe_new_mp4s.sh`:

```shell
#!/bin/bash

DIRECTORY_TO_WATCH=<CHANGE_TO_YOUR_DIRECTORY>
TRANSCRIBE_SCRIPT=<CHANGE_TO_TRANSCRIBE_SCRIPT_PATH>

inotifywait --include 'mp4' -m "${DIRECTORY_TO_WATCH}" -e moved_to --format '%w%f' |
    while IFS=' ' read -r fname
    do
        [ -f "${fname}" ] && "${TRANSCRIBE_SCRIPT}" "${fname}"
    done
```

Note: don't forget to specify `DIRECTORY_TO_WATCH` and `TRANSCRIBE_SCRIPT` in the above script.

We need to start this file at the startup:
Create new file: `~/.config/autostart/auto_transcribe_new_mp4s.sh.desktop`

```
[Desktop Entry]
Type=Application
Exec=<YOUR_SCRIPT_PATH>/auto_transcribe_new_mp4s.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Transcribe videos automatically
```

Note: Don't forget to change the `YOUR_SCRIPT_PATH` in the above file.
