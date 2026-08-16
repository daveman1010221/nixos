let
  flakeLock = builtins.fromJSON (builtins.readFile /etc/nixos/flake.lock);
  rootInputs = flakeLock.nodes.${flakeLock.root}.inputs;
  nixpkgsRev = flakeLock.nodes.${rootInputs.nixpkgs}.locked.rev;
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/${nixpkgsRev}.tar.gz") {};
in
pkgs.linux_7_1.overrideAttrs (o: {
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

    pkgs.starship
    pkgs.eza
  ];

  shellHook = ''
    export NIX_ENFORCE_NO_NATIVE=0
    set +e

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
    # MOK key material – sourced directly from /boot/secrets
    # ------------------------------------------------------------------
    export MOK_PEM="/boot/secrets/MOK.pem"
    export MOK_PRIV="/boot/secrets/MOK.priv"

    export KCFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"
    export KAFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"

    export HOSTCFLAGS=""
    export HOSTCXXFLAGS=""
    export HOSTLDFLAGS=""

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
        echo "❌ unpackPhase is not available in this shell (did you enter via nix-shell on the kernel derivation?)"
        return 1
      fi
      echo "📦 no kernel tree found; running unpackPhase"
      unpackPhase
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
    # MOK helpers (shared primitives)
    # ------------------------------------------------------------------
    kmok__need_install() {
      if ! command -v install >/dev/null 2>&1; then
        echo "❌ install(1) not found (coreutils missing?)"
        return 1
      fi
      return 0
    }

    kmok__sudo() {
      if ! command -v sudo >/dev/null 2>&1; then
        echo "❌ sudo not available (needed for /boot/secrets access)"
        return 1
      fi
      sudo "$@"
    }

    # Secure copy: if source is not readable, use sudo; always set destination
    # owner to $USER with given mode.
    kmok__safe_install() {
      local mode="$1" src="$2" dst="$3"
      kmok__need_install || return 1
      [ -f "$src" ] || { kmok__die "source missing: $src"; return 1; }
      if [ -r "$src" ]; then
        install -m "$mode" -D "$src" "$dst" || return 1
      else
        kmok__sudo install -m "$mode" -o "$USER" -D "$src" "$dst" || return 1
      fi
      return 0
    }

    kmok__warn() { echo "⚠️  $*"; }
    kmok__die()  { echo "❌ $*"; return 1; }

    # ------------------------------------------------------------------
    # MOK helpers
    # ------------------------------------------------------------------
    kneed_sudo() {
      if [ -n "''${MOK_DIR:-}" ] && [[ "$MOK_DIR" == /run/* ]]; then
        return 0
      fi
      [ -n "''${MOK_DIR:-}" ] && [ ! -w "$MOK_DIR" ] && return 0
      return 1
    }

    kmok_prepare() {
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      # Source directly from /boot/secrets; die if missing
      [ -f "$MOK_PEM" ]  || { kmok__die "MOK.pem not found: $MOK_PEM"; return 1; }
      [ -f "$MOK_PRIV" ] || { kmok__die "MOK.priv not found: $MOK_PRIV"; return 1; }

      mkdir -p "$out" "$out/certs" "$src/certs" || return 1

      kmok__safe_install 0644 "$MOK_PEM" "$out/MOK.pem"       || return 1
      kmok__safe_install 0644 "$MOK_PEM" "$out/certs/MOK.pem" || return 1
      kmok__safe_install 0644 "$MOK_PEM" "$src/certs/MOK.pem" || return 1

      kmok__safe_install 0600 "$MOK_PRIV" "$out/MOK.priv"       || return 1
      kmok__safe_install 0600 "$MOK_PRIV" "$out/certs/MOK.priv" || return 1
      kmok__safe_install 0600 "$MOK_PRIV" "$src/certs/MOK.priv" || return 1

      echo "✅ MOK invariants enforced:"
      echo "   runtime: $MOK_PEM , $MOK_PRIV"
      echo "   objtree:  $out/MOK.pem  and  $out/certs/MOK.pem"
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

      kmok_prepare || return 1

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

    kconfig() {
      unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

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
      local DEFAULT_SAVE_PATH="/etc/nixos/hosts/whitey/overlays/.config"
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

      kmok_prepare || return 1

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
      echo "MOK_PEM=$MOK_PEM  $( [ -f "$MOK_PEM" ] && echo "(present)" || echo "(missing)" )"
      echo "MOK_PRIV=$MOK_PRIV $( [ -f "$MOK_PRIV" ] && echo "(present)" || echo "(missing)" )"
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

      kmok_prepare || return 1

      khost || return 1

      if rg -q '^CONFIG_LTO_NONE=y$' "$out/.config" 2>/dev/null && rg -q '^CONFIG_LTO_CLANG_THIN=y$' "$src/../.config" 2>/dev/null; then
        echo "❌ OUT/.config was rewritten to LTO_NONE during kprep (likely syncconfig without consistent LLVM context)."
        echo "   repo-root expects: CONFIG_LTO_CLANG_THIN=y"
        echo "   out dir has:       CONFIG_LTO_NONE=y"
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
      KFORCE_PATCH=1 kensure_src
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
