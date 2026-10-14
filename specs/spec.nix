{ sources ? import ../nix/sources.nix
, packages ? import sources.nixpkgs {}
, catnumber
, spectype
, edition
, # Path of the .ast source relative to specs/, and output file stem.
  srcpath ? "/cat" + catnumber + "/" + spectype + "-" + edition + ".ast"
, stem ? "definition"
, # Render human readable documentation (HTML/PDF). Wireshark only
  # consumes definition.json, so this can be disabled to avoid the
  # TeX Live / pandoc build cost.
  docs ? true
}:

let
  to-pdf = import ../to-pdf/default.nix { inherit packages; inShell = false; };

  name = "asterix-${catnumber}-${spectype}-${edition}";
  src = builtins.readFile (./. + srcpath);
  orig = packages.writeText (name + "-source") src;

  aspecs = import ../aspecs/default.nix { inherit packages; inShell = false; };

  style1 = packages.writeText "style1" (builtins.readFile (../style/default.css));
  style2 = packages.writeText "style2" (builtins.readFile (../style/syntax.css));

  deps = (if docs
          then (with packages; [ pandoc to-pdf ])
          else [ ]);

in with packages; runCommand name
  { propagatedBuildInputs = deps;
    FONTCONFIG_FILE = packages.makeFontsConf
      { fontDirectories = [packages.dejavu_fonts]; };
  }
  ''
    echo ${name}
    mkdir $out

    echo "validate"
    ${aspecs}/bin/aspecs validate --input-ast ${orig}
    cp ${orig} $out/${stem}.ast

    echo "create fingerprint"
    ${aspecs}/bin/aspecs checksum --input-ast --sha256 ${orig} > $out/checksum.sha256

    echo "create txt"
    ${aspecs}/bin/aspecs convert --input-ast --output-ast ${orig} \
        > $out/${stem}.txt

    ${if docs then ''
    echo "create pandoc native"
    ${aspecs}/bin/aspecs pandoc --input-ast ${orig} \
        > $out/${stem}.pandoc.native

    echo "create html"
    pandoc --metadata title="asterix specification" \
        -f native -t html $out/${stem}.pandoc.native \
        -o $out/${stem}.html --embed-resources --standalone \
        --css=${style1} --css=${style2}

    echo "create pdf"
    to-pdf $out/${stem}.pandoc.native $out/${stem}.pdf
    '' else ''}

    echo "create internal"
    ${aspecs}/bin/aspecs convert --input-ast --output-internal ${orig} \
        > $out/${stem}.internal
    ${aspecs}/bin/aspecs checksum --sha256 \
        --input-internal $out/${stem}.internal > $out/${stem}.internal.cks
    diff $out/checksum.sha256 $out/${stem}.internal.cks
    rm $out/${stem}.internal.cks

    echo "create json"
    ${aspecs}/bin/aspecs convert --input-ast --output-json ${orig} \
        > $out/${stem}.json
    ${aspecs}/bin/aspecs checksum --sha256 \
        --input-json $out/${stem}.json > $out/${stem}.json.cks
    diff $out/checksum.sha256 $out/${stem}.json.cks
    rm $out/${stem}.json.cks
  ''
