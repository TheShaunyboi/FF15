require "FF15Menu"
require "utils"
local Vector = require("GeometryLib").Vector
local Circle = require("GeometryLib").Circle
local LineSegment = require("GeometryLib").LineSegment
local Polygon = require("GeometryLib").Polygon

local function Round(x)
    local remainder = x % 1
    if (remainder > 0.5) then
        return math.ceil(x)
    else
        return math.floor(x)
    end
end

local function DrawPolygon(vertices, color)
    for i = 1, #vertices do
        local startPos = Renderer:WorldToScreen(vertices[i]:toDX3())
        local next = i == #vertices and 1 or i + 1
        local endPos = Renderer:WorldToScreen(vertices[next]:toDX3())
        DrawHandler:Line(startPos, endPos, color)
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
    local cursorPos = pwHud.hudManager.virtualCursorPos
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
    end
    DrawPolygon(self:Vertices(), color)
    DrawPolygon(self:Vertices(true, myHero.boundingRadius), color)
end

local Graph = class()

function Graph:new(obj, interval, range)
    self.obj = obj
    self:SetInterval(interval)
    self:SetRange(range)
    self.nodes = {}
end

function Graph:Fill()
    self.nodes = {}
    local center = Vector(self.obj.position)
    for i = -self.iterations, self.iterations do
        if not self.nodes[i] then
            self.nodes[i] = {}
            for j = -self.iterations, self.iterations do
                self.nodes[i][j] = center + Vector(i, 0, j) * self.interval
            end
        end
    end
end

function Graph:SetInterval(interval)
    self.interval = interval
end

function Graph:SetRange(range)
    self.iterations = math.floor(range / self.interval)
end

function Graph:GetRange()
    return self.iterations * self.interval
end

function Graph:Nearest(pos)
    local diff = pos - Vector(self.obj.position)
    local maxRange = (self.iterations + 0.5) * self.interval
    if math.abs(diff.x) < maxRange and math.abs(diff.z) < maxRange then
        return Round(diff.x / self.interval), Round(diff.z / self.interval)
    end
end

function Graph:GetEdges(i, j)
    local iMin = i == -self.iterations and i or i - 1
    local jMin = j == -self.iterations and j or j - 1
    local iMax = i == self.iterations and i or i + 1
    local jMax = j == self.iterations and j or j + 1
    local res = {}
    for x = iMin, iMax do
        if not res[x] then
            res[x] = {}
        end
        for y = jMin, jMax do
            if x ~= i or y ~= j then
                res[x][y] = 1
            end
        end
    end
    return res
end

function Graph:Place(pos)
    local i, j = self:Nearest(pos)
    if i and j then
        self.nodes[i][j] = pos
        return true
    else
        return false
    end
end

function Graph:Draw()
    self:Place(Vector(pwHud.hudManager.virtualCursorPos))
    local a, b = self:Nearest(Vector(pwHud.hudManager.virtualCursorPos))
    local edges = {}
    if a and b then
        edges = self:GetEdges(a, b)
    end
    for i in pairs(self.nodes) do
        if self.nodes[i] then
            for j in pairs(self.nodes[i]) do
                if self.nodes[i][j] then
                    local color = Color.White
                    if i == a and j == b then
                        color = Color.Red
                    elseif edges[i] and edges[i][j] then
                        color = Color.Yellow
                    end
                    DrawHandler:Circle3D(self.nodes[i][j]:toDX3(), 10, color)
                end
            end
        end
    end
end

local Evade = {}

function Evade:__init()
    self.activeSpells = {}
    self.graph = Graph(myHero, 50, 20) -- decide that later
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
    self.menu:sub("graph", "Graph")
    self.menu.graph:slider("interval", "Interval", 25, 200, 50, 25):onChange(
        function(menu)
            self.graph:SetInterval(menu.value)
            self.graph:SetRange(menu.root.graph.range:get())
            self.graph:Fill()
        end
    )
    self.menu.graph:slider("range", "Range", 100, 2000, 1000, 100):onChange(
        function(menu)
            self.graph:SetRange(menu.value)
            self.graph:Fill()
        end
    )
    self.graph = Graph(myHero, self.menu.graph.interval:get(), self.menu.graph.range:get())
    self.menu:sub("draw", "Draw")
    self.menu.draw:checkbox("skillshots", "Draw skillshots", true)
    self.menu.draw:checkbox("graph", "Draw graph", true)
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
    self.graph:Fill()
    if self.menu.sandbox.enabled:get() then
        self:CreateSandboxSpells()
    end

    for i = #self.activeSpells, 1, -1 do
        if self.activeSpells[i]:IsExpired() then
            table.remove(self.activeSpells, i)
        end
    end
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
    if self.menu.draw.graph:get() then
        self.graph:Draw()
    end
end

function Evade:OnIssueOrder(order, pos)
end

function OnLoad()
    Evade:__init()
end
