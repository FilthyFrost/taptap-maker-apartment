-- apartment_generator/main.lua
local config = dofile("config.lua")
local layout_solver = dofile("layout_solver.lua")
local furniture_placer = dofile("furniture_placer.lua")
local M = {}

-- Serialize a Lua value to a readable string
function M.serialize(val, indent)
    indent = indent or 0
    local pad = string.rep("    ", indent)
    local pad1 = string.rep("    ", indent + 1)
    local t = type(val)

    if t == "number" then
        return string.format("%.2f", val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        local is_array = #val > 0
        if is_array then
            for _, v in ipairs(val) do
                parts[#parts + 1] = pad1 .. M.serialize(v, indent + 1)
            end
        else
            local keys = {}
            for k in pairs(val) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local v = val[k]
                parts[#parts + 1] = pad1 .. k .. " = " .. M.serialize(v, indent + 1)
            end
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
    else
        return tostring(val)
    end
end

-- Run the full pipeline
-- template_index: 1="南北通透", 2="L型客餐厅", 3="横厅大宅", nil=random
function M.generate(seed, template_index)
    if seed then math.randomseed(seed) end

    -- Step 1: Generate room layout from template
    local layout = layout_solver.generate(template_index)
    M._template_name = layout.template_name

    -- Step 2: Place furniture in all rooms
    furniture_placer.furnish_all(layout.rooms)

    -- Step 3: Assemble final output
    local output = {
        apartment = {
            width = config.apartment.width,
            depth = config.apartment.depth,
            ceiling_height = config.apartment.ceiling_height,
            wall_thickness = config.apartment.wall_thickness,
        },
        rooms = {},
        walls = layout.walls,
    }

    for _, room in ipairs(layout.rooms) do
        output.rooms[#output.rooms + 1] = {
            id = room.id,
            name = room.name,
            x = room.x,
            z = room.z,
            width = room.width,
            depth = room.depth,
            doors = room.doors or {},
            windows = room.windows or {},
            furniture = room.furniture or {},
        }
    end

    return output
end

-- Print summary of generated layout
function M.print_summary(output)
    print("========================================")
    print("  APARTMENT LAYOUT GENERATOR")
    if M._template_name then
        print("  Template: " .. M._template_name)
    end
    print("========================================")
    print(string.format("  Size: %.0fm x %.0fm (%.0fm2)", output.apartment.width, output.apartment.depth, output.apartment.width * output.apartment.depth))
    print(string.format("  Ceiling: %.1fm", output.apartment.ceiling_height))
    print(string.format("  Walls: %d segments", #output.walls))
    print("----------------------------------------")

    local total_furniture = 0
    for _, room in ipairs(output.rooms) do
        local fcount = #room.furniture
        total_furniture = total_furniture + fcount
        print(string.format("  %-6s %-4s  %5.1fx%-5.1f  %4.0fm2  doors:%-2d  wins:%-2d  furn:%-2d",
            room.id, room.name,
            room.width, room.depth,
            room.width * room.depth,
            #room.doors, #room.windows, fcount))
    end

    print("----------------------------------------")
    print(string.format("  Total furniture: %d items", total_furniture))
    print("========================================")
end

-- CLI entry point: lua main.lua [seed] [output_file] [template: 1|2|3]
if arg and arg[0] and arg[0]:match("main%.lua$") then
    local seed = tonumber(arg[1]) or os.time()
    local output_file = arg[2]
    local template_index = tonumber(arg[3])
    print("Seed: " .. seed)
    local output = M.generate(seed, template_index)
    M.print_summary(output)

    if output_file then
        local f = io.open(output_file, "w")
        if f then
            f:write("-- Generated apartment layout (seed: " .. seed .. ")\n")
            f:write("return " .. M.serialize(output) .. "\n")
            f:close()
            print("\nLayout written to: " .. output_file)
        end
    end
end

return M
