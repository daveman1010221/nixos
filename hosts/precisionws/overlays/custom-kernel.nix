{ myConfig, myPubCert, myPrivKey, ... }:

final: prev:
let
  opt = attrs: name:
    if builtins.hasAttr name attrs then
      let v = attrs.${name}; in if v == null then "" else v
    else
      "";

  # 1) Build the base kernelPackages set (your kernel override unchanged)
  hardenedBase =
    prev.linuxPackagesFor
      (prev.linuxKernel.kernels.linux_6_17.overrideAttrs (old: {
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

        buildPhase = ''
          mkdir -p tmp_certs
          cp ${myConfig} tmp_certs/.config
          cp ${myPubCert} tmp_certs/MOK.pem
          cp ${myPrivKey} tmp_certs/MOK.priv

          ls -lah tmp_certs

          cp tmp_certs/.config .config
          cp tmp_certs/MOK.pem MOK.pem
          cp tmp_certs/MOK.priv MOK.priv

          ls -alh

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
          echo "Using OpenSSL from: $(which openssl)"
          openssl version

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

          cp .config $dev/lib/modules/$version/source/.config
          if [ -f Module.symvers ]; then
            cp Module.symvers $dev/lib/modules/$version/source/Module.symvers
          fi
          if [ -f System.map ]; then
            cp System.map $dev/lib/modules/$version/source/System.map
          fi
          if [ -d include ]; then
            mkdir -p $dev/lib/modules/$version/source
            cp -r include $dev/lib/modules/$version/source/
          fi

          make O=. clean mrproper

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

  # 2) Override inside the kernelPackages fixpoint
  clang   = "${prev.llvmPackages.clang-unwrapped}/bin/clang";
  clangpp = "${prev.llvmPackages.clang-unwrapped}/bin/clang++";
  lld     = "${prev.llvmPackages.lld}/bin/ld.lld";
  llvmAr  = "${prev.llvmPackages.llvm}/bin/llvm-ar";
  llvmNm  = "${prev.llvmPackages.llvm}/bin/llvm-nm";

  lib = prev.lib;


  # nvidia-open (this drv) is not stdenv-phased: phases/preBuild/buildPhase are null.
  # So the only reliable lever is makeFlags (which is a *string* here).
  #
  # Pull specific key=value tokens out of the existing makeFlags string so we don't
  # break kernel wiring (SYSSRC/SYSOUT/KBUILD_OUTPUT/MODLIB/etc).
  grabMakeFlag = mf: key:
    let
      s =
        if mf == null then ""
        else if builtins.isString mf then mf
        else lib.concatStringsSep " " (normalizeMakeFlags mf);
      # Nix regex doesn't support \b. Use (^|[[:space:]]) as a safe token boundary.
      # Capture group 1 is the VALUE (no spaces).
      m = builtins.match (".*(^|[[:space:]])" + key + "=([^[:space:]]+).*") s;
    in
      if m == null then null else builtins.elemAt m 1;

  # nvidia-open's makeFlags often comes through as a *string* in drv env.
  # Normalize to a list so we can filter/replace entries sanely.
  normalizeMakeFlags = mf:
    if mf == null then []
    else if builtins.isList mf then mf
    else if builtins.isString mf then lib.filter (x: x != "") (lib.splitString " " mf)
    else [];

  stripToolFlags = flags:
    let
      fs = normalizeMakeFlags flags;
      bad = [
        "CC=" "CXX=" "HOSTCC=" "HOSTCXX="
        "LD=" "AR=" "NM=" "STRIP="
        "OBJCOPY=" "OBJDUMP=" "READELF="
        "HOSTAR=" "HOSTLD="
      ];
      isBad = f: lib.any (p: lib.hasPrefix p f) bad;
    in
      lib.filter (f: !(isBad f)) fs;

  overrideNvidiaOpen = pkg: pkg.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
      prev.llvmPackages.clang-unwrapped
      prev.llvmPackages.lld
      prev.llvmPackages.llvm
      prev.xz
      prev.hostname
    ];

    # NOTE: preBuild does not run for this drv (phases are null). Keep code around
    # for future but don't rely on it.

    # Replace makeFlags as a *string* (this drv stores it as a string), and preserve
    # important kernel wiring from the original makeFlags string.
    makeFlags =
      let
        mf     = old.makeFlags;
        arch   = grabMakeFlag mf "ARCH";
        target = grabMakeFlag mf "TARGET_ARCH";
        kbuild = grabMakeFlag mf "KBUILD_OUTPUT";
        syssrc = grabMakeFlag mf "SYSSRC";
        sysout = grabMakeFlag mf "SYSOUT";
        modlib = grabMakeFlag mf "MODLIB";
      in
        lib.concatStringsSep " " (lib.filter (x: x != null) [
          # Make the build *tell the truth* in logs.
          "V=1"
          "KBUILD_VERBOSE=1"
          # Proof this override is actually in the drv env.
          # (shows up via: nix derivation show ... | jq -r '.[].env.makeFlags')
          "DAVE_PROOF_OPEN=1"

          # Force LLVM toolchain.
          "LLVM=1"
          "LLVM_IAS=1"
          "CC=${clang}"
          "CXX=${clangpp}"
          "HOSTCC=${clang}"
          "HOSTCXX=${clangpp}"
          "LD=${lld}"
          "AR=${llvmAr}"
          "NM=${llvmNm}"
          "IGNORE_CC_MISMATCH=1"

          # Preserve kernel wiring that the nvidia-open builder depends on.
          (if arch   != null then "ARCH=${arch}" else null)
          (if target != null then "TARGET_ARCH=${target}" else null)
          (if kbuild != null then "KBUILD_OUTPUT=${kbuild}" else null)
          (if syssrc != null then "SYSSRC=${syssrc}" else null)
          (if sysout != null then "SYSOUT=${sysout}" else null)
          (if modlib != null then "MODLIB=${modlib}" else null)

          # Keep these as the upstream builder expects them.
          "CROSS_COMPILE="
          "IGNORE_PREEMPT_RT_PRESENCE=1"
        ]);

    # Don't set NIX_CC; it's not a drv env var used the way people wish it was.
  });

  hardened =
    hardenedBase.extend (selfKP: superKP:
      let
        inherit (prev) lib;
        # Keep your beta override (this is the one you already proved hits nvidia-x11)
        nvidiaBeta =
          superKP.nvidiaPackages.beta.overrideAttrs (old:
            let
              kdev = old.kernel;
              ksrc = "${kdev}/lib/modules/${old.kernelVersion}/source";
              kout = "${kdev}/lib/modules/${old.kernelVersion}/build";
            in {
              nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
                prev.llvmPackages.clang-unwrapped
                prev.llvmPackages.lld
                prev.xz
              ];

              makeFlags = [
                "CC=${clang}"
                "CXX=${clangpp}"
                "HOSTCC=${clang}"
                "HOSTCXX=${clangpp}"
                "LD=${lld}"
                "IGNORE_CC_MISMATCH=1"
                "SYSSRC=${ksrc}"
                "SYSOUT=${kout}"
                "KERNEL_SOURCES=${ksrc}"
                "KERNEL_OUTPUT=${kout}"
              ];

              preBuild = (opt old "preBuild") + ''
                echo "🚨 NVIDIA OVERRIDE HIT (preBuild) 🚨"
                echo "CC=$CC"
                echo "CXX=$CXX"
                echo "HOSTCC=$HOSTCC"
                echo "HOSTCXX=$HOSTCXX"
                echo "LD=$LD"
                echo "makeFlags=$makeFlags"
                echo "ksrc=${ksrc}"
                echo "kout=${kout}"
                test -e "${ksrc}/Makefile" || (echo "❌ ksrc missing Makefile"; exit 1)
                test -e "${kout}/Makefile" || (echo "❌ kout missing Makefile"; exit 1)
              '';

              postInstall = (opt old "postInstall") + ''
                set -euo pipefail

                # 🚫 DO NOT reference `hardened` here (infinite recursion).
                # Use the kernel dev output we already have (`kdev`).
                SIGN_FILE="${ksrc}/scripts/sign-file"
                MOK_CERT="${ksrc}/MOK.pem"
                MOK_KEY="${ksrc}/MOK.priv"

                echo "🚨 NVIDIA OVERLAY IS RUNNING (postInstall signing) 🚨"
                echo "SIGN_FILE=$SIGN_FILE"

                if [ ! -x "$SIGN_FILE" ]; then
                  echo "❌ sign-file tool not found at $SIGN_FILE"
                  exit 1
                fi

                if [ -d "$out/lib/modules" ]; then
                  for mod in $(find "$out/lib/modules" -type f -name '*.ko'); do
                    echo "🔹 Signing module: $mod"
                    "$SIGN_FILE" sha256 "$MOK_KEY" "$MOK_CERT" "$mod"
                  done

                  for modxz in $(find "$out/lib/modules" -type f -name '*.ko.xz'); do
                    echo "🔹 Decompress/sign/recompress: $modxz"
                    xz -d -f "$modxz"
                    mod="''${modxz%.xz}"
                    "$SIGN_FILE" sha256 "$MOK_KEY" "$MOK_CERT" "$mod"
                    xz -z -f "$mod"
                  done
                else
                  echo "⚠️ No $out/lib/modules directory found; nothing to sign"
                fi
              '';
            });

        # Override the open modules where NixOS actually wires them:
        # boot.kernelPackages.nvidiaPackages.open (plus a couple of common variant names).
        openOverrides =
          (lib.optionalAttrs (superKP.nvidiaPackages ? open) {
            open = overrideNvidiaOpen superKP.nvidiaPackages.open;
          }) //
          (lib.optionalAttrs (superKP.nvidiaPackages ? openKernel) {
            openKernel = overrideNvidiaOpen superKP.nvidiaPackages.openKernel;
          }) //
          (lib.optionalAttrs (superKP.nvidiaPackages ? openModules) {
            openModules = overrideNvidiaOpen superKP.nvidiaPackages.openModules;
          });
      in
      {
        # Single definition of nvidiaPackages, with all overrides merged in one place.
        nvidiaPackages = superKP.nvidiaPackages // openOverrides // {
          beta = nvidiaBeta;
        };

        # ✅ On your system these attrs *evaluate directly to the nvidia-open drv*:
        #   - nvidia_x11_beta_open     -> /nix/store/...-nvidia-open-...590...
        #   - nvidia_x11_latest_open   -> /nix/store/...-nvidia-open-...580...
        #   - nvidia_x11_production_open -> same 580 drv
        #
        # So override them directly (this is the splice point you verified with nix eval).
        nvidia_x11_beta_open       = overrideNvidiaOpen superKP.nvidia_x11_beta_open;
        nvidia_x11_latest_open     = overrideNvidiaOpen superKP.nvidia_x11_latest_open;
        nvidia_x11_production_open = overrideNvidiaOpen superKP.nvidia_x11_production_open;
      }
    );
in
{
  hardened_linux_kernel = hardened;
}
