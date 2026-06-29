#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName, 2], "wolfram", "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
(* spherical centroid of two points either side of the antimeridian must land
   near +/-180, NOT near 0 (the naive-mean failure). *)
c = sphericalCentroid[{0., 0.}, {170., -170.}, {1., 1.}];
near180 = Abs[Abs[c[[2]]] - 180.] < 1.0;
cs = monthlyCentroids[5229230, "sample"];
asserts = {near180, Dimensions[cs] === {12, 3},
  AllTrue[cs[[All,2]], -90 <= # <= 90 &],
  centroidPathLengthKm[cs] > 1000,
  FileExistsQ[FileNameJoin[{$repoRoot,"data","centroids_5229230.csv"}]]};
Print["PASS: ", Count[asserts, True], "/", Length[asserts]];
If[! And @@ asserts, Print[Position[asserts, False]]; Exit[1]];
