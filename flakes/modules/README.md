# flakes/modules

This folder is **auto-discovered** by `flake.nix`.

## How discovery works
- The flake recursively searches this directory for `*.nix` files.
- Files are sorted lexicographically by path to keep evaluation deterministic.
- Every discovered module is added to `commonModules` and applied to **all hosts**.

That means: **dropping a module into this folder makes it live everywhere.**

## Module contract
Each file must be a valid NixOS module, i.e. it must evaluate to an attribute set like:

- `{ config, lib, pkgs, ... }: { ... }`  
or
- `{ ... }: { ... }`

## Example
`example-module.nix`:

{ config, lib, pkgs, ... }:
{
  options.example.enable = lib.mkEnableOption "example module";

  config = lib.mkIf config.example.enable {
    environment.systemPackages = [ pkgs.hello ];
  };
}
