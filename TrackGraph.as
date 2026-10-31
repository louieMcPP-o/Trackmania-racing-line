// Step 1 & 2: read the map and turn it into a graph of drivable cells.

class ScanResult {
    array<CellEntry@> cells;
    array<Waypoint@> starts;
    array<Waypoint@> cps;
    array<Waypoint@> finishes;   // includes StartFinish (multilap)
    int blocks = 0;
    int items = 0;
    int skippedFree = 0;
    bool hasStartFinish = false;
}

array<string> ParseIgnoreList() {
    array<string> outList;
    auto parts = S_IgnoreNames.Split(",");
    for (uint i = 0; i < parts.Length; i++) {
        string s = parts[i].Trim().ToLower();
        if (s.Length > 0) outList.InsertLast(s);
    }
    return outList;
}

bool IsIgnored(const string &in name, const array<string> &in ignore) {
    string lower = name.ToLower();
    for (uint i = 0; i < ignore.Length; i++) {
        if (lower.Contains(ignore[i])) return true;
    }
    return false;
}

void AddWaypoint(ScanResult@ r, const string &in tag, vec3 p) {
    if (tag == "Spawn") {
        r.starts.InsertLast(Waypoint(WpKind::Start, p));
    } else if (tag == "Goal") {
        r.finishes.InsertLast(Waypoint(WpKind::Finish, p));
    } else if (tag == "StartFinish") {
        r.hasStartFinish = true;
        r.starts.InsertLast(Waypoint(WpKind::StartFinish, p));
    } else if (tag.Contains("Checkpoint")) {
        r.cps.InsertLast(Waypoint(WpKind::Checkpoint, p));
    }
}

// Runs in a single frame (no yields) so the map can't be unloaded mid-scan.
ScanResult@ ScanMap(CGameCtnChallenge@ map) {
    ScanResult@ r = ScanResult();
    auto ignore = ParseIgnoreList();

    for (uint i = 0; i < map.Blocks.Length; i++) {
        auto b = map.Blocks[i];
        if (b is null) continue;
        // Free-placed blocks don't have a usable grid coordinate.
        if (b.Coord.x > 1000 || b.Coord.z > 1000 || b.Coord.y > 1000) {
            r.skippedFree++;
            continue;
        }
        vec3 p = BlockCentre(b.Coord);
        bool isWp = b.WaypointSpecialProperty !is null;
        if (isWp) AddWaypoint(r, b.WaypointSpecialProperty.Tag, p);
        if (!isWp && IsIgnored(b.DescId.GetName(), ignore)) continue;
        r.cells.InsertLast(CellEntry(int(b.Coord.x), int(b.Coord.y), int(b.Coord.z), p));
        r.blocks++;
    }

    if (S_IncludeItems) {
        for (uint i = 0; i < map.AnchoredObjects.Length; i++) {
            auto it = map.AnchoredObjects[i];
            if (it is null) continue;
            string name = it.ItemModel is null ? "" : it.ItemModel.IdName;
            vec3 p = it.AbsolutePositionInMap;
            bool isWp = it.WaypointSpecialProperty !is null;
            if (isWp) AddWaypoint(r, it.WaypointSpecialProperty.Tag, p);
            if (!isWp && IsIgnored(name, ignore)) continue;
            r.cells.InsertLast(CellEntry(CellX(p.x), CellY(p.y), CellZ(p.z), p));
            r.items++;
        }
    }
    return r;
}

class TrackGraph {
    array<vec3> pos;
    array<array<int>> adj;
    array<array<float>> cost;
    array<int> grid;
    int minX, minY, minZ, sx, sy, sz;

    uint Count() { return pos.Length; }

    int At(int x, int y, int z) {
        x -= minX; y -= minY; z -= minZ;
        if (x < 0 || y < 0 || z < 0 || x >= sx || y >= sy || z >= sz) return -1;
        return grid[(x * sy + y) * sz + z];
    }

    // Builds nodes (one per occupied 32x8x32 cell) and edges between nearby cells.
    void Build(ScanResult@ r, LineSolver@ solver) {
        if (r.cells.Length == 0) return;
        minX = minY = minZ = 1000000;
        int maxX = -1000000, maxY = -1000000, maxZ = -1000000;
        for (uint i = 0; i < r.cells.Length; i++) {
            auto c = r.cells[i];
            minX = Math::Min(minX, c.x); maxX = Math::Max(maxX, c.x);
            minY = Math::Min(minY, c.y); maxY = Math::Max(maxY, c.y);
            minZ = Math::Min(minZ, c.z); maxZ = Math::Max(maxZ, c.z);
        }
        sx = maxX - minX + 1; sy = maxY - minY + 1; sz = maxZ - minZ + 1;
        grid.Resize(sx * sy * sz);
        for (uint i = 0; i < grid.Length; i++) grid[i] = -1;

        // Average every contribution in a cell, so items pull nodes to their real positions.
        array<vec3> sums;
        array<int> counts;
        for (uint i = 0; i < r.cells.Length; i++) {
            auto c = r.cells[i];
            int gi = ((c.x - minX) * sy + (c.y - minY)) * sz + (c.z - minZ);
            int n = grid[gi];
            if (n < 0) {
                n = int(sums.Length);
                grid[gi] = n;
                sums.InsertLast(vec3());
                counts.InsertLast(0);
            }
            sums[n] = sums[n] + c.pos;
            counts[n] = counts[n] + 1;
        }
        pos.Resize(sums.Length);
        for (uint i = 0; i < sums.Length; i++) pos[i] = sums[i] * (1.0f / float(counts[i]));

        // Recover each node's cell coordinate from the grid.
        array<int> nx(pos.Length), ny(pos.Length), nz(pos.Length);
        for (int x = 0; x < sx; x++)
            for (int y = 0; y < sy; y++)
                for (int z = 0; z < sz; z++) {
                    int n = grid[(x * sy + y) * sz + z];
                    if (n >= 0) { nx[n] = x + minX; ny[n] = y + minY; nz[n] = z + minZ; }
                }

        adj.Resize(pos.Length);
        cost.Resize(pos.Length);
        int G = S_MaxGap;
        for (uint i = 0; i < pos.Length; i++) {
            for (int dx = -G; dx <= G; dx++)
            for (int dz = -G; dz <= G; dz++)
            for (int dy = -3; dy <= 3; dy++) {
                if (dx == 0 && dy == 0 && dz == 0) continue;
                int j = At(nx[i] + dx, ny[i] + dy, nz[i] + dz);
                if (j <= int(i)) continue; // add each edge once, both directions
                float d = Len3(pos[j] - pos[i]);
                float penalty = 1.0f;
                int hstep = Math::Max(Absi(dx), Absi(dz));
                if (hstep > 1) penalty += 2.0f * float(hstep - 1); // jumping a gap
                if (Absi(dy) > 2) penalty += 0.5f;
                float w = d * penalty;
                adj[i].InsertLast(j); cost[i].InsertLast(w);
                adj[j].InsertLast(i); cost[j].InsertLast(w);
            }
            if (i % 300 == 0) {
                solver.progress = 0.10f + 0.15f * float(i) / float(pos.Length);
                solver.Yield();
            }
        }
    }

    int NearestNode(vec3 p) {
        int cx = CellX(p.x), cy = CellY(p.y), cz = CellZ(p.z);
        int best = -1;
        float bestD = INF;
        for (int dx = -1; dx <= 1; dx++)
        for (int dz = -1; dz <= 1; dz++)
        for (int dy = -2; dy <= 2; dy++) {
            int n = At(cx + dx, cy + dy, cz + dz);
            if (n < 0) continue;
            float d = Len3(pos[n] - p);
            if (d < bestD) { bestD = d; best = n; }
        }
        if (best >= 0) return best;
        for (uint i = 0; i < pos.Length; i++) {
            float d = Len3(pos[i] - p);
            if (d < bestD) { bestD = d; best = int(i); }
        }
        return best;
    }

    void Dijkstra(int src, array<float>@ dist, array<int>@ prev, LineSolver@ solver) {
        dist.Resize(pos.Length);
        prev.Resize(pos.Length);
        for (uint i = 0; i < pos.Length; i++) { dist[i] = INF; prev[i] = -1; }
        if (src < 0) return;
        MinHeap heap;
        dist[src] = 0;
        heap.Push(src, 0);
        int pops = 0;
        while (heap.Count() > 0) {
            float d;
            int u = heap.Pop(d);
            if (d > dist[u]) continue;
            auto@ nbrs = adj[u];
            auto@ ws = cost[u];
            for (uint k = 0; k < nbrs.Length; k++) {
                int v = nbrs[k];
                float nd = d + ws[k];
                if (nd < dist[v]) {
                    dist[v] = nd;
                    prev[v] = u;
                    heap.Push(v, nd);
                }
            }
            if (++pops % 3000 == 0) solver.Yield();
        }
    }

    // Node path src -> dst using a prev array produced by Dijkstra(src).
    array<int> PathTo(int dst, array<int>@ prev) {
        array<int> rev;
        int cur = dst;
        int guard = 0;
        while (cur >= 0 && guard++ < int(pos.Length) + 2) {
            rev.InsertLast(cur);
            cur = prev[cur];
        }
        array<int> path;
        for (int i = int(rev.Length) - 1; i >= 0; i--) path.InsertLast(rev[i]);
        return path;
    }
}
