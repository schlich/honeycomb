# The `honeycomb` command (honeycomb.nu), with the areas it files work under.
{
  lib,
  writers,
  writeText,
}:

writers.writeNuBin "honeycomb" (
  ''
    $env.HONEYCOMB_AREAS = "${
      writeText "honeycomb-areas.json" (builtins.toJSON (import ../nix { inherit lib; }).areas)
    }"
  ''
  + builtins.readFile ./honeycomb.nu
)
