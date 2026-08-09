namespace Base {


// One base layout, shared by every rule that places a structure.
//
// What this replaces: three separate lattices -- BandSpot (nano rows plus eco
// flanks), ConvSpot (the converter block) and RearPos (converters, again) --
// each re-deriving its own axis from gHomePos and the enemy centroid, none
// aware of the others, and none asking whether anything can stand where it
// pointed. Everything else went out as a position plus a shake radius and the
// engine slid it anywhere inside that radius. There was no footprint, no rows
// and no lanes, which is why the radius could only ever trade sprawl against
// self-walling.
//
// The model here is the one a human uses: an anchored rectangle, structures on
// a grid pitch inside it, and walkways left empty at a fixed spacing so the
// base stays crossable however densely it fills in.

// --- the frame ---------------------------------------------------------------
//
// Anchor is the first factory once there is one, latched, because a factory is
// where the base actually centres; the commander's start position stands in
// until then. Axis points at the front, so the base grows BACKWARD, away from
// the fighting.
//
// Both are latched once set. An anchor or axis that keeps re-deriving is worse
// than a slightly wrong one -- it moves the whole grid out from under every
// structure already standing, and what was a lane becomes a row.
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
// Lanes are defined in WORLD offsets rather than column indices, so that bands
// with different pitches still leave their gaps in the same places and the gaps
// line up into an actual corridor. The lane at lateral 0 is the axis itself:
// the road out of the factory toward the front.
// CELL is this file's own band pitch. GRID_CELL is the separate, much finer
// pitch handed to C++.
//
// They are separate because of what the C++ snap does downstream:
// IBuilderTask::Execute quantises the position onto the published pitch and then
// CTerrainManager::FindBuildSite takes the nearest site the blocking map allows.
// Structures whose footprint is not a multiple of that pitch therefore cannot
// land next to each other -- the quantised neighbour overlaps, the blocking map
// refuses it, and the spiral settles a whole pitch further out. A pitch of one
// heightmap square divides every footprint, so the snap aligns without ever
// forcing a gap, and the walkway push it also performs still applies.
const float CELL       = 72.f;
const float GRID_CELL  = 8.f;     // SQUARE_SIZE; the pitch published to C++
const float LANE_PITCH = 720.f;   // spacing between walkways: one column in ten
const float LANE_HALF  = 72.f;    // half-width of a walkway
// Lateral slack on Inside(). This WAS LANE_PITCH -- one constant serving two
// unrelated jobs, so the walkway spacing also decided how far sideways a
// position could be and still count as "in the base". At 720 that bound
// rejected ground the base genuinely needed, and Inside() gates the work that
// grows it. Measured, 8 seeds, 1v1 Altair vs easy, 16 min: total mex 56 -> 81
// (+45%) and metal 109,705 -> 139,406 (+27%), better in 7 of 8 seeds, with the
// walkways left ON -- an earlier run that removed them scored the same, so the
// gain was never the corridors.
// Effectively unbounded: depth still bounds the band, and GRID_RANGE still
// bounds the grid in C++. This is only the lateral test.
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
// band's own rectangle the site it comes back with may sit.
//
// The site is accepted on being clear of a walkway and inside the band, not on
// landing near the cell centre. block_map.json already fixes the spacing between
// any two structures -- structures of a class ignore each other and pack edge to
// edge, everything else gets a yard -- so a second spacing rule layered on top of
// it can only be looser than that one or fight it.
const float SEEK       = CELL * 2.f;
const float SEEK_LOOSE = CELL * 4.f;
const float BAND_SLACK = CELL * 2.f;

// Cells examined per placement, and how far back of the last success the scan
// resumes so holes left by losses still get refilled. A scan that always started
// at zero could never reach past cell SCAN_MAX however deep the band is.
const int SCAN_MAX    = 96;
const int SCAN_REWIND = 24;

// A handed-out cell is not blocked until its nanoframe exists, so two requests
// in the same few seconds would both pass FindBuildSiteNear on the same cell.
// The resolved site is reserved as well as the cell: neighbouring cells resolve
// to the same packed site once the ground between them is taken.
const int RESERVE_TTL = 90 * SECOND;
const float RESERVE_R = 96.f;

array<float> gColN;   // allowed lateral offsets, per kind, ordered outward
array<float> gColE;
array<float> gColH;
bool gColsBuilt = false;

// Slot visit order, per kind: row * 1000 + column index, nearest the band's own
// origin first. The index a caller sees is a position in THIS list, not a
// row-major cell number.
//
// Row-major order walks one row across every column before stepping back a row,
// so a band fills as a line the full width of the column list before it ever
// gains depth. Ordering by distance instead makes it accrete outward from a
// point, which is the shape CTerrainManager::FindBuildSite's distance-sorted
// offset table produces for a caller that keeps passing the same position.
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

int gPlaced = 0;
// Why a placement failed, split by cause. One combined counter conflated four
// unrelated things and was read as "the base is full" when it may have been
// none of them -- apexearth: "noroom is wrong".
int gNoRoom = 0;      // scan exhausted: every reason below, summed
int gFailBand = 0;    // ran off the end of the band's rows
int gFailHot = 0;     // cells rejected by the threat veto
int gFailTerrain = 0; // terrain manager would not take the cell
int gFailBusy = 0;    // cell already reserved by an in-flight request
int gNextLog = 0;

}  // namespace Base
