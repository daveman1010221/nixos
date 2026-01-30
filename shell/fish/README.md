# shell/fish

Fish functions are wired into `/etc/fish/vendor_functions.d` automatically.

## Static functions
Files in:
- `shell/fish/functions/static/*`

are copied verbatim into:
- `/etc/fish/vendor_functions.d/<filename>`

Use this for plain `.fish` function files.

## Templated functions
Files in:
- `shell/fish/functions/templated/*.nix`

are imported and must return a string containing the `.fish` content.
The output is written to:
- `/etc/fish/vendor_functions.d/<name>.fish`

These templates receive arguments from the host module:
- `pkgs`
- `manpackage`
- `hostname`
- `cowsayPath`

## Examples

{ pkgs, hostname, ... }:
''
function hello_${hostname}
  echo "hello from ${hostname}"
end
''

