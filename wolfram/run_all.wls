#!/usr/bin/env wolframscript
root = DirectoryName[$InputFileName];
repo = ParentDirectory[root];
src = If[FileExistsQ[FileNameJoin[{repo, "data", "gbif_dois.json"}]], "full", "sample"];
Print["=== run_all source = ", src, " ==="];
run[s_] := (Print["--- ", s, " ---"];
   If[Run["/usr/local/bin/wolframscript -file " <> FileNameJoin[{root, s}] <>
        If[s === "centroids.wls", " " <> src, ""]] =!= 0,
      Print["  WARNING: ", s, " returned nonzero"]));
run["centroids.wls"];
run["seasonal_maps.wls"];
If[FileExistsQ[FileNameJoin[{root, "figures.wls"}]], run["figures.wls"]];
run["hero.wls"];
Print["=== run_all done (", src, ") ==="];
