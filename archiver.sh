#!/bin/bash

set -e
cd "$(dirname "$0")"
7z a -p -mhe -t7z -xr'!.git' "Knowledge-$(date '+%Y-%m-%d').7z" .backup/* "$HOME/Desktop/Projects"
