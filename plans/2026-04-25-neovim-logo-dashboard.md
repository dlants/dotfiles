# context

Add a third dashboard mode (`MODE_LOGO`) to `nvim/lua/dashboard.lua`: a
spinning 3D Neovim mark, N64-logo style — three flat prisms (left vertical,
right vertical, diagonal cross) extruded along Z, ray-traced, and colored
with two `nvim_set_hl` groups matching the official blue and green.

## Why this is tractable despite weak spatial reasoning

- We don't invent the silhouette. We lift the polygon vertices straight from
  the official `neovim-mark-flat.svg` (saved at `/tmp/neovim-mark.svg` from
  github.com/neovim/neovim.io). 8 unique 2D points total define the entire
  shape — we never hand-place a 3D vertex.
- Every piece is **convex** in 2D (verified below), and extruding a convex
  2D polygon along Z gives a convex polyhedron. Convex polyhedra have a
  trivial closed-form ray intersection (slab method generalized to N face
  planes), so we don't need SDFs, raymarching, or rasterization.
- Geometry is built once at module load. Per frame we only rotate the
  precomputed face normals (plane offsets are rotation-invariant since the
  shape is centered at the origin).

## Source geometry (from the SVG, before centering/normalization)

Left pentagon (BLUE, fill `#3C92D2`):
  (0,155) (26,129) (155,321) (155,727) (0,572)

Right pentagon (GREEN, fill `#57A143`, original path then `scale(-1,1)`
mirror around x=521):
  raw: (443,157) (600,-1) (600,403) (469,601) (442,572)
  mirrored: (599,157) (442,-1) (442,403) (573,601) (600,572)

Diagonal cross parallelogram (GREEN, `#57A143`):
  (155,0) (558,615) (445,728) (42,114)

Convexity check (signs of consecutive edge cross products) — all same sign
for each polygon, confirmed manually for the left pentagon (8346, 52374,
62930, 64635, 10842 — all positive).

Coordinate transform applied once at load:
  - subtract center (300, 364)
  - negate y (SVG y-down → world y-up)
  - divide by 364 so the largest extent maps to ±1

Per-piece Z extrusion (object-space half-depth ~0.10), plus a small Z
offset per piece so the three prisms interlock in 3D rather than being
coplanar (this is what gives the N64-logo "depth reveal" when spinning):
  - left pentagon:  z_offset = +0.05
  - cross diagonal: z_offset =  0.00
  - right pentagon: z_offset = -0.05

## Rendering math (per frame)

Object → world rotation `R = R_x(tilt) * R_y(t * spin_rate)`.

For each piece i:
  - rotated normals: `n_world = R * n_obj` for each face
  - plane offsets unchanged: `d_world = d_obj` (centered geometry, R is
    orthogonal, so dot(R*p, R*n) = dot(p,n))

Per pixel:
  - build ray (orthographic or pinhole — pinhole matches the orbs mode)
  - for each piece, run convex-polyhedron slab test:
      tNear = -inf, tFar = +inf, hit_normal = nil
      for each face (n, d):
        denom = dot(rd, n)
        t = (d - dot(ro, n)) / denom
        if denom < 0 and t > tNear: tNear, hit_normal = t, n
        elif denom > 0 and t < tFar: tFar = t
        elif denom == 0 and dot(ro, n) > d: skip piece
      if tNear <= tFar and tFar >= 0: candidate hit at tNear
  - keep the piece+normal with smallest tNear across all 3 pieces
  - shade: lambert(n, light) + fresnel(n, rd), same recipe as `render_orbs`
  - output: ASCII char (from `RAMP`) + piece id (1=blue, 2=green, 0=bg)

## Coloring

Two highlight groups defined in `M.setup` (or first call to `M.open`):

  api.nvim_set_hl(0, "DashboardLogoBlue",  { fg = "#3C92D2" })
  api.nvim_set_hl(0, "DashboardLogoGreen", { fg = "#57A143" })

Both pentagons use one color; the cross uses the other. Per the SVG, blue
is the left pentagon only, green is the right pentagon AND the cross.

After buffer text is set, walk each row of the piece-id array and emit a
single extmark per contiguous run of the same id (via
`nvim_buf_set_extmark` with `hl_group` and `end_col`), keeping the extmark
count bounded.

## Relevant files

- `nvim/lua/dashboard.lua` — entire feature lives here. Mirrors structure
  of `render_orbs`/`render_life_cube`: a per-frame `render_logo(W,H,t)`
  returning ASCII rows, plus a parallel `piece_rows` table for highlights.
- `state.mode` already exists; add `MODE_LOGO = "logo"`. Existing `tick()`
  dispatches on mode — extend it.
- Highlighting: existing `tick()` uses `nvim_buf_set_lines` with no
  highlighting. We add a `state.ns` namespace and call
  `nvim_buf_clear_namespace` + `nvim_buf_set_extmark` after the lines are
  written (only for logo mode).

# implementation

- [ ] **Step 1: extract piece data into a module-level table.**
      Define `LOGO_PIECES = { {name, color_id, verts2d, z_offset, half_depth}, ... }`
      with the three polygons in centered/normalized coordinates (apply
      the transform from the context section to the raw SVG numbers, hard-code
      the results — don't compute the transform at runtime).
      Verify by printing the table from a Lua scratch buffer; check that
      coordinates are in roughly [-1,1]^2.
  - Test: open nvim, `:lua print(vim.inspect(require('dashboard').LOGO_PIECES))`
    and eyeball: x ranges ~[-0.82,0.82], y ranges ~[-1,1], cross diagonal
    goes from upper-left (negative x, positive y) to lower-right.

- [ ] **Step 2: build face data per piece (one-time, at load).**
      For each piece, produce `faces = { {nx, ny, nz, d}, ... }` with:
        - 1 front cap face: n=(0,0,+1), d = +half_depth + z_offset
        - 1 back cap face:  n=(0,0,-1), d = +half_depth - z_offset
            (signs chosen so plane equation dot(p,n) = d defines the
             outward half-space)
        - one side face per polygon edge: take edge (v_i, v_{i+1}), build
          the outward 2D normal (rotate edge by -90°), normalize, lift to
          3D with z=0; d = dot(midpoint, normal)
      Also store original normals separately so we can rotate them per
      frame without re-deriving from scratch.
  - Test: assert each piece has the expected number of faces (7, 7, 6).
    Pick one interior point per piece (e.g., the centroid of its 2D
    polygon, z=z_offset), and assert dot(p,n) < d for every face — proves
    the centroid is inside, which proves the outward-normal sign is correct.

- [ ] **Step 3: implement `render_logo(W, H, t)` returning ASCII rows + piece rows.**
      Reuse the camera/aspect setup from `render_orbs` (pinhole, focal 1.6,
      `inv_h = 2 * inv_w`, ray origin at z=-3). Start with rotation
      DISABLED (R = identity, ignore t). Per pixel: rotate face normals
      via the slab test, write char + piece id.
  - Test: temporarily wire the dashboard to render logo at a fixed
    rotation and inspect the buffer visually. Front view should show the
    silhouette of an "N" (left bar + diagonal + right bar). If pieces
    are missing, the outward normals from step 2 are wrong.

- [ ] **Step 4: add Y-axis spin and a small X tilt.**
      `R = R_x(0.30) * R_y(t * 0.5)`. Apply R to face normals each frame
      (compose into a 3x3 once per frame, then 6/7 per-face rotations).
      Update plane offsets — they DON'T change (rotation preserves
      centered geometry distances).
  - Test: open dashboard, watch one full revolution. The N silhouette
    should spin smoothly. At ~90° the prisms become thin strips
    (we're seeing the side faces). At ~180° we see a mirrored N.
    The slight X tilt should reveal the top caps subtly.

- [ ] **Step 5: define highlight groups and apply per-cell coloring.**
      In `M.open` (or once-only via `M.setup`), call `nvim_set_hl` for
      `DashboardLogoBlue` and `DashboardLogoGreen`. Create an autocmd
      namespace `state.ns = api.nvim_create_namespace("dashboard_logo")`.
      In `tick()` for logo mode, after `nvim_buf_set_lines`:
        - clear namespace
        - for each row, scan piece-id array, for each contiguous run of
          piece_id != 0 emit one extmark with `hl_group` set
          appropriately (blue for piece 1, green for pieces 2 and 3).
  - Test: dashboard renders; left vertical of N is blue, right vertical
    AND diagonal cross are green. Background characters remain
    uncolored. Resizing the window doesn't leak old extmarks.

- [ ] **Step 6: wire `MODE_LOGO` into `M.open`.**
      Either add a parameter `M.open(mode)` defaulting to a random
      choice among the three modes, or pick logo as the new default and
      keep the others as alternates. Existing `tick()` already dispatches
      on `state.mode`.
  - Test: opening nvim with no args lands on the new logo dashboard.
    `q`/`<Esc>` still tear down cleanly. Switching between modes via
    explicit `:lua require('dashboard').open('logo')` etc. works.

- [ ] **Step 7: performance pass (only if needed).**
      Worst case: 80×40 = 3200 pixels × 3 pieces × ~7 faces = 67k plane
      tests per frame. Should be fine in plain Lua at 30 fps. If not,
      hoist invariants out of the per-pixel loop (rotated normals already
      hoisted) and consider an early reject by piece bounding sphere.
  - Test: visually verify smooth animation; if stuttering, profile with
    `vim.uv.hrtime()` deltas around `render_logo`.
