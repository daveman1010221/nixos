# A host's hardened, clang-built kernel, from its own .config (hosts/<host>/overlays/.config) and the nixpkgs kernel
# its hosts/<host>/kernel-version.nix names. flake.nix applies it to a host that has a kernel-version.nix. Shared by
# every host that builds its own kernel; the sandbox (sandbox/shell.nix) builds from the same version file.
{ myConfig, kernelVersion, ... }:

final: prev:

let
  lib = prev.lib;
  llvm = prev.llvmPackages;

  # Source, version and upstream patches (bridge-stp-helper,
  # request-key-helper, ...) come from the nixpkgs kernel we track.
  base = prev.linuxKernel.kernels.${kernelVersion.attr};

  # nixpkgs replaces kbuild's module signing with kmodigest by passing
  # cmd_sign= on the make command line. Drop it so kbuild signs with the key
  # named by CONFIG_MODULE_SIG_KEY in our .config.
  dropKmodigest = lib.filter (f: !(lib.hasPrefix "cmd_sign=" f));

  # nixpkgs' postInstall concatenates the per-module kmodigest certificates
  # into modules.cer. kbuild signing produces none, so leave an empty
  # modules.cer for the module aggregator instead.
  kmodigestCat = "sed 's/$/\\.cer/' modules.order | xargs -d'\\n' cat > modules.cer";
  kmodigestRm = "sed 's/$/\\.cer/' modules.order | xargs -d'\\n' rm";

  # Used verbatim: no generate-config.pl, no common-config.nix.
  manual = prev.linuxManualConfig {
    inherit (base) src version modDirVersion kernelPatches;
    configfile = myConfig;
    stdenv = llvm.stdenv;
    extraMakeFlags = [
      "LLVM=1"
      "LLVM_IAS=1"
      "LD=${llvm.lld}/bin/ld.lld"
      "AR=${llvm.llvm}/bin/llvm-ar"
      "NM=${llvm.llvm}/bin/llvm-nm"
      "OBJCOPY=${llvm.llvm}/bin/llvm-objcopy"
      "OBJDUMP=${llvm.llvm}/bin/llvm-objdump"
      "STRIP=${llvm.llvm}/bin/llvm-strip"
      "READELF=${llvm.llvm}/bin/llvm-readelf"
      # LLVM=1 makes kbuild link host programs with -fuse-ld=lld, bypassing
      # Nix's ld wrapper: sign-file, objtool etc. would get no RUNPATH.
      "HOSTLDFLAGS=-fuse-ld=bfd"
    ];
  };

  hardenedKernel = manual.overrideAttrs (old: {
    makeFlags = dropKmodigest old.makeFlags;

    postInstall =
      if lib.hasInfix kmodigestCat old.postInstall && lib.hasInfix kmodigestRm old.postInstall then
        lib.replaceStrings [ kmodigestCat kmodigestRm ] [ ": > modules.cer" ":" ] old.postInstall
      else
        throw "custom-kernel.nix: nixpkgs' kernel postInstall no longer matches the kmodigest step this overlay removes; revisit it";

    # Out-of-tree modules build with these flags too.
    passthru = old.passthru // {
      commonMakeFlags = dropKmodigest old.passthru.commonMakeFlags;
    };
  });
in
{
  hardened_linux_kernel = prev.linuxPackagesFor hardenedKernel;
}
