## Custom Kernel Build Sandbox — Whitey

The kernel version comes from `../kernel-version.nix` (currently `linux_7_3`),
shared with `../overlays/custom-kernel.nix` so the sandbox and the flake build
the same source with the same nixpkgs patches.

### Enter the environment

From a working directory outside `/etc/nixos` (the kernel tree and build
output land in the current directory):

```bash
nix develop --impure --file /etc/nixos/hosts/whitey/kernel-sandbox/shell.nix
```

Not `nix-shell`: Nix 2.34's `nix-shell` fails with
`boost::bad_format_string` on any derivation that uses structured attrs and has
a `%` in an attribute, which nixpkgs' kernel derivation now does. `--impure`
is needed because `shell.nix` reads `/etc/nixos/flake.lock`.

### Option A: One‑shot “do everything” (recommended for most iterations)
```bash
kgo          # runs kprep → interactive nconfig → kkernel
```

### Option B: Step‑by‑step (full control)

1. **Prepare everything** (unpack source, apply nixpkgs patches, seed config, sync oldconfig, check the signing key, build host tools)  
```bash
   kprep
```
   * For a clean out‑of‑tree build, use `KCLEAN=1 kprep` (wipes the build directory first).

2. **Tweak the configuration interactively**  
```bash
   knconfig      # nconfig
   kmenu         # menuconfig
```

3. **Build kernel + modules**  
```bash
   kbuild        # runs kprep if needed, then kkernel
   kkernel       # raw build (requires a valid .config in out‑of‑tree dir)
```

4. **Save the updated config back to your flake**  
```bash
   ksaveconfig   # copies .config to repo root and /etc/nixos/hosts/whitey/overlays/.config,
                 # and writes savedefconfig output as defconfig beside it
```

### Moving to a new kernel version

1. Change `attr` in `../kernel-version.nix`, re-enter the shell from a
   directory without the old `linux-*` tree (unpacking only happens when none
   is found), and run `kphases` to unpack and patch the new one.
2. `knew` reports what the bump does to the current config before you touch it:
   options new in this version (`listnewconfig.txt`, with help text in
   `helpnewconfig.txt`) and everything `olddefconfig` would change
   (`diffconfig.txt`), under `<out dir>/knew/`.
3. Then `kprep`, nconfig, `kcheck`, `ksaveconfig` as usual.

### Helper commands

| Command | What it does |
|---------|--------------|
| `kstatus` | Show source tree, out‑of‑tree build directory, config presence, and signing key status |
| `kcheck` | Run kernel-hardening-checker on the out-dir `.config`, whitey's configured kernel command line, and the running sysctls; output also saved to `<out dir>/kcheck.txt`. Extra args go to the checker (`kcheck -m show_fail`); `KCHECK_CMDLINE=/proc/cmdline kcheck` checks the booted command line instead |
| `knew` | Version-bump report (see above); `knew <config>` for a config other than the repo-root one |
| `klog`   | Tail the build log (default last 200 lines) |
| `kenv`   | Print toolchain and environment variables |
| `kcd`    | Jump into the kernel source tree |
| `kclean` | Wipe the out‑of‑tree build directory (preserves source) |
| `kmok_status` | Show the key files, the certificate's subject and expiry, and `CONFIG_MODULE_SIG_KEY` |
| `kmok_check` | Check the key `CONFIG_MODULE_SIG_KEY` names is readable and holds a key and a certificate |
| `kmok_generate` | Create the signing key in `/boot/secrets` (see below) |

### Module signing key

kbuild signs every module with the file `CONFIG_MODULE_SIG_KEY` names, and
embeds that file's certificate in the kernel's builtin trusted keyring. To use
the MOK, the `.config` sets:

```
CONFIG_MODULE_SIG_KEY="/boot/secrets/MOK.priv"
```

With kbuild's default, `certs/signing_key.pem`, each build generates and uses a
throwaway key instead; `kmok_check` says so.

`kmok_generate` creates the key with the type and hash the `.config` selects
(RSA 4096 unless it selects ECDSA or ML-DSA):

| File | Contents | Access |
|------|----------|--------|
| `/boot/secrets/MOK.priv` | private key, then certificate | root, 0600, ACL read for you and `nixbld` only |
| `/boot/secrets/MOK.pem` | certificate | 0644 |
| `/boot/secrets/MOK.der` | certificate, DER, for `mokutil --import` if shim is ever used | 0644 |

It refuses to replace an existing key; `kmok_generate --force` does, keeping
the old files as `*.bak-<timestamp>` with the ACLs removed. `KMOK_CN` and
`KMOK_DAYS` override the certificate's CN and validity.

The flake build reads the key through `extra-sandbox-paths = /boot/secrets?`,
which is why `nixbld` needs read access. That path is visible to every
derivation built on this machine.
