# A real, reusable module, auto-discovered by flake.nix's own
# discoveredModules mechanism -- every host gets this option
# available, but only trusts a certificate if it explicitly opts in
# by name via my.pki.trustedCerts, in its own hosts/<host>/modules/
# file (also auto-discovered, via hostModules).
{ config, lib, ... }:

with lib;

let
  cfg = config.my.pki;
in
{
  options.my.pki.trustedCerts = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      Names of trusted root certificates to add to this host's own
      trust store. Each name `foo` resolves to ../../pki/foo.crt
      (relative to this module -- i.e. <repo-root>/pki/foo.crt),
      concatenated into /etc/ssl/certs/ca-certificates.crt via
      security.pki.certificateFiles.
    '';
    example = [ "gitea-self-signed" ];
  };

  config = mkIf (cfg.trustedCerts != [ ]) {
    security.pki.certificateFiles =
      map (name: ../../pki + "/${name}.crt") cfg.trustedCerts;
  };
}
