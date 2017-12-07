android-otamod
==============

Verify, modify, and re-sign an Android OTA.

Support files
-------------
### args.sh script
```bash
BOOT_SIGNER="/data/aosp/out/host/linux-x86/bin/boot_signer"
SIGNAPK_JAR="/data/aosp/prebuilts/sdk/tools/lib/signapk.jar"
BOOT_KEY_BASENAME="/data/key/boot/boot-key"
OTA_KEY_BASENAME="/data/key/ota/ota-key"
```

### modify-initrd script
Example: change a property in the initrd's default.prop
```bash
#!/bin/bash

# Toplevel script calls this after unpacking the initrd
# Assume this script is invoked in fakeroot where $PWD/ramdisk is the
# ramdisk to modify.

sed 's/^\(ro.oem_unlock_supported\)=1/\1=0/;' -i ramdisk/default.prop
```

### Google-Android-OTA-Certificate.pem
The script verifies the OTA against Google's release signing certificate before modifying it.

Invocation
----------
```bash
./split-and-verify.sh ../download/hamachi-ota-opm1.171019.011-a8e251fd.zip
```
Creates ```hamachi-ota-opm1.1271019.011-a8e251fd/signed.zip``` which can be adb sideloaded in recovery boot to update the device.

The device's recovery boot and bootloader must honor the keys used to re-sign the OTA (specified in args.sh).
