{
  description = "debuginfo-zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      zig,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      lib = nixpkgs.lib;
      # zig.2025-11-02
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (final: prev: {
                # zig_glibc_2_28 = (prev.callPackage ./zig { })."0.13";
              })
            ];
          };
        in
        {
          static = pkgs.callPackage ./pkg.nix {
            zigRequired = zig.packages.${system}."master-2025-11-02" // {
              meta = {
                platforms = pkgs.lib.platforms.all;
                broken = false;
                maintainers = [ ];
              };
            };
            flags = [ "-Dlinkage=static" ];
          };
          dynamic = pkgs.callPackage ./pkg.nix {
            zigRequired = zig.packages.${system}."master-2025-11-02" // {
              meta = {
                platforms = pkgs.lib.platforms.all;
                broken = false;
                maintainers = [ ];
              };
            };
            flags = [ "-Dlinkage=dynamic" ];
          };
          default = self.packages.${system}.dynamic;
        }
      );
      develop = forAllSystems (system: {
        default = zig.packages.${system}."master-2025-11-02";
      });
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
