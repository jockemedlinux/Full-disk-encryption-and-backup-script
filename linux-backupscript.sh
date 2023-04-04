#!/bin/bash

#########HOT BACKUP SCRIPT, @jockemedlinux###########
##MAKE SURE THE SETTINGS CORRESPONDS WITH THE GUIDE##
#####################################################

# Specify your devices.
fs=/dev/mmcblk0
loop=/dev/loop0
loopdev=/dev/loop0p2
cryptdev=/dev/mapper/box

# Specify file output name and place.
dir=/mnt/hdd/backups/server
name=backup_
fop=$name$(hostname)_$(date +%F).img

# Enter the password for your encrypted drive.
echo "[*] Enter your password:"
read -s pw

echo "[*] Backing up filesystem"
echo "[*] This will take som time, grab a coffe"
echo "[*] ..."
echo ""

pv -tpreb $fs | dd of=$dir/$fop bs=200M conv=noerror iflag=fullblock
sleep 5
findsize=`ls $dir/$fop -lhS | awk '{print $5}'`

#Calculates sektors and sizes
##############################################################################
losetup -f -P $dir/$fop
echo "$pw" | cryptsetup open $loopdev box
e2fsck -fy $cryptdev
blocksize=`dumpe2fs -h $cryptdev | grep 'Block size:' | awk '{print $3}'`
minsize=`resize2fs -P $cryptdev | grep -o '[0-9]\+'`
cryptoffset=`cryptsetup luksDump $loopdev | grep -v Area | grep offset | awk '{print $2}'`
start=`fdisk -lu | grep $loopdev | awk '{print $2}'`

startsize=`expr $start + 1`
minsizeconv=`expr $minsize \* 4096 / 512`
cryptconv=`expr $cryptoffset / 512`
partend=`expr $startsize + $minsizeconv + $cryptconv`
truncsize=`expr $partend \* 512`

##############################################################################
echo ""
echo -e "[*] r2fs blocksize:\t\t$blocksize\t\t[4K blocks]"
echo -e "[*] Filesystem minsize:\t\t$minsize\t\t[4K blocks]"
echo -e "[*] Cryptdevice Offset:\t\t$cryptoffset\t[bytes]"
echo ""
echo -e "[*] Start Sectors:\t\t$start\t\t[512 blocks]"
echo -e "[*] Start Sectors(+1):\t\t$startsize\t\t[512 blocks]"
echo -e "[*] Minsize Converted:\t\t$minsizeconv\t[512 blocks]"
echo -e "[*] Cryptdevice Converted:\t$cryptconv\t\t[512 blocks]"
echo -e "[*] Partition new end:\t\t$partend\t[512 blocks]"
echo -e "[*] Truncsize:\t\t\t$truncsize\t[bytes]"
echo ""

#############################################################################
e2fsck -fy $cryptdev
resize2fs -Mfp $cryptdev
cryptsetup close box
echo -e 'd\n2\nn\np\n2\n\n'$partend'\nw' | fdisk $loop
losetup -d $loop
echo "[*] Truncating image file."
truncate --size=$truncsize $dir/$fop
findsizen=`ls $dir/$fop -lhS | awk '{print $5}'`

#############################################################################
echo -e "[*] Backup is complete."
echo -e "[*] System is restored."
echo -e "[*] Old image size:\t$findsize"
echo -e "[*] New image size:\t$findsizen"
echo -e "[*] BYE!"
echo ""
