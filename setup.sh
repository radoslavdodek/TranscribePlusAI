#!/bin/bash

#
# This script sets up a Python virtual environment and installs the necessary dependencies
#

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

echo
echo "Setup completed."
