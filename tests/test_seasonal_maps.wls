#!/usr/bin/env wolframscript
dir = FileNameJoin[{DirectoryName[$InputFileName, 2], "docs", "images"}];
files = FileNameJoin[{dir, "seasonal_" <> ToString[#] <> ".png"}] & /@ {5229230,5228676,2481765};
ok = AllTrue[files, FileExistsQ[#] && FileByteCount[#] > 30000 &];
Print[If[ok, "PASS seasonal maps", "FAIL"]]; If[! ok, Exit[1]];
