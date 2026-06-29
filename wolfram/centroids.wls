#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
src = If[Length[$ScriptCommandLine] > 1, $ScriptCommandLine[[2]], "sample"];
rows = Table[
  Module[{cs = monthlyCentroids[sp["key"], src]},
    {sp["key"], sp["common"], centroidPathLengthKm[cs]}], {sp, $speciesList}];
Export[FileNameJoin[{$repoRoot, "data", "path_lengths.csv"}],
  Prepend[rows, {"key","common","km"}], "CSV"];
Print["path lengths (km): ", rows[[All, {2,3}]]];
