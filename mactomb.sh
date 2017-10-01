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
list:
   list all opened mactombs\n
chpass:
  -f <file>\t\tChange passphrase of mactomb <file>\n
compress:
  -f <file>\t\tCompress a mactomb <file> (will make it read-only)\n
decompress:
  -f <file>\t\tDecompress a mactomb <file>\n
rename:
  -f <file>\t\tmactomb file (already created)
  Optional:
    -n <volname>\tSpecify the new volume name to assign to the mactomb <file> (default is "untitled")
    -b <script>\tThe bash script in which replaces all the occurence of the old volum name with the new one\n
create:
  -f <file>\t\tFile to create (the mactomb file)
  -s <size[m|g|t]\tSize of the file (m=mb, g=gb, t=tb)
  Optional:
    -p <profile>\tFolder/file to copy into the newly created mactomb <file>
    -c\t\t\tCreate a zlib compressed mactomb <file> (will make it read-only)
    -n <volname>\tSpecify the volume name to assign to the mactomb <file>\n
app:
  -f <file>\tEncrypted DMG to use as mactomb file (already created)
  -a <app>\tBinary and arguments of the app you want to use inside the mactomb file
  -b <script>\tThe bash script used to launch the <app> inside the mactomb file <file>\n
forge:
  Will call both "create" and "app" if all flags are specified. Can be called on \n  already created files, in this case skipping "create" and/or "app"
  Optional:
    -o <app>\tThe Automator app used to launch the bash <output> script by Mac OS X
mount:
  Mount mactomb to file system
  -f <file>\tEncrypted DMG to use as mactomb file (already created)
  -m <path>\tMount at <path> instead of inside /Volumes
unmount:
  Unmount mactomb volume
  -f <file>\tMactomb file to unmount
	'''
	return 2
}

compression_banner() {
	echo '''
##################################################
#                  WARNING                       #
#                                                #
#  Compression will make the mactomb read-only   #
#                                                #
##################################################
		'''
}

decompression_banner() {
	echo '''
##################################################
#                  WARNING                       #
#                                                #
#  Decompression will overwrites your compressed #
#                  mactomb                       #
#                                                #
##################################################
		'''
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

list() {
	local PLISTBUDDY="/usr/libexec/PlistBuddy"
	# colours! even if I don't need all of them...colours!
	local BLUE="\x1b[0;34m"
	local RED="\x1b[0;31m"
	local GREEN="\x1b[0;32m"
	local YELLOW="\x1b[1;33m"
	local WHITE="\x1b[1;37m"
	local LIGHT_RED="\x1b[1;31m"
	local LIGHT_GREEN="\x1b[1;32m"
	local LIGHT_BLUE="\x1b[1;34m"
	local LIGHT_CYAN="\x1b[1;36m"
	local NO_COLOUR="\x1b[0m"
	local mountpoint mnt space_tot used avail perc oid

	if [ ! -x "$PLISTBUDDY" ]; then
		E_MESSAGE="PlistBuddy not found in $PLISTBUDDY. Maybe it's on a different path or not installed?"
		return 1
	fi

	local tempfile=$(mktemp /tmp/$RANDOM.XXX)
	${HDIUTIL} info -plist > $tempfile

	local -i idx=0
	local -i cnt=0
	local compressed="No"
	while True; do
		imgpath=$(${PLISTBUDDY} -c Print:images:$idx:image-path $tempfile 2>/dev/null)
		if [ ! "$imgpath" ]; then
			break
		fi

		encrypted=$(${PLISTBUDDY} -c Print:images:$idx:image-encrypted $tempfile)
		removable=$(${PLISTBUDDY} -c Print:images:$idx:removable $tempfile)
		writeable=$(${PLISTBUDDY} -c Print:images:$idx:writeable $tempfile)
		imgtype=$(${PLISTBUDDY} -c Print:images:$idx:image-type $tempfile)
		oid=$(${PLISTBUDDY} -c Print:images:$idx:owner-uid $tempfile)

		local out=$(dscl . -search /Users UniqueID $oid)
		local owner=$(cut -d ' ' -f1 <<< $out)

		local -i j=0
		while True; do
			mountpoint=$(${PLISTBUDDY} -c Print:images:$idx:system-entities:$j $tempfile 2>/dev/null)
			if [ ! "$mountpoint" ]; then
				# we can skip the while loop since it means there are no system-entities left
				# then it doesn't contain the mount-point for sure 
				break
			fi

			mountpoint=$(${PLISTBUDDY} -c Print:images:$idx:system-entities:$j:mount-point $tempfile 2>/dev/null)
			# mount-point is not mandatory inside system-entities
			if [ "$mountpoint" ]; then
				read -ra space_tot -d ''<<< $(df -h "$mountpoint" | awk -F ' ' '{print $2}')
				read -ra used -d '' <<< $(df -h "$mountpoint" | awk -F ' ' '{print $3}')
				read -ra avail -d '' <<< $(df -h "$mountpoint" | awk -F ' ' '{print $4}')
				read -ra perc -d '' <<< $(df -h "$mountpoint" | awk -F ' ' '{print $5}')
				# pretty lame...
				mnt=$mountpoint
			fi
			j+=1
		done

		# assume that macbombs are encrypted, removable and writable.
		# it's too loose, but for now it's ok
		if [[ "$encrypted" == "true" && "$removable" == "true" ]] && [[ "$writeable" == "true" || "$imgtype" =~ "compressed" ]]; then
			echo "***************"
			echo -e "${GREEN}Image Path$NO_COLOUR:\t$imgpath"
			echo -e "${GREEN}Mount Point$NO_COLOUR:\t$mnt"
			if [[ "$imgtype" =~ "compressed" ]]; then
				compressed="Yes ($imgtype)"
			fi
			echo -e "${GREEN}Compressed$NO_COLOUR:\t$compressed"
			echo -e "${GREEN}${space_tot[0]}$NO_COLOUR:\t\t${space_tot[1]}"
			echo -e "${GREEN}${used[0]}$NO_COLOUR:\t\t${used[1]}"
			echo -e "${GREEN}${avail[0]}$NO_COLOUR:\t\t${avail[1]}"
			
			# it's nice to have different colours based on the percentage of used space
			if [ ${perc[1]%?} -ge 50 ] && [ ${perc[1]%?} -lt 80 ]; then
				local colour=${YELLOW}
			elif [ ${perc[1]%?} -ge 80 ]; then
				local colour=${RED}
			fi
			echo -e "${GREEN}${perc[0]}$NO_COLOUR:\t$colour${perc[1]}$NO_COLOUR"
			echo -e "${GREEN}Owner$NO_COLOUR:\t\t$owner"
			cnt+=1
		fi
		idx+=1
	done

	rm -rf $tempfile
	if [ $cnt -gt 0 ]; then
		echo
		S_MESSAGE="There are nr.$cnt mactomb(s) open"
	else
		S_MESSAGE="There are no mactombs opened"
	fi
	return 0
}

# this function can be used even for not-encrypted DMG
chpass() {
	E_MESSAGE="Cannot change passphrase: "

	if [ ! "${FILENAME}" ]; then
		E_MESSAGE="Please specify the filename (-f)"
		return 1
	fi

	if [ ! -e "${FILENAME}" ]; then
		E_MESSAGE+="'${FILENAME}' not found."
		return 1
	fi

	if [ -d "${FILENAME}" ]; then
		E_MESSAGE+="'${FILENAME}' is a directory."
		return 1
	fi

	local ret=$(${HDIUTIL} chpass "${FILENAME}" 2>&1)
	if [[ "$ret" =~ "chpass failed" ]]; then
		E_MESSAGE+="$ret"
		return 1
	fi

	S_MESSAGE="Successfully changed your passphrase!"
	return 0
}

# this function can be used even for not-encrypted DMG
rename() {
	E_MESSAGE="Cannot rename '$FILENAME': "
	if [ ! "${FILENAME}" ]; then
		E_MESSAGE="Please specify the filename (-f)"
		return 1
	fi

	if [ ! -e "${FILENAME}" ]; then
		E_MESSAGE+="file not found."
		return 1
	fi

	local ret disk oldlabel
	# if the mactomb is already mounted we don't want to unmount it
	# at the end of the renaming process
	local already_mounted=$(${HDIUTIL} info | grep "$FILENAME")

	# a quick check to avoid going through the process of renameing a compressed mactomb.
	# if the mactomb is mounted, this check fails.
	if [ ! "${already_mounted}" ]; then
		s_echo "Getting information..."
		ret=$(${HDIUTIL} imageinfo "${FILENAME}" 2>&1 | grep "Compressed:")
		if [[ "$ret" =~ "true" ]]; then
			E_MESSAGE+="compressed mactombs are read-only"
			return 1
		fi
	fi

	s_echo "Renaming to '$VOLNAME'"
	# if already attached we don't care, hdiutil is smart enough
	ret=$(${HDIUTIL} attach "${FILENAME}" 2>&1)
	if [[ "$ret" =~ "attach failed" ]]; then
		E_MESSAGE+=$ret
		return 1
	fi

	disk=$(grep Volumes <<< "$ret" | awk -F ' ' '{print $1}')
	oldlabel=$(grep Volumes <<< "$ret" | awk -F ' ' '{print $3}')
	oldlabel=$(basename $oldlabel)

	if [[ "$oldlabel" == "$VOLNAME" ]]; then
		if [ ! "$already_mounted" ]; then
			${HDIUTIL} detach "$disk" &> /dev/null
		fi
		E_MESSAGE+="same label"
		return 1
	fi
	
	ret=$(/usr/sbin/diskutil rename "${disk}" "${VOLNAME}" 2>&1)

	S_MESSAGE="Successfully renamed your mactomb!"

	if [ ! "$already_mounted" ]; then
		# we don't want to let it sits open on your system!
		${HDIUTIL} detach "$disk" &> /dev/null
	fi

	# this can happens if your mactomb is compressed and already mounted
	if [[ "$ret" =~ "Failed to rename volume" ]]; then
		E_MESSAGE+=$ret
		return 1
	fi

	if [ "$BASHSCRIPT" ]; then
		if [ ! -w "$BASHSCRIPT" ]; then
			e_echo "'$BASHSCRIPT' does not exist or you don't have write permission! Not editing"
		else
			# yes: it will automatically replace all the occurence of $oldlabel with $VOLNAME
			sed -i '' -e "s@$oldlabel@$VOLNAME@" "${BASHSCRIPT}"
		fi
	fi

	return 0
}

# this function can be used even for not-encrypted DMG
resize() {
	E_MESSAGE="Cannot resize '$FILENAME': "
	if [[ ! "${FILENAME}" || ! "${SIZE}" ]]; then
		E_MESSAGE="Please specify the filename (-f) and the size (-s)"
		return 1
	fi

	if [ ! -e "${FILENAME}" ]; then
		E_MESSAGE+="file not found."
		return 1
	fi

	if [ -d "${FILENAME}" ]; then
		E_MESSAGE+="is a directory."
		return 1
	fi

	check_size
	if [ "$?" -eq 1 ]; then
		E_MESSAGE+="wrong size numer!"
		return 1
	fi

	local num=${SIZE%?}
	local new_size=$(( ($num*1024)*1024 ))
	local param

	# risky...but nice!
	eval $(stat -s "$FILENAME")

	echo $new_size
	echo $st_size

	if [ $new_size -lt $st_size ]; then
		param="-shrinkonly"
	elif [ $new_size -gt $st_size ]; then
		param="-growonly"
	else
		E_MESSAGE+="size is the same. Not resizing"
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

compress() {
	E_MESSAGE="Failed compressing the mactomb file '${FILENAME}': "
	if [[ ! "${FILENAME}" ]]; then
		E_MESSAGE="You must specify a filename!"
		return 1
	fi

	if [ -d "${FILENAME}" ]; then
		E_MESSAGE+="file is a directory"
		return 1
	fi

	if [ ! -e "${FILENAME}" ]; then
		E_MESSAGE+="file not found."
		return 1
	fi

	compression_banner

	local tmp="/tmp/$RANDOM$RANDOM.dmg"

	s_echo "Compressing...(you'll asked to insert a new passphrase: choose a new one or insert the old one)"
	ret=$(${HDIUTIL} convert "${FILENAME}" -format $CFORMAT -imagekey zlib-level=$CLEVEL -o "${tmp}" -encryption "$ENC" 2>&1)
	if [[ "$ret" =~ "convert failed" || "$ret" =~ "convert canceled" ]]; then
		E_MESSAGE+=$ret
		return 1
	fi

	mv -f "$tmp" "${FILENAME}"
	S_MESSAGE="Mactomb file '${FILENAME}' successfully compressed!"
	return 0

}

decompress() {
	E_MESSAGE="Failed decompressing the mactomb file '${FILENAME}': "
	if [[ ! "${FILENAME}" ]]; then
		E_MESSAGE="You must specify a filename!"
		return 1
	fi

	if [ -d "${FILENAME}" ]; then
		E_MESSAGE+="file is a directory"
		return 1
	fi

	if [ ! -e "${FILENAME}" ]; then
		E_MESSAGE+="file not found."
		return 1
	fi

	decompression_banner

	local tmp="/tmp/$RANDOM$RANDOM.dmg"

	s_echo "Decompressing...(you'll asked to insert a new passphrase: choose a new one or insert the old one)"
	ret=$(${HDIUTIL} convert "${FILENAME}" -format UDRW -o "${tmp}" -encryption "$ENC" 2>&1)
	if [[ "$ret" =~ "convert failed" || "$ret" =~ "convert canceled" ]]; then
		E_MESSAGE+=$ret
		return 1
	fi

	mv -f "$tmp" "${FILENAME}"
	S_MESSAGE="Mactomb file '${FILENAME}' successfully decompressed!"
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

	if [[ -e "${FILENAME}" || -e "${FILENAME}".dmg ]]; then
		E_MESSAGE+="File already exists!"
		return 1
	fi

	check_size
	if [ $? -eq 1 ]; then
		E_MESSAGE+="Wrong size number!"
		return 1
	fi

	local ret

	ret=$(mount | grep "$VOLNAME")

	if [[ "$ret" ]]; then
		E_MESSAGE="Volume name '$VOLNAME' already used. Please pick up a different name (-n) or unmount it"
		return 1
	fi
	
	# this can be quite huge block to read but I was not able to find a more elegant solution

	if [[ "${COMPRESS}" -eq 1 && "${PROFILE}" ]]; then

		compression_banner
		
		s_echo "Creating, copying and compressing the mactomb..."
		ret=$(${HDIUTIL} create "$FILENAME" -encryption "$ENC" -size "$SIZE" -fs "$FS" -nospotlight -volname "$VOLNAME" \
			-format $CFORMAT -imagekey zlib-level=$CLEVEL -srcfolder ${PROFILE} 2>&1)
		if [[ "$ret" =~ "create failed" || "$ret" =~ "create canceled" ]]; then
			E_MESSAGE+=$ret
			return 1
		fi
		S_MESSAGE="mactomb file '${FILENAME}' successfully created!"
	elif [[ "${COMPRESS}" -eq 0 && "${PROFILE}" ]]; then
		s_echo "Creating the mactomb..."
		ret=$(${HDIUTIL} create "$FILENAME" -encryption "$ENC" -size "$SIZE" -fs "$FS" -nospotlight -volname "$VOLNAME" -attach 2>&1)
		if [[ "$ret" =~ "create failed" || "$ret" =~ "attach failed" || "$ret" =~ "create canceled" ]]; then
			E_MESSAGE+=$ret
			return 1
		fi
		
		s_echo "mactomb file '${FILENAME}' successfully created!"
		echo -e "\nCopying profile file(s) into the mactomb..."

		local abs_vol_path="/Volumes/$VOLNAME"
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
			# I really don't care about the exit status.
			${HDIUTIL} detach "$abs_vol_path" &> /dev/null
		else
			E_MESSAGE="Problem mounting the mactomb file, file(s) not copied."
			return 1
		fi
		S_MESSAGE="Enjoy your mactomb"
	elif [[ ! "${PROFILE}" && "${COMPRESS}" -eq 1 ]]; then

		compression_banner

		# problem is: if you specify -format UDZO, hdiutil requires -srcfolder to be set.
		# so we need to create a temp tomb and then compress (hdiutil convert)
		local tmp="/tmp/$RANDOM$RANDOM.dmg"

		# since 'convert' doesn't preserve encryption, let's create a normal container
		# that will be encrypted by 'convert'
		ret=$(${HDIUTIL} create "$tmp" -size "$SIZE" -fs "$FS" -nospotlight -volname "$VOLNAME" 2>&1)
		if [[ "$ret" =~ "create failed" || "$ret" =~ "create canceled" ]]; then
			rm -rf "${tmp}"
			E_MESSAGE+=$ret
			return 1
		fi

		ret=$(${HDIUTIL} convert "$tmp" -format $CFORMAT -imagekey zlib-level=$CLEVEL -o "${FILENAME}" -encryption "$ENC" 2>&1)
		if [[ "$ret" =~ "convert failed" || "$ret" =~ "convert canceled" ]]; then
			rm -rf "${tmp}"
			E_MESSAGE+=$ret
			return 1
		fi

		# removing the temp file
		rm -rf "${tmp}"
		S_MESSAGE="mactomb file '${FILENAME}' successfully created!"
	else
		ret=$(${HDIUTIL} create "$FILENAME" -encryption "$ENC" -size "$SIZE" -fs "$FS" -nospotlight -volname "$VOLNAME" 2>&1)
		if [[ "$ret" =~ "create failed" || "$ret" =~ "create canceled" ]]; then
			E_MESSAGE+=$ret
			return 1
		fi
		S_MESSAGE="mactomb file '${FILENAME}' successfully created!"
	fi
	
	return 0
}

mount() {
	if [[ ! "${FILENAME}" ]]; then
		E_MESSAGE="You must specify a filename!"
		return 1
	fi

	if [ -d "${FILENAME}" ]; then
		E_MESSAGE+="File is a directory"
		return 1
	fi

	if [ -e "$FILENAME" ]; then
		local ret
		if [[ "$MOUNTPOINT" && -d "$MOUNTPOINT" ]]; then
			ret=$(${HDIUTIL} attach "${FILENAME}" -mountpoint "${MOUNTPOINT}" 2>&1)
		else
			ret=$(${HDIUTIL} attach "${FILENAME}" 2>&1)
		fi
		
		if [[ "$ret" =~ "attach failed" ]]; then
			E_MESSAGE+=$ret
			return 1
		fi
		S_MESSAGE="Mactomb ${FILENAME} was successfully mounted "
		return 0
	fi
	E_MESSAGE="Cannot find file ${FILENAME}"
	return 1
}

unmount() {
	if [[ ! "${FILENAME}" ]]; then
		E_MESSAGE="You must specify a filename!"
		return 1
	fi

	if [ -d "${FILENAME}" ]; then
		E_MESSAGE+="File is a directory"
		return 1
	fi

	local PLISTBUDDY="/usr/libexec/PlistBuddy"

	if [ ! -x "$PLISTBUDDY" ]; then
		E_MESSAGE="PlistBuddy not found in $PLISTBUDDY. Maybe it's on a different path or not installed?"
		return 1
	fi

	local mountpoint mnt ret
	# Small workaraund to get real mactomb path
	local real_path=$(cd "$(dirname $FILENAME)"; pwd)/$(basename $FILENAME)
	local tempfile=$(mktemp /tmp/$RANDOM.XXX)
	${HDIUTIL} info -plist > $tempfile

	local -i idx=0
	while True; do
		imgpath=$(${PLISTBUDDY} -c Print:images:$idx:image-path $tempfile 2>/dev/null)
		if [ ! "$imgpath" ]; then
			break
		fi
		
		local -i j=0
		while True; do
			mountpoint=$(${PLISTBUDDY} -c Print:images:$idx:system-entities:$j $tempfile 2>/dev/null)
			if [ ! "$mountpoint" ]; then
				break
			fi
			mountpoint=$(${PLISTBUDDY} -c Print:images:$idx:system-entities:$j:mount-point $tempfile 2>/dev/null)
			# mount-point is not mandatory inside system-entities
			if [ "$mountpoint" ]; then
				# pretty lame...
				if [[ "$imgpath" -ef "$real_path" ]]; then
					mnt=$mountpoint
					break
				fi
			fi
			j+=1
		done
		idx+=1
	done

	if [[ ! "$mnt" ]]; then
		E_MESSAGE="Can't find mount point for your tomb $FILENAME"
		return 1
	fi
	ret=$(${HDIUTIL} detach "$mnt" 2>&1)
	if [[ "$ret" =~ "detach failed" ]]; then
		E_MESSAGE+=$ret
		return 1
	fi
	S_MESSAGE="Mactomb ${FILENAME} was successfully unmounted"
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

	local abs_vol_path="/Volumes/$VOLNAME"
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

COMMAND=('create', 'app', 'help', 'forge', 'resize', 'list', 'chpass', 'compress', 'decompress', 'rename', 'mount', 'unmount')
HDIUTIL=/usr/bin/hdiutil
# if 1, the script will use the Mac OS X notification method
NOTIFICATION=0
ENC="AES-256"
FS="HFS+"
# compression? 
COMPRESS=0
# compression format (should be the default)
CFORMAT="UDZO"
# zlib compression level (9 = highest)
CLEVEL=9
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
# mount point for tombs, if not provided system will mount them to /Volume
MOUNTPOINT=""
VERSION=1.3
CMD=$1
shift

while getopts "a:f:s:p:o:b:n:m:hvc" opt; do
	case "${opt}" in
		f)
			FILENAME=$OPTARG;;
		s)
			SIZE=$OPTARG;;
		n)
			VOLNAME=$OPTARG;;
		a)
			APPCMD=$OPTARG;;
		c)
			COMPRESS=1;;
		p)
			PROFILE=$OPTARG;;
		b)
			BASHSCRIPT=$OPTARG;;
		o)
			OUTSCRIPT=$OPTARG;;
		m)
			MOUNTPOINT=$OPTARG;;
		v)
			NOTIFICATION=1;;
		\?)
			usage
			exit 1
			;;
	esac
done

if [[ ! "${COMMAND[@]}" =~ "${CMD}" ]]; then
	usage
	exit 1
fi

# add a checks just to be sure
if [ ! -e "${HDIUTIL}" ]; then
	e_echo "Weird, hdiutil not found in '${HDIUTIL}'. Can't make it."
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