-- need to rewrite get cursor pos
-- write radial search
-- check if path is safe

require "FF15Menu"
require "utils"

local Vector = require("GeometryLib").Vector
local Circle = require("GeometryLib").Circle
local LineSegment = require("GeometryLib").LineSegment
local Polygon = require("GeometryLib").Polygon

local ceil, floor, abs, pi, random, sin, cos, tan, sqrt, rad, deg, min, max =
    math.ceil,
    math.floor,
    math.abs,
    math.pi,
    math.random,
    math.sin,
    math.cos,
    math.tan,
    math.sqrt,
    math.rad,
    math.deg,
    math.min,
    math.max

local boundingRadius = myHero.boundingRadius
local sqrt2 = sqrt(2)

--to remove
local checkingPath = nil

local function Round(x)
    local remainder = x % 1
    if (remainder > 0.5) then
        return ceil(x)
    else
        return floor(x)
    end
end

local function DrawLines(vertices, color, complete)
    for i = 1, #vertices do
        if i == #vertices then
            if complete then
                DrawHandler:Line(
                    Renderer:WorldToScreen(vertices[i]:toDX3()),
                    Renderer:WorldToScreen(vertices[1]:toDX3()),
                    color
                )
            end
        else
            DrawHandler:Line(
                Renderer:WorldToScreen(vertices[i]:toDX3()),
                Renderer:WorldToScreen(vertices[i + 1]:toDX3()),
                color
            )
        end
    end
end

local function class()
    return setmetatable(
        {},
        {
            __call = function(self, ...)
                local result = setmetatable({}, {__index = self})
                result:new(...)

                return result
            end
        }
    )
end

local HeapNode = class()

function HeapNode:new(key, value)
    self.key = key
    self.value = value
end

function HeapNode.compare(a, b)
    return a.key < b.key
end

local Heap = class()

function Heap:new()
    self.items = {}
    self.dict = {}
end

function Heap:Insert(key, value)
    if not self.dict[value] then
        local node = HeapNode(key, value)
        table.insert(self.items, node)
        self.dict[value] = #self.items
        self:BubbleUp(#self.items)
    else
        local idx = self.dict[value]
        self.items[idx].key = key
        if self:BubbleUp(idx) then
        else
            if self:BubbleDown(idx) then
            end
        end
    end
end

function Heap:BubbleUp(idx)
    local idx2 = floor(idx / 2)
    if idx ~= 1 and self.items[idx2] and HeapNode.compare(self.items[idx], self.items[idx2]) then
        self.dict[self.items[idx].value] = idx2
        self.dict[self.items[idx2].value] = idx
        local temp = self.items[idx2]
        self.items[idx2] = self.items[idx]
        self.items[idx] = temp
        self:BubbleUp(idx2)

        return true
    end
end

function Heap:Remove()
    local res = self.items[1]
    self.dict[res.value] = nil
    if #self.items == 1 then
        table.remove(self.items, 1)
    else
        self.items[1] = self.items[#self.items]
        self.dict[self.items[1].value] = 1
        self.items[#self.items] = nil
        self:BubbleDown(1)
    end
    return res.key, res.value
end

function Heap:BubbleDown(idx)
    local nextIdx = 2 * idx
    if self.items[nextIdx] then
        nextIdx =
            (self.items[nextIdx + 1] and HeapNode.compare(self.items[nextIdx + 1], self.items[nextIdx])) and nextIdx + 1 or
            nextIdx
        if HeapNode.compare(self.items[nextIdx], self.items[idx]) then
            self.dict[self.items[idx].value] = nextIdx
            self.dict[self.items[nextIdx].value] = idx
            local temp = self.items[nextIdx]
            self.items[nextIdx] = self.items[idx]
            self.items[idx] = temp
            self:BubbleDown(nextIdx)
            return true
        end
    end
end

function Heap:IsEmpty()
    return #self.items == 0
end

local Movement = class()

--[[movement[0] = {
    x2 = 1,
    x = 23,
    b = 1
}, can't go back in distance]]
function Movement:new(movement)
    self.movementByTime = movement
    self.sortedMovement = {}
    for t in ipairs(movement) do
        table.insert(self.sortedMovement, t)
    end
    table.sort(self.sortedMovement)
    self.timeToDist = {}
    local cur = 0
    local curMotion = {x2 = 0, x = 0, b = 0}
    local lastTime = 0
    for i = 1, #self.sortedMovement do
        local startTime = self.sortedMovement[i]
        local motion = self.movementByTime[startTime]
        local diffTime = startTime - lastTime
        cur = cur + motion.b + curMotion.x * diffTime + curMotion.x2 * diffTime * diffTime
        self.timeToDist[startTime] = cur
        lastTime = startTime
    end
end

function Movement:Dist(t)
    if t >= 0 then
        for i = 1, #self.sortedMovement do
            local startTime = self.sortedMovement[i]
            if t >= startTime then
                local diffTime = t - startTime
                local motion = self.movementByTime[startTime]
                return self.timeToDist[startTime] + diffTime * motion.x + diffTime * diffTime * motion.x2
            end
        end
    end
end

function Movement:Velocity(t)
    if t >= 0 then
        for i = 1, #self.sortedMovement do
            local startTime = self.sortedMovement[i]
            if t >= startTime then
                local diffTime = t - startTime
                local motion = self.movementByTime[startTime]
                return motion.x + 2 * diffTime * motion.x2
            end
        end
    end
end

function Movement:Acceleration(t)
    if t >= 0 then
        for i = 1, #self.sortedMovement do
            local startTime = self.sortedMovement[i]
            if t >= startTime then
                local motion = self.movementByTime[startTime]
                return 2 * motion.x2
            end
        end
    end
end

function Movement:Intersect(other)
    --to do
end

local LinearSpell = class()

function LinearSpell:new(startPos, endPos, delay, width, speed, boundingRadiusMod) -- collision, forceDodge, expireFunc)
    self.createTime = RiotClock.time
    self.startPos = startPos
    self.endPos = endPos
    self.delay = delay - NetClient.ping / 2000 -- might be wrongwht
    self.width = width
    self.speed = speed
    self.range = startPos:dist(endPos)
    self.boundingRadiusMod = boundingRadiusMod

    self:Update()
end

function LinearSpell:Update()
    self.isCreated = self:IsCreated()
    self.isExpired = self:IsExpired()
    self.extendedStartPos = self.endPos + (self.startPos - self.endPos):normalized() * (self.range + boundingRadius)
    self.extendedEndPos = self.startPos + (self.endPos - self.startPos):normalized() * (self.range + boundingRadius)
    self.seg = LineSegment(self.extendedStartPos, self.extendedEndPos)
    self.vertices = self:Vertices(true, false)
    self.extendedVertices = self:Vertices(true, self.boundingRadiusMod)
    self.edges = self:Edges(true, false)
    self.extendedEdges = self:Edges(true, self.boundingRadiusMod)
    self.polygon = self:Polygon(true, false)
    self.extendedPolygon = self:Polygon(true, self.boundingRadiusMod)
    self.curPos = self:Position()
    self.curVertices = self:Vertices(false, false)
    self.curExtendedVertices = self:Vertices(false, self.boundingRadiusMod)
    self.curEdges = self:Edges(false, false)
    self.curExtendedEdges = self:Edges(false, self.boundingRadiusMod)
    self.curPolygon = self:Polygon(false, false)
    self.curExtendedPolygon = self:Polygon(false, self.boundingRadiusMod)
end

function LinearSpell:IsCreated(t)
    local t = t or 0
    return RiotClock.time + t >= self.createTime + self.delay
end

function LinearSpell:IsExpired(t)
    local t = t or 0
    return self.speed == 0 and self:IsCreated() or
        (RiotClock.time + t - self.createTime - self.delay) * self.speed > self.range
end

function LinearSpell:Displacement(t)
    if self.speed == 0 then
        return self:IsCreated(t) and self.range or 0
    end
    return min(max((RiotClock.time + t - self.createTime - self.delay) * self.speed, 0), self.range)
end

function LinearSpell:Position(t)
    local t = t or 0
    if not self:IsCreated(t) then
        return self.startPos
    end
    if self:IsExpired(t) then
        return self.endPos
    end
    local diff = (self.endPos - self.startPos):normalized()
    return self.startPos + self:Displacement(t) * diff
end

--[[
        currentpos
    1   ____   2

        |  |
        |  |
        |  |
    4   ____   3
        endpos


]]
function LinearSpell:Vertices(full, boundingRadiusMod)
    dist = boundingRadiusMod and boundingRadius or 0
    local res = {}
    local currentPos = full and self.startPos or self.curPos
    local diffVer = (self.startPos - self.endPos):normalized()
    local diffHor = diffVer:rotated(0, pi / 2, 0):normalized()
    res[1] = currentPos + self.width / 2 * diffHor + diffVer * dist + diffHor * dist
    res[2] = currentPos - self.width / 2 * diffHor + diffVer * dist - diffHor * dist
    res[3] = self.endPos - self.width / 2 * diffHor - diffVer * dist - diffHor * dist
    res[4] = self.endPos + self.width / 2 * diffHor - diffVer * dist + diffHor * dist
    return res
end

function LinearSpell:Edges(full, boundingRadiusMod)
    local vertices = self:Vertices(full, boundingRadiusMod)
    local res = {}
    for i = 1, #vertices - 1 do
        res[i] = LineSegment(vertices[i], vertices[i + 1])
    end
    res[4] = LineSegment(vertices[4], vertices[1])
    return res
end

function LinearSpell:Polygon(full, boundingRadiusMod)
    return Polygon(unpack(self:Vertices(full, boundingRadiusMod)))
end

function LinearSpell:Contains(pos, full)
    if full then
        return self.extendedPolygon:contains(pos)
    else
        return self.curExtendedPolygon:contains(pos)
    end
end

function LinearSpell:DistFromStart(pos)
    local dist = self.startPos:distanceTo(pos)
    local theta = self.startPos:angleBetween(self.endPos, pos)
    return dist * cos(rad(theta))
end

function LinearSpell:IsCollide(pos, t)
    t = t or 0
    if not self:IsCreated(t) then
        return false
    end
    if self:IsExpired(t) then
        return false
    end
    if self.speed == 0 then
        return self:Contains(pos)
    end
    local dist = self:DistFromStart(pos)
    local curDist = self:Displacement(t)
    return self.seg:distanceTo(pos) <= self.width / 2 + boundingRadius and dist <= curDist + boundingRadius and
        dist >= curDist - boundingRadius
end

function LinearSpell:IsPathDangerous(p1, p2, ms, t0, buffer)
    -- what if before createTime
    if self:IsExpired(t0) then
        return false
    end
    local dist = p1:dist(p2)
    local res = false
    if self:IsCollide(p1, t0) or self:IsCollide(p2, t0 + dist / ms) then
        res = true
    end
    buffer = buffer or 0
    local projSpeed = (p2 - p1):normalized():projectOn((self.endPos - self.startPos):normalized()):len() * ms

    local start = (RiotClock.time + t0 - self.createTime - self.delay) * self.speed
    local proj1 = self:DistFromStart(p1)
    local proj2 = self:DistFromStart(p2)
    projSpeed = proj1 >= proj2 and -1 * projSpeed or projSpeed
    local path = (p2 - p1):normalized() * ms
    -- start + t * self.speed = proj1 + projSpeed * t + r

    if self.speed == 0 then
        --to do
    elseif self.speed ~= projectSpeed then
        local t = (proj1 - start) / (self.speed - projSpeed)
        local t1 = t + (boundingRadius + buffer) / (self.speed - projSpeed)
        local t2 = t - (boundingRadius + buffer) / (self.speed - projSpeed)
        if t1 > dist / ms and t2 > dist / ms then
            return false
        end
        local pos1 = p1 + path * t1
        local pos2 = p1 + path * t2
        local pos3 = p1 + path * t
        local dist1 = self:DistFromStart(pos1)
        local dist2 = self:DistFromStart(pos2)
        if
            self.seg:distanceTo(pos1) <= self.width / 2 + boundingRadius + buffer and
                dist1 >= self:Displacement(t1 + t0) and
                dist1 <= self.range
         then
            res = true
        end
        if
            self.seg:distanceTo(pos2) <= self.width / 2 + boundingRadius + buffer and
                dist2 >= self:Displacement(t2 + t0) and
                dist2 <= self.range
         then
            res = true
        end
        return res, pos1, pos2, pos3
    else
        --paralell
        --do later
    end
end

function LinearSpell:Draw()
    -- if checkingPath then
    --     local p1 = checkingPath[#checkingPath]
    --     local p2 = checkingPath[#checkingPath - 1]
    --     local res, pos1, pos2, pos3 =
    --         self:IsPathDangerous(
    --         p1,
    --         p2,
    --         myHero.characterIntermediate.movementSpeed,
    --         NetClient.ping / 2000 + 0.03
    --     )
    --     local color = res and Color.Red or Color.White
    --     if pos1 and pos2 and pos3 then
    --         DrawHandler:Circle3D(pos1:toDX3(), 10, Color.Green)
    --         DrawHandler:Circle3D(pos2:toDX3(), 10, Color.Green)
    --         DrawHandler:Circle3D(pos3:toDX3(), 10, Color.Pink)
    --     end
    -- end
    local cursorPos = pwHud.hudManager.virtualCursorPos
    local cursorPosAdjust = D3DXVECTOR3(cursorPos.x, myHero.position.y, cursorPos.z)
    DrawHandler:Line(Renderer:WorldToScreen(myHero.position), Renderer:WorldToScreen(cursorPosAdjust), color)
    local color = Color.White

    DrawLines(self.curExtendedVertices, color, true)
    DrawLines(self.curVertices, color, true)
end

local Grid = class()

function Grid:new(interval, range)
    self:SetInterval(interval)
    self:SetRange(range)
    self.range = self:GetRange()
    self.nodes = {}
    self.edges = {}
end

function Grid:Reset(startPos)
    self.nodes = {}
    self.edges = {}
    if startPos then
        self.nodes[0] = {}
        self.nodes[0][0] = {}
        table.insert(self.nodes[0][0], startPos)
    end
end

function Grid:AddEdge(p1, p2) --need to be added before
    if p1 == p2 then 
        return 
    end
    if not self.edges[p1] then
        self.edges[p1] = {}
    end
    self.edges[p1][p2] = true
end

function Grid:GetNode(i, j)
    if not (self.nodes[0] and self.nodes[0][0] and self.nodes[0][0][1]) then
        return
    end
    return self.nodes[0][0][1] + Vector(i, 0, j) * self.interval
end

function Grid:SetInterval(interval)
    self.interval = interval
end

function Grid:SetRange(range)
    self.iterations = floor(range / self.interval)
end

function Grid:GetRange()
    return self.iterations * self.interval
end

function Grid:Nearest(pos)
    if not (self.nodes[0] and self.nodes[0][0] and self.nodes[0][0][1]) then
        return
    end
    local diff = pos - self.nodes[0][0][1]
    local maxRange = (self.iterations + 0.5) * self.interval
    if abs(diff.x) < maxRange and abs(diff.z) < maxRange then
        return Round(diff.x / self.interval), Round(diff.z / self.interval)
    else
        if abs(diff.x) > abs(diff.z) then
            local x = abs(diff.x) / diff.x * self.iterations
            local z = Round(abs(diff.z) / diff.z * abs(diff.z) / abs(diff.x) * self.iterations)
            return x, z
        else
            local z = abs(diff.z) / diff.z * self.iterations
            local x = Round(abs(diff.x) / diff.x * abs(diff.x) / abs(diff.z) * self.iterations)
            return x, z
        end
    end
end

function Grid:GetEdges(pos, t, validFunc)
    local res = {}
    local i, j = self:Nearest(pos)
    if i and j then
        local iMin = i == -self.iterations and i or i - 1
        local jMin = j == -self.iterations and j or j - 1
        local iMax = i == self.iterations and i or i + 1
        local jMax = j == self.iterations and j or j + 1
        for x = iMin, iMax do
            for y = jMin, jMax do
                if not self.nodes[x] then
                    self.nodes[x] = {}
                end
                local temp = nil
                if not self.nodes[x][y] then
                    self.nodes[x][y] = {}
                    temp = self:GetNode(x, y)
                end
                local diff = abs(x - i) + abs(y - j)
                function insert(pt, isPlaced)
                    if not validFunc or validFunc(pos, pt, t) then
                        if pt ~= pos then
                            res[pt] = pos:dist(pt)
                        end
                        return true
                    end
                end
                if temp and insert(temp, false) then
                    table.insert(self.nodes[x][y], temp)
                else
                    for idx = 1, #self.nodes[x][y] do
                        insert(self.nodes[x][y][idx], idx == 1)
                    end
                end
            end
        end
    end
    if self.edges[pos] then
        for pt in pairs(self.edges[pos]) do
            if self.edges[pos][pt] and (not validFunc or validFunc(pos, pt, t)) then
                res[pt] = startPos:dist(pt)
            end
        end
    end
    return res
end

function Grid:Place(pos)
    local i, j = self:Nearest(pos)
    if i and j then
        if not self.nodes[i] then
            self.nodes[i] = {}
        end
        if not self.nodes[i][j] then
            self.nodes[i][j] = {}
        end
        local getNode = self:GetNode(i, j)
        if getNode:distSqr(pos) > 1 then
            table.insert(self.nodes[i][j], getNode)
        end
        table.insert(self.nodes[i][j], pos)
        return true
    else
        return false
    end
end

function Grid:Draw()
    for i = -self.iterations, self.iterations do
        if self.nodes[i] then
            for j = -self.iterations, self.iterations do
                if self.nodes[i][j] then
                    for idx = 1, #self.nodes[i][j] do
                        local pt = self.nodes[i][j][idx]
                        local color = Color.White
                        DrawHandler:Circle3D(pt:toDX3(), self.interval / 2, color)
                    end
                end
            end
        end
    end
end

local function AStar(startPos, endPos, getEdges, ms, delay)
    local cost = {}
    local visited = {}
    cost[startPos] = delay
    local paths = {}
    local pq = Heap()
    pq:Insert(startPos:dist(endPos) / ms, startPos)
    while not pq:IsEmpty() do
        local _, pos = pq:Remove()
        local cur = cost[pos]
        visited[pos] = true
        if pos == endPos then
            local res = {}
            local backtrack = endPos
            table.insert(res, endPos)
            while backtrack ~= startPos do
                table.insert(res, paths[backtrack])
                backtrack = paths[backtrack]
            end
            return res, cost[endPos]
        end
        for neighbor, distance in pairs(getEdges(pos, cur, visited)) do
            local newCost = cur + distance / ms
            if not visited[neighbor] and (not cost[neighbor] or newCost < cost[neighbor]) then
                cost[neighbor] = newCost
                local newPriority = newCost + endPos:dist(neighbor) / ms
                paths[neighbor] = pos
                pq:Insert(newPriority, neighbor)
            end
        end
    end
end

local Evade = {}

function Evade:__init()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
    self.activeSpells = {}
    self.sandboxTimer = RiotClock.time
    self.paths = nil
    self.shouldEvade = false
    self.movePos = nil
    self.onPathTimer = 0
    self.lastTick = nil
    self:Menu()
    self:Event()
end

function Evade:Menu()
    self.menu = Menu("EmpyreanEvade", "EmpyreanEvade")
    self.menu:checkbox("enabled", "Enabled", true, string.byte("K"))
    self.menu:sub("sandbox", "Sandbox")
    self.menu.sandbox:checkbox("enabled", "Enabled", false)
    self.menu.sandbox:slider("frequency", "Frequency", 0.1, 10, 2, 0.1)
    self.menu.sandbox:slider("offset", "Random offset limit", 0, 1000, 100, 25)
    self.menu.sandbox:list("skillshotType", "Type", 1, {"Linear", "Circular", "Conic"}):onChange(
        function(menu)
            menu.root.sandbox.width:hide(menu.value ~= 1)
            menu.root.sandbox.range:hide(menu.value == 2)
            menu.root.sandbox.radius:hide(menu.value ~= 2)
            menu.root.sandbox.angle:hide(menu.value ~= 3)
            menu.root.sandbox.speed:hide(menu.value == 2)
        end
    )
    self.menu.sandbox:slider("delay", "Delay", 0, 10, 0.25, 0.05)
    self.menu.sandbox:slider("angle", "Angle", 0, 180, 90, 15)
    self.menu.sandbox:slider("width", "Width", 25, 500, 100, 25)
    self.menu.sandbox:slider("range", "Range", 100, 4000, 1000, 100)
    self.menu.sandbox:slider("radius", "Radius", 25, 500, 100, 25)
    self.menu.sandbox:slider("speed", "Speed", 0, 3000, 2000, 100)
    self.menu:sub("movement", "Movement")
    self.menu.movement:slider("buffer", "Buffer", 0, 30, 15, 5)
    self.menu.movement:slider("tickRate", "Tick Rate", 1, 5, 2, 1)
    self.menu:sub("grid", "Grid")
    self.menu.grid:slider("interval", "Interval", 25, 200, 50, 25):onChange(
        function(menu)
            self.grid:SetInterval(menu.value)
            self.grid:SetRange(menu.root.grid.range:get())
            self.grid:Reset()
        end
    )
    self.menu.grid:slider("range", "Range", 500, 2000, 1500, 100):onChange(
        function(menu)
            self.grid:SetRange(menu.value)
            self.grid:Reset()
        end
    )
    self.grid = Grid(self.menu.grid.interval:get(), self.menu.grid.range:get())
    self.menu:sub("draw", "Draw")
    self.menu.draw:checkbox("skillshots", "Draw skillshots", true)
    self.menu.draw:checkbox("grid", "Draw grid", true)
    self.menu.draw:checkbox("path", "Draw path", true)
    self.menu.draw:checkbox("boundingRadius", "Draw bounding radius", true)
end

function Evade:Event()
    AddEvent(
        Events.OnTick,
        function()
            self:OnTick()
        end
    )
    AddEvent(
        Events.OnDraw,
        function()
            self:OnDraw()
        end
    )
    AddEvent(
        Events.OnIssueOrder,
        function(...)
            self:OnIssueOrder(...)
        end
    )
end

function Evade:CreateSandboxSpells()
    if RiotClock.time > self.sandboxTimer then
        self.sandboxTimer = RiotClock.time + 1 / self.menu.sandbox.frequency:get()

        local intercept =
            Vector(myHero.position) +
            random() * self.menu.sandbox.offset:get() * Vector(1, 0, 0):rotated(0, random() * 2 * pi, 0)
        local startPos = nil
        local endPos = nil
        local skillshotType = self.menu.sandbox.skillshotType:get()
        if skillshotType ~= 2 then --not circular
            local diff = self.menu.sandbox.range:get() / 2 * Vector(1, 0, 0):rotated(0, random() * 2 * pi, 0)
            startPos = intercept + diff
            endPos = intercept - diff
        end
        if skillshotType == 1 then
            local spell =
                LinearSpell(
                startPos,
                endPos,
                self.menu.sandbox.delay:get(),
                self.menu.sandbox.width:get(),
                self.menu.sandbox.speed:get(),
                true
            )
            --temp
            table.insert(self.activeSpells, spell)
            return true
        end
    end
end

function Evade:TestDelay()
    local paths = myHero.aiManagerClient.navPath.paths
    if #paths > 1 and GetDistanceSqr(paths[2], self.clickPos) < 10 then
        print(RiotClock.time - self.lastClick)
        print("Path x: " .. paths[2].x .. "y: " .. paths[2].y .. "z: " .. paths[2].z)
        print("Click x : " .. self.clickPos.x .. "y: " .. self.clickPos.y .. "z: " .. self.clickPos.z)
        print()
        self.clickPos = pwHud.hudManager.virtualCursorPos
        self.lastClick = RiotClock.time
        myHero:IssueOrderFast(GameObjectOrder.MoveTo, self.clickPos)
    end
    if not self.clickPos then
        self.clickPos = pwHud.hudManager.virtualCursorPos
        self.lastClick = RiotClock.time
        myHero:IssueOrderFast(GameObjectOrder.MoveTo, self.clickPos)
    end
    if self.lastClick and RiotClock.time > self.lastClick + 0.6 then
        self.clickPos = pwHud.hudManager.virtualCursorPos
        self.lastClick = RiotClock.time
        myHero:IssueOrderFast(GameObjectOrder.MoveTo, self.clickPos)
    end
end

function Evade:OnTick()
    --self:TestDelay()
    boundingRadius = myHero.boundingRadius
    local newSpell = false
    if self.menu.sandbox.enabled:get() then
        if self:CreateSandboxSpells() then
            newSpell = true
        end
    end
    for i = #self.activeSpells, 1, -1 do
        self.activeSpells[i]:Update()
        if self.activeSpells[i].isExpired then
            table.remove(self.activeSpells, i)
        end
    end
    self.shouldEvade = self:ShouldEvade()
    if not self.shouldEvade then
        self:CleanUp()
    else
        local onPath = self:CheckPath()
        if onPath ~= 1 or newSpell then --or RiotClock.time > self.lastTick + 1 / self.menu.movement.tickRate:get() then
            self:InvokeEvade()
        end
    end
end

function Evade:CleanUp()
    self.paths = nil
    self.movePos = nil
    self.grid:Reset()
end

function Evade:CheckPath()
    if not self.movePos then
        return 0
    end
    if RiotClock.time < self.onPathTimer + 0.0333 + NetClient.ping / 1000 then
        return 1
    end
    local paths = myHero.aiManagerClient.navPath.paths
    if #paths < 2 then
        return -1
    end
    if
        self.movePos:distSqr(Vector(paths[2])) < 10 or
            (self.movePosExtended and self.movePosExtended:distSqr(Vector(paths[2])) < 10)
     then
        local predPos = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.0333)
        if Vector(predPos):distSqr(self.movePos) < 50 then
            PrintChat(RiotClock.time + NetClient.ping / 2000 + 0.0333 - self.movePosTime)
            return 3
        else
            -- print(Vector(predPos):distSqr(paths[2]))
            return 2
        end
    else
        -- PrintChat("not on path: " .. RiotClock.time - self.onPathTimer)
        return -1
    end
end

function Evade:IsDangerous(pos)
    for i = #self.activeSpells, 1, -1 do
        if self.activeSpells[i]:Contains(pos, false) then
            return true
        end
    end
    return false
end

function Evade:ShouldEvade()
    if not self.menu.enabled:get() then
        return false
    end
    local predPos = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.0333)
    return self:IsDangerous(Vector(predPos))
end

function Evade:InvokeEvade()
    local predPos = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.0333)
    self.paths = nil
    checkingPath = nil
    local function FindPath(buffer)
        self.grid:Reset(Vector(predPos))
        local cursorPos = self:GetCursorPosition()
        local function RadialSearch(theta, disp)

        end
        if cursorPos and self.grid:Place(cursorPos) then
            return AStar(
                self.grid.nodes[0][0][1],
                cursorPos,
                function(pos, t, visited)
                    return self.grid:GetEdges(
                        pos,
                        t,
                        function(startPos, endPos, t)
                            if visited[endPos] then
                                return false
                            end
                            if NavMesh:IsWall(endPos:toDX3()) then
                                return false
                            end
                            for _, spell in ipairs(self.activeSpells) do
                                if
                                    spell:IsPathDangerous(
                                        startPos,
                                        endPos,
                                        myHero.characterIntermediate.movementSpeed,
                                        t,
                                        buffer
                                    )
                                 then
                                    return false
                                end
                            end
                            return true
                        end
                    )
                end,
                myHero.characterIntermediate.movementSpeed,
                0.03 + NetClient.ping / 2000
            )

        --check up
        end
    end
    self.paths = FindPath(self.menu.movement.buffer:get())
    -- if not self.paths then
    --     print(RiotClock.time)
    --     self.paths = FindPath(0)
    --     if self.paths then
    --         PrintChat('fallback')
    --     end
    -- end
    if self.paths then
        checkingPath = self.paths
        self.movePos = self:GetMovePosition(self.paths)
        if self.movePos then
            self.movePosTime =
                Vector(predPos):dist(self.movePos) / myHero.characterIntermediate.movementSpeed + RiotClock.time + 0.03 +
                NetClient.ping / 2000
            if GetDistanceSqr(self.movePos:toDX3()) < 125 ^ 2 then
                self.movePosExtended = Vector(predPos):extended(self.movePos, 125)
                myHero:IssueOrder(GameObjectOrder.MoveTo, self.movePosExtended:toDX3())
            else
                myHero:IssueOrder(GameObjectOrder.MoveTo, self.movePos:toDX3())
            end
            self.onPathTimer = RiotClock.time
            --change later
            self.lastTick = RiotClock.time
        end
    end
end

function Evade:GetCursorPosition()
    local heroPos = Vector(myHero.position)
    local cursorPos = Vector(pwHud.hudManager.virtualCursorPos)
    local cursorPosExtended = heroPos:extended(cursorPos, self.grid.range)
    local i, j = self.grid:Nearest(cursorPosExtended)
    local startPos = self.grid:GetNode(i, j)
    local endPos = self.grid:GetNode(-i, -j)
    local dist = startPos:dist(endPos)
    local diff = (endPos - startPos):normalized()
    local lowestDistSqr = 100000 ^ 2
    local lowestPos = nil
    local signs = {-1, 1}
    for _, sign in pairs(signs) do
        local delta = 200
        while delta < dist / 2 do
            local pos = heroPos + sign * delta * diff
            if NavMesh:IsWall(pos:toDX3()) then
                break
            end
            local distSqr = cursorPos:distSqr(pos)
            if distSqr < lowestDistSqr then
                lowestDistSqr = distSqr
                lowestPos = pos
            end
            delta = delta + self.grid.interval
        end
        if lowestPos then
            return lowestPos
        end
    end
end

function Evade:GetMovePosition(paths)
    if not paths then
        return
    end
    if #paths <= 2 then
        return #paths[1]
    end
    for i = #paths - 1, 1, -1 do
        local angle = paths[#paths]:angleBetween(paths[#paths - 1], paths[i])
        if angle > 0 then
            return paths[i + 1]
        end
    end
end

function Evade:OnDraw()
    local coll = false
    if (self.menu.draw.skillshots:get()) then
        for i = #self.activeSpells, 1, -1 do
            local spell = self.activeSpells[i]
            spell:Draw()
            if spell:IsCollide(Vector(myHero.position)) then
                coll = true
            end
        end
    end
    if coll then
        PrintChat("hit: " .. RiotClock.time)
    end
    if self.menu.draw.boundingRadius:get() then
        DrawHandler:Circle3D(myHero.position, boundingRadius, coll and Color.Red or Color.White)
    end
    if self.menu.draw.grid:get() then
        self.grid:Draw()
    end
    if self.paths and self.menu.draw.path:get() then
        DrawLines(self.paths, Color.Red)
    end

    local paths = myHero.aiManagerClient.navPath.paths
    if #paths > 1 then
        DrawHandler:Circle3D(paths[2], 30, Color.Yellow)
    end
    if self.movePos then
        DrawHandler:Circle3D(self.movePos:toDX3(), 50, Color.Pink)
    end
    local predPos = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.03)
    DrawHandler:Circle3D(predPos, 30, Color.Blue)
end

function Evade:OnIssueOrder(order, pos)
end

function OnLoad()
    Evade:__init()
end
