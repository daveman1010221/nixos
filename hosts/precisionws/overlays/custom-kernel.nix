{ myConfig, myPubCert, myPrivKey, ... }:

{}

# final: prev: {
#   hardened_linux_kernel = prev.linuxPackagesFor (prev.linuxKernel.kernels.linux_6_13_hardened.overrideAttrs (old: {
#     dontConfigure = true;
# 
#     nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ prev.kmod prev.openssl prev.hostname prev.qboot ];
#     buildInputs = (old.buildInputs or []) ++ [ prev.kmod prev.openssl prev.hostname ];
# 
#     buildPhase = ''
#       mkdir -p tmp_certs
#       cp ${myConfig} tmp_certs/.config
#       cp ${myPubCert} tmp_certs/MOK.pem
#       cp ${myPrivKey} tmp_certs/MOK.priv
# 
#       # Ensure they are actually there before proceeding
#       ls -lah tmp_certs
# 
#       # Move them into place before compilation
#       cp tmp_certs/.config .config
#       cp tmp_certs/MOK.pem MOK.pem
#       cp tmp_certs/MOK.priv MOK.priv
# 
#       ls -alh
# 
#       make \
#         ARCH=${prev.stdenv.hostPlatform.linuxArch} \
#         CROSS_COMPILE= \
#         KBUILD_BUILD_VERSION=1-NixOS \
#         KCFLAGS=-Wno-error \
#         O=. \
#         SHELL=${prev.bash}/bin/bash \
#         -j$NIX_BUILD_CORES \
#         bzImage modules
#     '';
# 
#     installPhase = ''
#       export PATH=${prev.openssl}/bin:$PATH
#       echo "Using OpenSSL from: $(which openssl)"
#       openssl version
# 
#       mkdir -p $out
#       mkdir -p $dev
# 
#       make \
#         INSTALL_PATH=$out \
#         INSTALL_MOD_PATH=$out \
#         INSTALL_HDR_PATH=$dev \
#         O=. \
#         -j$NIX_BUILD_CORES \
#         headers_install modules_install
# 
#       cp arch/x86/boot/bzImage System.map $out/
# 
#       version=$(make O=. kernelrelease)
# 
#       # Prepare the source tree for external module builds
#       mkdir -p $dev/lib/modules/$version/source
# 
#       # Preserve essential files before cleanup
#       cp .config $dev/lib/modules/$version/source/.config
#       if [ -f Module.symvers ]; then cp Module.symvers $dev/lib/modules/$version/source/Module.symvers; fi
#       if [ -f System.map ]; then cp System.map $dev/lib/modules/$version/source/System.map; fi
#       if [ -d include ]; then
#         mkdir -p $dev/lib/modules/$version/source
#         cp -r include $dev/lib/modules/$version/source/
#       fi
# 
#       # Clean the build tree
#       make O=. clean mrproper
# 
#       # Copy the cleaned-up source tree before it gets removed.
#       cp -a . $dev/lib/modules/$version/source
# 
#       # **Change to the new source directory**
#       cd $dev/lib/modules/$version/source
# 
#       # Regenerate configuration and prepare for external module compilation
#       make O=$dev/lib/modules/$version/source \
#         -j$NIX_BUILD_CORES \
#         prepare modules_prepare
# 
#       ln -s $dev/lib/modules/$version/source $dev/lib/modules/$version/build
#     '';
# 
#     outputs = [ "out" "dev" ];
#   }));
# 
#   nvidiaPackages = final.hardened_linux_kernel.nvidiaPackages.beta.overrideAttrs (old: {
#     preInstall = (if old.preInstall == null then "" else old.preInstall) + ''
#       echo "🚨 NVIDIA OVERLAY IS RUNNING 🚨"
#       echo "🚨 NVIDIA PRE-FIXUP: Signing NVIDIA kernel modules before compression 🚨"
# 
#       SIGN_FILE="${final.hardened_linux_kernel.dev}/lib/modules/${old.kernelVersion}/source/scripts/sign-file"
#       MOK_CERT="${final.hardened_linux_kernel.dev}/lib/modules/${old.kernelVersion}/source/MOK.pem"
#       MOK_KEY="${final.hardened_linux_kernel.dev}/lib/modules/${old.kernelVersion}/source/MOK.priv"
# 
#       if [ ! -x "$SIGN_FILE" ]; then
#         echo "❌ sign-file tool not found at $SIGN_FILE"
#         exit 1
#       fi
# 
#       echo "✅ Using sign-file: $SIGN_FILE"
#       echo "✅ Signing NVIDIA kernel modules with MOK key: $MOK_KEY"
# 
#       # Find all uncompressed .ko modules and sign them
#       for mod in $(find $out/lib/modules -type f -name "*.ko"); do
#         echo "🔹 Signing module: $mod"
#         $SIGN_FILE sha256 $MOK_KEY $MOK_CERT "$mod" || exit 1
#       done
# 
#       echo "✅ All modules signed successfully!"
#     '';
#   });
# 
#   # Assign to kernel package set so the system uses it
#   final.hardened_linux_kernel.nvidiaPackages.beta = final.nvidiaPackages;
# }
