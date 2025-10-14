# 🧩 NixOS Debugging Notes — Tracking Initrd + Package Provenance
## Context

Debugging early-boot failure in nvme-hw-key (stage 1 systemd service) caused by sed-key not functioning correctly in the initrd.
Goal: determine whether sed-key was missing, mislinked, or broken in specific generations — and trace it to the corresponding source version.

## List and inspect system generations

List existing generations:

```bash
sudo nix-env -p /nix/var/nix/profiles/system --list-generations
```

Show where the symlinks point:

```bash
ls -l /nix/var/nix/profiles/system-*-link
```

Get current generation store path:

```bash
readlink -f /run/current-system
```

## Mount or unpack an initrd from a given generation

Identify the initrd path:

```bash
INITRD=$(readlink -f /nix/var/nix/profiles/system-9-link/initrd)
```

Option 1: View with lsinitrd

(Requires dracut or similar tools)

```bash
lsinitrd "$INITRD" | less
```

Option 2: Manual unpack (works anywhere)

Initrds are usually zstd-compressed cpio archives:

```bash
mkdir -p /tmp/initrd-9
cd /tmp/initrd-9
zstdcat "$INITRD" | cpio -idmv
```

Now you can browse files inside the early boot environment:

```bash
tree -L 2 .
```

Typical directories:

- /bin and /usr/bin — executables actually present in stage 1
- /etc/systemd/system — initrd-target unit files
- /nix/store/... — paths linked into the initrd closure

## Check whether sed-key is in the initrd closure

```bash
nix-store --query --requisites "$INITRD" | grep sed-key
```

If nothing appears, check reverse dependencies (what refers to it):

```bash
nix-store --query --referrers $(readlink -f /nix/store/*sed-key-0.1.*)
```

👉 Note:
The closure list may omit transiently used derivations if they were inlined into another build step (e.g., baked into a unit script). The real proof is to find the binary under /tmp/initrd-*/bin/sed-key.

## Verify service inclusion and linkage

Check that your service is inside the initrd:

```bash
ls /tmp/initrd-9/etc/systemd/system/initrd.target.wants/
```

Inspect the unit:

```bash
less /tmp/initrd-9/etc/systemd/system/nvme-hw-key.service
```

Look for:

    ExecStart= path (should reference a /nix/store/...-unit-script-nvme-hw-key-start)

    proper dependency ordering (Before=systemd-cryptsetup@...)

    environment lines or missing PATHs

## Evaluate the system configuration (when possible)

If NIX_PATH is unset:

```bash
export NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos
```

Then evaluate directly:

```bash
nix eval --impure --expr '
  let sys9 = import <nixpkgs/nixos> {
    configuration = import /nix/var/nix/profiles/system-9-link/nixos-config;
  };
  in sys9.config.boot.initrd.systemd.services.nvme-hw-key
'
```

(If it fails, the system likely predates current nixpkgs revisions or was garbage-collected — skip to unpacked analysis.)

## Diff services between generations

```bash
diff \
  /tmp/initrd-9/etc/systemd/system/nvme-hw-key.service \
  /tmp/initrd-18/etc/systemd/system/nvme-hw-key.service
```

Focus on:

    store path differences in ExecStart

    PATH/environment lines

    dependencies (After=, Before=, etc.)

## Map binaries to source revisions

Locate store path:

```bash
nix-store --query --deriver /nix/store/<hash>-sed-key-0.1.*
```

Get derivation info:

```bash
nix show-derivation /nix/store/<hash>-sed-key-0.1.*.drv | jq
```

The .env.pname, .env.src, and .outputs will tie it to a specific git revision if built from a flake or git source.

## Rebuild from a specific commit and verify nar hash

```bash
git clone https://github.com/daveman1010221/sed-key.git
cd sed-key
git checkout <commit-hash>
nix build .
nix hash path ./result
```

Compare the computed hash against your system’s flake.lock:

```bash
jq '.nodes."sed-key".locked.narHash' /etc/nixos/flake.lock
```

Hashes should match — confirming you’ve reconstructed the same artifact the system used.

## Compare old and new sources

```bash
diff -u ../sed-key-old/src/opal.rs src/opal.rs
```

Identify behavioral deltas — in our case,
the EBADF fix required keeping the file handle alive through the ioctl call.

## Patch + verify locally

```bash
nvim src/opal.rs
nix build .
sudo ./result/bin/sed-key unlock /dev/disk/by-id/nvme-<id> -
```

If it works, commit:

```bash
git add .
git commit -m "fix(opal): keep file handle alive during ioctl to prevent EBADF"
git tag -a 0.1.2 -m "Release 0.1.2 – fix EBADF ioctl bug"
git push && git push --tags
```

## Update and rebuild system

```bash
sudo nix flake update
sudo nixos-rebuild switch --flake .#whitey
```

Check the resulting system link:

```bash
readlink -f /run/current-system
```

🧠 Deep-Dive Forensics — Rebuilding Provenance by Hand

When the normal Nix tooling isn’t giving you a straight answer, you can manually reconstruct the provenance of any binary from the store.

1. Identify and inspect store copies

You can discover multiple historical builds of sed-key across generations:

nix-store --query --requisites /nix/var/nix/profiles/system-9-link/ | rg sed-key

Then test each one directly:

sudo /nix/store/<hash>-sed-key-0.1.0/bin/sed-key status /dev/disk/by-id/nvme-<drive-id>

This helps identify which generations contain a working binary.
2. Find the deriver and unpack its source

For a known store path:

nix-store --query --deriver /nix/store/<hash>-sed-key-0.1.0

Then:

nix derivation show /nix/store/<deriver>.drv | jq '.'

That JSON includes the full environment, input sources, and the Git checkout path used to produce the binary.
Navigate into that source path (it’ll look like /nix/store/<something>-source):

cd /nix/store/<something>-source

3. Reproduce its nar hash for verification

Nix store sources may include .git directories that change the hash; remove them to match the flake-locked artifact:

rm -rf .git .direnv .gitignore
nix hash path . --type sha256 --exclude .git

Compare the result with your system flake lock entry:

jq '.nodes."sed-key".locked.narHash' /etc/nixos/flake.lock

If they match, you’ve located the exact source revision that built the store binary.
4. Trace Git history manually

If multiple candidates exist, jump through commits until you find the one that produces the correct hash:

git checkout <commit-hash>
nix hash path . --type sha256

Iterate until the hash matches the narHash from the lock file.
5. Cross-validate versions and function

Use the directly built binary to test:

sudo cat /tmp/mnt/keys/nvme-<drive>.key | sudo ./result/bin/sed-key unlock /dev/disk/by-id/nvme-<drive> -

Compare behavior between revisions (e.g., generation 9’s vs generation 18’s).
In this case, generation 9 worked while later builds hit EBADF, indicating a regression in file handle lifetime during the ioctl call.
6. (Optional) Manual path metadata checks

To introspect the complete Nix object graph:

nix path-info --json . | jq '.'
cargo metadata --no-deps --format-version 1 | jq '.'
nix flake metadata .

This trio is useful for confirming what version the flake actually built versus what Cargo saw during the build.
7. Rebuild and re-tag once verified

After verifying the fix:

git commit -m "fix(opal): keep file handle alive during ioctl"
git tag -a 0.1.2 -m "Release 0.1.2 – fix EBADF ioctl bug"
git push && git push --tags

🧩 TL;DR Chain of Evidence
Stage	Tool	Purpose
nix-store --query --requisites	Find candidate store paths	
nix-store --query --deriver	Identify derivation (.drv)	
nix derivation show	Inspect source + inputs	
nix hash path	Verify nar hash against flake	
git checkout loop	Align source commit	
Manual binary test	Confirm behavioral parity
