#!/usr/bin/env bash
#
# Loads an org that holds the AI Assist source (a scratch org or a sandbox) with sample
# configuration and records, so every object has something in it.
#
#   scripts/load-sample-data.sh [org alias]        (the default org when no alias is given)
#
# It runs the five anonymous Apex scripts in scripts/apex/sample-data in order. They are separate
# because one anonymous script is limited to 32,000 characters, and because custom metadata cannot
# be deployed in a transaction that also writes records.
#
# The running user needs the AIAssistAdminUser, AIAssistSuperUser and AIAssistUser permission sets.
# Safe to run again: settings and custom metadata are overwritten, records that already exist are
# skipped. Options (the class or Flow behind the sample workflow actions, how many conversations)
# are at the top of each script.

set -euo pipefail

directory="$(cd "$(dirname "$0")" && pwd)/apex/sample-data"
org_flag=()
if [ -n "${1:-}" ]; then
  org_flag=(--target-org "$1")
fi

for part in 01-settings 02-agents 03-tools-and-rules 04-activity 05-custom-metadata; do
  if ! output="$(sf apex run --file "$directory/$part.apex" ${org_flag[@]+"${org_flag[@]}"} 2>&1)"; then
    echo "$part.apex failed:"
    echo "$output" | head -20
    exit 1
  fi

  # The script's own summary: from its debug line to the next log entry.
  echo "$output" | awk '
    /USER_DEBUG.*SAMPLE DATA: / { printing = 1; sub(/^.*SAMPLE DATA: /, "== "); print; next }
    printing && /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+ \([0-9]+\)\|/ { printing = 0 }
    printing { print }
  '
done
