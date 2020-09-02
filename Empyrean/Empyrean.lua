local version = 1.14

GetInternalWebResultAsync(
    "Empyrean.version",
    function(v)
        if tonumber(v) > version then
            DownloadInternalFileAsync(
                "Empyrean.lua",
                SCRIPT_PATH,
                function(success)
                    if success then
                        PrintChat("Empyrean loader updated. Press F5")
                    end
                end
            )
        end
    end
)

local Orbwalker = require("ModernUOL")
if not Orbwalker then
    DownloadInternalFileAsync(
        "ModernUOL.lua",
        COMMON_PATH,
        function(success)
            if success then
                PrintChat("UOL updated. Press F5")
                Orbwalker = require("ModernUOL")
            end
        end
    )
    return
end

local dir = COMMON_PATH .. "Empyrean\\"

CreateFolder(dir)
local champs = {
    Ezreal = 3.02,
    Kaisa = 1.93,
    Syndra = 3.4,
    Xerath = 3.83,
    Lucian = 1.1,
    Zoe = 1,
    Irelia = 1.1
}
if not champs[myHero.charName] then
    return
end

local function FileExists(path)
    local file = io.open(path)
    if file then
        io.close(file)
        return true
    end

    return false
end

if not FileExists(dir .. myHero.charName .. "Empyrean.lua") then
    DownloadInternalFileAsync(
        myHero.charName .. "Empyrean.lua",
        dir,
        function(success)
            if success then
                PrintChat(myHero.charName .. " downloaded. Press F5")
            end
        end
    )
    return
end

local script = require("Empyrean" .. "\\" .. myHero.charName .. "Empyrean")
local dependencies = {
    {
        "DreamPred",
        _G.PaidScript.DREAM_PRED,
        function()
            return _G.Prediction
        end
    }
}

if champs[myHero.charName] > script.version then
    DownloadInternalFileAsync(
        myHero.charName .. "Empyrean.lua",
        dir,
        function(success)
            if success then
                PrintChat(myHero.charName .. " updated. Press F5")
            end
        end
    )
end

Orbwalker:OnOrbLoad(
    function()
        _G.LoadDependenciesAsync(
            dependencies,
            function(success)
                if success then
                    script()
                end
            end
        )
    end
)
