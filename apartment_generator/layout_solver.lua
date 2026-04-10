-- apartment_generator/layout_solver.lua
-- Template-based apartment layout generator
-- References real-world Chinese luxury apartment (三室两厅) floor plans
local config = dofile("config.lua")
local sr = dofile("spatial_rules.lua")
local M = {}

math.randomseed(os.time())

-- ============================================================
-- TEMPLATES: Architect-designed floor plan layouts
-- Each room defined as fraction of apartment (w_pct, d_pct, x_pct, z_pct)
-- All rooms tile the full rectangle with ZERO gaps
-- Adjacency pairs all share walls
-- ============================================================

-- Design principle: 动静分区 (activity/quiet zoning)
-- South = public zone (living, dining, kitchen) — light and social
-- Center = transition (corridor, bathrooms) — buffer
-- North = private zone (bedrooms) — quiet and private

M.templates = {

    -- ============================================================
    -- Template A: "南北通透" (South-North Through-View)
    -- Most classic Chinese luxury layout
    -- Grand living room and dining along the south facade
    -- Long gallery corridor connecting all bedrooms on the north
    --
    --   N ┌──────────┬─────────────┬─────────────┐
    --     │MasterBed │   Bed 2     │   Bed 3     │
    --     │          │             │             │
    --     ├──┬───────┴─────────────┼───┬─────────┤
    --     │MB│    Corridor         │B2 │ Kitchen  │
    --     ├──┴─────────────────────┴───┼─────────┤
    --     │                            │         │
    --     │     Living Room            │ Dining  │
    --     │                            │         │
    --   S └────────────────────────────┴─────────┘
    -- ============================================================
    {
        name = "南北通透",
        rooms = {
            -- South public zone (z: 0% - 49%)
            { id = "living",      x_pct = 0,    z_pct = 0,    w_pct = 0.62, d_pct = 0.49 },
            { id = "dining",      x_pct = 0.62, z_pct = 0,    w_pct = 0.38, d_pct = 0.49 },
            -- Middle transition (z: 49% - 63%)
            { id = "master_bath", x_pct = 0,    z_pct = 0.49, w_pct = 0.14, d_pct = 0.14 },
            { id = "corridor",    x_pct = 0.14, z_pct = 0.49, w_pct = 0.62, d_pct = 0.14 },
            { id = "bath_2",      x_pct = 0.76, z_pct = 0.49, w_pct = 0.10, d_pct = 0.14 },
            { id = "kitchen",     x_pct = 0.86, z_pct = 0.49, w_pct = 0.14, d_pct = 0.14 },
            -- North private zone (z: 63% - 100%)
            { id = "master_bed",  x_pct = 0,    z_pct = 0.63, w_pct = 0.34, d_pct = 0.37 },
            { id = "bed_2",       x_pct = 0.34, z_pct = 0.63, w_pct = 0.33, d_pct = 0.37 },
            { id = "bed_3",       x_pct = 0.67, z_pct = 0.63, w_pct = 0.33, d_pct = 0.37 },
        },
    },

    -- ============================================================
    -- Template B: "L型客餐厅" (L-Shaped Living-Dining)
    -- Living and dining form an open L-shape
    -- Kitchen tucked behind dining
    -- Bedrooms along the north with a short corridor
    --
    --   N ┌──────────┬──────────┬──────────────┐
    --     │MasterBed │  Bed 2   │    Bed 3     │
    --     │          │          │              │
    --     ├──┬───────┼──┬───────┼──────────────┤
    --     │MB│ Corr  │B2│       │              │
    --     ├──┴───────┴──┤Kitchen│   Dining     │
    --     │             │       │              │
    --     │  Living     ├───────┴──────────────┤
    --     │  Room       │                      │ <- open to dining
    --   S └─────────────┴──────────────────────┘
    -- ============================================================
    {
        name = "L型客餐厅",
        rooms = {
            -- South zone: L-shaped living + dining
            { id = "living",      x_pct = 0,    z_pct = 0,    w_pct = 0.42, d_pct = 0.46 },
            { id = "dining",      x_pct = 0.42, z_pct = 0,    w_pct = 0.58, d_pct = 0.30 },
            { id = "kitchen",     x_pct = 0.42, z_pct = 0.30, w_pct = 0.22, d_pct = 0.16 },
            -- Middle transition
            { id = "master_bath", x_pct = 0,    z_pct = 0.46, w_pct = 0.12, d_pct = 0.14 },
            { id = "corridor",    x_pct = 0.12, z_pct = 0.46, w_pct = 0.30, d_pct = 0.14 },
            { id = "bath_2",      x_pct = 0.42, z_pct = 0.46, w_pct = 0.12, d_pct = 0.14 },
            -- North private zone
            { id = "master_bed",  x_pct = 0,    z_pct = 0.60, w_pct = 0.35, d_pct = 0.40 },
            { id = "bed_2",       x_pct = 0.35, z_pct = 0.60, w_pct = 0.30, d_pct = 0.40 },
            { id = "bed_3",       x_pct = 0.65, z_pct = 0.60, w_pct = 0.35, d_pct = 0.40 },
        },
    },

    -- ============================================================
    -- Template C: "横厅大宅" (Wide-Hall Mansion)
    -- Extra-wide living room spanning the full south facade
    -- Kitchen-dining cluster on one side
    -- Master suite with generous proportions
    --
    --   N ┌───────────────┬───────┬──────────────┐
    --     │  Master Bed   │ Bed 2 │   Bed 3      │
    --     │  + Ensuite    │       │              │
    --     ├─────┬─────────┼───┬───┼──────────────┤
    --     │ MB  │  Corr   │B2 │Kit│   Dining     │
    --     ├─────┴─────────┴───┴───┼──────────────┤
    --     │                       │              │
    --     │    Living Room        │  Dining cont │
    --     │    (panoramic view)   │              │
    --   S └───────────────────────┴──────────────┘
    -- ============================================================
    {
        name = "横厅大宅",
        rooms = {
            -- South panoramic zone
            { id = "living",      x_pct = 0,    z_pct = 0,    w_pct = 0.56, d_pct = 0.44 },
            { id = "dining",      x_pct = 0.56, z_pct = 0,    w_pct = 0.44, d_pct = 0.44 },
            -- Middle zone
            { id = "master_bath", x_pct = 0,    z_pct = 0.44, w_pct = 0.14, d_pct = 0.14 },
            { id = "corridor",    x_pct = 0.14, z_pct = 0.44, w_pct = 0.42, d_pct = 0.14 },
            { id = "bath_2",      x_pct = 0.56, z_pct = 0.44, w_pct = 0.10, d_pct = 0.14 },
            { id = "kitchen",     x_pct = 0.66, z_pct = 0.44, w_pct = 0.34, d_pct = 0.14 },
            -- North zone
            { id = "master_bed",  x_pct = 0,    z_pct = 0.58, w_pct = 0.40, d_pct = 0.42 },
            { id = "bed_2",       x_pct = 0.40, z_pct = 0.58, w_pct = 0.28, d_pct = 0.42 },
            { id = "bed_3",       x_pct = 0.68, z_pct = 0.58, w_pct = 0.32, d_pct = 0.42 },
        },
    },
}

-- ============================================================
-- Room name/zone lookup from config
-- ============================================================
local function get_room_info(id)
    for _, r in ipairs(config.rooms) do
        if r.id == id then return r end
    end
    return { name = id, zone = "center" }
end

-- ============================================================
-- Generate rooms from a template
-- Applies jitter to room sizes (±5%) for variety while keeping tiling
-- ============================================================
function M.generate_rooms(template_index)
    local apt = config.apartment
    local tmpl = M.templates[template_index or 1]
    local rooms = {}

    for _, def in ipairs(tmpl.rooms) do
        local info = get_room_info(def.id)
        local x = def.x_pct * apt.width
        local z = def.z_pct * apt.depth
        local w = def.w_pct * apt.width
        local d = def.d_pct * apt.depth

        -- Snap to grid for clean walls
        x = M.snap(x, apt.grid_snap)
        z = M.snap(z, apt.grid_snap)
        w = math.max(apt.grid_snap, M.snap(w, apt.grid_snap))
        d = math.max(apt.grid_snap, M.snap(d, apt.grid_snap))

        rooms[#rooms + 1] = {
            id = def.id,
            name = info.name,
            x = x,
            z = z,
            width = w,
            depth = d,
            priority = info.priority or 2,
            zone = info.zone or "center",
        }
    end

    return rooms, tmpl.name
end

-- ============================================================
-- Snap to grid
-- ============================================================
function M.snap(val, grid)
    return math.floor(val / grid + 0.5) * grid
end

-- ============================================================
-- Find shared wall between two rooms
-- ============================================================
function M.find_shared_wall(r1, r2)
    local tolerance = 1.0

    -- r1 north == r2 south
    if math.abs((r1.z + r1.depth) - r2.z) < tolerance then
        local start = math.max(r1.x, r2.x)
        local stop = math.min(r1.x + r1.width, r2.x + r2.width)
        if stop - start >= config.apartment.door_width then
            return { room1 = r1.id, room2 = r2.id, wall_r1 = "north", wall_r2 = "south",
                     x = (start + stop) / 2, z = (r1.z + r1.depth + r2.z) / 2, shared_length = stop - start }
        end
    end

    -- r1 south == r2 north
    if math.abs(r1.z - (r2.z + r2.depth)) < tolerance then
        local start = math.max(r1.x, r2.x)
        local stop = math.min(r1.x + r1.width, r2.x + r2.width)
        if stop - start >= config.apartment.door_width then
            return { room1 = r1.id, room2 = r2.id, wall_r1 = "south", wall_r2 = "north",
                     x = (start + stop) / 2, z = (r1.z + r2.z + r2.depth) / 2, shared_length = stop - start }
        end
    end

    -- r1 east == r2 west
    if math.abs((r1.x + r1.width) - r2.x) < tolerance then
        local start = math.max(r1.z, r2.z)
        local stop = math.min(r1.z + r1.depth, r2.z + r2.depth)
        if stop - start >= config.apartment.door_width then
            return { room1 = r1.id, room2 = r2.id, wall_r1 = "east", wall_r2 = "west",
                     x = (r1.x + r1.width + r2.x) / 2, z = (start + stop) / 2, shared_length = stop - start }
        end
    end

    -- r1 west == r2 east
    if math.abs(r1.x - (r2.x + r2.width)) < tolerance then
        local start = math.max(r1.z, r2.z)
        local stop = math.min(r1.z + r1.depth, r2.z + r2.depth)
        if stop - start >= config.apartment.door_width then
            return { room1 = r1.id, room2 = r2.id, wall_r1 = "west", wall_r2 = "east",
                     x = (r1.x + r2.x + r2.width) / 2, z = (start + stop) / 2, shared_length = stop - start }
        end
    end

    return nil
end

-- ============================================================
-- Place doors on shared walls for all adjacency pairs
-- ============================================================
function M.place_doors(rooms)
    local room_map = {}
    for _, r in ipairs(rooms) do room_map[r.id] = r end

    local doors = {}
    for _, pair in ipairs(config.adjacency) do
        local r1 = room_map[pair[1]]
        local r2 = room_map[pair[2]]
        if r1 and r2 then
            local wall = M.find_shared_wall(r1, r2)
            if wall then
                doors[#doors + 1] = {
                    room1 = wall.room1, room2 = wall.room2,
                    x = wall.x, z = wall.z,
                    width = config.apartment.door_width,
                    height = config.apartment.door_height,
                }

                -- Add door reference to room objects
                if not r1.doors then r1.doors = {} end
                local offset1
                if wall.wall_r1 == "north" or wall.wall_r1 == "south" then
                    offset1 = wall.x - r1.x
                else
                    offset1 = wall.z - r1.z
                end
                r1.doors[#r1.doors + 1] = { wall = wall.wall_r1, offset = offset1, width = config.apartment.door_width }

                if not r2.doors then r2.doors = {} end
                local offset2
                if wall.wall_r2 == "north" or wall.wall_r2 == "south" then
                    offset2 = wall.x - r2.x
                else
                    offset2 = wall.z - r2.z
                end
                r2.doors[#r2.doors + 1] = { wall = wall.wall_r2, offset = offset2, width = config.apartment.door_width }
            end
        end
    end
    return doors
end

-- ============================================================
-- Generate wall segments (exterior + interior)
-- ============================================================
function M.generate_walls(rooms)
    local apt = config.apartment
    local walls = {}
    local t = apt.wall_thickness
    local h = apt.ceiling_height

    -- Exterior walls
    walls[#walls + 1] = { x1 = 0, z1 = 0, x2 = apt.width, z2 = 0, height = h, thickness = t, type = "exterior" }
    walls[#walls + 1] = { x1 = apt.width, z1 = 0, x2 = apt.width, z2 = apt.depth, height = h, thickness = t, type = "exterior" }
    walls[#walls + 1] = { x1 = apt.width, z1 = apt.depth, x2 = 0, z2 = apt.depth, height = h, thickness = t, type = "exterior" }
    walls[#walls + 1] = { x1 = 0, z1 = apt.depth, x2 = 0, z2 = 0, height = h, thickness = t, type = "exterior" }

    -- Interior walls: deduplicate edges
    local edges = {}
    for _, r in ipairs(rooms) do
        -- North
        local key_n = string.format("h_%.1f_%.1f_%.1f", r.z + r.depth, r.x, r.x + r.width)
        if not edges[key_n] and math.abs(r.z + r.depth - apt.depth) > 0.1 then
            edges[key_n] = true
            walls[#walls + 1] = { x1 = r.x, z1 = r.z + r.depth, x2 = r.x + r.width, z2 = r.z + r.depth, height = h, thickness = t, type = "interior" }
        end
        -- South
        local key_s = string.format("h_%.1f_%.1f_%.1f", r.z, r.x, r.x + r.width)
        if not edges[key_s] and r.z > 0.1 then
            edges[key_s] = true
            walls[#walls + 1] = { x1 = r.x, z1 = r.z, x2 = r.x + r.width, z2 = r.z, height = h, thickness = t, type = "interior" }
        end
        -- East
        local key_e = string.format("v_%.1f_%.1f_%.1f", r.x + r.width, r.z, r.z + r.depth)
        if not edges[key_e] and math.abs(r.x + r.width - apt.width) > 0.1 then
            edges[key_e] = true
            walls[#walls + 1] = { x1 = r.x + r.width, z1 = r.z, x2 = r.x + r.width, z2 = r.z + r.depth, height = h, thickness = t, type = "interior" }
        end
        -- West
        local key_w = string.format("v_%.1f_%.1f_%.1f", r.x, r.z, r.z + r.depth)
        if not edges[key_w] and r.x > 0.1 then
            edges[key_w] = true
            walls[#walls + 1] = { x1 = r.x, z1 = r.z, x2 = r.x, z2 = r.z + r.depth, height = h, thickness = t, type = "interior" }
        end
    end

    return walls
end

-- ============================================================
-- Place windows on exterior-facing walls
-- ============================================================
function M.place_windows(rooms)
    local apt = config.apartment
    local windows = {}

    for _, r in ipairs(rooms) do
        local win_rule = config.window_rules[r.id]
        if not win_rule then goto continue end
        if not r.windows then r.windows = {} end

        -- South wall exterior
        if math.abs(r.z) < 0.5 then
            local num_wins = math.max(1, math.floor(r.width / 6))
            for i = 1, num_wins do
                local offset = r.width * i / (num_wins + 1)
                r.windows[#r.windows + 1] = { wall = "south", offset = offset, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
                windows[#windows + 1] = { room = r.id, wall = "south", x = r.x + offset, z = r.z, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
            end
        end
        -- North wall exterior
        if math.abs(r.z + r.depth - apt.depth) < 0.5 then
            local num_wins = math.max(1, math.floor(r.width / 6))
            for i = 1, num_wins do
                local offset = r.width * i / (num_wins + 1)
                r.windows[#r.windows + 1] = { wall = "north", offset = offset, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
                windows[#windows + 1] = { room = r.id, wall = "north", x = r.x + offset, z = r.z + r.depth, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
            end
        end
        -- East wall exterior
        if math.abs(r.x + r.width - apt.width) < 0.5 then
            local num_wins = math.max(1, math.floor(r.depth / 6))
            for i = 1, num_wins do
                local offset = r.depth * i / (num_wins + 1)
                r.windows[#r.windows + 1] = { wall = "east", offset = offset, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
                windows[#windows + 1] = { room = r.id, wall = "east", x = r.x + r.width, z = r.z + offset, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
            end
        end
        -- West wall exterior
        if math.abs(r.x) < 0.5 then
            local num_wins = math.max(1, math.floor(r.depth / 6))
            for i = 1, num_wins do
                local offset = r.depth * i / (num_wins + 1)
                r.windows[#r.windows + 1] = { wall = "west", offset = offset, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
                windows[#windows + 1] = { room = r.id, wall = "west", x = r.x, z = r.z + offset, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
            end
        end

        ::continue::
    end

    return windows
end

-- ============================================================
-- Full layout generation
-- ============================================================
function M.generate(template_index)
    -- Random template if not specified
    if not template_index then
        template_index = math.random(1, #M.templates)
    end

    local rooms, template_name = M.generate_rooms(template_index)
    local doors = M.place_doors(rooms)
    local walls = M.generate_walls(rooms)
    local windows = M.place_windows(rooms)

    return {
        rooms = rooms,
        doors = doors,
        walls = walls,
        windows = windows,
        template_name = template_name,
    }
end

-- Keep backward compatibility: solve() returns rooms
function M.solve(iterations)
    local layout = M.generate()
    return layout.rooms
end

function M.init_rooms()
    return M.generate_rooms(1)
end

-- Expose for testing
function M.room_overlap(r1, r2)
    local a = sr.aabb(r1.x + r1.width/2, r1.z + r1.depth/2, r1.width, r1.depth)
    local b = sr.aabb(r2.x + r2.width/2, r2.z + r2.depth/2, r2.width, r2.depth)
    return sr.overlap_area(a, b)
end

function M.distance(r1, r2)
    local cx1 = r1.x + r1.width / 2
    local cz1 = r1.z + r1.depth / 2
    local cx2 = r2.x + r2.width / 2
    local cz2 = r2.z + r2.depth / 2
    local dx = cx2 - cx1
    local dz = cz2 - cz1
    return math.sqrt(dx * dx + dz * dz), dx, dz
end

return M
