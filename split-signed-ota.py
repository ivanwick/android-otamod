#!/bin/env python3

import os
import sys
import struct
import argparse

parser = argparse.ArgumentParser(description='Remove the whole-file signature from an Android signed OTA zip.')
parser.add_argument('--input', required=True, help='Signed input zip')
parser.add_argument('--signature', required=True, help='Output signature DER')
parser.add_argument('--unsigned', required=True, help='Truncated zip output with signature removed')

args = parser.parse_args()

signed_zip_fname = args.input
signed_zip_size = os.stat(signed_zip_fname).st_size

# https://android.googlesource.com/platform/bootable/recovery/+/master/verifier.cpp
#     // An archive with a whole-file signature will end in six bytes:
#     //
#     //   (2-byte signature start) $ff $ff (2-byte comment size)
#     //
#     // (As far as the ZIP format is concerned, these are part of the
#     // archive comment.)  We start by reading this footer, this tells
#     // us how far back from the end we have to start reading to find
#     // the whole comment.

with open(signed_zip_fname, 'rb') as signed_zipfile, \
     open(args.signature, 'wb') as signature_file, \
     open(args.unsigned, 'wb') as unsig_zipfile:

    signed_zipfile.seek(signed_zip_size - 6)
    footer = signed_zipfile.read(6)

    sig_offsets = struct.unpack('<HHH', footer)
    sig_start = signed_zip_size - sig_offsets[0]

    assert sig_offsets[1] == 0xffff

    sig_size = sig_offsets[0] - 6
    signed_zipfile.seek(sig_start)
    sig = signed_zipfile.read(sig_size)

    signed_zipfile.seek(0)
    # 2 bytes comment length + size of whole comment from footer
    zip_data = signed_zipfile.read(signed_zip_size - sig_offsets[2] - 2)

    signature_file.write(sig)

    unsig_zipfile.write(zip_data)

    # truncating the comment off of the end of the signed zip actually yields
    # an invalid zip file because it doesn't end with a "valid
    # end-of-central-directory record".
    # Adding a zero-length comment makes the zip valid again, but the signature
    # was generated against the truncated-comment file.
    #
    # unsig_zipfile.write('\x00\x00') # end comment length (0) to make a valid end-of-central-directory record
