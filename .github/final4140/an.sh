#!/bin/bash
# Runs analyze.py with the site lists from lib.sh. Usage: an.sh <dir> <mode> <label>
. "$(dirname "$0")/lib.sh"; PHPSITES="$PHPSITES" HTMLSITES="$HTML" python3 $F/analyze.py "$@"
