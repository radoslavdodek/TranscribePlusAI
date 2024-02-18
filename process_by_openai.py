import os
import sys

import yaml
from openai import OpenAI


def print_usage():
    print()
    print('Usage: python3', __file__, '<INPUT_TEXT_FILE_PATH> <OUTPUT_FILE_PATH>')


# Check if both mandatory arguments are provided
if len(sys.argv) < 3:
    print_usage()
    exit(1)

input_text_file_path = sys.argv[1]
output_file_path = sys.argv[2]


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
OPENAI_MODEL = config.get('openaiModel')
MAX_CHUNK_SIZE = config.get('maxChunkSize')
PROMPT_TEMPLATE_FILE_NAME = config.get('promptTemplateFileName')


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


# Process the file using OpenAI
client = OpenAI()
with open(input_text_file_path, 'r') as file:
    transcription = file.read()

    chunks = split_into_chunks(transcription, MAX_CHUNK_SIZE)
    chunk_count = len(chunks)

    print()
    print(f"Number of text chunks to process: {chunk_count}")

    with open(output_file_path, 'w') as file:
        file.write('')

    script_directory = os.path.dirname(os.path.abspath(__file__))
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
