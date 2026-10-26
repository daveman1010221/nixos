# precisionws: a hardened, clang-built Linux 7.3, matching whitey's

Status, 2026-10-26: cleared by the maintainer; steps 1, 2 and 5 done, not yet built (steps 3, 4, 6 need /boot mounted). Written from a comparison of whitey's 7.3 config
(`hosts/whitey/overlays/.config`) with the one this host last built (`hosts/precisionws/overlays/.config`, Linux 6.19.8),
the 283 modules loaded here on the stock 7.2.9, `lspci -nnk`, and the 7.3 source's Kconfig files and Makefiles.

## Why now

The nixpkgs update (`d0e9c14`) moved `linuxPackages_latest` to 7.3, and generation 105 (stock 7.3) boots with no
keyboard at the disk passphrase prompt. Every keyboard module is in its initrd. What changed: nixpkgs' 7.3 is the
first kernel here built with `MODULE_SIG=y`, `MODULE_SIG_ALL=y` (its `kmodigest` signing, `MODULE_SIG_KEY=""`) and
`SECURITY_LOCKDOWN_LSM` / `_EARLY=y`, so two parameters this host has always passed take effect for the first time:
`module.sig_enforce=1` and `lockdown=confidentiality` (on 7.2.9 there was no lockdown LSM and no module signing). The
likely result is every module refused in the initrd. Not proven: that boot left no journal. A one-boot test is to
remove both parameters at the GRUB menu (`e`). Generation 105 is GRUB's default until a rollback.

Rather than drop the two parameters, the maintainer chose to build this host the kernel whitey runs, with modules
signed by the host's MOK key, so that both mean what they say.

## Decided (the maintainer, 2026-10-26)

- **Match whitey's hardened 7.3** as far as this hardware allows, built with clang and LLVM through whitey's
  `linuxManualConfig` overlay (`911b4bc`).
- **No kCFI or FineIBT on precisionws.** The NVIDIA open modules still link NVIDIA's prebuilt core
  (`nv-kernel.o_binary`), which is not built with kCFI, so calls between it and the kernel could trap.
- **`TRIM_UNUSED_KSYMS` off on precisionws.** It drops exported symbols no in-tree module uses, which NVIDIA's modules
  need.
- Settled by whitey's precedent: FIPS mode on (iwlwifi takes mac80211's software crypto; whitey's trouble was
  ath12k's `SW_CRYPTO_CONTROL`); IPv6 off (whitey's Mullvad patch is already staged in `overlays/`); hibernation off
  (lockdown forbids it; suspend to RAM is unaffected).

## What the comparison found

**Hardware this host loads that whitey's config does not build** (142 options; whitey is an AMD desktop, this an Intel
and Dell workstation laptop), from the loaded modules mapped to the options that build them:
- graphics: `DRM_XE`, `DRM_I915`, `INTEL_GTT`, `DRM_GPUVM`, `DRM_GPUSVM`; `SND_HDA_CODEC_HDMI_NVIDIA` and `_INTEL`
- network: `IWLWIFI`, `IWLMVM`; Bluetooth `BT_INTEL_PCIE` (and whitey turned off the btusb vendor quirks)
- platform: `INTEL_MEI`, `INTEL_MEI_ME`, `_HDCP`, `_PXP`, `INTEL_MEI_WDT`; `MFD_INTEL_LPSS(_PCI)`, `INTEL_IDMA64`,
  `PINCTRL_ALDERLAKE`, `SPI_INTEL(_PCI)`, `MTD`, `MTD_SPI_NOR` (the firmware flash), `INTEL_PMC_CORE` and the PMT and
  uncore-frequency telemetry, `INT340X_THERMAL`, `ACPI_THERMAL_REL`, `INTEL_POWERCLAMP`, `ACPI_TAD`
- input and sensors: `INTEL_ISH_HID` and the ISH HID sensors through IIO (`HID_SENSOR_HUB`, `_ALS`, `_GYRO_3D`,
  `_CUSTOM_INTEL_HINGE`), `I2C_HID_CORE`, `I2C_HID_ACPI`, `HID_MULTITOUCH` (the touchpad), `SERIO_RAW`
- audio: SOF (`SND_SOC_SOF_PCI_DEV`, `_INTEL_TGL`, `_INTEL_CNL`, `_HDA_*`), SoundWire (`SOUNDWIRE_INTEL`),
  `SND_SOC_INTEL_AVS`, `SND_HDA_CODEC_ALC269`
- Dell: `DELL_SMBIOS`, `DELL_WMI`, `_DDV`, `_SYSMAN`, `DELL_LAPTOP`, `DELL_PC`, `DELL_RBTN`, `DCDBAS`,
  `SENSORS_DELL_SMM`
- the rest: `KVM_INTEL`, `PERF_EVENTS_INTEL_UNCORE`, `SENSORS_CORETEMP`, `SENSORS_SPD5118`, `EDAC_IE31200`,
  `ITCO_WDT`, `RAS_CEC`, `TYPEC_DP_ALTMODE`, `NVIDIA_WMI_EC_BACKLIGHT`; Thunderbolt/USB4 (`USB4`, already `m` on
  whitey); `ENCRYPTED_KEYS` and `TRUSTED_KEYS` (loaded here; whitey leaves them out on purpose, to be decided)
- not mapped automatically: `intel_hid`, `intel_vsec`, and NVIDIA's four out-of-tree modules
- not seen yet: what the nix-usernetes node needs (veth, bridge, overlay, nftables sets and maps, conntrack, NAT,
  tun), since the cluster was not running when the modules were listed. Whitey builds the container stack; to be
  rechecked against `lsmod` with the cluster up.

**Whitey's hardening this host does not have** (163 differences), among them: kCFI and FineIBT (not taken, above),
`RANDSTRUCT_FULL`, bounds-only UBSAN with trap, KFENCE, `PAGE_TABLE_CHECK_ENFORCED`, `INIT_ON_ALLOC/FREE_DEFAULT_ON`,
`INIT_STACK_ALL_ZERO`, `MODULE_SIG_FORCE` with sha512 and the MOK key, `TRIM_UNUSED_KSYMS` (not taken), `DEBUG_WX`,
`SCHED_STACK_END_CHECK`, `BPF_JIT_ALWAYS_ON`, the BPF LSM, `PROC_MEM_FORCE_PTRACE`, and no IPv6, hibernation,
userfaultfd, IOPL, vsyscall emulation (execute-only kept) or line-discipline autoload. In `kernel.nix`:
`iommu=force`, `page_alloc.shuffle=1`, `hash_pointers=always`, and the sysctls `kptr_restrict=2`, `bpf_jit_harden=2`,
`io_uring_disabled=1`, `ldisc_autoload=0`, `protected_fifos/regular=2`, `suid_dumpable=0`, `accept_redirects=0`, oops
and warn limits of 100. This host's own parameters stay (`nosmt`, `intel_iommu=on`, `iommu.strict=1`, `debugfs=off`,
`vsyscall=none`, the `xe.*` settings, `fips=1`, `module.sig_enforce=1`, `lockdown=confidentiality`).

## The plan

1. **The build machinery, shared, not copied.** whitey's `kernel-sandbox/` (`kprep`, `kmok_check`, `kmok_generate`,
   `kcheck`, `knew`, `ksaveconfig`) and `overlays/custom-kernel.nix` take the host as a parameter, so precisionws gets
   its own `kernel-version.nix`, `overlays/.config` and `overlays/defconfig` and nothing else of its own.
   *Done 2026-10-26:* the overlay is `flakes/kernel/custom-kernel.nix` and the sandbox `flakes/kernel/sandbox/`
   (`shell.nix`, a function of the host's directory, which exports the host as `$KHOST`; `build_instructions.md`).
   A host gets the custom kernel when it has a `kernel-version.nix` (`flake.nix`, `hostOverlays`); each host keeps a
   one-line `kernel-sandbox/shell.nix`. Checked: whitey's kernel derivation is the same before and after
   (`1whmd7nz…-linux-7.3.drv`, and its `dev` output), and so is precisionws's stock one. precisionws's
   `kernel-version.nix` comes with its new `.config` in step 2: alone, it would build 7.3 from the 6.19.8 config.
2. **The config.** Start from whitey's `defconfig`; add the hardware above; `CFI=n`, `TRIM_UNUSED_KSYMS=n`;
   `KVM_INTEL` for `KVM_AMD`; drop what is AMD's alone (amdgpu, k10temp, the AMD EDAC, sp5100, gpio-amdpt,
   gigabyte-wmi, R8169) since this host has none of it; `olddefconfig`, then `ksaveconfig` and `kcheck`
   (kernel-hardening-checker) in the sandbox, and a diff against whitey's to review.
   *Done 2026-10-26:* `overlays/kernel.fragment` (precisionws's lines after whitey's `defconfig`, each group with its
   reason), resolved in the sandbox with `olddefconfig` into `overlays/.config` and `overlays/defconfig` (the 6.19.8
   config is in git history). Checked: every line of the fragment holds in the result; every module this host loads
   has its option on except those left out on purpose (whitey's own omissions: configfs, dmi_sysfs, TEE, NVMe in-band
   authentication, the non-Intel Bluetooth quirks; what IPv6 off removes: `nf_defrag_ipv6`, `nf_reject_ipv6`,
   `nft_reject_inet`, since `inet` needs IPv6 on 7.3; and `intel_spi` with MTD (write access to the firmware flash),
   mousedev, mac_hid, the AVS audio driver, which is not the one bound, and the keys below); the modules the
   nix-usernetes node adds when it runs (overlay, veth, nftables NAT, fib, reject, `nft_compat` with `xt_conntrack`
   and `xt_comment`, which the kubelet's KUBE-FIREWALL rule uses) are all built; `br_netfilter` is not loaded and not
   built. kernel-hardening-checker, configs only: whitey 208 OK and 42 FAIL, precisionws 206 and 44, the difference
   being exactly `CFI_AUTO_DEFAULT` and `TRIM_UNUSED_KSYMS`. The flake now has precisionws's custom kernel
   (`hardened_linux_kernel`, `92p1vpyn…-linux-7.3.drv`), and precisionws still boots the stock one until step 5
   (its kernel derivation is unchanged, and so is whitey's).
   For step 5, from this: the initrd list asks for `cryptd` and `nvme_auth`, which this config does not build, so
   they come out of it; the ruleset's `table ip6 filter` comes out (no IPv6), the rest is `table ip`.
   *Corrected 2026-10-26 (review of the above):* checking only against `lsmod` missed what the stock kernel builds in.
   The drivers bound in `/sys/bus/*/drivers`, `/sys/class/iommu` and `cpuidle` showed the config lacked the Intel IOMMU
   (`INTEL_IOMMU`, `DMAR_TABLE`, `IRQ_REMAP`; `dmar0` and `dmar1` are active, and `intel_iommu=on`, `iommu.strict=1`,
   `iommu=force` need it), `INTEL_IDLE` (the cpuidle driver), `X86_INTEL_LPSS` with the DesignWare I2C (the touchpad's
   bus), PCIe hotplug and AER (`pciehp` and `aer` are bound), `INTEL_HFI_THERMAL`, `INTEL_TURBO_MAX_3` and `ACPI_DPTF`;
   and that `xt_comment` was not built after all (it depends on `NETFILTER_ADVANCED`, off on whitey; with the cluster up
   it is loaded). All are in the fragment now; `NETFILTER_ADVANCED=y` comes with every netfilter option it would
   otherwise change pinned (nothing moved), `CRYPTO_ZSTD` for zswap, and the AMD-only drivers off. The firmware flash
   stays out as decided above. Checked: every fragment line holds; every bound driver and every module loaded with the
   cluster up is built or left out on purpose; every initrd module exists; the build reads exactly `overlays/.config`;
   whitey's kernel derivation is unchanged.

   kernel-hardening-checker, with the configured parameters and sysctls over the running system's: 296 OK, 56 FAIL
   (from 273 and 79). Taken from it: `mitigations=auto,nosmt` (with `nosmt` kept: it disables SMT whatever the CPU),
   `tsx=off`, `X86_INTEL_TSX_MODE_OFF`, `INTEL_IOMMU_SVM`; and, chosen by the maintainer,
   `kernel.unprivileged_bpf_disabled=1`, `kernel.sysrq=0`, `kernel.io_uring_disabled=2` (`yama.ptrace_scope` stays
   1). The 56 left: 33 this workstation uses, as whitey does (user namespaces, modules, BPF, tracing, compat and IA32
   for Wine and 32-bit graphics, binfmt_misc for aarch64 emulation, MSR, the console); 5 the NVIDIA decisions; 13 not
   applicable (clang, no SELinux, no IPv6, no TPM, not in 7.3, unreadable to the checker); 4 not appropriate
   (`STATIC_USERMODEHELPER` and `PROC_MEM_NO_FORCE`/`proc_mem.force_override` break modprobe and debuggers; `pti` costs
   on a CPU without Meltdown); `perf_event_paranoid=3` does nothing on a mainline kernel. Also in `kernel.nix`: zswap
   back to `zstd`, and this host's copies of `loglevel`, `lsm`, `pcie_aspm` and `usbcore.autosuspend` removed, since
   the shared block in `flake.nix` passes them (its `loglevel=4` already won over `loglevel=6`).
3. **The MOK key.** `kmok_check` on `/boot/secrets/MOK.pem` and `MOK.priv` with `/boot` mounted; `kmok_generate` if
   precisionws has none.
4. **NVIDIA** builds through kbuild against the custom kernel's `dev` output and is signed with the same key (whitey's
   overlay already signs out-of-tree modules this way); checked with `modinfo` (signer) before any boot.
5. **`kernel.nix`.** `kernelPackages` to the custom kernel; the initrd list rechecked against what 7.3 builds in (the
   keyboard stack above all); `pkcs8_key_parser` in `boot.kernelModules` (whitey `9427dce`; Polar's escrow keys go into
   the kernel keyring); whitey's parameters and sysctls; IPv6 off (`networking.enableIPv6 = false`, the `ip6` table out
   of `nftables.nft`, the Mullvad overlay).
   *Done 2026-10-26, not yet built:* `kernel.nix` points `kernelPackages` at `pkgs.hardened_linux_kernel`; the initrd
   list loses what this config does not build (`cryptd`, `vmd`, `nvme_auth`, `dax`; `cryptd` and `crypto_null` from
   the LUKS list), and the keyboard stack (`i8042`, `usbhid`, `hid_generic`, `xhci_hcd`, `xhci_pci`) is built in, so
   it cannot go missing from the initrd; `pkcs8_key_parser` in `boot.kernelModules`; whitey's three hardening
   parameters and its sysctls; `unprivileged_userns_clone` dropped from the parameters and sysctls, as on whitey (a
   Debian patch, nothing on this kernel); `zswap.compressor=lzo`, as on whitey, since this config builds no zstd for
   the crypto API; `networking.enableIPv6 = false` and the `ip6` table out of `nftables.nft` (checked with
   `nft -c`). The shared overlay now declares the kernel's `features` from its config (`linuxManualConfig` left them
   empty, and `hardware.graphics.enable32Bit` asserts `ia32Emulation`); whitey's kernel derivation is unchanged by
   it. The system evaluates (`toplevel`, with placeholder secrets). The flake reads the working tree, so the next
   `nixos_update` builds and installs this kernel: not before step 6.
6. **Build and check without booting:** the kernel, the initrd (every keyboard and storage module present and
   signed), NVIDIA, and the system's `toplevel`.
7. **The first boot, with the 7.2.9 generation one menu entry away:** the keyboard at the passphrase prompt, the
   display (xe), Wi-Fi under FIPS, Bluetooth, audio, the touchpad, `nvidia-offload`, suspend and resume, rootless
   podman, and the nix-usernetes node with kube-proxy now single-stack (and `lsmod` with the cluster up, for step 2).

Who does what: the builds need `/boot/secrets` for the MOK key and `flakey.json`, so `/boot` mounted; the switch and the
reboots are the maintainer's.

## Open

- `ENCRYPTED_KEYS` and `TRUSTED_KEYS`: loaded here today; whitey leaves them out. Whether anything on this host uses
  them.
