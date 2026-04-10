-- apartment_generator/test.lua
-- Assert-based test suite for the apartment generator
local passed = 0
local failed = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  PASS: " .. name)
    else
        failed = failed + 1
        print("  FAIL: " .. name .. " - " .. tostring(err))
    end
end

print("\n=== Config Tests ===")
local config = dofile("config.lua")

test("config has 9 rooms", function()
    assert(#config.rooms == 9)
end)

test("config has 8 adjacency pairs", function()
    assert(#config.adjacency == 8)
end)

test("all rooms have required fields", function()
    for _, r in ipairs(config.rooms) do
        assert(r.id, "missing id")
        assert(r.min_area, "missing min_area for " .. r.id)
        assert(r.max_area, "missing max_area for " .. r.id)
        assert(r.min_area < r.max_area, "min >= max for " .. r.id)
    end
end)

test("furniture templates exist for all rooms", function()
    for _, r in ipairs(config.rooms) do
        assert(config.furniture_templates[r.id], "no furniture template for " .. r.id)
    end
end)

test("total min area fits in apartment", function()
    local total = 0
    for _, r in ipairs(config.rooms) do total = total + r.min_area end
    local apt_area = config.apartment.width * config.apartment.depth
    assert(total < apt_area, "rooms too large: " .. total .. " > " .. apt_area)
end)

print("\n=== Spatial Rules Tests ===")
local sr = dofile("spatial_rules.lua")

test("AABB overlap detection", function()
    local a = sr.aabb(5, 5, 4, 4)
    local b = sr.aabb(8, 5, 4, 4)
    assert(sr.aabb_overlap(a, b))
    local c = sr.aabb(20, 20, 2, 2)
    assert(not sr.aabb_overlap(a, c))
end)

test("AABB overlap area", function()
    local a = sr.aabb(5, 5, 4, 4)
    local b = sr.aabb(8, 5, 4, 4)
    local area = sr.overlap_area(a, b)
    assert(math.abs(area - 4.0) < 0.01, "expected 4, got " .. area)
end)

test("AABB contains", function()
    local outer = sr.aabb(5, 5, 10, 10)
    local inner = sr.aabb(5, 5, 4, 4)
    assert(sr.aabb_contains(outer, inner))
    local outside = sr.aabb(15, 15, 2, 2)
    assert(not sr.aabb_contains(outer, outside))
end)

test("door clearance blocks furniture", function()
    local room = { x = 0, z = 0, width = 10, depth = 8, doors = { { wall = "north", offset = 5, width = 1.2 } } }
    local blocked = sr.aabb(5, 7.5, 1.0, 1.0)
    assert(not sr.check_door_clearance(blocked, room, 1.5))
end)

test("door clearance allows distant furniture", function()
    local room = { x = 0, z = 0, width = 10, depth = 8, doors = { { wall = "north", offset = 5, width = 1.2 } } }
    local safe = sr.aabb(2, 2, 1.0, 1.0)
    assert(sr.check_door_clearance(safe, room, 1.5))
end)

test("furniture inside room passes", function()
    local room = { x = 0, z = 0, width = 10, depth = 8 }
    assert(sr.check_inside_room(sr.aabb(5, 4, 2, 2), room))
end)

test("furniture outside room fails", function()
    local room = { x = 0, z = 0, width = 10, depth = 8 }
    assert(not sr.check_inside_room(sr.aabb(11, 4, 4, 2), room))
end)

test("furniture spacing check", function()
    local existing = { sr.aabb(5, 5, 2, 2) }
    -- Too close (0.3m gap, min is 0.4)
    assert(not sr.check_furniture_spacing(sr.aabb(5, 7.1, 2, 2), existing, 0.4))
    -- Far enough
    assert(sr.check_furniture_spacing(sr.aabb(5, 8, 2, 2), existing, 0.4))
end)

test("BFS passage check - open room passes", function()
    local room = { x = 0, z = 0, width = 6, depth = 6 }
    assert(sr.check_passage(room, {}, 3, 0.2))
end)

test("BFS passage check - blocked room fails", function()
    local room = { x = 0, z = 0, width = 4, depth = 4 }
    -- Wall of furniture blocking the room
    local blocked = {
        sr.aabb(2, 2, 3.5, 3.5),
    }
    assert(not sr.check_passage(room, blocked, 2, 0.2))
end)

print("\n=== Layout Solver Tests ===")
local ls = dofile("layout_solver.lua")

test("init_rooms creates 9 rooms", function()
    local rooms = ls.init_rooms()
    assert(#rooms == 9)
end)

test("rooms have valid dimensions", function()
    local rooms = ls.init_rooms()
    for _, r in ipairs(rooms) do
        assert(r.width > 0, r.id .. " width <= 0")
        assert(r.depth > 0, r.id .. " depth <= 0")
        -- Corridor can be long and narrow (gallery style), so allow up to 7:1
        local max_ratio = (r.id == "corridor") and 7.1 or 3.1
        local ratio = math.max(r.width / r.depth, r.depth / r.width)
        assert(ratio <= max_ratio, r.id .. " aspect ratio too high: " .. string.format("%.1f", ratio))
    end
end)

test("solver produces non-overlapping rooms", function()
    math.randomseed(42)
    local rooms = ls.solve(200)
    for i = 1, #rooms do
        for j = i + 1, #rooms do
            local overlap = ls.room_overlap(rooms[i], rooms[j])
            assert(overlap < 2, rooms[i].id .. " and " .. rooms[j].id .. " overlap by " .. string.format("%.1f", overlap))
        end
    end
end)

test("solver keeps rooms in bounds", function()
    math.randomseed(42)
    local rooms = ls.solve(200)
    for _, r in ipairs(rooms) do
        assert(r.x >= -0.5, r.id .. " x out of bounds: " .. r.x)
        assert(r.z >= -0.5, r.id .. " z out of bounds: " .. r.z)
        assert(r.x + r.width <= config.apartment.width + 0.5, r.id .. " extends past right boundary")
        assert(r.z + r.depth <= config.apartment.depth + 0.5, r.id .. " extends past top boundary")
    end
end)

test("door placement finds shared walls", function()
    math.randomseed(42)
    local layout = ls.generate(1)
    assert(#layout.doors > 0, "no doors placed")
end)

test("full layout generation succeeds", function()
    math.randomseed(42)
    local layout = ls.generate(1)
    assert(#layout.rooms == 9, "expected 9 rooms")
    assert(#layout.walls > 4, "expected more than 4 walls (exterior only)")
end)

print("\n=== Furniture Placer Tests ===")
local fp = dofile("furniture_placer.lua")

test("furnish master bedroom places bed and wardrobe", function()
    local room = {
        id = "master_bed", name = "主卧",
        x = 0, z = 0, width = 8, depth = 7,
        doors = { { wall = "south", offset = 4, width = 1.2 } },
        windows = {},
    }
    local items = fp.furnish_room(room)
    local has_bed = false
    for _, item in ipairs(items) do
        if item.type == "double_bed" then has_bed = true end
    end
    assert(has_bed, "no bed placed in master bedroom")
    assert(#items >= 3, "expected at least 3 items, got " .. #items)
end)

test("furnish living room places sofa and tv cabinet", function()
    local room = {
        id = "living", name = "客厅",
        x = 0, z = 0, width = 12, depth = 10,
        doors = { { wall = "north", offset = 6, width = 1.2 } },
        windows = {},
    }
    local items = fp.furnish_room(room)
    local has_sofa, has_tv = false, false
    for _, item in ipairs(items) do
        if item.type == "sofa" then has_sofa = true end
        if item.type == "tv_cabinet" then has_tv = true end
    end
    assert(has_sofa, "no sofa in living room")
    assert(has_tv, "no TV cabinet in living room")
end)

test("furniture does not overlap with door clearance", function()
    local room = {
        id = "bath_2", name = "公卫",
        x = 0, z = 0, width = 3, depth = 3,
        doors = { { wall = "south", offset = 1.5, width = 1.2 } },
        windows = {},
    }
    local items = fp.furnish_room(room)
    local clearance = config.apartment.door_clearance
    local door_zones = sr.door_clearance_zones(room, clearance)
    for _, item in ipairs(items) do
        local aabb = sr.aabb(item.x, item.z, item.width, item.depth)
        for _, zone in ipairs(door_zones) do
            assert(not sr.aabb_overlap(aabb, zone),
                item.type .. " overlaps door clearance zone!")
        end
    end
end)

print("\n=== Integration Tests ===")
local main = dofile("main.lua")

test("full pipeline generates complete output", function()
    local output = main.generate(42, 1)
    assert(output.apartment, "missing apartment config")
    assert(output.rooms, "missing rooms")
    assert(output.walls, "missing walls")
    assert(#output.rooms == 9, "expected 9 rooms, got " .. #output.rooms)
end)

test("serializer round-trips correctly", function()
    local output = main.generate(42, 1)
    local serialized = "return " .. main.serialize(output)
    local fn = load(serialized)
    assert(fn, "serialized output is not valid Lua")
    local loaded = fn()
    assert(#loaded.rooms == #output.rooms, "room count mismatch after round-trip")
end)

test("all rooms have furniture", function()
    local output = main.generate(42, 1)
    for _, room in ipairs(output.rooms) do
        -- Corridor furniture is optional, so skip it
        if room.id ~= "corridor" then
            assert(#room.furniture > 0, room.id .. " has no furniture")
        end
    end
end)

-- Summary
print("\n========================================")
print(string.format("  Results: %d passed, %d failed", passed, failed))
print("========================================")
if failed > 0 then
    os.exit(1)
end
