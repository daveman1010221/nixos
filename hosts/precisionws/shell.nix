let
  pkgs = import <nixpkgs> {};
in
pkgs.linux_6_17.overrideAttrs (o: {
  # IMPORTANT: don't use clangStdenv (wrapped) for the kernel build itself
  stdenv = pkgs.stdenv;

  nativeBuildInputs = (o.nativeBuildInputs or []) ++ [
    # Kernel toolchain bits
    pkgs.llvmPackages.clang-unwrapped
    pkgs.llvmPackages.lld
    pkgs.llvmPackages.llvm
    pkgs.llvmPackages.bintools

    # Kernel build deps
    pkgs.pkg-config
    pkgs.ncurses
    pkgs.bison
    pkgs.flex
    pkgs.openssl
    pkgs.bc
    pkgs.kmod
    pkgs.pahole

    # Host headers / libc bits (used by wrapped HOSTCC)
    pkgs.glibc.dev
    pkgs.linuxHeaders

    pkgs.rsync

    # comfort food
    pkgs.starship
    pkgs.eza
  ];

  shellHook = (o.shellHook or "") + ''
    export NIX_ENFORCE_NO_NATIVE=0

    # --- Toolchain split ---
    # Kernel compilation: unwrapped clang (avoid nix cc-wrapper injecting weirdness)
    export CC=${pkgs.llvmPackages.clang-unwrapped}/bin/clang
    export CXX=${pkgs.llvmPackages.clang-unwrapped}/bin/clang++

    # Host tools: wrapped cc/c++ so libc headers + sysroot "just work"
    export HOSTCC=${pkgs.stdenv.cc}/bin/cc
    export HOSTCXX=${pkgs.stdenv.cc}/bin/c++

    # Kernel LLVM mode
    export LLVM=1
    export LLVM_IAS=1

    # Binutils equivalents (kernel side)
    export LD=${pkgs.llvmPackages.lld}/bin/ld.lld
    export AR=${pkgs.llvmPackages.llvm}/bin/llvm-ar
    export NM=${pkgs.llvmPackages.llvm}/bin/llvm-nm
    export OBJCOPY=${pkgs.llvmPackages.llvm}/bin/llvm-objcopy
    export OBJDUMP=${pkgs.llvmPackages.llvm}/bin/llvm-objdump
    export STRIP=${pkgs.llvmPackages.llvm}/bin/llvm-strip
    export READELF=${pkgs.llvmPackages.llvm}/bin/llvm-readelf

    # Nix + kbuild + clang noise suppression (kernel side only)
    export KCFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"
    export KAFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"

    # --- Helpers ---
    kclean() {
      # Clean in-tree artifacts (not O=), preserve .config if present.
      local cfg=""
      if [ -f .config ]; then
        cfg="$(mktemp -p . .config.saved.XXXXXX)"
        cp -f .config "$cfg"
      fi

      make mrproper

      if [ -n "$cfg" ] && [ -f "$cfg" ]; then
        cp -f "$cfg" .config
        rm -f "$cfg"
      fi
    }

    # --- Helper commands ---
    khost() {
      # Build host-side tools (fixdep, modpost, etc.) using wrapped HOSTCC.
      make -j"$(nproc)" V=1 \
        HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" \
        scripts_basic scripts/mod
    }

    kkernel() {
      # Build kernel+modules using clang-unwrapped for CC, wrapped HOSTCC for host tools.
      make -j"$(nproc)" V=1 \
        CC="$CC" CXX="$CXX" \
        HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" \
        LLVM=1 LLVM_IAS=1 \
        bzImage modules
    }

    # quick sanity check (run manually if you want)
    kenv() {
      echo "CC=$CC"
      echo "HOSTCC=$HOSTCC"
      echo "CXX=$CXX"
      echo "HOSTCXX=$HOSTCXX"
      type -a "$HOSTCC" || true
      type -a "$CC" || true
    }

    lh() { eza --group --header --group-directories-first --long --icons --git --all --binary --dereference --links "$@"; }
    eval "$(starship init bash)"
  '';
})
