#!/bin/sh

# The MIT License (MIT)
# 
# Copyright (c) 2016 Richard E Sarkis <rich@sarkis.info>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#########################
# Configuration Variables
#########################
# Use "VBoxManage list ostypes" and pick the right ID for your OS X version.
OSX_TYPE="MacOS1011_64"
OSX_INSTALLER_APP="/Applications/Install OS X El Capitan.app"
OSX_CREATE_CMD=${OSX_INSTALLER_APP}/Contents/Resources/createinstallmedia
VM_NAME="OS X"
VM_INSTALLER_DMG=$HOME/Desktop/osx_install.dmg
VM_INSTALLER_VMDK=$HOME/Desktop/osx_install.vmdk
VM_VBOX_CMD=/usr/local/bin/VBoxManage
#########################
#########################

if [ ! -x "${OSX_INSTALLER_APP}/Contents/Resources/createinstallmedia" ]; then
    echo "Error: Missing 'createinstallmedia' command. Make sure the OS X installer is downloaded from the Mac App Store."
    exit 1
fi

if [ ! -x "${VM_VBOX_CMD}" ]; then
    echo "Error: The command 'VBoxManage' is missing. Is VirtualBox installed?"
    exit 1
fi

##
tput sgr0; tput setaf 141; tput bold; echo "Step 1: Create a blank, 8GB disk image."; tput sgr0
DMG_CREATE_OUTPUT=`hdiutil create -attach -size 8GB -type UDIF -layout MBRSPUD -fs HFS+ -volname Untitled ${VM_INSTALLER_DMG}`
DMG_MNT_PATH=`echo "${DMG_CREATE_OUTPUT}" | awk '/\/Volumes\//{ print $3 }'`
DMG_DEV_PATH=`echo "${DMG_CREATE_OUTPUT}" | awk '/\/Volumes\//{ print $1 }'`

tput sgr0; tput setaf 4; tput bold; 
echo "Disk image is located at ${VM_INSTALLER_DMG} and mounted on ${DMG_MNT_PATH} (${DMG_DEV_PATH})"
tput sgr0 

##
echo
tput sgr0; tput setaf 141; tput bold;
echo "Step 2: Create the bootable installer using this mounted disk image."; 
tput sgr0
if [ -d "${DMG_MNT_PATH}" ]; then
    tput sgr0; tput setaf 4; tput bold; 
    echo "Your user password may be needed for sudo to run the 'createinstallmedia' command."
    tput sgr0 

    sudo "${OSX_CREATE_CMD}" --volume "${DMG_MNT_PATH}" --applicationpath "${OSX_INSTALLER_APP}"
    echo 

    tput sgr0; tput setaf 4; tput bold; 
    echo "Disk image ${VM_INSTALLER_DMG}, mounted on ${DMG_MNT_PATH} (${DMG_DEV_PATH}) now mounted "
    DMG_MNT_PATH=`diskutil info "${DMG_DEV_PATH}" | awk 'BEGIN { FS = ":[ ]+" } /Mount Point/{ print $2 }'`
    echo "as ${DMG_MNT_PATH}."
    tput sgr0;

    # VirtualBox's EFI implementation doesn't read HFS inodes with more than one 
    # hard link (they appear as zero-length files). This de-couples the hard links.
    find "${DMG_MNT_PATH}" -type f -links +1 \( -exec cp -p {} {}.tmp \; -false -o -exec mv -f {}.tmp {} \; \) &> /dev/null

else
    echo exit
fi

# VirtualBox will fail into some odd 'Guru Mode' if we boot the installer 
# without verbose mode enabled. It seems it is failing on some aspect of video.
# Regardless, add '-v' to kernel flag allows it to boot properly.
CMDLINE=`defaults read "${DMG_MNT_PATH}/Library/Preferences/SystemConfiguration/com.apple.Boot.plist" "Kernel Flags"`
CMDLINE="-v "$CMDLINE
defaults write "${DMG_MNT_PATH}/Library/Preferences/SystemConfiguration/com.apple.Boot.plist" "Kernel Flags" -string "$CMDLINE"
plutil -convert xml1 "${DMG_MNT_PATH}/Library/Preferences/SystemConfiguration/com.apple.Boot.plist"

# Unmount and detach the OS X Installer disk image
hdiutil detach ${DMG_DEV_PATH} &> /dev/null

tput sgr0; tput setaf 4; tput bold; 
echo "Disk image ${VM_INSTALLER_DMG} mounted on ${DMG_MNT_PATH} has been unmounted."
tput sgr0;

##
echo
tput sgr0; tput setaf 141; tput bold; echo "Step 3: Create a VirtualBox VM with this disk image attached."; tput sgr0
VM_CREATE_OUTPUT=`VBoxManage createvm --name "${VM_NAME}" --ostype ${OSX_TYPE}`
VM_FILE=`echo "${VM_CREATE_OUTPUT}" | awk -F': ' '/Settings file:/{ print $2 }' | sed s/\'//g`
VM_UUID=`echo "${VM_CREATE_OUTPUT}" | awk -F': ' '/UUID:/{ print $2 }'`
if [ "${VM_UUID}" != "" ]; then
    ${VM_VBOX_CMD} registervm "${VM_FILE}"

    # Set to EFI mode, and PXII3 chipset as ICH3 crashes with EFI and above 2GB of RAM. 
    ${VM_VBOX_CMD} modifyvm ${VM_UUID} --chipset piix3 --firmware efi --memory 4096 --rtcuseutc on --vram 32 --mouse usb --keyboard usb

    # A VMDK shim used to map to the raw disk DMG file.
    tput sgr0; tput setaf 4; tput bold; 
    ${VM_VBOX_CMD} internalcommands createrawvmdk -filename "${VM_INSTALLER_VMDK}" -rawdisk "${VM_INSTALLER_DMG}"
    tput sgr0

    # Add a storage controller
    ${VM_VBOX_CMD} storagectl ${VM_UUID} --name "SATA" --add "sata"

    # Must be attached to SATA ports 0 or 1 (2 or greater, EFI will not map it)
    ${VM_VBOX_CMD} storageattach ${VM_UUID} --storagectl "SATA" --port 0 --medium "${VM_INSTALLER_VMDK}" --type hdd

    ${VM_VBOX_CMD} setextradata ${VM_UUID} VBoxInternal2/EfiGopMode 5


    ${VM_VBOX_CMD} setextradata ${VM_UUID} "VBoxInternal/Devices/efi/0/Config/DmiSystemSerial" \
        `system_profiler SPHardwareDataType | awk '/Serial/ {print $4}'`
    ${VM_VBOX_CMD} setextradata ${VM_UUID} "VBoxInternal2/EfiBootArgs" "-v"
else
    echo "Making a VirtualBox VM failed."
    exit
fi
echo
