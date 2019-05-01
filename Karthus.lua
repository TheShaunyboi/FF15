local Karthus = {}
local version = 1
--[[if tonumber(GetInternalWebResult("Karthus.version")) > version then
    DownloadInternalFile("Karthus.lua", SCRIPT_PATH .. "Karthus.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("Karthus.version")) .. " Press F5")
end--]]
require "FF15Menu"
require "utils"
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
end

function Karthus:__init()
    self.q = {
        type = "circular",
        speed = math.huge,
        range = 875,
        delay = 1.05,
        radius = 195
        --[[   damage = function(unit)
            return dmgLib:CalculateMagicDamage(
                myHero,
                unit,
                25 + myHero.spellbook:Spell(SpellSlot.Q).level * 20 +
                    0.3 * myHero.characterIntermediate.flatMagicDamageMod
            )
        end ]]
    }
    self.w = {
        type = "circular",
        speed = math.huge,
        range = 1000,
        delay = 0.50,
        radius = 165
    }
    self.e = {
        range = 500,
        active = false
        --[[    damage = function(unit)
            return dmgLib:CalculateMagicDamage(
                myHero,
                unit,
                10 + myHero.spellbook:Spell(SpellSlot.Q).level * 20 +
                    0.2 * myHero.characterIntermediate.flatMagicDamageMod
            )
        end ]]
    }
    self.inPassive = false
    self:Menu()
    self.TS =
        DreamTS(
        self.menu.dreamTs,
        {
            ValidTarget = function(unit)
                return _G.Prediction.IsValidTarget(unit)
            end,
            Damage = function(unit)
                return dmgLib:CalculateMagicDamage(myHero, unit, 100)
            end
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
    PrintChat("Karthus loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Karthus:Menu()
    self.menu = Menu("asdfkarthus", "Karthus")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:sub("karthusDraw", "Draw")
    self.menu.karthusDraw:checkbox("q", "Q", true)
    self.menu.karthusDraw:slider("qr", "Red", 1, 255, 150)
    self.menu.karthusDraw:slider("qg", "Green", 1, 255, 150)
    self.menu.karthusDraw:slider("qb", "Blue", 1, 255, 150)
end

function Karthus:OnDraw()
    if self.menu.karthusDraw.q:get() then
        DrawHandler:Circle3D(
            myHero.position,
            self.q.range,
            self:Hex(
                255,
                self.menu.karthusDraw.qr:get(),
                self.menu.karthusDraw.qg:get(),
                self.menu.karthusDraw.qb:get()
            )
        )
    end
    local text = "" 
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
end

function Karthus:CastQ(target)
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local pred = _G.Prediction.GetPrediction(target, self.q, myHero)
        if
            pred and pred.castPosition and GetDistanceSqr(pred.castPosition) <= self.q.range * self.q.range and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target))
         then
            myHero.spellbook:CastSpell(0, pred.castPosition)
            return true
        end
    end
end
function Karthus:CastW(target)
    if myHero.spellbook:CanUseSpell(1) == 0 then
        local pred = _G.Prediction.GetPrediction(target, self.w, myHero)
        if
            pred and pred.castPosition and GetDistanceSqr(pred.castPosition) <= self.w.range * self.w.range and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target))
         then
            myHero.spellbook:CastSpell(1, pred.castPosition)
            return true
        end
    end
end

function Karthus:ToggleE()
    if myHero.spellbook:CanUseSpell(2) == 0 then
        if self:GetTarget(self.e.range) then
            if myHero.spellbook:Spell(2).toggleState == 1 then
                myHero.spellbook:CastSpell(2, pwHud.hudManager.virtualCursorPos)
            end
        else
            if myHero.spellbook:Spell(2).toggleState == 2 then
                myHero.spellbook:CastSpell(2, pwHud.hudManager.virtualCursorPos)
            end
        end
    end
end

function Karthus:Lasthit()
end

function Karthus:OnTick()
    local target = self:GetTarget(self.q.range)
    if LegitOrbwalker:GetMode() == "Combo" then
        self:ToggleE()
    end
    if target then
        if false and self:CastQ(target) --[[or self:CastW(target)--]] then
            return
        elseif LegitOrbwalker:GetMode() == "Combo" and (self:CastQ(target) or self:CastW(target)) then
            return
        elseif LegitOrbwalker:GetMode() == "Harass" and self:CastQ(target) then
            return
        elseif LegitOrbwalker:GetMode() == "Lasthit" then
            self:Lasthit()
        end
    end
end

function Karthus:OnBuffGain(obj, buff)
    if obj and obj == myHero then
        if buff.name == "karthusdead" then
            self.inPassive = true
        end
    end
end

function Karthus:OnBuffLost(obj, buff)
    if obj and obj == myHero then
        if buff.name == "karthusdead" then
            self.inPassive = false
        end
    end
end

function Karthus:Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

function Karthus:GetTarget(dist, all)
    self.TS.ValidTarget = function(unit)
        return _G.Prediction.IsValidTarget(unit, dist)
    end
    local res = self.TS:update()
    if all then
        return res
    else
        if res and res[1] then
            return res[1]
        end
    end
end

if myHero.charName == "Karthus" then
    Karthus:__init()
end
