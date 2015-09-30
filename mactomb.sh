#!/bin/bash
##############################################################################
#    MacTomb                                                                 #
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
	echo -e "${0} <${COMMAND[@]}> -v\n"
	echo -e "-v\tMac OS X Notification"
	echo -e "Use 'help' to show the full help"
}

help() {
	banner
	echo "Help!"
	echo -e '''
create:
  -f <file>\t\tFile to create (the mactomb file)
  -s <size[m|g|t]\tSize of the file (m=mb, g=gb, t=tb)
  Optional:
    -p <profile>\tFolder/file to copy into the newly created mactomb <file>
    -n <volname>\tSpecify the volume name to assign to the mactomb <file>\n
app:
  -f <file>\tEncrypted DMG to use as mactomb file (already created)
  -a <app>\tBinary and arguments of the app you want to use inside the mactomb file
  -b <output>\tThe bash script used to launch the <app> inside the mactomb file <file>\n
forge:
  Will call both "create" and "app" if all flags are specified. Can be called on \n  already created files, in this case skipping "create" and/or "app"
  Optional:
    -o <output>\tThe Automator app used to launch the bash <output> script by Mac OS X
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
		E_MESSAGE="You must specify a filename and/or a size!"
		return 1
	fi

	if [ -d "${FILENAME}" ]; then
		E_MESSAGE+="File is a directory"
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

	r=$(${HDIUTIL} create "$FILENAME" -encryption "$ENC" -size "$SIZE" -fs "$FS" -nospotlight -volname $VOLNAME 2>&1)

	if [[ "$r" =~ "failed" || "$r" =~ "error" || "$r" =~ "canceled" ]]; then
		E_MESSAGE+=$r
		return 1
	fi

	# ensure FILENAME ends in dmg
	if [[ "${FILENAME##*.}" != "dmg" ]]; then
		FILENAME+=".dmg"
	fi	

	s_echo "mactomb file '${FILENAME}' successfully created!"

	if [[ "$PROFILE" ]]; then
		echo -e "\nCopying profile file(s) into the mactomb..."

		r=$(${HDIUTIL} attach "${FILENAME}")

		abs_vol_path="/Volumes/$VOLNAME"
		# enforce a check - don't trust hdiutil
		if [[ -d  "$abs_vol_path" ]]; then
			# do not let the script fails if cp fails
			if [ -e "$PROFILE" ]; then
				cp -rv "$PROFILE" "$abs_vol_path"
				echo
				if [ "$?" -eq 1 ]; then
					e_echo "File(s) not copied!"
				else
					s_echo "File(s) successfully copied!"
				fi
			else
				e_echo "Cannot find $PROFILE. File(s) not copied."
			fi
			# meh. it's ok to have two times the same message
			S_MESSAGE="mactomb file '${FILENAME}' successfully created!"
			# I really don't care about the exit status.
			${HDIUTIL} detach "$abs_vol_path" &> /dev/null
		else
			E_MESSAGE="Problem mounting the mactomb file, file(s) not copied."
			return 1
		fi
	fi

	return 0
}

app() {
	E_MESSAGE="Failed creating the script: "
	if [[ ! "$APPCMD" || ! "$BASHSCRIPT" || ! "$FILENAME" ]]; then
		E_MESSAGE="Please specify -a -b -f."
		return 1
	fi

	if  [ ! -e "${FILENAME}" ]; then
		E_MESSAGE+="$FILENAME file not found."
		return 1
	fi

	# check if we included a command (with spaces) or a binary path
	read -ra app_arr -d '' <<< "$APPCMD"

	if [ ! -e "${app_arr[0]}" ]; then
		E_MESSAGE+="Cannot find ${app_arr[0]}."
		return 1
	fi

	if [ -d "${BASHSCRIPT}" ]; then
		E_MESSAGE+="$BASHSCRIPT is a directory."
		return 1
	fi

	if [ -e "${BASHSCRIPT}" ]; then
		E_MESSAGE+="$BASHSCRIPT already exists."
		return 1
	fi

	# ensure absolute path for the mactomb file
	if [[ $(dirname "$FILENAME") == "." ]]; then
		FILENAME="$(PWD)"/"${FILENAME}"
	fi

	# ensure absolute path for the app
	if [[ $(dirname "$APPCMD") == "." ]]; then
		APPCMD="$(PWD)"/"${APPCMD}"
	fi

	if [ -e "${APPCMD}" ]; then
		E_MESSAGE+="$APPCMD already exists."
		return 1
	fi

	if [ -e "${APPCMD}" ]; then
		E_MESSAGE+="$APPCMD is a directory"
		return 1
	fi 

	abs_vol_path="/Volumes/$VOLNAME"
	for i in ${!app_arr[@]}; do
		if [[ "${app_arr[$i]}" =~ "\$VOLNAME" ]]; then
			app_arr[$i]=$(sed -e "s@\$VOLNAME@$abs_vol_path@" <<< ${app_arr[$i]})
		fi
	done

	$(cat << EOF > "$BASHSCRIPT"
#!/bin/bash
if [ -e "$FILENAME" ]; then
	${HDIUTIL} attach "$FILENAME"
	if [ \$? -eq 0 ]; then
		${app_arr[@]}
		${HDIUTIL} detach "$abs_vol_path"
	fi
fi)

	# ensure our bash script is executable
	chmod +x "$BASHSCRIPT"
	S_MESSAGE="File $BASHSCRIPT successfully created!"
	return 0
}

forge() {
	E_MESSAGE="Tell me what to do!"

	if [[ "${FILENAME}" && "$SIZE" ]]; then
		s_echo "Creating the mactomb file..."
		create
		if [ "$?" -eq 1 ]; then
			return 1
		fi
	fi

	if [[ "$APPCMD" && "$BASHSCRIPT" && "$FILENAME" ]]; then
		s_echo "Creating the output script..."
		app
		if [ "$?" -eq 1 ]; then
			return 1
		fi
	fi

	if [[ "$OUTSCRIPT" ]]; then
		# we can't create the Automator app without bash script!
		if [[ ! "$BASHSCRIPT" ]]; then
			E_MESSAGE="No bash script set. Please use the -b flag"
			return 1
		fi

		s_echo "Creating the Automator app to call the output script..."

		# ensure we have the .app extension to let Mac recognise it as app
		if [[ "${OUTSCRIPT##*.}" != "app" ]]; then
			OUTSCRIPT+=".app"
		fi

		# ensure absolute path for the output app
		if [[ $(dirname "$OUTSCRIPT") == "." ]]; then
			OUTSCRIPT="$(PWD)"/"${OUTSCRIPT}"
		fi

		if [ -e "$OUTSCRIPT" ]; then
			E_MESSAGE="$OUTSCRIPT already exists."
			return 1
		fi

		if [ -d "$OUTSCRIPT" ]; then
			E_MESSAGE="$OUTSCRIPT is a directory."
			return 1
		fi

		# keep the template safe
		cp -r "$AUTOMATOR" "${OUTSCRIPT}"

		# let's the magic happen!
		sed -i '' -e "s@SCRIPT_TO_RUN@$BASHSCRIPT@" "${OUTSCRIPT}/Contents/document.wflow"

		S_MESSAGE="Mactomb forged! Now double click on $automatr to start your app inside the mactomb."

		return 0
	fi

	return 1
}

COMMAND=('create', 'app', 'help', 'forge', 'resize')
HDIUTIL=/usr/bin/hdiutil
# if 1, the script will use the Mac OS X notification method
NOTIFICATION=0
ENC="AES-256"
FS="HFS+"
# path to the app used for the script
APPCMD=""
# output script for automatically call the app defined in APPCMD
BASHSCRIPT=""
# output Automator app that is in charge to call $BASHSCRIPT
OUTSCRIPT=""
# automator template
AUTOMATOR="template.app"
# default volume name for HFS+. Change this if you don't like it
VOLNAME="untitled"
VERSION=1.1
CMD=$1
shift

while getopts "a:f:s:p:o:b:n:h" opt; do
	case "${opt}" in
		f)
			FILENAME=$OPTARG;;
		s)
			SIZE=$OPTARG;;
		n)
			VOLNAME=$OPTARG;;
		a)
			APPCMD=$OPTARG;;
		p)
			PROFILE=$OPTARG;;
		b)
			BASHSCRIPT=$OPTARG;;
		o)
			OUTSCRIPT=$OPTARG;;
		v)
			NOTIFICATION=1;;
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