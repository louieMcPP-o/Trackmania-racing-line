// Drawing the line in 3D (projected to the screen) and the info window.

vec4 PointColour(LinePt@ p, float minS, float maxS) {
    if (S_ColourMode == LineColourMode::Inputs) {
        if (p.state == 2) return vec4(1.0f, 0.15f, 0.15f, 1);   // brake
        if (p.state == 1) return vec4(1.0f, 0.85f, 0.10f, 1);   // hold / lift
        return vec4(0.20f, 1.0f, 0.30f, 1);                      // accelerate
    }
    float t = maxS > minS ? Clampf((p.speed - minS) / (maxS - minS), 0, 1) : 0.5f;
    vec4 slow = vec4(0.2f, 0.4f, 1.0f, 1);
    vec4 mid  = vec4(0.2f, 1.0f, 0.3f, 1);
    vec4 fast = vec4(1.0f, 0.2f, 0.1f, 1);
    if (t < 0.5f) return Lerp4(slow, mid, t * 2.0f);
    return Lerp4(mid, fast, (t - 0.5f) * 2.0f);
}

void Render() {
    RenderInfo();

    if (!S_Show || g_line is null) return;
    if (GetApp().CurrentPlayground is null) return;

    auto@ pts = g_line.pts;
    if (pts.Length < 2) return;

    vec3 lift = vec3(0, S_HeightOffset + g_calib, 0);

    vec3 ref;
    bool haveRef = false;
    auto vis = VehicleState::ViewingPlayerState();
    if (vis !is null) { ref = vis.Position; haveRef = true; }

    for (uint i = 1; i < pts.Length; i++) {
        vec3 a = pts[i - 1].pos + lift;
        vec3 b = pts[i].pos + lift;
        if (Len3(b - a) > 20) continue; // gap (e.g. fallback leg)

        float dist = haveRef ? Len3(a - ref) : 0;
        if (dist > S_DrawDistance) continue;
        if (Camera::IsBehind(a) || Camera::IsBehind(b)) continue;

        vec2 sa = Camera::ToScreenSpace(a);
        vec2 sb = Camera::ToScreenSpace(b);

        float fade = 1.0f - Clampf(dist / S_DrawDistance, 0, 1);
        vec4 col = PointColour(pts[i - 1], g_line.minSpeed, g_line.maxSpeed);
        col.w = S_Opacity * (0.25f + 0.75f * fade);
        float w = Math::Max(1.0f, S_Width * Clampf(40.0f / Math::Max(dist, 1.0f), 0.15f, 1.0f));

        nvg::BeginPath();
        nvg::MoveTo(sa);
        nvg::LineTo(sb);
        nvg::StrokeColor(col);
        nvg::StrokeWidth(w);
        nvg::Stroke();
    }

    if (S_ShowWaypoints) {
        for (uint i = 0; i < g_line.markers.Length; i++) {
            auto m = g_line.markers[i];
            vec3 p = m.pos + lift + vec3(0, 3, 0);
            if (haveRef && Len3(p - ref) > S_DrawDistance) continue;
            if (Camera::IsBehind(p)) continue;
            vec2 sp = Camera::ToScreenSpace(p);
            nvg::BeginPath();
            nvg::Circle(sp, 12);
            nvg::FillColor(vec4(0, 0, 0, 0.6f));
            nvg::Fill();
            nvg::StrokeColor(m.colour);
            nvg::StrokeWidth(2);
            nvg::Stroke();
            nvg::FontSize(14);
            nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);
            nvg::FillColor(m.colour);
            nvg::Text(sp, m.label);
        }
    }
}

void RenderInfo() {
    if (!S_ShowInfo) return;
    if (GetApp().RootMap is null) return;

    int flags = UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoCollapse;
    if (UI::Begin("Racing Line", S_ShowInfo, flags)) {
        if (g_line is null) {
            UI::Text(g_status);
            if (g_progress > 0 && g_progress < 1) UI::Text(Text::Format("%.0f%%", g_progress * 100));
        } else {
            UI::Text("\\$0f0Line ready");
            UI::Text("Estimated time: " + FmtTime(g_line.estTime));
            UI::Text("Checkpoints: " + g_line.checkpoints + (g_line.isLoop ? "  (multilap)" : ""));
            UI::Text("Track model: " + g_line.blocks + " blocks, " + g_line.items + " items -> " + g_line.nodes + " cells");
            if (g_line.skippedFree > 0)
                UI::Text("\\$f80" + g_line.skippedFree + " free-placed blocks ignored");
            if (g_line.brokenLegs > 0)
                UI::Text("\\$f80" + g_line.brokenLegs + " section(s) had no road link (straight fallback)");
            if (S_AutoCalibrate)
                UI::Text(g_calibDone ? "Height calibrated (" + Text::Format("%.1f", g_calib) + " m)" : "Height: waiting for car at start");
            UI::Text("\\$0f0Green\\$z accelerate  \\$fd2Yellow\\$z hold  \\$f33Red\\$z brake");
        }
        if (UI::Button("Recalculate")) StartJob();
        UI::SameLine();
        S_Show = UI::Checkbox("Show line", S_Show);
    }
    UI::End();
}
