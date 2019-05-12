local Xerath = {}
local version = 1
if tonumber(GetInternalWebResult("asdfxerath.version")) > version then
    DownloadInternalFile("asdfxerath.lua", SCRIPT_PATH .. "asdfxerath.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("asdfxerath.version")) .. " Press F5")
end
require "FF15Menu"
require "utils"
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
end

local Vector = require("GeometryLib").Vector

function Xerath:__init()
    self.q = {
        type = "linear",
        last = nil,
        min = 750,
        max = 1450,
        charge = 1.5,
        range = 1450,
        delay = 0.6,
        width = 145,
        speed = math.huge
    }
    self.w1 = {
        type = "circular",
        range = 1000,
        delay = 0.75,
        radius = 250,
        speed = math.huge
    }
    self.w2 = {
        type = "circular",
        range = 1000,
        delay = 0.75,
        radius = 123,
        speed = math.huge
    }
    self.e = {
        type = "linear",
        range = 1000,
        delay = 0.25,
        width = 125,
        speed = 1400
    }
    self.r = {
        type = "circular",
        active = false,
        range = 80000,
        delay = 0.6,
        radius = 200,
        speed = math.huge
    }

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
    --[[
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
    ]]
    AddEvent(
        Events.OnNewPath,
        function(obj, paths, isWalk, dashspeed)
            self:OnNewPath(obj, paths, isWalk, dashspeed)
        end
    )
    AddEvent(
        Events.OnDraw,
        function()
            self:OnDraw()
        end
    )
    PrintChat("Xerath loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Xerath:Menu()
    self.menu = Menu("asdfxerath", "Xerath")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:slider("wc", "W Center Hitchance", 1, 100, 50)
    self.menu:slider("e", "E Hitchance", 1, 100, 50)

    self.menu:slider("rr", "R Near Mouse Radius", 0, 3000, 1500)
    self.menu:sub("antigap", "Anti Gapclose")
    for _, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.antigap:checkbox(enemy.charName, enemy.charName, true)
    end
    self.menu:key("tap", "Tap Key", string.byte("T"))
    self.menu:sub("xerathDraw", "Draw")
    self.menu.xerathDraw:sub("q", "Q")
    self.menu.xerathDraw.q:checkbox("q", "Q", true)
    self.menu.xerathDraw.q:slider("qa", "Alpha", 1, 255, 150)
    self.menu.xerathDraw.q:slider("qr", "Red", 1, 255, 150)
    self.menu.xerathDraw.q:slider("qg", "Green", 1, 255, 150)
    self.menu.xerathDraw.q:slider("qb", "Blue", 1, 255, 150)
    self.menu.xerathDraw:sub("r", "R")
    self.menu.xerathDraw.r:checkbox("r", "R", true)
    self.menu.xerathDraw.r:checkbox("rmini", "R Minimap", true)
    self.menu.xerathDraw.r:slider("ra", "Alpha", 1, 255, 150)
    self.menu.xerathDraw.r:slider("rr", "Red", 1, 255, 150)
    self.menu.xerathDraw.r:slider("rg", "Green", 1, 255, 150)
    self.menu.xerathDraw.r:slider("rb", "Blue", 1, 255, 150)
end

function Xerath:DrawMinimapCircle(pos3d, radius, color)
    pos3d = Vector(pos3d)
    local pts = {}
    local dir = pos3d:normalized()

    for angle = 0, 360, 15 do
        local pos = TacticalMap:WorldToMinimap((pos3d + dir:RotatedAngle(angle) * radius):toDX3())
        if pos.x ~= 0 then
            pts[#pts + 1] = pos
        end
    end

    for i = 1, #pts - 1 do
        DrawHandler:Line(
            pts[i],
            pts[i + 1],
            color
        )
    end
end

function Xerath:OnDraw()
    if self.menu.xerathDraw.q.q:get() then
        local isQActive, remainingTime = self:IsQActive()
        local range = self.q.max

        if isQActive then
            range = self:GetQRange(remainingTime)
        end

        DrawHandler:Circle3D(
            myHero.position,
            range,
            self:Hex(
                self.menu.xerathDraw.q.qa:get(),
                self.menu.xerathDraw.q.qr:get(),
                self.menu.xerathDraw.q.qg:get(),
                self.menu.xerathDraw.q.qb:get()
            )
        )
    end
    color =
        self:Hex(
        self.menu.xerathDraw.r.ra:get(),
        self.menu.xerathDraw.r.rr:get(),
        self.menu.xerathDraw.r.rg:get(),
        self.menu.xerathDraw.r.rb:get()
    )
    if myHero.spellbook:Spell(SpellSlot.R).level > 0 then
        self.r.range = self:GetRRange()
        if self.menu.xerathDraw.r.r:get() then
            DrawHandler:Circle3D(myHero.position, self.r.range, color)
        end
        if self.menu.xerathDraw.r.rmini:get() then
            local radius = TacticalMap.width * self.r.range / 14692
            self:DrawMinimapCircle(myHero, self.r.range, color)
            --DrawHandler:Circle(TacticalMap:WorldToMinimap(myHero.position), self.r.range, color)
        end
    end
    if self:IsRActive() then
        DrawHandler:Circle3D(pwHud.hudManager.virtualCursorPos, self.menu.rr:get(), color)
    end
end

function Xerath:CastQ(target)
    local isQActive, remainingTime = self:IsQActive()

    if myHero.spellbook:CanUseSpell(0) == 0 then
        self.q.range = isQActive and self:GetQRange(remainingTime) or self.q.max

        local pred = _G.Prediction.GetPrediction(target, self.q, myHero)
        if
            pred.castPosition and (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                GetDistanceSqr(pred.castPosition) <= self.q.range * self.q.range
         then
            if isQActive then
                myHero.spellbook:UpdateChargeableSpell(0, pred.castPosition, true)
                return true
            else
                myHero.spellbook:CastSpell(0, pred.castPosition)
            end
        end
    end
end

function Xerath:CastW1(target)
    if myHero.spellbook:CanUseSpell(1) == 0 then
        local pred = _G.Prediction.GetPrediction(target, self.w1, myHero)
        if
            pred and pred.castPosition and (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                GetDistanceSqr(pred.castPosition) <= self.w1.range * self.w1.range
         then
            myHero.spellbook:CastSpell(1, pred.castPosition)
            return true
        end
    end
end

function Xerath:CastW2(target)
    if myHero.spellbook:CanUseSpell(1) == 0 then
        local pred = _G.Prediction.GetPrediction(target, self.w2, myHero)
        if
            pred and pred.castPosition and pred.hitChance >= self.menu.wc:get() / 100 and
                (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                GetDistanceSqr(pred.castPosition) <= self.w2.range * self.w2.range
         then
            myHero.spellbook:CastSpell(1, pred.castPosition)
            return true
        end
    end
end

function Xerath:CastE(target)
    if myHero.spellbook:CanUseSpell(2) == 0 then
        local pred = _G.Prediction.GetPrediction(target, self.e, myHero)
        if
            pred and pred.castPosition and (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                not pred:windWallCollision() and
                not pred:minionCollision() and
                pred.hitChance >= self.menu.e:get() / 100 and
                GetDistanceSqr(pred.castPosition) <= self.e.range * self.e.range
         then
            myHero.spellbook:CastSpell(2, pred.castPosition)
            return true
        end
    end
end

function Xerath:GetRRange()
    return 2000 + 1200 * myHero.spellbook:Spell(3).level
end

function Xerath:CastR()
    self.r.range = self:GetRRange()
    if myHero.spellbook:CanUseSpell(3) == 0 and self.menu.tap:get() then
        local targets = self:GetTarget(self.r.range, true)
        local targetMouse, targetGen = nil, nil
        for _, target in ipairs(targets) do
            if not targetGen then
                targetGen = target
            end
            if
                not targetMouse and
                    GetDistanceSqr(pwHud.hudManager.virtualCursorPos, target.position) <=
                        self.menu.rr:get() * self.menu.rr:get()
             then
                targetMouse = target
            end
        end
        local target = targetMouse or targetGen
        if target then
            local pred = _G.Prediction.GetPrediction(target, self.r, myHero)
            if
                pred and pred.castPosition and
                    (pred.realHitChance == 1 or _G.Prediction.WaypointManager.ShouldCast(target)) and
                    GetDistanceSqr(pred.castPosition) <= self.r.range * self.r.range
             then
                myHero.spellbook:CastSpell(3, pred.castPosition)
                return true
            end
        end
    end
end

function Xerath:OnTick()
    local qActive = self:IsQActive()
    local rActive = self:IsRActive()

    if qActive or rActive then
        LegitOrbwalker:BlockAttack(true)
    else
        LegitOrbwalker:BlockAttack(false)
    end

    if rActive then
        if self:CastR() then
            return
        end
    end
    for _, target in ipairs(self:GetTarget(self.e.range, true)) do
        if self.menu.antigap[target.charName] and self.menu.antigap[target.charName]:get() then
            local _, canHit = _G.Prediction.IsDashing(target, self.e, myHero)
            if canHit then
                self:CastE(target)
            end
        end
        if LegitOrbwalker:GetMode() == "Combo" and not LegitOrbwalker:IsAttacking() and self:CastE(target) then
            return
        end
    end
    local target = self:GetTarget(self.w1.range)
    if target then
        if LegitOrbwalker:GetMode() == "Combo" and not LegitOrbwalker:IsAttacking() then
            if self:CastW2(target) then
                return
            end
            if self:CastW1(target) then
                return
            end
        end
    end
    target = self:GetTarget(self.q.max)
    if target then
        if LegitOrbwalker:GetMode() == "Combo" and not LegitOrbwalker:IsAttacking() and self:CastQ(target) then
            return
        elseif LegitOrbwalker:GetMode() == "Harass" and not LegitOrbwalker:IsAttacking() and self:CastQ(target) then
            return
        end
    end
end

function Xerath:IsQActive()
    local buffs = myHero.buffManager.buffs

    for i = 1, #buffs do
        local buff = buffs[i]

        if buff.name == "XerathArcanopulseChargeUp" then
            return true, buff.remainingTime
        end
    end

    return false, 0
end

function Xerath:IsRActive()
    local buffs = myHero.buffManager.buffs

    for i = 1, #buffs do
        local buff = buffs[i]

        if buff.name == "XerathLocusOfPower2" then
            return true, buff.remainingTime
        end
    end

    return false, 0
end

function Xerath:GetQRange(remainingTime)
    local chargeStart = RiotClock.time + remainingTime - 4
    return math.min(
        self.q.min + (self.q.max - self.q.min) * (RiotClock.time - chargeStart - 0.2) / self.q.charge,
        self.q.max
    )
end

function Xerath:OnNewPath(obj, paths, isWalk, dashspeed)
end

function Xerath:Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

function Xerath:GetTarget(dist, all)
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

if myHero.charName == "Xerath" then
    Xerath:__init()
end
