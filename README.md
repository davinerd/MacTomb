# MacTomb
MacTomb is a kind of [Tomb](https://github.com/dyne/Tomb) porting for Mac OS X. It allows you to create encrypted DMG file (called `mactomb`), copy files and folders into it and setup a couple of scripts needed to easily mount & run apps that use files stored inside the mactomb.

# What exactly it does?
The help is quite explicit:
```
$ bash mactomb.sh help
..:: MacTomb v.0.1 ::..
by Davide Barbato

Help!

create:
  -f <file>		    File to create (the mactomb file)
  -s <size[m|g|t]	Size of the file (m=mb, g=gb, t=tb)
  Optional:
    -p <profile>	Folder/file to copy into the newly created mactomb file <file>

app:
  -f <file>	     Encrypted DMG to use as mactomb file
  -a <app>	     Binary of the app you want to use inside the mactomb file
  -o <output>	 The bash output script used to launch the <app> inside the mactomb file <file>

forge:
  Will call both "create" and "app", so the flags are the same.
  Optional:
    -s <output>	The output Automator script used to launch the bash <output> script by Mac OS X
```

# What is the goal? What are you trying to do?
Ok, let's imagine this situation: you want to run Thunderbird or Firefox with a profile inside your mactomb. And since you're on a Mac, you want to do it in a fancy way and easily, painless.
What the script does for you with the `forge` parameter (including all the optiona parameters) is to:
- create an encrypted DMG file
- copy the Thunderbird/Firefox profile folder
- creating a bash script that will mount the mactomb and run the app (selecting the profile inside the mactomb if not already done)
- create the Automator script that call the previously created bash script, so all you need to do is clicking on this script.

In this way with a simple click you can enjoy your app with sensitive data stored inside an encrypted AES256 CBC container, ready to be uploaded on some cloud storage provider to have a backup and portable data backup.

You can drag the Automator script in the Dock and add an icon, so it will looks like a normal app.

## Jiucy stuff
Using the `-n` flag, you can have the final result printed as a Mac OS X notification.

# Technical details
MacTomb uses `hdiutil` to create the encrypted DMG. The parameters are specified at the bottom of the script. As previously stated, it uses AES256 and by default `hdiutil` uses CBC mode. The file system is `HFS+`, the native and well supported one by Mac OS X.
The `template.app` directory is used to create the Automator script. If you don't know what Automator is, this is a good start: http://www.raywenderlich.com/58986/automator-for-mac-tutorial-and-examples
