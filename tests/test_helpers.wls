#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName,2],"community","birdflightpaths_helpers.wl"}]];
asserts = {
  Length[monthNames] === 12,
  ColorQ[speciesColors[5229230]],
  speciesName[5228676] === "Common swift",
  ListQ[sphericalCentroid[{0.,0.},{170.,-170.},{1.,1.}]],
  MatchQ[sphericalCentroid[{0.,0.},{0.,180.},{1.,1.}], _Missing]
};
Print["PASS: ", Count[asserts,True], "/", Length[asserts]];
If[! And @@ asserts, Print[Position[asserts,False]]; Exit[1]];
