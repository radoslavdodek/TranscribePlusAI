#!/bin/bash

#
# This is a helper bash script to run the Python script with the same name
#

echo_help()
{
	echo ''
	echo 'Usage: ./transcribe_plus_ai.sh <FILE>'
	echo ''
}

if [[ -z "${1}" ]]
then
	echo_help
	exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Run Python script with all arguments passed to this script
python transcribe_plus_ai.py "$@"
