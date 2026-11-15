// Every number that decides how it feels, in one place.
//
// The road is a staircase: straight legs joined by quarter-turn corners, and
// each corner is a circular arc of radius driftRadius. The pole you sling around
// is the centre of that arc, so when you latch on the car follows the road
// exactly. One corner, one pole, one sling.
//
// Corners alternate left and right. That is not decoration. With every corner a
// full 90 degrees, two turns the same way in a row would point the road back the
// way it came and the ribbon would cross itself. Alternating keeps each leg
// perpendicular to the last, so the road can never fold and the nearest-point
// search can never jump branches.
//
// Geometry note: a corner of deflection phi needs its fillet to start and end
// r*tan(phi/2) from the vertex, which for a quarter turn is exactly r. Two
// neighbouring fillets must not eat the whole straight between them, so segLen
// must exceed 2*driftRadius plus minStraight. The track builder asserts this, so
// a bad combination fails loudly instead of shipping a folded road.
//
// The tuning was chosen with tools/sweep.mjs and tools/window.mjs, not by feel.
export const CFG = {
  speed: 290,          // px/s, held constant whether flying or drifting
  driftRadius: 62,     // the arc the car carves, and the radius of every corner
  grabRange: 95,       // how close the pole must be to latch on
  minGrabRadius: 20,   // a grab nearer than this would sit inside the road, so clamp
  reelSpeed: 150,      // px/s the orbit radius closes on the road radius. Grabbing
                       // wide is allowed, but reeling back in costs you time.
  // Post-release centring. While flying, the car steers gently back toward the
  // road centreline, so a sloppy release curves you home instead of dumping you
  // against the wall. It is a pure-pursuit nudge - aim at a point this far up
  // the centreline - so a curved recovery is a longer path and therefore costs
  // time. A centred car is left alone, so a perfect line is unaffected.
  centreLook: 150,     // lookahead up the centreline, px
  centreRate: 1.2,     // heading blend toward that point, per second. Tuned by
                       // tools: strong enough that a slightly-late release on the
                       // closing straight curves home instead of hitting the wall,
                       // weak enough that the perfect line is still the fastest and
                       // a corner cut still costs time.
  centreDead: 1.2,     // within this of the centreline, do nothing, px
  leadIn: 720,         // opening straight. Long enough that road exists behind
                       // the car, so the camera never sees grass at the start.
  segLen: 230,         // distance between corners (vertex to vertex). With a
                       // quarter turn the two fillets eat 2*driftRadius, so this
                       // leaves segLen - 124 px of visible straight between them.
  turn: Math.PI / 2,   // every corner is a quarter turn
  minStraight: 70,     // shortest straight we allow between two corners
  baseHeading: -Math.PI / 2,  // the road's general direction: up the screen
  roadHalfWidth: 46,   // beyond this from the centreline you hit the wall
  trailLen: 70,
  pxPerMetre: 50,      // for turning pixels into a distance readout

  // --- speedrun ---------------------------------------------------------
  // A speedrun track is a finite, fixed road you race the clock on. The opening
  // straight is CFG.leadIn and each corner adds about 203px, so at 290px/s a
  // corner costs about 0.70s. The twenty-five time-attack tracks live in tracks.js;
  // this is only the fallback shape and the shared constants.
  speedrunCorners: 11,
  speedrunFinish: 460, // fallback closing straight, px, when no target time is
                       // given. Otherwise the builder sizes it to hit the target.
  speedrunStartFrac: 0.15, // the car starts this far along the lead-in, so the
                           // clock starts a little into the road.
};
