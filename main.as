// Racing Line - calculates a racing line from the map's geometry and draws it on the track.

RaceLine@ g_line;
string g_uid = "";
string g_status = "";
float g_progress = 0;
int g_job = 0;
float g_calib = 0;
bool g_calibDone = false;

void Main() {
    while (true) {
        auto app = GetApp();
        string uid = "";
        if (app.RootMap !is null) uid = app.RootMap.MapInfo.MapUid;

        if (uid != g_uid) {
            g_uid = uid;
            @g_line = null;
            g_calib = 0;
            g_calibDone = false;
            if (uid != "") StartJob();
            else { g_job++; g_status = ""; }
        }

        if (S_AutoCalibrate && !g_calibDone && g_line !is null) TryCalibrate();
        yield();
    }
}

void StartJob() {
    g_job++;
    @g_line = null;
    g_progress = 0;
    LineSolver@ solver = LineSolver(g_job);
    startnew(CoroutineFunc(solver.Run));
}

// Map grid heights don't always match the road surface exactly, so when the car
// spawns we use its real height to shift the whole line onto the road.
void TryCalibrate() {
    auto vis = VehicleState::ViewingPlayerState();
    if (vis is null) return;
    vec3 car = vis.Position;
    vec3 s = g_line.startPos;
    float h = Math::Sqrt((car.x - s.x) * (car.x - s.x) + (car.z - s.z) * (car.z - s.z));
    if (h > 40) return;
    float dy = car.y - s.y;
    if (Math::Abs(dy) > 32) return;
    g_calib = dy;
    g_calibDone = true;
}

void RenderMenu() {
    if (UI::MenuItem("Racing Line", "", S_Show)) S_Show = !S_Show;
}

void OnSettingsChanged() {
    // Physics/display changes are cheap, but track-model changes need a recalculation;
    // the user can press "Recalculate" in the info window.
}
