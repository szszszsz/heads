#!/bin/sh
#
set -e -o pipefail
. /etc/functions
. /tmp/config

mount_usb(){
# Mount the USB boot device
if ! grep -q /media /proc/mounts ; then
  mount-usb "$CONFIG_USB_BOOT_DEV" || USB_FAILED=1
  if [ $USB_FAILED -ne 0 ]; then
    if [ ! -e "$CONFIG_USB_BOOT_DEV" ]; then
      whiptail --title 'USB Drive Missing' \
        --msgbox "Insert your USB drive and press Enter to continue." 16 60 USB_FAILED=0
        mount-usb "$CONFIG_USB_BOOT_DEV" || USB_FAILED=1
    fi
    if [ $USB_FAILED -ne 0 ]; then
      whiptail $CONFIG_ERROR_BG_COLOR --title 'ERROR: Mounting /media Failed' \
        --msgbox "Unable to mount $CONFIG_USB_BOOT_DEV" 16 60
    fi
  fi
fi
}

if (whiptail $CONFIG_WARNING_BG_COLOR --clear --title 'Factory Reset and reownership of GPG card' \
  --yesno "You are about to factory reset your GPG card!\n\nThis will:\n 1-Wipe all PRIVATE keys that were previously kept inside GPG card\n 2-Set default key size to 4096 bits (maximum)\n 3-Ask you to choose two passwords to interact with the card:\n  3.1: An admininstrative passphrase used to manage the card\n  3.2: A user passphrase (PIN) used everytime you sign\n   encrypt/decrypt content\n4-Generate new Encryption, Signing and Authentication keys\n  inside your GPG card\n5-Export associated public key, replace the one being\n  present and trusted inside running BIOS, and reflash\n  SPI flash with resulting rom image.\n\nAs a result, the running BIOS will be modified.\n\nWould you like to continue?" 30 90) then

  #TODO: Circumvent permission bug with mkdir and chmod permitting to use gpg --home=/media/gpg_keys directly. 
  #Cannot create a new gpg homedir with right permissions nor chmod 700 that directory.
  #Meanwhile, we reuse /.gnupg by temporarely deleting it's existing content.
  rm -rf .gnupg/*

  #Setting new passwords
  gpgcard_user_pass1=1
  gpgcard_user_pass2=2
  gpgcard_admin_pass1=3
  gpgcard_admin_pass2=4

  while [[ "$gpgcard_user_pass1" != "$gpgcard_user_pass2" ]] || [[ ${#gpgcard_user_pass1} -lt 6 || ${#gpgcard_user_pass1} -gt 20 ]];do
  {
    echo -e "Choose your new GPG card user password (PIN) that will be typed when using GPG smartcard (Sign files, encrypt emails and files).\nIt needs to be a least 6 but not more then 20 characters:"
    read -s gpgcard_user_pass1
    echo "Retype user passphrase:"
    read -s gpgcard_user_pass2
    if [[ "$gpgcard_user_pass1" != "$gpgcard_user_pass2" ]]; then echo "Passwords typed were different."; fi
  };done
  gpgcard_user_pass=$gpgcard_user_pass1

  while [[ "$gpgcard_admin_pass1" != "$gpgcard_admin_pass2" ]] || [[ ${#gpgcard_admin_pass1} -lt 8 || ${#gpgcard_admin_pass1} -gt 20 ]]; do
  {
    echo -e "\nChoose your new GPG card admin password that will be typed when managing GPG smartcard (HTOP sealing, managing key, etc).\nIt needs to be a least 8 but not more then 20 characters:"
    read -s gpgcard_admin_pass1
    echo "Retype admin password:"
    read -s gpgcard_admin_pass2

    if [[ "$gpgcard_admin_pass1" != "$gpgcard_admin_pass2" ]]; then echo "Passwords typed were different."; fi
  };done
  gpgcard_admin_pass=$gpgcard_admin_pass1

  echo -e "\n\n"
  echo -e "We will generate a GnuPG (GPG) keypair identifiable with the following text form:"
  echo -e "Real Name (Comment) email@address.org\n"
  echo -e "Enter your Real Name:"
  read gpgcard_real_name
  echo "Enter your email@adress.org:"
  read gpgcard_email_address
  echo "Enter Comment (To distinguish this key from others with same previous attributes):"
  read gpgcard_comment

  whiptail $CONFIG_WARNING_BG_COLOR --clear --title 'WARNING: Please Insert A USB Disk' --msgbox \
  "Please insert a USB disk on which you want to store your GPG public key\n and trustdb.\n\nThose will be backuped under the 'gpg_keys' directory.\n\nHit Enter to continue." 30 90     

  mount_usb

  #Copy generated public key, private_subkey, trustdb and artifacts to external media for backup:
  mount -o remount,rw /media

  #backup existing /media/gpg_keys directory
  if [ -d /media/gpg_keys ];then
    newdir="/media/gpg_keys-$(date '+%Y-%m-%d-%H_%M_%S')"
    echo "Backing up /media/gpg_keys into $newdir"
    mv /media/gpg_keys "$newdir"
  fi

  mkdir -p /media/gpg_keys

  #Generate Encryption, Signing and Authentication keys
  whiptail --clear --title 'GPG card key generation' --msgbox \
  "BE PATIENT! Generating 4096 bits Encryption, Signing and Authentication\n keys take around 5 minutes each! Be prepared to patient around 15 minutes!\n\nHit Enter to continue" 30 90

  confirm_gpg_card

  #Factory reset GPG card
  {
    echo admin
    echo factory-reset
    echo y
    echo yes
  } | gpg --command-fd=0 --status-fd=1 --pinentry-mode=loopback --card-edit --home=/.gnupg/

  #Setting new admin and user passwords in GPG card
  {
    echo admin
    echo passwd
    echo 1
    echo 123456 #Default user password after factory reset of card
    echo "$gpgcard_user_pass"
    echo "$gpgcard_user_pass"
    echo 3
    echo 12345678 #Default administrator password after factory reset of card
    echo "$gpgcard_admin_pass"
    echo "$gpgcard_admin_pass"
    echo Q
  } | gpg --command-fd=0 --status-fd=2 --pinentry-mode=loopback --card-edit --home=/.gnupg/

  #Set GPG card key attributes key sizes to 4096 bits
  {
    echo admin
    echo key-attr
    echo 1 # RSA
    echo 4096 #Signing key size set to maximum supported by SmartCard
    echo "$gpgcard_admin_pass"
    echo 1 # RSA
    echo 4096 #Encryption key size set to maximum supported by SmartCard
    echo "$gpgcard_admin_pass"
    echo 1 # RSA
    echo 4096 #Authentication key size set to maximum supported by SmartCard
    echo "$gpgcard_admin_pass"
  } | gpg --command-fd=0 --status-fd=2 --pinentry-mode=loopback --card-edit --home=/.gnupg/

  {
    echo admin
    echo generate
    echo n
    echo "$gpgcard_admin_pass"
    echo "$gpgcard_user_pass"
    echo 1y
    echo "$gpgcard_real_name"
    echo "$gpgcard_email_address"
    echo "$gpgcard_comment"
  } | gpg --command-fd=0 --status-fd=2 --pinentry-mode=loopback --card-edit --home=/.gnupg/

  #Export and inject public key and trustdb export into extracted rom with current user keys being wiped
  rom=/tmp/gpg-gui.rom
  #remove invalid kexec_* signed files
  mount -o remount,rw /boot
  rm -f /boot/kexec*
  mount -o remount,ro /boot

  gpg --home=/.gnupg/ --export --armor "$gpgcard_email_address"  > /media/gpg_keys/public.key
  #TODO: append this to cp commands below: 2> /dev/null
  cp -rf /.gnupg/openpgp-revocs.d/* /media/gpg_keys/
  cp -rf /.gnupg/private-keys-v1.d/* /media/gpg_keys/
  cp -rf /.gnupg/pubring.* /.gnupg/trustdb.gpg /media/gpg_keys/

  #Flush changes to external media
  mount -o remount,ro /media

  #Read rom
  /bin/flash.sh -r $rom

  #delete previously injected public.key
  if (cbfs -o $rom -l | grep -q "heads/initrd/.gnupg/keys/public.key"); then
    cbfs -o $rom -d "heads/initrd/.gnupg/keys/public.key"
  fi
  
  #delete previously injected GPG1 and GPG2 pubrings
  if (cbfs -o $rom -l | grep -q "heads/initrd/.gnupg/pubring.kbx"); then
    cbfs -o $rom -d "heads/initrd/.gnupg/pubring.kbx"
    if (cbfs -o $rom -l | grep -q "heads/initrd/.gnupg/pubring.gpg"); then
      cbfs -o $rom -d "heads/initrd/.gnupg/pubring.gpg"
      if [ -e /.gnupg/pubring.gpg ];then
        rm /.gnupg/pubring.gpg
      fi
    fi
  fi
  #delete previously injected trustdb
  if (cbfs -o $rom -l | grep -q "heads/initrd/.gnupg/trustdb.gpg") then
    cbfs -o $rom -d "heads/initrd/.gnupg/trustdb.gpg"
  fi
  #Remove old method of exporting/importing owner trust exported file
  if (cbfs -o $rom -l | grep -q "heads/initrd/.gnupg/otrust.txt") then
    cbfs -o $rom -d "heads/initrd/.gnupg/otrust.txt"
  fi

  #Insert public key in armored form and trustdb ultimately trusting user's key into reproducible rom:
  cbfs -o "$rom" -a "heads/initrd/.gnupg/pubring.kbx" -f /.gnupg/pubring.kbx
  cbfs -o "$rom" -a "heads/initrd/.gnupg/trustdb.gpg" -f /.gnupg/trustdb.gpg

  if (whiptail --title 'Flash ROM?' \
    --yesno "This will replace your old ROM with $rom\n\nDo you want to proceed?" 16 90) then
    /bin/flash.sh $rom
    whiptail --title 'ROM Flashed Successfully' \
      --msgbox "New $rom flashed successfully.\n\nIf your keys have changed, be sure to re-sign all files in /boot\nafter you reboot.\n\nPress Enter to continue" 16 60
    if [ -s /boot/oem ];then
      mount -o remount,rw /boot
      echo gpg_factory_resetted >> /boot/oem
      mount -o remount,ro /boot
    fi
    umount /media
    else
      exit 0
  fi

  whiptail $CONFIG_WARNING_BG_COLOR --clear --title 'WARNING: Reboot required' --msgbox \
    "A reboot is required.\n\n Your firmware has been reflashed with your own public key and trustdb\n included.\n\n Heads will detect it and react accordingly:\n It will ask you to regenerate a new TOTP/HOTP code (seal BIOS integrity),\n take /boot integrity measures and sign them with your freshly\n factory resetted GPG card user password (PIN).\n\nHit Enter to reboot." 30 90
  /bin/reboot
fi