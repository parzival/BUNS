#! /bin/bash

# Cull old backups based on preservation interval rules. 

# Required arguments: directory to cull, followed by all preservation rules to 
# apply. The cull will not be applied and exit with an error code of 2 if any
# argument rules are improperly formatted.

# Backup preservation rules have a type, indicated by the first letter in the
# rule. This is followed by the number of backups associated with the rule,
# which is followed by a '/'. For 'K' and 'R' rules the value after the slash
# is a time period (optionally with a letter P at the start). For 'D' rules
# the value after the slash is a regular expression for matching backup names.
#
# Periods
#
# The period is a sequence of time measurements, with the amount given
# first, followed by a single letter indicating the unit. The format for periods
# is similar to that of ISO-8601 recurring durations.
#
# Allowed time units and their corresponding values are:
# y = years (365 days + 6 hours)
# M = months (30 days + 10 hours + 30 minutes)
# w = weeks (7 days)
# d = days (24 hours)
# h = hours (60 minutes)
# m = minutes (60 seconds)
#
# # With the exception of months (M) and minutes (m), the unit indicators are not
# case-sensitive.
#
# The precision of all time values is to the second. Only the time units actually
# used are required, and the values are not limited by their maximum size in
# typical usage. However, all time values must be integers. 
#
#
# Rule types
#
# Direct intervals ('D'), which can also be thought of as 'Date' intervals, will
# match the expression given against the backup file name, and preserve up to
# the given number of those that match. A value of 0 means all matches are
# preserved. 
# Backup file names use ISO-8601 date format, although the colon between hour 
# and minute may be replaced if the 'COLON_REPLACEMENT' option is set in the 
# config file. Although generally intended to match a particular date or time, 
# other valid regular expression can be used, including any part of the file 
# name. However, the '/' character is not allowed in the expression.
#
# Example Direct intervals:
#  An example backup name is /backup/dir/2020-10-31T05h30-05h00
# "D3/202.-"   - keep the 3 most recent backups in the 202x decade
# "D0/-0[123]T" - keep all backups made on the first 3 days of any month
# "D1/-05-" - keep at least one backup made in the 5th month (May)
# "D5/T16"  - keep up to 5 backups made in the 4 p.m. hour 
#
#
# Keep intervals ('K') will preserve at most the given number of backups, and 
# will not preserve any backups older than the time period P. The most recent 
# backups are given priority. A value of 0 indicates that all backups in the 
# period will be preserved.
#
# Example Keep intervals:
#  "K10/P10d" - keep no more than 10 backups for the last 10 days
#  "K0/24h" - keep all backups made in the last 24 hours
#  "K100/P3Y" - keep the 100 most recent backups, but none older than 3 years
#
#
# Recurring intervals ('R') will attempt to preserve one backup per time period P,
# going as far back as R periods. The oldest backups are given priority.
# Since BUNS does not control when the backups actually occur, a given interval
# may or may not have a backup within it that matches this rule. Recurring 
# intervals attempt to keep the gap between them shorter by using an 'extension'
# when needed.
# The extension works in this way: Backups are marked starting from the oldest
# interval (P*n, where n is the number given for the rule) and working forward.
# If no backups are found that are older than half of a particular time
# interval, that interval will be extended. The extension is set by the time of 
# the backup that was most recently marked in an older interval, plus half a 
# period. This should keep the actual gap between backups to not much more than 
# 1.5 periods, assuming the backup schedule is smaller than the recurrence period,
# and backups are generally regular.
# This extension will not affect the measurement of time for other intervals or rules. 
#
# Some example Recurring intervals:
#  "R4/2w" - every two weeks, limit of four backups (8 weeks back)
#  "R20/P2d9h30m" - every 2 days, 9 and a half hours, limit of 20 ( ~48 days back)
#  "R6/120m" - every 120 minutes, limit of 6 ( 12 hours back )
#
# Any number of rules can be combined; all rules are applied before culling 
# occurs. The rules also only indicate which backups are preserved; backups are 
# culled when no rule has marked them as preserved. This means that multiple Keep
# rules are likely to be redundant, although possibly useful in situations 
# where the actual backup interval varies.
#
# Rules do not guarantee that backups will exist, since they may not match
# the backup schedule. Also, the actual time between saved backups for a 
# Recurring interval may not match the period P (see above explanation of
# extension for this rule type).
# 
#
# Variations in completion time
#
# The time used for culling is local time on the archival machine. The time 
# that a backup is considered to have occurred is taken from the filename used
# for the backup. Since backups are typically timestamped by the machine being 
# backed up, there could be a discrepancy in the completion time and the 
# culling time based on the machine clocks. If a backup is marked with a future 
# time (relative to the culling time), it will automatically be preserved and 
# not count toward any interval keep counts.
# The configuration setting FUTURE_LEEWAY determines how far into the future
# relative to culling time the backup can be marked.  A warning will
# be logged if the time exceeds this. If the ABORT_ON_FUTURE setting is true, 
# the cull will be terminated when values that exceed the future leeway are
# detected, and an error reported. In either case, the backup is preserved.
#


# First argument is the source directory, and required
if [[ $# == 0 ]]; then
	printf "Source directory not provided.\n" >&2
	exit 1
fi

backup_snapshot_dir=$1
[[ -d $backup_snapshot_dir ]] || { printf "Not a directory: %s\n" $backup_snapshot_dir>&2; exit 1; }
shift 

# Get the rules (all remaining arguments, as strings)
declare -a interval_rules
for rul in "$@"; do
	interval_rules+=("$rul")
done 

abort_cull=false

# Convert formatted period to a value in seconds
function parse_repeat_period {
    local sec=0
    local fval=0
	local str=$1
	local c=""
	for (( i=0; i < ${#str}; i++ )); do
		c=${str:$i:1}
		case $c in
			0|1|2|3|4|5|6|7|8|9)
				fval=$(( c + 10*fval ))
				;;
		 	Y|y)
				sec=$(( sec + fval*365*24*60*60 + 6*60*60 ))
				fval=0
				;;
			M)
				sec=$(( sec + fval*30*24*60*60 + 10*60*60 + 30*60 ))
				fval=0
				;;
			W|w)
				sec=$(( sec + fval*7*24*60*60 ))
				fval=0
				;;
			D|d)
				sec=$(( sec + fval*24*60*60 ))
				fval=0
				;;
			H|h)
				sec=$(( sec + fval*60*60 ))
				fval=0
				;;
			m)
				sec=$(( sec + fval*60 ))
				fval=0
				;;
			P|p)
				: 
				# Should only allow at start of field, this ignores any 'p'.
				;;
			*)
				# invalid character
				exit 1
				;;
		esac
	done
	echo "$sec"
}

# Convert a file name in ISO-8601 format (with possible ':' replacement)
# to seconds since epoch (using date).
# Returns a non-zero value if conversion fails.
function fname_to_seconds {
	local fname=$(echo "$1" | tr ${COLON_REPLACEMENT:-h} :)
	local secs=$(date -d "$fname" +%s)
	if [[ $? -eq 0 ]]; then
		echo "$secs"
		return 0
	else
		return $?
	fi
}	

# Get the current time as a datum (using epoch time)
sec_start=$(date +%s)
# Do not warn if future times are within some window (default 24 hours))
max_future=$(( sec_start + ${FUTURE_LEEWAY:-86400} ))

# Scan the backup directory for valid backups, index them by time
declare -a bsnaps
declare -a bsnapskeep

for fn in "$backup_snapshot_dir"/*; do
	fname=$(basename $fn)
	[ -e $fn ] || continue
	[ -d $fn ] || continue
	total_secs=$(fname_to_seconds $fname)
	if [[ $? -eq 0 ]]; then
		elapsed=$(( sec_start - total_secs ))
		if [[ $elapsed -lt 0 ]]; then
			if [[ $total_secs -gt $max_future ]]; then
				if [[ "$ABORT_ON_FUTURE" == true ]]; then
					printf "ERROR: Backup time too far in future, will abort. (time: %s)\n" $fname >&2
					abort_cull=true
					break
				else
				 	printf "Warning: Backup time is in future: %s\n" $fname >&2 
				fi
			fi	
			bsnapskeep+=("$fn")
			continue
		else
			bsnaps[$elapsed]="$fn"
		fi
	fi
done

# Find the oldest value in bsnaps (that is not greater than the max time argument)
function get_oldest_snapshot {
	local maxtime=$1
	local best_indx=-1
	for indx in ${!bsnaps[*]}; do
		[[ $indx -le $maxtime ]] || break
		best_indx=$indx
	done
	echo "$best_indx"
}


# Apply the rules to build list of items to preserve
rule_type_regex="^([dDkKrR])([0-9]+)$"
for irule in ${interval_rules[*]}; do
	echo "Applying rule: ${irule}" >>$LOG_FILE
	itype=""
	inum=-1
	# Split the rule into type & period (split by '/')
	IFS=/ read iarg1 iarg2 <<< "$irule"
    if [[ $iarg1 =~ $rule_type_regex ]]; then
		itype="${BASH_REMATCH[1]}"
		inum="${BASH_REMATCH[2]}"
		case $itype in
			D | d)
				# Keep up to inum backups that match the expression
				# Most recent backups preserved first
				# If inum = 0, keep all matches
				found_count=0
				match_exp=$iarg2
				for snapname in ${bsnaps[*]}; do
					[ $inum -ne 0 ] && [ $found_count -ge $inum ] && break
					if [[ $snapname =~ $match_exp ]]; then
						bsnapskeep+=($snapname)
						(( found_count++ ))
					fi
				done
				;;
			K | k)
				# Just keep up to inum backups, but stop if past the period
				# If inum = 0, keep all in the period
				iperiod=$( parse_repeat_period $iarg2 )
				if [[ $? -ne 0 ]]; then
						printf "Malformed rule period : $iarg2\n" >&2
						abort_cull=true
						break
				fi 
				indx_count=0
				for indx in ${!bsnaps[*]}; do
						((indx_count++))
					[ $inum -ne 0 ] && [ $indx_count -gt $inum ] && break
					[ $indx -gt $iperiod ] && break
					bsnapskeep+=(${bsnaps[$indx]})	
				done
				;;
			R | r)
				# Repeatedly find the oldest backup in a period, then
				# advance the period forward in time (expand the period
				# and retry once if no backup found later than half of it)
				iperiod=$( parse_repeat_period $iarg2 )
				if [[ $? -ne 0 ]]; then
						printf "Malformed rule period : $iarg2\n" >&2
						abort_cull=true
						break
				fi 	
				oldest_prev=-1
				while [[ $inum -gt 0 ]]; do
					mintime=$(( iperiod * (inum - 1) ))
					maxtime=$(( iperiod * inum ))
					halftime=$(( mintime + iperiod/2 ))
					best_indx=$(get_oldest_snapshot $maxtime)
					if [[ $best_indx -ge $halftime ]]; then
						bsnapskeep+=(${bsnaps[$best_indx]})
						oldest_prev=$best_indx
				    else
						# No backup found in latter half of period, expand max.
						# At this point we search the whole period.	
						if [[ $oldest_prev -ge 0 ]]; then
							maxtime=$(( oldest_prev - iperiod/2 ))
							best_indx=$(get_oldest_snapshot $maxtime)
						fi
						if [[ $best_indx -ge $mintime ]]; then
							bsnapskeep+=(${bsnaps[$best_indx]})
							oldest_prev=$best_indx
						fi
					fi
					((inum--))
				done
				;;
			*)
				printf "Error parsing rule:%s\n" $itype >&2
				;;
		esac
	else
		printf "Invalid rule:%s\n" $iarg1 >&2 
		abort_cull=true
	fi
done

if [[ "$abort_cull" = true ]]; then
		printf "Aborting cull due to one or more errors." >&2
		exit 2
fi

# Print out preserved files (Used for debugging when run standalone)
echo "Array items to keep:"
for snap in ${bsnapskeep[*]}; do
	printf $snap
	printf " ok\n"
done

# Tells whether an array has the given value in it
function contains {
	local -a ra=( "${!1}" )
	local m=$2
	for item in ${ra[*]}; do
		if [[ "$item" == "$m" ]]; then
			return 0
		fi
	done
	return 1
}

# Retrieves the prefix for btrfs mounts (to re-create full path)
function get_mount_prefix {
	local full_path=$(realpath $1)
	while read mntpt; do
		rxm="^${mntpt}"
		if [[ "$full_path" =~ $rxm ]]; then
			echo "${mntpt%/*}"
			return 0
		fi
	done < <(findmnt -nt btrfs | cut -d " " -f1)
	return 1 # Not found
}

delete_method=${SNAPSHOT_METHOD:-copy}

# Get a list of snapshots if using snapshot deletion
case $delete_method in
	btrfs | BTRFS )
		declare -a btrfs_snapshots
		mnt_prefix=$(get_mount_prefix "$backup_snapshot_dir")
		btrfs_paths=( $(btrfs subvol list -o "$backup_snapshot_dir" | grep -Po 'path\s\K.*' | cut -d " " -f1 ) )
		for path in ${btrfs_paths[*]}; do
	   		# Store with only backup dir + remaining path 
			# note: Btrfs 'path filter' may include subvols on other paths
			rp="${mnt_prefix}/${path}"  # Add the mount point to the front
			btrfs_snapshots+=(${rp/*${backup_snapshot_dir}/${backup_snapshot_dir}})
		done
		;;
	cp | copy | COPY)
		;; 

	*)
		echo "Snapshot Method not recognized - deleting as files." >&2
		;;
esac

# Cull all backups not marked for preservation
for fn in "$backup_snapshot_dir"/*; do
	[ -e $fn ] || continue
	[ -d $fn ] || continue
	$(contains bsnapskeep[@] "$fn") && continue
	case $delete_method in
		btrfs | BTRFS )
			if $(contains btrfs_snapshots[@] "$fn"); then
				btrfs subvol delete $(realpath "$fn") >>$LOG_FILE
			fi
			;;
		*)
			# Delete as file
			echo "Deleting $fn" >>$LOG_FILE
			rm -r "$fn" >>$LOG_FILE
			;;
	esac
done


