#!/usr/bin/env wolframscript
Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
Get[FileNameJoin[{$repoRoot, "wolfram", "load_data.wl"}]];
monNames = DateString[{2020, #, 1}, "MonthNameShort"] & /@ Range[12];

(* Guard empty months: GeoHistogram errors on empty input; show a blank dark
   panel so the 3x4 Grid is always complete. GeoPosition wrapper ensures WL
   interprets plain {lat,lon} pairs correctly across all version / OS combos. *)
panel[key_, src_] := Module[{o = loadOccurrences[key, src]},
  Grid[Partition[Table[
    Module[{idx = Flatten@Position[o["month"], m], pts},
      pts = GeoPosition /@ Transpose[{o["lat"][[idx]], o["lon"][[idx]]}];
      If[pts === {},
        Graphics[{GrayLevel[0.15], Rectangle[{0,0},{4,3}]},
                 PlotLabel -> Style[monNames[[m]], White], ImageSize -> 230],
        GeoHistogram[pts, Quantity[750, "Kilometers"],
          GeoRange -> "World", GeoProjection -> "Robinson",
          ColorFunction -> "TemperatureMap", PlotLabel -> monNames[[m]],
          GeoBackground -> GrayLevel[0.15], ImageSize -> 230,
          PlotLegends -> None]]],
    {m, 12}], 4]]];

Do[ Export[FileNameJoin[{$repoRoot, "docs", "images",
             "seasonal_" <> ToString[sp["key"]] <> ".png"}],
      panel[sp["key"], "sample"], "PNG", ImageResolution -> 120];
    Print["wrote seasonal_", sp["key"]], {sp, $speciesList}];
