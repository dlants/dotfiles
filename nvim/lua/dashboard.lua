local M = {}

local uv = vim.uv or vim.loop
local api = vim.api

local sin, cos, sqrt, exp = math.sin, math.cos, math.sqrt, math.exp
local atan2, acos = math.atan2, math.acos
local mmax, mmin, mabs = math.max, math.min, math.abs
local floor = math.floor

local RAMP = " .:-=+*#%@"
local RAMP_N = #RAMP - 1

local FRAME_MS = 33 -- ~30 fps

local MODE_ORBS = "orbs"
local MODE_LIFE = "life"
local MODE_LOGO = "logo"
local MAX_STEPS = 32
local MAX_DIST = 6.0
local EPS = 0.002

-- Max render area in cells; rest of the window is padded with spaces.
local MAX_W = 80
local MAX_H = 40

local TITLE = "neovim"
local TITLE_GAP = 2

local N_ORBS = 12
local POISSON_LAMBDA = 2.2

local function poisson(lambda)
  local L = math.exp(-lambda)
  local k, p = 0, 1.0
  repeat
    k = k + 1
    p = p * math.random()
  until p < L
  return k - 1
end

-- Each orb: { orbit_speed, phase, orbit_radius_xy, orbit_radius_z, ball_radius }
-- Ball radius drawn from Poisson(lambda) -> mapped to a radius scale, so we
-- get many small orbs and occasional large ones (long-tailed distribution).
local function generate_orbs()
  math.randomseed(os.time())
  for _ = 1, 3 do math.random() end -- discard early correlated samples
  local orbs = {}
  for i = 1, N_ORBS do
    local k = poisson(POISSON_LAMBDA)
    local r = 0.20 + 0.13 * k -- larger overall
    local speed = 0.18 / (r + 0.05) * (0.85 + math.random() * 0.30)
    orbs[i] = {
      speed, -- slower for big orbs
      math.random() * 6.2832,
      0.40 + math.random() * 0.65,
      0.20 + math.random() * 0.55,
      r,
    }
  end
  return orbs
end

local ORBS = generate_orbs()
local SMIN_K = 0.50

local function smin(a, b, k)
  local h = mmax(k - mabs(a - b), 0.0) / k
  return mmin(a, b) - h * h * k * 0.25
end

-- Scene: three orbiting spheres smoothly merged.
-- We pre-compute the orbit centers per-frame in tick() and pass them in to
-- avoid recomputing trig per-pixel.
local function scene(px, py, pz, cx, cy, cz, cr, n)
  local dx = px - cx[1]; local dy = py - cy[1]; local dz = pz - cz[1]
  local d = sqrt(dx * dx + dy * dy + dz * dz) - cr[1]
  for i = 2, n do
    dx = px - cx[i]; dy = py - cy[i]; dz = pz - cz[i]
    local di = sqrt(dx * dx + dy * dy + dz * dz) - cr[i]
    d = smin(d, di, SMIN_K)
  end
  return d
end

local function normal(px, py, pz, cx, cy, cz, cr, n)
  local h = 0.01
  local nx = scene(px + h, py, pz, cx, cy, cz, cr, n)
      - scene(px - h, py, pz, cx, cy, cz, cr, n)
  local ny = scene(px, py + h, pz, cx, cy, cz, cr, n)
      - scene(px, py - h, pz, cx, cy, cz, cr, n)
  local nz = scene(px, py, pz + h, cx, cy, cz, cr, n)
      - scene(px, py, pz - h, cx, cy, cz, cr, n)
  local len = sqrt(nx * nx + ny * ny + nz * nz)
  if len < 1e-6 then return 0, 0, 1 end
  return nx / len, ny / len, nz / len
end

local function render_orbs(W, H, t)
  -- Orbit centers and radii (computed once per frame, reused per-pixel)
  local n = #ORBS
  local cx, cy, cz, cr = {}, {}, {}, {}
  for i = 1, n do
    local o = ORBS[i]
    local sp, ph, rxy, rz, br = o[1], o[2], o[3], o[4], o[5]
    cx[i] = rxy * cos(t * sp + ph)
    cy[i] = rxy * sin(t * sp * 1.3 + ph * 1.7)
    cz[i] = rz * sin(t * sp + ph)
    cr[i] = br
  end

  -- terminal cells are ~2:1 (h:w) so squash y mapping
  local half_w = W * 0.5
  local half_h = H * 0.5
  -- World->cell mapping. Cells are ~2:1 (tall:wide), so vertical world space
  -- per cell needs to be 2x horizontal so circles look round.
  local inv_w = 2.4 / W
  local inv_h = 2.0 * inv_w

  -- normalized light direction
  local lx, ly, lz = 0.5, -0.7, -0.6
  local llen = sqrt(lx * lx + ly * ly + lz * lz)
  lx, ly, lz = lx / llen, ly / llen, lz / llen

  local pulse = 0.5 + 0.5 * sin(t * 2.4)

  local lines = {}
  local row = {}
  for j = 0, H - 1 do
    local v = (j - half_h) * inv_h
    for i = 0, W - 1 do
      local u = (i - half_w) * inv_w

      -- Ray dir = normalize(u, v, focal)
      local rdx, rdy, rdz = u, v, 1.6
      local rdlen = sqrt(rdx * rdx + rdy * rdy + rdz * rdz)
      rdx = rdx / rdlen; rdy = rdy / rdlen; rdz = rdz / rdlen

      local td = 0.0
      local closest = 1e9
      local hit_intensity = -1.0

      for _ = 1, MAX_STEPS do
        local px = rdx * td
        local py = rdy * td
        local pz = -3.0 + rdz * td
        local d = scene(px, py, pz, cx, cy, cz, cr, n)
        if d < closest then closest = d end
        if d < EPS then
          local nx, ny, nz = normal(px, py, pz, cx, cy, cz, cr, n)
          local lambert = nx * lx + ny * ly + nz * lz
          if lambert < 0 then lambert = 0 end
          -- fresnel = (1 - dot(n, -rd))^3 = (1 + dot(n, rd))^3
          local fres = 1.0 + (nx * rdx + ny * rdy + nz * rdz)
          if fres < 0 then fres = 0 end
          fres = fres * fres * fres
          hit_intensity = lambert * 0.45 + fres * (0.45 + 0.55 * pulse)
          break
        end
        td = td + d
        if td > MAX_DIST then break end
      end

      local intensity
      if hit_intensity >= 0 then
        intensity = hit_intensity
      elseif closest < 0.25 then
        -- thin pulsing rim hugging the surface; falls off to blank quickly
        local rim = 1.0 - closest * 4.0
        intensity = rim * rim * (0.25 + 0.75 * pulse) * 0.7
      else
        intensity = 0
      end
      if intensity > 1 then
        intensity = 1
      elseif intensity < 0 then
        intensity = 0
      end

      local idx = floor(intensity * RAMP_N + 0.5)
      row[i + 1] = RAMP:sub(idx + 1, idx + 1)
    end
    lines[j + 1] = table.concat(row, nil, 1, W)
  end
  return lines
end

-- ============================================================================
-- Conway's Game of Life on a tumbling cube
-- ============================================================================
--
-- One Life grid per cube face, with neighbours wrapping across face edges
-- so patterns flow continuously around the cube. Cells at cube corners
-- have only 7 neighbours (the 8th would cross a vertex singularity).
-- The cube is ray-traced and tumbles around two non-commensurate axes.
-- Render rate is decoupled from generation rate to keep the tumble smooth.

local LIFE_DENSITY       = 0.30
local LIFE_N             = 28   -- cells per cube face side
local LIFE_TUMBLE_X      = 0.21 -- tumble rate around X (rad/s)
local LIFE_TUMBLE_Y      = 0.32 -- tumble rate around Y (rad/s)
local LIFE_STEP_INTERVAL = 0.25 -- seconds between Life generations

local life               = { faces = nil, nbrs = nil, last_step = 0 }

-- Per-face axes (must match the UV mapping in render_life_cube).
local FACE_NORMAL        = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
local FACE_GI_AXIS       = { { 0, 0, -1 }, { 0, 0, 1 }, { 1, 0, 0 }, { 1, 0, 0 }, { 1, 0, 0 }, { -1, 0, 0 } }
local FACE_GJ_AXIS       = { { 0, -1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, -1, 0 }, { 0, -1, 0 } }

-- Project a point near the cube onto a face and return (face, gi, gj).
local function point_to_cell(x, y, z, N)
  local ax, ay, az = mabs(x), mabs(y), mabs(z)
  local F, su, sv
  if ax >= ay and ax >= az then
    if x > 0 then
      F, su, sv = 1, -z, -y
    else
      F, su, sv = 2, z, -y
    end
  elseif ay >= az then
    if y > 0 then
      F, su, sv = 3, x, z
    else
      F, su, sv = 4, x, -z
    end
  else
    if z > 0 then
      F, su, sv = 5, x, -y
    else
      F, su, sv = 6, -x, -y
    end
  end
  local gi = floor((su + 1) * N * 0.5) + 1
  local gj = floor((sv + 1) * N * 0.5) + 1
  if gi < 1 then gi = 1 elseif gi > N then gi = N end
  if gj < 1 then gj = 1 elseif gj > N then gj = N end
  return F, gi, gj
end

-- Build flat neighbour lists for every cell. Each candidate neighbour is the
-- cell center stepped one cell-width along the face's gi/gj axes; if the
-- step falls outside two cube axes (a vertex), the candidate is dropped.
-- Each list stores triples laid out as {face, gj, gi, ...} for direct
-- indexing into faces[face][gj][gi].
local function build_nbrs(N)
  local nbrs = {}
  local step = 2 / N
  for f = 1, 6 do
    local fn        = FACE_NORMAL[f]
    local gax       = FACE_GI_AXIS[f]
    local gjax      = FACE_GJ_AXIS[f]
    local face_nbrs = {}
    for gj = 1, N do
      local row_nbrs = {}
      for gi = 1, N do
        local u = (2 * gi - 1) / N - 1
        local v = (2 * gj - 1) / N - 1
        local cx = fn[1] + gax[1] * u + gjax[1] * v
        local cy = fn[2] + gax[2] * u + gjax[2] * v
        local cz = fn[3] + gax[3] * u + gjax[3] * v
        local list = {}
        for dj = -1, 1 do
          for di = -1, 1 do
            if di ~= 0 or dj ~= 0 then
              local px = cx + gax[1] * di * step + gjax[1] * dj * step
              local py = cy + gax[2] * di * step + gjax[2] * dj * step
              local pz = cz + gax[3] * di * step + gjax[3] * dj * step
              local oc = 0
              if mabs(px) > 1.0001 then oc = oc + 1 end
              if mabs(py) > 1.0001 then oc = oc + 1 end
              if mabs(pz) > 1.0001 then oc = oc + 1 end
              if oc < 2 then
                local nF, ngi, ngj = point_to_cell(px, py, pz, N)
                list[#list + 1] = nF
                list[#list + 1] = ngj
                list[#list + 1] = ngi
              end
            end
          end
        end
        row_nbrs[gi] = list
      end
      face_nbrs[gj] = row_nbrs
    end
    nbrs[f] = face_nbrs
  end
  return nbrs
end

local function life_init()
  local faces = {}
  for f = 1, 6 do
    local g = {}
    for j = 1, LIFE_N do
      local row = {}
      for i = 1, LIFE_N do
        row[i] = math.random() < LIFE_DENSITY and 1 or 0
      end
      g[j] = row
    end
    faces[f] = g
  end
  life.faces = faces
end

local function life_step()
  local N = LIFE_N
  if not life.nbrs then life.nbrs = build_nbrs(N) end
  local faces = life.faces
  local nbrs = life.nbrs
  local nf = {}
  for f = 1, 6 do
    local g = faces[f]
    local face_new = {}
    local face_nbrs = nbrs[f]
    for j = 1, N do
      local rj = g[j]
      local row_nbrs = face_nbrs[j]
      local row = {}
      for i = 1, N do
        local list = row_nbrs[i]
        local n = 0
        for k = 1, #list, 3 do
          n = n + faces[list[k]][list[k + 1]][list[k + 2]]
        end
        if rj[i] == 1 then
          row[i] = (n == 2 or n == 3) and 1 or 0
        else
          row[i] = (n == 3) and 1 or 0
        end
      end
      face_new[j] = row
    end
    nf[f] = face_new
  end
  life.faces = nf
end

local function render_life_cube(W, H, t)
  if not life.faces then life_init() end
  if t - life.last_step >= LIFE_STEP_INTERVAL then
    life_step()
    life.last_step = t
  end

  local N = LIFE_N
  local Nh = N * 0.5
  local A_x = t * LIFE_TUMBLE_X
  local A_y = t * LIFE_TUMBLE_Y
  local cx, sx = cos(A_x), sin(A_x)
  local cy, sy = cos(A_y), sin(A_y)

  -- Orthographic projection. World ray = (origin=(u,v,-3), dir=(0,0,1));
  -- inverse-rotate by R_Y(-A_y) * R_X(-A_x) into object space where the cube sits.
  -- The direction is constant per frame; only the origin varies per pixel.
  local rdx = -cx * sy
  local rdy = sx
  local rdz = cx * cy
  -- (u,v)-independent part of each per-pixel ortho ray origin.
  local cox = 3 * cx * sy
  local coy = -3 * sx
  local coz = -3 * cx * cy

  -- Light direction world -> object space
  local lwx, lwy, lwz = 0.5, -0.7, -0.6
  local llen = sqrt(lwx * lwx + lwy * lwy + lwz * lwz)
  lwx = lwx / llen; lwy = lwy / llen; lwz = lwz / llen
  local lly = lwy * cx + lwz * sx
  local llz = -lwy * sx + lwz * cx
  local lox = lwx * cy - llz * sy
  local loz = lwx * sy + llz * cy
  local loy = lly

  local half_w = W * 0.5
  local half_h = H * 0.5
  local inv_w = 3.2 / W
  local inv_h = 2.0 * inv_w

  local faces = life.faces
  local lines = {}
  local row_chars = {}
  for jj = 0, H - 1 do
    local v = (jj - half_h) * inv_h
    local ox_v = cox + v * sx * sy
    local oy_v = coy + v * cx
    local oz_v = coz - v * sx * cy
    for ii = 0, W - 1 do
      local u = (ii - half_w) * inv_w

      -- Per-pixel orthographic ray origin (object space).
      local ox = ox_v + u * cy
      local oy = oy_v
      local oz = oz_v + u * sy

      -- Ray vs unit cube AABB [-1, 1]^3
      local tn, tf = -1e18, 1e18
      local hit = true
      if mabs(rdx) > 1e-9 then
        local t1 = (-1 - ox) / rdx
        local t2 = (1 - ox) / rdx
        if t1 > t2 then t1, t2 = t2, t1 end
        if t1 > tn then tn = t1 end
        if t2 < tf then tf = t2 end
      elseif ox < -1 or ox > 1 then
        hit = false
      end
      if hit then
        if mabs(rdy) > 1e-9 then
          local t1 = (-1 - oy) / rdy
          local t2 = (1 - oy) / rdy
          if t1 > t2 then t1, t2 = t2, t1 end
          if t1 > tn then tn = t1 end
          if t2 < tf then tf = t2 end
        elseif oy < -1 or oy > 1 then
          hit = false
        end
      end
      if hit then
        if mabs(rdz) > 1e-9 then
          local t1 = (-1 - oz) / rdz
          local t2 = (1 - oz) / rdz
          if t1 > t2 then t1, t2 = t2, t1 end
          if t1 > tn then tn = t1 end
          if t2 < tf then tf = t2 end
        elseif oz < -1 or oz > 1 then
          hit = false
        end
      end

      local intensity = 0
      if hit and tn <= tf + 1e-4 and tf >= 0 then
        local td = tn > 0 and tn or 0
        local px = ox + td * rdx
        local py = oy + td * rdy
        local pz = oz + td * rdz
        -- Snap onto the cube surface so FP slop at edges can't mis-route the face dispatch.
        if px > 1 then px = 1 elseif px < -1 then px = -1 end
        if py > 1 then py = 1 elseif py < -1 then py = -1 end
        if pz > 1 then pz = 1 elseif pz < -1 then pz = -1 end
        local apx, apy, apz = mabs(px), mabs(py), mabs(pz)

        local face_grid, fnx, fny, fnz, su, sv
        if apx >= apy and apx >= apz then
          if px > 0 then
            face_grid = faces[1]; fnx, fny, fnz = 1, 0, 0
            su, sv = -pz, -py
          else
            face_grid = faces[2]; fnx, fny, fnz = -1, 0, 0
            su, sv = pz, -py
          end
        elseif apy >= apz then
          if py > 0 then
            face_grid = faces[3]; fnx, fny, fnz = 0, 1, 0
            su, sv = px, pz
          else
            face_grid = faces[4]; fnx, fny, fnz = 0, -1, 0
            su, sv = px, -pz
          end
        else
          if pz > 0 then
            face_grid = faces[5]; fnx, fny, fnz = 0, 0, 1
            su, sv = px, -py
          else
            face_grid = faces[6]; fnx, fny, fnz = 0, 0, -1
            su, sv = -px, -py
          end
        end

        local gi = floor((su + 1) * Nh) + 1
        local gj = floor((sv + 1) * Nh) + 1
        if gi < 1 then gi = 1 elseif gi > N then gi = N end
        if gj < 1 then gj = 1 elseif gj > N then gj = N end

        local lambert = fnx * lox + fny * loy + fnz * loz
        if lambert < 0 then lambert = 0 end
        local fres = 1.0 + (fnx * rdx + fny * rdy + fnz * rdz)
        if fres < 0 then fres = 0 end
        fres = fres * fres * fres

        if face_grid[gj][gi] == 1 then
          intensity = 0.4 + lambert * 0.5 + fres * 0.3
        else
          intensity = 0.05 + lambert * 0.2 + fres * 0.15
        end
        if intensity > 1 then intensity = 1 end
      end

      local idx = floor(intensity * RAMP_N + 0.5)
      row_chars[ii + 1] = RAMP:sub(idx + 1, idx + 1)
    end
    lines[jj + 1] = table.concat(row_chars, nil, 1, W)
  end
  return lines
end

-- ============================================================================
-- Spinning Neovim mark in N64 style
-- ============================================================================
--
-- Three flat convex prisms extruded along Z, ray-traced via slab method.
-- Geometry lifted from official neovim-mark-flat.svg, centered at origin
-- and normalized so the largest extent is ±1. Coords are y-down to match
-- the rest of the file (small y = top of buffer).
--
-- Per-piece Z offsets stagger the prisms so they interlock when spinning
-- (rather than being coplanar). Color ids: 1=blue, 2=green.

local LOGO_BLUE_ID = 1
local LOGO_GREEN_ID = 2
local LOGO_TILT = 0.5
local LOGO_SPIN_BASE = 0.6
local LOGO_SPIN_AMP = 0.4
local LOGO_SPIN_MOD = 0.5
local LOGO_INSTANCES = 4
local LOGO_HALF_PI = math.pi * 0.5
local LOGO_POLY_SCALE = 0.6
local LOGO_CUBE_OFFSET = 0.55

local LOGO_PIECES = {
  -- Left pentagon (BLUE).
  {
    color_id = LOGO_BLUE_ID,
    z_offset = 0.05,
    half_depth = 0.10,
    verts2d = {
      { -0.8242, -0.5742 },
      { -0.7527, -0.6456 },
      { -0.3984, -0.1181 },
      { -0.3984, 0.9973 },
      { -0.8242, 0.5714 },
    },
  },
  -- Diagonal cross parallelogram (GREEN).
  {
    color_id = LOGO_GREEN_ID,
    z_offset = 0.0,
    half_depth = 0.10,
    verts2d = {
      { -0.3984, -1.0000 },
      { 0.7088,  0.6896 },
      { 0.3984,  1.0000 },
      { -0.7088, -0.6868 },
    },
  },
  -- Right pentagon (GREEN).
  {
    color_id = LOGO_GREEN_ID,
    z_offset = -0.05,
    half_depth = 0.10,
    verts2d = {
      { 0.8214, -0.5687 },
      { 0.3901, -1.0027 },
      { 0.3901, 0.1071 },
      { 0.7500, 0.6511 },
      { 0.8242, 0.5714 },
    },
  },
}

-- Build object-space face data for each piece.
-- Each face: { nx, ny, nz, d } such that interior = { p : dot(p, n) <= d }.
-- d is rotation-invariant since the geometry is centered at origin.
local function build_logo_faces()
  local s = LOGO_POLY_SCALE
  for _, piece in ipairs(LOGO_PIECES) do
    local raw = piece.verts2d
    local verts = {}
    -- Mirror x so each face renders as a Neovim N rather than its reflection.
    for i = 1, #raw do verts[i] = { -raw[i][1] * s, raw[i][2] * s } end
    local n = #verts
    local hd = piece.half_depth * s
    local zo = piece.z_offset * s

    -- Centroid for outward-normal sign disambiguation.
    local ccx, ccy = 0, 0
    for i = 1, n do
      ccx = ccx + verts[i][1]
      ccy = ccy + verts[i][2]
    end
    ccx = ccx / n
    ccy = ccy / n

    local faces = {}
    -- Front cap (+Z outward).
    faces[#faces + 1] = { 0, 0, 1, hd + zo }
    -- Back cap (-Z outward).
    faces[#faces + 1] = { 0, 0, -1, hd - zo }

    -- Side faces, one per polygon edge.
    for i = 1, n do
      local v1 = verts[i]
      local v2 = verts[(i % n) + 1]
      local ex = v2[1] - v1[1]
      local ey = v2[2] - v1[2]
      local nx = ey
      local ny = -ex
      local len = sqrt(nx * nx + ny * ny)
      nx = nx / len
      ny = ny / len
      local mx = (v1[1] + v2[1]) * 0.5
      local my = (v1[2] + v2[2]) * 0.5
      local d = nx * mx + ny * my
      if nx * ccx + ny * ccy > d then
        nx = -nx; ny = -ny; d = -d
      end
      faces[#faces + 1] = { nx, ny, 0, d }
    end

    piece.faces_obj = faces
  end
end

build_logo_faces()

local function render_logo(W, H, t)
  local half_w = W * 0.5
  local half_h = H * 0.5
  local inv_w = 2.0 / W
  local inv_h = 2.0 * inv_w

  -- Build LOGO_INSTANCES copies of the N, each with a 90° offset around the
  -- spin axis. R_k = R_x(LOGO_TILT) * R_y(spin_angle + k*pi/2). The spin
  -- angle has a sinusoidal velocity modulation so the rotation periodically
  -- speeds up and slows down. All offsets stay rotation-invariant since the
  -- geometry is centered at origin.
  local tc = cos(LOGO_TILT)
  local ts = sin(LOGO_TILT)
  local spin_angle = t * LOGO_SPIN_BASE + (LOGO_SPIN_AMP / LOGO_SPIN_MOD) * sin(LOGO_SPIN_MOD * t)
  local pieces_world = {}
  for k = 0, LOGO_INSTANCES - 1 do
    local angle = spin_angle + k * LOGO_HALF_PI
    local sc = cos(angle)
    local ss = sin(angle)
    local r00, r02 = sc, ss
    local r10, r12 = ts * ss, -ts * sc
    local r20, r22 = -tc * ss, tc * sc
    for pi = 1, #LOGO_PIECES do
      local piece = LOGO_PIECES[pi]
      local fobj = piece.faces_obj
      local fworld = {}
      for fi = 1, #fobj do
        local f = fobj[fi]
        local nx0, ny0, nz0, d = f[1], f[2], f[3], f[4]
        local nx = r00 * nx0 + r02 * nz0
        local ny = r10 * nx0 + tc * ny0 + r12 * nz0
        local nz = r20 * nx0 + ts * ny0 + r22 * nz0
        -- Each instance is translated outward to its cube face by cube_offset
        -- along its (object-local) +Z. Translation effect on plane offset is
        -- d_world = d_obj + dot(translation_world, n_world). Since
        -- translation_world = R_k * (0,0,cube_offset) and n_world = R_k * n_obj,
        -- and R_k is orthogonal, this collapses to cube_offset * nz_obj.
        fworld[fi] = { nx, ny, nz, d + LOGO_CUBE_OFFSET * nz0 }
      end
      pieces_world[#pieces_world + 1] = { faces = fworld, color_id = piece.color_id }
    end
  end

  -- Light direction (toward light source) in world space.
  local lx, ly, lz = 0.5, -0.7, -0.6
  local llen = sqrt(lx * lx + ly * ly + lz * lz)
  lx = lx / llen; ly = ly / llen; lz = lz / llen

  local lines = {}
  local piece_rows = {}
  local row_chars = {}
  local row_pids = {}
  local n_pieces = #pieces_world

  for jj = 0, H - 1 do
    local v = (jj - half_h) * inv_h
    for ii = 0, W - 1 do
      local u = (ii - half_w) * inv_w

      local rdx, rdy, rdz = u, v, 1.6
      local rdlen = sqrt(rdx * rdx + rdy * rdy + rdz * rdz)
      rdx = rdx / rdlen; rdy = rdy / rdlen; rdz = rdz / rdlen

      local best_t = 1e18
      local best_nx, best_ny, best_nz = 0, 0, 0
      local best_color = 0

      for pi = 1, n_pieces do
        local pw = pieces_world[pi]
        local faces = pw.faces
        local n_faces = #faces
        local tNear = -1e18
        local tFar = 1e18
        local hit_nx, hit_ny, hit_nz = 0, 0, 0
        local miss = false
        for fi = 1, n_faces do
          local f = faces[fi]
          local nx, ny, nz, d = f[1], f[2], f[3], f[4]
          local denom = rdx * nx + rdy * ny + rdz * nz
          local numer = d - (-3 * nz)
          if mabs(denom) < 1e-9 then
            if numer < 0 then
              miss = true; break
            end
          else
            local tp = numer / denom
            if denom > 0 then
              if tp < tFar then tFar = tp end
            else
              if tp > tNear then
                tNear = tp
                hit_nx, hit_ny, hit_nz = nx, ny, nz
              end
            end
          end
        end
        if not miss and tNear <= tFar and tFar >= 0 then
          local t_hit = tNear > 0 and tNear or 0
          if t_hit < best_t then
            best_t = t_hit
            best_nx, best_ny, best_nz = hit_nx, hit_ny, hit_nz
            best_color = pw.color_id
          end
        end
      end

      local intensity = 0
      if best_color > 0 then
        local lambert = best_nx * lx + best_ny * ly + best_nz * lz
        if lambert < 0 then lambert = 0 end
        local fres = 1.0 + (best_nx * rdx + best_ny * rdy + best_nz * rdz)
        if fres < 0 then fres = 0 end
        fres = fres * fres * fres
        intensity = 0.30 + lambert * 0.55 + fres * 0.20
        if intensity > 1 then intensity = 1 end
      end

      local idx = floor(intensity * RAMP_N + 0.5)
      row_chars[ii + 1] = RAMP:sub(idx + 1, idx + 1)
      row_pids[ii + 1] = best_color
    end
    lines[jj + 1] = table.concat(row_chars, nil, 1, W)
    local copied = {}
    for k = 1, W do copied[k] = row_pids[k] end
    piece_rows[jj + 1] = copied
  end
  return lines, piece_rows
end

local state = { buf = nil, win = nil, timer = nil, start = nil, active = false, mode = nil, ns = nil }

local function stop()
  if state.timer then
    state.timer:stop()
    if not state.timer:is_closing() then state.timer:close() end
    state.timer = nil
  end
  state.active = false
  if state.buf and api.nvim_buf_is_valid(state.buf) then
    pcall(api.nvim_buf_delete, state.buf, { force = true })
  end
  state.buf = nil
  state.win = nil
end

local function tick()
  if not state.active then return end
  if not (state.win and api.nvim_win_is_valid(state.win)) then return stop() end
  if not (state.buf and api.nvim_buf_is_valid(state.buf)) then return stop() end
  if api.nvim_win_get_buf(state.win) ~= state.buf then return stop() end

  local W = api.nvim_win_get_width(state.win)
  local H = api.nvim_win_get_height(state.win)
  if W < 4 or H < 4 then return end

  local rW = mmin(W, MAX_W)
  local rH = mmin(H, MAX_H)

  local ok, inner, prows
  local t = (uv.hrtime() - state.start) / 1e9
  if state.mode == MODE_LIFE then
    ok, inner = pcall(render_life_cube, rW, rH, t)
  elseif state.mode == MODE_LOGO then
    ok, inner, prows = pcall(render_logo, rW, rH, t)
  else
    ok, inner = pcall(render_orbs, rW, rH, t)
  end
  if not ok then return stop() end

  local pad_l = floor((W - rW) / 2)
  local pad_r = W - rW - pad_l
  local content_h = 1 + TITLE_GAP + rH
  local pad_t = floor((H - content_h) / 2)
  if pad_t < 0 then pad_t = 0 end
  local pad_b = H - content_h - pad_t
  if pad_b < 0 then pad_b = 0 end

  local left = string.rep(" ", pad_l)
  local right = string.rep(" ", pad_r)
  local empty = string.rep(" ", W)

  local title_pad = floor((W - #TITLE) / 2)
  if title_pad < 0 then title_pad = 0 end
  local title_line = string.rep(" ", title_pad) .. TITLE
  title_line = title_line .. string.rep(" ", W - #title_line)

  local lines = {}
  for _ = 1, pad_t do lines[#lines + 1] = empty end
  lines[#lines + 1] = title_line
  for _ = 1, TITLE_GAP do lines[#lines + 1] = empty end
  for i = 1, rH do lines[#lines + 1] = left .. inner[i] .. right end
  for _ = 1, pad_b do lines[#lines + 1] = empty end

  pcall(api.nvim_buf_set_lines, state.buf, 0, -1, false, lines)

  if state.ns then
    pcall(api.nvim_buf_clear_namespace, state.buf, state.ns, 0, -1)
    if prows then
      for i = 1, rH do
        local prow = prows[i]
        local buf_line = pad_t + TITLE_GAP + i
        local k = 1
        while k <= rW do
          local id = prow[k]
          if id ~= 0 then
            local k_start = k
            while k <= rW and prow[k] == id do k = k + 1 end
            local hl = (id == LOGO_BLUE_ID) and "DashboardLogoBlue" or "DashboardLogoGreen"
            pcall(api.nvim_buf_set_extmark, state.buf, state.ns, buf_line, pad_l + k_start - 1, {
              end_col = pad_l + k - 1,
              hl_group = hl,
            })
          else
            k = k + 1
          end
        end
      end
    end
  end
end

local LOGO_MODES = { MODE_ORBS, MODE_LIFE, MODE_LOGO }

function M.open(mode)
  if state.active then return end

  if not mode then
    mode = MODE_LOGO
  end

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = "supernova"

  api.nvim_set_current_buf(buf)
  local win = api.nvim_get_current_win()

  vim.wo[win][0].number = false
  vim.wo[win][0].relativenumber = false
  vim.wo[win][0].cursorline = false
  vim.wo[win][0].cursorcolumn = false
  vim.wo[win][0].signcolumn = "no"
  vim.wo[win][0].list = false
  vim.wo[win][0].wrap = false
  vim.wo[win][0].colorcolumn = ""
  vim.wo[win][0].foldcolumn = "0"

  -- park cursor in bottom-left so it's least obtrusive
  pcall(api.nvim_win_set_cursor, win, { api.nvim_win_get_height(win), 0 })

  state.buf = buf
  state.win = win
  state.start = uv.hrtime()
  state.active = true
  state.mode = mode
  if state.mode == MODE_LIFE then
    life.grid = nil
    life.last_step = 0
  end

  state.ns = state.ns or api.nvim_create_namespace("dashboard_logo")
  api.nvim_set_hl(0, "DashboardLogoBlue", { fg = "#3C92D2" })
  api.nvim_set_hl(0, "DashboardLogoGreen", { fg = "#57A143" })

  -- Any leave event tears down the animation cleanly.
  api.nvim_create_autocmd({ "BufWipeout", "BufLeave", "BufHidden", "WinLeave" }, {
    buffer = buf,
    callback = function() vim.schedule(stop) end,
  })

  -- Re-render immediately on resize
  api.nvim_create_autocmd("VimResized", {
    callback = function() if state.active then vim.schedule(tick) end end,
  })

  -- Quit-on-key hints
  vim.keymap.set("n", "q", stop, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", stop, { buffer = buf, nowait = true, silent = true })

  tick()
  local interval = FRAME_MS
  local timer = uv.new_timer()
  state.timer = timer
  timer:start(interval, interval, vim.schedule_wrap(tick))
end

function M.setup()
  api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      if vim.fn.argc() ~= 0 then return end
      -- empty no-name buffer => line2byte("$") == -1
      if vim.fn.line2byte("$") ~= -1 then return end
      vim.schedule(M.open)
    end,
  })
end

return M
