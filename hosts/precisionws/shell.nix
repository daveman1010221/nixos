let
  pkgs = import <nixpkgs> {};
in
pkgs.linux_6_19.overrideAttrs (o: {
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
    # MOK key material (default: /run/mok; fallback: repo root)
    # ------------------------------------------------------------------
    export MOK_DIR="''${MOK_DIR:-/run/mok}"
    export MOK_PEM="''${MOK_PEM:-$MOK_DIR/MOK.pem}"
    export MOK_PRIV="''${MOK_PRIV:-$MOK_DIR/MOK.priv}"
    export MOK_FALLBACK_PEM="''${MOK_FALLBACK_PEM:-}"
    export MOK_FALLBACK_PRIV="''${MOK_FALLBACK_PRIV:-}"
    export KMOK_REQUIRE_PRIV="''${KMOK_REQUIRE_PRIV:-0}"
    export MOK_NIXBLD_GROUP="''${MOK_NIXBLD_GROUP:-nixbld}"

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
    #
    # What you asked for:
    #   - If no linux-* dir exists: run unpackPhase
    #   - Then run patchPhase from inside the unpacked tree
    #   - Then continue with the rest of the workflow
    #
    # Reality check:
    #   - unpackPhase/patchPhase are available in nix-shell because we’re in a derivation env
    #   - but they do NOTHING unless you call them
    #   - patchPhase generally expects to run from $sourceRoot
    #
    # These helpers make it deterministic and idempotent.
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
      # patchPhase can be re-run, but we avoid re-running it unless asked.
      # marker lives in repo root so you can blow it away with KCLEAN=1 or rm.
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

      # We need to run patchPhase from inside the kernel source root. Determine it.
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

    # Fan-out copy: copy ONE source to MANY destinations.
    # `cp` cannot do this correctly in a single invocation.
    #
    # Usage:
    #   kmok__fanout 0644 /run/mok/MOK.pem  "$out/MOK.pem" "$out/certs/MOK.pem" "$src/certs/MOK.pem"
    kmok__fanout() {
      local mode="$1"
      local src="$2"
      shift 2

      kmok__need_install || return 1
      if [ ! -f "$src" ]; then
        kmok__die "fanout source missing: $src"
      fi

      local dst
      for dst in "$@"; do
        # -D creates parent directories (no more "certs doesn't exist" nonsense)
        install -m "$mode" -D "$src" "$dst" || return 1
      done
      return 0
    }

    kmok__warn() { echo "⚠️  $*"; }
    kmok__die()  { echo "❌ $*"; return 1; }

    # ------------------------------------------------------------------
    # MOK helpers
    #
    # Goal:
    #   - Automated flow expects keys at /run/mok/{MOK.pem,MOK.priv}
    #   - Manual flow is allowed to keep keys next to the kernel tree (repo root)
    #   - kbuild often looks for "MOK.pem" relative to O= output dir (certs/)
    #   - We sync into BOTH SRCTREE/certs and O=/certs to keep it deterministic
    #
    # Notes:
    #   - We do NOT try to be clever about secureboot; we just make builds stop failing.
    #   - Cleanup removes /run/mok copies (optional but recommended).
    # ------------------------------------------------------------------

    # Ask for sudo only when we actually need it.
    # (You said: default unprivileged user; ask when script needs sudo.)
    kneed_sudo() {
      # Only bother if we’re targeting /run (root-owned) or if directory isn’t writable.
      if [ -n "''${MOK_DIR:-}" ] && [[ "$MOK_DIR" == /run/* ]]; then
        return 0
      fi
      [ -n "''${MOK_DIR:-}" ] && [ ! -w "$MOK_DIR" ] && return 0
      return 1
    }

    kmok__need_acl_tools() {
      if ! command -v setfacl >/dev/null 2>&1; then
        echo "❌ setfacl not found (pkgs.acl missing?)"
        return 1
      fi
      return 0
    }

    kmok__sudo() {
      if ! command -v sudo >/dev/null 2>&1; then
        echo "❌ sudo not available (needed for $MOK_DIR)"
        return 1
      fi
      sudo "$@"
    }

    kmok__fix_dir_perms() {
      # Goal:
      #   - /run/mok must be traversable by you (manual shell) AND nixbld (nix builds)
      #   - do NOT make MOK.priv world-readable
      # Approach:
      #   - keep /run/mok owned by root, mode 0755 (or 0750) + ACLs for nixbld/user
      #   - if MOK_NIXBLD_GROUP exists, ensure it has rx on dir
      #   - ensure current user has rx on dir (even if umask/ownership drift)
      local grp="''${MOK_NIXBLD_GROUP:-nixbld}"

      kmok__need_acl_tools || return 1

      # Directory base perms:
      #   - owned by root
      #   - group nixbld (so nixbld* can read keys when needed)
      #   - not world-traversable by default
      kmok__sudo install -d -m 0750 -o root -g "$grp" "$MOK_DIR" || return 1

      # If the nixbld group exists, give it rx explicitly (ACL) so nixbld* can read files.
      if getent group "$grp" >/dev/null 2>&1; then
        kmok__sudo setfacl -m "g:$grp:rx" "$MOK_DIR" >/dev/null 2>&1 || true
        kmok__sudo setfacl -m "d:g:$grp:rx" "$MOK_DIR" >/dev/null 2>&1 || true
      fi

      # Always ensure *this* user can traverse (ACL beats surprises).
      kmok__sudo setfacl -m "u:$USER:rx" "$MOK_DIR" >/dev/null 2>&1 || true
      kmok__sudo setfacl -m "d:u:$USER:rx" "$MOK_DIR" >/dev/null 2>&1 || true
    }

    kmok__fix_file_perms() {
      # Ensure:
      #   - MOK.pem is readable by you + nixbld (safe to be 0644)
      #   - MOK.priv is readable by you + nixbld but NOT world-readable (0640)
      # We rely on group + ACLs rather than trying to guess your group memberships.
      local path="$1"
      local mode="$2"
      local grp="''${MOK_NIXBLD_GROUP:-nixbld}"

      kmok__need_acl_tools || return 1

      # Put file in nixbld group if available; otherwise keep root:root.
      if getent group "$grp" >/dev/null 2>&1; then
        kmok__sudo chgrp "$grp" "$path" >/dev/null 2>&1 || true
      fi

      kmok__sudo chmod "$mode" "$path" >/dev/null 2>&1 || true

      # Ensure nixbld group can read if it exists.
      if getent group "$grp" >/dev/null 2>&1; then
        kmok__sudo setfacl -m "g:$grp:r--" "$path" >/dev/null 2>&1 || true
      fi

      # Ensure current user can read (and only read).
      kmok__sudo setfacl -m "u:$USER:r--" "$path" >/dev/null 2>&1 || true
    }

    kmok_mkdir() {
      # Create MOK_DIR, using sudo if required.
      if mkdir -p "$MOK_DIR" 2>/dev/null; then
        return 0
      fi

      if command -v sudo >/dev/null 2>&1 && kneed_sudo; then
        echo "🔐 need sudo to create/fix $MOK_DIR"
        kmok__fix_dir_perms || return 1
        return 0
      fi

      echo "❌ cannot create $MOK_DIR (permission denied?)"
      return 1
    }

    kmok_prepare() {
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      # Resolve stable fallback paths from repo root unless user overrides explicitly.
      local root
      root="$(kroot)" || { echo "❌ can't determine repo root"; return 1; }
      local fb_pem fb_priv
      fb_pem="''${MOK_FALLBACK_PEM:-$root/MOK.pem}"
      fb_priv="''${MOK_FALLBACK_PRIV:-$root/MOK.priv}"

      # Create runtime dir. If it’s /run/mok, you almost certainly need sudo.
      kmok_mkdir || return 1
      # If we’re in /run/mok, force sane perms + ACLs so you AND nixbld can read it.
      if [[ "$MOK_DIR" == /run/* ]] && command -v sudo >/dev/null 2>&1; then
        kmok__fix_dir_perms || return 1
      fi

      # If /run/mok already has the files, great. Otherwise seed from repo root.
      if [ ! -f "$MOK_PEM" ]; then
        if [ -f "$fb_pem" ]; then
          if install -m 0644 "$fb_pem" "$MOK_PEM" 2>/dev/null; then
            echo "✅ seeded $MOK_PEM from $fb_pem"
          else
            if command -v sudo >/dev/null 2>&1 && kneed_sudo; then
              echo "🔐 need sudo to write $MOK_PEM"
              kmok__sudo install -m 0640 -o root -g "$MOK_NIXBLD_GROUP" "$fb_pem" "$MOK_PEM" || return 1
              # Make sure you + nixbld can read it (and you can see it in kstatus).
              kmok__fix_file_perms "$MOK_PEM" 0640 || true
              echo "✅ seeded $MOK_PEM from $fb_pem"
            else
              echo "❌ failed to write $MOK_PEM (permission denied?)"
              return 1
            fi
          fi
        else
          echo "❌ missing MOK.pem: neither $MOK_PEM nor $fb_pem exists"
          return 1
        fi
      fi

      # Private key is config-dependent. Default: warn and continue if missing.
      # If you want hard invariants, set: KMOK_REQUIRE_PRIV=1
      if [ ! -f "$MOK_PRIV" ]; then
        if [ -f "$fb_priv" ]; then
          if install -m 0600 "$fb_priv" "$MOK_PRIV" 2>/dev/null; then
            echo "✅ seeded $MOK_PRIV from $fb_priv"
          else
            if command -v sudo >/dev/null 2>&1 && kneed_sudo; then
              echo "🔐 need sudo to write $MOK_PRIV"
              kmok__sudo install -m 0640 -o root -g "$MOK_NIXBLD_GROUP" "$fb_priv" "$MOK_PRIV" || return 1
              kmok__fix_file_perms "$MOK_PRIV" 0640 || true
              echo "✅ seeded $MOK_PRIV from $fb_priv"
            else
              if [ "''${KMOK_REQUIRE_PRIV:-0}" = "1" ]; then
                kmok__die "failed to write $MOK_PRIV (permission denied?)"
              fi
              kmok__warn "failed to write $MOK_PRIV (permission denied?); continuing (KMOK_REQUIRE_PRIV=0)"
            fi
          fi
        else
          if [ "''${KMOK_REQUIRE_PRIV:-0}" = "1" ]; then
            kmok__die "missing MOK.priv: neither $MOK_PRIV nor $fb_priv exists"
          fi
          kmok__warn "missing MOK.priv: neither $MOK_PRIV nor $fb_priv exists (continuing; KMOK_REQUIRE_PRIV=0)"
        fi
      fi

      # If files already existed under /run/mok but perms/ACLs are wrong, fix them anyway.
      if [[ "$MOK_DIR" == /run/* ]] && command -v sudo >/dev/null 2>&1; then
        [ -f "$MOK_PEM" ] && kmok__fix_file_perms "$MOK_PEM" 0640 || true
        [ -f "$MOK_PRIV" ] && kmok__fix_file_perms "$MOK_PRIV" 0640 || true
      fi

      # ------------------------------------------------------------------
      # Build invariants (THIS is what stops the "No rule to make target MOK.pem" crap)
      #
      # 1) Keep your preferred workflow: CONFIG_SYSTEM_TRUSTED_KEYS="MOK.pem"
      #    => ensure objtree root has MOK.pem
      # 2) certs rules often run in objtree/certs
      #    => also ensure objtree/certs has MOK.pem
      # 3) Optional convenience: src/certs copy
      # ------------------------------------------------------------------
      # NOTE:
      #   Do NOT try to do multi-dest copies with a single `cp` invocation.
      #   `cp a b c d` means: "copy a,b,c into directory d".
      #   If d is not a directory, you get failures and missing keys in the exact
      #   places the kernel build expects them.

      mkdir -p "$out" "$out/certs" "$src/certs" || return 1

      # Public cert is safe 0644 in the build trees.
      kmok__fanout 0644 "$MOK_PEM" \
        "$out/MOK.pem" \
        "$out/certs/MOK.pem" \
        "$src/certs/MOK.pem" || return 1

      # Private key: only fanout if we actually have it.
      if [ -f "$MOK_PRIV" ]; then
        kmok__fanout 0600 "$MOK_PRIV" \
          "$out/MOK.priv" \
          "$out/certs/MOK.priv" \
          "$src/certs/MOK.priv" || return 1
      else
        if [ "''${KMOK_REQUIRE_PRIV:-0}" = "1" ]; then
          kmok__die "MOK.priv missing at runtime; KMOK_REQUIRE_PRIV=1"
        fi
        kmok__warn "MOK.priv not present; fanout skipped (KMOK_REQUIRE_PRIV=0)"
      fi

      echo "✅ MOK invariants enforced:"
      echo "   runtime: $MOK_PEM , $MOK_PRIV"
      echo "   objtree:  $out/MOK.pem  and  $out/certs/MOK.pem"
    }

    kmok_cleanup() {
      # Only clean /run/mok by default; leave repo-root keys alone.
      # Set KMOK_CLEAN_ALL=1 if you really want to scrub SRCTREE/O copies too.
      local src out
      src="$(ksrc)" || true
      out=""
      if [ -n "''${src:-}" ]; then
        out="$(kout_for "$src")"
      fi

      # Remove runtime copies; use sudo if needed (because /run/mok is root-owned).
      if rm -f "$MOK_PEM" "$MOK_PRIV" 2>/dev/null; then
        :
      else
        if command -v sudo >/dev/null 2>&1 && kneed_sudo; then
          echo "🔐 need sudo to clean $MOK_DIR"
          kmok__sudo rm -f "$MOK_PEM" "$MOK_PRIV" 2>/dev/null || true
        fi
      fi
      if rmdir "$MOK_DIR" 2>/dev/null; then
        :
      else
        if command -v sudo >/dev/null 2>&1 && kneed_sudo; then
          sudo rmdir "$MOK_DIR" 2>/dev/null || true
        fi
      fi
      echo "🧹 removed runtime copies from $MOK_DIR (best-effort)"

      if [ "''${KMOK_CLEAN_ALL:-0}" = "1" ] && [ -n "''${src:-}" ]; then
        rm -f "$src/certs/MOK.pem" "$src/certs/MOK.priv" 2>/dev/null || true
        rm -f "$out/certs/MOK.pem" "$out/certs/MOK.priv" 2>/dev/null || true
        echo "🧹 also removed SRCTREE/O copies (KMOK_CLEAN_ALL=1)"
      fi
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

    # Seed OUT/.config once so kconfig stops asking the same questions forever.
    # Priority:
    #   1) OUT/.config
    #   2) SRCTREE/../.config   (your repo-root config pattern)
    #   3) SRCTREE/.config      (BUT: remove it after copy, because O= builds
    #                           treat SRCTREE/.config as "dirty source tree")
    kseed() {
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      mkdir -p "$out"

      # Keys are part of "ready to build". If kprep/knconfig runs, MOK must be present.
      # Idempotent: if they already exist, this is basically a no-op.
      kmok_prepare || return 1

      if [ -f "$out/.config" ]; then
        echo "✅ using existing $out/.config"
        return 0
      fi

      # Prefer repo-root config (keeps SRCTREE clean for O= builds)
      if [ -f "$src/../.config" ]; then
        cp -f "$src/../.config" "$out/.config"
        echo "✅ seeded $out/.config from $src/../.config"
	return 0
      fi

      # Last resort: SRCTREE/.config (if you copied it in there by habit)
      if [ -f "$src/.config" ]; then
        cp -f "$src/.config" "$out/.config"
        # IMPORTANT: remove SRCTREE/.config so kbuild doesn't scream "mrproper"
        rm -f "$src/.config"
        echo "✅ seeded $out/.config from $src/.config (and removed $src/.config to keep SRCTREE clean)"
        return 0
      fi
      echo "❌ no .config found to seed (expected $out/.config or $src/../.config or $src/.config)"
      return 1
    }

    # If you accidentally copied a config into SRCTREE, nuke it (O= builds want SRCTREE clean).
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

    # Run config update interactively (nconfig/menuconfig/etc).
    # Always use O= and run from SRCTREE so we don't confuse kbuild.
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

    # Non-interactive fill-in for *new* symbols only.
    # (Use this when you just want it to shut up and pick defaults.)
    kdefconfig() {
      kconfig olddefconfig
    }

    # Save your now-updated .config back to wherever you source it from in NixOS.
    # Change DEFAULT_SAVE_PATH to your real overlay path.
    ksaveconfig() {
      local DEFAULT_SAVE_PATH="/etc/nixos/hosts/precisionws/overlays/.config"
      local dst="''${1:-$DEFAULT_SAVE_PATH}"

      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      if [ ! -f "$out/.config" ]; then
        echo "❌ $out/.config missing (run: kseed; kconfig oldconfig)"
        return 1
      fi

      # Keep a copy in repo root for your workflow (easy copy into a fresh tree).
      cp -f "$out/.config" "$src/../.config"
      chmod 0644 "$src/../.config" || true
      echo "✅ saved .config -> $src/../.config"

      # And also to the NixOS overlay path (if it exists / is writable).
      if [ -n "$dst" ]; then
        cp -f "$out/.config" "$dst"
        chmod 0644 "$dst" || true
        echo "✅ saved .config -> $dst"
      fi
    }

    # Host-side targets (still uses O= so we don’t churn)
    khost() {
      unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      # IMPORTANT:
      #   khost may run syncconfig/conf --syncconfig (via scripts/mod or friends),
      #   which can rewrite OUT/.config + include/config/auto.conf.
      #   We must keep the *kernel toolchain context* consistent here (LLVM=1 etc),
      #   while still compiling host tools with HOSTCC (gcc-wrapper).
      make -C "$src" -j"$(nproc)" V=1 \
        O="$out" \
        SHELL="$SHELL" CONFIG_SHELL="$CONFIG_SHELL" \
        LLVM=1 LLVM_IAS=1 \
        CC="$CC" LD="$LD" \
        HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" \
        HOSTCFLAGS="$HOSTCFLAGS" HOSTCXXFLAGS="$HOSTCXXFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS" \
        scripts_basic scripts/mod
    }

    # Kernel build: clang for kernel, gcc-wrapper for host tools
    kkernel() {
      unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      # Ensure key material is available in the places kbuild expects.
      kmok_prepare || return 1

      make -C "$src" -j"$(nproc)" --output-sync=recurse V=1 \
        O="$out" \
        SHELL="$SHELL" CONFIG_SHELL="$CONFIG_SHELL" \
        CC="$CC" CXX="$CXX" \
        HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" \
        HOSTCFLAGS="$HOSTCFLAGS" HOSTCXXFLAGS="$HOSTCXXFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS" \
        LLVM=1 LLVM_IAS=1 \
        bzImage modules 2>&1 | tee build.log

      # Optional cleanup: keep /run/mok from hanging around after a successful build.
      # Set KMOK_NO_CLEAN=1 to keep runtime copies for iterative debugging.
      if [ "''${KMOK_NO_CLEAN:-0}" != "1" ]; then
        kmok_cleanup || true
      fi
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
      echo "MOK_DIR=$MOK_DIR"
      echo "MOK_PEM=$MOK_PEM  $( [ -f "$MOK_PEM" ] && echo "(present)" || echo "(missing)" )"
      echo "MOK_PRIV=$MOK_PRIV $( [ -f "$MOK_PRIV" ] && echo "(present)" || echo "(missing)" )"
      echo "MOK_FALLBACK_PEM=$MOK_FALLBACK_PEM  $( [ -f "$MOK_FALLBACK_PEM" ] && echo "(present)" || echo "(missing)" )"
      echo "MOK_FALLBACK_PRIV=$MOK_FALLBACK_PRIV $( [ -f "$MOK_FALLBACK_PRIV" ] && echo "(present)" || echo "(missing)" )"
    }

    # One-liner if you ever need to reassert sane perms after a reboot or a “sudo did something dumb”.
    kmok_fix_perms() {
      if [[ "$MOK_DIR" != /run/* ]]; then
        echo "⚠️  MOK_DIR is not under /run; nothing to fix for nixbld access"
        return 0
      fi
      kmok__fix_dir_perms || return 1
      [ -f "$MOK_PEM" ] && kmok__fix_file_perms "$MOK_PEM" 0640 || true
      [ -f "$MOK_PRIV" ] && kmok__fix_file_perms "$MOK_PRIV" 0640 || true
      echo "✅ /run/mok perms/ACLs enforced (user=$USER, nixbld-group=$MOK_NIXBLD_GROUP)"
    }

    # ------------------------------------------------------------------
    # Manual workflow "orchestration" helpers
    #
    # Target interactive steps only:
    #   - open config UI (nconfig/menuconfig/etc)
    #   - run actual build
    #   - save config
    #
    # Everything else becomes one-liners.
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

    # Prep repo + out dir + config + keys + host tools.
    #
    # Usage:
    #   kprep          # idempotent, does not wipe out dir
    #   KCLEAN=1 kprep # wipe out dir first (clean build)
    #
    # Notes:
    #   - DOES NOT run interactive config UI.
    #   - DOES run *oldconfig* by default so you are PROMPTED for unresolved / choice symbols.
    #     Override with: KPREP_CONFIG_TARGET=olddefconfig (if you hate yourself less that day).
    kprep() {
      # Ensure kernel source exists and patches (if any) are applied.
      kensure_src || return 1

      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"

      if [ "''${KCLEAN:-0}" = "1" ]; then
        kclean || return 1
      else
        mkdir -p "$out"
      fi

      # Ensure we are building against a known .config in O=
      kseed || return 1

      # Config reconciliation:
      #   - default: oldconfig     => PROMPTS you for unresolved/choice symbols (LTO, etc.)
      #   - opt-out: olddefconfig  => auto-picks defaults silently
      local cfgTarget="''${KPREP_CONFIG_TARGET:-oldconfig}"
      echo "🧩 kprep config step: $cfgTarget (clang toolchain)"
      kconfig "$cfgTarget" || return 1

      # Ensure key material exists where kbuild expects (after clean, after syncconfig).
      kmok_prepare || return 1

      # Build host-side tooling once (modpost, etc.)
      khost || return 1

      # (This is the failure mode you just hit: OUT/.config drifts from repo-root .config
      #  because a make invocation didn’t carry the LLVM context.)
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

    # Interactive config entry points that automatically ensure O= is ready.
    # Choose one.
    knconfig() {
      kprep || return 1
      kconfig nconfig
    }
    kmenu() {
      kprep || return 1
      kconfig menuconfig
    }

    # Build only (assumes kprep was run, but will attempt minimal prep if not).
    kbuild() {
      # If someone forgot kprep, do the minimum to avoid confusing failures.
      local src out
      src="$(ksrc)" || { echo "❌ can't find kernel source tree from $PWD"; return 1; }
      out="$(kout_for "$src")"
      if [ ! -f "$out/.config" ]; then
        echo "⚠️  $out/.config missing; running kprep first"
        kprep || return 1
      fi
      kkernel
    }

    # One-shot "do the thing" flow (prep + interactive config + build).
    # Default: nconfig. Override with KCONFIG_UI=menuconfig.
    kgo() {
      local ui="''${KCONFIG_UI:-nconfig}"
      kprep || return 1
      kconfig "$ui" || return 1
      kkernel
    }

    # Force the “repo flow” phases explicitly (useful when you change patches).
    # Example:
    #   KFORCE_PATCH=1 kphases
    kphases() {
      KFORCE_PATCH=1 kensure_src
      echo "✅ phases complete (unpackPhase + patchPhase)"
      local src
      src="$(ksrc)" || return 1
      echo "SRCTREE=$src"
    }

    # Convenience for watching build output
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
