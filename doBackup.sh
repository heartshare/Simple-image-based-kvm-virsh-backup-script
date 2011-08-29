#!/bin/bash
dd=/bin/dd
virsh="/usr/bin/virsh"
domain="virsh domain name here"
blockdev=/path/to/disk/image/or/block/device
image=/path/to/target/file
isRunning="0"
wasRunning="1"
start=`date +%s`
blockSize="1M"

function quit {
	if [ "$wasRunning" -eq "0" ]; then
		$virsh start "$domain"
	fi
	echo "$1"
	echo "Operation took $((`date +%s` - $start)) seconds."
	exit
}

until [ "$isRunning" -eq "1" ]; do

	$virsh list | grep -w "$domain" > /dev/null 2>&1 
	isRunning="$?"

	if [ "$isRunning" -eq "0" ]; then
		echo "Guest is running."
		wasRunning="0"
		$virsh shutdown "$domain"
	else
		echo "Copying $blockdev to $image"
		$dd if="$blockdev" of="$image" bs="$blockSize"
		if [ "$?" -eq "0" ]; then
			quit "Success!"
		else
			quit "FAIL"
		fi
	fi
	
	sleep 1
done
