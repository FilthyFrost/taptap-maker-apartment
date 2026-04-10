-- apartment_generator/spatial_rules.lua
local config = dofile("config.lua")
local M = {}

-- AABB: { x, z, w, d } where (x,z) is center, w is width (x-axis), d is depth (z-axis)

function M.aabb(cx, cz, w, d)
    return { x = cx, z = cz, w = w, d = d }
end

function M.aabb_min_x(a) return a.x - a.w / 2 end
function M.aabb_max_x(a) return a.x + a.w / 2 end
function M.aabb_min_z(a) return a.z - a.d / 2 end
function M.aabb_max_z(a) return a.z + a.d / 2 end

function M.aabb_overlap(a, b)
    return M.aabb_min_x(a) < M.aabb_max_x(b)
       and M.aabb_max_x(a) > M.aabb_min_x(b)
       and M.aabb_min_z(a) < M.aabb_max_z(b)
       and M.aabb_max_z(a) > M.aabb_min_z(b)
end

function M.aabb_contains(outer, inner)
    return M.aabb_min_x(inner) >= M.aabb_min_x(outer)
       and M.aabb_max_x(inner) <= M.aabb_max_x(outer)
       and M.aabb_min_z(inner) >= M.aabb_min_z(outer)
       and M.aabb_max_z(inner) <= M.aabb_max_z(outer)
end

function M.overlap_area(a, b)
    local ox = math.max(0, math.min(M.aabb_max_x(a), M.aabb_max_x(b)) - math.max(M.aabb_min_x(a), M.aabb_min_x(b)))
    local oz = math.max(0, math.min(M.aabb_max_z(a), M.aabb_max_z(b)) - math.max(M.aabb_min_z(a), M.aabb_min_z(b)))
    return ox * oz
end

-- Returns list of AABB clearance zones for all doors in a room
-- room: { x, z, width, depth, doors: { {wall, offset, width} ... } }
function M.door_clearance_zones(room, clearance)
    local zones = {}
    local rx, rz = room.x, room.z
    local rw, rd = room.width, room.depth
    for _, door in ipairs(room.doors or {}) do
        local dw = door.width
        if door.wall == "north" then
            local dx = rx + door.offset
            local dz = rz + rd
            -- clearance zone inside room
            zones[#zones + 1] = M.aabb(dx, dz - clearance / 2, dw, clearance)
            -- clearance zone outside room (in adjacent room/corridor)
            zones[#zones + 1] = M.aabb(dx, dz + clearance / 2, dw, clearance)
        elseif door.wall == "south" then
            local dx = rx + door.offset
            local dz = rz
            zones[#zones + 1] = M.aabb(dx, dz + clearance / 2, dw, clearance)
            zones[#zones + 1] = M.aabb(dx, dz - clearance / 2, dw, clearance)
        elseif door.wall == "east" then
            local dx = rx + rw
            local dz = rz + door.offset
            zones[#zones + 1] = M.aabb(dx - clearance / 2, dz, clearance, dw)
            zones[#zones + 1] = M.aabb(dx + clearance / 2, dz, clearance, dw)
        elseif door.wall == "west" then
            local dx = rx
            local dz = rz + door.offset
            zones[#zones + 1] = M.aabb(dx + clearance / 2, dz, clearance, dw)
            zones[#zones + 1] = M.aabb(dx - clearance / 2, dz, clearance, dw)
        end
    end
    return zones
end

-- Check if a furniture AABB violates any door clearance zone
function M.check_door_clearance(furniture_aabb, room, clearance)
    local zones = M.door_clearance_zones(room, clearance)
    for _, zone in ipairs(zones) do
        if M.aabb_overlap(furniture_aabb, zone) then
            return false, zone -- blocked
        end
    end
    return true -- clear
end

-- BFS reachability check on a 2D grid
-- room: { x, z, width, depth }
-- blocked: list of AABBs (furniture)
-- start: { x, z } (door position)
-- cell_size: grid cell size in meters (default 0.4)
-- Returns true if all non-blocked cells are reachable from start
function M.check_passage(room, blocked_aabbs, door_x, door_z, cell_size)
    cell_size = cell_size or 0.4
    local cols = math.floor(room.width / cell_size)
    local rows = math.floor(room.depth / cell_size)
    if cols < 1 or rows < 1 then return true end

    -- Build grid: false = free, true = blocked
    local grid = {}
    for r = 1, rows do
        grid[r] = {}
        for c = 1, cols do
            grid[r][c] = false
        end
    end

    -- Mark blocked cells
    for _, aabb in ipairs(blocked_aabbs) do
        local min_c = math.max(1, math.floor((M.aabb_min_x(aabb) - room.x) / cell_size) + 1)
        local max_c = math.min(cols, math.ceil((M.aabb_max_x(aabb) - room.x) / cell_size))
        local min_r = math.max(1, math.floor((M.aabb_min_z(aabb) - room.z) / cell_size) + 1)
        local max_r = math.min(rows, math.ceil((M.aabb_max_z(aabb) - room.z) / cell_size))
        for r = min_r, max_r do
            for c = min_c, max_c do
                grid[r][c] = true
            end
        end
    end

    -- Convert door world position to grid cell
    local start_c = math.max(1, math.min(cols, math.floor((door_x - room.x) / cell_size) + 1))
    local start_r = math.max(1, math.min(rows, math.floor((door_z - room.z) / cell_size) + 1))

    -- If start cell is blocked, nudge to nearest free cell
    if grid[start_r][start_c] then
        local found = false
        for dr = -2, 2 do
            for dc = -2, 2 do
                local nr, nc = start_r + dr, start_c + dc
                if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols and not grid[nr][nc] then
                    start_r, start_c = nr, nc
                    found = true
                    break
                end
            end
            if found then break end
        end
        if not found then return false end
    end

    -- BFS
    local visited = {}
    for r = 1, rows do
        visited[r] = {}
    end
    local queue = { { start_r, start_c } }
    visited[start_r][start_c] = true
    local head = 1

    while head <= #queue do
        local r, c = queue[head][1], queue[head][2]
        head = head + 1
        for _, d in ipairs({ {-1,0}, {1,0}, {0,-1}, {0,1} }) do
            local nr, nc = r + d[1], c + d[2]
            if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
               and not grid[nr][nc] and not visited[nr] then
                -- visited[nr] might not exist yet as a table
            end
            if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
               and not grid[nr][nc] and not (visited[nr] and visited[nr][nc]) then
                if not visited[nr] then visited[nr] = {} end
                visited[nr][nc] = true
                queue[#queue + 1] = { nr, nc }
            end
        end
    end

    -- Count free cells and visited cells
    local free_count = 0
    local visited_count = 0
    for r = 1, rows do
        for c = 1, cols do
            if not grid[r][c] then
                free_count = free_count + 1
                if visited[r] and visited[r][c] then
                    visited_count = visited_count + 1
                end
            end
        end
    end

    -- At least 80% of free space must be reachable from door
    if free_count == 0 then return true end
    return (visited_count / free_count) >= 0.8
end

-- Check furniture doesn't overlap with any existing furniture (min gap)
function M.check_furniture_spacing(new_aabb, existing_aabbs, min_gap)
    min_gap = min_gap or config.apartment.furniture_min_gap
    -- Expand new_aabb by min_gap on each side for gap check
    local expanded = M.aabb(new_aabb.x, new_aabb.z, new_aabb.w + min_gap, new_aabb.d + min_gap)
    for _, existing in ipairs(existing_aabbs) do
        if M.aabb_overlap(expanded, existing) then
            return false
        end
    end
    return true
end

-- Check furniture is fully inside room boundaries
function M.check_inside_room(furniture_aabb, room)
    local room_aabb = M.aabb(
        room.x + room.width / 2,
        room.z + room.depth / 2,
        room.width,
        room.depth
    )
    return M.aabb_contains(room_aabb, furniture_aabb)
end

-- Check window clearance: no tall furniture within 0.8m of window
function M.check_window_clearance(furniture_aabb, furniture_height, room, sill_height)
    sill_height = sill_height or 0.9
    if furniture_height <= sill_height then return true end
    for _, win in ipairs(room.windows or {}) do
        local wz_center, wx_center
        local clearance = 0.8
        if win.wall == "south" then
            wx_center = room.x + win.offset
            wz_center = room.z
            local zone = M.aabb(wx_center, wz_center + clearance / 2, win.width, clearance)
            if M.aabb_overlap(furniture_aabb, zone) then return false end
        elseif win.wall == "north" then
            wx_center = room.x + win.offset
            wz_center = room.z + room.depth
            local zone = M.aabb(wx_center, wz_center - clearance / 2, win.width, clearance)
            if M.aabb_overlap(furniture_aabb, zone) then return false end
        elseif win.wall == "east" then
            wz_center = room.z + win.offset
            wx_center = room.x + room.width
            local zone = M.aabb(wx_center - clearance / 2, wz_center, clearance, win.width)
            if M.aabb_overlap(furniture_aabb, zone) then return false end
        elseif win.wall == "west" then
            wz_center = room.z + win.offset
            wx_center = room.x
            local zone = M.aabb(wx_center + clearance / 2, wz_center, clearance, win.width)
            if M.aabb_overlap(furniture_aabb, zone) then return false end
        end
    end
    return true
end

-- Combined validation: run all checks for a single furniture placement
-- Returns true if placement is valid, false + reason string if not
function M.validate_placement(furniture_aabb, furniture_height, room, existing_aabbs)
    if not M.check_inside_room(furniture_aabb, room) then
        return false, "outside_room"
    end
    if not M.check_furniture_spacing(furniture_aabb, existing_aabbs) then
        return false, "too_close"
    end
    local clear, _ = M.check_door_clearance(furniture_aabb, room, config.apartment.door_clearance)
    if not clear then
        return false, "door_blocked"
    end
    if not M.check_window_clearance(furniture_aabb, furniture_height, room) then
        return false, "window_blocked"
    end
    return true
end

return M
