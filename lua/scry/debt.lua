-- Theory-debt: separate numbers, never one blended fraction. Unratified
-- and diverged are different kinds of wrongness, and the claim count leads
-- every rendering — "0 diverged / 3 claims" must read as a THIN map, not a
-- healthy repo. Debt is coverage-blind until exists-unclaimed lands, and
-- the docs say so.
local M = {}

---@class scry.Debt
---@field claims integer
---@field backed integer  backed or clean verdicts.
---@field missing integer
---@field violated integer
---@field unchecked integer no resolver, parse failure, resolver error, or no
---  verdict at all. NOT a pass — the fourth column exists so this can never
---  be inferred by subtraction.
---@field untouched integer no work has passed through this claim: not
---  authored by hand, not conjured to completion. Ownership is INFERRED
---  from the trail (see provenance.lua), never performed as an act.
---@field features integer
---@field done integer      features whose every claim holds AND that someone
---  here has engaged with.
---@field unread integer    features whose every claim holds and that nobody
---  has read: a fresh draft, or a map you have just cloned. Counted apart
---  from `done` because otherwise the first line of the header reports a
---  finished product on evidence nobody has looked at.
---@field building integer  features with some evidence, none broken.
---@field broken integer    features with a violated or failing claim.
---@field todo integer      features with no evidence holding yet.
---@field unknown integer   features nothing has answered for.
---@field unclaimed integer  files no feature's footprint names. Reflexion's
---  third verdict: without it, every feature can be done while the map
---  describes a tenth of the product, and nothing would say so.

--- Count a map + report into debt numbers. A claim can count on both the
--- diverged and unratified axes; each axis counts it once.
---
--- backed + missing + violated + unchecked == claims, always. That identity
--- is the honesty property: a claim no engine could answer must show up
--- somewhere, or a header reading "0 missing · 0 violated" invites the reader
--- to conclude the rest are fine.
---@param map_ scry.Map
---@param report scry.Report?
---@param root string? Project root; without it nothing counts as owned, and
---  divergence cannot be computed.
---@return scry.Debt
function M.count(map_, report, root)
  local mapmod = require("scry.map")
  local prov = require("scry.provenance")
  local counts = require("scry.feature").tally(map_, report, root)
  local d = {
    claims = #map_.claims,
    backed = 0,
    missing = 0,
    violated = 0,
    unchecked = 0,
    untouched = 0,
    features = #map_.features,
    done = counts.done,
    unread = counts.unread,
    building = counts.partial,
    broken = counts.broken,
    todo = counts.absent + counts.unevidenced,
    unknown = counts.unknown,
    unclaimed = 0,
    files = 0,
    reach = "off",
  }
  -- Divergence needs the filesystem, so it is best-effort: a repo without
  -- ripgrep, or a root that has gone away, must not take the whole header
  -- down with it.
  if root then
    local ok, div, total = pcall(function()
      return require("scry.divergence").unclaimed(root, map_, require("scry.project").resolve(root))
    end)
    if ok then
      d.unclaimed = #div
      -- WITH ITS DENOMINATOR. "46 unclaimed files" is a number without a
      -- scale — it reads as alarming at 46 of 50 and as nearly done at 46 of
      -- 4000, and the header gave no way to tell which.
      d.files = total
    end
    -- The count is computed as though reach does not exist until it has
    -- run. Saying so is the difference between a number and a claim: a
    -- file a feature REACHES is described by that feature, and until the
    -- closure is in, this number is an upper bound rather than an answer.
    d.reach = require("scry.reach").progress.state
  end

  for _, claim in ipairs(map_.claims) do
    if not (root and prov.owned(root, claim)) then
      d.untouched = d.untouched + 1
    end
    local v = report and report.verdicts[mapmod.claim_id(claim)]
    local status = v and v.status
    if status == "backed" or status == "clean" then
      d.backed = d.backed + 1
    elseif status == "missing" then
      d.missing = d.missing + 1
    elseif status == "violated" then
      d.violated = d.violated + 1
    else
      -- unchecked, error, an unknown status, or no verdict at all
      d.unchecked = d.unchecked + 1
    end
  end
  return d
end

--- Header for the glass.
---
--- Features lead, because the reader's question is what the product does —
--- not how many subfunctions resolved. Claim-level numbers follow on a
--- second line: they are the evidence behind the first, and reading them
--- first is the altitude mistake the whole map exists to avoid.
---@param d scry.Debt
---@param at integer? report timestamp
---@return string
function M.header(d, at)
  local line1, line2 = M.parts(d, at)
  local function join(parts)
    local out = {}
    for _, seg in ipairs(parts) do
      out[#out + 1] = seg[1]
    end
    return table.concat(out)
  end
  return join(line1) .. "\n      " .. join(line2)
end

--- The header's words, each with the group that colors it.
---
--- ONE LIST, so the plain string and the winbar can never come to say
--- different things — and so color can mean something. The bar used to be a
--- single band of Title, which in a normal scheme is the loudest color it
--- has: eight columns of yellow saying "scry", "features", "checked", none
--- of which is news. The counts ARE states, and they are the only thing on
--- the line worth a color, so they get the same groups the state column
--- uses and everything around them recedes.
---@param d scry.Debt
---@param at integer?
---@return table[] line1 {text, group} pairs
---@return table[] line2
function M.parts(d, at)
  local age = at and (os.time() - at) or nil
  local when = age == nil and "unchecked" or (age < 5 and "just checked" or ("checked " .. age .. "s ago"))

  local line1 = {
    { "scry", "ScryHeaderDim" },
    { " · ", "ScryHeaderDim" },
    -- A map with one feature in it read `1 features`. Small, and it is the
    -- first line anyone ever sees.
    { ("%d feature%s"):format(d.features, d.features == 1 and "" or "s"), "ScryHeader" },
  }
  local function add(n, word, group)
    if n > 0 then
      line1[#line1 + 1] = { " · ", "ScryHeaderDim" }
      line1[#line1 + 1] = { ("%d %s"):format(n, word), group }
    end
  end
  -- ONE STATE FOR EVERY FEATURE IS ONE FACT, not a repeated one. `14
  -- features · 14 unread` says the same number twice; `14 features, all
  -- unread` says it once and reads as the sentence it is. The rows below
  -- follow this rule too — see glass.foldtext.
  local states = { { d.done, "done", "ScryDone" }, { d.unread, "unread", "ScryUnread" },
    { d.building, "building", "ScryBuilding" }, { d.broken, "broken", "ScryBroken" },
    { d.todo, "to do", "ScryTodo" }, { d.unknown, "unknown", "ScryUnchecked" } }
  local only, folded = nil, false
  for _, st in ipairs(states) do
    if st[1] > 0 then
      only = only == nil and st or false
    end
  end
  if only and d.features > 0 and only[1] == d.features then
    line1[#line1 + 1] = { ", all " .. only[2], only[3] }
    folded = true
  end

  if not folded then
    add(d.done, "done", "ScryDone")
    -- Immediately after done, and before anything else: this is the number
    -- that keeps "N done" from being read as "N finished".
    add(d.unread, "unread", "ScryUnread")
    add(d.building, "building", "ScryBuilding")
    add(d.broken, "broken", "ScryBroken")
    add(d.todo, "to do", "ScryTodo")
    add(d.unknown, "unknown", "ScryUnchecked")
  end
  -- QUALIFIED, because until reach has run this is computed as though reach
  -- does not exist — a file a feature REACHES is described by that feature,
  -- so the number is an upper bound rather than an answer. Saying which it
  -- is costs four words and is the difference between a count and a claim.
  -- The number, what it is still waiting on, and the key that acts on it.
  -- A count with nothing to do about it is a complaint; the gesture belongs
  -- beside it rather than in a command someone has to have read about.
  local drafting = pcall(require, "scry.recover") and require("scry.recover").passing()
  add(
    d.unclaimed,
    ((d.files or 0) > 0 and ("of %d files undescribed"):format(d.files) or "unclaimed files")
      .. ((d.reach == "running" and " (reach pending)") or (d.reach == "unavailable" and " (no reach)") or "")
      .. (drafting and " · + to stop" or " · + to draft"),
    "ScryTodo"
  )
  line1[#line1 + 1] = { "   " .. when .. " (files on disk)", "ScryHeaderDim" }

  -- The unchecked column is shown whenever it is non-zero, between violated
  -- and unratified: nothing an engine declined to answer may be omitted from
  -- the one line the reader actually glances at.
  local unchecked = d.unchecked > 0 and (" · %d unchecked"):format(d.unchecked) or ""
  local line2 = {
    {
      ("%d claims · %d backed · %d missing · %d violated%s · %d untouched"):format(
        d.claims,
        d.backed,
        d.missing,
        d.violated,
        unchecked,
        d.untouched
      ),
      "ScryHeaderDim",
    },
  }
  return line1, line2
end

--- The header, formatted for a window bar.
---
--- The glass header used to be virtual lines above line 1, which Neovim
--- never draws: there is no room above the first line of a buffer, so the
--- header was invisible on exactly the map everyone sees first. A winbar has
--- no such problem, and gains something the virtual lines never had — it
--- stays put while you scroll, so the counts are readable from anywhere in a
--- long map rather than only from the top.
---
--- One line instead of two, FITTED rather than truncated.
---
--- `%<` was tried both ways and neither works here. In the middle, Vim keeps
--- the tail and eats the words before it: a real window rendered
--- `(files on disk)<issing · 0 violated`, the counts sliced in half. At the
--- end, the winbar renders EMPTY — the option was set and the function
--- returned a full string, and the bar was blank.
---
--- So the segments are joined only if they fit. Features first, because that
--- is what a reader scans, and the claim-level evidence is what a narrow
--- window gives up. The ellipsis says it was cut, since cut off must not read
--- as absent — the distinction the unchecked column exists for.
---@param d scry.Debt
---@param at integer? report timestamp
---@param width integer? columns available; unlimited when nil
---@return string
function M.winbar(d, at, width)
  local line1, line2 = M.parts(d, at)
  local function esc(t)
    return (t:gsub("%%", "%%%%"))
  end
  local function render(segs)
    local out = {}
    for _, seg in ipairs(segs) do
      out[#out + 1] = "%#" .. seg[2] .. "#" .. esc(seg[1])
    end
    return table.concat(out) .. "%*"
  end
  local function measure(segs)
    local n = 0
    for _, seg in ipairs(segs) do
      n = n + vim.fn.strdisplaywidth(seg[1])
    end
    return n
  end

  local full = vim.list_extend({ { "  ·  ", "ScryHeaderDim" } }, line2)
  full = vim.list_extend(vim.list_slice(line1), full)
  if not (width and width > 2) or measure(full) <= width then
    return render(full)
  end
  -- The claim counts are the evidence beneath the feature counts, so they
  -- are what a narrow window gives up first.
  if measure(line1) <= width then
    return render(vim.list_extend(vim.list_slice(line1), { { " …", "ScryHeaderDim" } }))
  end
  -- Narrower than the counts themselves: cut inside the segments, keeping
  -- each surviving word its own color rather than flattening the line.
  local kept, used = {}, 0
  for _, seg in ipairs(line1) do
    local w = vim.fn.strdisplaywidth(seg[1])
    if used + w <= width - 1 then
      kept[#kept + 1] = seg
      used = used + w
    else
      kept[#kept + 1] = { vim.fn.strcharpart(seg[1], 0, width - 1 - used), seg[2] }
      break
    end
  end
  kept[#kept + 1] = { "…", "ScryHeaderDim" }
  return render(kept)
end

--- Compact string for the user's own statusline. Plain function, no
--- statusline framework: `scry 9f ✓6 ◐2 ✗1 ∅3` — features first. The `–` count appears only
--- when something went unchecked, for the same reason the header carries it:
--- `✗0` must not be readable as "everything is accounted for". Unread
--- features fold into the `◐` count rather than the `✓` one: in six
--- characters the only thing worth preserving is that they are not finished.
---@return string
function M.statusline()
  local glass = require("scry.glass")
  local d = glass.current_debt()
  if not d then
    return ""
  end
  local unchecked = d.unchecked > 0 and (" –%d"):format(d.unchecked) or ""
  return ("scry %df ✓%d ◐%d ✗%d%s ∅%d"):format(
    d.features,
    d.done,
    d.building + d.unread,
    d.broken + d.todo,
    unchecked,
    d.untouched
  )
end

return M
