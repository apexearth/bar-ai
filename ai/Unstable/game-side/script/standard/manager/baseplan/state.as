namespace Base {


// One base layout, shared by every rule that places a structure: an anchored
// rectangle, structures on a grid pitch inside it, walkways left empty at a
// fixed spacing so the base stays crossable however densely it fills in.

// --- the frame ---------------------------------------------------------------
//
// Anchor is the first factory once there is one, latched (commander's start
// stands in until then). Axis points at the front, so the base grows BACKWARD.
// Both are latched once set: re-deriving would move the whole grid out from
// under every structure already standing.
AIFloat3 gAnchor;
AIFloat3 gFwd;      // unit vector, anchor -> front
AIFloat3 gAcross;   // unit vector, perpendicular
bool gAnchorSet = false;
bool gAnchorFinal = false;
bool gAxisSet = false;
bool gPublished = false;
const int ANCHOR_DEADLINE = 3 * MINUTE;

// --- grid geometry -----------------------------------------------------------
//
// Lanes are defined in WORLD offsets rather than column indices, so bands with
// different pitches still leave their gaps in the same places and line up into
// an actual corridor. The lane at lateral 0 is the axis itself.
//
// BUILD_CELL is the invariant every band pitch must satisfy: the engine places
// building centers on a 16-elmo lattice (Pos2BuildPos), so a pitch that is not
// a whole multiple of it rounds alternately down and up and neighbours meant to
// touch end up a build square apart. (CorrectPosition is only a map-bounds
// clamp; it never snaps.)
const float BUILD_CELL = 16.f;    // SQUARE_SIZE * 2; the engine's build square
// The site-search reach and band slack below, and nothing else. Band pitches are
// per band and live in EnsureCols.
const float CELL       = 72.f;
const float GRID_CELL  = 16.f;    // the engine's build square; the pitch published to C++
const float LANE_PITCH = 720.f;   // spacing between walkways, in world offset
const float LANE_HALF  = 72.f;    // half-width of a walkway
// Lateral slack on Inside(). Kept separate from LANE_PITCH, which used to also
// serve as this bound and rejected ground the base needed. Effectively
// unbounded: depth still bounds the band, and GRID_RANGE still bounds the grid
// in C++. This is only the lateral test.
const float BAND_LAT_SLACK = 100000.f;
const float HALF_SPAN  = 1512.f;  // lateral cap; a bound, not a target
const float GRID_RANGE = 2200.f;  // beyond this a placement is not "in the base"

// Bands, measured backward from the anchor. Nanos sit closest so their assist
// radius covers the factory and the first eco rows; heavy energy sits furthest
// back, where a fusion going up does not take the rest of the base with it.
enum Kind { NANO = 0, ECO = 1, HEAVY = 2, KINDS = 3 };

// depth of the first row, row pitch, column pitch, half-footprint, row count.
// Filled in EnsureCols rather than at global scope: a global initialiser that
// fails to compile takes the whole variant down silently.
array<float> BAND_BACK;
array<float> BAND_ROW;
array<float> BAND_COL;
array<float> BAND_HALF;
array<int>   BAND_ROWS;

// How far from a cell centre the site search may reach, and how far outside the
// band's own rectangle the site it comes back with may sit. The site is
// accepted on being clear of a walkway and inside the band, not on landing near
// the cell centre -- block_map.json already fixes structure-to-structure spacing.
const float SEEK       = CELL * 2.f;
const float SEEK_LOOSE = CELL * 4.f;
const float BAND_SLACK = CELL * 2.f;

// Cells examined per placement, and how far back of the last success the scan
// resumes so holes left by losses still get refilled. A scan that always started
// at zero could never reach past cell SCAN_MAX however deep the band is.
const int SCAN_MAX    = 96;
const int SCAN_REWIND = 24;

// A handed-out cell is not blocked until its nanoframe exists, so two requests
// within the TTL would both pass FindBuildSiteNear on the same cell. The
// resolved site is reserved too: neighbouring cells can resolve to the same
// packed site once the ground between them is taken.
const int RESERVE_TTL = 90 * SECOND;

array<float> gColN;   // allowed lateral offsets, per kind, ordered outward
array<float> gColE;
array<float> gColH;
bool gColsBuilt = false;

// Slot visit order, per kind: row * 1000 + column index, nearest the band's own
// origin first. The index a caller sees is a position in THIS list, not a
// row-major cell number. Ordering by distance instead of row-major makes the
// band accrete outward from a point rather than filling a full-width line
// before gaining depth.
array<int> gOrdN;
array<int> gOrdE;
array<int> gOrdH;

array<int> gResIdx;    // reserved cells: kind * 100000 + index
array<int> gResFrame;
array<float> gResX;    // reserved sites
array<float> gResZ;
array<int> gResSiteFrame;

array<int> gCursor;    // per kind, where the last successful scan got to

// Footprint, in band coordinates: how far back and how wide we have actually
// committed to. Grown only by slots we USED.
float gMinLat = 0.f, gMaxLat = 0.f, gMaxDepth = 0.f;
bool gGrown = false;

// Last few sites accepted, per kind, so a placement can be asked the only
// question that matters here: did it end up touching one of its neighbours?
// area= and width= say the base got smaller; they cannot say it got TILED.
const int TILE_MEMORY = 64;
array<float> gTileX;
array<float> gTileZ;
array<int> gTileKind;
int gTileNext = 0;
int gTouch = 0;   // accepted within a pitch of an earlier site of its own kind
int gApart = 0;

int gPlaced = 0;
// Why a placement failed, split by cause: a combined counter can't tell "base
// is full" from a threat veto or a busy reservation.
int gNoRoom = 0;      // scan exhausted: every reason below, summed
int gFailBand = 0;    // ran off the end of the band's rows
int gFailHot = 0;     // cells rejected by the threat veto
int gFailTerrain = 0; // terrain manager would not take the cell
int gFailBusy = 0;    // cell already reserved by an in-flight request
int gNextLog = 0;

}  // namespace Base
