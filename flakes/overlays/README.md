# flakes/overlays

This folder is **auto-discovered** by `flake.nix` and applied to **all hosts**.

## How discovery works
- The flake recursively searches this directory for `*.nix` files.
- Files are sorted lexicographically by path to keep evaluation deterministic.
- Each file is imported and appended to `commonOverlays`.

Dropping a file here changes the package set for every machine.

## Overlay contract
Each file must evaluate to an overlay function:

### Example overlay

`flakes/overlays/example-overlay.nix`

```nix
final: prev: {
  helloWrapped = final.writeShellScriptBin "hello-wrapped" ''
    exec ${final.hello}/bin/hello "$@"
  '';
}
```

