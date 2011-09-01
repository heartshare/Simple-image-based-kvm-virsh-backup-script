#!/bin/bash

#internal configuration
dd="/bin/dd"
virsh="/usr/bin/virsh"
gzip="/bin/gzip"
isRunning="0"
wasRunning="1"
start=`date +%s`
blockSize="1M"
compress="1"

function Quit {
	#if the guest was running we restart it
	if [ "$wasRunning" -eq "0" ]; then
		Guest restore
	fi

	#if we received a reason to end we echo it, if not we give the length of time it took (probably it was successful)
	if [ -n "$*" ] ; then 
		echo "$*";
	else
		echo "Operation took $((`date +%s` - $start)) seconds."
	fi

	#we do some cleanup
	if [ ! -z "$snapshot" ] ; then
		if [ -a "$snapshot" ] ; then
			RemoveSnapshot
		fi
	fi
	
	exit
}

function Usage {
	echo "Usage: `basename $0` -i source -o destination -n guestName [-s spanshotdevicepath] [-z] [-w windowshostname]"
	echo "-i file/device to backup"
	echo "-o path of output file"
	echo "-n name of guest"
	echo "-z compress the archive using gzip"
	echo "-s make a snapshot an immediately restart the guest"
	echo "-w accepts the hostname of the windows guest in order to send an RPC shutdown command.  you can pass additional arguments to the net RPC command by enclosing the argument to this in quotes.  ex: -w \"hostname -U username%password"
	Quit
}

function CheckFiles {
	#check if required variables are set (not sure if there's a better way to do this)
	if [ -z "$domain" ]; then
		Usage
	fi
	if [ -z "$blockdev" ]; then
		Usage
	fi
	if [ -z "$image" ]; then
		Usage
	fi

	#check if the files exist
	if [ ! -e "$blockdev" ]; then
		Quit "the source file does not exist";
	fi
	if [ -e "$image" ]; then
		Quit "$image already exists";
	fi

	#check if we have access to the files
	if [ ! -r "$blockdev" ] ; then
		Quit "You do not have read access for $blockdev"
	fi
	if [ -a "$image" ] ; then
		Quit "$image already exists";
		#Quit "You do not have write access for $image"
	fi
	if [ -a "$snapshot" ] ; then
		Quit "$snapshot already exists!";
	fi
}

function MakeSnapshot {
	#TODO: need more testing of error checking
	lvcreate -L `blockdev --getsize64 $blockdev`B --snapshot -n "$snapshot" "$blockdev"
	if [ "$?" -eq "0" ] ; then
		echo "nothing" > /dev/null
	else
		Quit "An error occurred created the snapshot volume"
	fi
}

function RemoveSnapshot {
	#TODO: we might need more error checking here...
	lvremove -f "$snapshot"
	if [ ! "$?" -eq "0" ] ; then	#we have to check if the remove failed because for some reason the lvm reports that it can't be removed sometimes
		echo "Retrying RemoveSnapshot"
		sleep 5
		RemoveSnapshot
	fi
}

function Backup {
	if [ "$compress" -eq "0" ] ; then
		echo "Copying $blockdev to $image and compressing with gzip"
		$dd if="$blockdev" bs="$blockSize" | $gzip > $image #TODO need error check
	else
		echo "Copying $blockdev to $image"
		$dd if="$blockdev" bs="$blockSize" | $dd of="$image" bs="$blockSize"
	fi
}

function Guest {
	case "$1" in
		"start") $virsh start "$domain";;
		"stop") 
			if [ -n "$winHost"  ] ; then
				echo "Attempting to shutdown windows host $winHost"
				net rpc shutdown -I "$winHost" -U "$winUser" -C "This system will go down for a short time to perform backups."
			else
				$virsh shutdown "$domain"
			fi
			;;
		"restore")
			if [ "$wasRunning" -eq "0" ] ; then
				virsh start "$domain"
				wasRunning="1"
			fi
			;;
	esac
}

function Abort {
	Quit "Received INT or TERM signal"
}
trap Abort INT TERM #i may need to include exit here as well...

#get the options
while getopts "i:o:n:s:w:U:z" Option
do
  case $Option in
    i)blockdev="$OPTARG";;
    o)image="$OPTARG";;
    n)domain="$OPTARG";;
    z)compress="0";;
    s)snapshot="$OPTARG";;
    w)winHost="$OPTARG";;
    U)winUser="$OPTARG";;
    ?)Usage;;
  esac
done

CheckFiles

#start the operation
until [ "$isRunning" -eq "1" ]; do

	$virsh list | grep -w "$domain" > /dev/null 2>&1 
	isRunning="$?"

	if [ "$isRunning" -eq "0" ]; then
		echo "Guest is running. Asking/waiting for guest to shutdown."
		wasRunning="0"
		Guest stop
	else
		if [ -z $snapshot ] ; then
			Backup
			Quit
		else
			MakeSnapshot
			Guest restore
			Backup
			Quit
		fi
	fi
	sleep 60
done

