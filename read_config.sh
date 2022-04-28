#! /bin/bash

# This reads the config file for BUNS snapshots & culling.
#
# The config file format consists of a listing of global settings and
# rulesets. 
#
# The global settings are variable name & value pairs, of the form:
# variable = value
# Each variable assignment must be on its own line. Leading and trailing
# whitespace is trimmed on both variable names and values.
#
# A ruleset consists of one or more paths, which are enclosed in [] brackets.
# Each path must be on its own line, and the [ symbol must begin the line.
# The paths are then followed by rules, which are separated by whitespace.
# A ruleset is terminated by either the end of the file or the start of a new
# ruleset using the [ symbol at the beginning of the line. When multiple
# paths are listed together, the rules that follow apply to each of the
# paths in that ruleset.

# No global settings may be placed after the rulesets.
#
# The # is used for comments; everything is ignored on the line past the #
# A ; can also be used to comment out a line, but must be the first character
# on that line.

# If an argument is provided, it will be used as the config file. If not, the
# file 'buns.conf' will be used as a default.
# 
# This file can take the option '-g' which will ignore rulesets and only 
# incorporate the global settings.

globals_only=false
if [[ $1 == "-g" ]]; then
	globals_only=true
	config="$2"
else
	config="$1"
fi

config_file_name=${config:-"buns.conf"}

# Trim whitespace around the input
# [From SO 369758, original source missing]
function trim {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   
    echo $var 
}

declare -A RULESETS
declare -a cur_paths
cur_token=""
rules=""
field=""
mode="globals"
linecount=0
error=""

# Add the ruleset to our list when it is complete
function close_out_ruleset {
	for cp in ${cur_paths[@]}; do
		RULESETS+=(["$cp"]="$rules")
	done
	rules=""
	cur_paths=()
}

# Parse the config file
while read line; do
	(( linecount++ ))	
	# ; at start of line is comment
	if [[ ${line::1} == ";" ]]; then
		continue
	fi
	c=""
	field=""
	for (( i=0; i < ${#line}; i++ )); do
		c=${line:$i:1}
		case $c in
			\#)
				# Comment statement
				break
				;;
			\[)
				# Start rule path
				if [[ $i == 0 ]]; then
					if [[ "$globals_only" == true ]]; then
						break 2 # No error, just skip past
					fi
					if [[ $mode == "rule" ]]; then
						close_out_ruleset
					fi
					mode="path"
				else
					error=" Unexpected '[' symbol."
					break 2	
				fi
				;;
			\])
				# End path for rule
				if [[ $mode == "path" ]]; then
					cur_paths+=( $(trim $field) )
					mode="path_or_rules"
				else
					error="Unexpected ']' symbol."
					break 2
				fi
				;;
			\=)
				# Assign a variable
				if [[ $mode == "globals" ]]; then
					if [[ $field == "" ]]; then
						error="Empty variable identifier."
						break 2
					else
						cur_token=$(trim $field)
						field=""
						mode="assign"
					fi
				else
					error="Invalid assignment."
					break 2
				fi
				;;
			*)
				if [[ $mode == "path_or_rules" ]]; then
						mode="rule"
				fi
				field+="$c"
				;;
		esac
	done
	# Line is ended
	field=$( trim "$field" )
	case $mode in
		"globals")
			if [[ $field != "" ]]; then
				error= "Invalid expression."
				break
			fi
			;;
		"assign")
			printf -v "$cur_token" "%s" "$field"
			export "$cur_token"
			cur_token=""
			field=""
			mode="globals"
			;;
		"path")
			error="Path not terminated (missing ']')."
			break
			;;
		"path_or_rules")
			:
			;;
		"rule")
			rules+="$field "
			;;
		*)
			error="Unknown parsing state. Unable to continue."
			break
			;;
	esac
done <"$config_file_name"

# Finalize last ruleset at end of file, if necessary
case $mode in 
		"rule" | "path_or_rules")
				close_out_ruleset
				;;
		*)
				:
				;;
esac

# Report an error
if [[ $error != "" ]]; then
		printf "Configuration Error at line %d. %s\n" $linecount "$error" >&2
	exit 1
fi

# Set ruleset
if [[ "$globals_only" != true ]]; then
		export RULESETS
fi

# Show settings
export -p 
