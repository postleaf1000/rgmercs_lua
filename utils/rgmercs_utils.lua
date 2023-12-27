local mq                = require('mq')
local RGMercsLogger     = require("rgmercs.utils.rgmercs_logger")
local animSpellGems     = mq.FindTextureAnimation('A_SpellGems')
local ICONS             = require('mq.Icons')
local ICON_SIZE         = 20

-- Global
Memorizing = false

local Utils      = { _version = '0.1a', author = 'Derple' }
Utils.__index    = Utils
Utils.Actors     = require('actors')
Utils.ScriptName = "RGMercs"

function Utils.BroadcastUpdate(module, event)
    Utils.Actors.send({ from = RGMercConfig.CurLoadedChar, script = Utils.ScriptName, module = module, event = event })
end

function Utils.PrintGroupMessage(msg)
    mq.cmdf("/dgt group_%s_%s %s", RGMercConfig.CurServer, mq.TLO.Group.Leader() or "None", msg)
end

---@param t table
function Utils.CheckPlugins(t)
    for _, p in pairs(t) do
        if not mq.TLO.Plugin(p)() then
            mq.cmdf("/squelch /plugin %s noauto", p)
            RGMercsLogger.log_info("\aw %s \ar not detected! \aw This macro requires it! Loading ...", p)
        end
    end
end

---@param t table
---@return table
function Utils.UnCheckPlugins(t)
    local r = {}
    for _, p in pairs(t) do
        if mq.TLO.Plugin(p)() then
            mq.cmdf("/squelch /plugin %s unload noauto", p)
            RGMercsLogger.log_info("\ar %s detected! \aw Unloading it due to known conflicts with RGMercs!", p)
            table.insert(r, p)
        end
    end

    return r
end

function Utils.GetBestSpell(t)
    local highestLevel = 0
    local selectedSpell = nil

    for _, s in ipairs(t or {}) do
        local spell = mq.TLO.Spell(s)
        --RGMercsLogger.log_debug("Found %s level(%d) rank(%s)", s, spell.Level(), spell.RankName())
        if spell.Level() <= mq.TLO.Me.Level() then
            if mq.TLO.Me.Book(spell.RankName())() or mq.TLO.Me.CombatAbility(spell.RankName())() then
                if spell.Level() > highestLevel then
                    highestLevel = spell.Level()
                    selectedSpell = spell
                end
            else
                Utils.PrintGroupMessage(string.format("%s \aw [%s] \ax \ar MISSING SPELL \ax -- \ag %s \ax -- \aw LVL: %d \ax", mq.TLO.Me.CleanName(), s, spell.RankName(), spell.Level() ))
            end
        end
    end

    if selectedSpell then
        RGMercsLogger.log_debug("\agFound\ax %s level(%d) rank(%s)", selectedSpell.BaseName(), selectedSpell.Level(), selectedSpell.RankName())
    else
        RGMercsLogger.log_debug("\arNo spell found for slot!")
    end

    return selectedSpell
end

function Utils.DotSpellCheck(config, spell)
    return not mq.TLO.Target.FindBuff("id "..tostring(spell.ID())).ID() and spell.StacksTarget() and mq.TLO.Target.PctHPs > config.HPStopDOT
end

function Utils.DetAACheck(aaId)
    if not mq.TLO.Target.ID() then return false end
    local Target = mq.TLO.Target
    local Me     = mq.TLO.Me

    return (not Target.FindBuff("id " .. tostring(Me.AltAbility(aaId).Spell.ID())).ID() and
           not Target.FindBuff("id " .. tostring(Me.AltAbility(aaId).Spell.Trigger(1).ID()))) and
           (Me.AltAbility(aaid).Spell.StacksTarget() or Me.AltAbility(aaid).Spell.Trigger(1).StacksTarget())
end

function Utils.DrawInspectableSpellIcon(iconID, spell)
    local cursor_x, cursor_y = ImGui.GetCursorPos()

    animSpellGems:SetTextureCell(iconID or 0)

    ImGui.DrawTextureAnimation(animSpellGems, ICON_SIZE, ICON_SIZE)

    ImGui.SetCursorPos(cursor_x, cursor_y)

    ImGui.PushID(tostring(iconID) .. spell.Name() .. "_invis_btn")
    ImGui.InvisibleButton(spell.Name(), ImVec2(ICON_SIZE, ICON_SIZE),
        bit32.bor(ImGuiButtonFlags.MouseButtonLeft))
    if ImGui.IsItemHovered() and ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
        spell.Inspect()
    end
    ImGui.PopID()
end

function Utils.RenderLoadoutTable(t)
    if ImGui.BeginTable("Spells", 5, ImGuiTableFlags.Resizable + ImGuiTableFlags.Borders) then
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.0, 1.0, 1)
        ImGui.TableSetupColumn('Icon', (ImGuiTableColumnFlags.WidthFixed), 20.0)
        ImGui.TableSetupColumn('Gem', (ImGuiTableColumnFlags.WidthFixed), 20.0)
        ImGui.TableSetupColumn('Base Name',(ImGuiTableColumnFlags.WidthFixed), 150.0)
        ImGui.TableSetupColumn('Level', ImGuiTableColumnFlags.None, 20.0)
        ImGui.TableSetupColumn('Rank Name', ImGuiTableColumnFlags.None, 150.0)
        ImGui.PopStyleColor()
        ImGui.TableHeadersRow()

        for gem, spell in pairs(t) do
            ImGui.TableNextColumn()
            Utils.DrawInspectableSpellIcon(spell.SpellIcon(), spell)
            ImGui.TableNextColumn()
            ImGui.Text(tostring(gem))
            ImGui.TableNextColumn()
            ImGui.Text(spell.BaseName())
            ImGui.TableNextColumn()
            ImGui.Text(tostring(spell.Level()))
            ImGui.TableNextColumn() 
            ImGui.Text(spell.RankName())
        end

        ImGui.EndTable()
    end
end

function Utils.RenderOptionToggle(id, text, on)
    local toggled = false
    local state   = on
    ImGui.PushID(id .. "_togg_btn")
    if on then
        if ImGui.SmallButton(ICONS.FA_TOGGLE_ON) then
            toggled = true
            state   = false
        end
    else
        if ImGui.SmallButton(ICONS.FA_TOGGLE_OFF) then
            toggled = true
            state   = true
        end
    end
    ImGui.PopID()
    ImGui.SameLine()
    ImGui.Text(text)

    return state, toggled
end

function Utils.LoadSpellLoadOut(t)
    local selectedRank = ""

    for gem, spell in pairs(t) do

        if mq.TLO.Me.SpellRankCap() > 1 then
            selectedRank = spell.RankName()
        else
            selectedRank = spell.BaseName()
        end

        if mq.TLO.Me.Gem(gem)() ~= selectedRank then
            RGMercsLogger.log_info("\ag Meming \aw %s in \ag slot %d", selectedRank, gem)
            mq.cmdf("/memspell %d \"%s\"", gem, selectedRank)

            while mq.TLO.Me.Gem(gem)() ~= selectedRank do
                mq.delay(10)
            end
        end
    end
end

mq.event('Being Memo', "Beginning to memorize #1#...", function(spell)
    Memorizing = true
end)

mq.event('End Memo', "You have finished memorizing #1#", function(spell)
    Memorizing = false
end)

mq.event('Abort Memo', "Aborting memorization of spell.", function()
    Memorizing = false
end)

return Utils
