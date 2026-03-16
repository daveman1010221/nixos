final: prev: {
  xbindkeys-config = prev.xbindkeys-config.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE =
        (old.env.NIX_CFLAGS_COMPILE or "") + " -Wno-error=incompatible-pointer-types";
    };
  });
}
