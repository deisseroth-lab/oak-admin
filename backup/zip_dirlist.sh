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

BASENAME=$(basename ${DIR})
PARENTDIR=$(dirname ${DIR})

cd $PARENTDIR
zip -r ${BASENAME}.zip ${BASENAME}

chmod a-w ${BASENAME}.zip

echo "Done zipping files."
