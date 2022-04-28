#! /bin/bash

# This file sets up the directories, scripts, and tasks needed for BUNS backups.
# It should be run if the paths for any of the Rulesets, the monitor
# directory name, the base script directory, or the config file location 
# itself has changed. It must be run from the same directory that contains
# the read_config script unless the -r option is used. It also requires the
# presence of the user script template directory ('user').
# It does not need to be run if only the rules in the Rulesets change.
#
# The -c option indicates the config file to use. If it is not present, the
# default file '/etc/buns/conf' is used, unless the -i (install) option is used.
# When the install option is used, the -c indicates which config file to install
# to the default location.
#
# The -i option (install) will copy the config file to the default location
# '/etc/buns.conf', and install BUNS scripts from the local directory to the 
# SCRIPT_DIR indicated by the config file. If a config file is not indicated
# by the -c option, the local file 'buns.conf' is used.
#
# The -u option (user) will determine where the user scripts (those that run the 
# actual backup called by the remote machine) are installed. It will also set
# the selected user as the owner of the backup monitor files.
#
# The -d option (directory) indicates the directory to install the user scripts to.
# This option overrides -u as the destination for user scripts.  

# If neither -u nor -d is specified, and the BACKUP_USER is not set in the config
# file, the user scripts will be installed to the current directory.
#
# 
# Note that running this script will clear the log file. 
# 

config_filename="buns.conf"
default_config="/etc/${config_filename}"

function exit_bad_argument {
	cat >&2 <<EOF
Usage: $0 [-i] [-c CONFIG FILE ] [-d USER_DIR] [-u USER] [-r READ_CONFIG SCRIPT ] 
  Default config $default_config is used if not specified (unless using -i).
  The -i option will install the config file to $default_config, and also install
    BUNS scripts to the directory indicated in the config file. (User scripts are
    always installed.)
  The -d option will install user scripts to the directory provided, overriding
    the config file USER_SCRIPT_DIR setting.
  The -u option will set the indicated user to handle backup scripts, overriding
    the config file BACKUP_USER setting.  
  The -r option indicates the location of the script to read the config file.
  When not specified, the current directory is used as the default location.
EOF
	exit 1
}

# Given a variable name, will produce an output line setting that variable
function resolve_line {
	local lv=$1
	line_output="${lv}="
	if [[ -z "${!lv}" ]]; then
		return 1
	fi
	local indx=0
	local contents=""
	local lv_ra="${lv}[@]"
	for rv in "${!lv_ra}"; do
		contents+="\"${rv}\" "
		indx+=1
	done
	if [[ $indx -gt 1 ]]; then
		line_output+="(${contents})"
	else
		line_output+="${contents}"
	fi
	return 0
}

# Test if a BTRFS subvolume already exists
function isBTRFSsub { 
	btrfs subvolume show "$1"  &>/dev/null &&  return 0  
	return 1 
}

# Set defaults
install_enabled=false
uscript_dir="."
script_dir="."
user_provided=false
user_dir_provided=false
config_script="read_config.sh"
config_file="$default_config"

while getopts "ic:d:u:r:" options; do
	case "$options" in
		i)
			install_enabled=true
			;;
		c)
			config_file="$OPTARG"
			;;
		d)
			uscript_dir="$OPTARG"
			user_dir_provided=true
			;;
		u)
			script_user="$OPTARG"
			user_provided=true
			;;
		r)
			config_script="$OPTARG"
			;;
		:) 
			printf "Error: -%s requires an argument.\n" "$OPTARG" >&2
			exit_bad_argument
			;;
		*)
			exit_bad_argument
			;;
	esac
done

config_error_msg="ERROR: Could not install config file to ${default_config}."
if [[ "$install_enabled" = true ]]; then
	if [[ "$config_file" = "$default_config" ]]; then
	       config_source="$config_filename" # Use local
	else
		config_source="$config_file"    # Use command-specified
	fi
	cp "$config_source" $default_config 
       	[[ $? = 0 ]] || { echo $config_error_msg >&2; exit 1; }
	chown $(/usr/bin/id -run) $default_config 
	[[ $? = 0 ]] || { echo $config_error_msg >&2; exit 1; }
	config_file="$default_config" # Use the installed one for remainder
fi	

# Load the config file now
[[ -e $config_script ]] || { echo "ERROR: Script to read config file not present." >&2; exit 1; }

source $config_script "$config_file"

# Reset the log file
cat >"$LOG_FILE" <<EOF
BUNS log file 
Setup initialized on $(date)
EOF

install_error_msg="ERROR: Could not install files to $SCRIPT_DIR."
# Copy BUNS scripts to script root (if install option enabled)
iscripts=("cull.sh" "file_response.sh" "snapshot.sh" "setup.sh")

if [[ "$install_enabled" = true ]]; then
	echo "Create directory ${SCRIPT_DIR}" >> "$LOG_FILE" 
	mkdir -p $SCRIPT_DIR 
	[[ $? = 0 ]] || { echo $install_error_msg >&2; exit 1; }
fi

if ! [[ -d $SCRIPT_DIR ]]; then
	printf "ERROR: Script install directory not found: %s.\n" "$SCRIPT_DIR" >&2
	exit_bad_argument
fi

if [[ "$install_enabled" = true ]]; then
	echo "Installing scripts to $SCRIPT_DIR" >> "$LOG_FILE"
	for bscript in ${iscripts[@]}; do
		[[ -e "$bscript" ]] || { echo "Script missing: $bscript" >&2; exit 1; }
		cp "$bscript" "$SCRIPT_DIR"
		[[ $? = 0 ]] || { echo $install_error_msg >&2; exit 1; }
	done
	cp "$config_script" "$SCRIPT_DIR" 
	[[ $? = 0 ]] || { echo $install_error_msg >&2; exit 1; }
	# Copy templates (user & uninstall)
	cp -r './templates' "$SCRIPT_DIR"
	[[ $? = 0 ]] || { echo $install_error_msg >&2; exit 1; }
fi	

# Create user scripts from templates

if [[ "$user_provided" = false ]]; then
	script_user="$BACKUP_USER"
fi

if [[ "$user_dir_provided" = false ]]; then
	uscript_dir=$(eval echo "~${script_user}/${USER_SCRIPT_DIR}")
fi

if [[ "$install_enabled" = true ]]; then
	echo "Create directory ${uscript_dir}" >> "$LOG_FILE"
	mkdir -p $uscript_dir >&2
	[[ $? = 0 ]] || { echo "ERROR: Could not create user script directory.">&2; exit 1; }
fi

if ! [[ -d $uscript_dir ]]; then
	printf "ERROR: User script directory not found: %s.\n" "$uscript_dir" >&2
	exit_bad_argument
fi


echo "Writing user scripts to ${uscript_dir}" >>"$LOG_FILE"

user_script_source="${SCRIPT_DIR}/templates/user"
user_script_error="ERROR: Could not install user scripts to ${uscript_dir}."
declare -a USER_SCRIPTS # Track installed user scripts (for uninstall)

for uscript in $user_script_source/*.template; do
	[[ -e "$uscript" ]] || continue
	config_mode=false
	ch_result=0
	output_basename=$(basename "$uscript")
	output_filename=${output_basename%%.template}
	output_file="${uscript_dir}/${output_filename}.sh"
	while IFS=$'\n' read line; do
		if [[ "$config_mode" = true ]]; then
			if [[ $line =~ ^#DONE ]]; then
				config_mode=false
				continue
			else
				resolve_line $line
				if [[ $? = 1  ]]; then
					echo $user_script_error >&2
					printf "Required config variable %s in  %s is null.\n" "$line" "$uscript"  >&2
					exit 1
				else
					# Add variable value after its name
					echo $line_output 
				fi
			fi
		else
			if [[ $line =~ ^#CONFIG ]]; then
				config_mode=true
				continue
			else
				# Just copy the line
				printf '%s\n' "$line"
			fi
		fi
	done <"$uscript" >"$output_file"
	
	# Change permissions/ownership for user script files
	chmod ug+x "$output_file"
	ch_result=$(($ch_result && $?))
	chmod go-w "$output_file"
	ch_result=$(($ch_result && $?))
	chmod o-x  "$output_file"
	ch_result=$(($ch_result && $?))
	if ! [[ -z $script_user ]]; then
		 chown "$script_user":"$BACKUP_GROUP" "$output_file"
		 ch_result=$(($ch_result && $?))
		 USER_SCRIPTS+=("$output_file")
   	else
		 chown :"$BACKUP_GROUP" "$output_file"
		 ch_result=$(($ch_result && $?))
	fi	 
	[[ $ch_result -eq 0 ]] || { echo $user_script_error >&2; exit 1; }
done

# Create start-up cleanup script
cleanup_script="${SCRIPT_DIR}/cleanup.sh"

cat > $cleanup_script <<EOF
#! /bin/bash

# Automatically generated file for BUNS directory cleanup on startup.
EOF

# Get the current incrontab for temporary editing
temp_incron=/tmp/bunsincron
temp_swap=/tmp/buns_scratch

incrontab -l >"$temp_incron"
incron_edited=false
declare -a INCRON_ENTRIES
declare -a MONITOR_PATHS

# Do all for each path in the Ruleset
for path in "${!RULESETS[@]}"; do
	# Create/edit incron entry
	incron_partial="${path}/${MONITOR_DIR} IN_CLOSE_WRITE ${SCRIPT_DIR}/file_response.sh" # Used for matching when removing entries
	incronline="${incron_partial} \$@ \$# ${config_file}"
	editregex="^${path}/${MONITOR_DIR}\s"
	while read line; do
		if [[ "$line" =~ $editregex ]]; then
		       line="$incronline"
		       incron_edited=true
		 fi
		echo "$line"
	done <"$temp_incron" >"$temp_swap"
	if [[ "$incron_edited" == false ]]; then
		echo "$incronline" >>"$temp_swap"
	fi
	INCRON_ENTRIES+=("$incron_partial")
	mv "$temp_swap" "$temp_incron"
	incron_edited=false
	editregex=""
	# Create directories if necessary
	# Make Monitor & Status directory accessible to group
	mod="${path}/${MONITOR_DIR}"
	echo "Create directory ${mod}" >>"$LOG_FILE"
	mkdir -p "${mod}" >>"$LOG_FILE" 
	chown :"$BACKUP_GROUP" "$mod" >>"$LOG_FILE" 
	chmod g+w "$mod" >>"$LOG_FILE" 
        bud="${path}/${BACKUP_DIR}"	
	case "$SNAPSHOT_METHOD" in
		btrfs | BTRFS )
			echo "Create BTRFS subvolume ${bud}" >>"$LOG_FILE"
			if isBTRFSsub "$bud"; then
				echo "Subvolume exists, skipping creation." >>"$LOG_FILE"
			else
				btrfs subvol create "${bud}" >>"$LOG_FILE" 
			fi
			;;
		cp | COPY | copy )
			echo "Create directory ${bud}" >>"$LOG_FILE"
			mkdir -p "${bud}" >>"$LOG_FILE"
			;;
		*)
	        	printf "Unrecognized snapshot method %s.\n" "$SNAPSHOT_METHOD"
	    		exit 1
			;;	    
        esac
	chown :"$BACKUP_GROUP" "$bud" 
	chmod g+w "$bud"
	# Repository not modifiable by group
	repd="${path}/${BACKUP_REPOSITORY}"	
	echo "Create directory ${repd}" >>"$LOG_FILE"
	mkdir -p "$repd" >>"$LOG_FILE"
	# Add entry to cleanup script
	echo "rm -rf ${path}/${MONITOR_DIR}/*" >>"$cleanup_script"
	MONITOR_PATHS+=("$mod")	
done

# Load modified incron file
incrontab "$temp_incron" >>"$LOG_FILE" 2>&1

# Add the cleanup script to systemd to run at startup
chmod +x $cleanup_script >>"$LOG_FILE" 2>&1
chmod a-w $cleanup_script >>"$LOG_FILE" 2>&1
servicename=buns_cleanup
servicefile=/etc/systemd/system/$servicename.service

echo "Adding systemd service ${servicename} to run at startup" >>"$LOG_FILE"

cat >$servicefile <<EOF
[Unit]
Description=BUNS File cleanup
[Service]
ExecStart=$cleanup_script
[Install]
WantedBy=default.target
EOF

systemctl daemon-reload >>"$LOG_FILE" 2>&1
systemctl enable $servicename >>"$LOG_FILE" 2>&1


# Create uninstall script

uninstaller="${SCRIPT_DIR}/templates/buns_uninstall.template"

config_mode=false
output_basename=$(basename "$uninstaller")
output_filename=${output_basename%%.template}
uninstall_script="${output_filename}.sh"
uninstall_script_error="ERROR: Could not create uninstaller script"

if [[ "$install_enabled" = true ]]; then
	uninstall_script="${SCRIPT_DIR}/${uninstall_script}"
fi	

echo "Creating uninstall script ${uninstall_script}" >> "$LOG_FILE"
CLEANUP_SCRIPT=$cleanup_script
SYSTEM_SERVICE=$servicename
CONFIG_FILE=$config_file
while IFS=$'\n' read line; do
	if [[ "$config_mode" = true ]]; then
		if [[ $line =~ ^#DONE ]]; then
			config_mode=false
			continue
		else
			resolve_line $line
			if [[ $? = 1 ]]; then
				echo $uninstall_script_error >&2
				printf "Required config variable %s in  %s is null.\n" "$line" "$uninstaller"  >&2
				exit 1
			else
				echo $line_output
			fi
		fi
	else
		if [[ $line =~ ^#CONFIG ]]; then
			config_mode=true
			continue
		else
			# Just copy the line
			printf '%s\n' "$line"
		fi
	fi
done <"$uninstaller" >"$uninstall_script"

chmod +x $uninstall_script >> "$LOG_FILE" 2>&1
chmod a-w $uninstall_script >> "$LOG_FILE" 2>&1

echo "Setup complete." >>"$LOG_FILE"
echo "Setup complete. Refer to ${LOG_FILE} for details."
