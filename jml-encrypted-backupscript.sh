#!/bin/bash
##@JOCKEMEDLINUX BACKUP-SCRIPT FOR ENCRYPTED DEVICES 2023-08-13##

##THIS SCRIPT PROVIDES A .IMG FILE YOU CAN###
##FLASH ONTO YOUR HD SD-CARD, USB ETC USING##
##TOOLS LIKE BALENA-ETCHER##


### DEVICES AND FILESYSTEMS
backupdevice=/dev/sda
cloudbackupdir=/mnt/DATADISK/_BACKUPS/server/CLOUD
backupdirectory=/mnt/DATADISK/_BACKUPS/server/thinker-server
dockerbackupdir=/mnt/DATADISK/_BACKUPS/server/dockers/
dockerimagenames=$(docker images --format {{.Repository}})
dockercontainernames=$(docker ps --format {{.Names}})
name=crypted_
fileoutput=$name$(hostname)_$(date +%F).img

### LOOP DEVICES
loop=/dev/loop0
loopdev=/dev/loop0p2
cryptdevice=/dev/mapper/crypted-temp

### LOG FILE. WILL BE PLACED IN CURRENT DIRECTORY.
log_file="./$(date +%F)_backupscript.log"

### FUNCTION TO PRINT ERROR AND EXIT
abort() {
    echo -e "\e[91m[ERROR] $1\e[0m"
    echo -e "\e[91m[ERROR] Removing loopdevices, closing crypt-device, and restoring services and dockers\e[0m"
    sleep 5
    docker start $(docker ps -a -q)
    cryptsetup close crypted-temp
    losetup -D
    exit 1
}

### CHECKPOINT FUNCTION
checkpoint() {
    if [ $? -ne 0 ]; then
        abort "An error occurred during: [$1]"
    fi
    echo -e "\e[92m[+] [PASSED]: $1\e[0m\n[-------------------------------------------------------------------------------------------]"
    
    ## UNCOMMENT TO SLOW DOWN SCRIPT.
    #sleep 5
}

####################################################################################
echo -e "####################################################################################"
echo -e '\e[93mRun script like "./backup-script.sh | tee `date +%F`.log" for logging.\e[0m'
echo -e "####################################################################################\n"

### CHECK SUDO RIGHTS
if [ $EUID != 0 ]; then
    echo -e "\n\e[91m[ERROR] Please run this script with sudo permissions\e[0m\n"
    exit 1
fi
checkpoint "Sudo permissions used"

### NEEDED PACKAGES
packages="pv e2fsck dumpe2fs resize2fs truncate docker losetup smbd cryptsetup docker"
echo -e "\e[93m[INFO] Checking needed packages and programs\e[0m\n"
for line in $packages; do
    if which $line >/dev/null; then
        echo -e "\e[92m[+] $line is installed\e[0m"
    else
        echo -e "\e[91m[ERROR] $line is not installed\e[0m"
        abort "Packages are missing"
    fi
done
echo -e ""
checkpoint "Found all needed settings and programs"

echo -e "\e[93m[INFO] Enter your password for the encrypted device:\e[0m"
read -s passwordvariable
checkpoint "Password saved"

echo -e "\e[93m[INFO] Do you also want to backup your dockers and volumes? [Y/N]: \e[0m"
read answer
if [[ $answer == "Y" || $answer == "y" ]]; then
    echo -e "\e[93m[INFO] Committing latest docker containers\e[0m"
    mkdir -p $dockerbackupdir/$(date +%F)
    docker start $(docker ps -a -q)
    for container in $dockercontainernames; do
        docker commit -p $container "jml-$container:latest"
    done
    echo -e "\e[93m[INFO] Backing up latest docker images \e[0m"
    for dockerimage in $dockerimagenames; do
        docker save $dockerimage | pv -tpre > "$dockerbackupdir/$(date +%F)/$dockerimage.tar"
    done
    echo -e "\e[93m[INFO] Backing up docker directories. (Will prune dangling dockers) \e[0m"
    tar -czvf --warning=no-file-changed "$dockerbackupdir/$(date +%F)/docker-directories.tar.gz" /srv/
    echo "Y" | docker system prune
    checkpoint "Backing up docker containers, volumes, and images"

else
   echo -e "\e[93m[INFO] Skipping docker backups\e[0m"
   checkpoint "Skipping docker backup"
fi

echo -e "\e[93m[INFO] Do you want to backup your cloud?\e[0m"
echo -e "\e[93m[INFO] This will significantly increase the time for the backup. Proceed? [Y/N]: \e[0m"
read cloudanswer
if [[ $cloudanswer == "Y" || $cloudanswer == "y" ]]; then
   echo -e "\e[93m[INFO] Backing up your cloud \e[0m"
   mkdir -p $cloudbackupdir/$(date +%F)
   tar -czvf --warning=no-file-changed "$cloudbackupdir/$(date +%F)/nextcloud.tar.gz" /mnt/DATADISK/_CLOUD/
   checkpoint "Backing up cloud settings, data, and configurations"
else
   echo -e "\e[93m[INFO] Skipping cloud backup\e[0m"
   checkpoint "Skipping cloud backup"
fi

### STOP SERVICES AND DOCKERS
echo -e "\e[93m[INFO] Stopping services and dockers\e[0m"
docker stop $(docker ps -a -q)
checkpoint "Stopping services and dockers"

### CHECK BACKUP-FILE BEFORE BACKUP DEVICE
if [[ -e "$backupdirectory/$fileoutput" ]]; then
    echo -e "\e[93m[INSPECT] Backup-file already exists. Do you want to overwrite this file? [Y/N]: \e[0m"
    read answer
    if [[ $answer == "Y" || $answer == "y" ]]; then
        echo -e "\e[93m[INFO] Overwriting existing backup file...\e[0m"
        pv -tpreb $backupdevice | dd of=$backupdirectory/$fileoutput bs=1M conv=noerror,sparse iflag=fullblock
        checkpoint "Backing up device"
    else
        echo -e "\e[93m[INFO] Skipping backup.\e[0m"
        checkpoint "Skipping backup"
    fi
else
    echo -e "\e[93m[INFO] Overwriting existing backup file...\e[0m"
    pv -tpreb $backupdevice | dd of=$backupdirectory/$fileoutput bs=1M conv=noerror,sparse iflag=fullblock
    checkpoint "Backing up device"
fi

### FIND ORIGINAL FILESIZE
echo -e "\e[93m[INFO] Checking filesize\e[0m"
findsize=$(ls $backupdirectory/$fileoutput -lhS | awk '{print $5}')
if [[ -z $findsize ]]; then
    abort "File not found $1"
fi
echo -e "\tFilesize: $findsize"
checkpoint "Find original filesize"


### LOOP AND MINIMIZE DEVICE FILESYSTEM
sleep 5
losetup -f -P $backupdirectory/$fileoutput
echo -e "\e[93m[INFO] Opening crypted container\e[0m"
echo "$passwordvariable" | cryptsetup luksOpen $loopdev crypted-temp
checkpoint "Encrypted container opened as: $cryptdevice"

echo -e "\e[93m[INFO] Checking filesystem #1\e[0m"
e2fsck -fy $cryptdevice
#checkpoint "Checking filesystem #1"


### GATHER necessary INFO
echo -e "\e[93m[INFO] Gathering necessary information\e[0m"
blocksize=`dumpe2fs -h $cryptdevice | grep 'Block size:' | awk '{print $3}'`
minsize=`resize2fs -P $cryptdevice | grep -o '[0-9]\+'`
cryptoffset=`cryptsetup luksDump $loopdev | grep -v Area | grep offset | awk '{print $2}'`
start=`fdisk -lu | grep $loopdev | awk '{print $2}'`
startsize=`expr $start + 1`
minsizeconv=`expr $minsize \* 4096 / 512`
cryptconv=`expr $cryptoffset / 512`
partend=`expr $startsize + $minsizeconv + $cryptconv`
truncsize=`expr $partend \* 512`

echo -e "\e[93m\n"
echo -e "[INFO] r2fs blocksize:\t\t$blocksize\t\t[4K blocks]"
echo -e "[INFO] Filesystem minsize:\t$minsize\t\t[4K blocks]"
echo -e "[INFO] Cryptdevice Offset:\t$cryptoffset\t[bytes]"
echo -e "[INFO] Start Sectors:\t\t$start\t\t[512 blocks]"
echo -e "[INFO] Start Sectors(+1):\t$startsize\t\t[512 blocks]"
echo -e "[INFO] Minsize Converted:\t$minsizeconv\t[512 blocks]"
echo -e "[INFO] Cryptdevice Converted:\t$cryptconv\t\t[512 blocks]"
echo -e "[INFO] Partition new end:\t$partend\t[512 blocks]"
echo -e "[INFO] Truncsize:\t\t$truncsize\t[bytes]"
echo -e "\e[0m\n"
checkpoint "Gathering necessary informations"

############################################################################################
### DEBUG SECTION. UNCOMMENT TO STOP SCRIPT HERE BEFORE IRREVOCABLY TRUNCATE/RESIZE BACKUP FILE
#echo -e "\e[93m\n\nExiting script for improvements\n\n\e[0m"
#cryptsetup close crypted-temp
#losetup -D
#exit 0
############################################################################################

### RESIZE FILESYSTEM TO MINIMUM SIZE
echo -e "\e[93m[INFO] Rezising filesystem. (The rest will be unallocated)\e[0m"
resize2fs -Mfp $cryptdevice
checkpoint "Resizing filesystem"

### RESIZE FILESYSTEM TO MINIMUM SIZE
echo -e "\e[93m[INFO] Rezising encrypted device\e[0m"
echo "$passwordvariable" | cryptsetup resize crypted-temp
checkpoint "Resizing filesystem"

echo -e "\e[93m[INFO] Closing the encrypted partition\e[0m"
cryptsetup luksClose crypted-temp

echo -e "\e[93m[INFO] Creating the new partition\e[0m"
echo -e 'd\n2\nn\n\n\n'$partend'\nw' | fdisk $loop
checkpoint "Create the new partition"

### UNMOUNT BEFORE CUTTING
echo -e "\e[93m[INFO] Unmount loopdevices before cutting\e[0m"
losetup -D
checkpoint "Loopdevices closed"

### TRUNCATE THE IMAGE FILE TO SMALLEST POSSIBLE SIZE.
echo -e "\e[93m[INFO] Truncating image file\e[0m"
truncate --size=$truncsize $backupdirectory/$fileoutput
checkpoint "Truncating image file"

### RECHECK FILESYSTEM AFTER TRUNCATION.
#echo -e "\e[93m[INFO] Remounting loopdevices for after truncation check\e[0m"
#losetup -f -P $backupdirectory/$fileoutput
#checkpoint "Opened truncated loopdevice"
#echo -e "\e[93m[INFO] Check the filesystem #2\e[0m"
#e2fsck -pv $loopdev
#checkpoint "Checking filesystem #2"

### FIND NEW FILESIZE
echo -e "\e[93m[INFO] Checking filesize\e[0m"
findnewsize=$(ls $backupdirectory/$fileoutput -lhS | awk '{print $5}')
if [[ -z $findnewsize ]]; then
    abort "File not found: $1"
fi
echo -e "\t[INFO] Filesize: $findnewsize"
checkpoint "Find new filesize"

### STATUS AND OUTPUTS.
echo -e "\e[93m[INFO] Old filesize:\t$findsize\e[0m"
echo -e "\e[93m[INFO] New filesize:\t$findnewsize\e[0m"
checkpoint "Find filesizes"

### CLEANUP
echo -e "\e[93m[INFO] Cleaning up\e[0m\n"
losetup -D
echo -e "\e[93m[INFO] Restarting dockers and services\e[0m"
docker restart $(docker ps -a -q)
systemctl restart smbd
checkpoint "Restarting dockers and services."
echo -e "\e[92m[+] Congratulation! The script finished successfully and services has been restored. BYE!\e[0m"
curl -d "BACKUP FINISHED WITHOUT ERRORS" 10.77.0.200:6677/BACKUPS
chmod -R 777 /mnt/
exit 0
