#!/usr/bin/env wolframscript
(* flock.wls — many birds streaming along each flyway (item 16).

   Instead of a single centroid dot, we release a flock of birds that glide
   along each species' migration loop: the monthly centroids are resampled
   along great circles into a smooth closed path, then N birds are spaced
   around it with small jitter and advanced frame by frame. Reliable vector
   basemap (no map tiles). Output: docs/images/flock.gif / .mp4. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];
img = FileNameJoin[{$repoRoot, "docs", "images"}];

cols = <|5229230 -> RGBColor[1, 0.45, 0.25], 5228676 -> RGBColor[0.35, 0.9, 1.0],
         2481765 -> RGBColor[1, 0.82, 0.2]|>;
names = <|5229230 -> "Arctic tern", 5228676 -> "Common swift", 2481765 -> "Red knot"|>;
keys = {5229230, 5228676, 2481765};
loadTrack[key_] := Select[Rest@Import[FileNameJoin[{$repoRoot, "data",
   "centroids_" <> ToString[key] <> ".csv"}], "CSV"], NumberQ[#[[2]]] && NumberQ[#[[3]]] &];

(* unit-vector slerp between two {lat,lon} points *)
toXYZ[{la_, lo_}] := {Cos[la Degree] Cos[lo Degree], Cos[la Degree] Sin[lo Degree], Sin[la Degree]};
toLL[{x_, y_, z_}] := {ArcSin[z]/Degree, ArcTan[x, y]/Degree};
slerp[p_, q_, t_] := Module[{u = toXYZ[p], v = toXYZ[q], om},
  om = ArcCos[Clip[u.v, {-1, 1}]];
  If[om < 1*^-6, toLL[u],
    toLL[(Sin[(1 - t) om] u + Sin[t om] v)/Sin[om]]]];

(* dense closed path of {lat,lon} from the 12 monthly centroids *)
densePath[key_, perSeg_: 12] := Module[{tr = loadTrack[key], pts},
  pts = {#[[2]], #[[3]]} & /@ tr;
  Flatten[Table[
     slerp[pts[[i]], pts[[Mod[i, Length[pts]] + 1]], t],
     {i, Length[pts]}, {t, 0, 1 - 1/perSeg, 1/perSeg}], 1]];
paths = Association[# -> densePath[#] & /@ keys];

SeedRandom[7];
nBirds = 16;
(* per-species, per-bird: a phase offset (0..1) and a small lat/lon jitter *)
phases = Association[# -> Sort@RandomReal[{0, 1}, nBirds] & /@ keys];
jit = Association[# -> RandomReal[{-1.6, 1.6}, {nBirds, 2}] & /@ keys];

frame[fr_, nFrames_] := Module[{prog = fr/nFrames},
  GeoGraphics[
    Flatten@Table[
      With[{path = paths[k], L = Length[paths[k]]},
       {(* faint full-year route *)
        {cols[k], Opacity[0.25], Thickness[0.0035], GeoPath[path]},
        (* the flock *)
        Table[
         With[{idx = Mod[Round[(phases[k][[i]] + prog) L], L] + 1},
          With[{pos = path[[idx]] + jit[k][[i]]},
           {cols[k], Opacity[0.35], PointSize[0.013], Point[GeoPosition[pos]],
            cols[k], PointSize[0.0065], Point[GeoPosition[pos]]}]],
         {i, nBirds}]}],
      {k, keys}],
    GeoRange -> "World", GeoProjection -> "Robinson", GeoBackground -> Automatic,
    ImageSize -> {960, 520},
    PlotLabel -> Style["Migration in motion \[LongDash] flocks streaming along each flyway", 14]]];

nFrames = 24;
Print["rendering ", nFrames, " flock frames ..."];
frames = Table[ColorQuantize[Rasterize[frame[fr, nFrames], ImageResolution -> 92], 200], {fr, 0, nFrames - 1}];
Export[FileNameJoin[{img, "flock.gif"}],
   AnimatedImage[frames, FrameRate -> 12, AnimationRepetitions -> Infinity], "GIF"];
Export[FileNameJoin[{img, "flock.mp4"}], AnimatedImage[frames, FrameRate -> 12], "MP4"];
Print["wrote flock.gif (", FileByteCount[FileNameJoin[{img, "flock.gif"}]], " B), ",
   Length[frames], " frames"];
Print["flock: OK"];
