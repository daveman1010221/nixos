{ myConfig, mokPemPath, mokPrivPath, ... }:

final: prev:

let
  # Our hardened kernel derivation – just a normal override, no phase hacking.
  hardenedKernel = prev.linuxKernel.kernels.linux_7_0.overrideAttrs (old: {
    # Automatic out‑of‑tree build, config from our file.
    useOutOfTreeBuilder = true;
    configfile = myConfig;

    # Toolchain overrides passed directly to the kernel build system.
    makeFlags = (old.makeFlags or []) ++ [
      "LLVM=1"
      "LLVM_IAS=1"
      "CC=${prev.llvmPackages.clang-unwrapped}/bin/clang"
      "CXX=${prev.llvmPackages.clang-unwrapped}/bin/clang++"
      "LD=${prev.llvmPackages.lld}/bin/ld.lld"
      "AR=${prev.llvmPackages.llvm}/bin/llvm-ar"
      "NM=${prev.llvmPackages.llvm}/bin/llvm-nm"
      "OBJCOPY=${prev.llvmPackages.llvm}/bin/llvm-objcopy"
      "OBJDUMP=${prev.llvmPackages.llvm}/bin/llvm-objdump"
      "STRIP=${prev.llvmPackages.llvm}/bin/llvm-strip"
      "READELF=${prev.llvmPackages.llvm}/bin/llvm-readelf"
    ];

    # Host side still uses the usual stdenv.
    env = (old.env or {}) // {
      HOSTCC = "${prev.stdenv.cc}/bin/cc";
      HOSTCXX = "${prev.stdenv.cc}/bin/c++";
    };

    # Additional build inputs we need.
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
      prev.llvmPackages.clang-unwrapped
      prev.llvmPackages.lld
      prev.llvmPackages.llvm
      prev.pkg-config
      prev.ncurses
      prev.bison
      prev.flex
      prev.openssl
      prev.bc
      prev.kmod
      prev.pahole
      prev.glibc.dev
      prev.linuxHeaders
      prev.rsync
    ];

    # Sign all modules after installation.
    postInstall = (old.postInstall or "") + ''
      version=$(ls $modules/lib/modules | head -1)
      if [ -n "$version" ] && [ -x "$dev/lib/modules/$version/build/scripts/sign-file" ]; then
        find $modules/lib/modules/$version -name '*.ko' \
          -exec $dev/lib/modules/$version/build/scripts/sign-file \
          sha256 ${mokPrivPath} ${mokPemPath} {};
      fi
    '';
  });
in
{
  hardened_linux_kernel = prev.linuxPackagesFor hardenedKernel;
}
