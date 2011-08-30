#!/bin/bash
#TODO: these variables should be set at the command line
domain=""
blockdev=""
image=""

dd="/bin/dd"
virsh="/usr/bin/virsh"
gzip="/bin/gzip"
isRunning="0"
wasRunning="1"
start=`date +%s`
blockSize="1M"
compress="0"

function Quit {
	if [ -n "$*" ] ; then 
		echo "$*";
		exit
	fi

	if [ "$wasRunning" -eq "0" ]; then
		$virsh start "$domain" > /dev/null 2>&1
	fi
	echo "Operation took $((`date +%s` - $start)) seconds."
	exit
}

function Usage {
	echo "Usage: `basename $0` -i source -o destination -n guestName [-z]"
	echo "-i file/device to backup"
	echo "-o path of output file"
	echo "-n name of guest"
	echo "-z compress the archive using gzip"
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
}


#get the options
while getopts "i:o:n:z" Option
do
  case $Option in
    i)blockdev="$OPTARG";;
    o)image="$OPTARG";;
    n)domain="$OPTARG";;
    z)compress="0";;
    ?)Usage;;
  esac
done

CheckFiles

#start the operation
until [ "$isRunning" -eq "1" ]; do

	$virsh list | grep -w "$domain" > /dev/null 2>&1 
	isRunning="$?"

	if [ "$isRunning" -eq "0" ]; then
		echo "Guest is running."
		wasRunning="0"
		$virsh shutdown "$domain" > /dev/null 2>&1
	else
		if [ -r "$blockdev" ] ; then
			echo "Copying $blockdev to $image"
			$dd if="$blockdev" bs="$blockSize" | $gzip > $image
			Quit "Success!"
		else
			Quit "You do not have read access for $blockdev"
		fi
	fi
	sleep 60
done
