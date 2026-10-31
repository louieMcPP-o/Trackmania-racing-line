// Shared data types and small helpers.

const float INF = 1e30f;
const float GRAVITY = 9.81f;

enum WpKind { Start, Checkpoint, Finish, StartFinish }

class Waypoint {
    WpKind kind;
    vec3 pos;
    int node = -1;
    Waypoint() {}
    Waypoint(WpKind k, vec3 p) { kind = k; pos = p; }
}

class Marker {
    vec3 pos;
    string label;
    vec4 colour;
    Marker() {}
    Marker(vec3 p, const string &in l, vec4 c) { pos = p; label = l; colour = c; }
}

// state: 0 = accelerate, 1 = hold (grip-limited), 2 = brake
class LinePt {
    vec3 pos;
    float speed;   // m/s
    int state;
    LinePt() {}
    LinePt(vec3 p, float s, int st) { pos = p; speed = s; state = st; }
}

class RaceLine {
    array<LinePt@> pts;
    array<Marker@> markers;
    vec3 startPos;
    float estTime = 0;     // seconds
    float minSpeed = 0;
    float maxSpeed = 0;
    int blocks = 0;
    int items = 0;
    int skippedFree = 0;
    int nodes = 0;
    int checkpoints = 0;
    int brokenLegs = 0;
    bool isLoop = false;
}

class CellEntry {
    int x, y, z;
    vec3 pos;
    CellEntry() {}
    CellEntry(int cx, int cy, int cz, vec3 p) { x = cx; y = cy; z = cz; pos = p; }
}

// ---------- maths helpers ----------
float Dot2(vec2 a, vec2 b) { return a.x * b.x + a.y * b.y; }
float Len2(vec2 a) { return Math::Sqrt(a.x * a.x + a.y * a.y); }
float Len3(vec3 a) { return Math::Sqrt(a.x * a.x + a.y * a.y + a.z * a.z); }
float Clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
int Absi(int v) { return v < 0 ? -v : v; }

vec4 Lerp4(vec4 a, vec4 b, float t) { return a + (b - a) * t; }

// Trackmania 2020 block grid: 32 x 8 x 32 metres, y offset of 8 cells.
vec3 BlockCentre(nat3 c) {
    return vec3(float(c.x) * 32.0f + 16.0f, (float(int(c.y)) - 8.0f) * 8.0f, float(c.z) * 32.0f + 16.0f);
}
int CellX(float x) { return int(Math::Floor(x / 32.0f)); }
int CellY(float y) { return int(Math::Floor(y / 8.0f)) + 8; }
int CellZ(float z) { return int(Math::Floor(z / 32.0f)); }

string FmtTime(float seconds) {
    if (seconds <= 0) return "--";
    return Time::Format(int64(seconds * 1000.0f));
}

// Simple binary min-heap for Dijkstra.
class MinHeap {
    array<int> ids;
    array<float> keys;

    uint Count() { return ids.Length; }

    void Push(int id, float k) {
        ids.InsertLast(id);
        keys.InsertLast(k);
        int i = int(ids.Length) - 1;
        while (i > 0) {
            int p = (i - 1) / 2;
            if (keys[p] <= keys[i]) break;
            Swap(i, p);
            i = p;
        }
    }

    int Pop(float &out k) {
        int top = ids[0];
        k = keys[0];
        int last = int(ids.Length) - 1;
        ids[0] = ids[last];
        keys[0] = keys[last];
        ids.RemoveLast();
        keys.RemoveLast();
        int n = int(ids.Length);
        int i = 0;
        while (true) {
            int l = 2 * i + 1;
            int r = l + 1;
            int m = i;
            if (l < n && keys[l] < keys[m]) m = l;
            if (r < n && keys[r] < keys[m]) m = r;
            if (m == i) break;
            Swap(i, m);
            i = m;
        }
        return top;
    }

    void Swap(int a, int b) {
        int ti = ids[a]; ids[a] = ids[b]; ids[b] = ti;
        float tk = keys[a]; keys[a] = keys[b]; keys[b] = tk;
    }
}
