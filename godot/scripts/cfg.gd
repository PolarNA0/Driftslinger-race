extends RefCounted
class_name Cfg

# Port of physics/config.js (the JS physics the server verifies runs with).
# Same numbers, so the Godot build drives like the verified physics.
const SPEED := 290.0
const DRIFT_RADIUS := 62.0
const GRAB_RANGE := 95.0
const MIN_GRAB_RADIUS := 20.0
const REEL_SPEED := 150.0
const CENTRE_LOOK := 150.0
const CENTRE_RATE := 1.2
const CENTRE_DEAD := 1.2
const LEAD_IN := 720.0
const SEG_LEN := 230.0
const TURN := PI / 2.0
const MIN_STRAIGHT := 70.0
const BASE_HEADING := -PI / 2.0
const ROAD_HALF_WIDTH := 46.0
const TRAIL_LEN := 70
const PX_PER_METRE := 50.0
const SPEEDRUN_CORNERS := 11
const SPEEDRUN_FINISH := 460.0
const SPEEDRUN_START_FRAC := 0.15
const DT := 1.0 / 120.0

# --- reattach pillars (tracks 26-28) -----------------------------------------
# Bail out of a reattach pillar, catch the same pole again, and ride it to the
# end, and the final release lands you a brief turn of speed. The first reattach
# on a pillar is worth it; doing it again on the same pillar costs you instead,
# so one clean reattach pays and spamming it does not. The effect only lands when
# that final release is near the end of the arc, which is what makes it a
# reattach rather than a plain bail. These pillars exist only in the Godot build,
# so nothing here touches the verified JS physics.
const REATTACH_BOOST := 1.10
const REATTACH_SLOW := 0.82
const REATTACH_EFFECT_TIME := 0.18
const REATTACH_END_FRAC := 0.35
