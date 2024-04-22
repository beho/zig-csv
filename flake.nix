{
  description = "zig-csv";
  # based on https://github.com/mitchellh/zig-overlay/blob/2c86c36e7fe65faac08bdf85d041cf7b798f8ee8/templates/init/flake.nix

  inputs = {
    # zls at 0.11.0
    nixpkgs.url = "github:nixos/nixpkgs/ff1a94e523ae9fb272e0581f068baee5d1068476";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs :
    let
      overlays = [
        (final: prev: {
          zigpkgs = inputs.zig.packages.${prev.system};
        })
      ];
      # Our supported systems are the same supported systems as the Zig binaries
      systems = builtins.attrNames inputs.zig.packages;
    in
      flake-utils.lib.eachSystem systems (
        system: let
          pkgs = import nixpkgs { inherit overlays system; };
        in rec {
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = [
              pkgs.zigpkgs."0.11.0"
            ];
            buildInputs = [
              pkgs.zls
            ];
          };

          # For compatibility with older versions of the `nix` binary
          devShell = self.devShells.${system}.default;
        }
      );
}
