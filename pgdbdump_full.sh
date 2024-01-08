#!/bin/sh
#####################
# pgdbdump_full v1.0
#####################
# Script for creating full dumps of postgres databases
# (C) 2023-2024 Sergey Merzlikin sm@smsoft.ru
#####################
# $1 = database name to dump
#####################
# Licensed under the GNU General Public License v3.0
#####################

scriptdir="$(dirname "$(realpath "$0")")"
# Source common script part
. "$scriptdir/pgdbdump_common.sh"

tmppath=$(mktemp -d)
trap "rm -r $tmppath" 0 2 3 15
outfile=${tmppath}/_pgdump_temp
# create database dump in temporary directory
if pg_dump -U "$pguser" -c -C --if-exists -f "$outfile" "$1" && [ -f "$outfile" ] ; then
    # get file mod date
    outfiledate=$(date -r "$outfile" +'%y%m%d%H%M%S')
    # rename to name which contains database name and timestamp
    newname=pgdump_${dbname}_$outfiledate
    tmpdumpname=$tmppath/$newname
    if mv "$outfile" "$tmpdumpname" && [ -f "$tmpdumpname" ] ; then
	# create backup directory if not exists
	mkdir -p "$backpath"
	if [ -d "$backpath" ] ; then
	    dumpname=$backpath/$newname
	    # make rdiff signature and write it to backup directory
	    if rdiff signature "$tmpdumpname" "${dumpname}.sign" && [ -f "${dumpname}.sign" ] ; then
		# compress dump
		if suffix="$(Compress "$tmpdumpname")" && [ -f "${tmpdumpname}$suffix" ] ; then
		    # move compressed dump to backup directory
		    if mv -t "$backpath" "${tmpdumpname}$suffix" && [ -f "${dumpname}$suffix" ] ; then
			# get contents of timestamp file if exists
			lfdfile=${backpath}/_${dbname}_latest_dump
			if [ -f "$lfdfile" ] ; then
			    oldoutfiledate=$(cat "$lfdfile")
			    if [ -n "$oldoutfiledate" ] ; then
				# delete previous signature file if exists
				rm -f "${backpath}/pgdump_${dbname}_${oldoutfiledate}.sign"
			    fi
			fi
			# create new timestamp file in backup directory
			echo $outfiledate > "$lfdfile"
		    else
			echo "Error moving database dump to backup directory"
			rm -f "${dumpname}.sign"
			exit 5
		    fi
		else
		    echo "Error compressing database dump"
		    rm -f "${dumpname}.sign"
		    exit 4
		fi
	    else
		echo "Error creating rdiff signature"
		exit 3
	    fi
	else
	    echo "Error creating backup directory"
	    exit 6
	fi
    else
	echo "Error renaming database dump"
	exit 2
    fi
else
    echo "Error creating database dump"
    exit 1
fi
