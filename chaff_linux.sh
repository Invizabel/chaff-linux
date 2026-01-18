#!/bin/bash
set -e

sudo rm -rf ~/LIVE_BOOT

sudo apt-get install -y \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-efi \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-efi-ia32-bin \
    mtools \
    dosfstools

export PATH=$PATH:/sbin:/usr/sbin

# Setup base folders
mkdir -p "${HOME}/LIVE_BOOT"/{chroot,tmp,staging/{EFI/BOOT,boot/grub/x86_64-efi,isolinux,live}}

# Bootstrap minimal Debian system
sudo debootstrap --arch=amd64 --variant=minbase stable \
    "${HOME}/LIVE_BOOT/chroot" \
    http://ftp.us.debian.org/debian/

echo "chaff-linux" | sudo tee "${HOME}/LIVE_BOOT/chroot/etc/hostname"

# Install system packages
sudo chroot "${HOME}/LIVE_BOOT/chroot" bash -c "
apt-get update &&
apt-get install -y linux-image-amd64 live-boot systemd-sysv python3 python3-pip &&
echo 'root:chaff' | chpasswd &&
pip install chaff --break-system-packages
"

# Generate squashfs (minus /boot)
sudo mksquashfs "${HOME}/LIVE_BOOT/chroot" "${HOME}/LIVE_BOOT/staging/live/filesystem.squashfs" -e boot

# Copy kernel and initrd
KERNEL=$(basename $(ls -1t ${HOME}/LIVE_BOOT/chroot/boot/vmlinuz-* | head -n1))
INITRD=$(basename $(ls -1t ${HOME}/LIVE_BOOT/chroot/boot/initrd.img-* | head -n1))

cp "${HOME}/LIVE_BOOT/chroot/boot/${KERNEL}" "${HOME}/LIVE_BOOT/staging/live/vmlinuz"
cp "${HOME}/LIVE_BOOT/chroot/boot/${INITRD}" "${HOME}/LIVE_BOOT/staging/live/initrd"

# ISOLINUX config for BIOS boot
cat <<'EOF' > "${HOME}/LIVE_BOOT/staging/isolinux/isolinux.cfg"
UI vesamenu.c32

MENU TITLE Boot Menu
DEFAULT chaff
TIMEOUT 600

LABEL chaff
  MENU LABEL Chaff Linux [BIOS/ISOLINUX]
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live

LABEL chaff-nomodeset
  MENU LABEL Chaff Linux [BIOS/ISOLINUX] (nomodeset)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live nomodeset
EOF

# GRUB config for UEFI
cat <<'EOF' > "${HOME}/LIVE_BOOT/staging/boot/grub/grub.cfg"
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod all_video
insmod font

set default="0"
set timeout=30

menuentry "Chaff Linux [EFI/GRUB]" {
    search --no-floppy --set=root --label CHAFF
    linux ($root)/live/vmlinuz boot=live
    initrd ($root)/live/initrd
}

menuentry "Chaff Linux [EFI/GRUB] (nomodeset)" {
    search --no-floppy --set=root --label CHAFF
    linux ($root)/live/vmlinuz boot=live nomodeset
    initrd ($root)/live/initrd
}
EOF

cp "${HOME}/LIVE_BOOT/staging/boot/grub/grub.cfg" "${HOME}/LIVE_BOOT/staging/EFI/BOOT/"

# Embed config for GRUB standalone
cat <<'EOF' > "${HOME}/LIVE_BOOT/tmp/grub-embed.cfg"
if ! [ -d "$cmdpath" ]; then
    if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "$cmdpath"; then
        cmdpath="${isodevice}/EFI/BOOT"
    fi
fi
configfile "${cmdpath}/grub.cfg"
EOF

# ISOLINUX binaries
cp /usr/lib/ISOLINUX/isolinux.bin "${HOME}/LIVE_BOOT/staging/isolinux/"
cp /usr/lib/syslinux/modules/bios/* "${HOME}/LIVE_BOOT/staging/isolinux/"

# GRUB UEFI binaries
cp -r /usr/lib/grub/x86_64-efi/* "${HOME}/LIVE_BOOT/staging/boot/grub/x86_64-efi/"

# Build EFI bootloaders
grub-mkstandalone -O i386-efi \
  --modules="part_gpt part_msdos fat iso9660" \
  --locales="" --themes="" --fonts="" \
  --output="${HOME}/LIVE_BOOT/staging/EFI/BOOT/BOOTIA32.EFI" \
  "boot/grub/grub.cfg=${HOME}/LIVE_BOOT/tmp/grub-embed.cfg"

grub-mkstandalone -O x86_64-efi \
  --modules="part_gpt part_msdos fat iso9660" \
  --locales="" --themes="" --fonts="" \
  --output="${HOME}/LIVE_BOOT/staging/EFI/BOOT/BOOTx64.EFI" \
  "boot/grub/grub.cfg=${HOME}/LIVE_BOOT/tmp/grub-embed.cfg"

# Create EFI system partition image
(cd "${HOME}/LIVE_BOOT/staging" && \
    dd if=/dev/zero of=efiboot.img bs=1M count=20 && \
    mkfs.vfat efiboot.img && \
    mmd -i efiboot.img ::/EFI ::/EFI/BOOT && \
    mcopy -vi efiboot.img \
        EFI/BOOT/BOOTIA32.EFI \
        EFI/BOOT/BOOTx64.EFI \
        boot/grub/grub.cfg \
        ::/EFI/BOOT/
)

# Build ISO
xorriso -as mkisofs \
  -iso-level 3 \
  -o "${HOME}/LIVE_BOOT/chaff-linux.iso" \
  -full-iso9660-filenames \
  -volid "CHAFF" \
  --mbr-force-bootable -partition_offset 16 \
  -joliet -joliet-long -rational-rock \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -eltorito-boot isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --eltorito-catalog isolinux/isolinux.cat \
  -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot -isohybrid-gpt-basdat \
  -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "${HOME}/LIVE_BOOT/staging/efiboot.img" \
  "${HOME}/LIVE_BOOT/staging"
