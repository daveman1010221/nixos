{ pkgs, lib, ... }:

let
  # all packages that bring *.pc files you want visible, for example, for
  # “cargo install”
  pcDeps = [ pkgs.openssl pkgs.zlib ];

in {
  # Make Cargo (and any other build system that honours the usual CC /
  # CFLAGS variables) call Clang and link with LLD by default.
  environment.variables = {
    # compile with clang
    CC  = "clang";
    CXX = "clang++";

    # and tell those compilers to use the LLVM linker
    CFLAGS   = "-fuse-ld=lld";
    CXXFLAGS = "-fuse-ld=lld";

    # optional, makes `cargo` fall back to pkg-config for native deps
    PKG_CONFIG_PATH = lib.strings.makeSearchPathOutput "dev" "lib/pkgconfig" pcDeps;
  };
}
