final: prev:
let
  # Make the helper script derivation-backed (has a .drv)
  gdfontHook = prev.writeShellScript "set-gdfontpath-from-fontconfig.sh" ''
    p=( $(fc-list : file | sed "s@/[^/]*: @@" | sort -u) )
    IFS=:
    export GDFONTPATH="''${GDFONTPATH}''${GDFONTPATH:+:}''${p[*]}"
    unset IFS p
  '';
in
{
  gnuplot = prev.gnuplot.overrideAttrs (old: {
    passthru = (old.passthru or {}) // { _gdfont_overlay = true; };
    postFixup = (old.postFixup or "") + ''
      # Find any references to the raw store script path and replace them
      # with our derivation-backed one.
      hits="$(grep -RhoE '/nix/store/[a-z0-9]{32}-set-gdfontpath-from-fontconfig\.sh' "$out" | sort -u || true)"

      if [ -n "$hits" ]; then
        echo "Patching gnuplot to replace deriver-less gdfontpath script:"
        echo "$hits" | sed 's/^/  - /'
        while IFS= read -r oldpath; do
          # Replace in any text file under $out that contains it
          while IFS= read -r f; do
            substituteInPlace "$f" --replace "$oldpath" "''${gdfontHook}"
          done < <(grep -RIlF "$oldpath" "$out" || true)
        done <<< "$hits"
      fi
    '';
  });
}
