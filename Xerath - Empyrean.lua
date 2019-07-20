if myHero.charName ~= "Xerath" then
    return
end

local CastModeOptions = {"slow", "very slow"}

local Xerath = {}
local version = 3
if tonumber(GetInternalWebResult("Xerath - Empyrean.version")) > version then
    DownloadInternalFile("Xerath - Empyrean.lua", SCRIPT_PATH .. "Xerath - Empyrean.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("Xerath - Empyrean.version")) .. " Press F5")
end
require("FF15Menu")
require("utils")
local DreamTS = require("DreamTS")
local Orbwalker = require("FF15OL")
local Vector = require("GeometryLib").Vector

function OnLoad()
    if not _G.Prediction then
        _G.LoadPaidScript(_G.PaidScript.DREAM_PRED)
    end
    if not _G.AuroraOrb and not _G.LegitOrbwalker then
        LoadPaidScript(PaidScript.AURORA_BUNDLE)
    end
    Orbwalker:Setup()
    Xerath:__init()
end

function Xerath:__init()
    self.q = {
        type = "linear",
        last = nil,
        min = 750,
        max = 1500,
        charge = 1.2,
        range = 1450,
        delay = 0.65,
        width = 145,
        speed = math.huge
    }
    self.w = {
        type = "circular",
        range = 1000,
        delay = 0.83,
        radius = 270,
        speed = math.huge
    }
    self.e = {
        type = "linear",
        range = 1000,
        delay = 0.25,
        width = 125,
        speed = 1400,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.e = {
        type = "linear",
        range = 1000,
        delay = 0.25,
        width = 125,
        speed = 1400,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.r = {
        type = "circular",
        active = false,
        range = 80000,
        delay = 0.7,
        radius = 200,
        speed = math.huge,
        lastTarget = nil,
        mode = nil
    }

    self.LastCasts = {
        Q1 = nil,
        Q2 = nil,
        W = nil,
        E = nil,
        R = nil
    }

    self:Menu()
    self.TS =
        DreamTS(
        self.menu.dreamTs,
        {
            Damage = DreamTS.Damages.AP
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
        Events.OnProcessSpell,
        function(obj, spell)
            self:OnProcessSpell(obj, spell)
        end
    )
    PrintChat("Xerath loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Xerath:Menu()
    self.menu = Menu("asdfxerath", "Xerath")

    self.menu:sub("dreamTs", "Target Selector")
    self.menu:sub("antigap", "Anti Gapclose")
    self.antiGapHeros = {}
    for _, enemy in ipairs(ObjectManager:GetEnemyHeroes()) do
        self.menu.antigap:checkbox(enemy.charName, enemy.charName, true)
        self.antiGapHeros[enemy.networkId] = true
    end
    self.menu:sub("interrupt", "Interrupter")
    _G.Prediction.LoadInterruptToMenu(self.menu.interrupt)

    self.menu:sub("spells", "Spell cast rates")
    self.menu.spells:list("q", "Q", 2, CastModeOptions)
    self.menu.spells:list("w", "W", 2, CastModeOptions)
    self.menu.spells:list("e", "E", 2, CastModeOptions)
    self.menu.spells:list("r", "R", 2, CastModeOptions)

    self.menu:slider("rr", "R Near Mouse Radius", 0, 3000, 1500)
    self.menu:key("tap", "Tap Key", string.byte("T"))
    self.menu:sub("xerathDraw", "Draw")
    self.menu.xerathDraw:sub("q", "Q")
    self.menu.xerathDraw.q:checkbox("q", "Q", true)
    self.menu.xerathDraw:sub("r", "R")
    self.menu.xerathDraw.r:checkbox("r", "R", true)
    self.menu.xerathDraw.r:checkbox("rmini", "R Minimap", true)
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
        DrawHandler:Line(pts[i], pts[i + 1], color)
    end
end

function Xerath:ShouldCast()
    for spell, time in pairs(self.LastCasts) do
        if time and RiotClock.time < time + 0.25 + NetClient.ping / 2000 + 0.06 then
            return false
        end
    end

    return true
end

function Xerath:GetCastRate(spell)
    return CastModeOptions[self.menu.spells[spell].value]
end

function Xerath:OnDraw()
    if self.menu.xerathDraw.q.q:get() then
        local isQActive, remainingTime = self:IsQActive()
        local range = self.q.max

        if isQActive then
            range = self:GetQRange(remainingTime)
        end

        DrawHandler:Circle3D(myHero.position, range, Color.White)
    end

    if myHero.spellbook:Spell(SpellSlot.R).level > 0 then
        self.r.range = self:GetRRange()
        if self.menu.xerathDraw.r.r:get() then
            DrawHandler:Circle3D(myHero.position, self.r.range, Color.White)
        end
        if self.menu.xerathDraw.r.rmini:get() then
            local radius = TacticalMap.width * self.r.range / 14692
            self:DrawMinimapCircle(myHero, self.r.range, Color.White)
        end
    end
    if self:IsRActive() then
        DrawHandler:Circle3D(pwHud.hudManager.virtualCursorPos, self.menu.rr:get(), Color.White)
        local text = "All"
        if self.r.mode then
            text = "Mouse"
        end
        DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)
    end
end

function Xerath:CastQ(pred)
    local isQActive, remainingTime = self:IsQActive()

    if isQActive then
        return self:CastQ2(pred, isQActive and self:GetQRange(remainingTime) or self.q.max)
    elseif pred.rates["instant"] then
        myHero.spellbook:CastSpell(0, pred.castPosition)
        self.LastCasts.Q1 = RiotClock.time
        self:CastQ2(pred, self.q.min)
        return true
    end
end

function Xerath:CastQ2(pred, range)
    local dist = GetDistanceSqr(pred.castPosition)
    local rangeAdjust = range - 100
    if pred.rates[self:GetCastRate("q")] or (dist > 100 * 100 and dist < 400 * 400) then
        if pred.isMoving and not pred.targetDashing then
            if dist > rangeAdjust * rangeAdjust then
                return
            end
        else
            if dist > range * range then
                return
            end
        end

        myHero.spellbook:UpdateChargeableSpell(0, pred.castPosition, true)

        pred.drawRange = range -- So debug draw shows it at the correct range rather than always self.q.max
        pred:draw()

        self.LastCasts.Q2 = RiotClock.time

        return true
    end
end

function Xerath:CastW(pred)
    if pred.rates[self:GetCastRate("w")] then
        myHero.spellbook:CastSpell(SpellSlot.W, pred.castPosition)
        self.LastCasts.W = RiotClock.time
        pred:draw()
        return true
    end
end

function Xerath:CastE(pred)
    if pred.rates[self:GetCastRate("e")] then
        myHero.spellbook:CastSpell(2, pred.castPosition)
        self.LastCasts.E = RiotClock.time
        pred:draw()
        return true
    end
end

function Xerath:GetRRange()
    return 2000 + 1200 * myHero.spellbook:Spell(3).level
end

function Xerath:CastTrinket()
    if
        myHero.spellbook:CanUseSpell(SpellSlot.Trinket) and self.r.lastTarget and not self.r.lastTarget.isDead and
            not self.r.lastTarget.isVisible
     then
        local castRange = myHero.spellbook:Spell(SpellSlot.Trinket).castRange
        if GetDistanceSqr(self.r.lastTarget) <= castRange * castRange then
            myHero.spellbook:CastSpell(SpellSlot.Trinket, self.r.lastTarget.position)
        end
    end
end

function Xerath:CastR()
    self.r.range = self:GetRRange()
    local maxRangeSqr = self.menu.rr:get() * self.menu.rr:get()
    local mouseTarget, mousePred =
        self:GetTarget(
        self.r,
        false,
        function(unit)
            return GetDistanceSqr(pwHud.hudManager.virtualCursorPos, unit) <= maxRangeSqr
        end
    )
    local allTarget, allPred = self:GetTarget(self.r)
    if self.r.lastTarget and self.r.lastTarget.isVisible and allTarget and allPred and allTarget ~= self.r.lastTarget then
        self.r.lastTarget = nil
        self.r.mode = nil
    end
    if self.menu.tap:get() and myHero.spellbook:CanUseSpell(3) == 0 then
        if mouseTarget and mousePred then
            if mousePred.rates[self:GetCastRate("r")] then
                myHero.spellbook:CastSpell(3, mousePred.castPosition)
                self.LastCasts.R = RiotClock.time
                self.r.lastTarget = mouseTarget
                self.r.mode = true
                mousePred:draw()
                return true
            end
        elseif (not self.r.mode) and allTarget and allPred then
            if allPred.rates[self:GetCastRate("r")] then
                myHero.spellbook:CastSpell(3, allPred.castPosition)
                self.LastCasts.R = RiotClock.time
                self.r.lastTarget = allTarget
                allPred:draw()
                return true
            end
        end
    end
end

function Xerath:OnTick()
    local qActive = self:IsQActive()
    local rActive = self:IsRActive()

    if qActive or rActive then
        Orbwalker:BlockAttack(true)
    else
        Orbwalker:BlockAttack(false)
    end
    -- Will waste pred calls without these conditions as well as call Cast when can't cast
    if not qActive and self:ShouldCast() then
        if rActive then
            if self:CastTrinket() or self:CastR() then
                return
            end
        else
            self.r.lastTarget = nil
            self.r.mode = nil
            if myHero.spellbook:CanUseSpell(SpellSlot.E) == 0 then
                local gapcloser_targets, gapcloser_preds =
                    self:GetTarget(
                    self.e,
                    true,
                    nil,
                    function(unit, pred)
                        if not pred then
                            return
                        end

                        if
                            pred.targetDashing and self.antiGapHeros[unit.networkId] and
                                self.menu.antigap[unit.charName]:get()
                         then
                            return true
                        end
                        if pred.isInterrupt and self.menu.interrupt[pred.interruptName]:get() then
                            return true
                        end

                        return false
                    end
                )

                for i = 1, #gapcloser_targets do
                    local pred = gapcloser_preds[gapcloser_targets[i].networkId]
                    if pred and self:CastE(pred) then
                        return
                    end
                end

                local e_target, e_pred = self:GetTarget(self.e)

                if
                    e_target and e_pred and Orbwalker:GetMode() == "Combo" and not Orbwalker:IsAttacking() and
                        self:CastE(e_pred)
                 then
                    return
                end
            end

            if myHero.spellbook:CanUseSpell(SpellSlot.W) == 0 then
                local w_target, w_pred = self:GetTarget(self.w)
                if w_target and w_pred then
                    if Orbwalker:GetMode() == "Combo" and not Orbwalker:IsAttacking() then
                        if self:CastW(w_pred) then
                            return
                        end
                    end
                end
            end
        end
    end

    if myHero.spellbook:CanUseSpell(SpellSlot.Q) == 0 and self:ShouldCast() then
        self.q.range = self.q.max

        local q_target, q_pred =
            self:GetTarget(
            self.q,
            false,
            nil,
            function(unit, pred)
                return pred.rates["instant"]
            end
        )
        if q_target and q_pred then
            if Orbwalker:GetMode() == "Combo" and not Orbwalker:IsAttacking() and self:CastQ(q_pred) then
                return
            elseif Orbwalker:GetMode() == "Harass" and not Orbwalker:IsAttacking() and self:CastQ(q_pred) then
                return
            end
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

function Xerath:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "XerathArcanopulseChargeUp" then
            self.LastCasts.Q1 = nil
        elseif spell.spellData.name == "XerathArcanopulse2" then
            self.LastCasts.Q2 = nil
        elseif spell.spellData.name == "XerathArcaneBarrage2" then
            self.LastCasts.W = nil
        elseif spell.spellData.name == "XerathMageSpear" then
            self.LastCasts.E = nil
        elseif spell.spellData.name == "XerathLocusPulse" then
            self.LastCasts.R = nil
        end
    end
end

function Xerath:GetQRange(remainingTime)
    local chargeStart = RiotClock.time + remainingTime - 4
    return math.min(
        self.q.min + (self.q.max - self.q.min) * (RiotClock.time - chargeStart - 0.2) / self.q.charge,
        self.q.max
    )
end

function Xerath:GetTarget(spell, all, targetFilter, predFilter)
    local units, preds = self.TS:GetTargets(spell, myHero.position, targetFilter, predFilter)
    if all then
        return units, preds
    else
        local target = self.TS.target
        if target then
            return target, preds[target.networkId]
        end
    end
end
