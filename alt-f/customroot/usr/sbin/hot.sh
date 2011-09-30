#!/bin/sh

debug=true

if test -n "$debug"; then
	exec >> /var/log/hot.log 2>&1
#	set -x
	echo "DATE=$(date)"
	env	
fi

# mdev -s generates these events while scanning /sys to populate /dev.
# so, most likely, these are "add" actions, and the events generated by the
# kernel are already lost
if test -z "$ACTION"; then
	logger -t hot "No ACTION for $MDEV, 'mdev -s' is scanning /sys"
	if test -d /sys/block/$SUBSYSTEM; then
		if test -d /sys/block/$SUBSYSTEM/$MDEV; then
			ACTION="add"
			DEVTYPE="partition"
		elif test "$MDEV" = "$SUBSYSTEM"; then
			ACTION="add"
			DEVTYPE="disk"
		else
			return 0
		fi
	else
		return 0
	fi
fi

# -an MD can be partitioned, thus the kernel sends the /dev/md? event as being
# a disk. But we use disk-based partitioning, thus a /dev/md? is in reality
# a partition. This might cause problems if plugging a MD-based partitioned disk
# -device-mapper events are also reported as disks
if test \( ${MDEV%%[0-9]} = "md" -o ${MDEV%%[0-9]} = "dm-" \) -a "$DEVTYPE" = "disk" -a \
	-z "$PHYSDEVDRIVER" -a -z "$PHYSDEVPATH" -a -z "$PHYSDEVBUS"; then
	logger -t hot "Changing DEVTYPE from disk to partition for \"$MDEV\""
	DEVTYPE="partition"
fi

PCAP=/etc/printcap
FSTAB=/etc/fstab
MISCC=/etc/misc.conf
BAYC=/etc/bay
MDADMC=/etc/mdadm.conf

if test "$ACTION" = "add" -a "$DEVTYPE" = "partition"; then
	if test -z "$MDEV"; then return 0; fi

	res=$(mdadm --query --examine --export --test $PWD/$MDEV)
	if test $? = 0; then
		mdadm --examine --scan > $MDADMC
		mdadm --incremental --run $PWD/$MDEV
		eval $res
		if test -z "$MD_NAME"; then # version 0.9 doesnt have the MD_NAME attribute
			MD_NAME=$(ls /sys/block/${MDEV:0:3}/$MDEV/holders/)
			MD_NAME=${MD_NAME:2}
		else
			MD_NAME=${MD_NAME##*:} # remove host: part
		fi
		if test -e $PWD/md$MD_NAME -a -b $PWD/md$MD_NAME; then
			mdadm --query --detail $PWD/md$MD_NAME
			if test $? = 0; then # generate hotplug event for /dev/md?. 
				(cd /dev && ACTION=add DEVTYPE=partition PWD=/dev MDEV=md$MD_NAME /usr/sbin/hot.sh)
			fi
		fi
		return 0
	fi

	if test -f $MISCC; then
		. $MISCC
	fi

	eval $(blkid -w /dev/null -c /dev/null $PWD/$MDEV | sed 's|^.*: ||')

	# mount options, sourced from /etc/misc.conf
	eval mopts=$(echo \$mopts_$UUID | tr '-' '_')
	if test -z "$mopts"; then mopts="defaults"; fi

	fstype=$TYPE
	fsckcmd="fsck"
	case $fstype in
		ext2|ext3|ext4)	fsopt="-p" ;;
		iso9660) fsckcmd="echo" ;;
		vfat) fsopt="-a" ;;			
		ntfs)
			if ! test -f /usr/bin/ntfsfix; then fsckcmd="echo "; fi
			fstype="ntfs-3g"
			fsopt="-" # FIXME, hack for hot_aux arguments (can't be empty)
			;; 
		swap) # don't mount swap on usb devices
			if ! readlink /sys/block/${MDEV:0:3}/device | grep -q /usb1/; then
				swapon -p 1 $PWD/$MDEV
				ns=$(awk '/SwapTotal:/{ns = $2 * 0.1 / 1000; if (ns < 32) ns = 32; printf "%d", ns}' /proc/meminfo)
				mount -o remount,size=${ns}M /tmp
				touch -r $FSTAB /tmp/fstab_date
				sed -i '\|^'$PWD/$MDEV'|d' $FSTAB
				echo "$PWD/$MDEV none swap pri=1 0 0" >> $FSTAB
				touch -r /tmp/fstab_date $FSTAB
				rm /tmp/fstab_date

			fi
			return 0
			;;
		lvm2pv) # LVM
			if test -x /usr/sbin/lvm; then
				if ! lsmod | grep -q dm_mod; then
					logger -t hot "Found partition type \"$fstype\" in \"$MDEV\", activating LVM support"
					modprobe -q dm-mod
				fi
				vgscan --mknodes 
				vgchange -a y
			else
				logger -t hot "No LVM support found for partition type \"$fstype\" in \"$MDEV\""
			fi
			return 0
			;;
		crypt_LUKS) # dm-crypt/luks
			if test -x /usr/sbin/cryptsetup; then
				if ! lsmod | grep -q dm_crypt; then
					logger -t hot "Found partition type \"$fstype\" in \"$MDEV\", activating crypt/LUKS support"
					modprobe -q dm-mod
					modprobe -q dm-crypt
					modprobe -q mv_cesa # partially fails, because of crypto_hash
					modprobe -q mv_cesa # try again
				fi

				if test -f "$CRYPT_KEYFILE" -a ! -b /dev/mapper/$MDEV-crypt; then
					if cryptsetup isLuks $PWD/$MDEV >& /dev/null ; then
						cryptsetup --key-file=$CRYPT_KEYFILE luksOpen $PWD/$MDEV $MDEV-crypt
					fi
				fi
			else
				logger -t hot "No cryptsetup support found for partition type \"$fstype\" in \"$MDEV\""
			fi
			return 0
			;;
		*)
			logger -t hot "unknown partition type \"$fstype\" in \"$MDEV\""
			return 0
			;;
	esac

	lbl=$(echo $LABEL | tr ' ' '_')

	if test -z "$lbl"; then
#		if test ${MDEV:0:3} = "dm-" -a -x /usr/sbin/dmsetup; then
#			lbl=$(dmsetup info -c --noheadings -o name /dev/$MDEV)
		if test ${MDEV:0:3} = "dm-"; then
			lbl=$(cat /sys/block/$MDEV/dm/name)
		else
			lbl=$MDEV
		fi
	fi

	/bin/mkdir -p /mnt/$lbl
	if mountpoint /mnt/$lbl; then return 0; fi

	# do fsck in the background, to not stop the boot process
	hot_aux.sh $fsckcmd $fsopt $mopts $lbl $fstype &

elif test "$ACTION" = "add" -a "$DEVTYPE" = "disk"; then

	if test -d /sys/block/$MDEV/md; then # md disk
		echo $MDEV: NO PARTITION BASED MD

	else # "normal" disk (not md)

		# which bay?	
		# dont use PHYSDEVPATH, for easy mounting disks in /etc/init.d/rcS 
		PHYSD=$(readlink /sys/block/$MDEV/device) 
		if $(echo $PHYSD | grep -q /host0/); then
			bay="right"
		elif $(echo $PHYSD | grep -q /host1/); then
			bay="left"
		elif $(echo $PHYSD | grep -q /usb1/); then
			bay="usb"${MDEV:2}
		fi
	
		if test -n "$bay"; then
			sed -i '/^'$bay'_/d' $BAYC
			sed -i '/^'$MDEV'/d' $BAYC

			eval $(smartctl -i $PWD/$MDEV | awk '
				/^Model Family/ {printf "fam=\"%s\";", substr($0, index($0,$3))}
				/^Device Model/ {printf "mod=\"%s\";", substr($0, index($0,$3))}
				/^SMART support is:.*Enabled/ {print "smart=yes;"}')

			if test -z "$smart"; then
				fam="$(cat /sys/block/$MDEV/device/vendor)"
				mod="$(cat /sys/block/$MDEV/device/model)"
			fi
			cap="$(awk '{printf "%.1f GB", $0 * 512 / 1e9}' /sys/block/$MDEV/size)"
			echo ${bay}_dev=$MDEV >> $BAYC
			echo $MDEV=${bay} >> $BAYC
			echo ${bay}_cap=\"$cap\" >> $BAYC
			echo ${bay}_fam=\"$fam\" >> $BAYC
			echo ${bay}_mod=\"$mod\" >> $BAYC

			if test -f $MISCC; then
				. $MISCC

				# set advanced power management
				eval pm=$(echo \$HDPOWER_$bay | tr 'a-z' 'A-Z' )
				if test -n "$pm"; then
					hdparm -B $pm $PWD/$MDEV
				fi

				# set disk spin down
				eval tm=$(echo \$HDSLEEP_$bay | tr 'a-z' 'A-Z' )
				if test -n "$tm"; then
		
					if test "$tm" -le "20"; then
						val=$((tm * 60 / 5))
					elif test "$tm" -le "300"; then
						val=$((240 + tm / 30))
					fi
					hdparm -S $val $PWD/$MDEV
				fi

				if rcsmart status; then
					rcsmart reload
				fi
			fi
		fi

		# no low latency (server, not desktop)
		echo 0 > /sys/block/$MDEV/queue/iosched/low_latency
	
		# for now use only disk partition-based md
		if ! fdisk -l /dev/$MDEV | awk '$6 == "da" || $6 == "fd" || $6 == "fd00" { exit 1 }'; then
			mdadm --examine --scan > $MDADMC
		fi
	fi

elif test "$ACTION" = "remove" -a "$DEVTYPE" = "disk"; then

	mdadm --examine --scan > $MDADMC
	blkid -g

	# remove some modules (repeat it while there are some?)
	lsmod | awk '{if ($3 == 0 && $1 != "usblp") system("modprobe -r " $1)}'

	. $BAYC
	bay=$(eval echo \$$MDEV)
	if test -n "$bay"; then
		sed -i '/^'$bay'_/d' $BAYC
		sed -i '/^'$MDEV'/d' $BAYC
	fi

	if rcsmart status >& /dev/null; then
		rcsmart reload
	fi

elif test "$ACTION" = "remove" -a "$DEVTYPE" = "partition"; then

	ret=0
	mdadm --examine --scan > $MDADMC

	mpt=$(awk '/'$MDEV'/{print $2}' /proc/mounts )
	if $(grep -q -e ^$PWD/$MDEV /proc/swaps); then
		swapoff $PWD/$MDEV
		ret=$?
		ns=$(awk '/SwapTotal:/{ns = $2 * 0.1 / 1000; if (ns < 32) ns = 32; printf "%d", ns}' /proc/meminfo)
		mount -o remount,size=${ns}M /tmp
	elif $(grep -q -e ^$PWD/$MDEV /proc/mounts); then
		if test "$(readlink -f /ffp)" = "$mpt/ffp"; then
			if test -x /etc/init.d/S??ffp; then
				/etc/init.d/S??ffp stop
			fi
			rm -f /ffp
		fi

		if test "$(readlink -f /home)" = "$mpt/Users"; then
			rm -f /home
		fi

		if test "$(readlink -f /Public)" = "$mpt/Public"; then
			rm -f /Public
		fi

		if test "$(readlink -f /Backup)" = "$mpt/Backup"; then
			rm -f /Backup
		fi

 		if test "$(readlink -f /Alt-F)" = "$mpt/Alt-F"; then
 			mount -t aufs -o remount,del:$mpt/Alt-F /
			if test $? = "0"; then
				loadsave_settings -fa
				rm -f /Alt-F
				rm -f /$mpt/Alt-F//README.txt
			else
				return 1	# busy?
			fi
 		fi
		
		umount $mpt
		ret=$?
		if test "$ret" = "0"; then
			rmdir $mpt
		else
			umount -r $mpt # damage control
		#	ret=$?	# "eject" should fail.
		fi
		
	elif test -e /proc/mdstat -a -n "$(grep $MDEV /proc/mdstat)"; then
		eval $(mdadm --examine --export $PWD/$MDEV)
		md=$(ls /sys/block/${MDEV%%[0-9]}/$MDEV/holders) # 0.9 metadata
		type=$MD_LEVEL
		if test -n "$md" -a -b $PWD/$md ; then
			act=$(cat /sys/block/$md/md/array_state)
			eval $(mdadm --detail $PWD/$md | awk \
				'/Active Devices/{ printf "actdev=%s;", $4}
				/Working Devices/{ printf "workdev=%s;", $4}')
			if test "$actdev" = 2; then # FIXME
				other=$(ls /sys/block/$md/slaves/ | grep -v $MDEV)
			fi
			if test "$act" != "inactive" -a \( \
				\( "$type" = "raid1" -a "$actdev" = 2 \) -o \
				\( "$type" = "raid5" -a "$actdev" = 3 \) \) ; then
				mdadm $PWD/$md --fail $PWD/$MDEV --remove $PWD/$MDEV
				return $ret
			elif $(grep -q ^$PWD/$md /proc/mounts); then
				(cd /dev && ACTION=remove DEVTYPE=partition PWD=/dev MDEV=$md /usr/sbin/hot.sh)
				if test $? != 0; then return 1; fi
				mdadm --stop $PWD/$md
				mdadm --incremental --run $PWD/$other
			else
				mdadm --stop $PWD/$md
				if test -n "$other"; then
					mdadm --incremental --run $PWD/$other
				fi
				return $ret
			fi
		fi
	fi

	if test "$ret" = "0"; then
		touch -r $FSTAB /tmp/fstab_date
		sed -i '\|^'$PWD/$MDEV'|d' $FSTAB
		touch -r /tmp/fstab_date $FSTAB
		rm /tmp/fstab_date
	fi
	return $ret	

elif test "$ACTION" = "add" -a "$PHYSDEVDRIVER" = "usblp"; then
	sysd="/sys/class/usb/$MDEV//device/ieee1284_id"
	if test -f "$sysd"; then
	  eval $(sed -e 's/:/="/g' -e 's/;/";/g' "$sysd") >/dev/null 2>&1
	fi
	model=${MDL:-$MODEL}
	mfg=${MFG:-$MANUFACTURER}

	mkdir -p /var/spool/lpd/$MDEV
	sed -i '/^'$MDEV'|/d' $PCAP
	echo "$MDEV|$mfg $model" >> $PCAP 
	rcsmb reload

elif test "$ACTION" = "remove" -a "$PHYSDEVDRIVER" = "usblp"; then
	rmdir /var/spool/lpd/$MDEV
	sed -i '/^'$MDEV'|/d' $PCAP

	if test -e $PCAP -a ! -s $PCAP; then
		rm $PCAP
	fi
	rcsmb reload

else
	logger -t hot "WHAT?"
	logger -t hot "$(env)"
fi
