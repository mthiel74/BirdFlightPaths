#!/usr/bin/env wolframscript
g = FileNameJoin[{DirectoryName[$InputFileName, 2], "docs", "images", "hero.gif"}];
ok = FileExistsQ[g] && FileByteCount[g] > 100000 &&
     Length[Import[g, {"GIF", "ImageList"}]] >= 12;
Print[If[ok, "PASS hero (" <> ToString[FileByteCount[g]] <> " bytes, " <>
   ToString[Length[Import[g, {"GIF","ImageList"}]]] <> " frames)", "FAIL"]];
If[! ok, Exit[1]];
