require("FF15Menu")
require("utils")
local Vector = require("GeometryLib").Vector
local LineSegment = require("GeometryLib").LineSegment

local LinearSpell = {}
LinearSpell.__index = LinearSpell
LinearSpell.__call = function(self, ...)
    return self:new(...)
end

setmetatable(LinearSpell, LinearSpell)

function LinearSpell:new(startPos, endPos, width, delay, speed)
    local res = {
        type = "LinearSpell",
        startPos = startPos,
        endPos = endPos,
        width = width,
        delay = delay,
        speed = speed,
        startTime = os.clock()
    }
    return setmetatable(res, Vector)
end

function LinearSpell:draw()
end

local CircularSpell = {}
CircularSpell.__index = CircularSpell
CircularSpell.__call = function(self, ...)
    return self:new(...)
end
setmetatable(CircularSpell, CircularSpell)

function CircularSpell:new(pos, radius, delay)
    local res = {
        type = "CircularSpell",
        pos = pos,
        radius = radius,
        delay = delay,
        startTime = os.clock()
    }
    return setmetatable(res, Vector)
end

function CircularSpell:draw()
end

local Evade = {}

function OnLoad()
    Evade:__init()
end

function Evade:__init()
    self.activeSpells = {}
    self.spellTester = {}
    self:Menu()
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
end

function Evade:Menu()
    self.menu = Menu("EmpyreanEvade", "Empyrean Evade")
    self.menu:sub("spellTester", "Spell Tester")
    self.menu.spellTester:slider("interval", "Interval", 0.05, 5, 0.1, 0.05)
    self.menu.spellTester:slider("width1", "Width limit 1", 5, 500, 50, 5)
    self.menu.spellTester:slider("width2", "Width limit 2", 5, 500, 400, 5)
    self.menu.spellTester:slider("radius1", "Radius limit 1", 5, 500, 50, 5)
    self.menu.spellTester:slider("radius1", "Radius limit 2", 5, 500, 400, 5)
    self.menu.spellTester:slider("range", "Maximum range", 100, 2000, 500, 100)
end

function Evade:OnDraw()
end

function Evade:OnTick()
end
