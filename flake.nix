{
  description = "Nix shell for building Verilator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem
    (system: let
      pkgs = import nixpkgs {
        inherit sytem;
      };
      buildInputs = with pkgs; [
        autoconf
        flex
        bison
        help2man
        perl
        python3
        zlib
        ccache
        mold
        libgoogle-perftools
        numactl
        perl-doc
        gdb
        graphviz
        lcov
        python3Packages.sphinx
        python3Packages.sphinx_rtd_theme
        python3Packages.breathe
        python3Packages.ruff
        python3Packages.yapf
        python3Packages.astsee
        libfl
        zlib
      ];
    in
      with pkgs; {
        devShells.default = mkShell {
          inherit buildInputs;
          # shellHook = ''
          #   export VERILATOR_ROOT="$PWD"
          # '';
        };
      });
}
