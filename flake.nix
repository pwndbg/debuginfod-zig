{
  description = "debuginfo-zig";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
    # nixpkgs 26.11 dropped x86_64-darwin; 26.05 still supports it
    nixpkgs-x86_64-darwin.url = "https://channels.nixos.org/nixpkgs-26.05-darwin/nixexprs.tar.zst";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-x86_64-darwin,
      zig,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs (
        lib.unique (nixpkgs.lib.systems.flakeExposed ++ [ "x86_64-darwin" ])
      );
      nixpkgsFor = system: if system == "x86_64-darwin" then nixpkgs-x86_64-darwin else nixpkgs;
      lib = nixpkgs.lib;

      fun_zig_0_17 =
        pkgs:
        (
          let
            meta = {
              platforms = pkgs.lib.platforms.all;
              broken = false;
              maintainers = [ ];
            };
            zig_bin = zig.packages.${pkgs.stdenv.hostPlatform.system}."0.17.1";
            dev_zig = zig_bin // {
              inherit meta;
            };
            dev_zig_hook =
              if pkgs.zig.hook ? override then
                # nixpkgs <= 25.11: separate makeSetupHook package
                pkgs.zig.hook.override { zig = dev_zig; }
              else
                # nixpkgs >= 26.05: the hook is zig's own setupHook (zig.hook = zig);
                # zig-overlay sets dontFixup, so install it by hand
                zig_bin.overrideAttrs (old: {
                  inherit meta;
                  inherit (pkgs.zig)
                    setupHook
                    zig_default_cpu_flag
                    zig_default_optimize_flag
                    propagatedNativeBuildInputs
                    ;
                  installPhase = old.installPhase + ''
                    mkdir -p $out/nix-support
                    substituteAll "$setupHook" $out/nix-support/setup-hook
                  '';
                });
          in
          dev_zig // { hook = dev_zig_hook; }
        );

      fun_libdebuginfod = pkgs: attrs: pkgs.callPackage ./pkg.nix attrs;

      overlay = (
        final: prev: {
          # nixpkgs' own zig 0.17 once it has one, else the prebuilt one from zig-overlay
          dev_zig_0_17 = if prev ? zig_0_17 then prev.zig_0_17 else fun_zig_0_17 prev;
          libdebuginfod-zig-static = (
            fun_libdebuginfod prev {
              flags = [ "-Dlinkage=static" ];
            }
          );
          libdebuginfod-zig-dynamic = (
            fun_libdebuginfod prev {
              flags = [ "-Dlinkage=dynamic" ];
            }
          );
        }
      );

      fun_pkgs =
        system:
        import (nixpkgsFor system) {
          inherit system;
          overlays = [
            overlay
          ];
        };
    in
    {
      overlays.default = overlay;
      packages = forAllSystems (
        system:
        let
          pkgs = (fun_pkgs system);
        in
        {
          static = pkgs.libdebuginfod-zig-static;
          dynamic = pkgs.libdebuginfod-zig-dynamic;
          default = self.packages.${system}.dynamic;
          pkgsCross = pkgs.pkgsCross;
        }
      );
      develop = forAllSystems (
        system:
        let
          pkgs = (fun_pkgs system);
        in
        {
          default = pkgs.dev_zig_0_17;
        }
      );
      formatter = forAllSystems (system: (nixpkgsFor system).legacyPackages.${system}.nixfmt-tree);
    };
}
