-- apartment_generator/furniture_placer.lua
local config = dofile("config.lua")
local sr = dofile("spatial_rules.lua")
local M = {}

-- Get wall segments of a room as { wall_name, start_pos, end_pos, normal_dx, normal_dz }
function M.get_walls(room)
    local x, z, w, d = room.x, room.z, room.width, room.depth
    return {
        { name = "south", x1 = x, z1 = z, x2 = x + w, z2 = z, nx = 0, nz = 1 },
        { name = "north", x1 = x, z1 = z + d, x2 = x + w, z2 = z + d, nx = 0, nz = -1 },
        { name = "west",  x1 = x, z1 = z, x2 = x, z2 = z + d, nx = 1, nz = 0 },
        { name = "east",  x1 = x + w, z1 = z, x2 = x + w, z2 = z + d, nx = -1, nz = 0 },
    }
end

-- Check if a wall has a door on it
function M.wall_has_door(room, wall_name)
    for _, door in ipairs(room.doors or {}) do
        if door.wall == wall_name then return true, door end
    end
    return false
end

-- Generate candidate positions along a wall for furniture of size (fw, fd)
-- Returns list of { x, z, rotation } in global coords
function M.wall_candidates(room, wall_name, fw, fd)
    local gap = config.apartment.furniture_wall_gap
    local x, z, w, d = room.x, room.z, room.width, room.depth
    local candidates = {}
    local step = 0.5

    if wall_name == "south" then
        for offset = fw/2, w - fw/2, step do
            candidates[#candidates + 1] = { x = x + offset, z = z + gap + fd/2, rotation = 0 }
        end
    elseif wall_name == "north" then
        for offset = fw/2, w - fw/2, step do
            candidates[#candidates + 1] = { x = x + offset, z = z + d - gap - fd/2, rotation = 180 }
        end
    elseif wall_name == "west" then
        for offset = fd/2, d - fd/2, step do
            candidates[#candidates + 1] = { x = x + gap + fw/2, z = z + offset, rotation = 90 }
        end
    elseif wall_name == "east" then
        for offset = fd/2, d - fd/2, step do
            candidates[#candidates + 1] = { x = x + w - gap - fw/2, z = z + offset, rotation = 270 }
        end
    end

    return candidates
end

-- Generate candidate positions in room center
function M.center_candidates(room, fw, fd)
    local cx = room.x + room.width / 2
    local cz = room.z + room.depth / 2
    local candidates = {}
    -- Try center and slight offsets
    for dx = -1, 1, 0.5 do
        for dz = -1, 1, 0.5 do
            candidates[#candidates + 1] = { x = cx + dx, z = cz + dz, rotation = 0 }
        end
    end
    return candidates
end

-- Generate candidate positions in room corners
function M.corner_candidates(room, fw, fd)
    local gap = config.apartment.furniture_wall_gap
    local x, z, w, d = room.x, room.z, room.width, room.depth
    return {
        { x = x + gap + fw/2,     z = z + gap + fd/2,     rotation = 0 },
        { x = x + w - gap - fw/2, z = z + gap + fd/2,     rotation = 0 },
        { x = x + gap + fw/2,     z = z + d - gap - fd/2, rotation = 0 },
        { x = x + w - gap - fw/2, z = z + d - gap - fd/2, rotation = 0 },
    }
end

-- Try to place a single furniture item in a room
-- Returns { type, x, z, width, depth, height, rotation } or nil
function M.try_place(template, room, placed_aabbs, placed_items)
    local fw, fd, fh = template.w, template.d, template.h
    local candidates = {}
    local rule = template.rule

    if rule == "against_wall" or rule == "against_wall_facing_opposite" or rule == "against_wall_not_door" or rule == "headboard_against_wall" or rule == "against_wall_near_window" then
        -- Try all walls, prefer walls without doors
        local walls_order = { "north", "south", "east", "west" }
        -- Shuffle to add variety
        for i = #walls_order, 2, -1 do
            local j = math.random(i)
            walls_order[i], walls_order[j] = walls_order[j], walls_order[i]
        end
        for _, wn in ipairs(walls_order) do
            local has_door = M.wall_has_door(room, wn)
            if rule == "against_wall_not_door" and has_door then goto skip_wall end
            -- For wall placements, swap fw/fd if wall is east/west
            local eff_w, eff_d = fw, fd
            if wn == "east" or wn == "west" then eff_w, eff_d = fd, fw end
            local wall_cands = M.wall_candidates(room, wn, eff_w, eff_d)
            for _, c in ipairs(wall_cands) do candidates[#candidates + 1] = c end
            ::skip_wall::
        end
    elseif rule == "center" then
        candidates = M.center_candidates(room, fw, fd)
    elseif rule == "corner" then
        candidates = M.corner_candidates(room, fw, fd)
    elseif rule == "in_front_of_sofa" then
        -- Find sofa in placed_items, place 0.5m in front of it
        for _, item in ipairs(placed_items) do
            if item.type == "sofa" then
                local sofa_front_z = item.z
                if item.rotation == 0 then sofa_front_z = item.z + item.depth/2 + 0.5 + fd/2
                elseif item.rotation == 180 then sofa_front_z = item.z - item.depth/2 - 0.5 - fd/2
                end
                candidates[#candidates + 1] = { x = item.x, z = sofa_front_z, rotation = item.rotation }
            end
        end
        -- Fallback to center if no sofa found
        if #candidates == 0 then candidates = M.center_candidates(room, fw, fd) end
    elseif rule == "against_wall_opposite_sofa" then
        -- Find sofa, place on opposite wall
        for _, item in ipairs(placed_items) do
            if item.type == "sofa" then
                if item.rotation == 0 then -- sofa on south wall, TV on north
                    local cands = M.wall_candidates(room, "north", fw, fd)
                    for _, c in ipairs(cands) do candidates[#candidates + 1] = c end
                elseif item.rotation == 180 then
                    local cands = M.wall_candidates(room, "south", fw, fd)
                    for _, c in ipairs(cands) do candidates[#candidates + 1] = c end
                else
                    local cands = M.wall_candidates(room, "west", fd, fw)
                    for _, c in ipairs(cands) do candidates[#candidates + 1] = c end
                end
            end
        end
        if #candidates == 0 then
            for _, wn in ipairs({"north","south","east","west"}) do
                local cands = M.wall_candidates(room, wn, fw, fd)
                for _, c in ipairs(cands) do candidates[#candidates + 1] = c end
            end
        end
    elseif rule == "beside_bed" then
        for _, item in ipairs(placed_items) do
            if item.type == "double_bed" or item.type == "single_bed" then
                -- Place on left side of bed
                candidates[#candidates + 1] = { x = item.x - item.width/2 - fw/2 - 0.05, z = item.z - item.depth/2 + fd/2, rotation = 0 }
                -- Place on right side of bed
                candidates[#candidates + 1] = { x = item.x + item.width/2 + fw/2 + 0.05, z = item.z - item.depth/2 + fd/2, rotation = 0 }
            end
        end
    elseif rule == "at_desk" then
        for _, item in ipairs(placed_items) do
            if item.type == "desk" then
                -- Place chair in front of desk
                candidates[#candidates + 1] = { x = item.x, z = item.z + item.depth/2 + fd/2 + 0.1, rotation = 180 }
                candidates[#candidates + 1] = { x = item.x, z = item.z - item.depth/2 - fd/2 - 0.1, rotation = 0 }
            end
        end
    elseif rule == "around_table" then
        for _, item in ipairs(placed_items) do
            if item.type == "dining_table" then
                local gap = 0.6
                -- 4 chairs around table
                candidates[#candidates + 1] = { x = item.x - item.width/2 - gap, z = item.z, rotation = 90 }
                candidates[#candidates + 1] = { x = item.x + item.width/2 + gap, z = item.z, rotation = 270 }
                candidates[#candidates + 1] = { x = item.x, z = item.z - item.depth/2 - gap, rotation = 0 }
                candidates[#candidates + 1] = { x = item.x, z = item.z + item.depth/2 + gap, rotation = 180 }
            end
        end
    elseif rule == "l_shape_walls" or rule == "on_counter" then
        -- For kitchen counter and stove, just use wall placement
        for _, wn in ipairs({"south","west","east","north"}) do
            if not M.wall_has_door(room, wn) then
                local cands = M.wall_candidates(room, wn, fw, fd)
                for _, c in ipairs(cands) do candidates[#candidates + 1] = c end
            end
        end
    else
        -- Default: try all walls then center then corners
        for _, wn in ipairs({"north","south","east","west"}) do
            local cands = M.wall_candidates(room, wn, fw, fd)
            for _, c in ipairs(cands) do candidates[#candidates + 1] = c end
        end
        local center = M.center_candidates(room, fw, fd)
        for _, c in ipairs(center) do candidates[#candidates + 1] = c end
    end

    -- Try each candidate position
    for _, cand in ipairs(candidates) do
        local aabb = sr.aabb(cand.x, cand.z, fw, fd)
        local valid, reason = sr.validate_placement(aabb, fh, room, placed_aabbs)
        if valid then
            return {
                type = template.type,
                x = cand.x,
                z = cand.z,
                width = fw,
                depth = fd,
                height = fh,
                rotation = cand.rotation,
            }, aabb
        end
    end

    return nil, nil
end

-- Place all furniture in a single room
function M.furnish_room(room)
    local templates = config.furniture_templates[room.id]
    if not templates then return {} end

    local placed_items = {}
    local placed_aabbs = {}

    -- Sort: required first, then optional
    local sorted = {}
    for _, t in ipairs(templates) do sorted[#sorted + 1] = t end
    table.sort(sorted, function(a, b)
        if a.required ~= b.required then return a.required end
        return false
    end)

    for _, template in ipairs(sorted) do
        local count = template.count or 1
        for c = 1, count do
            local item, aabb = M.try_place(template, room, placed_aabbs, placed_items)
            if item then
                placed_items[#placed_items + 1] = item
                placed_aabbs[#placed_aabbs + 1] = aabb
            elseif template.required then
                -- Try shrinking by 10%
                local shrunk = {}
                for k, v in pairs(template) do shrunk[k] = v end
                shrunk.w = template.w * 0.9
                shrunk.d = template.d * 0.9
                item, aabb = M.try_place(shrunk, room, placed_aabbs, placed_items)
                if item then
                    placed_items[#placed_items + 1] = item
                    placed_aabbs[#placed_aabbs + 1] = aabb
                end
            end
            -- Optional furniture: just skip if can't place
        end
    end

    -- Final passage validation
    if room.doors and #room.doors > 0 then
        local door = room.doors[1]
        local door_x, door_z
        if door.wall == "north" then
            door_x = room.x + door.offset
            door_z = room.z + room.depth - 0.2
        elseif door.wall == "south" then
            door_x = room.x + door.offset
            door_z = room.z + 0.2
        elseif door.wall == "east" then
            door_x = room.x + room.width - 0.2
            door_z = room.z + door.offset
        else
            door_x = room.x + 0.2
            door_z = room.z + door.offset
        end

        local passable = sr.check_passage(room, placed_aabbs, door_x, door_z)
        if not passable and #placed_items > 0 then
            -- Remove lowest-priority (last) item and recheck
            local removed = table.remove(placed_items)
            table.remove(placed_aabbs)
            -- Could recurse, but one removal is usually enough
        end
    end

    return placed_items
end

-- Furnish all rooms in a layout
function M.furnish_all(rooms)
    for _, room in ipairs(rooms) do
        room.furniture = M.furnish_room(room)
    end
    return rooms
end

return M
