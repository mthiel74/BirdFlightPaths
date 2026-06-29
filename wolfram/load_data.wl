(* ::Package:: *)
loadOccurrences[key_Integer, source_:"sample"] := Module[{dir, f, d, cols},
  dir = If[source === "full",
    FileNameJoin[{$repoRoot, "data", "raw"}],
    FileNameJoin[{$repoRoot, "data", "raw", "sample"}]];
  f = FileNameJoin[{dir, "occ_" <> ToString[key] <> ".csv"}];
  If[! FileExistsQ[f], Print["MISSING ", f]; Abort[]];
  d = Rest@Import[f, "CSV"];                 (* drop header *)
  d = Select[d, Length[#] >= 5 && NumberQ[#[[1]]] && NumberQ[#[[2]]] &];
  cols = Transpose[d];
  <|"lat"->cols[[1]], "lon"->cols[[2]], "month"->Round@cols[[3]],
    "year"->Round@cols[[4]], "count"->(If[NumberQ[#], #, 1]& /@ cols[[5]])|>];
