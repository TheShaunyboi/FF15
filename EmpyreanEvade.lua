--make the ms a function of time: offset, velocity, acceleration
--use time as input for heap

require "FF15Menu"
require "utils"
local Vector = require("GeometryLib").Vector
local Circle = require("GeometryLib").Circle
local LineSegment = require("GeometryLib").LineSegment
local Polygon = require("GeometryLib").Polygon

local sqrt2 = math.sqrt(2)

local function Round(x)
    local remainder = x % 1
    if (remainder > 0.5) then
        return math.ceil(x)
    else
        return math.floor(x)
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
    local idx2 = math.floor(idx / 2)
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

local NaiveHeap = class()

function NaiveHeap:new()
    self.dict = {}
end

function NaiveHeap:Insert(key, value)
    self.dict[value] = key
end

function NaiveHeap:Remove(key, value)
    local minKey = nil
    local minValue = nil
    for v, k in pairs(self.dict) do
        if not minKey or minKey > k then
            minKey = k
            minValue = v
        end
    end
    self.dict[minValue] = nil
    return minKey, minValue
end

function NaiveHeap:IsEmpty()
    for _, i in pairs(self.dict) do
        if i then
            return false
        end
    end
    return true
end

local LinearSpell = class()

function LinearSpell:new(startPos, endPos, delay, width, speed)
    self.createTime = RiotClock.time
    self.startPos = startPos
    self.endPos = endPos
    self.delay = delay - NetClient.ping / 2000 -- might be wrong
    self.width = width
    self.speed = speed
    self.range = startPos:dist(endPos)
end

function LinearSpell:IsCreated()
    return RiotClock.time >= self.createTime + self.delay
end

function LinearSpell:IsExpired()
    return self.speed == 0 and self:IsCreated() or
        (RiotClock.time - self.createTime - self.delay) * self.speed > self.range
end

function LinearSpell:CurrentPos()
    if not self:IsCreated() then
        return self.startPos
    end
    local diff = (self.endPos - self.startPos):normalized()
    return self.startPos + (RiotClock.time - self.createTime - self.delay) * self.speed * diff
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
function LinearSpell:Vertices(full, dist)
    dist = dist or 0
    local res = {}
    local currentPos = full and self.startPos or self:CurrentPos()
    local diffVer = (self.startPos - self.endPos):normalized()
    local diffHor = diffVer:rotated(0, math.pi / 2, 0):normalized()
    res[1] = currentPos + self.width / 2 * diffHor + diffVer * dist + diffHor * dist
    res[2] = currentPos - self.width / 2 * diffHor + diffVer * dist - diffHor * dist
    res[3] = self.endPos - self.width / 2 * diffHor - diffVer * dist - diffHor * dist
    res[4] = self.endPos + self.width / 2 * diffHor - diffVer * dist + diffHor * dist
    return res
end

function LinearSpell:Edges(full, dist)
    local vertices = self:Vertices(full, dist)
    local res = {}
    for i = 1, #vertices - 1 do
        res[i] = LineSegment(vertices[i], vertices[i + 1])
    end
    res[4] = LineSegment(vertices[4], vertices[1])
    return res
end

function LinearSpell:Contains(pos, full)
    local poly = Polygon(unpack(self:Vertices(full)))
    return poly:contains(pos)
end

function LinearSpell:ContainsObj(pos, r, full)
    if self:Contains(pos, full) then
        return true
    end
    local circle = Circle(pos, r)
    local edges = self:Edges(full)
    for i = 1, #edges do
        if circle:intersects(edges[i]) then
            return true
        end
    end
    return false
end

function LinearSpell:DistFromStart(pos)
    local dist = self.startPos:distanceTo(pos)
    local theta = self.startPos:angleBetween(self.endPos, pos)
    return math.abs(dist * math.cos(math.rad(theta)))
end

function LinearSpell:TimeTillCollision(pos, r)
    if self:ContainsObj(pos, r) then
        if self.speed == 0 then
            return -RiotClock.time + self.createTime + self.delay
        end
        local distFromStart = self:DistFromStart(pos)
        return (self:DistFromStart(pos) - r - (RiotClock.time - self.createTime - self.delay) * self.speed) / self.speed
    end
end

function LinearSpell:TimeTillExitCollision(pos, r)
    local before = self:TimeTillCollision(pos, r)
    if before then
        return self.speed == 0 and before or before + 2 * r / self.speed
    end
end

function LinearSpell:IsCollide(pos, r)
    local t = self:TimeTillCollision(pos, r)
    return t and t <= 0
end

function LinearSpell:PathIntersection(p1, p2, r)
    local res = {}
    local edgesExtended = self:Edges(true, r - 0.01)
    local edges = self:Edges(true)
    local vertices = self:Vertices(true)
    local seg = LineSegment(p1, p2)
    local distSqr = p1:distSqr(p2)
    for _, edgeExtended in pairs(edgesExtended) do
        local intersect, intersection = edgeExtended:intersects(seg)
        if intersect then
            local vec = Vector(intersection)
            local inside = false
            for _, edge in pairs(edges) do
                if edge:distanceTo(vec) < r then
                    inside = true
                end
            end
            if inside then
                table.insert(res, Vector(intersection))
            end
        end
    end
    for i, vertex in pairs(vertices) do
        local closest = seg:closest(vertex)
        local diffSqr = r * r - vertex:distSqr(closest)
        if diffSqr >= 0 then
            local diff = math.sqrt(diffSqr)
            local adjust1 = closest:extended(p2, diff - 0.1)
            local adjust2 = closest:extended(p2, -diff + 0.1)
            local temp1 = closest:extended(p2, diff + 0.1)
            local temp2 = closest:extended(p2, -diff - 0.1)
            if not self:ContainsObj(temp1, r, true) and self:ContainsObj(adjust1, r, true) then
                table.insert(res, adjust1)
            end
            if not self:ContainsObj(temp2, r, true) and self:ContainsObj(adjust2, r, true) then
                table.insert(res, adjust2)
            end
        end
    end
    if #res > 2 then
        local a = res[1]:distSqr(res[2])
        local b = res[2]:distSqr(res[3])
        local c = res[3]:distSqr(res[1])
        local min = math.min(a, b, c)
        if min == a then
            table.remove(res, 1)
        elseif min == b then
            table.remove(res, 2)
        else
            table.remove(res, 3)
        end
    end
    return res
end

function LinearSpell:IsPathDangerous(p1, p2, r, ms)
    local intersect = self:PathIntersection(p1, p2, r)
    local reactionTime = NetClient.ping / 2000 -- might change later
    local startPos = nil
    local endPos = nil
    if #intersect == 0 then
        local obj1 = self:ContainsObj(p1, r)
        local obj2 = self:ContainsObj(p2, r)
        if obj1 then
            return true
        else
            if not obj2 then
                return false
            else
                local t2 = self:TimeTillExitCollision(p2, r)
                return t2 and p1:dist(p2) / ms + reactionTime < t2
            end
        end
    elseif #intersect == 1 then
        if self:ContainsObj(p1, r, true) then
            startPos = p1
            endPos = intersect[1]
        else
            local t2 = self:TimeTillExitCollision(p2, r)
            if t2 and p1:dist(p2) / ms + reactionTime < t2 then
                return true
            end
            startPos = intersect[1]
            endPos = p2
        end
    else
        local dist1 = p1:distSqr(intersect[1])
        local dist2 = p1:distSqr(intersect[2])
        if dist1 < dist2 then
            startPos = intersect[1]
            endPos = intersect[2]
        else
            startPos = intersect[2]
            endPos = intersect[1]
        end
    end
    --+- r self.speed * (t - creationTime) = projectSpeed(t - reactionTime - currentTime) + startDist
    local startDist = self:DistFromStart(startPos)
    local projectSpeed = (p2 - p1):normalized():projectOn((self.endPos - self.startPos):normalized()):len() * ms
    projectSpeed = projectSpeed * ((self.startPos:distSqr(startPos) < self.startPos:distSqr(endPos)) and 1 or -1)
    local t1 = nil
    local t2 = nil
    if self.speed == 0 then
        t1 = self.createTime + self.delay - RiotClock.time
    elseif self.speed ~= projectSpeed then
        local sum =
            -projectSpeed * (reactionTime + RiotClock.time) + startDist + self.speed * (self.createTime + self.delay)
        t1 = (sum + r) / (self.speed - projectSpeed) - RiotClock.time
        t2 = (sum - r) / (self.speed - projectSpeed) - RiotClock.time
    end
    if t1 then
        local lowBound = p1:dist(startPos) / ms + reactionTime
        local highBound = p1:dist(endPos) / ms + reactionTime
        return (t1 > lowBound and t1 < highBound) or (t2 and t2 > lowBound and t2 < highBound)
    else
        local initialDanger = self:TimeTillCollision(startPos, r)
        return initialDanger and initialDanger < p1:dist(startPos) / ms + reactionTime
    end
end

function LinearSpell:Draw()
    local color =
        self:IsPathDangerous(
        Vector(myHero.position),
        Vector(pwHud.hudManager.virtualCursorPos),
        myHero.boundingRadius,
        myHero.characterIntermediate.movementSpeed
    ) and
        Color.Red or
        Color.White
   --[[  local cursorPos = pwHud.hudManager.virtualCursorPos
    local cursorPosAdjust = D3DXVECTOR3(cursorPos.x, myHero.position.y, cursorPos.z)
    DrawHandler:Line(Renderer:WorldToScreen(myHero.position), Renderer:WorldToScreen(cursorPosAdjust), color)
    local intersects =
        self:PathIntersection(Vector(myHero.position), Vector(pwHud.hudManager.virtualCursorPos), myHero.boundingRadius)
    for i, pos in pairs(intersects) do
        DrawHandler:Circle3D(pos:toDX3(), myHero.boundingRadius, Color.White)
        DrawHandler:Text(
            DrawHandler.defaultFont,
            Renderer:WorldToScreen(pos:toDX3()),
            self:TimeTillCollision(pos, myHero.boundingRadius),
            Color.White
        )
    end ]]
    DrawLines(self:Vertices(), color, true)
    DrawLines(self:Vertices(true, myHero.boundingRadius), color, true)
end

local Grid = class()

function Grid:new(obj, interval, range)
    self.obj = obj
    self:SetInterval(interval)
    self:SetRange(range)
    self.nodes = {}
end

function Grid:Fill()
    self.nodes = {}
    local center = Vector(self.obj.position)
    for i = -self.iterations, self.iterations do
        if not self.nodes[i] then
            self.nodes[i] = {}
            for j = -self.iterations, self.iterations do
                local pos = center + Vector(i, 0, j) * self.interval
                self.nodes[i][j] = {}
                table.insert(self.nodes[i][j], pos)
            end
        end
    end
end

function Grid:SetInterval(interval)
    self.interval = interval
end

function Grid:SetRange(range)
    self.iterations = math.floor(range / self.interval)
end

function Grid:GetRange()
    return self.iterations * self.interval
end

function Grid:Nearest(pos)
    local diff = pos - Vector(self.obj.position)
    local maxRange = (self.iterations + 0.5) * self.interval
    if math.abs(diff.x) < maxRange and math.abs(diff.z) < maxRange then
        return Round(diff.x / self.interval), Round(diff.z / self.interval)
    end
end

function Grid:GetEdges(pos, validFunc)
    local res = {}
    local i, j = self:Nearest(pos)
    if i and j then
        local startPos = self.nodes[i][j][1]
        local isPlaced = pos ~= startPos
        local iMin = i == -self.iterations and i or i - 1
        local jMin = j == -self.iterations and j or j - 1
        local iMax = i == self.iterations and i or i + 1
        local jMax = j == self.iterations and j or j + 1
        for x = iMin, iMax do
            for y = jMin, jMax do
                local diff = math.abs(x - i) + math.abs(y - j)
                for idx, pt in pairs(self.nodes[x][y]) do
                    if not validFunc or validFunc(pos, pt) then
                        if pt ~= pos then
                            if not isPlaced then
                                res[pt] = startPos:dist(pt)
                            else
                                if idx == 1 then
                                    if diff == 1 then
                                        res[pt] = self.interval
                                    elseif diff == 2 then
                                        res[pt] = self.interval * sqrt2
                                    else
                                        res[pt] = 0
                                    end
                                else
                                    res[pt] = startPos:dist(pt)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return res
end

function Grid:Place(pos)
    local i, j = self:Nearest(pos)
    if i and j then
        table.insert(self.nodes[i][j], pos)
        return true
    else
        return false
    end
end

function Grid:Draw()
    local vec = Vector(pwHud.hudManager.virtualCursorPos)
    local edges = self:GetEdges(vec)
    for i in pairs(self.nodes) do
        if self.nodes[i] then
            for j in pairs(self.nodes[i]) do
                if self.nodes[i][j] then
                    for _, pt in pairs(self.nodes[i][j]) do
                        local color = Color.White
                        if pt == vec then
                            color = Color.Red
                        elseif edges[pt] then
                            color = Color.Yellow
                        end
                        DrawHandler:Circle3D(pt:toDX3(), 10, color)
                    end
                end
            end
        end
    end
end

local function AStar(startPos, endPos, getEdges, ms)
    local cost = {}
    local visited = {}
    cost[startPos] = 0
    local paths = {}
    local pq = Heap()
    pq:Insert(0, startPos)
    while not pq:IsEmpty() do
        local cur, pos = pq:Remove()
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
        for neighbor, distance in pairs(getEdges(pos)) do
            local newCost = cur + distance
            if not visited[neighbor] and (not cost[neighbor] or newCost < cost[neighbor]) then
                cost[neighbor] = newCost
                local newPriority = newCost + endPos:dist(neighbor)
                paths[neighbor] = pos
                pq:Insert(newPriority, neighbor)
            end
        end
    end
end

local Evade = {}

function Evade:__init()
    self.activeSpells = {}
    self.sandboxTimer = RiotClock.time
    self:Menu()
    self:Event()
end

function Evade:Menu()
    self.menu = Menu("EmpyreanEvade", "EmpyreanEvade")
    self.menu:checkbox("enabled", "Enabled", true, string.byte("K"))
    self.menu:sub("sandbox", "Sandbox")
    self.menu.sandbox:checkbox("enabled", "Enabled", false)
    self.menu.sandbox:slider("frequency", "Frequency", 0.1, 5, 2, 0.1)
    self.menu.sandbox:slider("offset", "Random offset limit", 0, 300, 100, 25)
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
    self.menu.sandbox:slider("range", "Range", 100, 2000, 1000, 100)
    self.menu.sandbox:slider("radius", "Radius", 25, 500, 100, 25)
    self.menu.sandbox:slider("speed", "Speed", 0, 3000, 2000, 100)
    self.menu:sub("grid", "Grid")
    self.menu.grid:slider("interval", "Interval", 25, 200, 50, 25):onChange(
        function(menu)
            self.grid:SetInterval(menu.value)
            self.grid:SetRange(menu.root.grid.range:get())
            self.grid:Fill()
        end
    )
    self.menu.grid:slider("range", "Range", 100, 2000, 1000, 100):onChange(
        function(menu)
            self.grid:SetRange(menu.value)
            self.grid:Fill()
        end
    )
    self.grid = Grid(myHero, self.menu.grid.interval:get(), self.menu.grid.range:get())
    self.menu:sub("draw", "Draw")
    self.menu.draw:checkbox("skillshots", "Draw skillshots", true)
    self.menu.draw:checkbox("grid", "Draw grid", true)
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
            math.random() * self.menu.sandbox.offset:get() * Vector(1, 0, 0):rotated(0, math.random() * 2 * math.pi, 0)
        local startPos = nil
        local endPos = nil
        local skillshotType = self.menu.sandbox.skillshotType:get()
        if skillshotType ~= 2 then --not circular
            local diff = self.menu.sandbox.range:get() / 2 * Vector(1, 0, 0):rotated(0, math.random() * 2 * math.pi, 0)
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
                self.menu.sandbox.speed:get()
            )
            table.insert(self.activeSpells, spell)
        end
    end
end

function Evade:OnTick()
    if self.menu.sandbox.enabled:get() then
        self:CreateSandboxSpells()
    end

    for i = #self.activeSpells, 1, -1 do
        if self.activeSpells[i]:IsExpired() then
            table.remove(self.activeSpells, i)
        end
    end
    self.grid:Fill()
end

function Evade:OnDraw()
    local coll = false
    if (self.menu.draw.skillshots:get()) then
        for i, spell in ipairs(self.activeSpells) do
            spell:Draw()
            if spell:IsCollide(Vector(myHero.position), myHero.boundingRadius) then
                coll = true
            end
        end
    end
    if self.menu.draw.boundingRadius:get() then
        DrawHandler:Circle3D(myHero.position, myHero.boundingRadius, coll and Color.Red or Color.White)
    end
    local cursorPos = Vector(pwHud.hudManager.virtualCursorPos)
    local heroPos = Vector(myHero.position)
    if self.grid:Place(cursorPos) then
        local paths =
            AStar(
            Vector(myHero.position),
            cursorPos,
            function(pos)
                return self.grid:GetEdges(
                    pos--[[ ,
                    function(startPos, endPos)
                        for _, spell in ipairs(self.activeSpells) do
                            if spell:IsPathDangerous(startPos, endPos, myHero.boundingRadius, myHero.characterIntermediate.movementSpeed) then
                                return false
                            end
                        end
                        return true
                    end ]]
                )
            end,
            myHero.characterIntermediate.movementSpeed
        ) --check up
        if paths then
            DrawLines(paths, Color.White)
        end
    end
    if self.menu.draw.grid:get() then
        self.grid:Draw()
    end
end

function Evade:OnIssueOrder(order, pos)
end

function OnLoad()
    Evade:__init()
end
