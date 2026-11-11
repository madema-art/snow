class_name SnowTuning
extends RefCounted
## Central gameplay tuning. Every feel-critical number lives here so Claude/Codex
## passes can tune riding, tricks, nitro, crashes and camera without hunting
## through presentation code. Units: metres, seconds, radians.

# --- Gravity, drag and riding resistance (pass-1/2 constants preserved) ---
const GRAVITY := 20.0
const DRAG := 0.0075               # Quadratic air drag coefficient. NO maximum speed cap.
const TUCK_DRAG_REDUCTION := 0.58  # Full RT tuck removes 58% of air drag.
const ROLLING_RESISTANCE := 0.4    # m/s^2 base snow friction.
const AIR_DRAG_SCALE := 0.35       # Air-only drag in flight (snow friction is gone).

# --- Carving ---
const STEER_CURVE := 1.3           # Analog response exponent: fine control near centre.
const EDGE_ENGAGE_RATE := 8.0      # How fast the edge bites when steering (1/s).
const EDGE_RELEASE_RATE := 11.0    # How fast the board flattens when the stick returns.
const PIVOT_RATE := 1.9            # Max yaw rate at walking speed (rad/s).
const CARVE_ACCEL := 22.0          # Max lateral acceleration a committed carve can hold (m/s^2).
const SKID_TURN_BONUS := 0.55      # Braking lets the board pivot/skid faster.
const EDGE_GRIP := 5.2             # Lateral damping rate on a fully engaged edge.
const FLAT_BASE_GRIP := 0.78       # Grip fraction while running a flat base (slight drift).
const BRAKE_GRIP_LOSS := 0.65      # Braking deliberately breaks the edge into a skid.
const CARVE_SCRUB := 0.018         # Speed scrubbed by a hard carve (per m/s per unit edge).
const EDGE_CATCH_LATERAL := 17.0   # Sideways slide speed that catches the downhill edge...
const EDGE_CATCH_SPEED := 21.0     # ...when also travelling faster than this without braking.

# --- Brake / tuck ---
const BRAKE_BASE := 9.0
const BRAKE_SPEED := 0.2

# --- Snow surfaces (subtle; geography decides time, not surface) ---
const ICE_GRIP_LOSS := 0.32
const ICE_RESISTANCE := -0.15
const POWDER_RESISTANCE := 0.75
const POWDER_DRAG := 0.12

# --- Left stick forward / back (fixed, alongside the remappable triggers) ---
const LEAN_DEADZONE := 0.3         # Stick Y below this is ignored so steering never brakes/tucks by accident.
const RESTART_HOLD := 0.35         # Hold the restart control this long (a tap can never wipe a run).

# --- Deep carve, snow plume and over-lean ---
const PLUME_START := 0.45          # Edge engagement where the plume begins...
const PLUME_FULL := 0.8            # ...and where it is a full rooster tail.
const PLUME_MIN_SPEED := 7.0
const PLUME_FULL_SPEED := 20.0
const DEEP_LEAN_START := 0.82      # Raw stick deflection where the lean becomes "too far"...
const DEEP_LEAN_TURN_BONUS := 0.2  # ...which turns tighter (the reward)...
const OVERLEAN_TIME := 1.9         # ...but held at full lock this long, the edge washes out.
const OVERLEAN_RECOVER := 0.45     # Seconds to come back upright once the stick eases off.
const OVERLEAN_MIN_SPEED := 7.0    # Slow pivots never tip the rider over.
const OVERLEAN_FULL_SPEED := 15.0

# --- Standing push ---
const PUSH_MAX_SPEED := 2.2      # Below this speed A pushes off instead of ollieing.
const PUSH_SPEED := 3.2

# --- Ollie / air ---
const OLLIE_SPEED := 8.8           # Tap ollie (unchanged). Holding A preloads up to:
const OLLIE_PRELOAD_BONUS := 0.3   # +30% pop after a full preload crouch.
const OLLIE_PRELOAD_TIME := 0.42
const COYOTE_TIME := 0.14          # Releasing A just after leaving a lip still pops.
const AIR_STEER_RATE := 0.7        # LS pre-aims the board in the air (does not move it).
const SPIN_RATE := 4.6             # LB/RB full spin speed (rad/s).
const SPIN_ACCEL := 16.0
const FLIP_RATE := 4.2             # D-pad flip speed (rad/s).
const FLIP_ACCEL := 14.0
const AIR_CONFIRM := 0.09          # Tiny terrain hops below this are not "air".

# --- Landing ---
const LAND_YAW_TOLERANCE := 0.85
const LAND_PITCH_TOLERANCE := 0.7
const LAND_IMPACT_LIMIT := 24.0    # Normal impact speed a clean landing absorbs.
const LAND_ALIGN_LIMIT := 0.95     # Board vs travel direction misalignment that catches.
const FATAL_LANDING_DROP := 35.0   # Apex-to-surface drop that is never survivable.
const FATAL_FALL_DROP := 55.0      # Sustained free fall distance that ends the run.

# --- Trick rewards (stored nitro fraction, 1.0 = full board) ---
const REWARD_MIN_AIR := 0.55       # A flat little ollie pays nothing.
const REWARD_AIR_BASE := 0.025
const REWARD_AIR_PER_SECOND := 0.035
const REWARD_DROP_PER_METRE := 0.008 # Big, dangerous drops pay more.
const REWARD_DROP_MAX := 0.14
const REWARD_SPIN := [0.0, 0.07, 0.15, 0.24, 0.34, 0.45, 0.56]  # per completed 180 count
const REWARD_FLIP := [0.0, 0.28, 0.5, 0.7]
const REWARD_GRAB_BASE := 0.04
const REWARD_GRAB_PER_SECOND := 0.08
const REWARD_COMBO := 0.3          # Each extra distinct element multiplies by +30%.
const REWARD_CAP := 0.85
const FATIGUE_DECAY := 1.0 / 25.0  # Repeating the same trick halves, thirds... its value.
const GLOBAL_FATIGUE := 0.45       # Any rewarded landing briefly devalues the next one...
const GLOBAL_FATIGUE_DECAY := 1.0 / 7.0 # ...so constant hop-spam cannot farm the board.

# --- Nitro ---
const BOOST_ACCEL := 24.0
const NITRO_BURN := 0.25           # Full board lasts four seconds of held boost.

# --- Impacts / crashes ---
const BRUSH_IMPACT := 5.0          # Normal impacts below this merely brush past.
const FATAL_TREE_IMPACT := 30.0
const FATAL_ROCK_IMPACT := 34.0
const WALL_CRASH_IMPACT := 16.0
const RECOVERY_MIN := 1.2
const RECOVERY_PER_SEVERITY := 0.12
const RECOVERY_MAX := 7.0
const GETUP_TIME := 0.9            # Final part of recovery spent standing up.
# Tumbles are momentum physics: the body is thrown with most of the speed it had,
# bounces, rolls and slides to rest. Riding speed and nitro are still wiped at once;
# the tumble only decides where (and how sorely) the rider ends up.
const TUMBLE_MOMENTUM := 0.62      # Share of crash velocity the body keeps.
const TUMBLE_REBOUND := 0.38       # Share kept when thrown back off a trunk/boulder.
const TUMBLE_RESTITUTION := 0.42   # Bounce off the snow...
const TUMBLE_IMPACT_LOSS := 0.3   # ...losing this share of sliding speed per impact.
const TUMBLE_FRICTION := 11.0      # Rolling/sliding deceleration (m/s^2)...
const TUMBLE_PLOW := 0.3           # ...plus this per m/s of speed (snow ploughing).
const TUMBLE_HOP := 0.24           # Cartwheel hop: share of speed pitched upward...
const TUMBLE_HOP_MIN_SPEED := 8.0  # ...while the body is still moving this fast.
const TUMBLE_FATAL_DROP := 18.0    # Tumbling off a drop this high is not survivable.
const TUMBLE_MAX_TIME := 9.0
const TUMBLE_MAX_TRAVEL := 70.0    # Safety bound only; friction normally stops it far sooner.

# --- Camera ---
const CAM_DEADZONE := 0.18
const CAM_RESPONSE := 1.35
const CAM_YAW_RATE := 2.9
const CAM_PITCH_RATE := 1.9
const CAM_INPUT_SMOOTH := 16.0     # Angular velocity smoothing for analog feel.
const CAM_PITCH_MIN := -0.35
const CAM_PITCH_MAX := 1.25
const CAM_IDLE_DELAY := 3.0
const CAM_SETTLE_RATE := 1.4
const CAM_RECENTER_RATE := 5.0
const CAM_DISTANCE_MIN := 5.8
const CAM_DISTANCE_MAX := 8.6
const CAM_FOV_REST := 62.0
const CAM_FOV_FAST := 73.0
const CAM_FOV_BOOST := 4.0
const CAM_COLLISION_RADIUS := 0.35
const CAM_RANGES := [0.72, 1.0, 1.5]  # View button: close / medium / far boom length.
const CAM_RANGE_LIFT := [-0.02, 0.0, 0.06]
const CAM_REEXTEND_SPEED := 3.5    # Metres/second the camera may slide back out after an obstruction.
