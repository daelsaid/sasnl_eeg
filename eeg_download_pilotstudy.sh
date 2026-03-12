#!/bin/bash

#Author: Dawlat El-Said 
# eeg_download_pilotstudy.sh - Download EEG pilot data from Box to oak storage
#
# Box folder naming convention: PID_visit_session.EEG
#   PID/visit/session/eeg/clicktrials/         <- clicktrials
#   PID/visit/session/eeg/storytrials/         <- storytrials
#   PID/visit/session/behavioral/eeg/Results/  <- behavioral logs from expyfun + audio of comprehension question and answer
#
# Usage:
#   ./eeg_download_pilotstudy.sh                  # download all PIDs
#   ./eeg_download_pilotstudy.sh 14054            # download specific PID
#   ./eeg_download_pilotstudy.sh --dry-run        # preview all dry run
#   ./eeg_download_pilotstudy.sh 14054 --dry-run  # preview specific PID dryrun

set -u

usage() {
    echo "Usage: $(basename "$0") [PID] [--dry-run] [-h]"
    echo ""
    echo "  PID          Optional. Download the subject ID provided (e.g. 14054)."
    echo "               if no PID, all dirs downloaded if they match standard structure"
    echo "  --dry-run    do a dry run of the download"
    echo "  -h, --help   Show this help message."
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")                  # download all PIDs"
    echo "  $(basename "$0") 14054            # download 14054 only"
    echo "  $(basename "$0") --dry-run        # dry run download of all EEG dirs"
    echo "  $(basename "$0") 14054 --dry-run  # dry run download of 14054"
    exit 0
}

box_parent_dir="Abrams Lab Studies/Abrams_EEG_data/from_1070_BV_computer/in_lab_eeg_pilot_data"
oak_dir='/oak/stanford/groups/daa/rawdata/sasnl/eeg_pilot'

#args
DRY_RUN=''
TARGET_PID=''
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage
    elif [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN='--dry-run'
    elif [[ "$arg" =~ ^[0-9]+$ ]]; then
        TARGET_PID="$arg"
    else
        echo "Error: unknown argument '$arg'"
        echo ""
        usage
    fi
done

LOG_FILE="/oak/stanford/groups/daa/sasnlscripts/utilities/eeg_download/.logs/download_$(date +%Y%m%d_%H%M%S).log"

# write output to log and print in stdout
exec > >(tee -a "$LOG_FILE") 2>&1


echo "========================================"
echo "EEG data download from BOX"
echo "Started:  $(date)"
echo "Source:   $box_parent_dir"
echo "Output:   $oak_dir"
[[ -n "$TARGET_PID" ]] && echo "PID:      $TARGET_PID (only)"
[[ -n "$DRY_RUN"    ]] && echo "Mode:     DRY RUN (no files will be copied)"
echo "Log:      $LOG_FILE"
echo "========================================"
echo ""

n_success=0
n_skip=0
n_error=0

# get dirnames
folders=( $(rclone lsd stanfordbox:/"${box_parent_dir}" | awk '{print $NF}') )

if [[ ${#folders[@]} -eq 0 ]]; then
    echo "ERROR: rclone lsd returned no folders. Check your Box connection or rate limit."
    exit 1
fi

for folder in "${folders[@]}"; do
    echo $folder
    # Only process folders matching exactly: PID_visit_session.EEG format
    if [[ ! "$folder" =~ ^[0-9]+_[0-9]+_[0-9]+\.EEG$ ]]; then
        echo "SKIP  $folder  (does not match PID_visit_session.EEG)"
        n_skip=$((n_skip + 1))
        continue
    fi

    base="${folder%.EEG}"
    echo $base
    IFS='_' read -r pid visit session <<< "$base"

    # If PID provided, skip other subj
    if [[ -n "$TARGET_PID" && "$pid" != "$TARGET_PID" ]]; then
        n_skip=$((n_skip + 1))
        continue
    fi

    echo "----"
    echo "Processing  PID=$pid  visit=visit$visit  session=session$session"

    subject_dir_box="$box_parent_dir/$folder"
    eeg_dir="$oak_dir/$pid/visit$visit/session$session/eeg"
    behav_eeg_dir="$oak_dir/$pid/visit$visit/session$session/behavioral/eeg/Results"
    echo $subject_dir_box $eeg_dir  $behav_eeg_dir


    mkdir -p \
        "$eeg_dir/clicktrials" \
        "$eeg_dir/storytrials" \
        "$behav_eeg_dir"

    # --- clicktrials EEG files and qc
    echo "  [1/3] clicktrials → $eeg_dir/clicktrials"
    if rclone -v --stats 5s --retries 5 --retries-sleep 10s copy $DRY_RUN \
            --max-depth 1 \
            --include "*clicktrials*" \
            --ignore-existing \
            --progress \
            stanfordbox:/"$subject_dir_box" \
            "$eeg_dir/clicktrials"; then
        echo "        done"
    else
        echo "        ERROR: clicktrials copy failed for $pid/$visit/$session"
        n_error=$((n_error + 1))
    fi

    # --- storytrials
    echo "  [2/3] storytrials → $eeg_dir/storytrials"
    if rclone -v --stats 5s --retries 5 --retries-sleep 10s copy $DRY_RUN \
            --max-depth 1 \
            --include "*storytrials*" \
            --ignore-existing \
            --progress \
            stanfordbox:/"$subject_dir_box" \
            "$eeg_dir/storytrials"; then
        echo "        done"
    else
        echo "        ERROR: storytrials copy failed for $pid/$visit/$session"
        n_error=$((n_error + 1))
    fi

    # --- behavioral Results folder (comp_audio_recording/) ---
    echo "  [3/3] Results/ → $behav_eeg_dir"
    if rclone -v --stats 5s --retries 5 --retries-sleep 10s copy  $DRY_RUN \
            --ignore-existing \
            --progress \
            stanfordbox:/"$subject_dir_box/Results" \
            "$behav_eeg_dir"; then
        echo "        done"
    else
        echo "        WARNING: Results copy failed (folder may not exist) for $pid/$visit/$session"
    fi

    n_success=$((n_success + 1))

done

echo ""
echo "========================================"
echo "Summary"
echo "  Processed: $n_success"
echo "  Skipped:   $n_skip"
echo "  Errors:    $n_error"
echo "Log:      $LOG_FILE"
echo "Finished: $(date)"
echo "========================================"
