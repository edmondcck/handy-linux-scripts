#!/bin/bash
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#  Filename: resize_san_pv.sh
#  Description: In Linux, it takes many steps to extend the PV after the PV's
#               underlying LUN in the SAN Storage has been expanded. This
#               script helps to automate all the necessary steps. All you need
#               to do is to provide the VG name to the script.
#  Usage: resize_san_pv.sh <VG name>

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 [VGNAME]" >&2
  exit 1
fi

VGNAME=$1

vgs ${VGNAME} > /dev/null 2>&1
VGCHECK=$?
if [ ${VGCHECK} -ne 0 ]; then
  echo "Input parameter VGNAME = '${VGNAME}' is invalid. Likely this VG does not exist." >&2
  exit 1
fi

# Issue command to scan storage interconnects
echo "Issuing commands to scan storage interconnects..."
echo "1" > /sys/class/fc_host/host1/issue_lip
echo "1" > /sys/class/fc_host/host2/issue_lip
sleep 3

# Rescan Multipath devices
echo "Looking for multipath devices of volume group '$VGNAME' to rescan..."
for i in `pvscan | grep $VGNAME | awk '{print $2}' | awk -F/ '{print $4}'`
do
  echo " ... Multipath device $i found for volume group '$VGNAME', searching for underlying SCSI devices to rescan..."
  for j in `multipath -ll $i | egrep -v "mpath|size|policy" | sed 's/|//g' | awk '{print $3}'`
  do
    echo "      ... Issuing command to rescan SCSI device '$j'..."
    echo 1 > /sys/block/$j/device/rescan
  done
done
sleep 3

# Detect new size on Multipath level
echo "Detecting new disk size on multipath level for volume group '$VGNAME'..."
for i in `pvscan | grep $VGNAME | awk '{print $2}' | awk -F/ '{print $4}'`
do
  echo " ... Resizing multipath device '$i'..."
  multipathd -k"resize map $i"
done

# Resize physical volume
echo "Resizing physical volume(s) for volume group '$VGNAME'..."
for i in `pvscan | grep $VGNAME | awk '{print $2}'`
do
  echo " ... Resizing physical volume '$i'..."
  pvresize $i
done

echo "Resize physical volumes for volume group '$VGNAME' completed!"
