local Karthus = {}
local version = 1
--[[if tonumber(GetInternalWebResult("asdfkarthus.version")) > version then
    DownloadInternalFile("asdfkarthus.lua", SCRIPT_PATH .. "asdfkarthus.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("asdfkarthus.version")) .. " Press F5")
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
        delay = 1.02,
        radius = 195,
        damage = function(unit)
            return dmgLib:CalculateMagicDamage(
                myHero,
                unit,
                25 + myHero.spellbook:Spell(SpellSlot.Q).level * 20 +
                    0.3 * myHero.characterIntermediate.flatMagicDamageMod
            )
        end
    }
    self.w = {
        type = "circular",
        speed = math.huge,
        range = 1000,
        delay = 0.4,
        radius = 80
    }
    self.e = {
        range = 500,
        active = false,
        damage = function(unit)
            local mult = 1
            local pred = _G.Prediction.GetPrediction(unit, self.q, myHero)
            if
                pred and pred.castPosition and GetDistanceSqr(pred.castPosition) <= self.q.range * self.q.range and
                    not pred:minionCollision() and
                    not pred:heroCollision()
             then
                mult = 2
            end
            return dmgLib:CalculateMagicDamage(
                myHero,
                unit,
                10 + myHero.spellbook:Spell(SpellSlot.E).level * 20 +
                    0.2 * myHero.characterIntermediate.flatMagicDamageMod
            ) * mult
        end
    }
    self.passiveLast = 0
    self.AAs = {}
    self.Qlast = {}
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
        Events.OnCreateObject,
        function(object, nId)
            self:OnCreateObject(object, nId)
        end
    )
    AddEvent(
        Events.OnDeleteObject,
        function(object)
            self:OnDeleteObject(object)
        end
    )
    PrintChat("Karthus loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Karthus:Menu()
    self.menu = Menu("asdfkarthus", "Karthus")
    self.menu:checkbox("aQ", "Always use Q to lasthit", true)
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
    if os.clock() <= self.passiveLast + 7 then
        text = text .. "Time to ult: " .. 4 - os.clock() + self.passiveLast .. "\n"
    end
    if myHero.spellbook:CanUseSpell(3) == 0 then
        for _, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
            text = text .. enemy.charName .. ": " .. enemy.health - self:GetRDamage(enemy) .. "\n"
        end
    end
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

function Karthus:GetRDamage()
    return dmgLib:CalculateMagicDamage(
        myHero,
        unit,
        100 + myHero.spellbook:Spell(SpellSlot.R).level * 150 + 0.75 * myHero.characterIntermediate.flatMagicDamageMod
    )
end

function Karthus:Lasthit()
    for _, minion in pairs(ObjectManager:GetEnemyMinions()) do
        if
            _G.Prediction.IsValidTarget(minion) and GetDistanceSqr(minion) <= self.q.range * self.q.range and
                (self.menu.aQ:get() or GetDistanceSqr(minion) >= self.e.range * self.e.range) and
                LegitOrbwalker:HpPred(minion, self.q.delay) > 0 and
                minion.health - self.q.damage(minion) < 0 and
                not self.AAs[minion] and
                not self.Qlast[minion] and
                self:CastQ(minion)
         then
            self.Qlast[minion] = os.clock() + self.q.delay + NetClient.ping / 1000
            return
        elseif
            _G.Prediction.IsValidTarget(minion) and GetDistanceSqr(minion) <= self.e.range * self.e.range and
                minion.health > 0 and
                minion.health - self.e.damage(minion) < 0 and
                not self.AAs[minion] and
                not self.Qlast[minion]
         then
            if myHero.spellbook:CanUseSpell(2) == 0 and myHero.spellbook:Spell(2).toggleState == 1 then
                myHero.spellbook:CastSpell(2, pwHud.hudManager.virtualCursorPos)
                return
            end
        end
    end
    if myHero.spellbook:CanUseSpell(2) == 0 and myHero.spellbook:Spell(2).toggleState == 2 then
        myHero.spellbook:CastSpell(2, pwHud.hudManager.virtualCursorPos)
    end
end

function Karthus:OnTick()
    for minion in pairs(self.Qlast) do
        if self.Qlast[minion] >= os.clock() then
            self.Qlast[minion] = nil
        end
    end
    local target = self:GetTarget(self.q.range)
    if LegitOrbwalker:GetMode() == "Combo" then
        self:ToggleE()
        if
            myHero.spellbook:CanUseSpell(0) == 0 and target and
                self.q.damage(target) >= 1.5 * dmgLib:GetAutoAttackDamage(myHero, target)
         then
            LegitOrbwalker:BlockAttack(true)
        else
            LegitOrbwalker:BlockAttack(false)
        end
    else
        LegitOrbwalker:BlockAttack(false)
    end
    if target then
        if os.clock() <= self.passiveLast + 7 and (self:CastW(target) or self:CastQ(target)) then
            return
        elseif
            LegitOrbwalker:GetMode() == "Combo" and not LegitOrbwalker:IsAttacking() and
                (self:CastW(target) or self:CastQ(target))
         then
            return
        elseif LegitOrbwalker:GetMode() == "Harass" and not LegitOrbwalker:IsAttacking() and self:CastQ(target) then
            return
        end
    end
    if LegitOrbwalker:GetMode() == "Lasthit" then
        self:Lasthit()
    end
end

function Karthus:OnBuffGain(obj, buff)
    if obj and obj == myHero then
        if buff.name == "KarthusDeathDefiedBuff" then
            self.passiveLast = os.clock()
        end
    end
end

function Karthus:OnCreateObject(object, nId)
    if object and object.name:find("KarthusBasicAttack") and object.asMissile.spellCaster.networkId == myHero.networkId then
        self.AAs[object.asMissile.target] = nil
    end
end

function Karthus:OnDeleteObject(object)
    for target in pairs(self.AAs) do
        if self.AAs[target] == object then
            self.AAs[target] = nil
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
