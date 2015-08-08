#!/bin/bash
##############################################################################
#    MacTomb                                                            #
#    Copyright (C) 2015  Davide `Anathema` Barbato                           #
#                                                                            #
#    This program is free software; you can redistribute it and/or modify    #
#    it under the terms of the GNU General Public License as published by    #
#    the Free Software Foundation; either version 3 of the License.          #
#                                                                            #
#    This program is distributed in the hope that it will be useful,         #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of          #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           #
#    GNU General Public License for more details.                            #
#                                                                            #
#    You should have received a copy of the GNU General Public License       #
#    along with this program; if not, write to the Free Software Foundation, #
#    Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA       #
##############################################################################

banner() {
	echo "..:: MacTomb v.$VERSION ::.."
	echo -e "by Davide Barbato\n"
}

e_echo() {
	echo -e "[x] $1"
}

s_echo() {
	echo -e "[*] $1"
}

usage() {
	banner
	echo -e "Usage:"
	echo -e "${0} <${COMMAND[@]}> -n\n"
	echo -e "-n\tMac OS X Notification"
	echo -e "Use 'help' to show a detailed help"
}

help() {
	banner
	echo "Help!"
	echo -e '''
create:
  -f <file>\t\tFile to create (the mactomb file)
  -s <size[m|g|t]\tSize of the file (m=mb, g=gb, t=tb)
  Optional:
    -p <profile>\tFolder/file to copy into the newly created mactomb file <file>\n
app:
  -f <file>\tEncrypted DMG to use as mactomb file
  -a <app>\tBinary of the app you want to use inside the mactomb file
  -o <output>\tThe bash output script used to launch the <app> inside the mactomb file <file>\n
forge:
  Will call both "create" and "app", so the flags are the same.
  Optional:
    -s <output>\tThe output Automator script used to launch the bash <output> script by Mac OS X
	'''
	return 2
}

check_size() {
	local dim=${SIZE:~0}
	local size=${SIZE%?}

	# check if the size ends with a well know character and if it's a number
	if [[ "(m, g, t)" =~ "$dim" ]] && [[ "$size" =~ ^[0-9]+$ ]]; then
		return 0
	fi

	return 1
}

resize() {
	if [[ ! "${FILENAME}" || ! "${SIZE}" ]]; then
		E_MESSAGE="Please specify the filename (-f) and the size (-s)"
		return 1
	fi

	if [ ! -e "${FILENAME}" ]; then
		E_MESSAGE="Cannot find $FILENAME"
		return 1
	fi

	check_size
	if [ "$?" -eq 1 ]; then
		E_MESSAGE="Wrong size numer!"
		return 1
	fi

	num=${SIZE%?}
	new_size=$(( ($num*1024)*1024 ))

	# risky...but nice!
	eval $(stat -s "$FILENAME")

	echo $new_size
	echo $st_size
    
    if [ $new_size -lt $st_size ]; then
    	param="-shrinkonly"
    elif [ $new_size -gt $st_size ]; then
    	param="-growonly"
    else
    	E_MESSAGE="Size is the same. Not resizing"
    	return 1
    fi

    ${HDIUTIL} resize -size ${SIZE} ${param} "${FILENAME}"

    if [ "$?" -ne 0 ]; then
    	E_MESSAGE="Mactomb file '$FILENAME' not resized"
   		return 1
    fi

    S_MESSAGE="Mactomb file '$FILENAME' succesfully resized!"
    return 0
}

create() {
	E_MESSAGE="Failed creating the mactomb file '${FILENAME}': "

	if [[ ! "${FILENAME}" || ! "$SIZE" ]]; then
		E_MESSAGE+="You must specify a filename and/or a size!"
		return 1
	fi

	if [ -e "${FILENAME}" ]; then
		E_MESSAGE+="File arealdy exists!"
		return 1
	fi

	check_size
	if [ $? -eq 1 ]; then
		E_MESSAGE+="Wrong size number!"
		return 1
	fi

	r=`${HDIUTIL} create "$FILENAME" -encryption "$ENC" -size "$SIZE" -fs "$FS" -nospotlight`

	if [[ "$r" =~ "failed" || "$r" =~ "error" ]]; then
		return 1
	fi

	if [[ "$PROFILE" ]]; then
		s_echo "tombfile '${FILENAME}' successfully created!"
		echo -e "\nCopying profile file(s) into the mactomb..."

		r=$(${HDIUTIL} attach "${FILENAME}")

		vol=$(grep "/Volumes" <<< "$r" | awk -F ' ' '{print $3}')

		# enforce a check - don't trust hdiutil output
		if [[ "$vol" =~ "/Volumes/" ]]; then
			if [ -e "$PROFILE" ]; then
				cp -rv "$PROFILE" "$vol"
				s_echo "\nFile(s) successfully copied!"
			else
				e_echo "Cannot find $PROFILE. File(s) not copied."
			fi
			# meh. it's ok to have two times the same message
			S_MESSAGE="mactomb file '${FILENAME}' successfully created!"
			# I really don't care about the exit status.
			${HDIUTIL} detach "$vol" &> /dev/null
		else
			E_MESSAGE="Problem mounting the mactomb file."
			return 1
		fi
	fi

	return 0
}

app() {
	if [[ ! "$APPPATH" || ! "OUTSCRIPT" || ! "$FILENAME" ]]; then
		E_MESSAGE="Please specify -a -o -f."
		return 1
	fi

	if  [ ! -e "${FILENAME}" ]; then
		E_MESSAGE+="$FILENAME file not found."
		return 1
	fi

	if [ ! -e "$APPPATH" ]; then
		E_MESSAGE="Cannot find $APPPATH."
		return 1
	fi

	if [ -e "$OUTSCRIPT" ]; then
		E_MESSAGE="$OUTSCRIPT already exists."
		return 1
	fi

	# ensure absolute path for the mactomb file
	if [[ $(dirname "$FILENAME") == "." ]]; then
		FILENAME="$(PWD)"/"${FILENAME}"
	fi

	# ensure absolute path for the app
	if [[ $(dirname "$APPPATH") == "." ]]; then
		APPPATH="$(PWD)"/"${APPPATH}"
	fi

	$(cat << EOF > "$OUTSCRIPT"
#!/bin/bash
if [ -e "$FILENAME" ]; then
	${HDIUTIL} attach "$FILENAME"
	if [ \$? -eq 0 ]; then
		$APPPATH
	fi
fi)

	S_MESSAGE="File $OUTSCRIPT successfully created!"
	return 0
}

forge() {
	s_echo "Creating the mactomb file..."
	create
	if [ "$?" -eq 1 ]; then
		return 1
	fi

	s_echo "Creating the output script..."
	app
	if [ "$?" -eq 1 ]; then
		return 1
	fi

	s_echo "Creating the Automator script to call the output script..."

	base_filename=$(basename "$FILENAME")
	# stripping the dmg extension and adding the automator extension (.app)
	automatr="${base_filename%.dmg}.app"

	# keep the template safe
	cp -r "$AUTOMATOR" "$automatr"

	# ensure absolute path for the output script
	if [[ $(dirname "$OUTSCRIPT") == "." ]]; then
		OUTSCRIPT="$(PWD)"/"${OUTSCRIPT}"
	fi

	# let's the magic happen!
	sed -i '' -e "s@SCRIPT_TO_RUN@$OUTSCRIPT@" "${automatr}/Contents/document.wflow"

	S_MESSAGE="Mactomb forged! Now double click on $automatr to start your app inside the mactomb."
	return 0
}

COMMAND=('create', 'app', 'help', 'forge', 'resize')
HDIUTIL=/usr/bin/hdiutil
# if 1, the script will use the Mac OS X notification method
NOTIFICATION=0
ENC="AES-256"
FS="HFS+"
# path to the app used for the script
APPPATH=""
# output script for automatically call the app defined in APPPATH
OUTSCRIPT=""
# automator template
AUTOMATOR="template.app"
VERSION=0.1
CMD=$1
shift

while getopts "a:f:s:p:o:nh" opt; do
	case "${opt}" in
		f)
			FILENAME=$OPTARG;;
		s)
			SIZE=$OPTARG;;
		n)
			NOTIFICATION=1;;
		a)
			APPPATH=$OPTARG;;
		p)
			PROFILE=$OPTARG;;
		o)
			OUTSCRIPT=$OPTARG;;
		v)
			VERBOSE=1;;
	   \?)
			e_echo "Invalid option: -$OPTARG" >&2;;
    esac
done

if [[ ! "${COMMAND[@]}" =~ "${CMD}" ]]; then
	usage
	exit 1
fi

$CMD
ret=$?

if [ "$NOTIFICATION" -eq 1 ]; then
		if [ "$ret" -eq 0 ]; then
			osascript -e 'display notification "'"${S_MESSAGE}"'" with title "MacTomb" subtitle "'${CMD}'"'
		else
			osascript -e 'display notification "'"${E_MESSAGE}"'" with title "MacTomb" subtitle "'${CMD}'"'
		fi
else
	if [ "$ret" -eq 1 ]; then
		e_echo "${E_MESSAGE}"
	# enforce check to 0 if we want some commands not to return a message (like 'help')
	elif [ "$ret" -eq 0 ]; then
		s_echo "${S_MESSAGE}"
	fi
fi