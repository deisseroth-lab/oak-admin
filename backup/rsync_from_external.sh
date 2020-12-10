#!/bin/bash
# vim: ts=4 sw=4 noet

#  Tool to sync directory from external computer to OAK.

#  NEW USERS:
#
#  To use the script, run it directly.
#  (In other words, run it like any other script!)
#
#  The script takes two arguments: The external machine and the directory.
#  So, to sync the directory "/blah" from computer "foo", you would run like so:
#    ./scriptname.sh user@foo /blah
#
#  The backup will be in $OAK/users/$USER/backups/foo/blah
#
#  The script will do some checks, and then submit itself as a SLURM job.
#  The script does support preemption, so it can be requeued and restarted as
#+ many times as needed.
#  The script has a time limit; if it needs more time to complete the backup,
#+ it will resubmit itself.
#  Once a sync has completed, it will email you, and submit itself to re-run
#+ tomorrow.
#

#
# SLURM SETTINGS START HERE
#

#  The partition to use.  If possible, choose a preemptable partition.
#SBATCH --partition owners

#  Use one CPU core, 2G RAM, and support sharing resources (if allowed).
#SBATCH --ntasks 1
#SBATCH --cpus-per-task 1
#SBATCH --mem-per-cpu 2G
#SBATCH --oversubscribe

#  Limit runtime to 3 hours.  We'll reschedule ourselves if needed.
#SBATCH --time 3:00:00

#  Let us know when we're going to be killed.
#  Also, ask SLURM to only let one of us be running at a time.
#SBATCH --signal B:USR1@300
#SBATCH --dependency singleton

#  We support being kicked off of a node.
#SBATCH --requeue

#  Only email if the job fails (which means it won't reschedule).
#SBATCH --mail-type FAIL

#  NOTE: These two lines are disabled by default!  You can "enable" them by
#+ deleting one of the # characters at the start of the line.
#  Stop creating .out files for each SLURM job.  Only do this if things work.
##SBATCH --error /dev/null
##SBATCH --output /dev/null

#
# CODE STARTS HERE
#

# DEBUG can be set to 1 outside of the script, to enable debug logs.
DEBUG=${DEBUG:=0}
if [ $DEBUG -eq 1 ]; then
	echo 'Debug alive'
fi

# We need TMPDIR to be set.  If it's not, default to '/tmp'
TMPDIR=${TMPDIR:=/tmp}

# Combine standard output and standard error
exec 2>&1

# Before we have any real code, define a function to email or output an error.
function mail_or_print {
	#  $1 = The body of the email
	#  $2 = The subject line of the email
	if [ $DEBUG -eq 1 ]; then
		echo 'In mail_or_print'
	fi

	#  If we are in SLURM, then we need to send an email to the user.
	#  Otherise, simply print the subject and message to the user.
	if [ ${SLURM_JOB_ID:=0} -ne 0 ]; then
		if [ $DEBUG -eq 1 ]; then
			echo 'Sending email'
		fi
		echo "${1}" | mail -s "${2}" $USER
	else
		echo "${2}"
		echo "${1}"
	fi
	return 0
}

#  Next, we need a set of functions to tell us if a particular rsync exit code
#+ has a partiuclar meaning.  We know exit code zero is "completed
#+ successfully", but what about the others?
#  NOTE: For these functions, returning true means returning zero, so that
#+ the function's result can be used directly in an `if` statement.

# TODO: Add functions to detect recoverable failures (i.e. network hiccups)
# rsync return codes:
#  0     Success
#  1     Syntax or usage error
#  2     Protocol incompatibility
#  3     Errors selecting input/output files, dirs
#  4     Requested action not supported: an attempt was made to manipulate 64-bit
#        files on a platform that cannot support them; or an option was specified
#        that is supported by the client and not by the server.
#  5     Error starting client-server protocol
#  6     Daemon unable to append to log-file
# 10     Error in socket I/O
# 11     Error in file I/O
# 12     Error in rsync protocol data stream
# 13     Errors with program diagnostics
# 14     Error in IPC code
# 20     Received SIGUSR1 or SIGINT
# 21     Some error returned by waitpid()
# 22     Error allocating core memory buffers
# 23     Partial transfer due to error
# 24     Partial transfer due to vanished source files
# 25     The --max-delete limit stopped deletions
# 30     Timeout in data send/receive
# 35     Timeout waiting for daemon connection

# This function returns true for any non-zero exit code.
function rsync_exit_failed {
	if [ $DEBUG -eq 1 ]; then
		echo "In rsync_exit_failed with exit code ${1}"
	fi
	case $1 in
		0)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

#  Finally, define a set of functions that will send an alert on a particular
#+ rsync condition, and then exit.
#  TIP: 'rsync_exit_' -> "Did rsync exit because of ..."
#  TIP: 'exit_rsync_' -> "Exit because of rsync issue ..."

#  This function handles alerting when rsync exited because of a generic, non-
#+ retryable failure.
#  $1 is the command run.
#  $2 is the command output.
function exit_rsync_failed {
	if [ $DEBUG -eq 1 ]; then
		echo "In exit_rsync_failed"
		echo "Command is ${1}"
	fi
	IFS='' read -r -d '' error_message <<-EOF
	There was a problem running rsync.  This is either because of a local problem, or because of some other problem that rsync hasn't otherwise classified.  Either way, this program will not work until the underlying problem is fixed.

	The rsync command run was: ${1}
	Here is the output from rsync:
	${2}
EOF
	error_subject='rsync failure [ACTION REQUIRED]'
	mail_or_print "${error_message}" "${error_subject}"
	exit 1
}

# OMG
# Now we can actually DO STUFF!!!!!

#  Make sure we actually have arguments
if [ $# -ne 2 ]; then
	echo 'This script got the wrong number of arguments!'
	echo 'You should be running this script with two arguments: The name of the computer and a directory to sync.'
	exit 1
fi

#  Now, make sure the remote path is accessible.

remote_path=$(echo "${1}:${2}/" | tr -s /)
if [ $DEBUG -eq 1 ]; then
	echo "Using remote_path ${remote_path}"
fi
ssh ${1} "stat ${2} > /dev/null 2>&1"
exit_code=$?
if [ $exit_code -ne 0 ]; then
	IFS='' read -r -d '' error_message <<EOF
The remote path "${1}:${2}" is not accessible.  It may be that you do not have access to the computer or the directory has been moved, or renamed.   Either way, this program will not work anymore.  You should try re-submitting it with different arguments.
EOF
	error_subject='rsync remote_path problem [ACTION REQUIRED]'
	mail_or_print "${error_message}" "${error_subject}"
	if [ $DEBUG -eq 1 ]; then
		echo 'stat output:'
		ssh ${1} "stat ${2} 2>&1"
	fi
	exit 1
fi

# Now, make sure the OAK path is accessible.

oak_path=$(echo "${OAK}/users/${USER}/backups/${1}/${2}/" | tr -s /)
if [ $DEBUG -eq 1 ]; then
	echo "Using oak_path ${oak_path}"
fi
mkdir -p ${oak_path}
exit_code=$?
if [ $exit_code -ne 0 ]; then
	IFS='' read -r -d '' error_message <<EOF
The OAK path "${oak_path}" is cannot be accessed properly.  It may be that the directory or its parents do not have the correct permissions.  This program will not work anymore.  You should try re-submitting it with a new path.
EOF
	error_subject='rsync oak_path problem [ACTION REQUIRED]'
	mail_or_print "${error_message}" "${error_subject}"
	if [ $DEBUG -eq 1 ]; then
		echo 'mkdir output:'
		mkdir -p ${oak_path} 2>&1
	fi
	exit 1
fi

#  NOTE: We do not print "good to go" unless we are running interactively.
#  This is to reduce unnecessary output noise.

#  If the user is running this interactively, it's time to submit our job.
#  NOTE: This is the only time we'll run sbatch without `--quiet`.
if [ ${SLURM_JOB_ID:=0} -eq 0 ]; then
	cat - <<EOF
Good to go!
Attempting to submit a job.
After this, you will either get a job ID number, or an error.
If you get a job ID number, all further messages should come to you by email!
EOF
	exec sbatch --job-name="rsync ${remote_path}" --begin=now $0 $@
fi

# If we're here, then we are running inside a job.

#  We'll be running rsync in a subshell.  With a subshell, variables from the
#+ parent are copied into the child, but then the parent has no visibility
#+ into what the child's vars are.
#  So, we'll need to capture subshell output into a separate temp file.
rsync_pid=0
rsync_output_file="${TMPDIR}/rsync.${SLURM_JOBID}.out"
if [ $DEBUG -eq 1 ]; then
	echo "rsync output will be sent to path ${rsync_output_file}"
fi

#  We also need to start looking out for our job being warned about
#+ impending killing.  We'll get a USR1 signal, which we'll need to trap.
function signal_usr1 {
	if [ $DEBUG -eq 1 ]; then
		echo 'Received USR1 signal.  Our time has run out.'
	fi

	# Since we'll be killing rsync, unlink our temp file.
	if [ -f ${rsync_output_file} ]; then
		rm ${rsync_output_file}
	fi

	#  Kill the rsync process, and then requeue ourselves.
	#  NOTE: We use `requeue` here so that all of the executions appear under
	#+ the same jobid, which helps with future lookups via `sacct`.
	kill $rsync_pid
	exec scontrol requeue ${SLURM_JOBID}
}

#  We also need to be on the lookout for Control-C (SIGINT); when we receive
#+ it, we need to kill the chiild process.
function signal_int {
	if [ $DEBUG -eq 1 ]; then
		echo 'Received INT signal.  Killing child process and cleaning up.'
	fi

	# Since we'll be killing rsync, unlink our temp file.
	if [ -f ${rsync_output_file} ]; then
		rm ${rsync_output_file}
	fi

	# Kill the rsync process, and then exit ourselves.
	kill $rsync_pid
	exit 1
}

#  All our checks look good!  Let's try running things.

#  This part gets interesting.  We're going to run rsync via a subshell.
#  Vars from the parent shell are present in the subshell, but we can't access
#+ vars created in the subshell.  So, we'll need an output file.
trap "signal_usr1" USR1
trap "signal_int" INT
echo $@
if [ $DEBUG -eq 1 ]; then
	echo "Running rsync -avP '${remote_path}' '${oak_path}'"
fi
(
	exec 1>${rsync_output_file} 2>&1
	exec rsync -avP "${remote_path}" "${oak_path}"
) &

#  Get the process ID of the rsync subshell
rsync_pid=$!

#  Wait for rsync to exit, or for something else to happen
if [ $DEBUG -eq 1 ]; then
	echo "rsync launched with PID ${rsync_pid}.  Waiting..."
fi
wait $rsync_pid
exit_code=$?

# Read in the rsync output, in case we have to send an error message.
rsync_output=$(cat ${rsync_output_file})

if rsync_exit_failed "${exit_code}"; then
	exit_rsync_failed "${rsync_command[*]}" "${rsync_output}"; exit $?
fi

# We got this far, which must mean that rsync completed!  Wooo!
if [ $DEBUG -eq 1 ]; then
	echo "Sync complete!  Sending mail and scheduling to run again tomorrow."
fi
IFS='' read -r -d '' completion_message <<EOF
Your backup of path ${remote_path} has been completed without errors!

The output of the \`rsync\` command is attached.  Please check it for problems.
EOF
echo "${completion_message}" | mail -s "Backup completed for ${1}" -a ${rsync_output_file} ${USER}

# Clean up the rsync output file
rm ${rsync_output_file}

# Submit ourselves to run tomorrow.
exec sbatch --quiet --job-name "rsync ${1}:${2}" --begin 'now+1day' $0 $@
