# hosts/<host>/modules

Each host may have a `modules/` directory for host-specific NixOS modules.

## How discovery works
For each host directory under `hosts/`:
- If `hosts/<host>/modules` exists, `flake.nix` recursively finds `*.nix` files.
- Those modules are appended to the host's module list.

These modules are applied **only** to that host.

## Module contract
Same as any NixOS module:

### Example

`hosts/precisionws/modules/example.nix`

```nix
{ config, lib, pkgs, ... }:
{
  config = {
    services.openssh.enable = true;
  };
}
```
