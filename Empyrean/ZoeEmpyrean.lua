local function class()
    return setmetatable(
        {},
        {
            __call = function(self, ...)
                local result = setmetatable({}, {__index = self})
                result:__init(...)

                return result
            end
        }
    )
end

local Zoe = class()
Zoe.version = 1

require "FF15Menu"
require "utils"
local DreamTS = require("DreamTS")
local Vector = require("GeometryLib").Vector
local LineSegment = require("GeometryLib").LineSegment
local dmgLib = require("FF15DamageLib")
local Orbwalker = require "ModernUOL"

function Zoe:__init()
    self.range = {
        q = 800,
        e = 800,
        eWall = 650
    }
    self.q = {
        type = "linear",
        speed = 2000,
        range = 10000,
        delay = 0.25,
        width = 97.5,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.q2 = {
        type = "linear",
        speed = 2000,
        range = 10000,
        delay = 0,
        width = 135,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.e = {
        type = "linear",
        speed = 1850,
        range = 10000,
        delay = 0.3,
        width = 100,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.wBuffTarget = nil
    self:Menu()
    self.TS =
        DreamTS(
        self.menu.dreamTs,
        {
            Damage = DreamTS.Damages.AD
        }
    )
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
        Events.OnBuffGain,
        function(obj, buff)
            self:OnBuffGain(obj, buff)
        end
    )
    AddEvent(
        Events.OnBuffLost,
        function(obj, buff)
            self:OnBuffLost(obj, buff)
        end
    )
    AddEvent(
        Events.OnProcessSpell,
        function(...)
            self:OnProcessSpell(...)
        end
    )
    AddEvent(
        Events.OnExecuteCastFrame,
        function(...)
            self:OnExecuteCastFrame(...)
        end
    )
    AddEvent(
        Events.OnDeleteObject,
        function(obj)
            self:OnDeleteObject(obj)
        end
    )
    PrintChat("Zoe loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Zoe:Menu()
    self.menu = Menu("Zoe", "Zoe - Empyrean v" .. self.version)
    self.menu:sub("dreamTs", "Target Selector")
end

function Zoe:OnDraw()
    local mousePos = pwHud.hudManager.virtualCursorPos
    if GetDistanceSqr(mousePos) >= self.range.q ^ 2 then
        DrawHandler:Circle3D(mousePos, 500, Color.White)
    end
    DrawHandler:Circle3D(myHero.position, self.range.q, Color.White)
    -- local heroPos = Renderer:WorldToScreen(myHero.position)
    -- local endPos = Renderer:WorldToScreen(self:GetERange(mousePos))
    -- DrawHandler:Line(heroPos, endPos, Color.White)
end

function Zoe:GetERange(pos)
    -- local interval, cur = 25, 0
    -- local check = myHero.position
    -- while cur <= self.range.e do
    --     check = Vector(myHero.position):extended(Vector(pos), cur):toDX3()
    --     if NavMesh:IsWall(check) then
    --         while NavMesh:IsWall(check) do
    --             cur = cur + interval
    --             check = Vector(myHero.position):extended(Vector(pos), cur):toDX3()
    --         end
    --         return Vector(myHero.position):extended(Vector(pos), cur + self.range.eWall):toDX3()
    --     end
    --     cur = cur + interval
    -- end
    -- return check
    return self.range.e
end

function Zoe:ShouldCast()
    return true
end

function Zoe:CastE()
    local source = myHero.position
    targets, preds = self:GetTarget(self.e, source, true)
    for _, target in pairs(targets) do
        if
            preds[target.networkId] and preds[target.networkId].rates["veryslow"] and
                GetDistanceSqr(source, preds[target.networkId].castPosition) < self.range.e ^ 2 and
                GetDistanceSqr(source, target) < self.range.e ^ 2
         then
            myHero.spellbook:CastSpell(2, preds[target.networkId].castPosition)
            preds[target.networkId]:draw()
            return true
        end
    end
end

function Zoe:OnTick()
    local e = myHero.spellbook:CanUseSpell(2)
    if self:ShouldCast() and Orbwalker:GetMode() == "Combo" then
        if e and self:CastE() then
            return
        end
    end
end

function Zoe:OnBuffGain(obj, buff)
end

function Zoe:OnBuffLost(obj, buff)
end

function Zoe:GetTarget(spell, source, all, targetFilter, predFilter)
    local units, preds = self.TS:GetTargets(spell, source, targetFilter, predFilter)
    if all then
        return units, preds
    else
        local target = self.TS.target
        if target then
            return target, preds[target.networkId]
        end
    end
end

function Zoe:OnProcessSpell(obj, spell)
    if obj == myHero then
    end
end

function Zoe:OnExecuteCastFrame(obj, spell)
end

function Zoe:OnDeleteObject(obj)
end

return Zoe
