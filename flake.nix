{
  description = "Honeycomb: no collection a person navigates holds more than six members";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      honeycomb = import ./nix { inherit lib; };
    in
    {
      # The model (nix/default.nix): the hexagon arithmetic, the keys, the
      # areas and the audit, with `census` for counting a repository's
      # collections (nix/census.nix).
      lib = honeycomb // {
        census = import ./nix/census.nix { inherit lib; };
      };

      packages.${system} = {
        honeycomb = pkgs.callPackage ./runtime/package.nix { };
        default = self.packages.${system}.honeycomb;
      };

      # The phone's hub (runtime/hub), on loopback; publishing it is the
      # host's.
      nixosModules = {
        hub = ./runtime/hub/module.nix;
        default = self.nixosModules.hub;
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = {
        # The hexagon arithmetic behind the rule of six.
        tests =
          let
            tests = import ./nix/tests.nix { inherit lib; };
            failures = lib.runTests tests;
          in
          pkgs.writeText "honeycomb-tests" (
            assert lib.assertMsg (failures == [ ])
              "honeycomb-tests failed:\n${lib.generators.toPretty { } failures}";
            lib.concatMapStrings (test: "${test}\n") (builtins.attrNames tests)
          );

        # This repository keeps its own rule: nothing in it passes six.
        census =
          let
            result = honeycomb.audit {
              census = self.lib.census.directories { root = ./.; };
              baseline = { };
            };
          in
          pkgs.writeText "honeycomb-census" (
            assert lib.assertMsg (honeycomb.clean result)
              "honeycomb-census failed:\n${honeycomb.report result}";
            "clean\n"
          );

        # `honeycomb sidebar`, `sessions`, `flower` and `hub apply` on a
        # fixture of Claude's sidebar, and the hub on requests as Tailscale
        # Serve passes them on.
        runtime =
          pkgs.runCommand "honeycomb-runtime-check"
            {
              nativeBuildInputs = [ pkgs.nushell ];
            }
            ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              ${pkgs.nushell}/bin/nu --no-config-file ${./runtime/tests.nu} ${./runtime/honeycomb.nu} ${pkgs.writeText "honeycomb-areas.json" (builtins.toJSON honeycomb.areas)} ${./runtime/hub/server.nu} ${lib.getExe pkgs.http-nu}
              touch "$out"
            '';

        package = self.packages.${system}.honeycomb;
      };
    };
}
