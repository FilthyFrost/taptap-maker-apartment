-- apartment_generator/config.lua
local M = {}

M.apartment = {
    width = 50,
    depth = 35,
    wall_thickness = 0.2,
    ceiling_height = 3.5,
    door_width = 1.2,
    door_height = 2.4,
    corridor_min_width = 1.8,
    door_clearance = 1.5,
    grid_snap = 0.5,
    min_passage_width = 0.8,
    furniture_wall_gap = 0.05,
    furniture_min_gap = 0.4,
}

M.rooms = {
    { id = "living",      name = "客厅",  min_area = 80,  max_area = 120, priority = 1, zone = "south" },
    { id = "dining",      name = "餐厅",  min_area = 30,  max_area = 50,  priority = 2, zone = "south" },
    { id = "kitchen",     name = "厨房",  min_area = 20,  max_area = 35,  priority = 3, zone = "east"  },
    { id = "master_bed",  name = "主卧",  min_area = 35,  max_area = 55,  priority = 1, zone = "north" },
    { id = "bed_2",       name = "次卧1", min_area = 20,  max_area = 35,  priority = 2, zone = "north" },
    { id = "bed_3",       name = "次卧2", min_area = 18,  max_area = 30,  priority = 2, zone = "north" },
    { id = "master_bath", name = "主卫",  min_area = 10,  max_area = 18,  priority = 3, zone = "north" },
    { id = "bath_2",      name = "公卫",  min_area = 6,   max_area = 12,  priority = 3, zone = "north" },
    { id = "corridor",    name = "走廊",  min_area = 15,  max_area = 30,  priority = 1, zone = "center" },
}

M.adjacency = {
    { "corridor", "living" },
    { "corridor", "master_bed" },
    { "corridor", "bed_2" },
    { "corridor", "bed_3" },
    { "corridor", "bath_2" },
    { "living",   "dining" },
    { "dining",   "kitchen" },
    { "master_bed", "master_bath" },
}

M.furniture_templates = {
    living = {
        { type = "sofa",         w = 2.5, d = 1.0, h = 0.9, required = true,  rule = "against_wall_facing_opposite" },
        { type = "coffee_table", w = 1.2, d = 0.6, h = 0.45, required = true,  rule = "in_front_of_sofa" },
        { type = "tv_cabinet",   w = 2.0, d = 0.5, h = 0.6, required = true,  rule = "against_wall_opposite_sofa" },
        { type = "floor_lamp",   w = 0.4, d = 0.4, h = 1.7, required = false, rule = "corner" },
        { type = "bookshelf",    w = 1.0, d = 0.35, h = 2.0, required = false, rule = "against_wall" },
        { type = "potted_plant", w = 0.5, d = 0.5, h = 1.2, required = false, rule = "corner" },
    },
    dining = {
        { type = "dining_table", w = 1.8, d = 0.9, h = 0.75, required = true,  rule = "center" },
        { type = "chair",        w = 0.45, d = 0.45, h = 0.9, required = true,  rule = "around_table", count = 4 },
        { type = "sideboard",    w = 1.5, d = 0.45, h = 0.9, required = false, rule = "against_wall" },
    },
    kitchen = {
        { type = "counter",      w = 3.0, d = 0.6, h = 0.9, required = true,  rule = "l_shape_walls" },
        { type = "refrigerator", w = 0.7, d = 0.7, h = 1.8, required = true,  rule = "corner" },
        { type = "stove",        w = 0.6, d = 0.6, h = 0.9, required = true,  rule = "on_counter" },
    },
    master_bed = {
        { type = "double_bed",   w = 2.0, d = 2.2, h = 0.5, required = true,  rule = "headboard_against_wall" },
        { type = "nightstand",   w = 0.5, d = 0.4, h = 0.55, required = true,  rule = "beside_bed", count = 2 },
        { type = "wardrobe",     w = 2.0, d = 0.6, h = 2.2, required = true,  rule = "against_wall_not_door" },
        { type = "dresser",      w = 1.2, d = 0.45, h = 0.8, required = false, rule = "against_wall" },
    },
    bed_2 = {
        { type = "single_bed",   w = 1.0, d = 2.0, h = 0.5, required = true,  rule = "headboard_against_wall" },
        { type = "desk",         w = 1.2, d = 0.6, h = 0.75, required = true,  rule = "against_wall_near_window" },
        { type = "desk_chair",   w = 0.5, d = 0.5, h = 0.9, required = true,  rule = "at_desk" },
        { type = "wardrobe",     w = 1.2, d = 0.6, h = 2.2, required = true,  rule = "against_wall" },
    },
    bed_3 = {
        { type = "single_bed",   w = 1.0, d = 2.0, h = 0.5, required = true,  rule = "headboard_against_wall" },
        { type = "desk",         w = 1.2, d = 0.6, h = 0.75, required = true,  rule = "against_wall_near_window" },
        { type = "desk_chair",   w = 0.5, d = 0.5, h = 0.9, required = true,  rule = "at_desk" },
        { type = "wardrobe",     w = 1.2, d = 0.6, h = 2.2, required = true,  rule = "against_wall" },
    },
    master_bath = {
        { type = "toilet",       w = 0.4, d = 0.7, h = 0.8, required = true,  rule = "against_wall" },
        { type = "sink",         w = 0.6, d = 0.5, h = 0.85, required = true,  rule = "against_wall" },
        { type = "shower",       w = 1.0, d = 1.0, h = 2.2, required = true,  rule = "corner" },
    },
    bath_2 = {
        { type = "toilet",       w = 0.4, d = 0.7, h = 0.8, required = true,  rule = "against_wall" },
        { type = "sink",         w = 0.6, d = 0.5, h = 0.85, required = true,  rule = "against_wall" },
    },
    corridor = {
        { type = "shoe_cabinet", w = 1.0, d = 0.35, h = 1.0, required = false, rule = "against_wall" },
    },
}

M.window_rules = {
    living      = { width = 2.0, height = 1.5, sill = 0.9 },
    dining      = { width = 1.5, height = 1.5, sill = 0.9 },
    kitchen     = { width = 1.2, height = 1.2, sill = 0.9 },
    master_bed  = { width = 1.5, height = 1.5, sill = 0.9 },
    bed_2       = { width = 1.5, height = 1.5, sill = 0.9 },
    bed_3       = { width = 1.5, height = 1.5, sill = 0.9 },
    master_bath = { width = 0.8, height = 0.8, sill = 1.5 },
    bath_2      = { width = 0.8, height = 0.8, sill = 1.5 },
}

return M
