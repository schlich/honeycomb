{ lib }:

# Counts the collections a repository asks a person to hold in mind, as
# { "kind:name" = count; } for `audit`. Each counter covers one kind of
# collection; a repository merges the ones that apply to it, with its own
# counts beside them.
let
  # What a directory holds for itself rather than for a person to choose
  # between: what describes it, its manifest and lock, and what a forge or an
  # agent looks for at that exact path. These are the cell, not members seated
  # around it, the way home is the centre of the seven areas.
  centreNames = [
    "README.md"
    "AGENTS.md"
    "CLAUDE.md"
    "flake.nix"
    "flake.lock"
    "default.nix"
    ".github"
    ".agents"
  ];
in
rec {
  centre = centreNames;

  # Build output and dependency trees, which `path:` flakes include.
  skipped = [
    "node_modules"
    "packages"
    "target"
    "dist"
    "iwe.log"
  ];

  # Sort one directory's entries ({ NAME = TYPE; }, as builtins.readDir gives
  # them) into the `members` that take a seat and the `directories` to count
  # in turn. The centre takes no seat, but a directory in it is still counted.
  # Hidden entries are left out unless they are in the centre or named in
  # `hiddenButCounted`.
  seating =
    {
      centre ? centreNames,
      hiddenButCounted ? [ ],
    }:
    entries:
    let
      kept = lib.filterAttrs (
        name: _:
        !(lib.elem name skipped)
        && !(lib.hasPrefix "result" name)
        && !(lib.hasPrefix "_" name)
        && !(lib.hasSuffix ".egg-info" name)
        && (!(lib.hasPrefix "." name) || lib.elem name hiddenButCounted || lib.elem name centre)
      ) entries;
    in
    {
      members = builtins.attrNames (removeAttrs kept centre);
      directories = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") kept);
    };

  # Every directory's members under `root`, as "dir:PATH", seated by
  # `seating`.
  directories =
    {
      root,
      centre ? centreNames,
      hiddenButCounted ? [ ],
    }:
    let
      walk =
        relative:
        let
          seats = seating { inherit centre hiddenButCounted; } (
            builtins.readDir (if relative == "" then root else root + "/${relative}")
          );
          below = name: if relative == "" then name else "${relative}/${name}";
        in
        [
          (lib.nameValuePair "dir:${if relative == "" then "." else relative}" (
            builtins.length seats.members
          ))
        ]
        ++ lib.concatMap (name: walk (below name)) seats.directories;
    in
    lib.listToAttrs (walk "");

  # The lines of a file that match a regular expression.
  matching =
    pattern: file:
    builtins.length (
      builtins.filter (line: builtins.match pattern line != null) (
        lib.splitString "\n" (builtins.readFile file)
      )
    );

  # A tree of cells ({ name, cells ? [ ] }): each cell's member count, as
  # "PREFIX:NAME".
  cells =
    prefix: cell:
    lib.listToAttrs (
      let
        sizes =
          cell:
          lib.optionals (cell ? cells) (
            [ (lib.nameValuePair "${prefix}:${cell.name}" (builtins.length cell.cells)) ]
            ++ lib.concatMap sizes cell.cells
          );
      in
      sizes cell
    );

  # A flake's inputs, from its lock file, as "flake:inputs", with each
  # group's as "flake:GROUP/PATH". A group is an input locked as a relative
  # path, which is how a flake keeps its inputs six to a flake.
  flakeInputs =
    lockFile:
    let
      lock = builtins.fromJSON (builtins.readFile lockFile);
      isGroup = node: (node.locked.type or null) == "path" && node ? parent;
      counts =
        name: key:
        let
          node = lock.nodes.${key};
          members = lib.filterAttrs (_: builtins.isString) (node.inputs or { });
          groups = lib.filterAttrs (_: member: isGroup lock.nodes.${member}) members;
        in
        [ (lib.nameValuePair "flake:${name}" (builtins.length (builtins.attrNames (node.inputs or { })))) ]
        ++ lib.concatLists (
          lib.mapAttrsToList (
            member: memberKey: counts (if name == "inputs" then member else "${name}/${member}") memberKey
          ) groups
        );
    in
    lib.listToAttrs (counts "inputs" lock.root);
}
