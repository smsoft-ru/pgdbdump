###################################
# Sample config file for pgdbrestore.sh
###################################

# Location of backup directory, must be specified.
#backdir="/var/pgbackup"

# Log to syslog/systemd journal. May be 1 (enabled) or any other value (disabled).
# Empty is default.
#logger=

# Dialog window maximum width and height. By default 120 and 45 characters.
#dialog_width=120
#dialog_height=45

# Common options for all windows of dialog command. By default "--noshadow".
#dialog_common_options="--noshadow"

# Account name on postgres server used to access to it. By default "postgres"
#pguser="postgres"

# Here you may export some environment variables needed to run postgres
# command-line utilities and compression commands. In particular, you may
# export PGPASSWORD variable and add some directories to PATH variable.
#export PGPASSWORD="secret"
#export PATH=$PATH:/opt/pgpro/1c-15/bin