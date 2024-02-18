#!/bin/bash
set -e

#
# Uploads file to S3 bucket and runs AWS transcribe API on it.
# Afterwards, it executes the 'process_by_openai.py' script on the transcription file.
#

script_path=$(realpath "$0")
script_dir=$(dirname "$script_path")
config_file="${script_dir}/CONFIG.yaml"

ORIGINAL_FILE="${1}"
FILE="${1}"

#
# FUNCTIONS:
#-----------------------------------------------------------------------

#
# Write help
#
echo_help()
{
	echo ''
	echo 'Usage: ./transcribe.sh <FILE>'
	echo ''
}

# Function to read a specific parameter from the YAML file
read_yaml() {
    local key=$1
    local value=$(grep "^${key}:" $config_file | head -n1 | awk '{ print $2 }')
    echo $value
}

echo "Reading configuration parameters from '${config_file}'"
S3_BUCKET=$(read_yaml "s3Bucket")
S3_BACKUP_FOLDER=$(read_yaml "s3BackupFolder")
AWS_PROFILE=$(read_yaml "awsProfile")
TRANSCRIPTION_LANG_CODE=$(read_yaml "transcriptionLangCode")
TRANSCRIPTION_FILE_EXTENSION=$(read_yaml "transcriptionFileExtension")
OUTPUT_FILE_EXTENSION=$(read_yaml "outputFileExtension")

#
# Uploads audio file to AWS S3 and initiates Transcribe job
#
# Parameters:
#  1. Audio File
#  2. Original file
#  3. Format (mp3)
#
transcribe_audio() {
	local FILE="${1}"
	local ORIGINAL_FILE="${2}"
	local FORMAT="${3}"

	local ORIGINAL_FILE_NAME="$(basename -- "$ORIGINAL_FILE")"

	# Upload file to AWS S3
	echo 'Upload file to S3...'
	aws --profile ${AWS_PROFILE} s3 cp "${FILE}" "s3://${S3_BUCKET}/audio.${FORMAT}" --storage-class REDUCED_REDUNDANCY

	# Check if upload was successful
	if [[ "${?}" -ne 0 ]]
	then
		echo 'AWS S3 upload failed'
		exit 1
	fi

	# Call AWS Transcribe service
	local JOB_NAME="job-$(date +%Y-%m-%d)-$(uuidgen)"
	printf "Working on transcription (${JOB_NAME})..."
	aws --profile ${AWS_PROFILE} --region eu-central-1 transcribe start-transcription-job --transcription-job-name "${JOB_NAME}" --language-code "${TRANSCRIPTION_LANG_CODE}" --media-format "${FORMAT}" --media "{\"MediaFileUri\": \"https://${S3_BUCKET}.s3.eu-central-1.amazonaws.com/audio.${FORMAT}\"}" &> /dev/null

	# Check if Transcribe call was successful
	if [[ "${?}" -ne 0 ]]
	then
		echo 'AWS Transcribe call failed'
		exit 1
	fi

	# Check the result
	# Check the result
	local STATUS="IN_PROGRESS"
	while [[ "${STATUS}" != "COMPLETED" ]]
	do
		sleep 3
		local RES=$(aws --profile ${AWS_PROFILE} transcribe get-transcription-job --region eu-central-1 --transcription-job-name "${JOB_NAME}")
		local STATUS=$(echo $RES | jq -r '.TranscriptionJob.TranscriptionJobStatus')

		if [[ "${STATUS}" = "COMPLETED" ]]
		then
			local TRANSCRIPTION_URL=$(echo $RES | jq -r '.TranscriptionJob.Transcript.TranscriptFileUri')
			local TRANSCRIPTION=$(curl -s ${TRANSCRIPTION_URL} | jq -r '.results.transcripts[0].transcript')

			echo ''
			echo ''
			echo "Transcription for '${ORIGINAL_FILE}':"
			echo ''
			echo "${TRANSCRIPTION}"
			echo ''

			#
			echo "${TRANSCRIPTION}" > /tmp/transcription.txt
			cp /tmp/transcription.txt "${ORIGINAL_FILE}.${TRANSCRIPTION_FILE_EXTENSION}"

      echo 'Remove file from S3...'
      aws --profile ${AWS_PROFILE} s3 rm "s3://${S3_BUCKET}/audio.${FORMAT}"

			return 0
		else 
			printf '.'
		fi
	done
	return 1
}

#
# Check if the file is of supported type (mp3)
#
# Parameters:
#   1. File
#
get_file_format() {
	local FILE=${1}

	local MIME=$(file --mime-type -b "$FILE")
	case $MIME in
		'audio/mpeg') 
			echo 'mp3'
			;;
		*) 
			echo ''
			;;
	esac
}

#
# Check if input file can be converted to supported audio file.
# If yes -> convert it and return path to new audio file.
#
# Parameters:
#   1. File
# Returns: 
#   Name of converted audio file. Empty string otherwise
#
convert_file_to_mp3() {
	local FILE=${1}
	local CONVERTED_FILE=''

	local MIME=$(file --mime-type -b "$FILE")
	case $MIME in
		'video/mp4') 
			# Convert this mp4 file to mp3
			ffmpeg -loglevel quiet -y -i "${FILE}" -f mp3 -ac 1 -ab 32768 -vn "${FILE}.mp3" < /dev/null && CONVERTED_FILE="${FILE}.mp3" 
			;;
	esac

	echo "${CONVERTED_FILE}"
}

#-----------------------------------------------------------------------
# END OF FUNCTIONS
# 

# Check whether AWS CLI is installed
aws --version &> /dev/null
if [[ "${?}" -ne 0 ]]
then
	echo 'AWS CLI is not installed'
	exit 1
fi

# Check whether user provided path to audio file
if [[ -z "${FILE}" ]]
then
	echo 'Audio file not provided'
	echo_help
	exit 1
fi

# Check whether the file exists
if [[ ! -a "${FILE}" ]]
then
	echo "Provided file not found: ${FILE}"
	echo_help
	exit 1
fi

# Check MIME type
FORMAT=$(get_file_format "${FILE}")

# Check if the file is in supported format (mp3)
if [[ -z "${FORMAT}" ]]
then
  # Not a supported audio format. Check if there already is "mp3" file in the directory
  if [ -f "${FILE}.mp3" ];
  then
    FILE="${FILE}.mp3"
    FORMAT="mp3"
    echo "Mp3 file found: '${FILE}'"
  else
    # Not a supported audio format. Check if we can convert it to mp3
    echo 'Convert file to supported format...'
    FILE="$(convert_file_to_mp3 "${FILE}")"
    FORMAT=$(get_file_format "${FILE}")
  fi

	if [[ -z "${FORMAT}" ]]


	then
		echo 'Unable to convert file to supported format.'
	fi
fi

if [[ -z "${FORMAT}" ]]
then
	echo "Supported file types are: mp3 and mp4."
	echo_help
	exit 1
fi

if [ -f "${ORIGINAL_FILE}.${TRANSCRIPTION_FILE_EXTENSION}" ];
then
  echo "Transcription file found: '${ORIGINAL_FILE}.${TRANSCRIPTION_FILE_EXTENSION}'"
else
  transcribe_audio "${FILE}" "${ORIGINAL_FILE}" "${FORMAT}"
  echo 'transcription done'
fi

# If transcription file is found, process it using OpenAI:
if [ -f "${ORIGINAL_FILE}.${TRANSCRIPTION_FILE_EXTENSION}" ];
then
  echo
  echo 'Processing transcription by OpenAI, please wait...'
  python3 "${script_dir}/process_by_openai.py" "${ORIGINAL_FILE}.${TRANSCRIPTION_FILE_EXTENSION}" "${ORIGINAL_FILE}.${OUTPUT_FILE_EXTENSION}"

  # Backup files to AWS S3 bucket
  if [ -z "${S3_BACKUP_FOLDER}" ]; then
      echo "S3_BACKUP_FOLDER is not set, no backup executed"
  else
      echo "Backing up the files to S3. S3_BACKUP_FOLDER is set to '${S3_BACKUP_FOLDER}'"
			aws --profile ${AWS_PROFILE} s3 cp /tmp/transcription.txt "s3://${S3_BUCKET}/${S3_BACKUP_FOLDER}/${ORIGINAL_FILE_NAME}.${TRANSCRIPTION_FILE_EXTENSION}"
			aws --profile ${AWS_PROFILE} s3 cp "${ORIGINAL_FILE}" "s3://${S3_BUCKET}/${S3_BACKUP_FOLDER}/${ORIGINAL_FILE_NAME}" --storage-class REDUCED_REDUNDANCY
			aws --profile ${AWS_PROFILE} s3 cp "${ORIGINAL_FILE}.${OUTPUT_FILE_EXTENSION}" "s3://${S3_BUCKET}/${S3_BACKUP_FOLDER}/${ORIGINAL_FILE_NAME}.${OUTPUT_FILE_EXTENSION}"
  fi

else
  echo 'Transcription file not found'
fi

echo 'Script finished.'