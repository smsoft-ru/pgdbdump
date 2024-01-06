pgdbdump

A set of linux shell scripts intended for creating full, differential or incremental dumps of postgres databases.
This set of scripts also include interactive based on dialog (which in turn is ncurses-based) script for restore these dumps.
(C) 2024 Sergey Merzlikin sm@smsoft.ru
Licensed under the GNU General Public License v3.0.

pgdbdump.sh is used to create dumps. How it works creating full dump:
1. It creates raw text dump of database in temporary directory.
2. It creates rdiff signature for created dump and stores it in backup directory.
3. It compresses the dump with lrzip, pixz, xz or 7-zip (depending on options in config file and on size of raw dump)
   and stores it in backup directory. Temporary uncompressed dump deletes after it. Information about date and dump type
   contains in compessed dump filename.

How it works creating differential or incremental dump:
1. It creates raw text dump of database in temporary directory.
2. It creates rdiff delta file in temporary directory based on previously stored rdiff signature.
3. Only when creating incremental dump it creates rdiff signature for created dump and replaces it in backup directory.
3. It compresses rdiff delta with above mentioned archivers and stores it in backup directory. Temporary uncompressed
   dump and delta deletes after it. Information about date and dump type contains in compessed delta filename.

Primarily pgdbdump.sh is designed to start via cron jobs.

pgdbrestore.sh is interactive (with non-interactive option) user-friendly script intended for restore postgres
database archives into new or original database. Also it is possible to reconstruct raw text dump to subsequent manual
restore of database (possibly on another machine).
The script unpacks and combines differential, incremental and full dumps (using rdiff) and applies resulting
full dump to postgres database.
Dialog screens of the script allows to select database to restore, date of archive, restore mode (into original 
database, new database or save raw full dump) and some other options.

Dialog screens and log messages may appear on different national languages. Currently supported English and Russian
languages. Support for another languages may appear in future.

Both scripts may log their activity and errors in systemd journal and syslog.
Command-line parameters and config options are explained at the beginning of corresponding files.

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

Compressing utilities are needed only those which are configured (for compression) and which type of archives are
present (for decompression). If "auto" compression type chosen (default), then pixz and lrzip are used if installed
(recommended), and xz otherwise.

Most of above dependencies are already present in modern linux distributives.

Installation:
 - Check dependencies and install any if required
 - Copy config files to /etc/pgdbdump directory
 - Copy all other files to any directory in file system (all files must be together)
 - Set up backup directory in config files
 - Set up cron jobs to create dumps on regular basis
