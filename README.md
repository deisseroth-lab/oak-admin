# oak-admin
Admin files, scripts, etc. for use on the OAK cluster

## Archive (tar and gzip) many directories.

Archiving a directory creates a single file with the entire contents of the 
directory, compressed.  This helps save disk space and file counts.

To get started, create a file with one directory per line, listing all the directories
to archive.  The following command shows how you might do this on the command
line, creating a file called `dirs.txt`.  Verify the contents of the file before
proceeding.

```bash
$ ls -d ${OAK}/users/${USER}/SOME/DIRECTORY/PATTERN > dirs.txt
# Example:
# $ ls -d ${OAK}/users/${USER}/grin/2020* > dirs.txt
```

Now, we will launch an "array job", which creates one Sherlock job per directory.
Make sure to update the `--array` parameter based on the number of directories
you will backup.  **Note that N here is the number of directories MINUS 1** because
we are counting from zero!

If you would like to test, you can run 2 jobs with `--array=0-1`, and then run
the rest of the jobs with `--array=2-N`.

```bash
$ sbatch --job-name=archive --array=0-N ${OAK}/admin/oak-admin/backup/tar_and_zip_dirlist.sh dirs.txt
# Example with 40 jobs: 
# $ sbatch --job-name=archive --array=0-39 ${OAK}/admin/oak-admin/backup/tar_and_zip_dirlist.sh dirs.txt
```
