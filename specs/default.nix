{ sources ? import ../nix/sources.nix
, packages ? import sources.nixpkgs {}
}:

let
  aspecs = import ../aspecs/default.nix { inherit packages; inShell = false; };

  cats =
    let
      toCatNumber = s:
        let
          x = builtins.split "cat" s;
        in if (builtins.length x) == 3
          then builtins.head (builtins.tail (builtins.tail x))
          else null;

      isCat = key: val:
        (val == "directory" && toCatNumber key != null);
    in map toCatNumber (builtins.attrNames
      (packages.lib.attrsets.filterAttrs isCat (builtins.readDir ../specs)));

  values = lst: builtins.filter (x: x != null) lst;

  isRegular = key: val: (val == "regular");

  listing = catnum: builtins.attrNames (packages.lib.attrsets.filterAttrs isRegular
    (builtins.readDir (./. + "/cat" + catnum)));

  findAst = x: s:
    let m = builtins.match (x + "-(.*).ast") s;
    in if m == null
      then null
      else builtins.head m;

  sortEditions = lst:
    let compareEditions = a: b: builtins.compareVersions a b == 1;
    in builtins.sort compareEditions lst;

  catsUnder = catnum: sortEditions (values (map (findAst "cat") (listing catnum)));

  refsUnder = catnum: sortEditions (values (map (findAst "ref") (listing catnum)));

  manifest =
    let
      obj = map (catnum: { category = catnum; cats = catsUnder catnum; refs = refsUnder catnum;}) cats;
    in
      packages.writeText "asterix-specs-manifest" ''
        ${builtins.toJSON obj}
      '';

  # BDS registers are kept out of the category manifest on purpose, so that
  # the existing manifest.json stays byte compatible for consumers which only
  # care about ASTERIX categories. They are published in their own
  # $out/bds/manifest.json instead.

  findBds = s:
    let m = builtins.match "bds-(.*)\\.ast" s;
    in if m == null
      then null
      else builtins.head m;

  bdsListing =
    builtins.attrNames (packages.lib.attrsets.filterAttrs isRegular
      (builtins.readDir (./. + "/bds")));

  bdsRaw = values (map findBds bdsListing);

  # Source files are named bds-<R1>.<R2>.ast, e.g. bds-4.0.ast. The register
  # as written inside the source uses a comma (bds 4,0 "..."), so Wireshark
  # has to translate between the two when it builds the download URL.
  bdsPair = s:
    let m = builtins.match "(.*)\\.(.*)" s;
    in if m == null
      then null
      else { r1 = builtins.head m; r2 = builtins.head (builtins.tail m); };

  # Registers are identified by two octal numbers, so they have to be
  # compared numerically ("4,10" comes after "4,2", not before).
  compareBds = a: b:
    let c = builtins.compareVersions (bdsPair a).r1 (bdsPair b).r1;
    in if c == 0
      then builtins.compareVersions (bdsPair a).r2 (bdsPair b).r2
      else c;

  bdsRegs = builtins.sort compareBds bdsRaw;

  bdsManifest =
    packages.writeText "asterix-specs-bds-manifest" ''
      ${builtins.toJSON bdsRegs}
    '';

  level1 = catnum:
    let
      asterix-spec = catnumber: spectype: edition:
        import ./spec.nix { inherit packages; inherit catnumber spectype edition;};

      linkCats =
        let linkCat = ed: "\"" + ed + " " + asterix-spec catnum "cat" ed + "\"";
        in toString (map linkCat (catsUnder catnum));

      linkRefs =
        let linkRef = ed: "\"" + ed + " " + asterix-spec catnum "ref" ed + "\"";
        in toString (map linkRef (refsUnder catnum));

    in
      packages.stdenv.mkDerivation {
        name = "asterix-category-" + catnum;
        src = builtins.filterSource
          (path: type:
            (type != "directory" || baseNameOf path != ".git")
            && (type != "symlink" || baseNameOf path != "result"))
          ./.;

        installPhase = ''
          mkdir -p $out

          mkdir -p $out/cats
          for i in ${linkCats}; do
            set -- $i
            ln -s $2 $out/cats/cat$1
          done

          mkdir -p $out/refs
          for i in ${linkRefs}; do
            set -- $i
            ln -s $2 $out/refs/ref$1
          done
        '';
      };

  linkCategories =
    let linkCategory = cat: "\"" + cat + " " + level1 cat + "\"";
    in toString (map linkCategory cats);

  bdsSpec = reg: import ./spec.nix {
    inherit packages;
    catnumber = "bds";
    spectype = "reg";
    edition = let p = bdsPair reg; in "${p.r1}.${p.r2}";
    srcpath = "/bds/bds-" + reg + ".ast";
    stem = reg;
    docs = false;
  };

  levelBds =
    let linkBds = reg: "\"" + reg + " " + bdsSpec reg + "\"";
    in toString (map linkBds bdsRegs);

  drv = packages.stdenv.mkDerivation {
    name = "asterix-specs";
    src = builtins.filterSource
      (path: type:
          (type != "directory" || baseNameOf path != ".git")
       && (type != "symlink" || baseNameOf path != "result"))
      ../specs;

    installPhase = ''
      mkdir -p $out

      cat ${manifest} | ${packages.jq}/bin/jq > $out/manifest.json

      mkdir -p $out/specs
      for i in ${linkCategories}; do
        set -- $i
        ln -s $2 $out/specs/cat$1
      done

      mkdir -p $out/bds
      cat ${bdsManifest} | ${packages.jq}/bin/jq > $out/bds/manifest.json
      for i in ${levelBds}; do
        set -- $i
        ln -s $2 $out/bds/bds$1
      done
    '';
  };

in
  drv
