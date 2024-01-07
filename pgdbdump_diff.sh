#!/bin/sh
#####################
# pgdbdump_diff
#####################
# Script for creating differential and incremental dumps of postgres databases
# (C) 2023-2024 Sergey Merzlikin sm@smsoft.ru
#####################
# $1 = database name to dump
# $2 may be "inc" or empty, in case "inc" incremental dump created, otherwise differential
#####################
# Licensed under the GNU General Public License v3.0
#####################

scriptdir="$(dirname "$(realpath "$0")")"
# Source common script part
. "$scriptdir/pgdbdump_common.sh"

# Check incremental mode parameter
if [ -n "$2" ]
then
    if [ "$2" = "inc" ] ; then
	incmode="$2"
    else
	echo "Invalid parameter \"$2\""
	exit 9
    fi
fi

# locate and read latest dump timestamp file
lfdfile=${backpath}/_${dbname}_latest_dump
if [ -f "$lfdfile" ] ; then
    fdfiledate=$(cat "$lfdfile")
    # locate latest dump signature file
    fdsignfile=${backpath}/pgdump_${dbname}_${fdfiledate}.sign
    if [ -f "$fdsignfile" ] ; then
	tmppath=$(mktemp -d)
	trap "rm -r $tmppath" 0 2 3 15
	outfile=${tmppath}/_pgdump_temp
	# create database dump in temporary directory
	if pg_dump -U "$pguser" -c -C --if-exists -f "$outfile" "$1" && [ -f "$outfile" ] ; then
	    # get file mod date
	    outfiledate=$(date -r $outfile +'%y%m%d%H%M%S')
	    # create delta file in temporary directory
	    if [ -n "$incmode" ] ; then
		deltaname=pginc_${dbname}_${fdfiledate}_$outfiledate
	    else
		deltaname=pgdelta_${dbname}_${fdfiledate}_$outfiledate
	    fi
	    tmpdeltaname=$tmppath/$deltaname
	    if rdiff delta "$fdsignfile" "$outfile" "$tmpdeltaname" && [ -f "$tmpdeltaname" ] ; then
		# compress delta
		if suffix="$(Compress "$tmpdeltaname")" && [ -f "${tmpdeltaname}$suffix" ] ; then
		    # move compressed delta to backup directory
		    if mv -t "$backpath" "${tmpdeltaname}$suffix" && [ -f "$backpath/${deltaname}$suffix" ] ; then
			# incremental mode processing
			if [ -n "$incmode" ] ; then
			    # make rdiff signature and write it to backup directory
			    dumpname=$backpath/pgdump_${dbname}_$outfiledate
			    if rdiff signature "$outfile" "${dumpname}.sign" && [ -f "${dumpname}.sign" ] ; then
				# delete previous signature file if exists
				rm -f "$fdsignfile"
				# create new timestamp file in backup directory
				echo $outfiledate > "$lfdfile"
			    else
				echo "Error creating rdiff signature"
				exit 3
			    fi
			fi
		    else
			echo "Error moving differential dump file to backup directory"
			exit 5
		    fi
		else
		    echo "Error compressing differential dump file"
		    exit 4
		fi
	    else
		echo "Error creating differential dump file"
		exit 10
	    fi
	else
	    echo "Error creating temporary database dump"
	    exit 1
	fi
    else
	echo "Latest dump signature file not found"
	exit 13
    fi
else
    echo "Latest dump timestamp file not found"
    exit 14
fi
