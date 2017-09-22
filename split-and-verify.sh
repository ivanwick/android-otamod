#!/bin/bash

# Rely on the script to exit with openssl's error code if verification fails
set -o errexit

OTAZIP_NAME="$1"

# args.sh sets variables
#   BOOT_SIGNER aosp.../host/linux-x86/bin/boot_signer
#   SIGNAPK_JAR aosp.../sdk/tools/lib/signapk.jar
#   BOOT_KEY_BASENAME keypair passed to $BOOT_SIGNER when signing boot.img
#   OTA_KEY_BASENAME keypair passed to $SIGNAPK_JAR when signing the OTA zip
#   Keypair basenames will have ".pk8" and ".x509.pem" appended as appropriate
source args.sh

OTAMOD_DIRNAME=$(basename "$OTAZIP_NAME")
OTAMOD_DIRNAME=${OTAMOD_DIRNAME/.zip/}

SPLIT_SIGFILE="signature.der"
SPLIT_OTAZIP="ota-unsigned.zip"
VERIFICATION_SIG="../Google-Android-OTA-Certificate.pem"

echo Directory "$OTAMOD_DIRNAME" >&2
mkdir "$OTAMOD_DIRNAME"

echo Writing to "$SPLIT_SIGFILE" >&2
echo Writing to "$SPLIT_OTAZIP" >&2

python3 split-signed-ota.py \
  --input "$1" \
  --signature "$OTAMOD_DIRNAME"/"$SPLIT_SIGFILE" \
  --unsigned "$OTAMOD_DIRNAME"/"$SPLIT_OTAZIP"

echo Verifying against "$VERIFICATION_SIG" >&2

openssl smime \
  -verify \
  -CAfile "$VERIFICATION_SIG" \
  -in "$OTAMOD_DIRNAME"/"$SPLIT_SIGFILE" -inform DER \
  -content "$OTAMOD_DIRNAME"/"$SPLIT_OTAZIP" \
  > /dev/null

# Once the split portion of the ota zip is verified, "repair" it.
#
# truncating the comment off of the end of the signed zip actually yields
# an invalid zip file because it doesn't end with a "valid
# end-of-central-directory record".
# Adding a zero-length comment makes the zip valid again, but the signature
# was generated against the truncated-comment file.
#
# end comment length (0) to make a valid end-of-central-directory record
echo -ne '\0\0' >> "$OTAMOD_DIRNAME"/"$SPLIT_OTAZIP"


pushd "$OTAMOD_DIRNAME" >/dev/null

# can an OTA update the recovery partition?
# unzip listing will return 0 when it does find something matching 'recovery*'
# so we want this script to exit when rc is NOT 0

if unzip -qq -l "$SPLIT_OTAZIP" 'recovery*'; then
  echo "Does the OTA have a new recovery image?" >&2
  exit 1
else
  echo "OTA does not appear to have a new recovery image" >&2
fi

mkdir -p boot/{orig,modified}


pushd boot/orig >/dev/null
unzip ../../$SPLIT_OTAZIP boot.img
abootimg -x boot.img
popd >/dev/null

pushd boot/modified >/dev/null

# Must be able to create root-owned files inside the initrd
fakeroot bash <<END_FAKEROOT
set -o errexit

abootimg-unpack-initrd ../orig/initrd.img

echo "Applying modifications" >&2

# now in $OTAMOD_DIRNAME/boot/modified
# call modify-initrd in the toplevel directory
../../../modify-initrd

abootimg-pack-initrd initrd.img ramdisk
END_FAKEROOT


abootimg --create boot-unsigned.img \
  -f ../orig/bootimg.cfg \
  -k ../orig/zImage \
  -r ./initrd.img

"$BOOT_SIGNER" \
  /boot \
  boot-unsigned.img \
  "${BOOT_KEY_BASENAME}.pk8" \
  "${BOOT_KEY_BASENAME}.x509.pem" \
  boot.img

popd >/dev/null

# back in $OTAMOD_DIRNAME

# update boot.img inside the zip. Use "-j" to "junk" the path so it won't put boot.img inside directories within the zip
# A warning here about CRC CD not matching is OK I guess. (Did not cause a problem 2016-11-10 nrd91n)
zip "$SPLIT_OTAZIP" -j boot/modified/boot.img

# Sign the OTA zip with signapk.jar using personal OTA key
#
# -w means sign whole file
#
#   signapk has an extra 'sign whole file' mode, enabled with the -w option. When in this
#   mode, in addition to signing each individual JAR entry, the tool generates a
#   signature over the whole archive as well. This mode is not supported by jarsigner
#   and is specific to Android. So why sign the whole archive when each of the individual
#   files is already signed? In order to support over the air updates (OTA).
#     http://nelenkov.blogspot.com/2013/04/android-code-signing.html

echo Signing modified OTA >&2

java -jar "$SIGNAPK_JAR" \
  -w \
  "${OTA_KEY_BASENAME}.x509.pem" \
  "${OTA_KEY_BASENAME}.pk8" \
  "$SPLIT_OTAZIP" \
  ./signed.zip

popd >&2

cat <<END_MSG

  adb reboot recovery (or hold vol down at boot, select Recovery Mode)
  - power + vol up
  - apply update from ADB
  adb sideload signed.zip

END_MSG
