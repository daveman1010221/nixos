{ myConfig, mokPemPath, mokPrivPath, ... }:

final: prev:
let
  lib = prev.lib;

  clang   = "${prev.llvmPackages.clang-unwrapped}/bin/clang";
  clangpp = "${prev.llvmPackages.clang-unwrapped}/bin/clang++";
  lld     = "${prev.llvmPackages.lld}/bin/ld.lld";
  llvmAr  = "${prev.llvmPackages.llvm}/bin/llvm-ar";
  llvmNm  = "${prev.llvmPackages.llvm}/bin/llvm-nm";

  normalizeMakeFlags = mf:
    if mf == null then []
    else if builtins.isList mf then mf
    else if builtins.isString mf then lib.filter (x: x != "") (lib.splitString " " mf)
    else [];

  grabMakeFlag = mf: key:
    let
      s = lib.concatStringsSep " " (normalizeMakeFlags mf);
      m = builtins.match (".*(^|[[:space:]])" + key + "=([^[:space:]]+).*") s;
    in
      if m == null then null else builtins.elemAt m 1;

  stripToolFlags = flags:
    let
      fs  = normalizeMakeFlags flags;
      bad = [
        "CC=" "CXX=" "HOSTCC=" "HOSTCXX=" "LD=" "AR=" "NM=" "STRIP="
        "OBJCOPY=" "OBJDUMP=" "READELF=" "HOSTAR=" "HOSTLD="
      ];
      isBad = f: lib.any (p: lib.hasPrefix p f) bad;
    in
      lib.filter (f: !(isBad f)) fs;

  # Shared preBuild toolchain rewrite.
  # Rewrites gcc paths in $makeFlags to clang at build time.
  # Done at build time (not eval time) because the gcc store paths are
  # dynamic and cannot be predicted in the Nix expression.
  mkPreBuild = old: ''
      echo "Rewriting makeFlags to use clang toolchain..."
      makeFlags="$(echo "$makeFlags" | \
        sed 's|CC=[^ ]*|CC=${clang}|g' | \
        sed 's|CXX=[^ ]*|CXX=${clangpp}|g' | \
        sed 's|HOSTCC=[^ ]*|HOSTCC=${clang}|g' | \
        sed 's|HOSTCXX=[^ ]*|HOSTCXX=${clangpp}|g' | \
        sed 's|LD=[^ ]*|LD=${lld}|g' | \
        sed 's|AR=[^ ]*|AR=${llvmAr}|g' | \
        sed 's|NM=[^ ]*|NM=${llvmNm}|g')"
  
      # Exclude nvidia-modeset, nvidia-drm, and nvidia-peermem from the build.
      # These modules are only needed for display output from the nvidia card.
      # We use the Intel/Xe driver for display; nvidia is only needed for compute.
      # Excluding these also avoids CFI compatibility issues with nvidia-modeset's
      # C++ source files which cannot be compiled with clang's kcfi sanitizer flags.
      # Export as environment variable — make reads it without quoting issues
      export NV_EXCLUDE_KERNEL_MODULES="nvidia-modeset nvidia-drm nvidia-peermem"
      echo "NV_EXCLUDE_KERNEL_MODULES=$NV_EXCLUDE_KERNEL_MODULES"
    '';

  # Applied to nvidia-open derivations.
  #
  # nvidia-open builds the open kernel modules. We:
  #   1) Rewrite toolchain in makeFlags to use clang (mkPreBuild)
  #   2) Rewrite kernel paths in makeFlags to use our custom kernel
  #   3) Sign the resulting .ko files with our MOK key
  overrideNvidiaOpen = pkg: pkg.overrideAttrs (old:
    let
      kdev    = old.kernel or null;
      version = old.kernelVersion or null;
      kout    = if kdev != null && version != null
                then "${kdev}/lib/modules/${version}/build"
                else null;
    in {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        prev.llvmPackages.clang-unwrapped
        prev.llvmPackages.lld
        prev.llvmPackages.llvm
        prev.xz
        prev.hostname
      ];

      preBuild =
        (lib.optionalString (old ? preBuild && old.preBuild != null) old.preBuild)
        + (mkPreBuild old);

      postInstall =
        (lib.optionalString (old ? postInstall && old.postInstall != null) old.postInstall)
        + lib.optionalString (kout != null) ''
            (
              set -euo pipefail

              SIGN_FILE="${kout}/scripts/sign-file"
              MOK_CERT="${mokPemPath}"
              MOK_KEY="${mokPrivPath}"

              if [ ! -x "$SIGN_FILE" ]; then
                echo "sign-file not found at $SIGN_FILE" >&2
                exit 1
              fi

              if [ ! -f "$MOK_CERT" ] || [ ! -f "$MOK_KEY" ]; then
                echo "MOK material missing: $MOK_CERT / $MOK_KEY" >&2
                exit 1
              fi

              if [ -d "$out/lib/modules" ]; then
                find "$out/lib/modules" -type f -name '*.ko' | while read -r mod; do
                  echo "Signing: $mod"
                  "$SIGN_FILE" sha256 "$MOK_KEY" "$MOK_CERT" "$mod"
                done

                find "$out/lib/modules" -type f -name '*.ko.xz' | while read -r modxz; do
                  echo "Decompress/sign/recompress: $modxz"
                  xz -d -f "$modxz"
                  mod="''${modxz%.xz}"
                  "$SIGN_FILE" sha256 "$MOK_KEY" "$MOK_CERT" "$mod"
                  xz -z -f "$mod"
                done
              else
                echo "Warning: no $out/lib/modules found, nothing to sign" >&2
              fi
            )
          '';
    });

  # Applied to nvidia-x11 derivations.
  #
  # nvidia-x11 is the full driver package: userspace libraries, X drivers,
  # firmware, utilities, AND closed kernel modules. We want everything except
  # the closed kernel modules — GPL-incompatible, rejected by modpost on a
  # kernel with strict GPL symbol enforcement.
  #
  # We override buildPhase entirely to skip the make module step while
  # leaving $bin intact for installPhase and fixupPhase. We cannot unset
  # $bin because stdenv's fixupPhase uses ${!output} (bash indirect
  # expansion) over all output names — unsetting $bin causes those hooks
  # to fail with "parameter null or not set".
  overrideNvidiaX11 = pkg: pkg.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
      prev.llvmPackages.clang-unwrapped
      prev.llvmPackages.lld
      prev.llvmPackages.llvm
      prev.xz
      prev.hostname
    ];

    preBuild =
      (lib.optionalString (old ? preBuild && old.preBuild != null) old.preBuild)
      + (mkPreBuild old);

    # Skip the closed kernel module build entirely.
    # Open modules come from nvidia-open (hardware.nvidia.open = true).
    buildPhase = ''
      runHook preBuild
      # Closed kernel modules intentionally not built.
      # Open kernel modules come from nvidia-open (hardware.nvidia.open = true).
      runHook postBuild
    '';

    # Disable systemd user units migration hook. nvidia-x11 does not install
    # systemd user units but the hook runs anyway and fails because $prefix
    # is unset during lib32 output processing in our override chain.
    dontMoveSystemdUserUnits = "1";
  });

  hardenedBase =
    prev.linuxPackagesFor
      (prev.linuxKernel.kernels.linux_6_19.overrideAttrs (old: {
        dontConfigure = true;

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

          unset NIX_LDFLAGS NIX_CFLAGS_LINK NIX_CFLAGS_COMPILE LDFLAGS CFLAGS CXXFLAGS CPPFLAGS || true

          SRCTREE="$PWD"
          O="$PWD/.o"
          mkdir -p "$O" "$O/certs"

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

          install -m 0644 ${myConfig} "$O/.config"

          fanout() {
            local mode="$1"; local src="$2"; shift 2
            for dst in "$@"; do
              install -m "$mode" -D "$src" "$dst"
            done
          }

          fanout 0644 ${mokPemPath} \
            "$O/MOK.pem" \
            "$O/certs/MOK.pem"

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

          kmake -j$NIX_BUILD_CORES \
            INSTALL_PATH=$out \
            INSTALL_MOD_PATH=$out \
            INSTALL_HDR_PATH=$dev \
            headers_install modules_install

          cp "$O/arch/x86/boot/bzImage" "$O/System.map" $out/

          version=$(kmake -s kernelrelease)

          rm -f "$O/MOK.pem" "$O/MOK.priv" "$O/certs/MOK.pem" "$O/certs/MOK.priv" || true

          mkdir -p $dev/lib/modules/$version/source $dev/lib/modules/$version/build

          rsync -a \
            --exclude '/.o/' \
            --exclude '/MOK.pem' \
            --exclude '/MOK.priv' \
            --exclude '/certs/MOK.pem' \
            --exclude '/certs/MOK.priv' \
            ./ \
            $dev/lib/modules/$version/source/

          rsync -a \
            --exclude '/MOK.pem' \
            --exclude '/MOK.priv' \
            --exclude '/certs/MOK.pem' \
            --exclude '/certs/MOK.priv' \
            "$O"/ \
            $dev/lib/modules/$version/build/

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

  hardened =
      hardenedBase.extend (selfKP: superKP:
        let
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
  
      overrideFullPackage = origPkg:
        let
          customKernelDev = selfKP.kernel.dev;
          modDirVersion   = selfKP.kernel.modDirVersion;
          mf = origPkg.open.makeFlags;
          mfStr = if builtins.isList mf
                  then lib.concatStringsSep " " mf
                  else mf;
          mfClean = builtins.unsafeDiscardStringContext mfStr;
          oldSyssrc = let m = builtins.match ".*SYSSRC=([^ ]+).*" mfClean;
                      in if m == null then "~~NOSYSSRC~~" else builtins.head m;
          oldSysout = let m = builtins.match ".*SYSOUT=([^ ]+).*" mfClean;
                      in if m == null then "~~NOSYSOUT~~" else builtins.head m;
          oldKbuild = let m = builtins.match ".*KBUILD_OUTPUT=([^ ]+).*" mfClean;
                      in if m == null then "~~NOKBUILD~~" else builtins.head m;
          newMf = builtins.replaceStrings
            [ "SYSSRC=${oldSyssrc}" "SYSOUT=${oldSysout}" "KBUILD_OUTPUT=${oldKbuild}" ]
            [ "SYSSRC=${customKernelDev}/lib/modules/${modDirVersion}/source"
              "SYSOUT=${customKernelDev}/lib/modules/${modDirVersion}/build"
              "KBUILD_OUTPUT=${customKernelDev}/lib/modules/${modDirVersion}/build"
            ]
            mfClean;
            overriddenOpen = (overrideNvidiaOpen (origPkg.open.overrideAttrs (_: {
              makeFlags = newMf;
            }))).overrideAttrs (old: {
              __impureHostDeps = (old.__impureHostDeps or []) ++ [ "/boot/secrets" ];

              postInstall = (lib.optionalString (old ? postInstall && old.postInstall != null) old.postInstall) + ''
                (
                  set -euo pipefail

                  SIGN_FILE="${customKernelDev}/lib/modules/${modDirVersion}/build/scripts/sign-file"
                  MOK_CERT="${mokPemPath}"
                  MOK_KEY="${mokPrivPath}"

                  if [ ! -x "$SIGN_FILE" ]; then
                    echo "sign-file not found at $SIGN_FILE" >&2
                    exit 1
                  fi

                  if [ ! -f "$MOK_CERT" ] || [ ! -f "$MOK_KEY" ]; then
                    echo "MOK material missing: $MOK_CERT / $MOK_KEY" >&2
                    exit 1
                  fi

                  if [ -d "$out/lib/modules" ]; then
                    find "$out/lib/modules" -type f -name '*.ko' | while read -r mod; do
                      echo "Signing with MOK: $mod"
                      "$SIGN_FILE" sha256 "$MOK_KEY" "$MOK_CERT" "$mod"
                    done

                    find "$out/lib/modules" -type f -name '*.ko.xz' | while read -r modxz; do
                      echo "Decompress/sign/recompress: $modxz"
                      xz -d -f "$modxz"
                      mod="''${modxz%.xz}"
                      "$SIGN_FILE" sha256 "$MOK_KEY" "$MOK_CERT" "$mod"
                      xz -z -f "$mod"
                    done
                  fi
                )
              '';
            });
        in
          (overrideNvidiaX11 origPkg).overrideAttrs (old: {
            open = overriddenOpen;
            passthru = (old.passthru or {}) // {
              open = overriddenOpen;
            };
          });
        in
        {
          nvidiaPackages = superKP.nvidiaPackages // openOverrides // {
            latest     = overrideFullPackage superKP.nvidiaPackages.latest;
            stable     = overrideFullPackage superKP.nvidiaPackages.stable;
            beta       = overrideFullPackage superKP.nvidiaPackages.beta;
            production = overrideFullPackage superKP.nvidiaPackages.production;
          };
  
          nvidia_x11_beta_open       = overrideNvidiaOpen superKP.nvidia_x11_beta_open;
          nvidia_x11_latest_open     = overrideNvidiaOpen superKP.nvidia_x11_latest_open;
          nvidia_x11_production_open = overrideNvidiaOpen superKP.nvidia_x11_production_open;
        }
      );

in
{
  hardened_linux_kernel = hardened;
}
