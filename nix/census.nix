{ lib }:

# Counts the collections a repository asks a person to hold in mind, as
# { "kind:name" = count; } for `audit`. Each counter covers one kind of
# collection; a repository merges the ones that apply to it, with its own
# counts beside them.
rec {
  # Build output and dependency trees, which `path:` flakes include.
  skipped = [
    "node_modules"
    "packages"
    "target"
    "dist"
    "iwe.log"
  ];

  # Every directory's entries under `root`, as "dir:PATH". Hidden entries
  # are left out except those named in `hiddenButCounted`.
  directories =
    {
      root,
      hiddenButCounted ? [
        ".agents"
        ".github"
      ],
    }:
    let
      counted =
        name:
        !(lib.elem name skipped)
        && !(lib.hasPrefix "result" name)
        && !(lib.hasPrefix "_" name)
        && !(lib.hasSuffix ".egg-info" name)
        && (!(lib.hasPrefix "." name) || lib.elem name hiddenButCounted);

      walk =
        relative:
        let
          entries = lib.filterAttrs (name: _: counted name) (
            builtins.readDir (if relative == "" then root else root + "/${relative}")
          );
          below = name: if relative == "" then name else "${relative}/${name}";
          children = lib.concatLists (
            lib.mapAttrsToList (name: type: lib.optionals (type == "directory") (walk (below name))) entries
          );
        in
        [
          (lib.nameValuePair "dir:${if relative == "" then "." else relative}" (
            builtins.length (builtins.attrNames entries)
          ))
        ]
        ++ children;
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
