#!/usr/bin/env wolframscript
(* hero.wls -- THE hero animation for the bird-migration post.
   A slowly breathing dark globe; each species' monthly population centroid
   glides along its great-circle migration loop as a glowing comet, over a
   faint full-year route, with a synchronized month timeline + legend. *)

Get[FileNameJoin[{DirectoryName[$InputFileName], "fetcher_common.wl"}]];

(* ---- load PRIMARY per-flyway tracks (drop Missing months) ---- *)
loadTrack[key_] := Module[{d},
  d = Rest@Import[
     FileNameJoin[{$repoRoot, "data", "centroids_" <> ToString[key] <> ".csv"}], "CSV"];
  Select[d, NumberQ[#[[2]]] && NumberQ[#[[3]]] &]];

keys  = {5229230, 5228676, 2481765};
cols  = <|5229230 -> RGBColor[1, 0.45, 0.28], 5228676 -> RGBColor[0.4, 0.92, 1.0],
          2481765 -> RGBColor[1, 0.86, 0.30]|>;
names = <|5229230 -> "Arctic tern", 5228676 -> "Common swift", 2481765 -> "Red knot"|>;
tracks = Association[# -> loadTrack[#] & /@ keys];
monName = DateString[{2020, #, 1}, "MonthName"] &;

(* ---- great-circle (spherical) interpolation between two lat/lon points ---- *)
toVec[{lat_, lon_}] := Module[{a = lat Degree, b = lon Degree},
  {Cos[a] Cos[b], Cos[a] Sin[b], Sin[a]}];
toLatLon[{x_, y_, z_}] := {ArcSin[Clip[z, {-1, 1}]]/Degree, ArcTan[x, y]/Degree};
slerp[p0_, p1_, t_] := Module[{v0 = toVec[p0], v1 = toVec[p1], om, s},
  om = ArcCos[Clip[v0 . v1, {-1, 1}]];
  s = Sin[om];
  toLatLon@If[s < 1.*^-6, (1 - t) v0 + t v1,
    (Sin[(1 - t) om] v0 + Sin[t om] v1)/s]];

(* ---- build a dense closed annual loop (great-circle) per species ---- *)
nSub = 1;                         (* sub-frames per month segment      *)
nFrames = 12 nSub;                (* total animation frames (=12)      *)
denseLoop[key_] := Module[{pts = (#[[{2, 3}]] & /@ tracks[key]), n, loop},
  n = Length[pts];
  loop = Append[pts, First[pts]];  (* close Dec -> Jan                 *)
  Flatten[Table[
    Table[slerp[loop[[i]], loop[[i + 1]], t], {t, 0, 1 - 1/nSub, 1/nSub}],
    {i, n}], 1]];
loops = Association[# -> denseLoop[#] & /@ keys];   (* each length nFrames *)

(* ---- visuals ---- *)
tailLen = 9;                       (* comet tail length (frames)        *)
gp[ll_] := GeoPosition[ll];

cometTrail[key_, f_] := Module[{L = loops[key], col = cols[key], idxs, seg, op, w},
  (* faint full-year route always visible *)
  idxs = Range[Length[L]];
  Flatten@{
    {col, Opacity[0.22], Thickness[0.0035],
     Line[gp /@ Append[L, First[L]]]},
    (* glowing comet tail: recent positions, brightening toward the head *)
    Table[
      seg = {L[[Mod[f - k - 1, nFrames] + 1]], L[[Mod[f - k, nFrames] + 1]]};
      op = (1 - k/tailLen);
      {  (* soft outer glow *)
       {col, Opacity[0.10 op], CapForm["Round"], Thickness[0.018 op + 0.004],
        Line[gp /@ seg]},
        (* mid stroke *)
       {col, Opacity[0.28 op], CapForm["Round"], Thickness[0.009 op + 0.003],
        Line[gp /@ seg]},
        (* bright core *)
       {Lighter[col, 0.25], Opacity[0.5 + 0.45 op], CapForm["Round"],
        Thickness[0.004 op + 0.0018], Line[gp /@ seg]}},
      {k, tailLen, 1, -1}]}];

marker[key_, f_] := Module[{p = gp[loops[key][[Mod[f, nFrames] + 1]]], col = cols[key]},
  {{col, Opacity[0.22], PointSize[0.034], Point[p]},
   {col, Opacity[0.45], PointSize[0.020], Point[p]},
   {Lighter[col, 0.4], PointSize[0.011], Point[p]}}];

(* one globe frame f = 0..nFrames-1; gentle breathing rotation, seamless loop *)
globe[f_] := Module[{spin = 26 Sin[2 Pi f/nFrames]},
  GeoGraphics[
    Flatten[{cometTrail[#, f], marker[#, f]} & /@ keys],
    GeoRange -> "World",
    GeoProjection -> {"Orthographic", "Centering" -> {18, -26 + spin}},
    (* real-world textured relief globe -- tiles download at render time *)
    GeoBackground -> "ReliefMap",
    GeoGridLines -> Automatic,
    GeoGridLinesStyle -> Directive[GrayLevel[0.9], Opacity[0.10]],
    ImageSize -> {580, 580}, Background -> Black, ImagePadding -> 2]];

(* synchronized month label (nearest month to current phase) *)
curMonth[f_] := Mod[Round[f/nSub], 12] + 1;

(* compact month-timeline playhead, synchronized to the globe *)
timeline[f_] := Module[{phase = f/nSub, x},
  x = phase/12;
  Graphics[{
     {GrayLevel[0.25], Thickness[0.006], Line[{{0, 0}, {1, 0}}]},
     Table[{GrayLevel[0.45], PointSize[0.012], Point[{(m - 1)/12, 0}]}, {m, 12}],
     {White, PointSize[0.03], Point[{x, 0}]},
     {GrayLevel[0.6], Opacity[0.6], Point[{x, 0}]}},
   ImageSize -> {560, 26}, PlotRange -> {{-0.03, 1.03}, {-0.5, 0.5}},
   Background -> Black, AspectRatio -> Full]];

legend = Row[Riffle[
   (Row[{Graphics[{cols[#], Disk[]}, ImageSize -> 13], "  ",
         Style[names[#], White, 13, FontFamily -> "Helvetica"]}] & /@ keys),
   Spacer[26]]];

title[f_] := Style[monName[curMonth[f]], White, 23, FontFamily -> "Helvetica",
   FontWeight -> "Light"];

compose[f_] := Rasterize[
   Column[{
      Style[title[f], LineSpacing -> {0, 0}],
      globe[f],
      timeline[f],
      Pane[legend, Alignment -> Center]},
     Background -> Black, Alignment -> Center, Spacings -> {0, 0.45}],
   Background -> Black, ImageSize -> 600];

Print["rendering ", nFrames, " frames ..."];
frames = Table[compose[f], {f, 0, nFrames - 1}];
frames = ColorQuantize[#, 240, Dithering -> False] & /@ frames;

(* representative middle frame (nearest month 7) for visual QC *)
Export[FileNameJoin[{$repoRoot, "docs", "images", "hero_frame_preview.png"}],
   frames[[Position[curMonth /@ Range[0, nFrames - 1], 7][[1, 1]]]], "PNG"];

Export[FileNameJoin[{$repoRoot, "docs", "images", "hero.gif"}],
   AnimatedImage[frames, FrameRate -> 12, AnimationRepetitions -> Infinity], "GIF"];
Export[FileNameJoin[{$repoRoot, "docs", "images", "hero.mp4"}],
   AnimatedImage[frames, FrameRate -> 12], "MP4"];

Print["hero frames: ", Length[frames], "  gif bytes: ",
   FileByteCount[FileNameJoin[{$repoRoot, "docs", "images", "hero.gif"}]]];
