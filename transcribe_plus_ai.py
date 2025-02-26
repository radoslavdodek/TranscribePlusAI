import mimetypes
import os
import shutil
import sys

import assemblyai as aai
import boto3
import yaml
from moviepy.editor import VideoFileClip
from openai import OpenAI


def echo_help():
    print('\nUsage: python3 transcribe_plus_ai.py <FILE>\n')


def read_yaml_config(file_path):
    with open(file_path, 'r') as file:
        try:
            return yaml.safe_load(file)
        except yaml.YAMLError as exc:
            print(exc)
            return None


# Read the configuration
script_directory = os.path.dirname(os.path.abspath(__file__))
config_file_path = os.path.join(script_directory, 'CONFIG.yaml')
config = read_yaml_config(config_file_path)

S3_BUCKET = config['s3Bucket']
S3_BACKUP_FOLDER = config.get('s3BackupFolder', '')
AWS_PROFILE = config['awsProfile']
AWS_REGION = config['awsRegion']
TRANSCRIPTION_LANG_CODE = config['transcriptionLangCode']
TRANSCRIPTION_FILE_EXTENSION = config['transcriptionFileExtension']
OUTPUT_FILE_EXTENSION = config['outputFileExtension']

OPENAI_MODEL = config.get('openaiModel')
MAX_CHUNK_SIZE = config.get('maxChunkSize')
PROMPT_TEMPLATE_FILE_NAME = config.get('promptTemplateFileName')
AAI_API_KEY = config.get('aaiApiKey')

# AWS clients
session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
s3_client = session.client('s3')
transcribe_client = session.client('transcribe')


def transcribe_audio(file, original_file):

    # Use Assembly AI to transcribe the audio
    aai.settings.api_key = AAI_API_KEY
    transcriber = aai.Transcriber()
    transcript = transcriber.transcribe(file)

    if transcript.status == aai.TranscriptStatus.error:
        print(transcript.error)
        print('Transcription failed.')
        sys.exit(1)
    else:
        print(f"\n\nTranscription for '{original_file}':\n{transcript.text}\n")

        with open('/tmp/transcription.txt', 'w') as f:
            f.write(transcript.text)
        shutil.copy('/tmp/transcription.txt', f"{original_file}.{TRANSCRIPTION_FILE_EXTENSION}")


def get_file_format(file):
    mime_type, _ = mimetypes.guess_type(file)
    if mime_type == 'audio/mpeg':
        return 'mp3'
    return ''


def convert_file_to_mp3(file):
    mime_type, _ = mimetypes.guess_type(file)
    if mime_type == 'video/mp4':
        converted_file = f"{file}.mp3"

        # Load the video file
        video_clip = VideoFileClip(file)

        # Extract the audio from the video clip and write it to a file
        audio_clip = video_clip.audio
        audio_clip.write_audiofile(converted_file, codec='mp3')

        # Close the clips to release resources
        video_clip.close()
        audio_clip.close()

        return converted_file
    return ''


def split_into_chunks(text, n):
    # Split the text into sentences
    sentences = []
    temp_sentence = ''
    for char in text:
        temp_sentence += char
        if char in '.?!':
            sentences.append(temp_sentence.strip())
            temp_sentence = ''

    # Group sentences into chunks
    chunks = []
    current_chunk = ''
    for sentence in sentences:
        if len(current_chunk) + len(sentence) + 1 <= n:  # +1 for space between sentences
            current_chunk += (' ' + sentence).strip()
        else:
            chunks.append(current_chunk)
            current_chunk = sentence
    if current_chunk:  # Add the last chunk if it's not empty
        chunks.append(current_chunk)

    return chunks


def process_by_openai(input_text_file_path, output_file_path):
    client = OpenAI()
    with open(input_text_file_path, 'r') as input_file:
        transcription = input_file.read()

        chunks = split_into_chunks(transcription, MAX_CHUNK_SIZE)
        chunk_count = len(chunks)

        print()
        print(f"Number of text chunks to process: {chunk_count}")

        with open(output_file_path, 'w') as file:
            file.write('')

        template_path = os.path.join(script_directory, PROMPT_TEMPLATE_FILE_NAME)
        with open(template_path, 'r', encoding='utf-8') as file:
            prompt_template = file.read()

        for i, chunk in enumerate(chunks):
            print()
            print(f"Processing text chunk {i + 1}/{chunk_count}: ")

            # Replace {INPUT_TEXT} with the actual content
            prompt = prompt_template.format(INPUT_TEXT=chunk)

            completion = client.chat.completions.create(
                model=OPENAI_MODEL,
                temperature=0.0,
                messages=[
                    {"role": "user", "content": prompt}
                ]
            )

            # Write text to file in case of success
            if completion.choices[0].message:
                with open(output_file_path, 'a') as file:
                    content = f"{completion.choices[0].message.content} "
                    file.write(content)
                    print(content)

        print()
        print(f"Result was stored in: '{output_file_path}'")


def main():
    if len(sys.argv) < 2:
        echo_help()
        sys.exit(1)

    file = sys.argv[1]
    original_file = file
    original_file_name = os.path.basename(original_file)

    if not os.path.exists(file):
        print(f"Provided file not found: {file}")
        echo_help()
        sys.exit(1)

    file_format = get_file_format(file)
    if not file_format:
        if os.path.isfile(f"{file}.mp3"):
            file = f"{file}.mp3"
            file_format = "mp3"
            print(f"Mp3 file found: '{file}'")
        else:
            print('Convert file to supported format...')
            file = convert_file_to_mp3(file)
            file_format = get_file_format(file)
            if not file_format:
                print('Unable to convert file to supported format.')
                sys.exit(1)

    if not file_format:
        print("Supported file types are: mp3 and mp4.")
        echo_help()
        sys.exit(1)

    transcription_file = f"{original_file}.{TRANSCRIPTION_FILE_EXTENSION}"
    if not os.path.isfile(transcription_file):
        transcribe_audio(file, original_file)
        print('Transcription done')
    else:
        print('Transcription file found:', transcription_file)

    if os.path.isfile(transcription_file):
        print('\nProcessing transcription by OpenAI, please wait...')
        process_by_openai(transcription_file, f"{original_file}.{OUTPUT_FILE_EXTENSION}")

        # Backup files to AWS S3 bucket
        if S3_BACKUP_FOLDER:
            print(f"Backing up the files to S3. S3_BACKUP_FOLDER is set to '{S3_BACKUP_FOLDER}'")
            s3_client.upload_file('/tmp/transcription.txt', S3_BUCKET,
                                  f"{S3_BACKUP_FOLDER}/{original_file_name}.{TRANSCRIPTION_FILE_EXTENSION}",
                                  ExtraArgs={'StorageClass': 'REDUCED_REDUNDANCY'})
            s3_client.upload_file(original_file, S3_BUCKET, f"{S3_BACKUP_FOLDER}/{original_file_name}",
                                  ExtraArgs={'StorageClass': 'REDUCED_REDUNDANCY'})
            s3_client.upload_file(f"{original_file}.{OUTPUT_FILE_EXTENSION}", S3_BUCKET,
                                  f"{S3_BACKUP_FOLDER}/{original_file_name}.{OUTPUT_FILE_EXTENSION}")
        else:
            print("S3_BACKUP_FOLDER is not set, no backup executed")
    else:
        print('Transcription file not found')

    print('Script finished.')


if __name__ == '__main__':
    main()
