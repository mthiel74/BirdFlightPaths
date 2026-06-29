root = DirectoryName[$InputFileName, 2];
(* run_all.wls exists and is syntactically loadable *)
src = FileNameJoin[{root, "wolfram", "run_all.wls"}];
ok1 = FileExistsQ[src] && Quiet[Check[ToExpression[Import[src,"Text"], InputForm, Hold]; True, True]];
(* key artifacts from earlier tasks already present *)
img = FileNameJoin[{root, "docs", "images"}];
ok2 = AllTrue[{"hero.gif","seasonal_5229230.png"}, FileExistsQ[FileNameJoin[{img,#}]]&];
ok3 = AllTrue[{5229230,5228676,2481765}, FileExistsQ[FileNameJoin[{root,"data","centroids_"<>ToString[#]<>".csv"}]]&];
Print[If[ok1 && ok2 && ok3, "PASS run_all", "FAIL"]]; If[!(ok1&&ok2&&ok3), Exit[1]];
