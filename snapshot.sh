#! /bin/bash

# Creates a new snapshot when backups have completed.

# The first argument passed should be the base directory for the source
# and repository.
#
# The second argument should be a date string to be used
# for naming the backup directory (snapshot).
#
# Remaining arguments are the rules passed to the culling script.
#
# After the snapshot is created, old backups will then be culled
# according to the rules passed.
#
# This file cannot be run standalone, as it relies on the configuration
# settings externally defined.

if [[ $# <  2 ]]; then
	printf "ERROR: required argument missing." >&2 
	exit 1
fi

backup_root="$1"
shift
timestamp="$1"
shift

ruleset="$*"

backup_source="${backup_root}/${BACKUP_DIR}"
backup_repo="${backup_root}/${BACKUP_REPOSITORY}"

# Dates are in ISO-8601 format, but we want to remove the colons to be safe
# in filenames.
dan=$(echo "$timestamp" | tr : $COLON_REPLACEMENT)

sn_name="${backup_repo}/${dan}"

# Make the snapshot
case "$SNAPSHOT_METHOD" in
	btrfs | BTRFS )
		btrfs subvol snapshot -r $backup_source $sn_name
		;;
	cp | copy | COPY )
		cp -r $backup_source $sn_name
		;;
	*)
		echo "Unrecognized Snapshot Method - no snapshot created." >&2
		exit 1
		;;
esac

# Now cull the old ones
echo "Snapshot ${sn_name} complete. Culling old backups..." >>$LOG_FILE

$SCRIPT_DIR/cull.sh "$backup_repo" "$ruleset"
