#!/usr/bin/env wolframscript
(* figures.wls — GBIF-derived static figures ONLY (CC BY 4.0, publishable)
   Produces: centroid-track globes per species + path-length bar chart.
   NO Status & Trends overlay — compliance requirement. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];

img = FileNameJoin[{$repoRoot, "docs", "images"}];

trackName = <|
  5229230 -> "Atlantic basin",
  5228676 -> "Afro-Palearctic",
  2481765 -> "Americas flyway"
|>;

cols = <|
  5229230 -> RGBColor[1, 0.4, 0.25],
  5228676 -> RGBColor[0.2, 0.55, 0.95],
  2481765 -> RGBColor[0.9, 0.7, 0.1]
|>;

loadTrack[key_] := Select[
  Rest @ Import[FileNameJoin[{$repoRoot, "data", "centroids_" <> ToString[key] <> ".csv"}], "CSV"],
  NumberQ[#[[2]]] && NumberQ[#[[3]]] &
];

(* --- centroid-track globes, one per species --- *)
Do[
  Module[{
    sp  = Lookup[First @ Select[$speciesList, #["key"] == key &], "common"],
    cs  = loadTrack[key],
    g
  },
    g = GeoGraphics[{
      cols[key], Thick,
      GeoPath[GeoPosition[{#[[2]], #[[3]]}] & /@ cs],
      Table[
        {cols[key],
         Disk[GeoPosition[{cs[[m, 2]], cs[[m, 3]]}], Quantity[120, "Kilometers"]]},
        {m, Length[cs]}
      ],
      Table[
        Text[Style[ToString[Round @ cs[[m, 1]]], 9, White, Bold],
             GeoPosition[{cs[[m, 2]], cs[[m, 3]]}]],
        {m, Length[cs]}
      ]
    },
      GeoRange       -> "World",
      GeoProjection  -> {"Orthographic",
                         "Centering" -> {Mean[cs[[All, 2]]], Mean[cs[[All, 3]]]}},
      GeoBackground  -> "ReliefMap",
      PlotLabel      -> Style[sp <> " \[LongDash] monthly centroid (" <> trackName[key] <> ")", 14],
      ImageSize      -> 760
    ];
    Export[FileNameJoin[{img, "centroid_track_" <> ToString[key] <> ".png"}], g, "PNG"];
    Print["wrote centroid_track_", key];
  ],
  {key, {5229230, 5228676, 2481765}}
];

(* --- path-length bar chart: defensible primary tracks only ---
   Exclude knot-global "BROKEN" row — it pools hemispheres and overstates distance. *)
pl   = Rest @ Import[FileNameJoin[{$repoRoot, "data", "path_lengths.csv"}], "CSV"];
prim = Select[pl, ! StringContainsQ[ToString[#[[3]]], "global", IgnoreCase -> True] &];

labels = MapThread[#1 <> "\n(" <> #2 <> ")" &,
                   {prim[[All, 2]], ToString /@ prim[[All, 3]]}];

(* Use per-species colours; fall back gracefully if a key is missing *)
barCols = Lookup[cols, prim[[All, 1]], GrayLevel[0.6]];

Export[FileNameJoin[{img, "path_lengths.png"}],
  BarChart[prim[[All, 4]],
    ChartLabels -> (Style[#, 10] & /@ labels),
    BarOrigin   -> Left,
    ChartStyle  -> barCols,
    PlotLabel   -> Style[
      "Annual centroid displacement (km) \[LongDash] not individual journey distance", 13],
    ImageSize   -> 780,
    AspectRatio -> 0.5
  ],
  "PNG"
];
Print["figures done"];
