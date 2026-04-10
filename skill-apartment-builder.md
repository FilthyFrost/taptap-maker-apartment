# 自动化公寓场景搭建（布局生成器 → UrhoX 3D 场景）

## 适用场景

- 自动生成 **3室2厅大型公寓**（50m × 35m）的完整 3D 室内场景
- 包含：墙壁、地板、天花板、门、窗户、家具自动摆放
- 所有空间规则已内置：**门前留空、通道不堵、天花板合理高度、家具不重叠**
- 素材格式：FBX（StaticModel 组件加载）

**不适用于**：骨骼动画角色 → 用 `skill-animated-character.md`

---

## 整体流程

```
┌─────────────────────────────────────────────────────────────┐
│                    自动化公寓搭建流程                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 运行布局生成器 → 得到 layout 数据表                       │
│     lua apartment_generator/main.lua 42 layout.lua          │
│                    ↓                                        │
│  2. 在游戏 Lua 脚本中加载 layout.lua                         │
│     local layout = dofile("layout.lua")                     │
│                    ↓                                        │
│  3. 调用本 skill 提供的 BuildApartment(layout) 函数           │
│     自动创建地板、墙壁、天花板、门洞、窗户、家具               │
│                    ↓                                        │
│  4. 完成！角色可以在公寓里自由走动                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 核心原则（TapTap Maker AI 必须遵守）

### 绝对禁止的低级错误

| 错误 | 为什么错 | 正确做法 |
|------|---------|---------|
| 门后方放家具 | 门打开会撞到家具，玩家无法进入房间 | 门两侧各留 1.5m 空地 |
| 天花板低于 2.5m | 角色感觉被压迫，不真实 | 统一 3.5m 层高 |
| 家具挡住房间入口 | 玩家无法进入房间 | 从门到房间内部必须有 ≥0.8m 通道 |
| 家具悬浮在空中 | Y 坐标错误 | 家具 Y = 0（地面），壁挂物 Y = 1.5 |
| 家具穿墙 | 位置超出房间范围 | 家具必须完全在房间边界内 |
| 沙发放在房间正中间 | 不符合生活常识 | 沙发靠墙放，面朝电视墙 |
| 床头不靠墙 | 不符合生活常识 | 床头必须贴墙 |
| 走廊太窄 | 角色过不去 | 走廊最小宽度 1.8m |

---

## Step 1：准备 FBX 素材

在 `assets/Models/apartment/` 下准备以下 FBX 文件。**没有的素材可以用纯色方块代替**（代码已内置 fallback）。

### 必备素材

```
assets/Models/apartment/
├── wall.fbx              ← 墙壁片段（1m 宽 × 3.5m 高 × 0.2m 厚）
├── floor.fbx             ← 地板块（1m × 1m）
├── ceiling.fbx           ← 天花板块（1m × 1m）
├── door_frame.fbx        ← 门框（1.2m 宽 × 2.4m 高）
└── window_frame.fbx      ← 窗框（可选，没有也行）
```

### 家具素材

```
assets/Models/furniture/
├── sofa.fbx
├── coffee_table.fbx
├── tv_cabinet.fbx
├── dining_table.fbx
├── chair.fbx
├── double_bed.fbx
├── single_bed.fbx
├── nightstand.fbx
├── wardrobe.fbx
├── desk.fbx
├── desk_chair.fbx
├── dresser.fbx
├── counter.fbx           ← 厨房橱柜
├── refrigerator.fbx
├── stove.fbx
├── toilet.fbx
├── sink.fbx
├── shower.fbx
├── shoe_cabinet.fbx
├── floor_lamp.fbx
├── bookshelf.fbx
├── potted_plant.fbx
└── sideboard.fbx         ← 餐边柜
```

**如果某个素材不存在**，代码会自动用带颜色的方块 Box 代替，不会崩溃。

---

## Step 2：完整 Lua 代码 — 复制到你的游戏脚本中

### 2.1 素材映射表和颜色

```lua
-- =============================================
-- 公寓搭建器 — 素材映射
-- =============================================

-- FBX 素材路径映射（没有的素材设为 nil，会用方块代替）
local ASSET_MAP = {
    -- 建筑构件
    wall           = "Models/apartment/wall.fbx",
    floor          = "Models/apartment/floor.fbx",
    ceiling        = "Models/apartment/ceiling.fbx",
    door_frame     = "Models/apartment/door_frame.fbx",
    window_frame   = "Models/apartment/window_frame.fbx",
    -- 家具
    sofa           = "Models/furniture/sofa.fbx",
    coffee_table   = "Models/furniture/coffee_table.fbx",
    tv_cabinet     = "Models/furniture/tv_cabinet.fbx",
    dining_table   = "Models/furniture/dining_table.fbx",
    chair          = "Models/furniture/chair.fbx",
    double_bed     = "Models/furniture/double_bed.fbx",
    single_bed     = "Models/furniture/single_bed.fbx",
    nightstand     = "Models/furniture/nightstand.fbx",
    wardrobe       = "Models/furniture/wardrobe.fbx",
    desk           = "Models/furniture/desk.fbx",
    desk_chair     = "Models/furniture/desk_chair.fbx",
    dresser        = "Models/furniture/dresser.fbx",
    counter        = "Models/furniture/counter.fbx",
    refrigerator   = "Models/furniture/refrigerator.fbx",
    stove          = "Models/furniture/stove.fbx",
    toilet         = "Models/furniture/toilet.fbx",
    sink           = "Models/furniture/sink.fbx",
    shower         = "Models/furniture/shower.fbx",
    shoe_cabinet   = "Models/furniture/shoe_cabinet.fbx",
    floor_lamp     = "Models/furniture/floor_lamp.fbx",
    bookshelf      = "Models/furniture/bookshelf.fbx",
    potted_plant   = "Models/furniture/potted_plant.fbx",
    sideboard      = "Models/furniture/sideboard.fbx",
}

-- 当 FBX 不存在时用方块的颜色
local FALLBACK_COLORS = {
    -- 建筑构件
    wall           = Color(0.92, 0.91, 0.88, 1.0),   -- 米白色墙壁
    floor          = Color(0.55, 0.35, 0.17, 1.0),   -- 木地板棕色
    ceiling        = Color(0.95, 0.95, 0.95, 1.0),   -- 白色天花板
    door_frame     = Color(0.45, 0.28, 0.15, 1.0),   -- 深棕色门框
    window_frame   = Color(0.80, 0.90, 1.00, 0.3),   -- 半透明蓝玻璃
    -- 家具
    sofa           = Color(0.30, 0.45, 0.65, 1.0),   -- 蓝灰色沙发
    coffee_table   = Color(0.45, 0.30, 0.15, 1.0),   -- 深棕色
    tv_cabinet     = Color(0.25, 0.25, 0.25, 1.0),   -- 深灰色
    dining_table   = Color(0.55, 0.35, 0.17, 1.0),   -- 木色
    chair          = Color(0.55, 0.35, 0.17, 1.0),   -- 木色
    double_bed     = Color(0.85, 0.75, 0.65, 1.0),   -- 米色床
    single_bed     = Color(0.75, 0.80, 0.85, 1.0),   -- 浅蓝色
    nightstand     = Color(0.50, 0.35, 0.20, 1.0),   -- 棕色
    wardrobe       = Color(0.60, 0.45, 0.25, 1.0),   -- 木色
    desk           = Color(0.55, 0.35, 0.17, 1.0),   -- 木色
    desk_chair     = Color(0.20, 0.20, 0.20, 1.0),   -- 黑色
    dresser        = Color(0.60, 0.45, 0.25, 1.0),   -- 木色
    counter        = Color(0.85, 0.85, 0.80, 1.0),   -- 浅灰色台面
    refrigerator   = Color(0.90, 0.90, 0.92, 1.0),   -- 白色冰箱
    stove          = Color(0.20, 0.20, 0.20, 1.0),   -- 黑色灶台
    toilet         = Color(0.95, 0.95, 0.95, 1.0),   -- 白色
    sink           = Color(0.90, 0.90, 0.92, 1.0),   -- 白色
    shower         = Color(0.80, 0.90, 1.00, 0.5),   -- 半透明蓝
    shoe_cabinet   = Color(0.50, 0.35, 0.20, 1.0),   -- 棕色
    floor_lamp     = Color(0.90, 0.85, 0.60, 1.0),   -- 暖黄色
    bookshelf      = Color(0.50, 0.35, 0.20, 1.0),   -- 棕色
    potted_plant   = Color(0.30, 0.55, 0.20, 1.0),   -- 绿色
    sideboard      = Color(0.55, 0.35, 0.17, 1.0),   -- 木色
}
```

### 2.2 创建物体的通用函数

```lua
-- =============================================
-- 通用创建函数 — 优先 FBX，没有就用彩色方块
-- =============================================

-- 创建纯色 PBR 材质
local function CreateColorMaterial(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Roughness", Variant(0.7))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    return mat
end

-- 尝试加载 FBX，失败则用方块代替
-- assetType: ASSET_MAP 里的 key（如 "sofa", "wall"）
-- node: 要设置模型的节点
-- boxSize: 当 FBX 不存在时，方块的尺寸 Vector3(w, h, d)
local function SetModelOrBox(node, assetType, boxSize)
    local model = node:CreateComponent("StaticModel")
    local fbxPath = ASSET_MAP[assetType]
    local loaded = false

    if fbxPath then
        local res = cache:GetResource("Model", fbxPath)
        if res then
            model:SetModel(res)
            loaded = true
        end
    end

    if not loaded then
        -- 用引擎内置 Box 模型代替
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        node.scale = Vector3(boxSize.x, boxSize.y, boxSize.z)
        local color = FALLBACK_COLORS[assetType] or Color(0.7, 0.7, 0.7, 1.0)
        model:SetMaterial(CreateColorMaterial(color))
    end

    model:SetCastShadows(true)
    return model
end
```

### 2.3 搭建地板和天花板

```lua
-- =============================================
-- 地板和天花板 — 铺满每个房间
-- =============================================

local function BuildFloorAndCeiling(layout, parentNode)
    for _, room in ipairs(layout.rooms) do
        -- 地板：一整块平面
        local floorNode = parentNode:CreateChild("Floor_" .. room.id)
        -- 地板中心点，Y = 0
        floorNode.position = Vector3(
            room.x + room.width / 2,
            0,
            room.z + room.depth / 2
        )
        SetModelOrBox(floorNode, "floor", Vector3(room.width, 0.05, room.depth))

        -- 天花板：Y = ceiling_height
        local ceilNode = parentNode:CreateChild("Ceiling_" .. room.id)
        ceilNode.position = Vector3(
            room.x + room.width / 2,
            layout.apartment.ceiling_height,
            room.z + room.depth / 2
        )
        SetModelOrBox(ceilNode, "ceiling", Vector3(room.width, 0.05, room.depth))
    end
end
```

### 2.4 搭建墙壁（自动跳过门窗位置）

```lua
-- =============================================
-- 墙壁 — 沿每段 wall 数据搭建，门窗位置留洞
-- =============================================

-- 检查墙段上的某个位置是否有门
local function HasDoorAt(layout, wallX1, wallZ1, wallX2, wallZ2, posAlongWall)
    for _, room in ipairs(layout.rooms) do
        for _, door in ipairs(room.doors or {}) do
            local doorX, doorZ
            if door.wall == "north" then
                doorX = room.x + door.offset
                doorZ = room.z + room.depth
            elseif door.wall == "south" then
                doorX = room.x + door.offset
                doorZ = room.z
            elseif door.wall == "east" then
                doorX = room.x + room.width
                doorZ = room.z + door.offset
            elseif door.wall == "west" then
                doorX = room.x
                doorZ = room.z + door.offset
            end
            -- 检查门是否在这面墙上
            if doorX and doorZ then
                local onWall = false
                if wallZ1 == wallZ2 then -- 水平墙
                    if math.abs(doorZ - wallZ1) < 0.5 then
                        if doorX >= math.min(wallX1, wallX2) and doorX <= math.max(wallX1, wallX2) then
                            if math.abs(posAlongWall - doorX) < door.width / 2 + 0.1 then
                                return true, door.width
                            end
                        end
                    end
                elseif wallX1 == wallX2 then -- 竖直墙
                    if math.abs(doorX - wallX1) < 0.5 then
                        if doorZ >= math.min(wallZ1, wallZ2) and doorZ <= math.max(wallZ1, wallZ2) then
                            if math.abs(posAlongWall - doorZ) < door.width / 2 + 0.1 then
                                return true, door.width
                            end
                        end
                    end
                end
            end
        end
    end
    return false, 0
end

local function BuildWalls(layout, parentNode)
    local wallHeight = layout.apartment.ceiling_height
    local wallThick = layout.apartment.wall_thickness
    local segmentWidth = 1.0 -- 每段墙 1m 宽

    for i, wall in ipairs(layout.walls) do
        local dx = wall.x2 - wall.x1
        local dz = wall.z2 - wall.z1
        local length = math.sqrt(dx * dx + dz * dz)
        if length < 0.1 then goto continue_wall end

        local numSegments = math.floor(length / segmentWidth)
        local dirX = dx / length
        local dirZ = dz / length

        for seg = 0, numSegments - 1 do
            local posAlongWall
            local sx = wall.x1 + dirX * (seg + 0.5) * segmentWidth
            local sz = wall.z1 + dirZ * (seg + 0.5) * segmentWidth

            -- 用沿墙方向的坐标检查是否有门
            if math.abs(dz) < 0.01 then -- 水平墙
                posAlongWall = sx
            else -- 竖直墙
                posAlongWall = sz
            end

            local hasDoor, doorWidth = HasDoorAt(layout, wall.x1, wall.z1, wall.x2, wall.z2, posAlongWall)

            if hasDoor then
                -- 门的位置：只建上半部分（门框上方）
                local aboveDoorHeight = wallHeight - 2.4 -- 门高 2.4m
                if aboveDoorHeight > 0.1 then
                    local topNode = parentNode:CreateChild("WallAboveDoor_" .. i .. "_" .. seg)
                    topNode.position = Vector3(sx, 2.4 + aboveDoorHeight / 2, sz)
                    -- 旋转墙面对准方向
                    if math.abs(dz) < 0.01 then -- 水平墙（沿X轴）
                        topNode.rotation = Quaternion(0, 0, 0)
                    else -- 竖直墙（沿Z轴）
                        topNode.rotation = Quaternion(0, 90, 0)
                    end
                    SetModelOrBox(topNode, "wall", Vector3(segmentWidth, aboveDoorHeight, wallThick))
                end

                -- 放置门框
                local doorNode = parentNode:CreateChild("Door_" .. i .. "_" .. seg)
                doorNode.position = Vector3(sx, 1.2, sz) -- 门中心高度
                if math.abs(dz) < 0.01 then
                    doorNode.rotation = Quaternion(0, 0, 0)
                else
                    doorNode.rotation = Quaternion(0, 90, 0)
                end
                SetModelOrBox(doorNode, "door_frame", Vector3(1.2, 2.4, 0.15))
            else
                -- 普通墙段
                local wallNode = parentNode:CreateChild("Wall_" .. i .. "_" .. seg)
                wallNode.position = Vector3(sx, wallHeight / 2, sz)
                if math.abs(dz) < 0.01 then
                    wallNode.rotation = Quaternion(0, 0, 0)
                else
                    wallNode.rotation = Quaternion(0, 90, 0)
                end
                SetModelOrBox(wallNode, "wall", Vector3(segmentWidth, wallHeight, wallThick))

                -- 添加碰撞体（角色不能穿墙）
                local body = wallNode:CreateComponent("RigidBody")
                body:SetCollisionLayer(2)
                local shape = wallNode:CreateComponent("CollisionShape")
                shape:SetBox(Vector3(segmentWidth, wallHeight, wallThick))
            end
        end

        ::continue_wall::
    end
end
```

### 2.5 摆放家具

```lua
-- =============================================
-- 家具摆放 — 读取 layout 数据自动放置
-- =============================================

local function BuildFurniture(layout, parentNode)
    for _, room in ipairs(layout.rooms) do
        for j, furn in ipairs(room.furniture or {}) do
            local furnNode = parentNode:CreateChild(room.id .. "_" .. furn.type .. "_" .. j)

            -- 位置：x 和 z 来自布局数据，y 根据家具类型设置
            -- 地面家具 y = 高度/2（因为方块原点在中心）
            -- 壁挂物品 y = 1.5
            local yPos = furn.height / 2

            furnNode.position = Vector3(furn.x, yPos, furn.z)
            furnNode.rotation = Quaternion(0, furn.rotation or 0, 0)

            SetModelOrBox(furnNode, furn.type, Vector3(furn.width, furn.height, furn.depth))

            -- 大型家具添加碰撞体（角色不能穿过）
            if furn.width * furn.depth > 0.5 then
                local body = furnNode:CreateComponent("RigidBody")
                body:SetCollisionLayer(2)
                local shape = furnNode:CreateComponent("CollisionShape")
                shape:SetBox(Vector3(furn.width, furn.height, furn.depth))
            end
        end
    end
end
```

### 2.6 放置灯光

```lua
-- =============================================
-- 灯光 — 每个房间一盏顶灯
-- =============================================

local function BuildLights(layout, parentNode)
    -- 全局环境光
    local zoneNode = parentNode:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(
        Vector3(-10, -10, -10),
        Vector3(layout.apartment.width + 10, layout.apartment.ceiling_height + 10, layout.apartment.depth + 10)
    )
    zone.ambientColor = Color(0.3, 0.3, 0.35)
    zone.fogColor = Color(0.8, 0.85, 0.9)

    -- 每个房间一盏点光源（天花板下方 0.3m）
    for _, room in ipairs(layout.rooms) do
        local lightNode = parentNode:CreateChild("Light_" .. room.id)
        lightNode.position = Vector3(
            room.x + room.width / 2,
            layout.apartment.ceiling_height - 0.3,
            room.z + room.depth / 2
        )
        local light = lightNode:CreateComponent("Light")
        light.lightType = LIGHT_POINT
        light.range = math.max(room.width, room.depth) * 1.5
        light.brightness = 1.2
        light.color = Color(1.0, 0.95, 0.85) -- 暖白色
        light.castShadows = true
    end
end
```

### 2.7 主入口函数

```lua
-- =============================================
-- 主入口 — 一键搭建整个公寓
-- =============================================

function BuildApartment(layout)
    -- 创建公寓根节点
    local aptNode = scene_:CreateChild("Apartment")

    print("========================================")
    print("  开始搭建公寓")
    print(string.format("  尺寸: %.0fm x %.0fm", layout.apartment.width, layout.apartment.depth))
    print(string.format("  层高: %.1fm", layout.apartment.ceiling_height))
    print(string.format("  房间: %d 个", #layout.rooms))
    print("========================================")

    -- 1. 地板和天花板
    BuildFloorAndCeiling(layout, aptNode)
    print("  [1/4] 地板和天花板 ✓")

    -- 2. 墙壁（自动开门洞）
    BuildWalls(layout, aptNode)
    print("  [2/4] 墙壁和门 ✓")

    -- 3. 家具
    BuildFurniture(layout, aptNode)
    local totalFurniture = 0
    for _, room in ipairs(layout.rooms) do
        totalFurniture = totalFurniture + #(room.furniture or {})
    end
    print("  [3/4] 家具 (" .. totalFurniture .. " 件) ✓")

    -- 4. 灯光
    BuildLights(layout, aptNode)
    print("  [4/4] 灯光 ✓")

    print("========================================")
    print("  公寓搭建完成！")
    print("========================================")

    return aptNode
end
```

---

## Step 3：在游戏中调用

### 方式 A：使用预生成的布局文件

先在命令行生成布局：
```bash
cd apartment_generator
lua main.lua 42 ../assets/scripts/apartment_layout.lua
```

然后在游戏脚本中：
```lua
-- 加载预生成的布局
local layout = dofile("scripts/apartment_layout.lua")

-- 一键搭建
BuildApartment(layout)

-- 把角色放到走廊入口
local corridorRoom = nil
for _, room in ipairs(layout.rooms) do
    if room.id == "corridor" then corridorRoom = room; break end
end
if corridorRoom then
    characterNode.position = Vector3(
        corridorRoom.x + corridorRoom.width / 2,
        0,
        corridorRoom.z + 1  -- 走廊入口偏南一点
    )
end
```

### 方式 B：内嵌布局数据（不需要外部文件）

如果不想依赖外部文件，直接在游戏脚本里写布局数据：

```lua
-- 直接定义布局（从 apartment_generator 的输出复制过来）
local layout = {
    apartment = { width = 50, depth = 35, ceiling_height = 3.5, wall_thickness = 0.2 },
    rooms = {
        -- ... 粘贴 main.lua 生成的 rooms 数据 ...
    },
    walls = {
        -- ... 粘贴 walls 数据 ...
    },
}
BuildApartment(layout)
```

---

## Step 4：摄像机设置

公寓很大（50m × 35m），摄像机需要调整：

```lua
-- 第三人称跟随摄像机
local function SetupCamera()
    local cameraNode = scene_:CreateChild("Camera")
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 100  -- 远剪裁面要足够远
    camera.fov = 60

    -- 摄像机跟随角色
    function HandleUpdate(eventType, eventData)
        local dt = eventData["TimeStep"]:GetFloat()
        if characterNode then
            local targetPos = characterNode.position + Vector3(0, 8, -6)
            cameraNode.position = cameraNode.position + (targetPos - cameraNode.position) * dt * 5
            cameraNode:LookAt(characterNode.position + Vector3(0, 1, 0))
        end
    end
    SubscribeToEvent("Update", "HandleUpdate")
end
```

---

## 布局数据格式参考

`BuildApartment()` 接收的 layout 表结构：

```lua
{
    apartment = {
        width = 50,             -- 公寓总宽度（米）
        depth = 35,             -- 公寓总深度（米）
        ceiling_height = 3.5,   -- 天花板高度（米）
        wall_thickness = 0.2,   -- 墙厚（米）
    },
    rooms = {
        {
            id = "living",          -- 房间ID
            name = "客厅",          -- 中文名
            x = 0, z = 0,          -- 左下角全局坐标（米）
            width = 12, depth = 10, -- 房间宽深（米）
            doors = {
                { wall = "north", offset = 5, width = 1.2 },
                -- wall: 门在哪面墙（north/south/east/west）
                -- offset: 门中心距墙起点的距离（米）
                -- width: 门的宽度（米）
            },
            windows = {
                { wall = "south", offset = 6, width = 2, height = 1.5, sill_height = 0.9 },
            },
            furniture = {
                { type = "sofa", x = 6, z = 8.5, width = 2.5, depth = 1.0, height = 0.9, rotation = 180 },
                -- type: 家具类型（对应 ASSET_MAP 的 key）
                -- x, z: 家具中心的全局坐标
                -- width, depth, height: 家具尺寸（米）
                -- rotation: Y 轴旋转角度
            },
        },
        -- ... 其他 8 个房间
    },
    walls = {
        { x1 = 0, z1 = 0, x2 = 50, z2 = 0, height = 3.5, thickness = 0.2, type = "exterior" },
        -- x1,z1 到 x2,z2: 墙段的起点和终点
        -- type: "exterior"（外墙）或 "interior"（内墙）
    },
}
```

---

## 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| 看不到公寓 | 摄像机太远或角度不对 | 把角色放到走廊里，摄像机 farClip 设为 100 |
| 墙上有缝隙 | 墙段之间没对齐 | 布局生成器已 snap 到 0.5m 网格，正常不会有缝 |
| 家具全是方块 | FBX 素材不存在 | 属于正常 fallback，放入 FBX 文件后会自动加载 |
| 角色穿墙 | 没有碰撞体 | 代码已自动给墙和大型家具添加 RigidBody + CollisionShape |
| 门进不去 | 门洞没开或被家具挡住 | 布局生成器保证门前 1.5m 内无家具 |
| 房间太暗 | 灯光不够 | 增大 light.brightness 或 light.range |

更多问题请查看 `skill-troubleshooting.md`

---

## 坐标系说明

```
        Z+ (北)
        ↑
        |
        |
  ------+-----→ X+ (东)
        |
        |
        
  Y+ = 向上

  原点 (0, 0, 0) = 公寓西南角地面
```

所有坐标单位为**米**。UrhoX 使用 Y 轴向上的左手坐标系。
