# Trackmania-racing-line
Racing line for Trackmania


As of right now - 31/10/2026 the line only works on flat straight track maps with some exceptions

# Racing Line (Openplanet plugin for Trackmania)

Works out a racing line from the map's geometry when you load a track, then draws it on the road, coloured by what you should be doing.

- **Green**: accelerate
- **Yellow**: hold at the grip limit (cornering flat out)
- **Red**: brake

# -- Requires Openplanet software to work and unless it gets verified also requires a club susbscription :( sorry --

 Install

1. Go to `Documents\OpenplanetNext\Plugins\`.
2. Copy this whole `RacingLine` folder in. You should end up with `Plugins\RacingLine\info.toml`.
3. In game, press **F3** to open the Openplanet overlay.
4. Go to **Developer → Signature Mode** and pick a mode that allows unsigned plugins.
5. Go to **Developer → Reload plugin** and pick **Racing Line**. Restarting the game also works.
6. Load any map. The info window shows progress, then the line appears.

If it fails to compile, the reason is in **Openplanet → Log**. It names the file and line number.

 How it works

1. **Scans the map.** It reads every block (grid position) and item (exact position). It also finds the start, the checkpoints and the finish.
2. **Builds a track graph.** Each occupied 32×32×8 m cell becomes a node. Nearby cells are linked, including across small gaps so jumps are possible.
3. **Finds the route.** It runs Dijkstra from the start and from every checkpoint. Checkpoints in TM2020 can be taken in any order, so it orders them using nearest-neighbour followed by 2-opt.
4. **Builds a centreline.** It traces the path through the cells and resamples it every few metres. Smoothing then turns the blocky cell path into a plausible road centre.
5. **Minimum-curvature optimisation.** Each point may slide sideways within the road width, and it is pinned tighter at checkpoints. The solver minimises the sum of squared second differences, which roughly means total curvature. This produces outside–apex–outside lines.
6. **Builds a speed profile.** Each point's corner speed limit is `sqrt(grip / curvature)`. A forward pass applies acceleration from a standstill, with uphill and downhill gravity. A backward pass applies braking. Wherever braking limits the speed, the line turns red.

 Tuning (Openplanet settings → Racing Line)

- **Road half-width**: lower it if the line runs off narrow roads, raise it for wide platforms.
- **Corner grip / Acceleration / Braking**: these change where yellow and red appear. Lower grip on dirt or ice maps.
- **Ignore blocks whose name contains**: stops decoration or scenery being treated as road.
- **Max gap**: higher values let the route find jumps, but also let it cut between separate roads.
- **Height above road**: use this if the line floats or sinks. Auto-calibration also fixes height when your car spawns.

After changing the track-model settings, press **Recalculate**.

 Known limitations

This is a real geometric solver. Trackmania isn't a normal racing game, though, so expect these:

- **Free-placed blocks** are ignored, because they have no grid position. Items are used.
- **Road width is guessed.** The mod can't see the real road edges, only which cells contain something, so it assumes a fixed width.
- **Parallel or stacked roads** close together can make the route cut across between them.
- **Surfaces, drifts, speed-slides, wall rides, loops, boosters and reactors** aren't modelled. The physics is a simple grip/accel/brake model.
- **Linked checkpoints** are each treated as a separate required checkpoint.
- **The line draws over walls** because it's an overlay.
