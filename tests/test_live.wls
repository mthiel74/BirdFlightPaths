#!/usr/bin/env wolframscript
dir = FileNameJoin[{DirectoryName[$InputFileName, 2], "data"}];
img = FileNameJoin[{DirectoryName[$InputFileName, 2], "docs", "images"}];
csvOk = AllTrue[{5229230,5228676,2481765},
  FileExistsQ[FileNameJoin[{dir, "live_" <> ToString[#] <> ".csv"}]] &];
imgOk = AllTrue[{5229230,5228676,2481765},
  FileExistsQ[FileNameJoin[{img, "live_" <> ToString[#] <> ".png"}]] &];
(* privacy: CSV header must be exactly lat,lon,obsDt (no locName) *)
hdrOk = AllTrue[{5229230,5228676,2481765},
  First@Import[FileNameJoin[{dir,"live_"<>ToString[#]<>".csv"}], "CSV"] === {"lat","lon","obsDt"} &];
Print[If[csvOk && imgOk && hdrOk, "PASS live layer", "FAIL"]]; If[! (csvOk && imgOk && hdrOk), Exit[1]];
