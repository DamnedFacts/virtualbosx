# virtualbosx
A HOWTO on installing OS X as a guest on VirtualBox

This script is a straightfoward way of creating a bootable disk image of the OS X installer.

# Step 1: Create an installer DMG
Most steps I've found for creating a bootable disk for the OS X installer involve a whole lot of complicated copying of files to different directories and images. There is actually a far more straightforward technique, and some technical gotchas.

First, create a empty, 8GB large file to act as a "USB drive" for VirtualBox. It's attached to your VirtualBox VM as a SATA drive, not a CD ISO. You'll need to keep it attached once (or, permanenetly if you want the option of booting a separate recovery disk - your choice).

We used Apple's 'hdiutil' to do this. Since the Read-Write version of OS X disk images (DMGs) are just raw disk image files, this benefits us later on. This disk image is formatted as a GPT partitioned disk with one HFS+ partition, and then mounted.

`hdiutil create -attach -size 8GB -type UDIF -layout MBRSPUD -fs HFS+ -volname Untitled ~/Desktop/osx-installer.dmg`

# Step 2: Install the installer files
Secondly, we use the `createinstallmedia` command-line tool that comes with "Install OS X El Capitan.app" (and previous versions of OS X) to create a bootable installer user this mounted disk image:

`sudo createinstallmedia --volume /Volumes/Untitled --applicationpath "/Applications/Install OS X El Capitan.app"`

## Step 2a: HFS+, Hard Links and EFI issue
Once that completes we use the 'find' to look for any file inodes on our installer disk image with more than 1 hard link. Apparently, VirtualBox's EFI implementation (maybe?) can't read files with multiple hard links on an HFS+ volume. They show up as zero file size and prevent booting.

# Step 3: Turn on verbose booting
Penultimately, a plist file `com.apple.Boot.plist` on the installer image needs to be edited to add a '-v' kernel flag to force the OS X installer to boot in verbose mode. Not doing this makes the booting installer disk attempt some sort of EFI graphics detection which fails on VirtualBox with an obscure "Guru Mediation" error. Verbose booting avoids this. This uses Apple's `plutil`.

# Step 4: Make a VirtualBox VM for OS X
Lastly, create an OS X virtual machine in VirtualBox. This step can be done using the VirtualBox GUI, or, using the VBoxManage  command-line utility (as this script uses).

## Requirements (or, non-obvious technical "gotchas"):
 * **Enable:** Extended Features: "Enable EFI"
 * **Choose:** Chipset: PIIX3 (ICH9 fails inexplicably with EFI enabled and more than 2GB of RAM)
 * **Attach:** Installer disk image must be attached as SATA port 0 or 1, only, or else the EFI won't see the disk.
