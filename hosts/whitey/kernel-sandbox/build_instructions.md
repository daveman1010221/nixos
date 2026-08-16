## Custom Kernel Build Sandbox — Whitey (Linux 7.1.8)

### Enter the environment
```bash
nix-shell shell.nix
```

### Option A: One‑shot “do everything” (recommended for most iterations)
```bash
kgo          # runs kprep → interactive nconfig → kkernel
```

### Option B: Step‑by‑step (full control)

1. **Prepare everything** (unpack source, seed config, sync oldconfig, place MOK keys from /boot/secrets, build host tools)  
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
   ksaveconfig   # copies from out‑of‑tree to repo root and /etc/nixos/hosts/whitey/overlays/.config
```

### Helper commands

| Command | What it does |
|---------|--------------|
| `kstatus` | Show source tree, out‑of‑tree build directory, config presence, and MOK status |
| `klog`   | Tail the build log (default last 200 lines) |
| `kenv`   | Print toolchain and environment variables |
| `kcd`    | Jump into the kernel source tree |
| `kclean` | Wipe the out‑of‑tree build directory (preserves source) |
| `kmok_status` | Show MOK key paths and whether they exist |

### MOK keys in the sandbox

The sandbox sources keys directly from `/boot/secrets`.  
`kmok_prepare` copies them into the out‑of‑tree build directory with correct permissions.  
No fallback paths, no manual seeding — just keep your keys in `/boot/secrets`.
