local Ezreal = {}
local version = 2.1
if tonumber(GetInternalWebResult("asdfezreal.version")) > version then
    DownloadInternalFile("asdfezreal.lua", SCRIPT_PATH .. "asdfezreal.lua")
    PrintChat("New version:" .. tonumber(GetInternalWebResult("asdfezreal.version")) .. " Press F5")
end
require "FF15Menu"
require "utils"
local DreamTS = require("DreamTS")
local dmgLib = require("FF15DamageLib")
local Orbwalker = require "FF15OL"

function OnLoad()
    if not _G.Prediction then
        LoadPaidScript(PaidScript.DREAM_PRED)
    end
    if not _G.AuroraOrb and not _G.LegitOrbwalker then
        LoadPaidScript(PaidScript.AURORA_BUNDLE)
    end

    Orbwalker:Setup()
end

function Ezreal:__init()
    self.q = {
        type = "linear",
        speed = 2000,
        range = 1150,
        delay = 0.25,
        width = 125,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.w = {
        type = "linear",
        speed = 1700,
        range = 1150,
        delay = 0.25,
        width = 165,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = false
        }
    }
    self.r = {
        type = "linear",
        speed = 2000,
        range = 2500,
        delay = 1,
        width = 325,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = false
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
    PrintChat("Ezreal loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Ezreal:Menu()
    self.menu = Menu("asdfezreal", "Ezreal")
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:checkbox("q", "AutoQ", true, string.byte("T"))
    self.menu:checkbox("user", "Use R", true)
    self.menu:key("r", "Manual R Key", 0x5A)
    self.menu:sub("ezrealDraw", "Draw")
    self.menu.ezrealDraw:checkbox("q", "Q", true)
    self.menu.ezrealDraw:slider("qa", "Alpha", 1, 255, 150)
    self.menu.ezrealDraw:slider("q0r", "AutoQ off: Red", 1, 255, 150)
    self.menu.ezrealDraw:slider("q0g", "AutoQ off: Green", 1, 255, 150)
    self.menu.ezrealDraw:slider("q0b", "AutoQ off: Blue", 1, 255, 150)
    self.menu.ezrealDraw:slider("q1r", "AutoQ on: Red", 1, 255, 255)
    self.menu.ezrealDraw:slider("q1g", "AutoQ on: Green", 1, 255, 150)
    self.menu.ezrealDraw:slider("q1b", "AutoQ on: Blue", 1, 255, 150)
end

function Ezreal:OnDraw()
    if self.menu.ezrealDraw.q:get() then
        if self.menu.q:get() then
            DrawHandler:Circle3D(
                myHero.position,
                self.q.range,
                self:Hex(
                    self.menu.ezrealDraw.qa:get(),
                    self.menu.ezrealDraw.q1r:get(),
                    self.menu.ezrealDraw.q1g:get(),
                    self.menu.ezrealDraw.q1b:get()
                )
            )
            text = "AutoQ on"
        else
            DrawHandler:Circle3D(
                myHero.position,
                self.q.range,
                self:Hex(
                    self.menu.ezrealDraw.qa:get(),
                    self.menu.ezrealDraw.q0r:get(),
                    self.menu.ezrealDraw.q0g:get(),
                    self.menu.ezrealDraw.q0b:get()
                )
            )
            text = "AutoQ off"
        end
    end
    DrawHandler:Text(DrawHandler.defaultFont, Renderer:WorldToScreen(myHero.position), text, Color.White)

    if self.wBuffTarget then
        DrawHandler:Circle3D(
            self.wBuffTarget.position,
            20,
            self:Hex(
                self.menu.ezrealDraw.qa:get(),
                self.menu.ezrealDraw.q0r:get(),
                self.menu.ezrealDraw.q0g:get(),
                self.menu.ezrealDraw.q0b:get()
            )
        )
    end
end

function Ezreal:CastQ()
    if myHero.spellbook:CanUseSpell(0) == 0 then
        local qTargets, qPred =
            self:GetTarget(
            self.q,
            true,
            nil,
            function(unit, pred)
                return pred.rates["very slow"] or
                    GetDistanceSqr(pred.castPosition) <
                        myHero.characterIntermediate.attackRange * myHero.characterIntermediate.attackRange
            end
        )
        if self.wBuffTarget and qPred[self.wBuffTarget.networkId] then
            myHero.spellbook:CastSpell(0, qPred[self.wBuffTarget.networkId].castPosition)
        end
        for _, pred in pairs(qPred) do
            myHero.spellbook:CastSpell(0, pred.castPosition)
        end
    end
end

function Ezreal:OnTick()
    if not Orbwalker:IsAttacking() then
        if self.menu.r:get() and myHero.spellbook:CanUseSpell(3) == 0 then
            local rTarget, rPred = self:GetTarget(self.r)
            if rTarget and rPred and rPred.rates["very slow"] then
                myHero.spellbook:CastSpell(3, rPred.castPosition)
            end
        end
        if Orbwalker:GetMode() == "Combo" then
            if self.menu.user:get() and myHero.spellbook:CanUseSpell(3) == 0 then
                local rTarget, rPred =
                    self:GetTarget(
                    self.r,
                    false,
                    nil,
                    function(unit, pred)
                        return pred:heroCollision(2)
                    end
                )
                if rTarget and rPred and rPred.rates["very slow"] then
                    myHero.spellbook:CastSpell(3, rPred.castPosition)
                end
            end
            if myHero.spellbook:CanUseSpell(1) == 0 then
                local wTarget, wPred = self:GetTarget(self.w)
                if wTarget and wPred and wPred.rates["very slow"] then
                    myHero.spellbook:CastSpell(1, wPred.castPosition)
                end
            end
            self:CastQ()
        elseif self.menu.q:get() and not _G.Prediction.IsRecalling(myHero) then
            self:CastQ()
        end
    end
end

function Ezreal:OnBuffGain(obj, buff)
    if obj and obj.team ~= myHero.team and obj.type == myHero.type and buff.name == "ezrealwattach" then
        self.wBuffTarget = obj
        Orbwalker:ForceTarget(obj)
    end
end

function Ezreal:OnBuffLost(obj, buff)
    if obj and obj.team ~= myHero.team and obj.type == myHero.type and buff.name == "ezrealwattach" then
        self.wBuffTarget = nil
        Orbwalker:ResetForcedTarget()
    end
end

function Ezreal:Hex(a, r, g, b)
    return string.format("0x%.2X%.2X%.2X%.2X", a, r, g, b)
end

function Ezreal:GetTarget(spell, all, targetFilter, predFilter)
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

if myHero.charName == "Ezreal" then
    Ezreal:__init()
end
