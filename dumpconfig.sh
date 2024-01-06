###################################
# Sample config file for pgdbdump.sh
###################################

# Location of backup directory, must be specified.
#backdir="/var/pgbackup"

# Compress method. May be "auto", "xz", "pixz", "lrzip", "lrzipz", "7-zip".
# "auto" is default. It means that "pixz" is used for dumps below 50Mb, and "lrzipz" otherwise.
# "xz": xz command is used for compression, "pixz": pixz command, "lrzip": lrzip command,
# "lrzipz": lrzip in ZPAQ mode, "7-zip": 7za command is used.
# xz command is used in "auto" mode if pixz and/or lrzip are not installed.
# Also xz command is used if compress method is not recognizrd.
#compress="auto"

# Log to syslog/systemd journal. May be 1 (enabled) or any other value (disabled).
# Empty is default.
#logger=

# Account name on postgres server used to access to it. By default "postres"
#pguser="postgres"

# Here you may export some environment variables needed to run postgres
# command-line utilities and compression commands. In particular, you may
# export PGPASSWORD variable and add some directories to PATH variable.
#export PGPASSWORD="secret"
#export PATH=$PATH:/opt/pgpro/1c-15/bin