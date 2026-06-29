Get[FileNameJoin[{DirectoryName[$InputFileName, 2], "wolfram", "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
o = loadOccurrences[5229230, "sample"];
asserts = {
  AssociationQ[o], Sort@Keys[o] === Sort@{"lat","lon","month","year","count"},
  Equal @@ (Length /@ Values[o]), Length[o["lat"]] > 100,
  Min[o["month"]] >= 1 && Max[o["month"]] <= 12,
  Min[o["lat"]] >= -90 && Max[o["lat"]] <= 90};
Print["PASS: ", Count[asserts, True], "/", Length[asserts]];
If[! And @@ asserts, Print[Position[asserts, False]]; Exit[1]];
