# The `honeycomb` command (honeycomb.nu), with the areas it files work under,
# and `honeycomb-mcp` (mcp.nu), the same command as an MCP server.
{
  lib,
  symlinkJoin,
  writers,
  writeText,
}:

let
  areas = writeText "honeycomb-areas.json" (builtins.toJSON (import ../nix { inherit lib; }).areas);

  honeycomb = writers.writeNuBin "honeycomb" (
    ''
      $env.HONEYCOMB_AREAS = "${areas}"
    ''
    + builtins.readFile ./honeycomb.nu
  );

  mcp = writers.writeNuBin "honeycomb-mcp" (
    ''
      $env.HONEYCOMB_SCRIPT = "${honeycomb}/bin/honeycomb"
    ''
    + builtins.readFile ./mcp.nu
  );
in
symlinkJoin {
  name = "honeycomb";
  paths = [
    honeycomb
    mcp
  ];
  meta.mainProgram = "honeycomb";
}
