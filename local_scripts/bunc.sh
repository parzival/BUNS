#! /bin/bash

# *** Set options below to configure for your machine ***
# Options marked with BUNS.CONF must match the config file on the archival machine.

# Remote (archival) machine name/address 
remote_server=backups.server

# Backup user on remote machine. 
# Must be a member of the backup group.
remote_user=backup # BUNS.CONF 

# Remote user script directory.
remote_user_script_dir="~"  # BUNS.CONF 

# Base path for backups on the remote machine. 
# This should match the path of a ruleset in the (remote) config file.
backup_base_path=/mnt/backup_drive # BUNS.CONF 

# Remote directory to place backups in, typically the local machine or volume name.
backup_name="My Macintosh"

# Local ssh key to use
ssh_key=/var/root/.ssh/backup_server_key

# Local log file
log_file=/var/log/last_backup.log

# Rsync filter rules file. 
# To disable these rules, remove the --filter option in the rsync command below.
rsync_rules=rsync_filter.rules

# *** END OF CONFIG ***

echo "Starting backup on $(date)" >$log_file

# First check if we can initiate backup
backup_dir=$(ssh -i "$ssh_key" "${remote_user}@${remote_server}" "${remote_user_script_dir}/init_check.sh ${backup_base_path}" 2>>$log_file)
init_result=$?

if [[ "$init_result" -ne 0 ]]; then
	echo "ERROR: Unable to start backup. Exiting." | tee -a $log_file >&2
	exit 1
fi

# We should be okay to proceed

#backup_time=$(date --iso-8601=minutes) 
backup_time=$(date +%Y-%m-%dT%H:%M%z)  # Use this version if iso-8601 not supported by date 

# Some of these options may be modified. Please refer to rsync documentation for more details.
rsync -ax --delete --delete-excluded --filter="merge ${rsync_rules}"\
		  --numeric-ids --protect-args --xattrs -M--fake-super -e "ssh -i ${ssh_key}"\
		  --rsync-path="${remote_user_script_dir}/rsync_wrapper.sh ${backup_base_path} ${backup_name} ${backup_time}" \
		  --log-file="$log_file" --progress --stats\
		  --relative / $remote_user@$remote_server:"${backup_dir}/${backup_name}" 2>>$log_file

# On completion, check that we finished successfully.
if [[ $? -ne 0 ]]; then
	echo "ERROR: rsync error during backup. Backup did not complete." >>$log_file
	echo "ERROR: Backup did not complete. See ${log_file} for details." >&2
	exit 1
fi

# Log finished backup
echo "Backup time sent to server is ${backup_time}" >>$log_file
echo "Backup completed." >>$log_file

echo "Backup done. Logged to ${log_file}."


