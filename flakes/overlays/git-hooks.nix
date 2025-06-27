# flakes/overlays/git-hooks.nix
#
#   Overlay that exposes *your* commit-message validator as pkgs.commitMsgHook
#   so it can be referenced from the system flake with `pkgs.commitMsgHook`.

self: super:

let
  # Always resolve to an absolute path inside this repository
  src = builtins.path { path = ../../git-hooks; };
in
{
  commitMsgHook = super.rustPlatform.buildRustPackage {
    pname   = "commit-msg-hook";
    version = "0.1.0";

    inherit src;

    cargoLock.lockFile = "${src}/Cargo.lock";

    # the binary is tiny – no need to run tests in the system build
    doCheck = false;

    # install the binary as “commit-msg-hook” (default name is fine)
    # installPhase = ''
    #   runHook preInstall
    #   install -Dm0755 target/${RUST_TARGET:-x86_64-unknown-linux-gnu}/release/commit-msg-hook \
    #     $out/bin/commit-msg-hook
    #   runHook postInstall
    # '';
  };
}
