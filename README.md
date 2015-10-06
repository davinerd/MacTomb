# MacTomb
MacTomb is a kind of [Tomb](https://github.com/dyne/Tomb) porting for Mac OS X. It allows you to create encrypted DMG file (called `mactomb`), copy files and folders into it and setup a couple of scripts needed to easily mount & run apps that use files stored inside the mactomb.

Read about MacTomb on [dyne](https://www.dyne.org/software/mactomb/) and [Lost in ICT blog](https://lostinict.wordpress.com/2015/09/27/mactomb-enhance-your-privacy-on-mac-os-x/)

# What's new? (v.1.2)
- compression/decompression support: mactomb is able to compress and decompress mactomb files. See the related section
- `list` command: it will list all the open mactombs
- change password: with `chpass` you can change your mactomb's password
- bug fixes and improvements

# What's new? (v.1.1)
- changing flags (again!): now `-n` specify the name of the volume (the famous `$VOLNAME`) while `-v` enables Mac OS X notification
- now the bash script umount the mactomb when closing the application. It means that when you close the Automatr App, the mactomb will be umounted
- added strong checks to verify if bash script and Automator App already exist or they are a directory
- added a check for the filename to ensure it contains/adds the `.dmg` extension
- better error messages

# What's new? (v.1.0)
Version 1.0 released! Yes, from 0.1 to 1.0. Why? Big improvements has been made. Read below:
- there was a conflict between two `-s` options (size and Automator app). Now the Automator app has the `-o` flag and the bash script (that previously was `-o`) becomes `-b`.
- possibility to call `forge` without automatically fire `create` and `app`. This means: you can use `forge` to create only the Automator app. For a better explaination on `forge`, see the related paragrah
- you can now specify a command (binary + arguments) with the `-a` flag, that will be outputted in the bash script created with the `-b` flag
- `-o` ensure the Automator app has .app extension so Mac OS X can recognise it (you don't need to specify it via command line)
- introduced the `VOLNAME` variable (line 305). By default, the encrypted DMG is labeled `untitled`. You can rename it by changing the value of that variable.
- the `VOLNAME` variable can be used also inside the `-a` argument to specify an action that has to access file(s) inside the mactomb. As in example, the following line works: `-a /Applications/Firefox.app/Contents/MacOS/firefox-bin \$VOLNAME/index.html` (will tell Firefox to open _/Volumes/$VOLNAME/index.html_). Please note the `\$VOLNAME`: it will be automatically translated to the value of the `VOLNAME` variable defined in the script
- more robust errors checking

# What exactly it does?
The help is quite explicit:
```
$ bash mactomb.sh help
..:: MacTomb v.1.2 ::..
by Davide Barbato

Help!

list:
   list all opened mactombs

chpass:
  -f <file>   Change passphrase of mactomb <file>

compress:
  -f <file>   Compress a mactomb <file> (will make it read-only)

decompress:
  -f <file>   Decompress a mactomb <file>

create:
  -f <file>   File to create (the mactomb file)
  -s <size[m|g|t] Size of the file (m=mb, g=gb, t=tb)
  Optional:
    -p <profile>  Folder/file to copy into the newly created mactomb <file>
    -c      Create a zlib compressed mactomb <file> (will make it read-only)
    -n <volname>  Specify the volume name to assign to the mactomb <file>

app:
  -f <file> Encrypted DMG to use as mactomb file (already created)
  -a <app>  Binary and arguments of the app you want to use inside the mactomb file
  -b <output> The bash script used to launch the <app> inside the mactomb file <file>

forge:
  Will call both "create" and "app" if all flags are specified. Can be called on already created files, in this case skipping "create" and/or "app"
  Optional:
    -o <output> The Automator app used to launch the bash <output> script by Mac OS X
```

# What is the goal? What are you trying to do?
Ok, let's imagine this situation: you want to run Thunderbird or Firefox with a profile inside your mactomb. And since you're on a Mac, you want to do it in a fancy way and easily, painless.
What the script does for you with the `forge` command (including all the optional parameters) is to:
- create an encrypted DMG file
- copy the Thunderbird/Firefox profile folder
- creating a bash script that will mount the mactomb and run the app (selecting the profile inside the mactomb if not already done)
- create the Automator script that call the previously created bash script, so all you need to do is clicking on this script.

In this way with a simple click you can enjoy your app with sensitive data stored inside an encrypted AES256 CBC container, ready to be uploaded on some cloud storage provider to have a backup and portable data backup.

You can drag the Automator app in the Dock and add an icon, so it will looks like a normal app.

# The `forge` command
The `forge` command is most likely the command you want to use or you'll use mostly.
If you need to create your mactomb from scratch and use an app inside, this command will be your first choice, since it avoids you to call `create` and `app`. Plus, `forge` creates the Automatr app that it's useful if you want to run your bash script (created with `app`) in a Mac OS X way.
A good use of `forge` is the following:
```
$ bash mactomb.sh forge -f ~/mytomb.dmg -s 100m -a "/Applications/Firefox.app/Contents/MacOS/firefox-bin -p test" -b ~/run.sh -o ~/runmy.app
```
With the command above we're creating a mactomb file of 100 MB, a bash script (`run.sh`) that will mount the mactomb and will call `/Applications/Firefox.app/Contents/MacOS/firefox-bin -p test`, and the Automator app `runmy.app` that will call `run.sh`. To make a sense of this command, you probably want to create the Firefox profile `test` inside the mactomb, so everytime you run `runmy.app` you'll use Firefox with a profile that runs inside an encrypted container.

Now, what if you have already created a mactomb with `create` or `app` but you need to create the Automator app. The following command will be handy (new in version 1.0):
```
$ bash mactomb.sh forge -b ~/run.sh -o ~/runmy.app
```
That command can be used even outside the mactomb concept: it can be used to create an Automator app that will call any bash script passed as `-b` argument.

# Compression / Decompression
New in version 1.2, you are now able to compress and decompress your mactomb.
Compressing a mactomb will help you save some space: it uses zlib compression at the higest level (9). 

**Please note that compressing a mactomb will make it read-only**

While this can be seen as a disadvantage, it can be quite useful in the following scenarios:
- you need to transfer a big mactomb and don't have much space/bandwith available
- you need only to read the mactomb's content, so there is no need for writing support

mactomb provides also a `decompress` command that decompress a compressed mactomb file, making it read-write

# How to update
If you have your original folder, move there and type `git pull`. If not, you'd do better to clone the repository or download the zip file.

# Jiucy stuff
Using the `-v` flag, you can have the final result printed as a Mac OS X notification.

# Technical details
MacTomb uses `hdiutil` to create the encrypted DMG. The parameters are specified at the bottom of the script. As previously stated, it uses AES256 and by default `hdiutil` uses CBC mode. The file system is `HFS+`, the native and well supported one by Mac OS X.
The `template.app` directory is used to create the Automator script. If you don't know what Automator is, this is a good start: http://www.raywenderlich.com/58986/automator-for-mac-tutorial-and-examples
