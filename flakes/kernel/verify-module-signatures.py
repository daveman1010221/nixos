"""Verify that every kernel module under a directory carries a signature by one certificate.

Usage: verify-module-signatures.py <certificate, DER> <modules directory>

A module is signed as kbuild's sign-file appends it: the module, a PKCS#7 signature, a 12-byte struct
module_signature (its last four bytes the signature's length, big-endian) and the magic string. Each is
checked with `openssl cms -verify` against the certificate alone; compressed modules (.xz, .zst) are
decompressed first. Exits non-zero, naming each module, if any is unsigned or does not verify.
"""
import lzma
import os
import struct
import subprocess
import sys
import tempfile

MAGIC = b"~Module signature appended~\n"


def module_bytes(path):
    if path.endswith(".xz"):
        return lzma.decompress(open(path, "rb").read())
    if path.endswith(".zst"):
        return subprocess.run(["zstd", "-dcq", path], check=True, capture_output=True).stdout
    return open(path, "rb").read()


def main():
    cert_der, root = sys.argv[1:3]
    work = tempfile.mkdtemp()
    cert = os.path.join(work, "cert.pem")
    subprocess.run(["openssl", "x509", "-inform", "DER", "-in", cert_der, "-out", cert], check=True)
    good, bad = 0, []
    for directory, _, files in os.walk(root, followlinks=True):
        for name in sorted(files):
            if not name.endswith((".ko", ".ko.xz", ".ko.zst")):
                continue
            path = os.path.join(directory, name)
            data = module_bytes(path)
            if not data.endswith(MAGIC):
                bad.append(f"{path}: not signed")
                continue
            info = data[-len(MAGIC) - 12:-len(MAGIC)]
            length = struct.unpack(">I", info[8:12])[0]
            body = data[:-len(MAGIC) - 12 - length]
            signature = data[-len(MAGIC) - 12 - length:-len(MAGIC) - 12]
            body_file, sig_file = os.path.join(work, "body"), os.path.join(work, "sig")
            open(body_file, "wb").write(body)
            open(sig_file, "wb").write(signature)
            result = subprocess.run(
                ["openssl", "cms", "-verify", "-binary", "-inform", "DER", "-in", sig_file, "-content", body_file,
                 "-certfile", cert, "-nointern", "-noverify", "-out", os.devnull],
                capture_output=True, text=True)
            if result.returncode == 0:
                good += 1
            else:
                bad.append(f"{path}: signature does not verify against the host's certificate")
    print(f"{good} module(s) signed by the host's key")
    for line in bad:
        print(line, file=sys.stderr)
    if bad or good == 0:
        sys.exit(1)


main()
