{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    nixpkgsFor = forAllSystems (system: import nixpkgs {inherit system;});
  in {
    packages = forAllSystems (
      system: let
        pkgs = nixpkgsFor.${system};
      in {
        default = pkgs.stdenv.mkDerivation {
          name = "zig-project";
          src = self;
          buildInputs = [pkgs.libuuid.dev pkgs.sqlite.dev pkgs.zig];
          nativeBuildInputs = [pkgs.pkg-config];
          buildPhase = ''
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            export C_INCLUDE_PATH="${pkgs.sqlite.dev}/include:${pkgs.libuuid.dev}/include:$C_INCLUDE_PATH"
            zig build
          '';
          installPhase = ''
            mkdir -p $out/lib
            cp zig-out/lib/* $out/lib/
          '';
        };
      }
    );

    devShells = forAllSystems (
      system: let
        pkgs = nixpkgsFor.${system};
      in {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.libuuid.dev
            pkgs.sqlite.dev
            pkgs.zig
            pkgs.zls
          ];
          shellHook = ''
            export C_INCLUDE_PATH="${pkgs.sqlite.dev}/include:${pkgs.libuuid.dev}/include:$C_INCLUDE_PATH"
            export CPLUS_INCLUDE_PATH="${pkgs.sqlite.dev}/include:${pkgs.libuuid.dev}/include:$CPLUS_INCLUDE_PATH"
          '';
        };
      }
    );
  };
}
