-- EXP SHARE -- the EXP SHARE option's distribution rules.
--
-- One options row (options.lua: off / gen1 / gen2 / gen3 / gen6) selecting
-- which generation's party-wide experience behaviour a battle uses.  OFF
-- (default) defers to the game's own award untouched; the four generation
-- modes replace the split through the engine's shared battle.exp_award seam
-- -- the same seam both generations expose (Gen 1's
-- src/battle/BattleState.lua awardExp and Gen 2's
-- src/battle/gen2/Battle.lua awardExperience, which native.lua's Gen 1 model
-- now also raises -- see state:awardExperience there).
--
-- The engine's ctx is { battle, participants, alive, applyShare } on Gen 1
-- and { battle, participants, alive, applyShare, recipients, holders,
-- halved, loser } on Gen 2.  `applyShare(mon, split, announce)` pays ONE mon
-- using the generation's own formula: split is the DIVISOR its base exp
-- (and stat exp) are divided by, and `announce` (Gen 1's third argument,
-- honoured on Gen 2) prints that mon's GainedText line (truthy) or pays it
-- silently (falsy / an explicit nil).
--
-- WHAT EACH MODE DOES.  E is the defeated enemy's full base exp (before the
-- level/trainer/traded multipliers), n the number of ACTIVE party members
-- counted for the kill (fainted ones included -- their share is simply lost,
-- per the spec), P the party size and H the number of non-fainted party
-- members.  A fainted mon never receives anything in any mode.
--
--   gen1 -- Exp. All.  Every non-fainted active mon gets E/(2n).  Then every
--           non-fainted party mon gets E/(2nP): the participant division is
--           inherited by the party pass (the documented Gen 1 bug), so a
--           fainted party member's slice is lost rather than re-spread.
--   gen2 -- Exp. Share held.  50% of E is split among the non-fainted active
--           mons (E/(2n) each) and 50% among the non-fainted party (E/(2H)
--           each).  A mon that is BOTH active and a recipient therefore
--           collects twice -- the documented Gen II "shown twice" quirk --
--           and the numbers are floored once per pass.
--   gen3 -- Generation III-V's split.  Numerically identical to gen2 (the
--           Gen III-V level-exp rule is the same 50/50); the only difference
--           is that the shares are announced once rather than per pass.
--   gen6 -- Exp. Share key item.  Every non-fainted ACTIVE mon gets the full
--           E (100% each, undivided); every other non-fainted party mon
--           gets E/2 (50%).  Activity is per enemy: a mon counts as active
--           only while it stood on the field during THAT enemy's presence.
--
-- The "active" set is the scene's own, not the engine's participant list.
-- The user's rule: a mon is active for an enemy if it was on the field at
-- any point during that enemy's stay, and only an enemy SWITCH-OUT (not a
-- faint) resets the set -- the replacement enemy starts a fresh one.  The
-- screen tracks it (self.expActive) and hands it to the seam as
-- `battle.expSharePending = { active = <set of mon tables>, ... }` right
-- before each award, so this module reads it off ctx.battle.
--
-- EVs ARE NOT TOUCHED.  The spec keeps modern EV points whole in every
-- generation and changes only the level-experience amount distributed, so
-- this module never scales an EV award.  On Gen 2 applyShare runs the
-- engine's own giveExperiencePass, whose battle.exp_gained event is what the
-- engine's EV-yield subscriber listens for; on Gen 1 this module's own
-- applyShare emits the same event.  Primitive stat experience (Gen 1 stat
-- exp) is divided along with the exp by the engine's own formula and is
-- deliberately left alone.
--
-- `ctx.halved` on Gen 2 is the engine's own EXP.SHARE tax (any real holder
-- halves the whole pool before applyShare divides).  Since every mode here
-- already encodes the halving in its divisors, the divisors are halved again
-- (`f = 0.5`) when ctx.halved is set, so the intended share is not taxed
-- twice when a player also happens to hold the item.
--
-- CONDENSED ANNOUNCEMENT (the whole award is two messages, not one per mon).
-- A generation mode never prints a GainedText box per recipient any more.
-- `M.distribute` pays every share silently (applyShare's third argument is
-- an explicit false, which Gen 2's seam reads as "pay it, do not print its
-- line") and records what each mon actually gained, from the
-- battle.exp_gained event both generations raise (with the return value of
-- our own Gen 1 applyShare as a fallback for the no-Runtime case).  It then
-- builds exactly TWO summary lines for the award and inserts them at the
-- FRONT of that award's own events, so they read as the award's header and
-- the "grew to level" lines follow instead of the exp amounts arriving after
-- them:
--
--   gen6, four actives + two bench:
--     PIKACHU, CHARMELEON, BLASTOISE and VENUSAUR gained 120 EXP. Points!
--     EEVEE and SNORLAX gained 60 EXP. Points!
--
-- The split is ACTIVE vs the rest (the bench), matching the user's format
-- and the per-enemy active rule above: the first line lists every mon the
-- active set counted, the second every other party mon that was paid.  A mon
-- that collects on BOTH passes (gen1/gen2/gen3 -- the active mon also
-- appears in the party pass) has its lines SUMMED into one figure on the
-- active line, so each mon is named exactly once and the number is the total
-- level-experience it actually gained from this award.  Within one line, if
-- every mon gained the same amount the amount prints once; if one mon's
-- traded 1.5x (or the like) makes them differ, each name carries its own
-- figure.  OFF is untouched: no summaries, the vanilla award's own
-- narration.
return function(mod)
  local MODES = { off = true, gen1 = true, gen2 = true, gen3 = true, gen6 = true }

  -- Same defensive option read every sibling uses: pcall'd, string-only,
  -- falling back when the mod is disabled or running under a harness.
  local function optionString(key, fallback)
    local options = mod and mod.options
    if options and type(options.get) == "function" then
      local ok, value = pcall(function() return options:get(key) end)
      if ok and type(value) == "string" and value ~= "" then return value end
    end
    return fallback
  end

  local function aliveMon(mon)
    return type(mon) == "table" and (mon.hp or 0) > 0
  end

  -- The party behind a battle on either generation: Gen 2's Battle carries it
  -- directly (battle.party, aliasing save.party); Gen 1's model carries it on
  -- the live game (battle.game.save.party).  Also accepts a pending.party
  -- override the scene may hand through on expSharePending.
  local function partyOf(battle, pending)
    if pending and type(pending.party) == "table" then return pending.party end
    if type(battle) ~= "table" then return {} end
    if type(battle.party) == "table" then return battle.party end
    local save = battle.save or (battle.game and battle.game.save)
    return (save and save.party) or {}
  end

  -- The per-enemy active set.  Prefers the scene's pending set; without it
  -- (a bare hook call, or a harness) falls back to ctx.alive so the mode
  -- still does something sane.
  local function activeSetOf(ctx, battle)
    local pending = type(battle) == "table" and battle.expSharePending or nil
    if pending and type(pending.active) == "table" and next(pending.active) then
      return pending.active
    end
    local set = {}
    if ctx and type(ctx.alive) == "table" then
      for _, mon in ipairs(ctx.alive) do
        if type(mon) == "table" then set[mon] = true end
      end
    end
    return set
  end

  -- The pure distribution: a list of { mon, split } the caller can assert
  -- against.  `halved` is Gen 2's engine tax (see the header).  The caller
  -- pays every row silently and condenses the narration itself, so this
  -- returns no announce flag.
  local function shares(mode, party, activeSet, halved)
    local out = {}
    if type(party) ~= "table" then return out end
    local f = halved and 0.5 or 1
    local aliveParty, aliveActive = {}, {}
    local activeCount = 0
    for _, mon in ipairs(party) do
      if type(mon) == "table" then
        if activeSet and activeSet[mon] then
          activeCount = activeCount + 1
          if aliveMon(mon) then aliveActive[#aliveActive + 1] = mon end
        end
        if aliveMon(mon) then aliveParty[#aliveParty + 1] = mon end
      end
    end
    -- Fainted mons still count toward the participant divisor (their share is
    -- lost); only when nobody at all is marked active do we fall back.
    local n = activeCount
    if n == 0 then n = #aliveActive end
    if n == 0 then n = 1 end
    local P = #party
    if mode == "gen1" then
      for _, mon in ipairs(aliveActive) do
        out[#out + 1] = { mon = mon, split = (2 * n) * f }
      end
      if P > 0 then
        local partyDiv = math.max(1, 2 * n * P) * f
        for _, mon in ipairs(aliveParty) do
          out[#out + 1] = { mon = mon, split = partyDiv }
        end
      end
    elseif mode == "gen2" or mode == "gen3" then
      for _, mon in ipairs(aliveActive) do
        out[#out + 1] = { mon = mon, split = (2 * n) * f }
      end
      local H = #aliveParty
      if H > 0 then
        local holderDiv = (2 * H) * f
        for _, mon in ipairs(aliveParty) do
          out[#out + 1] = { mon = mon, split = holderDiv }
        end
      end
    elseif mode == "gen6" then
      for _, mon in ipairs(aliveActive) do
        out[#out + 1] = { mon = mon, split = 1 * f }
      end
      for _, mon in ipairs(aliveParty) do
        if not (activeSet and activeSet[mon]) then
          out[#out + 1] = { mon = mon, split = 2 * f }
        end
      end
    end
    return out
  end

  -- ------------------------------------------------------------- narration --
  -- The recipient's display name: Gen 2's Battle:monName when the battle has
  -- one (the engine's own), else the raw mon/def name both generations store.
  local function displayName(battle, mon)
    if type(mon) ~= "table" then return "?" end
    if type(battle) == "table" and type(battle.monName) == "function" then
      local ok, name = pcall(battle.monName, battle, mon)
      if ok and type(name) == "string" and name ~= "" then return name end
    end
    local data = type(battle) == "table" and battle.data or nil
    local def = data and data.pokemon and data.pokemon[mon.species]
    local name = mon.nickname or (def and def.name)
    if type(name) == "string" and name ~= "" then return name end
    if mon.species ~= nil then return tostring(mon.species) end
    return "?"
  end

  -- "A", "A and B", "A, B and C" -- the user's list format.
  local function joinNames(names)
    local n = #names
    if n == 0 then return "" end
    if n == 1 then return names[1] end
    if n == 2 then return names[1] .. " and " .. names[2] end
    return table.concat(names, ", ", 1, n - 1) .. " and " .. names[n]
  end

  local function fmtAmount(value)
    if type(value) ~= "number" then return "0" end
    if value == math.floor(value) then return string.format("%d", value) end
    return string.format("%.1f", value)
  end

  -- One summary line for a group of mons and their captured gains, or nil
  -- when the group is empty.  A single common figure prints once; differing
  -- figures (a traded mon's 1.5x) print per name.
  local function buildSummary(battle, mons, amounts)
    if #mons == 0 then return nil end
    local names, values, allSame, firstValue = {}, {}, true, nil
    for i = 1, #mons do
      names[i] = displayName(battle, mons[i])
      local value = amounts[mons[i]]
      if type(value) ~= "number" then value = 0 end
      values[i] = value
      if i == 1 then
        firstValue = value
      elseif value ~= firstValue then
        allSame = false
      end
    end
    local text
    if allSame then
      text = string.format("%s gained %s EXP. Points!",
        joinNames(names), fmtAmount(firstValue))
    else
      local parts = {}
      for i = 1, #names do
        parts[i] = string.format("%s gained %s", names[i], fmtAmount(values[i]))
      end
      text = string.format("%s EXP. Points!", joinNames(parts))
    end
    return { kind = "experience", text = text }
  end

  -- Insert the summaries at `atIdx` in the battle's own event list (its
  -- award's event block starts there), so they precede the level-up lines.
  -- Falls back to a plain emit when the battle has no accessible list.
  local function emitSummaries(battle, list, atIdx)
    if type(battle) ~= "table" or #list == 0 then return end
    local events = battle.events
    if type(events) == "table" and type(atIdx) == "number" then
      for i = 1, #list do
        table.insert(events, atIdx + i - 1, list[i])
      end
      return
    end
    if type(battle.emit) == "function" then
      for i = 1, #list do pcall(battle.emit, battle, list[i]) end
    end
  end

  -- The capture sink: while distribute is paying, the shared
  -- battle.exp_gained event both generations raise lands each mon's real
  -- gain here, keyed by the mon table (summing the two passes of a
  -- double-collect).
  local captureTarget = nil
  local function onExpGained(payload)
    local sink = captureTarget
    if not sink or type(payload) ~= "table" then return end
    local mon, gained = payload.mon, payload.gained
    if type(mon) == "table" and type(gained) == "number" then
      sink[mon] = (sink[mon] or 0) + gained
    end
  end

  local M = {}
  mod.exports.expShare = M

  function M.mode()
    local value = optionString("exp_share", "off")
    if MODES[value] then return value end
    return "off"
  end

  M.MODES = MODES
  M.partyOf = partyOf
  M.activeSetOf = activeSetOf
  M.shares = shares

  -- Pay a whole award and narrate it as two condensed lines.  Returns the
  -- number of shares paid (0 when the mode has nothing to do).  applyShare
  -- is pcall'd per call so one bad payload costs a share, not the battle.
  function M.distribute(mode, ctx)
    if type(ctx) ~= "table" or type(ctx.applyShare) ~= "function" then return 0 end
    local battle = ctx.battle
    local pending = type(battle) == "table" and battle.expSharePending or nil
    local party = partyOf(battle, pending)
    local activeSet = activeSetOf(ctx, battle)
    local list = shares(mode, party, activeSet, ctx.halved)

    local eventCapture, returnCapture = {}, {}
    local previousTarget = captureTarget
    captureTarget = eventCapture
    local events = type(battle) == "table" and battle.events or nil
    local atIdx = type(events) == "table" and (#events + 1) or nil

    local paid = 0
    for _, share in ipairs(list) do
      local ok, gained = pcall(ctx.applyShare, share.mon, share.split, false)
      if ok then
        paid = paid + 1
        if type(gained) == "number" then
          returnCapture[share.mon] = (returnCapture[share.mon] or 0) + gained
        end
      end
    end
    captureTarget = previousTarget

    -- Prefer the engine's own battle.exp_gained payloads; fall back to what
    -- our own Gen 1 applyShare returned when no Runtime raised the event.
    local amounts = next(eventCapture) and eventCapture or returnCapture
    if next(amounts) then
      local actives, bench = {}, {}
      for _, mon in ipairs(party) do
        if type(mon) == "table" and amounts[mon] ~= nil then
          if activeSet[mon] then
            actives[#actives + 1] = mon
          else
            bench[#bench + 1] = mon
          end
        end
      end
      local summaries = {}
      local activeLine = buildSummary(battle, actives, amounts)
      if activeLine then summaries[#summaries + 1] = activeLine end
      local benchLine = buildSummary(battle, bench, amounts)
      if benchLine then summaries[#summaries + 1] = benchLine end
      emitSummaries(battle, summaries, atIdx)
    end
    return paid
  end

  -- Observe every gain the award raises so M.distribute can build the
  -- summaries above.  Harmless outside an award (the sink is nil) and in
  -- harnesses without a mod.events facade.
  if mod and mod.events and type(mod.events.on) == "function" then
    pcall(function() mod.events:on("battle.exp_gained", onExpGained, 0) end)
  end

  -- battle.exp_award: OFF defers to the vanilla chain (next, so any other
  -- mod's wrap still runs); a generation mode replaces the split outright.
  -- Priority 90 mirrors the established battle.exp_award mod convention
  -- (the reference exp_share mod) so this wins over lower-priority wraps.
  mod.hooks:wrap("battle.exp_award", function(nextFn, ctx)
    local mode = M.mode()
    if mode == "off" then return nextFn(ctx) end
    if type(ctx) ~= "table" or type(ctx.applyShare) ~= "function" then
      return nextFn(ctx)
    end
    local ok, err = pcall(M.distribute, mode, ctx)
    if not ok then
      mod.log:warn("g9_Battle_Scene: exp_share %s failed: %s -- vanilla award kept",
        mode, tostring(err))
      return nextFn(ctx)
    end
  end, 90)

  mod.log:info("g9_Battle_Scene: EXP SHARE ready (off / gen1 / gen2 / gen3 / gen6)")
end
