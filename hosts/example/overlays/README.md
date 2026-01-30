# hosts/<host>/overlays

This folder contains host-specific overlays and kernel build inputs.

## How discovery works
`flake.nix`:
- Imports all `*.nix` files directly in this directory as overlays (`final: prev: { ... }`)
- Skips `custom-kernel.nix` (handled specially)
- Requires a kernel config at: `hosts/<host>/overlays/.config`

## Required files
- `.config` — kernel configuration for this host (required)

## Special file: custom-kernel.nix
If present, `custom-kernel.nix` is imported with extra arguments:

- `myConfig`  (generated from `.config`)
- `mokPemPath` (MOK certificate as a Nix store file)
- `mokPrivPath` (MOK private key as a Nix store file)

`custom-kernel.nix` must itself return an overlay function.

## Overlay contract
Standard overlay:

```nix
final: prev: { ... }
```

### Example 1

`hosts/precisionws/overlays/example-overlay.nix`

```nix
final: prev: {
  hostBanner = "precisionws";
}
```


### Example 2

```nix
{ myConfig, mokPemPath, mokPrivPath }:
final: prev: {
  # This is just a stub showing how arguments arrive.
  # Your real file likely defines `hardened_linux_kernel = ...`
  exampleKernelInputs = {
    config = myConfig;
    pubCert = mokPemPath;
    privKey = mokPrivPath;
  };
}
```
