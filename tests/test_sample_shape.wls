dir = FileNameJoin[{DirectoryName[$InputFileName, 2], "data", "raw", "sample"}];
files = FileNames["occ_*.csv", dir];
If[Length[files] < 3, Print["FAIL: expected 3 sample files, got ", Length[files]]; Exit[1]];
Do[ With[{d = Import[f, "CSV"]},
   If[First[d] =!= {"lat","lon","month","year","count"}, Print["FAIL header ", f]; Exit[1]];
   If[Length[d] < 200, Print["FAIL too few rows ", f]; Exit[1]];
   If[! (Min[#] >= 1 && Max[#] <= 12 &@ (Rest[d][[All,3]])), Print["FAIL month range ", f]; Exit[1]];
 ], {f, files}];
Print["PASS sample shape: ", Length[files], " files"];
