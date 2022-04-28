#! /bin/bash

# Tests for buns culling. Will create directories and rulesets to
# check proper operation of buns/cull.sh

# This will run the tests in the current directory. See settings below to
# use alternate sources. If using BTRFS snapshots, ensure that a reference
# (dummy) subvolume is available. Also see notes below on reference_subvolume.

# 'External' config options. These represent settings that would normally be
# set in the config file. 
# For some values, this  can serve as a means of testing that script defaults
# are set, by commenting out these variables as desired.

export COLON_REPLACEMENT="h"
export SNAPSHOT_METHOD="btrfs"  # Ensure ref subvolume is available if btrfs
export FUTURE_LEEWAY=86400
export LOG_FILE=/dev/null

# Set to /dev/null to suppress btrfs creation/deletion messages, &1 otherwise
btrfs_output=/dev/null

# Used to remove all btrfs subvolumes for a given (relative) path. This will not
# work for absolute paths, since btrfs's subvolume list removes the mount point.
# (See cull.sh for one method to get a full path when needed).
function recursive_remove_snapshots {
	local removal_path=$1
	# Do not use btrfs path filter (its logic is convoluted)
	# Here we get all subvolumes that btrfs lists, find the column labeled path
	# and get whatever follows it, and then filter for our own relative path.
	# The sort allows us to delete in recursive order.
	local -a subvol_paths=( $(btrfs subvol list "$removal_path" | grep -Po 'path\s\K.*' | cut -f1 | grep "$removal_path" | sort -r ) )
	for bp in ${subvol_paths[*]}; do
		path="${bp/*${removal_path}/${removal_path}}"
		[ -e $path ] || continue
		btrfs subvol delete "$path" >$btrfs_output
	done
}

echo "Starting cull tests for BUNS in this directory."

# Create the base test dir if necessary
mkdir culltests

case $SNAPSHOT_METHOD in
	btrfs | BTRFS )
		use_btrfs_snapshots=true
		recursive_remove_snapshots culltests
		;&
	* )
		rm -rf ./culltests/*
		;;
esac

if [[ "$1" == "clean" ]]; then
	rm -rf ./culltests
	echo "Finished deleting test directories."
	exit 0
fi

# If using btrfs snapshots, define where the reference subvolume is.
# Ref subvolume must also have a file in it (if empty, snapshot creation
# will append the source name and cause the tests to fail).
# This path should be relative to the current directory (or potentially 
# referenced to the top-level subvolume of the current directory).
reference_subvolume=./test_subvolume

# Variables used for testing (global)
test_script=./cull.sh # location where the culling script is
declare -a duts
testdir=./culltests

declare -a dreq  # Indicates files that must exist
declare -a ddel  # Indicates files that must be deleted

tests_passed=0   # Running count of passed tests
tests_failed=0   # Running count of failed tests

function check_test_result {
	local script_result=$?
	if [[ "$1" = "must_fail" ]]; then
		if [ "$script_result" -eq 0 ]; then
			echo "Test failed: error expected when culling."
			(( tests_failed++ ))
			return 1
		fi
	else
		if [ "$script_result" -ne 0 ]; then
			echo "Test failed: no error expected when culling."
			(( tests_failed++ ))
			return 1
		fi
	fi
	for fn in ${dreq[*]}; do
		if [ -e "$testdir"/$fn ]; then
			continue
		else
			echo "Test failed: $fn not present"
			(( tests_failed++ ))
			return 1
		fi
	done
	for fn in ${ddel[*]}; do
		if [ -e "$testdir"/$fn ]; then
			echo "Test failed: $fn present"
			(( tests_failed++ ))
			return 1
		else
			continue
		fi
	done
	echo "Test passed."
	(( tests_passed++ ))
	return 0
}

function make_test_dir_from {
	local tdname=$2
	local -n snaps=$1
	[ -d ./culltests/$tdname ] || mkdir culltests/$tdname
	if [[ "$use_btrfs_snapshots" == true ]]; then
		recursive_remove_snapshots culltests/$tdname
	fi
	rm -rf culltests/$tdname/*
	testdir=culltests/$tdname
	for snapname in ${snaps[*]}; do
		case $SNAPSHOT_METHOD in
			btrfs | BTRFS )
				btrfs subvol snapshot -r "$reference_subvolume" $testdir/"$snapname" >$btrfs_output
				;;
			*)
				mkdir $testdir/"$snapname"
				;;
		esac
		duts+=("$snapname")
	done
}

function make_standard_test_dir {
	local -a std_days
	for (( i=0; i < 10; i++ )); do
		dirname=$( date --iso-8601=minutes --date "$i days ago" | tr : h)
	       std_days+=("$dirname")
       done
       make_test_dir_from 'std_days' 'stdtest'
}

# Test: No directory given
duts=()
make_standard_test_dir
dreq=( "${duts[@]}" )
ddel=()
$test_script
check_test_result "must_fail"

# Test: Invalid directory argument
duts=()
make_standard_test_dir
dreq=( "${duts[@]}" )
ddel=()
$test_script "K5/10d"
check_test_result "must_fail"

# Test: No rules
duts=()
make_standard_test_dir
dreq=() # None remain
ddel=( "${duts[@]}" )  # All removed
$test_script $testdir ""
check_test_result

# Test: Invalid Rule (period)
duts=()
make_standard_test_dir
dreq=( "${duts[@]}" ) # None removed
ddel=()   
$test_script $testdir "K0/10fruitloops"
check_test_result "must_fail"

# Test: Invalid Rule (type)
duts=()
make_standard_test_dir
dreq=( "${duts[@]}" ) # None removed
ddel=()
$test_script $testdir "P1/R100h"
check_test_result "must_fail"

# Test: 1 Rule - Keep 1, 10 days
duts=()
make_standard_test_dir
dreq=( "${duts[0]}" )
ddel=( "${duts[@]:1}" )
$test_script $testdir "K1/P10d"
check_test_result

# Test: 1 Rule - Keep 8, 30 days
duts=()
make_standard_test_dir
dreq=( "${duts[@]:0:8}" )
ddel=( "${duts[@]:8}" )
$test_script $testdir "K8/P30d"
check_test_result

# Test: 2 Rules - larger number overrides ( K3/30  K5/30 )
duts=()
make_standard_test_dir
dreq=( "${duts[@]:0:5}" )
ddel=( "${duts[@]:5}" )
$test_script $testdir "K3/30d K5/p30d"
check_test_result

# Test: 1 Rule, cut off by date 
duts=()
make_standard_test_dir
dreq=( "${duts[@]:0:5}" )
ddel=( "${duts[@]:5}" )
$test_script $testdir "K10/4d23h"
check_test_result

# Test: 'Future' times are preserved
duts=()
make_standard_test_dir
# Add a future entry to stdtest dir
fdate=$( date --iso-8601="minutes" --date="+12 hours" | tr : h )
mkdir "$testdir/$fdate"
ddel=( "${duts[@]:1}" )
dreq=( "$fdate" "${duts[0]}" )
$test_script $testdir "K1/23h"
check_test_result

# Test: Keep 0 indicates keep all in period
duts=()
make_standard_test_dir
dreq=( "${duts[@]:0:7}" )
ddel=( "${duts[@]:7}" )
$test_script $testdir "K0/6d23h"
check_test_result

# Sample dates to use for 'D' tests
dates=( 2020-03-01T01h40 2020-03-01T15h37 2020-04-02T12h40 2020-05-01T01h00 2021-06-23T14h40 2021-03-15T09h55 )

echo "Testing dates"

# Test: Direct will match against a date 
duts=()
make_test_dir_from 'dates' 'datedir'
dreq=( "${duts[@]:0:2}" )
ddel=( "${duts[@]:2}" )
$test_script $testdir "D0/2020-03-01"
check_test_result

# Test: Direct will match against time
duts=()
make_test_dir_from 'dates' 'datedir'
dreq=( "${duts[0]}" "${duts[3]}" )
ddel=( "${duts[@]:1:2}" "${duts[@]:4}" )
$test_script $testdir "D0/T01h"
check_test_result

# Test: Direct limits matches found, keeps newest
duts=()
make_test_dir_from 'dates' 'datedir'
dreq=( "${duts[@]:2:2}" )
ddel=( "${duts[@]:0:2}" "${duts[@]:4}" )
$test_script $testdir "D2/2020-"
check_test_result

# Test: Direct will handle regex properly
duts=()
make_test_dir_from 'dates' 'datedir'
dreq=( "${duts[@]:0:2}" "${duts[5]}" )
ddel=( "${duts[@]:2:3}" )
$test_script $testdir "D0/20..-03"
check_test_result

# Test : Direct handles regex with group
duts=()
make_test_dir_from 'dates' 'datedir'
dreq=( "${duts[@]:2:2}" )
ddel=( "${duts[@]:0:2}" "${duts[@]:4}" )
$test_script $testdir "D0/2020-0[456]"
check_test_result

# Test: Recurring with 0 periods keeps none
duts=()
make_standard_test_dir
dreq=()
ddel=( "${duts[@]}" )
$test_script $testdir "R0/5d"
check_test_result

# Test: Recurring with invalid period is error
duts=()
make_standard_test_dir
dreq=( "${duts[@]}" )
ddel=()
$test_script $testdir "R1/P80horses"
check_test_result "must_fail"

# Test: Recurring with 1 cycle over all backups
duts=()
make_standard_test_dir
dreq=( "${duts[9]}" )
ddel=( "${duts[@]:0:9}" )
$test_script $testdir "R1/30d"
check_test_result

# Test: Recurring with multiple cycles, short period
duts=()
make_standard_test_dir
dreq=( "${duts[@]}" )
ddel=()
$test_script $testdir "R10/23h"
check_test_result

# Test: Recurring culls older than last period
duts=()
make_standard_test_dir
dreq=( "${duts[7]}" )
ddel=( "${duts[@]:0:7}" "${duts[8]}" "${duts[9]}" )
$test_script $testdir "R1/7d1h"
check_test_result 

# Test: Recurring with 2 cycles
duts=()
make_standard_test_dir
dreq=( "${duts[4]}" "${duts[9]}" )
ddel=( "${duts[0]}"  "${duts[1]}"  "${duts[2]}"  "${duts[3]}"  "${duts[5]}"  "${duts[6]}"  "${duts[7]}"  "${duts[8]}" ) 
$test_script $testdir "R2/5d"
check_test_result

# Test: Recurring with multiple rules (R3/1d, R2/4d)
duts=()
make_standard_test_dir
dreq=( "${duts[@]:0:3}" "${duts[7]}" )
ddel=( "${duts[@]:4:3}" "${duts[@]:8}" )
$test_script $testdir "R3/1d R2/4d"
check_test_result

# Test: Recurring period extension when none found
duts=()
make_standard_test_dir
odate=$( date --iso-8601="minutes" --date="-11 days 70 minutes" | tr : h )
mkdir "$testdir/$odate"
dreq=( "${duts[@]}" $odate )
ddel=()
$test_script $testdir "R11/1d"
check_test_result

# Test: Mixed Keep/Recurring periods
duts=()
make_standard_test_dir
dreq=( "${duts[@]:0:2}" "${duts[3]}" "${duts[7]}" "${duts[9]}" )
ddel=( "${duts[2]}" "${duts[@]:4:3}" "${duts[8]}" )
$test_script $testdir "K2/3d R3/3d23h"
check_test_result

echo "$tests_passed tests passed."
echo "$tests_failed tests failed."

if [[ $tests_failed = 0 ]]; then
	echo "All tests passed, cleaning test files."
	if [[ "$use_btrfs_snapshots" == true ]]; then
		recursive_remove_snapshots culltests
	fi
	rm -rf ./culltests
fi

	
