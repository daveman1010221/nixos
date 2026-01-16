{ myConfig, myPubCert, myPrivKey, ... }:

final: prev:
let
  lib = prev.lib;

  # 1) Your custom clang-built 6.18 kernelPackages (UNCHANGED)
  hardenedBase =
    prev.linuxPackagesFor
      (prev.linuxKernel.kernels.linux_6_18.overrideAttrs (old: {
        dontConfigure = true;

        nativeBuildInputs =
          (old.nativeBuildInputs or [])
          ++ [
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

        # --- your buildPhase exactly as before ---
        buildPhase = ''
          mkdir -p tmp_certs
          cp ${myConfig} tmp_certs/.config
          cp ${myPubCert} tmp_certs/MOK.pem
          cp ${myPrivKey} tmp_certs/MOK.priv

          cp tmp_certs/.config .config
          cp tmp_certs/MOK.pem MOK.pem
          cp tmp_certs/MOK.priv MOK.priv

          export LLVM=1
          export LLVM_IAS=1

          export CC=${prev.llvmPackages.clang-unwrapped}/bin/clang
          export CXX=${prev.llvmPackages.clang-unwrapped}/bin/clang++

          export LD=${prev.llvmPackages.lld}/bin/ld.lld
          export AR=${prev.llvmPackages.llvm}/bin/llvm-ar
          export NM=${prev.llvmPackages.llvm}/bin/llvm-nm
          export OBJCOPY=${prev.llvmPackages.llvm}/bin/llvm-objcopy
          export OBJDUMP=${prev.llvmPackages.llvm}/bin/llvm-objdump
          export STRIP=${prev.llvmPackages.llvm}/bin/llvm-strip
          export READELF=${prev.llvmPackages.llvm}/bin/llvm-readelf

          export KCFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"
          export KAFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"

          make \
            ARCH=${prev.stdenv.hostPlatform.linuxArch} \
            CROSS_COMPILE= \
            KBUILD_BUILD_VERSION=1-NixOS \
            O=. \
            SHELL=${prev.bash}/bin/bash \
            LLVM=1 LLVM_IAS=1 \
            CC="$CC" CXX="$CXX" \
            HOSTCC=${prev.stdenv.cc}/bin/cc \
            HOSTCXX=${prev.stdenv.cc}/bin/c++ \
            LD="$LD" AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" READELF="$READELF" \
            -j$NIX_BUILD_CORES \
            bzImage modules
        '';

        installPhase = ''
          export PATH=${prev.openssl}/bin:$PATH

          export LLVM=1
          export LLVM_IAS=1

          export CC=${prev.llvmPackages.clang-unwrapped}/bin/clang
          export CXX=${prev.llvmPackages.clang-unwrapped}/bin/clang++

          export LD=${prev.llvmPackages.lld}/bin/ld.lld
          export AR=${prev.llvmPackages.llvm}/bin/llvm-ar
          export NM=${prev.llvmPackages.llvm}/bin/llvm-nm
          export OBJCOPY=${prev.llvmPackages.llvm}/bin/llvm-objcopy
          export OBJDUMP=${prev.llvmPackages.llvm}/bin/llvm-objdump
          export STRIP=${prev.llvmPackages.llvm}/bin/llvm-strip
          export READELF=${prev.llvmPackages.llvm}/bin/llvm-readelf

          export KCFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"
          export KAFLAGS="-Qunused-arguments -Wno-error=unused-command-line-argument -Wno-unused-command-line-argument"

          mkdir -p $out
          mkdir -p $dev

          make \
            O=. \
            LLVM=1 LLVM_IAS=1 \
            CC="$CC" CXX="$CXX" \
            HOSTCC=${prev.stdenv.cc}/bin/cc \
            HOSTCXX=${prev.stdenv.cc}/bin/c++ \
            LD="$LD" AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" READELF="$READELF" \
            INSTALL_PATH=$out \
            INSTALL_MOD_PATH=$out \
            INSTALL_HDR_PATH=$dev \
            -j$NIX_BUILD_CORES \
            headers_install modules_install

          cp arch/x86/boot/bzImage System.map $out/

          version=$(make \
            O=. \
            LLVM=1 LLVM_IAS=1 \
            CC="$CC" CXX="$CXX" \
            HOSTCC=${prev.stdenv.cc}/bin/cc \
            HOSTCXX=${prev.stdenv.cc}/bin/c++ \
            LD="$LD" AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" READELF="$READELF" \
            kernelrelease)

          mkdir -p $dev/lib/modules/$version/source
          cp -a . $dev/lib/modules/$version/source

          cd $dev/lib/modules/$version/source
          make \
            O=$dev/lib/modules/$version/source \
            LLVM=1 LLVM_IAS=1 \
            CC="$CC" CXX="$CXX" \
            HOSTCC=${prev.stdenv.cc}/bin/cc \
            HOSTCXX=${prev.stdenv.cc}/bin/c++ \
            LD="$LD" AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" STRIP="$STRIP" READELF="$READELF" \
            -j$NIX_BUILD_CORES \
            prepare modules_prepare

          ln -s $dev/lib/modules/$version/source \
            $dev/lib/modules/$version/build
        '';

        outputs = [ "out" "dev" ];
      }));

  # Keep kernelPackages clean; extend later only if needed
  hardened =
    hardenedBase.extend (selfKP: superKP: {});
in
{
  hardened_linux_kernel = hardened;
}
