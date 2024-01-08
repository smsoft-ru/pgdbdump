pgdbdump v1.0

A set of Linux shell scripts designed to create full, differential, or incremental dumps of postgres databases.
This set of scripts also includes an interactive script based on dialog (which in turn is based on ncurses)
to restore these dumps.

(C) 2024 Sergey Merzlikin sm@smsoft.ru

Licensed under the GNU General Public License v3.0.

pgdbdump.sh is used to create dumps. When creating a full dump, it works like this:

1. It creates a text dump of the database in raw format in a temporary directory.
2. It creates a rdiff signature for the created dump and stores (or replaces if exists) it in the backup directory.
3. It compresses the dump using lrzip, pixz, xz or 7-zip (depending on the options in the configuration file and the
   size of the dump) and saves it in the backup directory. The temporary uncompressed dump is then deleted.
   Dump date and type information contained in the compressed dump file name.

When creating a differential or incremental dump, it works like this:

1. It creates a text dump of the database in raw format in a temporary directory.
2. It creates a rdiff delta file in a temporary directory using the previously saved rdiff signature.
3. Only when creating an incremental dump, it creates a rdiff signature for the created dump and replaces it in the
   backup directory.
4. It compresses the rdiff delta file with the above-mentioned archivers and stores it in the backup directory.
   Temporary uncompressed dump and the delta file are then deleted. Information about the date and type of dump
   is contained in the name of the compressed delta file.

The main way to run pgdbdump.sh is through cron jobs.

pgdbrestore.sh is an interactive (with the ability to run non-interactively) user-friendly script designed to restore
postgres database archives created by the pgdbdump.sh script to the new or original database. It is also possible
reconstruct a text dump in raw format for subsequent manual recovery (possibly on another machine).
The script unpacks and combines differential, incremental and full dumps (using rdiff), and using the resulting
full raw dump restores the postgres database. The script dialog screens allow to select the database to restore, the date
of archive, recovery mode (to the original database, new database or save a full dump on disk) and some other options.

Dialog boxes and log messages may be displayed in different national languages. Currently supported are English
and Russian languages. Support for other languages may be available in the future.

Both scripts can log their actions and errors to the systemd journal and syslog. Command line parameters and
configuration options are described at the beginning of the corresponding files.

Dependencies:

 - postgres (pg_dump, psql)
 - rdiff
 - lrzip
 - pixz
 - xz
 - 7-zip
 - bash
 - dialog
 - realpath
 - logger

Compression utilities require only those that are configured (for compression), and for which the corresponding archive
types are present in the backup directory (for unpacking). If the compression type is "auto" (default), then pixz and
lrzip are used, if installed (recommended), and xz otherwise.

Most of the above dependencies are already present in modern Linux distributions.

Installation:

 - Check dependencies and install missing ones if necessary
 - Copy the configuration files to the /etc/pgdbdump directory
 - Copy the remaining files to any directory on the file system (all files must be together)
 - Change file permissions to make them executable: pgdbdump.sh, pgdbdump_diff.sh, pgdbdump_full.sh and pgdbrestore.sh
 - Set up the backup directory in the configuration files
 - Set up cron jobs to generate dumps on a regular basis
   
Some screen shots of pgdbrestore script:

Selection of database to restore

![Select database screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_selectdb.png)

Setting range of dates to search and display dumps

![Select date range screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_ranges.png)

Calendar panel appears after activating of button "Change" on above screen

![Select date screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_calendar.png)

This screen allows to select exact dump to restore

![Select dump screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_selectdump.png)

Selection of restore mode

![Select mode screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_mode.png)

Saving reconstructed full dump chosen: selecting directory to save dump file

![Select directory screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_seldir.png)

Restoring to new database chosen: setting new database name

![Set new database name screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_newdb.png)

Confirmation of creating new database

![Confirm creation new database screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_sure.png)

Restore process started

![Progress screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_progress.png)

Database is successfully restored as new database

![Complete screen](https://github.com/smsoft-ru/pgdbdump/blob/main/screenshots/en/pgdbrestore_progress2.png)
 
