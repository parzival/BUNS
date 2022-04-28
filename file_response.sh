#! /bin/bash

# Script to monitor status for BUNS backup process

# This will be passed a file that was created/modified in the backup status
# directory.
# * For the PID file, a timeout will begin. When the timeout expires, the
#   PID file is removed unless the process is active.
# * For the completion file (indicating a backup is done), a new snapshot
#   is made and the completion file is removed. The client backup process must wait
#   on the completion snapshot, even if it has acquired access to the PID file.
# * If the file is not one of the expected monitor files, the filename is logged
#   but no other action is taken.
#
# The config file must be passed as an argument; the 'read_config.sh' script to
# read the config file must also be present in the same directory as this script.

# Require the path, filename, and config file (in that order)
if [[ $# != 3 ]]; then
	printf "Required arguments missing.\n" >&2
	exit 1
fi;

config_file="$3"
passed_filename="$2"
passed_path="$1"

# Load config 
config_script="$(dirname "$0")/read_config.sh"
source $config_script "$config_file" >/dev/null

backup_root_path=${passed_path%"/$MONITOR_DIR"}
monitor_folder="${backup_root_path}/${MONITOR_DIR:-"status"}"

pid_filename="${PID_FILENAME:-"in_progress"}.pid"
pid_path="${monitor_folder}/${pid_filename}"

lockfilename="${LOCK_FILENAME:-"buns"}.lock"
lockfile="${monitor_folder}/${lockfilename}"

monfilename="monitoring_progress"
monfile="${monitor_folder}/${monfilename}"

completion_filename=${BACKUP_DONE_FILENAME:-"backup_ready"}
completion_file="${monitor_folder}/${completion_filename}"

snapshot_script="${SCRIPT_DIR:-"/root/scripts/buns"}/snapshot.sh"

# Monitors that the process in the PID file is still active; returns
# true (0) if so, false (non-zero)  if not. Will return false if the PID
# file is not present.
function check_progress_active() {
	( flock -n 128 
		if [[ -e "$pid_path" ]]; then
			read -r -n 100 progress_pid < "$pid_path"
			ps -p "$progress_pid" >/dev/null 2>&1
			return $?
		else
			return 1
		fi
	) 128>$lockfile
}

# Determine what to do, based on the passed file
case "$passed_filename" in
	$pid_filename)
		# Check status every minute, and ensure that PID gets deleted
		# once the process is dead.
		# A 'monitoring' file is added if it is not present.
		# This can aid debugging, and reduces the likelihood of
	    # duplicate 'in-progress' messages.
		if ! [[ -e "$monfile" ]]; then
			echo "Backup initiated $(date)" >$monfile
			echo "In-progress backup detected:  $(date)" >>"$LOG_FILE"
		fi
		sleep 60s
		while check_progress_active; do
			sleep 60s
		done
		# Remove the monitor file
		rm -f $monfile &2>1 >>"$LOG_FILE"
		# Ensure PID file is removed
		( flock -n 153
			if [[ -e "$pid_path" ]]; then
				echo "Timeout occurred at $(date)" >>"$LOG_FILE"
				echo "Removing ${pid_path}" >>"$LOG_FILE"
				rm -f "$pid_path" &2>1 >>"$LOG_FILE"
				# This takes care of a situation where the completion
				# file did not get removed. The first new backup will 
				# fail, but will trigger a timeout. This allows backups
				# to continue from that point forward.
				rm -f "$completion_file" &2>1 >>"$LOG_FILE"
			fi
		) 153>$lockfile
		;;
	$completion_filename)
		# Backup indicated as complete
		# Check the file contents for a parsable date
		if [[ -e "$completion_file" ]]; then
			read -r -n 200 dateline < "$completion_file"
			filedate=$(date --iso-8601="minutes" -d "$dateline" 2>>"$LOG_FILE")
			if $?; then
				snapshot_time="$filedate"
			else
				# Just use current time if date in file is invalid
				snapshot_time=$(date --iso-8601="minutes")
			fi
			# Create a snapshot using the date as its name
			$snapshot_script "$backup_root_path" "$snapshot_time" "${RULESETS[$backup_root_path]}"  2>>"$LOG_FILE"
			rm "$completion_file" 2>>"$LOG_FILE"
			rm -f "$monfile" >/dev/null &2>1
		fi		
		;;
	$lockfilename | $monfilename)
		:      # Don't need to respond to these
		;;	
	*)			
		echo "File in monitor directory ignored: ${passed_filename}" >>"$LOG_FILE"
		;;
esac
