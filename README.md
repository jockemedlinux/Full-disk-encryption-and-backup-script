# FDE-and-Backup (FOR SD-CARD's ONLY)
#### Create a Full disk encrypted OS on an SD-card for a raspberry pi with corresponding backupscript. The way I do it.
#### The backupscript truncates the image file to smallest possible size.

tldr;
```
1 This step prepares the environment by creating necessary directories and mounting the base image onto a directory.
2 This step formats a new filesystem in the target image, encrypts it, and closes the encrypted device.
3 This step opens the encrypted filesystem, mounts it, and then copies all the files from the base image that are not encrypted to the mounted encrypted filesystem.
4 This step enters the newly created filesystem without booting, by mounting necessary directories, copying a package to the chroot directory, and entering the chroot.
5 This step makes changes to the configuration files of the chrooted system, specifically adding an entry for the encrypted device in crypttab, pointing the root to the encrypted device in fstab, and updating the cmdline.txt file to boot the right filesystem.
6 This step updates and installs necessary packages onto the newly created system.
7 This step creates a hook to enable cryptsetup in the initramfs.
8 This step creates necessary SSH keys for dropbear and configures it to listen to a certain port and unlock root.
9 This step updates the kernel and applies the new initramfs settings.  
10 This step unmounts all the mounted directories, closes the encrypted device, and removes the loop devices.
```

Foreword:
```
Go to: https://ubuntu.com/download/server
and grab yourself a version of ubuntu-server img.
Copy the image so you'll have two, rename them "base.img" and "target.img".
This is necessary because we need to create an encrypted formatted container within "target.img".
Then we'll copy the "base.img" OS onto the "target.img"
```


### 1; Probe both images, create necessary directories and mount the base image on `/mnt/original`:

```bash
losetup -r -f -P base.img
losetup -f -P target.img
mkdir -p /mnt/original
mkdir -p /mnt/chroot/boot
mount /dev/loop0p2 /mnt/original/
```

### 2; Format the target.img filesystem, create an ext4 filesystem in it and close the encrypted device:

```bash
cryptsetup luksFormat -c xchacha20,aes-adiantum-plain64 /dev/loop1p2
cryptsetup luksOpen /dev/loop1p2 box
mkfs.ext4 /dev/mapper/box
cryptsetup close box
```

### 3; Open the encrypted filesystem, mount it to your chroot directory and rsync all files from the base image to the chroot directory:

```bash
cryptsetup luksOpen /dev/loop1p2 box
mount /dev/mapper/box /mnt/chroot/
rsync --archive --hard-links --acls --xattrs --one-file-system --numeric-ids --info="progress2" /mnt/original/* /mnt/chroot/
```

### 4; Enter the newly created filesystem without booting by entering chroot:

```
mount /dev/loop1p1 /mnt/chroot/boot/
mount -t proc none /mnt/chroot/proc/
mount -t sysfs none /mnt/chroot/sys/
mount -o bind /dev /mnt/chroot/dev/
mount -o bind /dev/pts /mnt/chroot/dev/pts/
apt install qemu-user-static
cp /usr/bin/qemu-aarch64-static /mnt/chroot/usr/bin/
sudo env LANG=C chroot /mnt/chroot/
```

### 5; Add the following to `/etc/crypttab`, `/etc/fstab`, and `/boot/cmdline.txt` respectively:

```
/etc/crypttab: "box UUID=XXXXXX-XXXXXX-XXXXXX-XXXXXX none luks,initramfs"
/etc/fstab: "/dev/mapper/box / ext4 discard,errors=remount-ro 0 1"
/boot/cmdline.txt: "root=/dev/mapper/box cryptdevice=/dev/mmcblk1p2:box"
```

### 6; Update your chrooted system and install necessary packages or any packages you want or need on your filesystem. For example:

```
apt update
apt install -y busybox cryptsetup dropbear-initramfs pv
```

### 7; Create the hook and make sure the `conf-hook` exists:

```
echo "CRYPTSETUP=y" > /etc/cryptsetup-initramfs/conf-hook
```

### 8; Create the necessary ssh-keys for dropbear and configure dropbear to listen to a certain port and unlock root:

```
ssh-keygen
chmod 0600 id_rsa
cp id_rsa.pub /etc/dropbear/initramfs/authorized_keys
cp id_rsa to client
echo 'DROPBEAR_OPTIONS="-I 180 -j -k -p 9876 -s -c cryptroot-unlock"' >> /etc/dropbear/initramfs/dropbear.conf
echo 'IP=192.168.0.100::192.168.0.1:255.255.255.0:srv' >> /etc/initramfs-tools/initramfs.conf
```

### 9; Find the latest kernel to apply the new initramfs settings, and update it:

```
ls /lib/modules/
mkinitramfs -o /boot/initrd.img 5.4.0-10xx-raspi
update-initramfs -v -u -k all
sync
history -c && exit
```

### 10; Unmount all mounted directories and close the encrypted device:

```
umount /mnt/chroot
umount /mnt/chroot/boot
umount /mnt/chroot/sys
umount /mnt/chroot/proc
umount /mnt/chroot/dev/pts
umount /mnt/chroot/dev
umount /mnt/original
cryptsetup close box
losetup -D
```

# EXTRA:

### AFTER BOOT GROW PARTITION

```
echo -e 'd\n2\nn\np\n2\n\n\nw' | fdisk /dev/mmcblk0
cryptsetup resize box
resize2fs /dev/mapper/box

##

This uses echo command to send a series of commands to fdisk utility with /dev/mmcblk0 as its input parameter. These commands are used to manipulate the disk partitions of the specified device, /dev/mmcblk0.
d, command deletes an existing partition
2, selects the second partition
n, creates a new partition
p, specifies that the partition is primary
2, sets the partition number to 2
The three empty Enter keys (\n) accept the default settings for the partition size
w writes the changes to disk and exits.
"cryptsetup resize" is used to increase the size of the encrypted partition named "box".
Finally, "resize2fs" is used to resize the filesystem on the encrypted partition /dev/mapper/box to fill the new size of the partition.
```

### USEFUL COMMANDS

```
dmsetup table --showkeys
cryptsetup luksDump /dev/mmcblk0
cryptsetup luksChangeKey /dev/mmcblk0p2-S 0
cryptsetup --verbose open --test-passphrase /dev/mmcblk0p2 -S 0
```

### CHANGE NAME OF ENCRYPTED PARTITION

```
dmsetup rename OLD_NAME NEW_NAME
cp -a /dev/mapper/NEW_NAME /dev/mapper/OLD_NAME
#dont forget to ...-->
...change fstab to NEW_NAME
...change cmdline to NEW_NAME
...change crypttab to NEW_NAME
&
update-initramfs -u -k all
```
If you don't, you'll brick your system.
