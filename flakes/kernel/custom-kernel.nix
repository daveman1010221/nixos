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

  # The kept-files list in nixpkgs' postInstall, and the same list with the signing certificate.
  keepConfig = "  \"$buildRoot/.config\"\n";
  keepConfigAndCert = keepConfig + "  \"$buildRoot/certs/signing_key.x509\"\n";

  # What NixOS modules ask of a kernel (kernel.features): a stock nixpkgs kernel declares these, and
  # linuxManualConfig leaves them empty, so they are read from the config itself. graphics.nix asserts
  # ia32Emulation for hardware.graphics.enable32Bit; the iptables firewall reads netfilterRPFilter.
  configText = builtins.readFile myConfig;
  builds = sym: lib.any (v: lib.hasInfix "\nCONFIG_${sym}=${v}\n" configText) [ "y" "m" ];

  # Used verbatim: no generate-config.pl, no common-config.nix.
  manual = prev.linuxManualConfig {
    inherit (base) src version modDirVersion kernelPatches;
    configfile = myConfig;
    features = {
      ia32Emulation = builds "IA32_EMULATION";
      efiBootStub = builds "EFI_STUB";
      netfilterRPFilter = builds "IP_NF_MATCH_RPFILTER";
    };
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

    # Two changes to nixpkgs' postInstall. The kmodigest step goes (above). And the dev output keeps the signing
    # certificate, certs/signing_key.x509: kbuild's modules_install signs an out-of-tree module (NVIDIA's) with
    # CONFIG_MODULE_SIG_KEY and that certificate, and without it sign-file fails, which kbuild does not treat as
    # fatal, so the module installs unsigned. The certificate is public; the kernel embeds it.
    postInstall =
      if lib.hasInfix kmodigestCat old.postInstall && lib.hasInfix kmodigestRm old.postInstall
         && lib.hasInfix keepConfig old.postInstall then
        lib.replaceStrings [ kmodigestCat kmodigestRm keepConfig ] [ ": > modules.cer" ":" keepConfigAndCert ]
          old.postInstall
      else
        throw "custom-kernel.nix: nixpkgs' kernel postInstall no longer matches what this overlay changes (the kmodigest step, the kept .config); revisit it";

    # Out-of-tree modules build with these flags too.
    passthru = old.passthru // {
      commonMakeFlags = dropKmodigest old.passthru.commonMakeFlags;
      # Every module this kernel loads must carry a signature by the host's key (MODULE_SIG_FORCE);
      # flakes/modules/kernel-module-signatures.nix checks it for the whole system.
      signsWithHostKey = true;
    };
  });
  # nixpkgs' module aggregation (the system's modules tree) merges each out-of-tree module's kmodigest certificate,
  # <module>.ko.cer, into modules.cer. Modules signed by kbuild with the host's key have none, so for NVIDIA's the
  # merge's cat fails the build. The merge goes; modules.cer stays the kernel's (empty, above).
  mergeExternalCerts = "| xargs -d'\\n' cat >> modules.cer";
in
{
  hardened_linux_kernel = prev.linuxPackagesFor hardenedKernel;

  aggregateModules = modules:
    (prev.aggregateModules modules).overrideAttrs (old: {
      postBuild =
        if lib.hasInfix mergeExternalCerts old.postBuild then
          lib.replaceStrings [ mergeExternalCerts ] [ "| cat > /dev/null" ] old.postBuild
        else
          throw "custom-kernel.nix: nixpkgs' aggregateModules no longer merges kmodigest certificates as this overlay expects; revisit it";
    });
}
