#!/usr/bin/env wolframscript
(* PRIVATE S&T validation smoke test.  Reads the git-ignored validation.json that
   wolfram/ebirdst_r.wls produces and asserts at least one species was validated
   against its GBIF track with a finite mean great-circle separation. *)

v = FileNameJoin[{DirectoryName[$InputFileName, 2], "data", "raw", "ebirdst", "validation.json"}];
If[! FileExistsQ[v], Print["FAIL: no validation.json (need S&T key + ebirdst)"]; Exit[1]];
d = Import[v, "RawJSON"];
got = Select[Values@KeyDrop[d, "_unavailable"],
  AssociationQ[#] && NumberQ[#["meanSepKm"]] &];
Print[If[Length[got] >= 1,
  "PASS ebirdst (" <> ToString[Length[got]] <> " species)",
  "FAIL none validated"]];
If[Length[got] < 1, Exit[1]];
