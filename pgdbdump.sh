#!/bin/sh
#####################
# pgdbdump v1.0
#####################
# Script for creating full, differential or incremental dumps of postgres databases
# (C) 2024 Sergey Merzlikin sm@smsoft.ru
#####################
# $1 = database name to dump
# $2 may be "diff", "inc" or empty, in case "diff" and "inc" differential and incremental dump created, otherwise full
# Logs informational messages to syslog/systemd journal if corresponding parameter in dumpconfig.sh exist
#####################
# Licensed under the GNU General Public License v3.0
#####################
scriptdir="$(dirname "$(realpath "$0")")"
. /etc/pgdbdump/dumpconfig.sh

Log()
# allows to log to syslog/systemd journal
{
    logger -t "pgdbdump" "$@"
}

Dumpfull() {
# Make full dump
    o=$("$scriptdir/pgdbdump_full.sh" "$1")
    e=$?
    [ "$logger" = 1 ] && [ -n "$o" ] && Log "$o"
    [ -n "$o" ] && echo $o
    return $e
}

Dumpdiff() {
# Make differential or incremental dump
    o=$("$scriptdir/pgdbdump_diff.sh" "$1" "$2")
    e=$?
    [ "$logger" = 1 ] && [ -n "$o" ] && Log "$o"
    if [ $e -eq 13 ] || [ $e -eq 14 ] ; then
	# Make full dump if previous full or incremental dump doesn't exist
	Dumpfull $1
    else
	[ -n "$o" ] && echo $o
	return $e
    fi
}

case "$2" in
    diff)
	[ "$logger" = 1 ] && Log "Differential dump of database \"$1\" started"
	Dumpdiff "$1"
	e=$?
	[ "$logger" = 1 ] && [ $e -eq 0 ] && Log "Differential dump of database \"$1\" completed"
    ;;
    inc)
	[ "$logger" = 1 ] && Log "Incremental dump of database \"$1\" started"
	Dumpdiff "$1" inc
	e=$?
	[ "$logger" = 1 ] && [ $e -eq 0 ] && Log "Incremental dump of database \"$1\" completed"
    ;;
    *)
	[ "$logger" = 1 ] && Log "Full dump of database \"$1\" started"
	Dumpfull "$1"
	e=$?
	[ "$logger" = 1 ] && [ $e -eq 0 ] && Log "Full dump of database \"$1\" completed"
    ;;
esac
exit $e
