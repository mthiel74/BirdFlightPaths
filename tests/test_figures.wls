#!/usr/bin/env wolframscript
(* test_figures.wls — verify centroid-track globes and path-length bar chart exist *)
img = FileNameJoin[{DirectoryName[$InputFileName,2],"docs","images"}];
need = Join[FileNameJoin[{img,"centroid_track_"<>ToString[#]<>".png"}]&/@{5229230,5228676,2481765},
            {FileNameJoin[{img,"path_lengths.png"}]}];
ok = AllTrue[need, (FileExistsQ[#] && FileByteCount[#] > 10000) &];
Print[If[ok,"PASS figures","FAIL"]]; If[!ok, Exit[1]];
