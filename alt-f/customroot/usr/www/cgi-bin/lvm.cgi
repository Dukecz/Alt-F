#!/bin/sh

. common.sh
check_cookie
write_header "LVM Setup"

echo "<h3><center><font color=red>Work in progress, don't use for serious work.</font></center></h3>"

CONFF=/etc/misc.conf

if test -f $CONFF; then
	. $CONFF
fi

#rclvm load >& /dev/null

blkid -t TYPE="lvm2pv" > /dev/null
no_pv=$?

# FIXME no check is made to see if a partition already is a PV or if a PV belongs to another VG!
# pvdisplay --noheadings --separator ':' -C /dev/$pdev | awk -F: '{printf "vg=%s", $2}'

devs=$(fdisk -l /dev/sd? 2> /dev/null | awk 'substr($1,1,5) == "/dev/" && ($5 == "8e" || $5 == "8e00") {
	found = 1; dev=substr($1, 6); "grep " dev " /proc/partitions" | getline
	printf "<option value=%s>%s (%.1f GB)</option>\n", dev, dev, $3*1024/1e9}
	END {exit found}')
no_part=$?

if test $no_pv != 0 -a $no_part = 0; then
	echo "No Physical Volumes nor LVM partitions found."
	exit 0
fi

cat<<EOF
	<form id="lvmf" action="/cgi-bin/lvm_proc.cgi" method="post">
	<fieldset><legend><strong>Volume Group</strong></legend>
	<table style="border-collapse:collapse">
	<colgroup span=4></colgroup>
	<colgroup span=4 style="background:#ddd;"></colgroup>
EOF

vg=$(vgs --noheadings --units g 2>&1)

if ! echo $vg | grep -qi 'No volume groups'; then
	echo "<tr><th>Group</th><th>Capacity</th><th>Free</th><th></th>
		<th colspan=4>Manage Physical Volumes</th></tr>"

	i=1
	echo "$vg" | while read vgname pvcount lvcount t1 attr cap free; do

		# Device error: "Couldn't find device with uuid mbXtaf-..."
		# FIXME: we need command stderr in string ...

		if test "$vgname" = "Couldn't" -o \
			"$vgname" = "Failure" -o \
			"$vgname" = "Check" -o \
			"$vgname" = "/dev/mapper/control:" -o \
			"$lvcount" = "failed"; then
				continue
		fi

		dvgname=$vgname
		if test ${attr:3:1} = "p"; then
			dvgname="<font color=red>$vgname</font>"
		fi

		cat<<-EOF
			<tr><td align=center>$dvgname</td>
			<td align=center>${cap%g}GB</td><td align=center>${free%g}GB</td>
			<td><input type="submit" name=$vgname value="Destroy"></td>
			<td><select name=pdev_$i><option value=none>Select a Partition</option>$devs</select></td>
			<td><input type="submit" name=$i value="Add"></td>
			<td><input type="submit" name=$i value="Remove"></td>
			<td><input type="submit" name=$i value="Empty"></td>
		EOF
		echo "</tr>"
		i=$((i+1))
	done
fi

VG=altf
vgdisplay $VG >& /dev/null
altfvg=$?

if test $altfvg != 0; then
	cat<<-EOF
		<tr><td><br></td></tr><tr><td colspan=5>No Alt-F Volume Group detected
		<select name=pdev><option value=none>Select a Partition</option>$devs</select>
		<input type="submit" name=action value="VGCreate"></td></tr>
	EOF
fi

pvd=$(pvs --noheadings --separator ';' --nosuffix --units g 2> /dev/null)
IFS=';'

if test -n "$pvd"; then
	cat<<-EOF
		</table></fieldset><br>
		<fieldset><legend><strong>Physical Volumes</strong></legend>
		<table style="border-collapse:collapse">
		<colgroup span=4></colgroup>
		<colgroup span=1 style="background:#ddd;"></colgroup>
		<tr><th>Dev</th><th>Group</th><th>Capacity</th><th>Free</th><th>In use by</th></tr>
	EOF

	echo "$pvd" | while read pdev vg fmt attr cap free; do

		if test -z "$vg"; then vg="--"; fi

		if echo "$pdev" | grep -q "unknown device"; then
			inuse=""
			pdev="<font color=red>missing</font>"
		else
			pdev=$(basename $pdev)
			inuse=$(pvdisplay --map /dev/$pdev 2> /dev/null | sed -n -e '/mlog/d' \
				-e 's/_mimage_.*//' -e '\|Logical volume|s|.*dev/'$vg'/||p')
		fi

		cat<<-EOF
			<tr><td>$pdev</td><td align=center>$vg</td>
			<td align=center>${cap}GB</td><td align=center>${free}GB</td>
			<td>$inuse</td></tr>
		EOF
	done
	
	echo "</table>"
	if echo "$pvd" | grep -q "unknown device"; then
		echo "<p>Missing volumes:<input type=submit name=rmMissing value=\"Force Removal\">"
	fi
	echo "</fieldset><br>"
fi

lvd=$(lvs -a --separator ';' --noheading -o +segtype --units g 2>/dev/null)

if test "$altfvg" = 0 -o -n "$lvd"; then
	cat<<-EOF
		<fieldset><legend><strong>Logical Volumes</strong></legend>
		<table style="border-collapse:collapse">
		<colgroup span=6></colgroup>
		<colgroup span=3 style="background:#ddd;"></colgroup>
	EOF

	if test -n "$lvd"; then
		i=1
		echo "<tr><th>Dev</th><th>Group</th><th>Type</th><th>Capacity</th><th></th>
			<th>Operations</th><th colspan=3>Manage Capacity</th></tr>"

		echo "$lvd" | while read ldev vg attr cap orig snap move log copy conv type; do

			# Device error: "Couldn't find device with uuid mbXtaf-..."
			# do we need command stderr in string? 
			if test "$ldev" = "Couldn't"; then continue; fi

			if echo "$ldev" | grep -qE _mimage_\|_mlog; then continue; fi

			dldev=$ldev
			if test ${attr:4:1} != "a"; then
				dldev="<font color=red>$ldev</font>"
			fi

			all_dis=""
			if echo "$ldev" | grep -q pvmove; then all_dis=disabled; fi

			dis_tolin=""; dis_tomirr=""; dis_csnap=""; dis_msnap=""; dis_split="disabled"

			if test -n "$snap"; then
				dis_csnap="disabled"
				dis_tolin="disabled"
				dis_tomirr="disabled"
			else
				dis_msnap="disabled"
			fi

			case  $type in
				linear) dis_tolin="disabled" ;;
				mirror)	dis_tomirr="disabled"; dis_split="" ;;
				striped) dis_tomirr="disabled"; dis_tolin="disabled" ;;
			esac

			op=""
			if test -n "$copy" -a -n "$move"; then op="<font color=red>copy $move ${copy%.*}%</font>"
			elif test -n "$copy" -a "$copy" != "100.00"; then op="<font color=red>copy ${copy%.*}%</font>"
			elif test -n "$move"; then op="<font color=red>move ${move%.*}%</font>"
			elif test -n "$snap"; then op="<font color=red>snap ${snap%.*}%</font>"; fi

			# not needed
			# all_dis=""
			# if test -n "$move" -o -n "$copy"; then all_dis="disabled"; fi

			cat<<-EOF
				<tr><td align=center>$dldev</td><td align=center>$vg</td>
				<td>$type</td>
				<td align=center>${cap%g}GB</td><td>$op</td>
				<td><input type=hidden name=vg_$i value="$vg">
					<input type=hidden name=ldev_$i value="$(echo $ldev | tr -d ' ')">
					<select $all_dis name=$i onchange="return submit()"> 			
						<option value="none">Operation</option>
						<option value=delete>Delete</option>
						<option $dis_tolin value=tolinear>Conv. to Linear</option>
						<option $dis_tomirr value=tomirror>Conv. to Mirror</option>
						<option $dis_csnap value=csnap>Create Snapshot</option>
						<option $dis_msnap value=msnap>Merge Snapshot</option>
						<option $dis_split value=split>Split</option>
					</select></td>
				<td><input $all_dis type=submit name=$i value="Enlarge"></td>
				<td><input $all_dis type=submit name=$i value="Shrink"></td>
				<td>&nbsp; <em>by</em> <input $all_dis type=text size=4 name=ncap_$i value="">GB</td>
				</tr>
			EOF
			i=$((i+1))
		done
	fi

	if test "$altfvg" = 0; then
		cat<<-EOF
			</table><br> New 
			<select name=type><option>Linear</option><option>Mirror</option>
			<option>Stripped</option></select> volume with
			<input type=text size=4 name=lvsize> GB
			<input type=submit name=action value="Create">
			</fieldset>
		EOF
	fi

fi

echo "</form></body></html>"
