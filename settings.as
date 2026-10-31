enum LineColourMode { Inputs, Speed }

// ---------------- Display ----------------
[Setting category="Display" name="Show racing line"]
bool S_Show = true;

[Setting category="Display" name="Show info window"]
bool S_ShowInfo = true;

[Setting category="Display" name="Colour mode" description="Inputs: green = accelerate, yellow = hold at the grip limit, red = brake. Speed: blue (slow) to red (fast)."]
LineColourMode S_ColourMode = LineColourMode::Inputs;

[Setting category="Display" name="Draw distance (m)" min=50 max=2000]
float S_DrawDistance = 500;

[Setting category="Display" name="Line width" min=1 max=20]
float S_Width = 6;

[Setting category="Display" name="Opacity" min=0.1 max=1]
float S_Opacity = 0.85f;

[Setting category="Display" name="Height above road (m)" min=-5 max=10]
float S_HeightOffset = 0.5f;

[Setting category="Display" name="Auto-calibrate height from car spawn"]
bool S_AutoCalibrate = true;

[Setting category="Display" name="Show checkpoint markers"]
bool S_ShowWaypoints = true;

// ---------------- Track model ----------------
[Setting category="Track model" name="Road half-width (m)" min=2 max=16 description="How far the line may move sideways from the estimated road centre."]
float S_HalfWidth = 9;

[Setting category="Track model" name="Checkpoint half-width (m)" min=1 max=16 description="How far the line may move sideways while passing through a checkpoint."]
float S_CpHalfWidth = 5;

[Setting category="Track model" name="Include items"]
bool S_IncludeItems = true;

[Setting category="Track model" name="Ignore blocks whose name contains (comma separated)"]
string S_IgnoreNames = "Grass,Deco,Pillar,Structure";

[Setting category="Track model" name="Max gap the line may jump (cells)" min=1 max=3 description="1 cell = 32 m. Higher values let it find jumps but also let it cut between separate roads."]
int S_MaxGap = 2;

[Setting category="Track model" name="Centreline smoothing passes" min=0 max=200]
int S_SmoothPasses = 40;

// ---------------- Physics ----------------
[Setting category="Physics" name="Corner grip (m/s^2)" min=5 max=80]
float S_LatAccel = 28;

[Setting category="Physics" name="Acceleration (m/s^2)" min=2 max=40]
float S_Accel = 16;

[Setting category="Physics" name="Braking (m/s^2)" min=5 max=80]
float S_Brake = 30;

[Setting category="Physics" name="Top speed (km/h)" min=100 max=1000]
float S_TopSpeed = 1000;

// ---------------- Solver ----------------
[Setting category="Solver" name="Point spacing (m)" min=1 max=10]
float S_Spacing = 4;

[Setting category="Solver" name="Optimiser iterations" min=50 max=5000]
int S_Iterations = 800;
