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

# --- reattach pillars --------------------------------------------------------
# A reattach pillar stays live if you let go before its arc is done, so you can
# fly off and catch the same pole again. The reward is a slingshot, and it is
# scaled by the detour: the longer you fly before re-catching, the bigger the
# speed boost, up to a cap. A quick release-and-recatch - the "spam" line - flies
# almost nowhere, so it earns almost nothing, which is what keeps spamming from
# being the way. The boost is granted at most once per pillar, so grinding one
# pole cannot stack it.
#
# The old numbers were 1.10x for 0.18s, which measured as ~0.017s per reattach
# and was identical for every bail point - imperceptible and with no skill in it.
# These are the retuned values; see tools/verify_reattach.gd for the proof that
# the reward scales with the detour and that a quick re-catch earns nothing.
const REATTACH_BOOST_MAX := 1.30    # speed multiplier at a full-length detour
const REATTACH_EFFECT_TIME := 0.70  # how long the boost lasts, seconds
const REATTACH_MIN_DETOUR := 6.0    # detour (px) below which there is no boost
const REATTACH_REF_DETOUR := 90.0   # detour (px) that earns the full boost
# A reattach pillar reaches further than an ordinary one, so a committed detour
# can still be caught. Without it the pole radius leaves only a sliver of flight
# before the car is out of range, and there is no room for a real detour.
const REATTACH_GRAB_MULT := 1.6

# --- endless difficulty ramp -------------------------------------------------
# Endless is one road that gets harder the further you get: the car runs faster
# and the corners tighten and crowd together. Everything ramps on road position,
# so the difficulty is a pure function of distance and a replay reproduces it
# exactly. The ramp is deliberately gentle enough that a clean line still
# survives a long run (tools/verify_guard.gd proves it on the ramped road).
const ENDLESS_RAMP_LEN := 9000.0       # px over which difficulty reaches full
const ENDLESS_SPEED_MAX := 1.35        # top speed multiplier
const ENDLESS_RADIUS_MIN := 46.0       # tightest corner radius
const ENDLESS_SEG_MIN := 178.0         # shortest straight between corners
const ENDLESS_REATTACH_AFTER := 2400.0 # px before reattach pillars appear
const ENDLESS_REATTACH_EVERY := 3      # every Nth corner past that is reattach
