# hosts/<host>/pkgs

Host-local packages live here and are auto-exported into the host's `pkgs` set.

## How discovery works
`flake.nix` scans:

- `hosts/<host>/pkgs/<name>/default.nix`

If the directory exists and contains `default.nix`, it becomes available as:

- `pkgs.<name>` with `-` replaced by `_`

Example:
- `hosts/precisionws/pkgs/nvidia590/default.nix`
  → `pkgs.nvidia590` (or `pkgs.nvidia_590` depending on directory name)

## Package contract
Each package is written as a `callPackage`-friendly function, typically:

```nix
{ stdenv, lib, fetchFromGitHub, ... }:
stdenv.mkDerivation { ... }
```

### Example package: `hosts/precisionws/pkgs/example/default.nix`

```nix
{ lib, stdenv, writeShellScriptBin }:
writeShellScriptBin "example-host-pkg" ''
  echo "hello from a host-local package"
''
```
