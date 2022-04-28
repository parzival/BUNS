#! /bin/bash

# This is a convenience script to aid in restoring a file from backup. It is not 
# required to use this script to recover backed-up files.

# The argument for the backup file's location should be given in 
# this form: TIMESTAMP/BACKUP_NAME/path/to/file
# The BACKUP_NAME is from the original backup script. 
# The file will be restored locally to /path/to/file, unless a second 
# argument is given to indicate where to restore it.
# NOTE: When restoring a folder, a trailing slash should be used; otherwise 
# a nested folder will be created.

# Example usage:
# restore.sh 2020-03-17T00h01-01h00/My Macintosh/Users/me/Documents/notes.txt
#
# This will restore the file to its original location from the backup indicated. 

# The file restore will check if a backup has recently completed and is 
# being processed, and will not continue if that is the case, to avoid 
# corrupting the restore. The setting 'ignore_archival_check' will override
# this behavior, and when true will always attempt to restore the file. Be aware
# that the culling rules and settings could result in files being deleted 
# before they can be restored. Use this setting only when you are confident 
# that the restore will not result in data corruption.

# *** Set options below to configure for your machine ***
# Options marked with BUNS.CONF must match the config file on the archival machine.

# Remote (archival) machine name/address 
remote_server=backups.server

# Backup user on remote (archival) machine. 
# Must be a member of the backup group.
remote_user=backup # BUNS.CONF

# Remote user script directory. 
remote_user_script_dir="~" # BUNS.CONF

# Base path for backups on the remote machine. 
# This should match the path of a ruleset in the (remote) config file.
backup_base_path=/mnt/backup_drive # BUNS.CONF 

# Local ssh key to use 
ssh_key=/var/root/.ssh/backup_server_key

# Local log file
log_file=~/backup_restore.log

# Disable/enable whether to check if archiving in progress
# Use with caution! May result in unexpected errors or missing files.
ignore_archival_check=false

# *** END OF CONFIG ***

function exit_bad_argument {
        cat >&2 <<EOF
Usage: $0 BACKUP_FILE_LOCATION [RESTORE_LOCATION]
  If only the backup file location is supplied, the file or folder will
  be restored to the same relative location on the local machine, possibly
  overwriting any existing files.
EOF
        exit 1
}

if [[ $# > 2 ]]; then
	printf "ERROR: Too many arguments." >&2
	exit_bad_argument
fi

if [[ $# < 1 ]]; then
	printf "ERROR: Missing backup location." >&2
	exit_bad_argument
fi

backup_file="$1"
shift

# We remove the timestamp & machine name to get the file's location on local machine
restore_location="/"${backup_file#[^/]*\/[^/]*\/}

if [[ $# == 1 ]]; then
	restore_location="$1"
fi

#echo "$restore_location" # DBG

echo "Restoring from backup on $(date)" >$log_file

# First check if a backup is in progress, and get actual file location
backup_archive_dir=$(ssh -i "$ssh_key" "${remote_user}@${remote_server}" "${remote_user_script_dir}/restore_check.sh ${backup_base_path}" 2>>$log_file)
init_result=$?

if [[ "$init_result" -ne 0 ]]; then
	if [[ "$ignore_archival_check" -eq true ]]; then
		echo "WARNING: Archival may be in progress. Proceeding due to script setting (ignore_archival_check)." | tee -a $log_file >&2
	else
		echo "ERROR: Unable to start restore due to backup/archiving potentially in progress. Exiting." | tee -a $log_file >&2
		exit 1
	fi
fi

backup_source="$backup_archive_dir"/"$backup_file"

# Now do the copy

# Some of these options may be modified. Please refer to rsync documentation for more details.
rsync -ax --delete\
		  --numeric-ids --protect-args --xattrs -M--fake-super -e "ssh -i ${ssh_key}"\
		  --log-file="$log_file" --progress --stats\
		  $remote_user@$remote_server:"${backup_source}" $restore_location 2>>$log_file

# On completion, check that we finished successfully.
if [[ $? -ne 0 ]]; then
	echo "ERROR: rsync error during restore. Restore did not complete." >>$log_file
	echo "ERROR: Restore did not complete. See ${log_file} for details." >&2
	exit 1
fi

# Log finished backup
echo "Restore complete to $restore_location" >>$log_file

echo "Restore finished. Logged to ${log_file}."


