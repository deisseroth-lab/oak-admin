#!/bin/bash
#
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G

[ "$#" -ne 1 ] && echo "USAGE $0 <FILE_WITH_DIRECTORY_PER_LINE>" && exit

set -e
set -x

# The one argument is a file containing a list of directories to process.
DIRLIST=${1}

readarray -t DIRS < ${DIRLIST}
DIR=${DIRS[${SLURM_ARRAY_TASK_ID}]}

rm -rf ${DIR}

echo "Done deleting files."
