#!/usr/bin/env wolframscript
f = FileNameJoin[{DirectoryName[$InputFileName, 2], "data", "gbif_dois.json"}];
If[! FileExistsQ[f], Print["FAIL: no gbif_dois.json"]; Exit[1]];
d = Import[f, "RawJSON"];
ok = AllTrue[{"5229230","5228676","2481765"},
   KeyExistsQ[d, #] && StringContainsQ[d[#]["doi"], "doi.org"] &];
Print[If[ok, "PASS dois", "FAIL doi content"]]; If[! ok, Exit[1]];
