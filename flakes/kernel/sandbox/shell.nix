# The kernel build sandbox for a host that builds its own kernel: the source, nixpkgs patches and version of the kernel
# its kernel-version.nix names. Entered through the host's own kernel-sandbox/shell.nix, which passes its directory;
# see build_instructions.md.
{ hostDir }:
let
  flakeLock = builtins.fromJSON (builtins.readFile /etc/nixos/flake.lock);
  rootInputs = flakeLock.nodes.${flakeLock.root}.inputs;
  nixpkgsRev = flakeLock.nodes.${rootInputs.nixpkgs}.locked.rev;
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/${nixpkgsRev}.tar.gz") {};
  kernelAttr = (import (hostDir + "/kernel-version.nix")).attr;
  # The host this sandbox builds for: its directory's name, as nixosConfigurations names it.
  hostName = baseNameOf (toString hostDir);
in
pkgs.${kernelAttr}.overrideAttrs (o: {
  stdenv = pkgs.stdenv;

  nativeBuildInputs = (o.nativeBuildInputs or []) ++ [
    pkgs.llvmPackages.clang-unwrapped
    pkgs.llvmPackages.lld
    pkgs.llvmPackages.llvm
    pkgs.llvmPackages.bintools

    pkgs.pkg-config
    pkgs.ncurses
    pkgs.bison
    pkgs.flex
    pkgs.openssl
    pkgs.bc
    pkgs.kmod
    pkgs.pahole

    pkgs.glibc.dev
    pkgs.linuxHeaders

    pkgs.rsync
    pkgs.acl

    pkgs.kernel-hardening-checker

    pkgs.starship
    pkgs.eza
  ];

  shellHook = ''
    export NIX_ENFORCE_NO_NATIVE=0
    set +e

    # The host this kernel is for (hosts/<host>): where its config is saved, and whose command line kcheck reads.
    export KHOST="${hostName}"

    # --- Toolchain split ---
    export CC=${pkgs.llvmPackages.clang-unwrapped}/bin/clang
    export CXX=${pkgs.llvmPackages.clang-unwrapped}/bin/clang++

    export HOSTCC=${pkgs.stdenv.cc}/bin/cc
    export HOSTCXX=${pkgs.stdenv.cc}/bin/c++
    export HOSTLD=${pkgs.stdenv.cc.bintools}/bin/ld

    export LD=${pkgs.llvmPackages.lld}/bin/ld.lld
    export AR=${pkgs.llvmPackages.llvm}/bin/llvm-ar
    export NM=${pkgs.llvmPackages.llvm}/bin/llvm-nm
    export OBJCOPY=${pkgs.llvmPackages.llvm}/bin/llvm-objcopy
    export OBJDUMP=${pkgs.llvmPackages.llvm}/bin/llvm-objdump
    export STRIP=${pkgs.llvmPackages.llvm}/bin/llvm-strip
    export READELF=${pkgs.llvmPackages.llvm}/bin/llvm-readelf

    # ------------------------------------------------------------------
    # Repo root helper (stable anchor for fallback files)
    #
    # We define "repo root" as the parent directory of the kernel source tree.
    # This avoids fragile $PWD assumptions when you cd around.
    # ------------------------------------------------------------------
    kroot() {
      local src
      src="$(ksrc)" || return 1
      # repo root = parent of linux-* dir
      (cd "$src/.." && pwd)
    }

    # ------------------------------------------------------------------
    # MOK key material – lives in /boot/secrets (see kmok_generate)
    # ------------------------------------------------------------------
    export MOK_DIR="/boot/secrets"
    export MOK_PRIV="$MOK_DIR/MOK.priv"   # private key + certificate (CONFIG_MODULE_SIG_KEY)
    export MOK_PEM="$MOK_DIR/MOK.pem"     # certificate
    export MOK_DER="$MOK_DIR/MOK.der"     # certificate, DER (mokutil --import)

    export KCFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"
    export KAFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"

    export HOSTCFLAGS=""
    export HOSTCXXFLAGS=""
    # With LLVM=1, kbuild links host programs with -fuse-ld=lld unless a
    # linker is already chosen. That bypasses Nix's ld wrapper, so nconf,
    # sign-file, objtool and friends get no RUNPATH and can't find their
    # libraries. Keep host links on the wrapped bfd linker.
    export HOSTLDFLAGS="-fuse-ld=bfd"

    # Shell sanity (avoid /bin/sh assumptions when you later mimic nix builds)
    export SHELL=${pkgs.bash}/bin/bash
    export CONFIG_SHELL=${pkgs.bash}/bin/bash

    # ------------------------------------------------------------------
    # Kernel tree + stable out dir
    # ------------------------------------------------------------------
    export KERNEL_SRC_GLOB="''${KERNEL_SRC_GLOB:-linux-*}"
    ksrc() {
      # Prefer current dir if it looks like a kernel tree
      if [ -f "$PWD/Makefile" ] && grep -q '^VERSION[[:space:]]*=' "$PWD/Makefile" 2>/dev/null; then
        echo "$PWD"
        return 0
      fi
      # Fallback: common layout (repo root contains linux-*/)
      for d in "$PWD"/$KERNEL_SRC_GLOB "$PWD"/Linux-* "$PWD"/kernel "$PWD"/src/$KERNEL_SRC_GLOB; do
        if [ -f "$d/Makefile" ] && grep -q '^VERSION[[:space:]]*=' "$d/Makefile" 2>/dev/null; then
          echo "$d"
          return 0
        fi
      done
      return 1
    }

    kout_for() {
      # One out dir per source tree, so different extracted versions don't trample each other.
      local src="$1"
      local base
      base="$(basename "$src")"
      echo "$src/../.o-$base"
    }

    # ------------------------------------------------------------------
    # Nix phases orchestration (repo workflow)
    # ------------------------------------------------------------------
    kneed_src() {
      local d
      shopt -s nullglob
      for d in "$PWD"/$KERNEL_SRC_GLOB "$PWD"/src/$KERNEL_SRC_GLOB; do
        if [ -d "$d" ] && [ -f "$d/Makefile" ]; then
          shopt -u nullglob
          return 1  # nope, we already have a kernel tree
        fi
      done
      shopt -u nullglob
      return 0  # yes, need source
    }

    kunpack_if_needed() {
      if ! kneed_src; then
        return 0
      fi
      if ! command -v unpackPhase >/dev/null 2>&1; then
        echo "❌ unpackPhase is not available in this shell (did you enter via nix develop on shell.nix?)"
        return 1
      fi
      echo "📦 no kernel tree found; running unpackPhase"
      # nixpkgs' preUnpack/postUnpack move the tree to
      # $dev/lib/modules/<ver>/source for its install layout; skip them so it
      # lands here as linux-<ver>. Subshell: unpackPhase cds into the tree.
      (
        preUnpack=""
        postUnpack=""
        unpackPhase
      )
    }

    kpatch_if_needed() {
      local marker="''${KPATCH_MARKER:-.kpatchPhase.done}"

      if [ "''${KFORCE_PATCH:-0}" = "1" ]; then
        rm -f "$marker" 2>/dev/null || true
      fi

      if [ -f "$marker" ]; then
        return 0
      fi
      if ! command -v patchPhase >/dev/null 2>&1; then
        echo "⚠️  patchPhase is not available in this shell; skipping (set KFORCE_PATCH=1 after entering a proper nix-shell)"
        return 0
      fi

      local src
      src="$(ksrc)" || { echo "❌ can't find kernel source tree after unpackPhase"; return 1; }

      echo "🩹 running patchPhase in $src"
      (
        cd "$src"
        patchPhase
      )
      touch "$marker"
    }

    kensure_src() {
      kunpack_if_needed || return 1
      kpatch_if_needed || return 1
    }

    # ------------------------------------------------------------------
    # Module signing key
    #
    # kbuild signs modules with the file CONFIG_MODULE_SIG_KEY names and
    # embeds that file's certificate in the builtin trusted keyring. To use
    # the MOK, the .config sets:
    #   CONFIG_MODULE_SIG_KEY="/boot/secrets/MOK.priv"
    # MOK.priv holds the private key followed by the certificate, the same
    # layout as kbuild's autogenerated certs/signing_key.pem.
    # ------------------------------------------------------------------
    kmok__sudo() {
      if ! command -v sudo >/dev/null 2>&1; then
        echo "❌ sudo not available (needed for /boot/secrets access)"
        return 1
      fi
      sudo "$@"
    }

    kmok__warn() { echo "⚠️  $*"; }
    kmok__die()  { echo "❌ $*"; return 1; }

    # Value of CONFIG_<name> from the out-dir .config, else the repo-root one.
    kmok__cfg() {
      local src out f
      src="$(ksrc)" || return 1
      out="$(kout_for "$src")"
      for f in "$out/.config" "$src/../.config"; do
        if [ -f "$f" ]; then
          sed -n "s/^CONFIG_$1=//p" "$f" | tr -d '"'
          return 0
        fi
      done
      return 1
    }

    kmok_check() {
      local key
      key="$(kmok__cfg MODULE_SIG_KEY)" || { kmok__warn "no .config yet; skipping signing key check"; return 0; }
      case "$key" in
        "")
          echo "ℹ️  CONFIG_MODULE_SIG_KEY unset (module signing off?)"
          return 0
          ;;
        certs/signing_key.pem)
          kmok__warn "CONFIG_MODULE_SIG_KEY is kbuild's default: modules get a throwaway per-build key, not $MOK_PRIV"
          return 0
          ;;
        pkcs11:*)
          echo "ℹ️  signing via PKCS#11: $key"
          return 0
          ;;
      esac
      [ -r "$key" ] || { kmok__die "signing key $key is missing or unreadable by $USER (kmok_generate creates it; is /boot mounted?)"; return 1; }
      grep -q 'PRIVATE KEY-----' "$key" || { kmok__die "$key holds no private key"; return 1; }
      grep -q 'BEGIN CERTIFICATE-----' "$key" || { kmok__die "$key holds no certificate (kbuild takes the builtin keyring cert from it)"; return 1; }
      echo "✅ signing key: $key"
    }

    # Create the signing key in /boot/secrets with the key type and hash the
    # .config asks for. Refuses to replace an existing key unless given
    # --force, which keeps the old files as *.bak-<timestamp>.
    #   KMOK_CN    certificate CN (default: "<hostname> kernel module signing key")
    #   KMOK_DAYS  validity (default 36500, as kbuild uses; the kernel does not
    #              check module certificate expiry)
    kmok_generate() {
      local force=0
      [ "''${1:-}" = "--force" ] && force=1

      [ -d "$MOK_DIR" ] || { kmok__die "$MOK_DIR does not exist (is /boot mounted?)"; return 1; }
      if [ "$force" != 1 ] && kmok__sudo test -e "$MOK_PRIV"; then
        kmok__die "$MOK_PRIV already exists; kmok_generate --force replaces it (old files kept as .bak-*)"
        return 1
      fi

      local hash keytype v
      hash="$(kmok__cfg MODULE_SIG_HASH)"
      hash="''${hash:-sha512}"
      keytype="rsa:4096"
      [ "$(kmok__cfg MODULE_SIG_KEY_TYPE_ECDSA)" = y ] && keytype="ec -pkeyopt ec_paramgen_curve:secp384r1"
      for v in 44 65 87; do
        [ "$(kmok__cfg MODULE_SIG_KEY_TYPE_MLDSA_$v)" = y ] && keytype="ml-dsa-$v"
      done
      echo "🔑 generating $keytype key, $hash, for $MOK_DIR"

      local tmp
      tmp="$(mktemp -d)" || return 1
      chmod 0700 "$tmp"
      printf '%s\n' \
        '[ req ]' \
        'distinguished_name = req_distinguished_name' \
        'prompt = no' \
        'string_mask = utf8only' \
        'x509_extensions = myexts' \
        "" \
        '[ req_distinguished_name ]' \
        "CN = ''${KMOK_CN:-$(hostname) kernel module signing key}" \
        "" \
        '[ myexts ]' \
        'basicConstraints = critical,CA:FALSE' \
        'keyUsage = digitalSignature' \
        'subjectKeyIdentifier = hash' \
        'authorityKeyIdentifier = keyid' \
        'extendedKeyUsage = codeSigning,1.3.6.1.4.1.2312.16.1.2' \
        > "$tmp/x509.genkey"

      # $keytype is deliberately unquoted: it can carry -pkeyopt.
      if ! openssl req -new -nodes -utf8 -"$hash" -days "''${KMOK_DAYS:-36500}" -batch -quiet -x509 \
             -config "$tmp/x509.genkey" -newkey $keytype \
             -outform PEM -out "$tmp/cert.pem" -keyout "$tmp/key.pem" \
         || ! openssl x509 -in "$tmp/cert.pem" -outform DER -out "$tmp/MOK.der"; then
        rm -rf "$tmp"
        kmok__die "openssl failed"
        return 1
      fi
      cat "$tmp/key.pem" "$tmp/cert.pem" > "$tmp/MOK.priv"

      if [ "$force" = 1 ]; then
        local ts f
        ts="$(date +%Y%m%d-%H%M%S)"
        for f in MOK.priv MOK.pem MOK.der; do
          if kmok__sudo test -e "$MOK_DIR/$f"; then
            kmok__sudo mv "$MOK_DIR/$f" "$MOK_DIR/$f.bak-$ts"
            kmok__sudo setfacl -b "$MOK_DIR/$f.bak-$ts"
            kmok__sudo chmod go-rwx "$MOK_DIR/$f.bak-$ts"
          fi
        done
      fi

      # Root-owned. $USER reads it for sandbox builds, nixbld for flake builds
      # (which see /boot/secrets through extra-sandbox-paths).
      local rc=0
      kmok__sudo install -m 0600 -o root -g root "$tmp/MOK.priv" "$MOK_PRIV" \
        && kmok__sudo setfacl -m "u:$USER:r,g:nixbld:r" "$MOK_PRIV" \
        && kmok__sudo install -m 0644 -o root -g root "$tmp/cert.pem" "$MOK_PEM" \
        && kmok__sudo install -m 0644 -o root -g root "$tmp/MOK.der" "$MOK_DER" \
        || rc=1
      shred -u "$tmp/key.pem" "$tmp/MOK.priv" 2>/dev/null
      rm -rf "$tmp"
      [ "$rc" = 0 ] || { kmok__die "installing into $MOK_DIR failed"; return 1; }

      echo "✅ wrote $MOK_PRIV (key + cert), $MOK_PEM, $MOK_DER"
      openssl x509 -in "$MOK_PEM" -noout -subject -fingerprint -sha256 -enddate
      echo "   the .config needs: CONFIG_MODULE_SIG_KEY=\"$MOK_PRIV\""
    }

    kcd() {
      local src
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      cd "$src"
    }

    kenvk() {
      local src
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      local out
      out="$(kout_for "$src")"
      echo "SRCTREE=$src"
      echo "KOUT=$out"
    }

    # --- Helpers ---
    kclean() {
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      rm -rf "$out"
      mkdir -p "$out"
      echo "🧹 cleaned $out"
    }

    kout() {
      local src
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      kout_for "$src"
    }

    kseed() {
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      mkdir -p "$out"

      if [ -f "$out/.config" ]; then
        echo "✅ using existing $out/.config"
        return 0
      fi

      if [ -f "$src/../.config" ]; then
        cp -f "$src/../.config" "$out/.config"
        echo "✅ seeded $out/.config from $src/../.config"
    return 0
      fi

      if [ -f "$src/.config" ]; then
        cp -f "$src/.config" "$out/.config"
        rm -f "$src/.config"
        echo "✅ seeded $out/.config from $src/.config (and removed $src/.config to keep SRCTREE clean)"
        return 0
      fi
      echo "❌ no .config found to seed (expected $out/.config or $src/../.config or $src/.config)"
      return 1
    }

    kdrop_srctree_config() {
      local src
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      if [ -f "$src/.config" ]; then
        rm -f "$src/.config"
        echo "🧹 removed $src/.config"
      else
        echo "✅ no $src/.config present"
      fi
    }

    # KOUT_OVERRIDE points it at a scratch out dir (knew uses one).
    kconfig() {
      unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="''${KOUT_OVERRIDE:-$(kout_for "$src")}"

      make -C "$src" -j"$(nproc)" V=1 \
        O="$out" \
        SHELL="$SHELL" CONFIG_SHELL="$CONFIG_SHELL" \
        CC="$CC" CXX="$CXX" LD="$LD" \
        AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" READELF="$READELF" \
        HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" \
        HOSTCFLAGS="$HOSTCFLAGS" HOSTCXXFLAGS="$HOSTCXXFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS" \
        LLVM=1 LLVM_IAS=1 \
        "$@"
    }

    kdefconfig() {
      kconfig olddefconfig
    }

    ksaveconfig() {
      local DEFAULT_SAVE_PATH="/etc/nixos/hosts/$KHOST/overlays/.config"
      local dst="''${1:-$DEFAULT_SAVE_PATH}"

      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      if [ ! -f "$out/.config" ]; then
        echo "❌ $out/.config missing (run: kseed; kconfig oldconfig)"
        return 1
      fi

      cp -f "$out/.config" "$src/../.config"
      chmod 0644 "$src/../.config" || true
      echo "✅ saved .config -> $src/../.config"

      if [ -n "$dst" ]; then
        cp -f "$out/.config" "$dst"
        chmod 0644 "$dst" || true
        echo "✅ saved .config -> $dst"
      fi

      # Minimal form (only what differs from defaults) beside it, for
      # readable diffs. The full .config stays the one that gets built.
      if kconfig -s savedefconfig >/dev/null; then
        cp -f "$out/defconfig" "$(dirname "''${dst:-$src/../.config}")/defconfig"
        echo "✅ saved defconfig -> $(dirname "''${dst:-$src/../.config}")/defconfig"
      else
        echo "⚠️  savedefconfig failed; .config was still saved"
      fi
    }

    khost() {
      unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      make -C "$src" -j"$(nproc)" V=1 \
        O="$out" \
        SHELL="$SHELL" CONFIG_SHELL="$CONFIG_SHELL" \
        LLVM=1 LLVM_IAS=1 \
        CC="$CC" LD="$LD" \
        HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" \
        HOSTCFLAGS="$HOSTCFLAGS" HOSTCXXFLAGS="$HOSTCXXFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS" \
        scripts_basic scripts/mod
    }

    kkernel() {
      unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      kmok_check || return 1

      make -C "$src" -j"$(nproc)" --output-sync=recurse V=1 \
        O="$out" \
        SHELL="$SHELL" CONFIG_SHELL="$CONFIG_SHELL" \
        CC="$CC" CXX="$CXX" \
        HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" \
        HOSTCFLAGS="$HOSTCFLAGS" HOSTCXXFLAGS="$HOSTCXXFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS" \
        LLVM=1 LLVM_IAS=1 \
        bzImage modules 2>&1 | tee build.log
    }

    kenv() {
      echo "CC=$CC"
      echo "CXX=$CXX"
      echo "LD=$LD"
      echo
      echo "HOSTCC=$HOSTCC"
      echo "HOSTCXX=$HOSTCXX"
      echo "HOSTLD=$HOSTLD"
      echo
      echo "SHELL=$SHELL"
      echo "CONFIG_SHELL=$CONFIG_SHELL"
      kenvk || true
      echo
      type -a "$HOSTCC" || true
      type -a "$CC" || true
      type -a "$HOSTLD" || true
    }

    kmok_status() {
      local f
      for f in "$MOK_PRIV" "$MOK_PEM" "$MOK_DER"; do
        echo "$f $( [ -e "$f" ] && echo "(present)" || echo "(missing)" )"
      done
      [ -r "$MOK_PEM" ] && openssl x509 -in "$MOK_PEM" -noout -subject -enddate
      echo "CONFIG_MODULE_SIG_KEY=$(kmok__cfg MODULE_SIG_KEY || echo '(no .config)')"
    }

    # ------------------------------------------------------------------
    # Review helpers
    # ------------------------------------------------------------------

    # kernel-hardening-checker on the out-dir .config, the kernel command
    # line and sysctls. The command line defaults to the host's configured
    # boot.kernelParams (KCHECK_CMDLINE=<file> overrides, e.g. /proc/cmdline).
    # sysctls come from the running kernel, so read those with that in mind.
    # Extra arguments go to the checker (e.g. -m show_fail).
    kcheck() {
      local src out tmp
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      [ -f "$out/.config" ] || { echo "❌ $out/.config missing (run kprep)"; return 1; }

      tmp="$(mktemp -d)" || return 1
      if [ -n "''${KCHECK_CMDLINE:-}" ]; then
        cp "$KCHECK_CMDLINE" "$tmp/cmdline"
      elif ! nix eval --raw "/etc/nixos#nixosConfigurations.$KHOST.config.boot.kernelParams" \
               --apply 'ps: builtins.concatStringsSep " " ps' > "$tmp/cmdline" 2>/dev/null; then
        echo "⚠️  couldn't evaluate $KHOST's kernelParams; using /proc/cmdline"
        cp /proc/cmdline "$tmp/cmdline"
      fi
      sysctl -a > "$tmp/sysctl" 2>/dev/null

      kernel-hardening-checker -c "$out/.config" -l "$tmp/cmdline" -s "$tmp/sysctl" "$@" \
        | tee "$out/kcheck.txt"
      rm -rf "$tmp"
      echo "📝 $out/kcheck.txt"
    }

    # What a version bump does to a config, before you touch it: the options
    # new in this tree (listnewconfig, helpnewconfig), and what olddefconfig
    # would change (diffconfig). Works on a copy in a scratch out dir; the
    # real out dir and .config are untouched.
    #   knew [config]   (default: repo-root .config, else the flake's)
    knew() {
      local src out scratch base report
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      base="''${1:-}"
      if [ -z "$base" ]; then
        if [ -f "$src/../.config" ]; then base="$src/../.config"
        else base="/etc/nixos/hosts/$KHOST/overlays/.config"; fi
      fi
      [ -f "$base" ] || { echo "❌ no config at $base"; return 1; }

      scratch="$out.knew"
      report="$out/knew"
      rm -rf "$scratch" "$report"
      mkdir -p "$scratch" "$report"
      cp -f "$base" "$report/base.config"
      cp -f "$base" "$scratch/.config"

      KOUT_OVERRIDE="$scratch" kconfig -s listnewconfig > "$report/listnewconfig.txt" || return 1
      KOUT_OVERRIDE="$scratch" kconfig -s helpnewconfig > "$report/helpnewconfig.txt" || return 1
      KOUT_OVERRIDE="$scratch" kconfig -s olddefconfig >/dev/null || return 1
      cp -f "$scratch/.config" "$report/olddefconfig.config"
      python3 "$src/scripts/diffconfig" "$report/base.config" "$report/olddefconfig.config" \
        > "$report/diffconfig.txt"
      rm -rf "$scratch"

      echo "🔎 $base against $(basename "$src"):"
      echo "   $(grep -c '^CONFIG_' "$report/listnewconfig.txt") new options   -> $report/listnewconfig.txt (help: helpnewconfig.txt)"
      echo "   $(grep -c . "$report/diffconfig.txt") olddefconfig changes -> $report/diffconfig.txt"
    }

    # ------------------------------------------------------------------
    # Manual workflow "orchestration" helpers
    # ------------------------------------------------------------------
    kstatus() {
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      echo "SRCTREE=$src"
      echo "KOUT=$out"
      echo
      echo "Config:"
      echo "  $out/.config $( [ -f "$out/.config" ] && echo "(present)" || echo "(missing)" )"
      echo "  $src/../.config $( [ -f "$src/../.config" ] && echo "(present)" || echo "(missing)" )"
      echo
      kmok_status
    }

    kprep() {
      kensure_src || return 1

      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      if [ "''${KCLEAN:-0}" = "1" ]; then
        kclean || return 1
      else
        mkdir -p "$out"
      fi

      kseed || return 1

      local cfgTarget="''${KPREP_CONFIG_TARGET:-oldconfig}"
      echo "🧩 kprep config step: $cfgTarget (clang toolchain)"
      kconfig "$cfgTarget" || return 1

      kmok_check || return 1

      khost || return 1

      # The LTO choice silently falls back to LTO_NONE when kconfig runs
      # without the LLVM context; catch it changing from the repo-root config.
      local want have
      want="$(grep -oE '^CONFIG_LTO_(NONE|CLANG_THIN|CLANG_FULL)=y' "$src/../.config" 2>/dev/null)"
      have="$(grep -oE '^CONFIG_LTO_(NONE|CLANG_THIN|CLANG_FULL)=y' "$out/.config" 2>/dev/null)"
      if [ -n "$want" ] && [ "$want" != "$have" ]; then
        echo "❌ OUT/.config's LTO mode changed during kprep (likely syncconfig without consistent LLVM context)."
        echo "   repo-root expects: $want"
        echo "   out dir has:       ''${have:-(none)}"
        echo "   Fix: ensure khost/kconfig invocations include LLVM=1 LLVM_IAS=1 and CC/LD context."
        return 1
      fi

      echo "✅ prep complete"
      kstatus || true
    }

    knconfig() {
      kprep || return 1
      kconfig nconfig
    }
    kmenu() {
      kprep || return 1
      kconfig menuconfig
    }

    kbuild() {
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      if [ ! -f "$out/.config" ]; then
        echo "⚠️  $out/.config missing; running kprep first"
        kprep || return 1
      fi
      kkernel
    }

    kgo() {
      local ui="''${KCONFIG_UI:-nconfig}"
      kprep || return 1
      kconfig "$ui" || return 1
      kkernel
    }

    kphases() {
      KFORCE_PATCH=1 kensure_src || return 1
      echo "✅ phases complete (unpackPhase + patchPhase)"
      local src
      src="$(ksrc)" || return 1
      echo "SRCTREE=$src"
    }

    klog() {
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      tail -n "''${1:-200}" -f "$out/build.log" 2>/dev/null || tail -n "''${1:-200}" -f build.log
    }

    lh() { eza --group --header --group-directories-first --long --icons --git --all --binary --dereference --links "$@"; }
    eval "$(starship init bash)"
  '';
})
