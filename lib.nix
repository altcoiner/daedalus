let
  # iohk-nix can be overridden for debugging purposes by setting
  # NIX_PATH=iohk_nix=/path/to/iohk-nix
  iohkNix = import (
    let try = builtins.tryEval <iohk_nix>;
    in if try.success
    then builtins.trace "using host <iohk_nix>" try.value
    else
      let
        spec = builtins.fromJSON (builtins.readFile ./iohk-nix.json);
      in builtins.fetchTarball {
        url = "${spec.url}/archive/${spec.rev}.tar.gz";
        inherit (spec) sha256;
      }) {};

  # NIX_PATH=cardano-sl=/path/to/cardano-sl
  # WARNING: currently broken with infinite recursion
  cardanoSL = { config ? {}, system ? builtins.currentSystem }:
    let try = builtins.tryEval <cardano-sl>;
    in if try.success
    then builtins.trace "using host <cardano-sl>" (import try.value { inherit system config; })
    else
      let
        spec = builtins.fromJSON (builtins.readFile ./cardano-sl-src.json);
      in import (builtins.fetchTarball {
        url = "${spec.url}/archive/${spec.rev}.tar.gz";
        inherit (spec) sha256;
      }) { inherit system config; gitrev = spec.rev; };

  # nixpkgs can be overridden for debugging purposes by setting
  # NIX_PATH=custom_nixpkgs=/path/to/nixpkgs
  pkgs = iohkNix.pkgs;
  lib = pkgs.lib;
  isDaedalus = name: false;

in lib // (rec {
  inherit iohkNix pkgs cardanoSL isDaedalus;

  # Removes files within the source tree which won't change the
  # result of building the package.
  # This is so that cached build products can be used whenever possible.
  # It also applies the lib.cleanSource filter from nixpkgs which
  # removes VCS directories, emacs backup files, etc.
  cleanSourceTree = src:
    if (builtins.typeOf src) == "path"
      then lib.cleanSourceWith {
        filter = with pkgs.stdenv;
          name: type: let baseName = baseNameOf (toString name); in ! (
            # Filter out npm downloads and builds
            baseName == "node_modules" || baseName == "release" ||
            baseName == ".cache" ||
            # Filter out cabal build products.
            baseName == "dist" || baseName == "dist-newstyle" ||
            baseName == "cabal.project.local" ||
            lib.hasPrefix ".ghc.environment" baseName ||
            # Filter out stack build products.
            lib.hasPrefix ".stack-work" baseName ||
            # Filter out files which are commonly edited but don't
            # affect npm or cabal builds.
            lib.hasSuffix ".nix" baseName ||
            # Filter out editor temp files
            (type == "symlink" && lib.hasPrefix ".#" baseName)
          );
        src = lib.cleanSource src;
      } else src;

  # Removes anything but source directories and top-level config files
  # relevant to the npm build.
  npmSourceTree = src: lib.sourceByRegex (cleanSourceTree src)
    (map (base: ".*${base}.*") [
      "\."
      "/features"
      "/flow"
      "/gulpfile.js"
      "/package.json"
      "/source"
      "/storybook"
      "/yarn.lock"
    ]);

  # Selects only sources added to the git index if this is a git
  # checkout -- otherwise returns cleaned sources.
  gitSources = src: let
    dotGitExists = builtins.pathExists (src + "/.git");
    isNix2 = 0 <= builtins.compareVersions builtins.nixVersion "1.12";
    canUseFetchGit = dotGitExists && isNix2;
  in
    if canUseFetchGit then builtins.fetchGit src else cleanSourceTree src;

  # Generate a derivation with correct installer filename and hydra metrics.
  wrapPackage = buildNum: package: let
    components = lib.splitString "." package.name;
    backend = lib.concatStringsSep "." (lib.init components);
    ext = lib.last components;
    fn = "${backend}-${package.network}-${niceOSName package.system}${versionSuffix buildNum}.${ext}";
  in pkgs.runCommand fn {} ''
    mkdir -pv $out/nix-support
    cp ${package} $out/${fn}
    echo "file binary-dist $out/${fn}" >> $out/nix-support/hydra-build-products
    size="$(stat $out/${fn} --printf="%s")"
    echo installerSize $(($size / 1024 / 1024)) MB >> $out/nix-support/hydra-metrics
  '';

  # Optional build number suffix for version strings.
  versionSuffix = buildNum: if buildNum == null then "" else "-${toString buildNum}";

  # darwin is a four letter word
  niceOSName = system:
    let os = lib.last (lib.splitString "-" system);
    in if os == "darwin" then "macos" else os;

  # Make a name for the Daedalus program depending on the network it
  # is configured to.
  daedalusProgName = network:
    let suffix = if network != "mainnet" then "-${network}" else "";
    in "daedalus${suffix}";
  # Same as above, except with upper-case letter and space.
  daedalusAppName = network:
    let suffixSp = if network != "mainnet" then " ${network}" else "";
    in "Daedalus${suffixSp}";
})
