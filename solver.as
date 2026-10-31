// Steps 3-6: order checkpoints, route through the graph, optimise the line, compute speeds.

class LineSolver {
    int job;
    float progress = 0;

    LineSolver(int jobId) { job = jobId; }

    bool Cancelled() { return job != g_job; }

    void Yield() {
        g_progress = progress;
        yield();
        if (Cancelled()) throw("cancelled");
    }

    void Status(const string &in s, float p) {
        progress = p;
        g_status = s;
        g_progress = p;
    }

    void Run() {
        try {
            DoRun();
        } catch {
            if (!Cancelled()) {
                g_status = "\\$f44Error: " + getExceptionInfo();
                error("Racing Line: " + getExceptionInfo());
            }
        }
    }

    void DoRun() {
        Status("Waiting for the map to load...", 0);
        // Wait until we're actually in a playground with the map loaded.
        while (GetApp().CurrentPlayground is null) Yield();
        for (int i = 0; i < 30; i++) Yield();

        auto map = GetApp().RootMap;
        if (map is null) { g_status = "No map loaded."; return; }

        // ---- 1. Scan ----
        Status("Reading map blocks...", 0.05f);
        ScanResult@ scan = ScanMap(map);
        @map = null;
        Yield();

        if (scan.starts.Length == 0) { g_status = "\\$f80No start found on this map."; return; }
        if (scan.cells.Length == 0) { g_status = "\\$f80No drivable blocks found."; return; }

        // ---- 2. Graph ----
        Status("Building track graph...", 0.10f);
        TrackGraph graph;
        graph.Build(scan, this);

        RaceLine@ line = RaceLine();
        line.blocks = scan.blocks;
        line.items = scan.items;
        line.skippedFree = scan.skippedFree;
        line.nodes = int(graph.Count());
        line.checkpoints = int(scan.cps.Length);
        line.isLoop = scan.hasStartFinish && scan.finishes.Length == 0;

        Waypoint@ start = scan.starts[0];
        start.node = graph.NearestNode(start.pos);
        line.startPos = start.pos;
        for (uint i = 0; i < scan.cps.Length; i++) scan.cps[i].node = graph.NearestNode(scan.cps[i].pos);
        array<Waypoint@> finishes = scan.finishes;
        if (finishes.Length == 0) finishes.InsertLast(start); // multilap: finish where we started
        for (uint i = 0; i < finishes.Length; i++) finishes[i].node = graph.NearestNode(finishes[i].pos);

        // ---- 3. Shortest paths from start and every checkpoint ----
        // stops[0] = start, stops[1..k] = checkpoints
        array<Waypoint@> stops;
        stops.InsertLast(start);
        for (uint i = 0; i < scan.cps.Length; i++) stops.InsertLast(scan.cps[i]);

        array<array<float>@> dists;
        array<array<int>@> prevs;
        for (uint s = 0; s < stops.Length; s++) {
            Status("Finding routes (" + (s + 1) + "/" + stops.Length + ")...", 0.25f + 0.25f * float(s) / float(stops.Length));
            array<float>@ d = array<float>();
            array<int>@ p = array<int>();
            graph.Dijkstra(stops[s].node, d, p, this);
            dists.InsertLast(d);
            prevs.InsertLast(p);
        }

        // ---- 4. Checkpoint order (checkpoints in TM2020 can be taken in any order) ----
        Status("Ordering checkpoints...", 0.50f);
        array<int> route = OrderCheckpoints(stops, finishes, dists);
        Yield();

        // Pick the finish closest (by road) to the last stop.
        int lastStop = route.Length > 0 ? route[route.Length - 1] : 0;
        Waypoint@ finish = finishes[0];
        float bestF = INF;
        for (uint i = 0; i < finishes.Length; i++) {
            float d = StopDist(lastStop, finishes[i], stops, dists);
            if (d < bestF) { bestF = d; @finish = finishes[i]; }
        }

        // Markers for drawing
        line.markers.InsertLast(Marker(start.pos, "S", vec4(0.2f, 1, 0.3f, 1)));
        for (uint i = 0; i < route.Length; i++)
            line.markers.InsertLast(Marker(stops[route[i]].pos, "" + (i + 1), vec4(0.3f, 0.6f, 1, 1)));
        if (finish !is start)
            line.markers.InsertLast(Marker(finish.pos, "F", vec4(1, 0.25f, 0.25f, 1)));

        // ---- 5. Build the centreline through the graph ----
        Status("Tracing centreline...", 0.55f);
        array<vec3> centre;
        array<bool> pinned;
        array<int> legStops;           // stop index for each leg start
        legStops.InsertLast(0);
        for (uint i = 0; i < route.Length; i++) legStops.InsertLast(route[i]);

        for (uint L = 0; L < legStops.Length; L++) {
            int from = legStops[L];
            Waypoint@ a = stops[from];
            Waypoint@ b = finish;
            if (L + 1 < legStops.Length) @b = stops[legStops[L + 1]];

            array<vec3> leg;
            leg.InsertLast(a.pos);
            if (b.node >= 0 && dists[from][b.node] < INF) {
                array<int> path = graph.PathTo(b.node, prevs[from]);
                // skip the first/last node (they sit in the waypoint cells themselves)
                for (uint k = 1; k + 1 < path.Length; k++) leg.InsertLast(graph.pos[path[k]]);
            } else {
                line.brokenLegs++; // no road connection found: straight line fallback
            }
            leg.InsertLast(b.pos);
            AppendResampled(leg, centre, pinned, L == 0);
        }
        Yield();

        if (centre.Length < 5) { g_status = "\\$f80Track too short to solve."; return; }

        // ---- 5b. Smooth the blocky cell path into a plausible road centre ----
        Status("Smoothing centreline...", 0.60f);
        SmoothCentre(centre, pinned);

        // ---- 6. Minimum-curvature optimisation ----
        Status("Optimising line...", 0.65f);
        array<vec3> racing = OptimiseLine(centre, pinned);

        // ---- 7. Speed profile ----
        Status("Computing speeds...", 0.95f);
        ComputeSpeeds(racing, line);

        @g_line = line;
        g_status = "Ready";
        g_progress = 1;
    }

    // ----------------------------------------------------------------

    float StopDist(int fromStop, Waypoint@ to, array<Waypoint@>@ stops, array<array<float>@>@ dists) {
        float d = (to.node >= 0) ? dists[fromStop][to.node] : INF;
        if (d >= INF) d = Len3(to.pos - stops[fromStop].pos) * 3.0f; // unreachable: heavy straight-line estimate
        return d;
    }

    float RouteCost(const array<int> &in route, array<Waypoint@>@ stops, array<Waypoint@>@ finishes, array<array<float>@>@ dists) {
        float c = 0;
        int prev = 0;
        for (uint i = 0; i < route.Length; i++) {
            c += StopDist(prev, stops[route[i]], stops, dists);
            prev = route[i];
        }
        float bestF = INF;
        for (uint i = 0; i < finishes.Length; i++) bestF = Math::Min(bestF, StopDist(prev, finishes[i], stops, dists));
        return c + bestF;
    }

    // Nearest-neighbour tour, then improved with 2-opt.
    array<int> OrderCheckpoints(array<Waypoint@>@ stops, array<Waypoint@>@ finishes, array<array<float>@>@ dists) {
        array<int> route;
        uint k = stops.Length - 1;
        if (k == 0) return route;

        array<bool> used(stops.Length, false);
        int cur = 0;
        for (uint n = 0; n < k; n++) {
            int best = -1;
            float bestD = INF * 2;
            for (uint s = 1; s < stops.Length; s++) {
                if (used[s]) continue;
                float d = StopDist(cur, stops[s], stops, dists);
                if (d < bestD) { bestD = d; best = int(s); }
            }
            used[best] = true;
            route.InsertLast(best);
            cur = best;
        }

        float bestCost = RouteCost(route, stops, finishes, dists);
        bool improved = true;
        int rounds = 0;
        while (improved && rounds++ < 60) {
            improved = false;
            for (uint i = 0; i + 1 < route.Length; i++) {
                for (uint j = i + 1; j < route.Length; j++) {
                    array<int> cand = route;
                    uint lo = i;
                    uint hi = j;
                    while (lo < hi) {
                        int t = cand[lo]; cand[lo] = cand[hi]; cand[hi] = t;
                        lo++;
                        hi--;
                    }
                    float c = RouteCost(cand, stops, finishes, dists);
                    if (c < bestCost - 0.01f) { route = cand; bestCost = c; improved = true; }
                }
            }
        }
        return route;
    }

    // Resample a polyline at even spacing. Leg endpoints (waypoints) are pinned.
    void AppendResampled(const array<vec3> &in leg, array<vec3> &inout centre, array<bool> &inout pinned, bool first) {
        array<float> cum;
        cum.InsertLast(0);
        for (uint i = 1; i < leg.Length; i++) cum.InsertLast(cum[i - 1] + Len3(leg[i] - leg[i - 1]));
        float total = cum[cum.Length - 1];
        int n = Math::Max(1, int(Math::Round(total / S_Spacing)));

        uint seg = 0;
        for (int s = (first ? 0 : 1); s <= n; s++) {
            float t = total * float(s) / float(n);
            while (seg + 2 < leg.Length && cum[seg + 1] < t) seg++;
            float segLen = cum[seg + 1] - cum[seg];
            float f = segLen > 0.0001f ? (t - cum[seg]) / segLen : 0;
            vec3 p = leg[seg] + (leg[seg + 1] - leg[seg]) * Clampf(f, 0, 1);
            centre.InsertLast(p);
            pinned.InsertLast(s == 0 || s == n);
        }
    }

    void SmoothCentre(array<vec3> &inout c, const array<bool> &in pinned) {
        uint N = c.Length;
        for (int pass = 0; pass < S_SmoothPasses; pass++) {
            array<vec3> next = c;
            for (uint i = 1; i + 1 < N; i++) {
                if (pinned[i]) continue;
                next[i] = c[i] * 0.5f + (c[i - 1] + c[i + 1]) * 0.25f;
            }
            c = next;
            if (pass % 10 == 0) Yield();
        }
    }

    // Minimise sum of squared second differences (≈ curvature) of the line,
    // letting each point slide sideways within the road width.
    array<vec3> OptimiseLine(const array<vec3> &in c3, const array<bool> &in pinned) {
        int N = int(c3.Length);
        array<vec2> c(N);
        array<vec2> n(N);
        array<float> lim(N);
        array<float> a(N, 0);

        for (int i = 0; i < N; i++) {
            c[i] = vec2(c3[i].x, c3[i].z);
            lim[i] = pinned[i] ? S_CpHalfWidth : S_HalfWidth;
        }
        for (int i = 0; i < N; i++) {
            vec2 t = c[Math::Min(i + 1, N - 1)] - c[Math::Max(i - 1, 0)];
            float l = Len2(t);
            if (l < 0.0001f) { n[i] = vec2(0, 0); continue; }
            t = t * (1.0f / l);
            n[i] = vec2(-t.y, t.x);
        }
        // Ends are fixed: start from the spawn, finish in the finish gate.
        lim[0] = 0;
        lim[N - 1] = Math::Min(lim[N - 1], S_CpHalfWidth);

        const float omega = 1.6f; // over-relaxation
        for (int it = 0; it < S_Iterations; it++) {
            for (int i = 1; i < N - 1; i++) {
                vec2 pm1 = c[i - 1] + n[i - 1] * a[i - 1];
                vec2 pp1 = c[i + 1] + n[i + 1] * a[i + 1];
                vec2 target;
                if (i >= 2 && i <= N - 3) {
                    vec2 pm2 = c[i - 2] + n[i - 2] * a[i - 2];
                    vec2 pp2 = c[i + 2] + n[i + 2] * a[i + 2];
                    // argmin of the three second-difference terms that involve point i
                    target = ((pm1 + pp1) * 4.0f - pm2 - pp2) * (1.0f / 6.0f);
                } else {
                    target = (pm1 + pp1) * 0.5f;
                }
                float aStar = Dot2(target - c[i], n[i]);
                float na = a[i] + omega * (aStar - a[i]);
                a[i] = Clampf(na, -lim[i], lim[i]);
            }
            if (it % 20 == 0) {
                progress = 0.65f + 0.30f * float(it) / float(S_Iterations);
                Yield();
            }
        }

        array<vec3> outPts(N);
        for (int i = 0; i < N; i++) {
            vec2 p = c[i] + n[i] * a[i];
            outPts[i] = vec3(p.x, c3[i].y, p.y);
        }
        return outPts;
    }

    void ComputeSpeeds(const array<vec3> &in p, RaceLine@ line) {
        int N = int(p.Length);
        float vTop = S_TopSpeed / 3.6f;

        // curvature from consecutive point triples (horizontal plane)
        array<float> kappa(N, 0);
        for (int i = 1; i < N - 1; i++) {
            vec2 A = vec2(p[i - 1].x, p[i - 1].z);
            vec2 B = vec2(p[i].x, p[i].z);
            vec2 C = vec2(p[i + 1].x, p[i + 1].z);
            float ab = Len2(B - A), bc = Len2(C - B), ca = Len2(C - A);
            float cross = (B.x - A.x) * (C.y - A.y) - (B.y - A.y) * (C.x - A.x);
            float denom = ab * bc * ca;
            kappa[i] = denom > 0.0001f ? Math::Abs(2.0f * cross) / denom : 0;
        }
        // light smoothing of curvature to kill numerical noise
        array<float> ks(N, 0);
        for (int i = 0; i < N; i++) {
            float s = 0; int cnt = 0;
            for (int j = i - 2; j <= i + 2; j++) if (j >= 0 && j < N) { s += kappa[j]; cnt++; }
            ks[i] = s / float(cnt);
        }

        array<float> cap(N), ds(N, 0), slope(N, 0);
        for (int i = 0; i < N; i++) {
            cap[i] = ks[i] > 0.00001f ? Math::Min(vTop, Math::Sqrt(S_LatAccel / ks[i])) : vTop;
            if (i + 1 < N) {
                ds[i] = Math::Max(0.01f, Len3(p[i + 1] - p[i]));
                slope[i] = Clampf((p[i + 1].y - p[i].y) / ds[i], -1, 1); // sin(theta)
            }
        }

        // forward pass: accelerate from standstill, limited by engine and grip
        array<float> vf(N);
        vf[0] = 0;
        for (int i = 0; i < N - 1; i++) {
            float acc = S_Accel * Math::Max(0.05f, 1.0f - vf[i] / vTop) - GRAVITY * slope[i];
            float v2 = vf[i] * vf[i] + 2.0f * acc * ds[i];
            vf[i + 1] = Math::Min(cap[i + 1], Math::Sqrt(Math::Max(v2, 1.0f)));
        }
        // backward pass: braking limits
        array<float> v(N);
        v[N - 1] = vf[N - 1];
        for (int i = N - 2; i >= 0; i--) {
            float dec = Math::Max(1.0f, S_Brake + GRAVITY * slope[i]);
            float vb = Math::Sqrt(v[i + 1] * v[i + 1] + 2.0f * dec * ds[i]);
            v[i] = Math::Min(vf[i], vb);
        }

        float t = 0;
        line.minSpeed = INF;
        line.maxSpeed = 0;
        for (int i = 0; i < N; i++) {
            int state = 0;
            if (v[i] < vf[i] - 0.3f) state = 2;
            else if (cap[i] < vTop - 0.5f && v[i] >= cap[i] - 0.3f) state = 1;
            line.pts.InsertLast(LinePt(p[i], v[i], state));
            line.minSpeed = Math::Min(line.minSpeed, v[i]);
            line.maxSpeed = Math::Max(line.maxSpeed, v[i]);
            if (i + 1 < N) t += ds[i] / Math::Max(0.5f, (v[i] + v[i + 1]) * 0.5f);
        }
        line.estTime = t;
    }
}
