#####################
# pgdbdump_common
#####################
# Common parts for scripts related to creating dumps of postgres databases
# (C) 2023-2024 Sergey Merzlikin sm@smsoft.ru
#####################
# Licensed under the GNU General Public License v3.0
#####################

Exists()
{
  command -v "$1" >/dev/null 2>&1
}
Compress()
{
    if [ "$compress" = "auto" ] ; then
	size=$(stat -c %s "$1")
	if [ "$size" -gt 52428800 ] ; then
	    if Exists "lrzip" ; then
		compress="lrzipz"
	    elif Exists "pixz" ; then
		compress="pixz"
	    else
		compress="xz"
	    fi
	else
	    if Exists "pixz" ; then
		compress="pixz"
	    else
		compress="xz"
	    fi
	fi
    fi
    case "$compress" in
	lrzip)
	    echo ".lrz"
	    lrzip -D -f -Q "$1" > /dev/null
	;;
	lrzipz)
	    echo ".lrz"
	    lrzip -D -f -Q -z "$1" > /dev/null
	;;
	7-zip)
	    echo ".7z"
	    7za a "$1.7z" "$1" -bd -sdel > /dev/null
	    ;;
	pixz)
	    echo ".xz"
	    pixz "$1" > /dev/null
	;;
	*)
	    echo ".xz"
	    xz -T0 -q -f "$1" > /dev/null
	;;
    esac
}

#####################
# Execution starts here
# Some defaults
compress="auto"
pguser="postgres"
# Process config file
. /etc/pgdbdump/dumpconfig.sh
if [ -z "$1" ] ; then
  echo "Database name not specified"
  exit 7
fi
if [ -z "$backdir" ] ; then
  echo "Backup directory not specified"
  exit 8
fi
# if base name contains characters '_' or '%' replace them by '%1' and '%0' accordingly
dbname=$(echo "$1" | sed -e 's/%/%0/g; s/_/%1/g')
backpath="$backdir/$dbname"
#####################
