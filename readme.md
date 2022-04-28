BUNS
=====

BUNS is a set of shell scripts for performing backups from one machine to another, and managing the archive of backups created. BUNS does not control the scheduling of backups; instead the machine that wants to make a backup initiates it on its own time. The idea behind BUNS is to remove old backups in a more controlled manner that stays independent of when or how often they were created. The rules for managing the archive are designed to be flexible and allow for multiple approaches to preservation. 

An additional feature of BUNS is that it does not require the machine performing the backup to have superuser access. The files are stored using rsync's 'fake superuser' to preserve as many file attributes on the original machine as possible, making it possible to use BUNS to back up machines that have different operating systems and user accounts.

BUNS is written for Bash. It relies on rsync for making backups, as well as incrontab and flock for managing the archival process. It is also recommended that BTRFS is used on the archival machine, for making efficient snapshots. 

# How it Works

Backups are made whenever the backup machine decides. It will connect to the archival machine/server using the designated backup user account, and start a backup. Once that backup has successfully completed, the management process will begin. 

First, a snapshot is made of the most recent backup. It is named using the timestamp of the backup (as provided by the backup machine). Next, the archive rules are applied, to determine which backups are preserved and which will be discarded. Once all the rules have been checked, the unneeded backups will be culled. This produces an orderly archive with only the backups that are needed, all named by the time and date when they were created.

# Installation

Copy all the scripts (including the 'templates' directory) to the archival machine. Then set the configuration settings in the file 'buns.conf' as desired. Two values that **must** be configured are the backup user and backup group name. The paths for the archive storage must also be set at this time in the 'ruleset' section at the bottom of the config file. The rules for each path may be configured too, or modified later. 

The configuration file requires the designation of a user account which will handle the backups on the archival machine. This account does not need to be a superuser, and the best choice is to create one that only performs backups. A named backup group must also exist, and the backup user has to be a member of that group.

To create the groups and accounts is fairly simple. Here's an example, using the backup group 'bugs' and the backup user account 'bunny'. These names would be used in the configuration file, with 'bugs' as the `BACKUP_GROUP` and 'bunny' as `BACKUP_USER`. On most machines creating users and groups will need to performed as root.

```
groupadd bugs
useradd -g bugs bunny
```

Once the 'buns.conf' configuration file is complete, run the setup script with the install option (-i). This step as well will likely require superuser (root) privileges.

```
./setup.sh -i 
```

The setup script runs all the needed setup tasks, and copy all the scripts to the `SCRIPT_DIR` as set by buns.conf. Once this has been run, any configuration changes will need to be made to the installed version of the config file (located by default at /etc/buns.conf). Once installed, setup can also be executed from the main script directory, as all files needed to run BUNS on the archival machine will be located there.

Next, copy the 'local_scripts' directory to any machine that will be making backups. The scripts 'bunc.sh' and 'restore.sh' must be configured according to the same settings as in the 'buns.conf' file, with a additional settings for their machine (like SSH key location). The rsync filter file should be modified if necessary for the machine that will be backed up.

For the rsync scripts to work correctly, SSH must be set up on the archival machine to allow login to the backup user account without entering the password. Using ssh-keygen and uploading the keys is a simple process. [Here's a page that shows how to do it](https://www.tecmint.com/ssh-passwordless-login-using-ssh-keygen-in-5-easy-steps/). Note that on the machine that initiates the backup, the script will most likely be run as root if it is a full disk backup, so the ssh keys should be located in the root home directory. 

Once this has been done, it should be possible to run bunc.sh on the machine backing up. The backup will be performed, and the archival machine will manage the backups. The 'bunc.sh' script can be scheduled as desired on the machine doing the backup.

## Uninstalling

When the setup script is run, it creates a custom uninstall script (named 'buns_uninstall.sh') based on the configuration, and places it in the main script directory with the other scripts. Executing the custom uninstall script will remove the system service, incrontab entries, user scripts, and the directories used for managing the archive process. The backups, including both the archive and the most recent backup, will not be removed. Note that the user script directory itself (and the main script directory) is not deleted.

Once the uninstall script has executed, the script directories can be deleted to remove BUNS entirely.  On other machines (the ones initiating backups), simply delete the local scripts. The log file on those machines (as configured in the script file) can also be removed, along with SSH keys if they are no longer required.

# Scripts Included

Main scripts. These are run on the archival machine, and installed to the script directory indicated in the config file. 

* setup.sh - This file is uses the configuration and runs the setup for BUNS, and is run manually. On the first run, the -i (install) option should be used. After that, setup should be run again if the configuration file has been changed. See the script for additional details.

* read_config.sh - This is used to read the config file. Not all scripts use the config file during their operation.

* file_response.sh - This is triggered by incrontab, when new files are added to a directory that has a defined ruleset. It will manage an in-progress backup and set off the archival process. 

* snapshot.sh - Creates a 'snapshot' for the archive once a backup is completed. This snapshot depends on the filesystem and snapshot method configured. For BTRFS it will create normal (subvolume) snapshots.

* cull.sh - Determines which archived backups should be preserved, and will delete those that are considered unneeded.

* test_cull.sh - Can be used to test the culling rules. For development only.

Several files are created using a 'template'. These make use of the config file, but only at setup time. The template is thus filled in with the values from the config file, and a standalone script is generated. 

* buns_uninstall - This will create a script that will remove all elements of BUNS, although the backup repository will remain intact. When setup is run, a customized uninstall script will be placed in the script directory. After this script is executed, only the main script directory will remain, which can be deleted manually.

The 'user' scripts are all created from templates. The user scripts are the ones that the backup user account needs to perform backups.

* init_check - This determines if a backup can be initiated. Once it is run, the backup (using rsync) must begin within 60 seconds.

* rsync_wrapper - This will handle the backup task itself, as well as the necessary steps required for managing the snapshot and archive, and to avoid multiple backups at the same time.

* restore_check - This is used when restoring a file to determine if a backup is in progress, as that may disrupt the file restoration process. The restore check can be bypassed by a setting in the restore script.

Local scripts. These are run on the machine that initiates the backup. Each has its own configuration section at the head of the file.

* bunc.sh - Used to start a backup. By default, the backup will be made of the whole machine (using the root directory), although the filter rules can be used to restrict the actual files copied.

* restore.sh - While it is not required to use this to restore files from a backup, this is a convenience script for restoring a single file or directory, and will take care of the file attributes that are stored using the 'fake superuser' feature of rsync.


# Rulesets

A ruleset is a pairing of a particular directory path with a sequence of preservation rules that are used for backups made using that directory. 

The format of the ruleset is the path first, in square brackets.  The rules are then listed, one line for each, following the path. Multiple paths can be listed together, in which case the rules that follow will be applied to each path separately. Thus if all backups follow the same management schedule, only one ruleset needs to be created.

Here's an example of a ruleset as it would appear in the config file:

```
[ /mnt/backup_disk/backups ]
D4/01T
K20/P30d
R12/2w3d
```

The actual backups will be placed in folders indicated by the configuration (one to contain the latest backup, and one for the archived backups), which are relative to the path in the ruleset. For instance, in this case if the default names are used, the archived backups would all be in /mnt/backup_disk/backups/archive. 

Backup preservation rules have a type, indicated by the first letter in the rule. This is followed by the number of backups associated with the rule, which is followed by a '/'. Each rule appears on its own line (comments are allowed after the rule).

For 'D' rules the value following the slash is a regular expression for matching backup names (by timestamp in ISO-8601 format).

For 'K' and 'R' rules the value after the slash is a time period (optionally with a letter P at the start). The period is a sequence of time measurements, each with a number indicating the amount, followed by a single letter indicating the unit. The format for periods is similar to that of ISO-8601 recurring durations.

Here are the allowed time units and the values used for calculation. With the exception of months (M) and minutes (m), the unit indicators are not case-sensitive.

| Indicator | Unit | Value |
| :-:   | :--  | :--   |
| y | year   | 365 days + 6 hours
| M | month  | 30 days + 10 hours + 30 minutes
| w | week   | 7 days
| d | day    | 24 hours
| h | hour   | 60 minutes
| m | minute | 60 seconds

The precision of all time values is to the second, although the smallest unit allowed is the minute. Values are not limited by their maximum size in typical usage (e.g. '1h4300m' is valid, indicating 1 hour and 4,300 minutes). All time values must be integers. 


## Rule types

The rules are used to determine how backups are preserved, which is also to say how unneeded backups are culled. The rules only indicate which backups are preserved; backups are culled when no rule has marked them as preserved. Any number of rules can be combined, and all rules are applied before culling occurs.

Rules do not guarantee that backups will exist, since they might not match the backup schedule. Also, the actual time between saved backups for a Recurring interval may not match the period P (see the explanation of extension for this rule type).

### Direct 

Direct match rules ('D'), which can also be thought of as 'Date' rules, will match the expression given against the backup file name, and preserve up to the given number of those that match. A value of 0 means all matches are preserved. 

Backup file names use ISO-8601 date format, although the colon between hour and minute may be replaced if the `COLON_REPLACEMENT` option is set in the config file. Although generally intended to match a particular date or time, other valid regular expression can be used, including any part of the file name. However, the '/' character is not allowed in the expression.

An example backup name (using the default colon replacement of 'h') is /mnt/backup_disk/backups/archive/desktop/2020-10-31T05h30+05h00

This gives the year, month, then day. The letter T is followed by time of day in 24-hour format, with the timezone adjustment afterward.

Example Direct intervals:
: `D3/202.-`   - keep the 3 most recent backups in the 202x decade
: `D0/-0[123]T` - keep all backups made on the first 3 days of any month
: `D1/-05-` - keep at least one backup made in the 5th month (May)
: `D5/T16`  - keep up to 5 backups made in the 4 p.m. hour 

### Keep 

Keep rules ('K') will preserve at most the given number of backups, and will not preserve any backups older than the time period P. The most recent backups are given priority. A value of 0 indicates that all backups in the period will be kept. Since rules are combined and all applied prior to culling, multiple Keep rules are likely to be unnecessary. However, some situations (such as irregular, or changing backup intervals) might make additional Keep rules useful.

Example Keep intervals:
: `K10/P10d` - keep no more than 10 backups for the last 10 days
: `K0/24h` - keep all backups made in the last 24 hours
: `K100/P3Y` - keep the 100 most recent backups, but none older than 3 years

### Recurring

Recurring rules ('R') will attempt to preserve one backup per time period, going as far back as the number of periods set by the rule. In this case, the oldest backups are given priority.

Recurring rules are meant to keep a roughly regular number of backups available in the archive, since these are not scheduling backups, but managing backups already made. There is an 'extension' applied to the recurring rule to avoid large gaps between preserved backups as they move from one period into another. See the note below and the file 'recurrence_extension.txt' for further information.

Example Recurring intervals:
: `R4/2w` - every two weeks, limit of four backups (8 weeks back)
: `R20/P2d9h30m` - every 2 days, 9 and a half hours, limit of 20 ( ~48 days back)
: `R6/120m` - every 120 minutes, limit of 6 ( 12 hours back )


# Additional Notes
 
## Clock variations between machines

The time used to indicate when a backup occurs (and how it is named in the archive) is based on the timestamp submitted by the machine actually backing up (using the 'bunc.sh' script or similar), and this may be any time desired as long as it is in ISO-8601 format. On the archival machine, however, the culling rules are applied using the local clock setting. Calculations are done using epoch time to avoid any issues with timezones. However, variations in the clocks may result in a backup's timestamp name indicating a future time relative to the archival machine. When this occurs, the backup is always preserved, regardless of culling rules. 

There are a few configuration settings that account for this situation. The `FUTURE_LEEWAY` is the time in seconds that the backup may be marked ahead of the archival machine's culling time. If the timestamp on the backup is farther ahead in the future than the culling time + `FUTURE_LEEWAY`, a warning is logged, although the backup is preserved and normal culling takes place. If the `ABORT_ON_FUTURE` option is set to true, an error is logged when the backup time is beyond this point in time, and no culling will occur. 

## Irregular backup schedules and recurring rules

Since BUNS does not schedule the backups, the periods indicated by the rules may not match the period at which backups are actually made. Even when backups are regular, the interaction of rules can result in culling that leads to variation in what is preserved. This is most noticeable with recurring rules. 

When the recurring rule is applied, it will first check to see if the period in question has a backup in the older half of the period. If not, it will try to find the oldest backup that is at least half a period younger than the one marked in the previous period. The effect is that when recurring rules are applied, the time between preserved backups can vary up to about 1.5x the recurrence period, as long as the recurrence period is long relative to the time between backups. See the file 'recurrence_extension.txt' for additional explanation and examples.

## Using the scripts separately

Aside from needing to read the config file (or at least have the variables set), the scripts for BUNS can be run independently. You are free to use or adapt them as you see fit, including only using the rsync wrappers, or only the culling side. The culling portion is not dependent on how the backups are made at all, although it does require the filenames to be timestamps in order to determine when the backup was made. 

## Errors during backups

The archival and preservation/culling only occurs when a backup completes successfully. This helps to ensure that only complete and valid backups are entered in the archive, and also allows for partial backups to be made, and only archived once fully complete. It also means that if there are any rsync errors at all during the backup, the archival process will not be performed.

Some common rsync errors that occur may be the result of extended attributes not copying correctly. This may be due to filesystem differences, or to not being compatible with the 'fake superuser' operation of rsync that BUNS uses. In these cases, it is advisable to add a filter to the rsync rules that excludes those extended attributes (using -x), or even exclude those files explicitly to avoid having a copy with missing attributes. 

Other rsync errors may also be the result of SSH errors, which may be indicated by 'broken pipe' messages or 'unexplained error' in the logs. Check your SSH configuration if this is a frequent occurrence. 

BUNS attempts to recover from situations in which part of the process fails for any reason. This may be due to a lost connection during the backup, or when the archival machine is restarted while the backup or archival is in progress. In most cases, a backup can be started (or continued) later with no issues. Some situations may result in the first backup after a failed one to indicate a failure and halt, but after the BUNS monitoring times out (60 seconds), subsequent backups will work normally. 

## What does BUNS stand for?

At one time, this was named 'BUMS' for Back-Up Management System (or Server), but later renamed since 'buns' just sounds better. The most apposite backronym to use is 'Back-Up Negotiation Scripts', although it could also be read as 'Back Up as Non-Superuser', or even 'Back-Up Negotiation - Server', to contrast with the local back-up script 'bunc.sh' possibly standing for 'Back-Up Negotiation - Client'.


