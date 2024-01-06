#!/bin/bash
#####################
# pgdbrestore
#####################
# Interactive script for restoring full/incremental/differential dumps of postgres databases
# (C) 2023-2024 Sergey Merzlikin sm@smsoft.ru
#####################
# $1 - database name to restore, optional if not used --nointer switch
# $2 - optional end date to search dumps, by default current date used
# $3 - optional start date to search dumps, by default used date at one month ago from end date
# Options (must be before parameters):
# --savedumpto dirpathname - directory where will be saved unpacked full dump
# --restoretodb dbname - name of database to restore dump to
# Only one of above options may be specified
# --nointer - non-interactive mode. In this mode no interactive dialogs shown, if neither --savedumpto nor --restoretodb specified, then 
# restoration goes to original database, date of dump will be chosen closest to specified in $2 or to now if $2 is empty
#####################
# Licensed under the GNU General Public License v3.0
#####################

GetDirs()
# fills array with names of subdirectories in directory $1
# $2 - name of array to fill
{
    local -n dirs=$2
    dirs=("$1"/*/)                    # This creates an array of the full paths to all subdirs
    dirs=("${dirs[@]%/}")             # This removes the trailing slash on each item
    dirs=("${dirs[@]##*/}")           # This removes the path prefix, leaving just the dir names
    if [ "${dirs[0]}" == '*' ] ; then # Empty dir returns one "*" element - removing it
	dirs=()
    fi
}

Log()
# allows to log to syslog/systemd journal
{
    logger -t "pgdbrestore" "$@"
}

Progressbox()
# Shows dialog progress box and expects messages strings on stdin, also allows to log all messages to syslog
# if variable "$logger" is equal to 1.
# In non-interactive mode simply passes messages to stdout
{
    {
	if (( $logger == 1 )) ; then
	    tee -a -i >(Log)
	else
	    cat <&0
	fi
    } | {
	if (( $nointer == 1 )) ; then
	    cat <&0
	else
	    dialog $dialog_common_options --progressbox "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3
	fi
    }
}

Calendar()
# Shows calendar dialog box. $1 - header text, $2 - pre-filled date (may be empty, defaults to current date)
# In non-interactive mode echoes $2 (or current date) and exits
# Dates are in format YYYYmmdd000000 (14-digit)
{
    local d res rc
    if (( $logger == 1 )) ; then
	Log "$1"
    fi
    d="$(DateToInt "$2")"
    res="$(dialog $dialog_common_options --calendar "$1" 0 0 ${d:6:2} ${d:4:2} ${d:0:4} 3>&1 1>&2 2>&3 )"
    rc=$?
    if (( $rc == 0 )) ; then
	res="$(DateToInt "${res:6:4}${res:3:2}${res:0:2}")"
	echo "$res"
    fi
    if (( $logger == 1 )) ; then
	Log "[$res][$rc]"
    fi
    return $rc
}

Message()
# Allows to show message dialog box
# $1 may be "--msgbox", "--yesno" or any other option of dialog command
# If $1 doesn't start with "--", this parameter treats as message text, and "--infobox" as dialog option used
# If $1 is a dialog option, $2 is message text
# $3 may contain any other dialog option not containing internal space symbols
# In non-interactive mode echoes message to stdout and exits
{
    if ! [[ "$1" =~ ^--.* ]] ; then
	if (( $logger == 1 )) ; then
	    Log "$1"
	fi
	if (( $nointer == 1 )) ; then
	    echo "$1"
	else
	    dialog $dialog_common_options --infobox "$1" 0 0 3>&1 1>&2 2>&3
	fi
    else
	if (( $logger == 1 )) ; then
	    Log "$2"
	fi
	if (( $nointer == 1 )) ; then
	    echo "$2"
	else
	    local rc
	    dialog $dialog_common_options $3 "$1" "$2" 0 0 3>&1 1>&2 2>&3
	    rc=$?
	    if (( $logger == 1 )) ; then
		Log "[$rc]"
	    fi
	    return $rc
	fi
    fi
}

Inputbox()
{
    local res rc
    if (( $logger == 1 )) ; then
	Log "$1"
    fi
    if (( $nointer == 1 )) ; then
	res="$2"
    else
	res=$(dialog $dialog_common_options --inputbox "$1" 0 0 "$2" 3>&1 1>&2 2>&3)
	rc=$?
    fi
    if (( $logger == 1 )) ; then
	Log "[$res][$rc]"
    fi
    echo "$res"
    return $rc
}

Menu()
{
    local res rc
    if (( $logger == 1 )) ; then
	Log "$1"
    fi
    res="$(Menu0 "$@")"
    rc=$?
    if (( $logger == 1 )) ; then
	Log "[$res][$rc]"
    fi
    echo "$res"
    return $rc
}
Menu0()
# Shows menu
# $1 - message text above menu
# $2 - name of array of tags
# $3 - name of array of menu entries (may be empty)
# $4 - any other dialog command options (for example, "--notags"). May be empty, option parameters must not contain spaces
# $5 - title of dialog box, may be empty
# $6 - default item tag, may be empty
# Selected item tag goes to stdout, nonzero return code assigned in case user canceled dialog
# In non-interactive mode echoes $6 and exits
{
    if (( $nointer == 1 )) ; then
	echo "$6"
    else
	local -n v=$2
	if [ -n "$3" ] ; then
	    local -n vd=$3
	else
	    local vd=()
	fi
	# Mix tags and menu entries into one array
	local va=()
	for (( iv=0; iv<${#v[@]}; iv++ )) ; do
	    va[(( $iv*2 ))]="${v[$iv]}"
	    va[(( ($iv*2)+1 ))]="${vd[$iv]}"
	done
	dialog $dialog_common_options $4 --title "$5" --default-item "$6" --menu "$1" 0 0 0 "${va[@]}" 3>&1 1>&2 2>&3
    fi
}

ArrayInsert()
# Inserts array element $3 to position $2
# #1 - name of array
{
    local -n arr=$1
    arr=("${arr[@]:0:$2}" "$3" "${arr[@]:$2}")
}

DSelect()
# Allows to navigate file system and select directory
# Also allows to create new directory
# $1 - message at the top of dialog window. If not specified, defaults to "Select directory"
# This message will be supplemented with some lines which explain dialog usage
# $2 - directory pathname to start with. If not specified, defaults to "~"
# Selected directory pathname goes to stdout, nonzero return code assigned in case user canceled dialog
{
    local msg="$1"
    if [ -z "$msg" ] ; then
	#msg="Select directory"
	msg="$nls_41"
    fi
    if (( $logger == 1 )) ; then
	Log "$msg"
    fi
    #msg+="\nSelect \"/ New Directory /\" to create new directory\nPress \"GoTo\" to navigate to selected directory\nSelect \".\" to choose current directory"
    msg+="$nls_42"
    local basedir="$2"
    if ! [ -d "$basedir" ] ; then
	basedir=~
    fi
    local defbutton="ok"
    local curdir
    while true ; do
	# Navigate until user selects some dir or press Cancel
	local ds=()
	GetDirs "$basedir" "ds"
	# Don't add element ".." to root directory
	# Add "/ New Directory /" element to allow creation of new directory
	# Pre-select first subdir if exists and if no other subdir already pre-selected
	if [ "$basedir" == '/' ] ; then
	    #ds=("." "/ New Directory /" "${ds[@]}")
	    ds=("." "/ $nls_43 /" "${ds[@]}")
	    if [ -z "$curdir" ] ; then
		curdir="${ds[2]}"
	    fi
	else
	    #ds=("." ".." "/ New Directory /" "${ds[@]}")
	    ds=("." ".." "/ $nls_43 /" "${ds[@]}")
	    if [ -z "$curdir" ] ; then
		curdir="${ds[3]}"
	    fi
	fi
	# Show menu with extra button
	local dir
	local xe
	#dir="$(Menu0 "$msg" "ds" "" "--no-hot-list --extra-button --extra-label GoTo --default-button $defbutton --scrollbar" "$basedir" "$curdir")"
	dir="$(Menu0 "$msg" "ds" "" "--no-hot-list --extra-button --extra-label $nls_44 --default-button $defbutton --scrollbar" "$basedir" "$curdir")"
	xe=$?
	#if [ "$dir" == '/ New Directory /' ] ; then
	if [ "$dir" == "/ $nls_43 /" ] ; then
	    case $xe in
		0 | 3 )
		    # Try to create new directory
		    local newdir
		    #if newdir="$(Inputbox "Enter new directory name" "new_dir")" ; then
		    if newdir="$(Inputbox "$nls_45" "$nls_46")" ; then
			local e
			if e="$(mkdir "$basedir/$newdir" 2>&1)" ; then
			    # Pre-select created directory
			    curdir="$newdir"
			else
			    Message "--msgbox" "$e"
			fi
		    fi
		;;
		* )
		    # User pressed Cancel or other error
		    if (( $logger == 1 )) ; then
			Log "[][$xe]"
		    fi
		    return $xe
		;;
	    esac
	else
	    case $xe in
		0 )
		    # User selected some dir
		    local res="$(realpath -mqs "$basedir/$dir")"
		    if (( $logger == 1 )) ; then
			Log "[$res][0]"
		    fi
		    echo "$res"
		    return 0
		;;
		3 )
		    # User pressed "GoTo" button
		    if [ "$dir" == '..' ] ; then
			# Pre-select current dir if we are going to parent dir
			curdir="${basedir##*/}"
		    else
			curdir=""
		    fi
		    basedir="$(realpath -mqs "$basedir/$dir")"
		    # Pre-select "GoTo" button if we srarted directory navigation
		    defbutton="extra"
		;;
		* )
		    # User pressed Cancel or other error
		    if (( $logger == 1 )) ; then
			Log "[][$xe]"
		    fi
		    return $xe
		;;
	    esac
	fi
    done
}

DateToInt()
# Converts date to internal format "YYmmddHHMMSS"
{
    local d z
    if [ -n "$1" ] ; then
	# Remove punctuation from date and time
	d="$1"
	d="${d//-/}"
	d="${d////}"
	d="${d//./}"
	d="${d// /}"
	d="${d//:/}"
	# Pad date with zeros up to 14 symbols (YYYYmmddHHMMSS)
	z="00000000000000"
	d="${d:0:14}${z:0:$((14 - ${#d}))}"
    else
	# Use current timestamp if date is not specified on command line
	d="$(date +%Y%m%d%H%M%S)"
    fi
    echo "$d"
}


DateToHuman()
# Converts date from "YYmmddHHMMSS" to "%c" format or any other format specified in $2
{
    local dt="$1"
    local f="$2"
    if [ -z "$f" ]; then
	f="%c"
    fi
    # Test for 2-digit year in string
    if [ "${#dt}" -eq "12" ] ; then
	# Assume 20XX year
	dt="20$dt"
    fi
    local dts
    dts="${dt:0:4}-${dt:4:2}-${dt:6:2}t${dt:8:2}:${dt:10:2}:${dt:12:2}"
    date -d "$dts" +"$f"
}

GetDumpType()
# Retrieves dump type from filename
{
    if [[ "$1" =~ ^.*/pg(inc|delta|dump)_.* ]] ; then
	case "${BASH_REMATCH[1]}" in
	    "inc" )
		#echo "incremental"
		echo "$nls_47"
	    ;;
	    "delta" )
		#echo "differential"
		echo "$nls_48"
	    ;;
	    "dump" )
		#echo "full"
		echo "$nls_49"
	    ;;
	esac

    else
	return 7
    fi
}
GetDumpFileDate()
# Returns dump date in "%Y%m%d%H%M%S" format from filename
# If $2 is "parent", returns parent incremental or full dump date
{
    if [ "$2" == "parent" ] ; then
	local m=3
    else
	local m=4
    fi
    re="^.*/pg((inc|delta)_[[:alnum:]!-.:-@[-^{-~]+_([[:digit:]]+)|dump_[[:alnum:]!-.:-@[-^{-~]+)_([[:digit:]]+)\.(xz|lrz|7z)"
    if [[ "$1" =~ $re ]] ; then
	if [ -z "${BASH_REMATCH[$m]}" ] ; then
	    # No date: return error
	    return 2
	elif [ "${#BASH_REMATCH[$m]}" -eq "12" ] ; then
	    # Date in YYmmddHHMMSS format: left pad with assuming 20XX year digits
	    echo "20${BASH_REMATCH[$m]}"
	elif [ "${#BASH_REMATCH[$m]}" -eq "14" ] ; then
	    # Date in YYYYmmddHHMMSS format: return as is
	    echo "${BASH_REMATCH[$m]}"
	else
	    # Date in Unix format: convert it to YYYYmmddHHMMSS
	    date -d "@${BASH_REMATCH[$m]}" +%Y%m%d%H%M%S
	fi
    fi
}

IsUint()
# Returns zero if $1 contains unsigned integer value
{
    case $1 in ''|*[!0-9]* )
	return 1
	;;
    esac
}

GetDatabases()
# Fills array by all Postgres database names
# $1 - name of array to fill
# $2 - name of variable to return error message
{
    local -n dbn=$1
    local -n dbe=$2
    local dbo=$(psql -U "$pguser" -w -q -A -t -c "SELECT datname FROM pg_database")
    local dbr=$?
    if (( $dbr == 0 )) && [ -n "$dbo" ] ; then
	mapfile -t dbn <<< "$dbo"
    else
	dbe=$(psql -U "$pguser" -w -q -A -t -c "SELECT datname FROM pg_database" 2>&1)
	return $dbr
    fi
}

FindInArray()
# Finds element in array
# $1 - element; $2 - array name
{
    local needle="$1"
    local -n arrref="$2"
    local item
    for item in "${arrref[@]}"; do
        [ "$item" == "$needle" ] && return 0
    done
    return 1
}

Exists()
# Succeds if given command exists
{
  command -v "$1" >/dev/null 2>&1
}

Extract()
# Uncompresses xz, lrz and 7z archives with 1 file which name coincides with archive name
# $1 - archive name
# Echoes unpacked filename
{
    local ext="${1##*.}"
    local unpacked="${1%.*}"
    echo "$unpacked"
    case "$ext" in
	xz)
	    if Exists "pixz" ; then
		pixz -d "$1" > /dev/null
	    else
		xz -d -T0 -q -f "$1" > /dev/null
	    fi
	;;
	lrz)
	    lrzip -d -f -Q "$1" > /dev/null
	;;
	7z)
	    local exdir="${1%/*}"
	    7za e "$1" -aoa -o"$exdir" > /dev/null
	    e7="$?"
	    if (( $e7 == 0 )) ; then
		rm -f "$1"
	    fi
	    return "$e7"
	;;
	*)
	    return 10
	;;
    esac
}
EncodeDbname()
# If database name contains characters '_' or '%' replace them with '%1' and '%0' accordingly
# $1 - database name
{
    local dbn="${1//%/%0}"
    dbn="${dbn//_/%1}"
    echo $dbn
}
DecodeDbname()
# Reverts back replacements of '_' and '%' with '%1' and '%0' accordingly
# $1 - encoded database name
{
    local db="${1//%1/_}"
    db="${db//%0/%}"
    echo $db
}
Trim()
# Trims leading and trailing whitespace characters in string $1
{
    if [[ "$1" =~ ^[[:space:]]*([^[:space:]].*[^[:space:]]|[^[:space:]])[[:space:]]*$ ]] ; then
	echo "${BASH_REMATCH[1]}"
    fi
}
Nls_Init()
# Init National languadge support
{
    # Get Lang string without encoding
    nls_lang="${LANG:0:5}"
    # If NLS file for this language exists use it
    if ! [ -f "${scriptdir}/nls_${nls_lang}.sh" ] ; then
	# Otherwise parse aliases file if exists
	if [ -f "${scriptdir}/nls_aliases" ] ; then
	    local nlsa=()
	    local nlse
	    # Read aliases file into array
	    mapfile -t nlsa < "${scriptdir}/nls_aliases"
	    for nlse in "${nlsa[@]}" ; do
		nlse=$(Trim "$nlse")
		# Skip empty strings and comments
		if [ -n "$nlse" ] && [ ! "${nlse:0:1}" == "#" ] ; then
		    # Compare lang string with left part of alias record with wildcards pattern matching
		    if [[ "$nls_lang" == $(Trim "${nlse%%=*}") ]] ; then
			# Alias found - replace lang string with right part of alias record
			nls_lang="$(Trim "${nlse#*=}")"
			break
		    fi
		fi
	    done
	fi
    fi
    if [ -f "${scriptdir}/nls_${nls_lang}.sh" ] ; then
	source "${scriptdir}/nls_${nls_lang}.sh"
    else
	# NLS file not found - use English as last resort
	source "${scriptdir}/nls_en_US.sh"
    fi
}
Printfn()
# Add support for numbered conversion specifiers
# Add \n to the output
{  
    local -a args
    local opt=
    case $1 in
	-v)
	    opt="-v $2"
	    shift 2
	;;
	-*)
	    opt="$1"
	    shift
	;;
    esac
    local format="$1"
    shift
    while [[ "$format" =~ ((^|.*[^%])%)([0-9]+)\$(.*) ]] ; do
	args=("${!BASH_REMATCH[3]}" "${args[@]}")
	format="${BASH_REMATCH[1]}${BASH_REMATCH[4]}"
    done
    let ${#args[@]} && set -- "${args[@]}"
    printf $opt "$format\n" "$@"
}
##################### Execution starts here

# Export this variable to get correct work of dialog boxes with ssh connection
export NCURSES_NO_UTF8_ACS=1
# Get directory where this script is
scriptdir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# Some defaults
(( dialog_width=120 ))
(( dialog_height=45 ))
dialog_common_options="--noshadow"
pguser="postgres"
# Read configuration
source /etc/pgdbdump/restconfig.sh
# Initialize NLS
Nls_Init
(( nointer=0 ))
while true ; do
    if [ "${1:0:2}" == "--" ] ; then
	case "$1" in
	    "--nointer" )
		(( nointer=1 ))
		shift
	    ;;
	    "--savedumpto" )
		if [ -n "$restoretodb" ] ; then
		    #Message 'Options "--restoretodb" and "--savedumpto" cannot be set simultaneously'
		    Message "$nls_52"
		    exit 11
		fi
		savedumpto="$2"
		shift 2
	    ;;
	    "--restoretodb" )
		if [ -n "$savedumpto" ] ; then
		    #Message 'Options "--restoretodb" and "--savedumpto" cannot be set simultaneously'
		    Message "$nls_52"
		    exit 11
		fi
		restoretodb="$2"
		shift 2
	    ;;
	    * )
		#Message "Invalid option \"$1\""
		Message "$(Printfn "$nls_51" "$1")"
		exit 10
	    ;;
	esac
    else
	break
    fi
done
if [ -z "$1" ] ; then
    if (( $nointer == 1 )) ; then
	# Database not specified in non-interactive mode. Exit with error
	#Message "Database not specified"
	Message "$nls_50"
	exit 1
    fi
    # Database name not specified. Find subdirectories of Backup directory and show menu to select one
    mapfile -t dbs <<< $(find "$backdir" -mindepth 1 -maxdepth 1 -type d)
    dbpl=$(( ${#backdir}+1 ))
    for (( idb=0; idb<${#dbs[@]}; idb++ )) ; do
	# Cut path
	# Replace "%1" to "_" and "%0" to "%"
	dbs[$idb]="$(DecodeDbname "${dbs[$idb]:$dbpl}")"
    done
#    if ! dbname=$(Menu "Select databse to restore:" "dbs" "" "--no-hot-list") ; then
    if ! dbname=$(Menu "$nls_1" "dbs" "" "--no-hot-list") ; then
#	Message "Database name not selected"
	Message "$nls_2"
	exit 1
    fi
else
    dbname="$1"
fi

# If base name contains characters '_' or '%' replace them with '%1' and '%0' accordingly
dbname="$(EncodeDbname "$dbname")"
backpath="${backdir}/$dbname"
# Parse start and stop dates and initialize defaults if corresponding parameters omitted
date="$(DateToInt "$2")"
if [ -z "$3" ]; then
    datefrom="$(DateToInt "$(date --date "$(DateToHuman "$date" "%F") -1 month" "+%F")")"
else
    datefrom="$(DateToInt "$3")"
fi
# Show menu to adjust start and stop dates
menutags=(0 1)
spaces="          "
defbutton="ok"
# Loop with menu until user pressed OK or Cancel
while true ; do
    # Two menu rows: From and To dates, and extra button Change to change selected date
    menuitems[0]="${nls_57:0:${#spaces}}:${spaces:0:$(( ${#spaces} - ${#nls_57} - 1 ))}$(DateToHuman $datefrom)"
    menuitems[1]="${nls_58:0:${#spaces}}:${spaces:0:$(( ${#spaces} - ${#nls_58} - 1 ))}$(DateToHuman $date)"
    rsd="$(Menu "$nls_59" "menutags" "menuitems" "--no-hot-list --no-tags --extra-button --extra-label $nls_60 --default-button $defbutton")"
    xsd=$?
    case $xsd in
	0 )
	    # User pressed OK: exit loop
	    break
	;;
	3 )
	    # User pressed "Change" button
	    # Show calendar to change corresponding date
	    defbutton="extra"
	    if ((rsd == 0)); then
		if dx=$(Calendar "$nls_61" "$datefrom") ; then
		    datefrom=$dx
		fi
	    else
		if dx=$(Calendar "$nls_62" "$date") ; then
		    date=$dx
		fi
	    fi
	;;
	* )
	    # User pressed Cancel or other error
	    #Message "Recovery canceled"
	    Message "$nls_7"
	    exit
	;;
    esac
done

if [ -d "$backpath" ] ; then
    # Escape special symbols in database name
    dbnamef="${dbname//\\/\\\\}"
    dbnamef="${dbnamef//\$/\\$}"
    dbnamef="${dbnamef//\^/\\^}"
    dbnamef="${dbnamef//\./\\.}"
    dbnamef="${dbnamef//\*/\\*}"
    dbnamef="${dbnamef//\+/\\+}"
    dbnamef="${dbnamef//\?/\\?}"
    dbnamef="${dbnamef//\[/\\[}"
    # Find all backup files in backup directory
    mapfile -t files <<< $(find "$backpath" -maxdepth 1 -regex "^.+/pg\(dump\|inc\|delta\)_${dbnamef}_.+\.\(xz\|7z\|lrz\)$")
    ((bestdate=0))
    (( warnings = 0 ))
    {
	# Array pf will contain backup chains for each dump file
	declare -A pf
	# Array filesn is unsorted array of file dates
	# Array filess is sorted array of file dates
	# Array filessdesc contains corresponding human-readable items for menu
	filesn=()
	filess=()
	filessdesc=()
#	echo "Search dumps..."
	echo "$nls_3"
	for file in "${files[@]}" ; do
	    fd=$(GetDumpFileDate "$file")
	    if IsUint "$fd" ; then
		# Write name of file itself to the first cell of pf array
		pf["0$fd"]=$file
		filesn+=( "$fd" )
	    fi
	done
	# All dumps found, now we need to examine each dump name and build dump chains
#	echo "Building dump chains..."
	echo "$nls_63"
	for fd in "${filesn[@]}" ; do
	    # Select files by date: skip newer then $date and older then $datefrom
	    if (( $fd >= $datefrom )) && (( $fd <= $date )) ; then
		(( i=0 ))
		file="${pf[0$fd]}"
		while fdp=$(GetDumpFileDate "${pf[$i$fd]}" "parent"); do
		    # Parent date found, try to find its file
		    if [ -n "${pf[0$fdp]}" ]; then
			# Parent file is present in array
			ff="${pf[0$fdp]}"
		    else
			# Chain is broken
			#echo "Warning: file chain broken for dump made at $(DateToHuman $fd). This dump ignored"
			Printfn "$nls_4" "$(DateToHuman $fd)"
			(( warnings=1 ))
			continue 2
		    fi
		    # Write names of parent dumps to the next cells of pf array
		    (( i++ ))
		    pf["$i$fd"]=$ff
		done
		# Last array element must be a full dump, otherwise file chain is broken
		if [[ "${pf[$i$fd]}" =~ ^.*/pgdump_.*\.(xz|7z|lrz) ]] ; then
		    # All parent files found, store this file date and name as best suitable (at this stage), store depth of chain of parents in special pf array entry
		    if (( $fd >= $bestdate )) ; then
			((bestdate=$fd))
			bestfile="$file"
		    fi
		    pf["#$fd"]="$i"
		    # Find place in sorted array of dates and insert this date there
		    (( ai=0 ))
		    filedesc="$(DateToHuman $fd) $(GetDumpType $file)"
		    for (( ss=0 ; ss<${#filess[@]} ; ss++ )) ; do
			if (( $fd > ${filess[$ss]} )) ; then
			    ArrayInsert "filess" "$ss" "$fd"
			    ArrayInsert "filessdesc" "$ss" "$filedesc"
			    (( ai=1 ))
			    break
			fi
		    done
		    if (( $ai == 0 )) ; then
			# Append this date if all dates in array are earlier
			filess+=( "$fd" )
			filessdesc+=( "$filedesc" )
		    fi
		else
		    #echo "Warning: file chain broken for dump made at $(DateToHuman $fd). This dump ignored"
		    Printfn "$nls_4" "$(DateToHuman $fd)"
		    (( warnings=1 ))
		fi
	    fi
	done
	# Show all messages in progress box
    } > >(Progressbox)
    if (( $warnings == 1 )) ; then
	# Pause 10 sec to allow user to read warnings
	sleep 10
    fi
    if (( $bestdate == 0 )) ; then
	#Message "No dumps found"
	Message "$nls_5"
	exit 2
    fi
    if (( $nointer == 1 )) ; then
	selecteddate="$bestdate"
    else
	#if ! selecteddate="$(Menu "You may restore following dumps\nSelect one, please" "filess" "filessdesc" "--no-hot-list --no-tags --scrollbar")" ; then
	if ! selecteddate="$(Menu "$nls_6" "filess" "filessdesc" "--no-hot-list --no-tags --scrollbar")" ; then
	    #Message "Recovery canceled"
	    Message "$nls_7"
	    exit
	fi
    fi
    if [ -n "$savedumpto" ] ; then
	savedir="$savedumpto"
    elif [ -n "$restoretodb" ] ; then
	restname="$restoretodb"
    elif (( $nointer == 1 )) ; then
	restname="$(DecodeDbname "$dbname")"
    else
	# Show menu to allow user to select recovery options
	menutags=(0 1 2)
	#menuitems=("Save reconstructed full dump for manual restore" "Restore dump as new database" "Restore dump to original database")
	menuitems=("$nls_8" "$nls_9" "$nls_10")
	#if ! selected="$(Menu "Selected dump made at $(DateToHuman $selecteddate)\nSelect action, please" "menutags" "menuitems" "--no-hot-list --no-tags")" ; then
	if ! selected="$(Menu "$(Printfn "$nls_11" "$(DateToHuman $selecteddate)")" "menutags" "menuitems" "--no-hot-list --no-tags")" ; then
	    #Message "Recovery canceled"
	    Message "$nls_7"
	    exit
	fi
	case "$selected" in
	    0 )
		# Manual restore selected
		#if ! savedir="$(DSelect "Select directory to save dump file")" ; then
		if ! savedir="$(DSelect "$nls_12")" ; then
		    # User decided not to select directory
		    #Message "Recovery canceled"
		    Message "$nls_7"
		    exit
		fi
	    ;;
	    1 )
		# Restore as new database selected
		dbz=()
		GetDatabases "dbz" "e"
		if (( $? == 0 )) && [ -z "$e" ] ; then
		    while true ; do
			#if ! restname="$(Inputbox "Enter new name of restored database" "$(DecodeDbname "$dbname")_${selecteddate:2}")" ; then
			if ! restname="$(Inputbox "$nls_13" "$(DecodeDbname "$dbname")_${selecteddate:2}")" ; then
			    # User decided not to enter new name
			    #Message "Recovery canceled"
			    Message "$nls_7"
			    exit
			fi
			if FindInArray "$restname" "dbz" ; then
			    #if Message "--yesno" "Database \"$restname\" exists. Overwrite?" ; then
			    if Message "--yesno" "$(Printfn "$nls_14" "$restname")" ; then
				break
			    fi
			else
			    break
			fi
		    done
		else
		    Message "$e"
		    exit 9
		fi
		#if ! Message "--yesno" "This will create new database named \"$restname\". Are you sure?" ; then
		if ! Message "--yesno" "$(Printfn "$nls_15" "$restname")" ; then
		    #Message "Recovery canceled"
		    Message "$nls_7"
		    exit
		fi
	    ;;
	    2 )
		# Restore as original database selected
		# Replace "%1" to "_" and "%0" to "%"
		restname="$(DecodeDbname "$dbname")"
		#if ! Message "--yesno" "This will overwrite database named \"$restname\". Are you sure?" ; then
		if ! Message "--yesno" "$(Printfn "$nls_16" "$restname")" ; then
		    #Message "Recovery canceled"
		    Message "$nls_7"
		    exit
		fi
	    ;;
	esac
    fi
    # restore in temporary directory
    if [ -n "$savedir" ] ; then
	# Construct save filename
	savefilename="${savedir}/pgdump_${dbname}_${selecteddate:2}"
	# Append (digits) to pre-filled save filename if file already exists
	for k in {1..255} ; do
	    if ! [ -f "$savefilename($k)" ] ; then
		break
	    fi
	done
	if ! (( $nointer == 1 )) ; then
	    sfn="$savefilename"
	    while true ; do
		# Loop until user inputs non-existing filename or allows overwrite or presses cancel
		if [ -f "$sfn" ] ; then
		    #Message "--yesno" "File \"$sfn\" exists. Overwrite?" "--extra-button --extra-label Cancel"
		    Message "--yesno" "$(Printfn "$nls_17" "$sfn")" "--extra-button --extra-label $nls_18"
		    ee=$?
		    if (( $ee == 3 )) ; then
			# User decided to press Cancel
			#Message "Recovery canceled"
			Message "$nls_7"
			exit
		    elif (( $ee == 0 )) ; then
			# User allowed overwrire
			break
		    else
			# User decided not overwrite. Ask new fileneme.
			if nsfn="$(Inputbox "$nls_19" "$savefilename($k)")" ; then
			    sfn="$nsfn"
			fi
		    fi
		else
		    # File doesn't exist
		    break
		fi
	    done
	    savefilename="$sfn"
	fi
    fi
    tmppath=$(mktemp -d)
    trap "rm -r $tmppath" 0 2 3 15
    (( excode=0 ))
    for (( i="${pf[#$selecteddate]}"; i>=0; i-=1 )); do
	# Loop from the end of array because full dump is the last element
	cfile="${pf[$i$selecteddate]}"
	# Construct path relative to temporary directory
	cfilename=${cfile:${#backpath}}
	tmpfile="$tmppath$cfilename"
	# Copy compressed file to temporary directory
	#echo "Copying \"$cfile\" to \"$tmppath\"..."
	Printfn "$nls_20" "$cfile" "$tmppath"
	if cp "$cfile" "$tmpfile" 2>&1 && [ -f "$tmpfile" ] ; then
	    # Unpack it
	    #echo "Unpacking \"$tmpfile\"..."
	    Printfn "$nls_21" "$tmpfile"
	    if utmpfile=$(Extract "$tmpfile") && [ -f "$utmpfile" ] ; then
		#  Apply patch to the result of previous stage if it is not first stage
		if [ -n "$utmpfileprev" ] ; then
		    utmpfilecur="${utmpfile}_$i"
		    #echo "Patching with \"$utmpfile\"..."
		    Printfn "$nls_22" "$utmpfile"
		    if rdiff patch "$utmpfileprev" "$utmpfile" "$utmpfilecur" && [ -f "$utmpfilecur" ] ; then
			# Remove intermediate results
			rm -f "$utmpfileprev"
			rm -f "$utmpfile"
			utmpfileprev="$utmpfilecur"
		    else
			Message "$nls_23"
			(( excode=6 ))
			break
		    fi
		else
		    # On first stage set file itself (full dump) as result
		    utmpfileprev="$utmpfile"
		    utmpfilecur="$utmpfile"
		fi
	    else
		#Message "Error unpacking compressed dump file"
		Message "$nls_24"
		(( excode=5 ))
		break
	    fi
	else
	    #Message "Error copying compressed dump file to temporary folder"
	    Message "nls_25"
	    (( excode=4 ))
	    break
	fi
    done > >(Progressbox)
    if (( $excode == 0 )) ; then
	# Full dump reconstructed, it is time to apply it
	if [ -n "$savedir" ] ; then
	    {
		# Save result to chosen directory
		#echo "Copying result to \"$savefilename\"..."
		Printfn "$nls_26" "$savefilename"
		if cp "$utmpfilecur" "$savefilename" 2>&1 && [ -f "$savefilename" ] ; then
		    #echo "Dump prepared for manual restore copied to \"$savefilename\""
		    Printfn "$nls_27" "$savefilename"
		else
		    #echo "Error copying result to \"$savedir\" directory"
		    Printfn "$nls_28" "$savedir"
		    (( excode=8 ))
		fi
	    } > >(Progressbox)
	elif [ -n "$restname" ] ; then
	    {
		# Using postgres to restore database
		# Firstly comment out in dump file all DROP/CREATE/ALTER DATABASE and \connect statements because they may relate to wrong database
		# Note: multiline statements not yet supported (hope pgdump will never produce them)
		#echo "Removing DROP/CREATE DATABASE statements from dump file..."
		echo "$nls_29"
		dbname0="$(DecodeDbname "$dbname")"
		# Read first 50 lines of dump file
		mapfile -n 50 -t headlines < "$utmpfilecur"
		reh="(^[[:space:]]*DROP (DATABASE|DATABASE IF EXISTS)) ($dbname0|\"$dbname0\"|'$dbname0')( .*;$|;$)"
		reh0="(^[[:space:]]*(CREATE|ALTER) DATABASE) ($dbname0|\"$dbname0\"|'$dbname0')( .*;$|;$)"
		reh1="(^[[:space:]]*(ALTER ROLE) .* IN DATABASE) ($dbname0|\"$dbname0\"|'$dbname0')( .*;$|;$)"
		reh2="(^[[:space:]]*(CONNECT) TO) ($dbname0|\"$dbname0\"|'$dbname0')( .*;$|;$)"
		reh3="(^[[:space:]]*\\\\(connect|c)) ($dbname0|\"$dbname0\"|'$dbname0')( .*$|$)"
		for headline in "${headlines[@]}" ; do
		    if [[ "$headline" =~ $reh ]] ; then
			# Replace dump line with comment of the same length
			headlines1+="--${headline:2}"$'\n'
		    elif [[ "$headline" =~ $reh0 ]] || [[ "$headline" =~ $reh1 ]] || [[ "$headline" =~ $reh2 ]] || [[ "$headline" =~ $reh3 ]] ; then
			# Construct new command with actual database name
			pgcmd+="${BASH_REMATCH[1]} \"$restname\"${BASH_REMATCH[4]}"$'\n'
			# Replace dump line with comment of the same length
			headlines1+="--${headline:2}"$'\n'
		    else
			# Write dump line as is if no dangerous statement found
			headlines1+="$headline"$'\n'
		    fi
		done
		if [ -n "$headlines1" ] ; then
		    # Remove last newline from $headlines1
		    headlines1=${headlines1::-1}
		    # Owerwrite first 50 dump lines
		    dd of="$utmpfilecur" conv=notrunc status=none <<< "$headlines1"
		    edd="$?"
		    if ! (( $edd == 0 )) ; then
			#echo "Error removing DROP/CREATE DATABASE statements from dump file"
			echo "$nls_30"
			(( excode=$edd ))
		    fi
		fi
		if [ -z "$pgcmd" ] ; then
		    #echo $'Dump file does not contain CREATE DATABASE statement.\nAutomatic recovery is impossible'
		    echo "nls_64"
		    (( excode=14 ))
		fi
		# Add set output format wrapped statement to avoid truncating
		pgcmd="\\pset pager off \\pset format wrapped \\\\ $pgcmd"
	    } > >(Progressbox)
	    if (( $excode == 0 )) ; then
		# Try to drop database if exists
		if (( $logger == 1 )) ; then
		    psql -U "$pguser" -w -b &> >(Log) <<< "DROP DATABASE IF EXISTS \"$restname\";"
		else
		    psql -U "$pguser" -w -b &> /dev/null <<< "DROP DATABASE IF EXISTS \"$restname\";"
		fi
		# Test if database still exists
		if GetDatabases "dbb" "e" && [ -z "$e" ] ; then
		    if FindInArray "$restname" "dbb" ; then
			#if Message "--yesno" "Error removing database \"$restname\". Remove forcedly?" ; then
			if Message "--yesno" "$(Printfn "$nls_54" "$restname")" ; then
			    psql -U "$pguser" -w -b &>> "$lfile" <<< "DROP DATABASE IF EXISTS \"$restname\" WITH (FORCE);" 
			    # Once more test if database still exists
			    if GetDatabases "dbb" "e" && [ -z "$e" ] ; then
				if FindInArray "$restname" "dbb" ; then
				    #Message "Unable to remove database \"$restname\". Recovery canceled"
				    Message "$(Printfn "$nls_55" "$restname")"
				    (( excode=13 ))
				fi
			    else
				Message "$nls_56"
				(( excode=12 ))
			    fi
			else
			    # User decided to press No
			    #Message "Recovery canceled"
			    Message "$nls_7"
			    (( excode=3 ))
			fi
		    fi
		else
		    Message "$nls_56"
		    (( excode=12 ))
		fi
		if (( $excode == 0 )) ; then
		    {
			# Apply constructed CREATE/ALTER DATABASE commands
			#echo "Creating new empty database \"$restname\"..."
			Printfn "$nls_31" "$restname"
			psql -U "$pguser" -w -b 2>&1 <<< "$pgcmd" 
			ep="$?"
			if ! (( $ep == 0 )) ; then
			    #echo "Error creating database \"$restname\""
			    Printfn "$nls_32" "$restname"
			    (( excode=$ep ))
			fi
			if (( $excode == 0 )) ; then
			    # Process dump file
			    #echo "Copying data from dump to database \"$restname\"..."
			    Printfn "$nls_33" "$restname"
			    psql -U "$pguser" -w -b -d "$restname" -f "$utmpfilecur" 2>&1
			    ep="$?"
			    if ! (( $ep == 0 )) ; then
				#echo "Error copying data to database \"$restname\""
				Printfn "$nls_34" "$restname"
				(( excode=$ep ))
			    fi
			fi
			if ! (( $excode == 0 )) ; then
			    # Something went wrong. Check whether database exists
			    if GetDatabases "dbb" "e" && [ -z "$e" ] ; then
				if FindInArray "$restname" "dbb" ; then
				    #echo "Database \"$restname\" restored but may contain errors"
				    Printfn "$nls_35" "$restname"
				    restoredwitherrors=1
				else
				    #echo "Database \"$restname\" not restored"
				    Printfn "$nls_36" "$restname"
				fi
			    else
				#echo "Database \"$restname\" not restored"
				Printfn "$nls_36" "$restname"
			    fi
			else
			    #echo "Database \"$restname\" successfully restored"
			    Printfn "$nls_37" "$restname"
			fi
		    } > >(Progressbox)
		fi
	    fi
	fi
    fi
    if [ -n "$restoredwitherrors" ] ; then
	if (( $nointer == 1 )) ; then
	    psql -U "$pguser" -w -b -c "DROP DATABASE \"$restname\";" 2>&1
	else 
	    sleep 3
	    #if Message "--yesno" "Database \"$restname\" restored with errors and may be unusable. Remove it?" ; then
	    if Message "--yesno" "$(Printfn "$nls_38" "$restname")" ; then
		{    
		    if psql -U "$pguser" -w -b -c "DROP DATABASE \"$restname\";" 2>&1 ; then
			#echo "Database \"$restname\" removed"
			Printfn "$nls_39" "$restname"
		    else
			#echo "Error removing database \"$restname\". Remove it manually"
			Printfn "$nls_40" "$restname"
		    fi
		} > >(Progressbox)
	    fi
	fi
    fi
    exit $excode
else
    #Message "No dumps found"
    Message "$nls_5"
    exit 2
fi
