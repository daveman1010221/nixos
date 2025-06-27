every new hook is basically:

    Add a new Rust crate in git-hooks/

cargo new --bin pre-push-hook

Implement your logic in src/main.rs.

Declare it in the overlay

# flakes/overlays/git-hooks.nix
{
  commitMsgHook = …;
  prePushHook   = super.rustPlatform.buildRustPackage {
    pname   = "pre-push-hook";
    version = "0.1.0";
    src     = builtins.path { path = ../../git-hooks/pre-push-hook; };
    cargoLock.lockFile = "${src}/Cargo.lock";
    doCheck = false;
  };
}

Drop it into the templates dir

environment.etc."git-templates".source = pkgs.runCommand "git-templates" {} ''
  mkdir -p $out/hooks
  install -m0755 ${pkgs.commitMsgHook}/bin/commit-msg-hook $out/hooks/commit-msg
  install -m0755 ${pkgs.prePushHook}/bin/pre-push-hook     $out/hooks/pre-push
'';
