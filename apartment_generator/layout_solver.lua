-- apartment_generator/layout_solver.lua
local config = dofile("config.lua")
local sr = dofile("spatial_rules.lua")
local M = {}

-- Seed random for reproducibility (can be overridden)
math.randomseed(os.time())

-- Calculate initial room dimensions from area, respecting max 3:1 aspect ratio
function M.calc_room_dims(room_def)
    local area = (room_def.min_area + room_def.max_area) / 2
    -- Start with square, then randomize aspect ratio within 1:1 to 2.5:1
    local ratio = 1.0 + math.random() * 1.5
    local w = math.sqrt(area * ratio)
    local d = area / w
    -- Enforce max 3:1
    if w / d > 3 then d = w / 3 end
    if d / w > 3 then w = d / 3 end
    return w, d
end

-- Zone-based initial position
function M.initial_position(room_def, apt_w, apt_d)
    local x, z
    local zone = room_def.zone
    if zone == "south" then
        x = math.random() * apt_w * 0.6
        z = math.random() * apt_d * 0.3
    elseif zone == "north" then
        x = math.random() * apt_w * 0.6
        z = apt_d * 0.5 + math.random() * apt_d * 0.4
    elseif zone == "east" then
        x = apt_w * 0.6 + math.random() * apt_w * 0.3
        z = math.random() * apt_d * 0.4
    elseif zone == "center" then
        x = apt_w * 0.2 + math.random() * apt_w * 0.3
        z = apt_d * 0.3 + math.random() * apt_d * 0.3
    else
        x = math.random() * apt_w * 0.5
        z = math.random() * apt_d * 0.5
    end
    return x, z
end

-- Initialize all rooms with dimensions and positions
function M.init_rooms()
    local rooms = {}
    local apt = config.apartment
    for _, def in ipairs(config.rooms) do
        local w, d = M.calc_room_dims(def)
        local x, z = M.initial_position(def, apt.width, apt.depth)
        rooms[#rooms + 1] = {
            id = def.id,
            name = def.name,
            x = x,
            z = z,
            width = w,
            depth = d,
            priority = def.priority,
            zone = def.zone,
        }
    end
    return rooms
end

-- Helper: get center of a room
function M.center(room)
    return room.x + room.width / 2, room.z + room.depth / 2
end

-- Helper: distance between room centers
function M.distance(r1, r2)
    local cx1, cz1 = M.center(r1)
    local cx2, cz2 = M.center(r2)
    local dx = cx2 - cx1
    local dz = cz2 - cz1
    return math.sqrt(dx * dx + dz * dz), dx, dz
end

-- Compute overlap between two rooms (as AABBs from corner + size)
function M.room_overlap(r1, r2)
    local a = sr.aabb(r1.x + r1.width/2, r1.z + r1.depth/2, r1.width, r1.depth)
    local b = sr.aabb(r2.x + r2.width/2, r2.z + r2.depth/2, r2.width, r2.depth)
    return sr.overlap_area(a, b)
end

-- Build adjacency lookup: room_id -> set of adjacent room_ids
function M.build_adjacency_map()
    local adj = {}
    for _, pair in ipairs(config.adjacency) do
        if not adj[pair[1]] then adj[pair[1]] = {} end
        if not adj[pair[2]] then adj[pair[2]] = {} end
        adj[pair[1]][pair[2]] = true
        adj[pair[2]][pair[1]] = true
    end
    return adj
end

-- Compute all forces for one iteration
-- Returns table of { id -> { fx, fz } }
function M.compute_forces(rooms, adj_map)
    local forces = {}
    local apt = config.apartment
    local k_attract = 0.05
    local k_repel = 0.2
    local k_boundary = 0.3

    for _, r in ipairs(rooms) do
        forces[r.id] = { fx = 0, fz = 0 }
    end

    -- Pairwise forces
    for i = 1, #rooms do
        for j = i + 1, #rooms do
            local ri, rj = rooms[i], rooms[j]
            local dist, dx, dz = M.distance(ri, rj)
            if dist < 0.01 then dist = 0.01; dx = 0.01; dz = 0 end
            local nx, nz = dx / dist, dz / dist

            -- Attraction (only for adjacent rooms)
            if adj_map[ri.id] and adj_map[ri.id][rj.id] then
                local target_dist = (ri.width + rj.width) / 4 + (ri.depth + rj.depth) / 4
                if dist > target_dist then
                    local f = k_attract * (dist - target_dist)
                    forces[ri.id].fx = forces[ri.id].fx + nx * f
                    forces[ri.id].fz = forces[ri.id].fz + nz * f
                    forces[rj.id].fx = forces[rj.id].fx - nx * f
                    forces[rj.id].fz = forces[rj.id].fz - nz * f
                end
            end

            -- Repulsion (for overlapping rooms)
            local overlap = M.room_overlap(ri, rj)
            if overlap > 0 then
                local f = k_repel * overlap
                forces[ri.id].fx = forces[ri.id].fx - nx * f
                forces[ri.id].fz = forces[ri.id].fz - nz * f
                forces[rj.id].fx = forces[rj.id].fx + nx * f
                forces[rj.id].fz = forces[rj.id].fz + nz * f
            end
        end
    end

    -- Boundary forces
    for _, r in ipairs(rooms) do
        local f = forces[r.id]
        -- Left boundary
        if r.x < 0 then
            f.fx = f.fx + k_boundary * (-r.x)
        end
        -- Right boundary
        if r.x + r.width > apt.width then
            f.fx = f.fx - k_boundary * (r.x + r.width - apt.width)
        end
        -- Bottom boundary
        if r.z < 0 then
            f.fz = f.fz + k_boundary * (-r.z)
        end
        -- Top boundary
        if r.z + r.depth > apt.depth then
            f.fz = f.fz - k_boundary * (r.z + r.depth - apt.depth)
        end
    end

    return forces
end

-- Snap value to grid
function M.snap(val, grid)
    return math.floor(val / grid + 0.5) * grid
end

-- Snap all room edges to grid
function M.snap_rooms(rooms)
    local grid = config.apartment.grid_snap
    for _, r in ipairs(rooms) do
        r.x = M.snap(r.x, grid)
        r.z = M.snap(r.z, grid)
        r.width = math.max(grid, M.snap(r.width, grid))
        r.depth = math.max(grid, M.snap(r.depth, grid))
    end
end

-- Clamp rooms inside apartment boundary
function M.clamp_rooms(rooms)
    local apt = config.apartment
    for _, r in ipairs(rooms) do
        r.x = math.max(0, math.min(apt.width - r.width, r.x))
        r.z = math.max(0, math.min(apt.depth - r.depth, r.z))
    end
end

-- Run the force-directed solver
function M.solve(iterations)
    iterations = iterations or 200
    local rooms = M.init_rooms()
    local adj_map = M.build_adjacency_map()

    for iter = 1, iterations do
        local forces = M.compute_forces(rooms, adj_map)
        -- Apply forces with damping (decreases over iterations)
        local damping = 1.0 - (iter / iterations) * 0.8
        for _, r in ipairs(rooms) do
            local f = forces[r.id]
            r.x = r.x + f.fx * damping
            r.z = r.z + f.fz * damping
        end
        M.clamp_rooms(rooms)
    end

    -- Post-processing
    M.snap_rooms(rooms)
    M.clamp_rooms(rooms)

    -- Resolve any remaining overlaps with greedy nudging
    for pass = 1, 50 do
        local any_overlap = false
        for i = 1, #rooms do
            for j = i + 1, #rooms do
                local overlap = M.room_overlap(rooms[i], rooms[j])
                if overlap > 0.01 then
                    any_overlap = true
                    local _, dx, dz = M.distance(rooms[i], rooms[j])
                    local dist = math.sqrt(dx*dx + dz*dz)
                    if dist < 0.01 then dx = 1; dz = 0; dist = 1 end
                    local push = math.sqrt(overlap) * 0.5
                    rooms[i].x = rooms[i].x - (dx/dist) * push
                    rooms[i].z = rooms[i].z - (dz/dist) * push
                    rooms[j].x = rooms[j].x + (dx/dist) * push
                    rooms[j].z = rooms[j].z + (dz/dist) * push
                end
            end
        end
        M.snap_rooms(rooms)
        M.clamp_rooms(rooms)
        if not any_overlap then break end
    end

    return rooms
end

-- Find shared wall between two rooms (if they are touching)
-- Returns wall info or nil
function M.find_shared_wall(r1, r2)
    local tolerance = 0.6 -- rooms within 0.6m count as "touching"

    -- r1's north wall == r2's south wall?
    if math.abs((r1.z + r1.depth) - r2.z) < tolerance then
        local overlap_start = math.max(r1.x, r2.x)
        local overlap_end = math.min(r1.x + r1.width, r2.x + r2.width)
        if overlap_end - overlap_start > config.apartment.door_width then
            return {
                room1 = r1.id, room2 = r2.id,
                wall_r1 = "north", wall_r2 = "south",
                x = (overlap_start + overlap_end) / 2,
                z = r1.z + r1.depth,
                shared_length = overlap_end - overlap_start,
            }
        end
    end

    -- r1's south wall == r2's north wall?
    if math.abs(r1.z - (r2.z + r2.depth)) < tolerance then
        local overlap_start = math.max(r1.x, r2.x)
        local overlap_end = math.min(r1.x + r1.width, r2.x + r2.width)
        if overlap_end - overlap_start > config.apartment.door_width then
            return {
                room1 = r1.id, room2 = r2.id,
                wall_r1 = "south", wall_r2 = "north",
                x = (overlap_start + overlap_end) / 2,
                z = r1.z,
                shared_length = overlap_end - overlap_start,
            }
        end
    end

    -- r1's east wall == r2's west wall?
    if math.abs((r1.x + r1.width) - r2.x) < tolerance then
        local overlap_start = math.max(r1.z, r2.z)
        local overlap_end = math.min(r1.z + r1.depth, r2.z + r2.depth)
        if overlap_end - overlap_start > config.apartment.door_width then
            return {
                room1 = r1.id, room2 = r2.id,
                wall_r1 = "east", wall_r2 = "west",
                x = r1.x + r1.width,
                z = (overlap_start + overlap_end) / 2,
                shared_length = overlap_end - overlap_start,
            }
        end
    end

    -- r1's west wall == r2's east wall?
    if math.abs(r1.x - (r2.x + r2.width)) < tolerance then
        local overlap_start = math.max(r1.z, r2.z)
        local overlap_end = math.min(r1.z + r1.depth, r2.z + r2.depth)
        if overlap_end - overlap_start > config.apartment.door_width then
            return {
                room1 = r1.id, room2 = r2.id,
                wall_r1 = "west", wall_r2 = "east",
                x = r1.x,
                z = (overlap_start + overlap_end) / 2,
                shared_length = overlap_end - overlap_start,
            }
        end
    end

    return nil
end

-- Place doors for all adjacency pairs
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
                local door = {
                    room1 = wall.room1,
                    room2 = wall.room2,
                    x = wall.x,
                    z = wall.z,
                    width = config.apartment.door_width,
                    height = config.apartment.door_height,
                }
                doors[#doors + 1] = door

                -- Add door info to room objects for furniture_placer
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

-- Generate wall segments (exterior + interior between rooms)
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

    -- Interior walls: for each room edge that borders another room
    local edges = {} -- track unique edges to avoid duplicates
    for _, r in ipairs(rooms) do
        -- North edge
        local key_n = string.format("h_%.1f_%.1f_%.1f", r.z + r.depth, r.x, r.x + r.width)
        if not edges[key_n] and r.z + r.depth < apt.depth - 0.1 then
            edges[key_n] = true
            walls[#walls + 1] = { x1 = r.x, z1 = r.z + r.depth, x2 = r.x + r.width, z2 = r.z + r.depth, height = h, thickness = t, type = "interior" }
        end
        -- South edge
        local key_s = string.format("h_%.1f_%.1f_%.1f", r.z, r.x, r.x + r.width)
        if not edges[key_s] and r.z > 0.1 then
            edges[key_s] = true
            walls[#walls + 1] = { x1 = r.x, z1 = r.z, x2 = r.x + r.width, z2 = r.z, height = h, thickness = t, type = "interior" }
        end
        -- East edge
        local key_e = string.format("v_%.1f_%.1f_%.1f", r.x + r.width, r.z, r.z + r.depth)
        if not edges[key_e] and r.x + r.width < apt.width - 0.1 then
            edges[key_e] = true
            walls[#walls + 1] = { x1 = r.x + r.width, z1 = r.z, x2 = r.x + r.width, z2 = r.z + r.depth, height = h, thickness = t, type = "interior" }
        end
        -- West edge
        local key_w = string.format("v_%.1f_%.1f_%.1f", r.x, r.z, r.z + r.depth)
        if not edges[key_w] and r.x > 0.1 then
            edges[key_w] = true
            walls[#walls + 1] = { x1 = r.x, z1 = r.z, x2 = r.x, z2 = r.z + r.depth, height = h, thickness = t, type = "interior" }
        end
    end

    return walls
end

-- Place windows on exterior-facing walls
function M.place_windows(rooms)
    local apt = config.apartment
    local windows = {}

    for _, r in ipairs(rooms) do
        local win_rule = config.window_rules[r.id]
        if not win_rule then goto continue end

        if not r.windows then r.windows = {} end

        -- Check each wall for exterior exposure
        -- South wall (z == 0)
        if math.abs(r.z) < 0.5 then
            local win = { wall = "south", offset = r.width / 2, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
            r.windows[#r.windows + 1] = win
            windows[#windows + 1] = { room = r.id, wall = "south", x = r.x + r.width / 2, z = r.z, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
        end
        -- North wall (z + depth == apt.depth)
        if math.abs(r.z + r.depth - apt.depth) < 0.5 then
            local win = { wall = "north", offset = r.width / 2, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
            r.windows[#r.windows + 1] = win
            windows[#windows + 1] = { room = r.id, wall = "north", x = r.x + r.width / 2, z = r.z + r.depth, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
        end
        -- East wall (x + width == apt.width)
        if math.abs(r.x + r.width - apt.width) < 0.5 then
            local win = { wall = "east", offset = r.depth / 2, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
            r.windows[#r.windows + 1] = win
            windows[#windows + 1] = { room = r.id, wall = "east", x = r.x + r.width, z = r.z + r.depth / 2, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
        end
        -- West wall (x == 0)
        if math.abs(r.x) < 0.5 then
            local win = { wall = "west", offset = r.depth / 2, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
            r.windows[#r.windows + 1] = win
            windows[#windows + 1] = { room = r.id, wall = "west", x = r.x, z = r.z + r.depth / 2, width = win_rule.width, height = win_rule.height, sill_height = win_rule.sill }
        end

        ::continue::
    end

    return windows
end

-- Full layout generation: rooms + doors + walls + windows
function M.generate(iterations)
    local rooms = M.solve(iterations)
    local doors = M.place_doors(rooms)
    local walls = M.generate_walls(rooms)
    local windows = M.place_windows(rooms)
    return {
        rooms = rooms,
        doors = doors,
        walls = walls,
        windows = windows,
    }
end

return M
