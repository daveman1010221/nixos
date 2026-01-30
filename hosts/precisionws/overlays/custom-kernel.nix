{ myConfig, mokPemPath, mokPrivPath, ... }:

final: prev:
let
  lib = prev.lib;

  hardenedBase =
    prev.linuxPackagesFor
      (prev.linuxKernel.kernels.linux_6_18.overrideAttrs (old: {
        dontConfigure = true;

        # Allow this derivation to read host-resident key material at build time
        __impureHostDeps = (old.__impureHostDeps or []) ++ [
          "/boot/secrets"
        ];

        nativeBuildInputs =
          (old.nativeBuildInputs or [])
          ++ [
	    prev.rsync
            prev.kmod
            prev.openssl
            prev.hostname
            prev.qboot

            prev.pkg-config
            prev.ncurses
            prev.bison
            prev.flex
            prev.bc
            prev.pahole

            prev.llvmPackages.clang-unwrapped
            prev.llvmPackages.lld
            prev.llvmPackages.llvm
            prev.llvmPackages.bintools

            prev.glibc.dev
            prev.linuxHeaders
          ];

        buildInputs =
          (old.buildInputs or [])
          ++ [
            prev.kmod
            prev.openssl
            prev.hostname
          ];

        buildPhase = ''
          set -euo pipefail

          # Keep stdenv flags from poisoning kbuild (match manual flow)
          unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS || true

          SRCTREE="$PWD"
          O="$PWD/.o"
	  mkdir -p "$O" "$O/certs"

          # --- Tooling (match manual contract) ---
          export LLVM=1
          export LLVM_IAS=1

          export CC=${prev.llvmPackages.clang-unwrapped}/bin/clang
          export CXX=${prev.llvmPackages.clang-unwrapped}/bin/clang++

          export HOSTCC=${prev.stdenv.cc}/bin/cc
          export HOSTCXX=${prev.stdenv.cc}/bin/c++
          export HOSTLD=${prev.stdenv.cc.bintools}/bin/ld

          export LD=${prev.llvmPackages.lld}/bin/ld.lld
          export AR=${prev.llvmPackages.llvm}/bin/llvm-ar
          export NM=${prev.llvmPackages.llvm}/bin/llvm-nm
          export OBJCOPY=${prev.llvmPackages.llvm}/bin/llvm-objcopy
          export OBJDUMP=${prev.llvmPackages.llvm}/bin/llvm-objdump
          export STRIP=${prev.llvmPackages.llvm}/bin/llvm-strip
          export READELF=${prev.llvmPackages.llvm}/bin/llvm-readelf

          export KCFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"
          export KAFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"

          # Make sure /bin/sh assumptions don’t explode in the sandbox.
          export SHELL=${prev.bash}/bin/bash
          export CONFIG_SHELL=${prev.bash}/bin/bash

          # --- Seed config into objtree (manual kseed equivalent) ---
          install -m 0644 ${myConfig} "$O/.config"

          # --- MOK fanout (manual kmok_prepare equivalent) ---
          fanout() {
            local mode="$1"; local src="$2"; shift 2
            for dst in "$@"; do
              install -m "$mode" -D "$src" "$dst"
            done
          }

          # Public cert can be 0644 in build trees
          fanout 0644 ${mokPemPath} \
            "$O/MOK.pem" \
            "$O/certs/MOK.pem"

          # Private key: keep restricted
          fanout 0600 ${mokPrivPath} \
            "$O/MOK.priv" \
            "$O/certs/MOK.priv"

          kmake() {
            make -C "$SRCTREE" \
              ARCH=${prev.stdenv.hostPlatform.linuxArch} \
              O="$O" \
              SHELL="$SHELL" CONFIG_SHELL="$CONFIG_SHELL" \
              LLVM=1 LLVM_IAS=1 \
              CC="$CC" CXX="$CXX" LD="$LD" \
              AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" READELF="$READELF" \
              HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" \
              KCFLAGS="$KCFLAGS" KAFLAGS="$KAFLAGS" \
              "$@"
          }

          # Ensure syncconfig is non-interactive inside nix builds:
          # olddefconfig preserves existing choices; fills only new symbols with defaults.
          kmake olddefconfig

          kmake -j$NIX_BUILD_CORES --output-sync=recurse V=1 \
            CROSS_COMPILE= \
            KBUILD_BUILD_VERSION=1-NixOS \
            bzImage modules
        '';

        installPhase = ''
          set -euo pipefail

          export MAKEFLAGS="''${MAKEFLAGS:-} --no-print-directory"

          export PATH=${prev.openssl}/bin:$PATH

          unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS || true

          SRCTREE="$PWD"
          O="$PWD/.o"

          export LLVM=1
          export LLVM_IAS=1

          export CC=${prev.llvmPackages.clang-unwrapped}/bin/clang
          export CXX=${prev.llvmPackages.clang-unwrapped}/bin/clang++

          export HOSTCC=${prev.stdenv.cc}/bin/cc
          export HOSTCXX=${prev.stdenv.cc}/bin/c++
          export HOSTLD=${prev.stdenv.cc.bintools}/bin/ld

          export LD=${prev.llvmPackages.lld}/bin/ld.lld
          export AR=${prev.llvmPackages.llvm}/bin/llvm-ar
          export NM=${prev.llvmPackages.llvm}/bin/llvm-nm
          export OBJCOPY=${prev.llvmPackages.llvm}/bin/llvm-objcopy
          export OBJDUMP=${prev.llvmPackages.llvm}/bin/llvm-objdump
          export STRIP=${prev.llvmPackages.llvm}/bin/llvm-strip
          export READELF=${prev.llvmPackages.llvm}/bin/llvm-readelf

          export KCFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"
          export KAFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"

          export SHELL=${prev.bash}/bin/bash
          export CONFIG_SHELL=${prev.bash}/bin/bash

          mkdir -p $out $dev

          kmake() {
            make -C "$SRCTREE" \
              O="$O" \
              SHELL="$SHELL" CONFIG_SHELL="$CONFIG_SHELL" \
              LLVM=1 LLVM_IAS=1 \
              CC="$CC" CXX="$CXX" LD="$LD" \
              AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" READELF="$READELF" \
              HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" \
              KCFLAGS="$KCFLAGS" KAFLAGS="$KAFLAGS" \
              "$@"
          }

          # Prevent "make: Entering directory ..." from contaminating captured output.
          # Also makes logs less insane.
          export MAKEFLAGS="''${MAKEFLAGS:-} --no-print-directory"

          kmake -j$NIX_BUILD_CORES \
            INSTALL_PATH=$out \
            INSTALL_MOD_PATH=$out \
            INSTALL_HDR_PATH=$dev \
            headers_install modules_install

          cp "$O/arch/x86/boot/bzImage" "$O/System.map" $out/

          version=$(kmake -s kernelrelease)

          # Absolute hard rule: do NOT let signing material land in outputs.
          rm -f "$O/MOK.pem" "$O/MOK.priv" "$O/certs/MOK.pem" "$O/certs/MOK.priv" || true

          # Nix-standard external module build layout:
          #   /lib/modules/$ver/source -> SRCTREE (no objtree junk, no secrets)
          #   /lib/modules/$ver/build  -> prepared objtree
          #
          mkdir -p $dev/lib/modules/$version/source $dev/lib/modules/$version/build

          # 1) Source tree (exclude objtree + any signing material)
          rsync -a \
            --exclude '/.o/' \
            --exclude '/MOK.pem' \
            --exclude '/MOK.priv' \
            --exclude '/certs/MOK.pem' \
            --exclude '/certs/MOK.priv' \
            ./ \
            $dev/lib/modules/$version/source/

          # 2) Build tree: copy the prepared objtree, excluding any signing material
          rsync -a \
            --exclude '/MOK.pem' \
            --exclude '/MOK.priv' \
            --exclude '/certs/MOK.pem' \
            --exclude '/certs/MOK.priv' \
            "$O"/ \
            $dev/lib/modules/$version/build/

          # 3) Ensure the build dir is properly prepared for out-of-tree modules.
          make -C $dev/lib/modules/$version/source -s \
            O=$dev/lib/modules/$version/build \
            SHELL="$SHELL" CONFIG_SHELL="$CONFIG_SHELL" \
            LLVM=1 LLVM_IAS=1 \
            CC="$CC" CXX="$CXX" LD="$LD" \
            AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" READELF="$READELF" \
            HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" HOSTLD="$HOSTLD" \
            KCFLAGS="$KCFLAGS" KAFLAGS="$KAFLAGS" \
            -j$NIX_BUILD_CORES \
            prepare modules_prepare
        '';

        outputs = [ "out" "dev" ];
      }));

  hardened = hardenedBase.extend (selfKP: superKP: {});
in
{
  hardened_linux_kernel = hardened;
}
