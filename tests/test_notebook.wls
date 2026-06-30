#!/usr/bin/env wolframscript
(* test_notebook.wls — structural checks on the built community notebook.
   Verifies a Title cell, NO "How to cite" section, >= 8 Section headers,
   an embedded hero animation (or a large .nb), and Cornell's required
   acknowledgement string. *)

nb = FileNameJoin[{DirectoryName[$InputFileName, 2], "community", "bird_migration.nb"}];
If[! FileExistsQ[nb], Print["FAIL: no notebook"]; Exit[1]];
e = Import[nb];
titleOk = Length[Cases[e, Cell[_, "Title", ___], Infinity]] >= 1;
noCite  = Cases[e, Cell[t_String, ___] /; StringContainsQ[t, "How to cite", IgnoreCase -> True] :> t, Infinity] === {};
secOk   = Length[Cases[e, Cell[_, "Section", ___], Infinity]] >= 8;
heroOk  = Length[Cases[e, _AnimatedImage, Infinity]] >= 1 || FileByteCount[nb] > 2*10^6;
ackOk   = Length[Cases[e, Cell[t_, ___] /; StringContainsQ[ToString[t], "Cornell Lab of Ornithology"] :> t, Infinity]] >= 1;
Print["title:", titleOk, " noCite:", noCite, " sections:", secOk, " hero:", heroOk, " ack:", ackOk];
If[! (titleOk && noCite && secOk && heroOk && ackOk), Exit[1]];
Print["PASS notebook"];
