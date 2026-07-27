-- The cascade: an absent claim becomes work. scry does NOT conjure — it
-- seeds the quickfix list with the target site and hands the intent to
-- conjurer's aggregate driver, which owns casting and per-site review.
--
-- The holdout is the point. Everything the conjurer will ever see is built
-- from exactly three inputs — the concern name, the claim's own target, and
-- an intent the user typed. Concern PROSE is deliberately excluded: prose
-- can restate a prohibition in words no scrubber could catch, so the channel
-- is closed rather than filtered. assert_clean is the tripwire on top.
--
-- Settlement: conjurer has no completion event and ripgrep reads DISK, so
-- the honest trigger for re-checking is "the file was saved". Nothing is
-- real until written — which is what the glass header already says.
local M = {}

-- The open cascade: { concern, target, files[], augroup }
local active = nil

M._active = function()
  return active
end

--- Build everything that leaves scry for a contains-claim. Pure: no side
--- effects, no buffer or list writes — so a spec can walk every outgoing
--- string and prove no never-pattern text rides along.
---@param claim scry.Claim
---@param intent string
---@return { items: table[], intent: string, file: string, symbol: string }
function M.build(claim, intent)
  if claim.kind ~= "contains" then
    error("[scry] cascade supports contains claims (got " .. claim.kind .. ")", 0)
  end
  local file, symbol = claim.target:match("^(.-):([%w_.]+)$")
  if not file then
    error("[scry] malformed contains target (want path:symbol)", 0)
  end
  -- The entry text becomes request.note in conjurer, so it says only what
  -- the claim says.
  local text = ("scry: %s should define %s"):format(claim.concern, symbol)
  return {
    file = file,
    symbol = symbol,
    intent = intent,
    items = {
      {
        filename = file,
        lnum = 1,
        col = 1,
        text = text,
        user_data = { scry = { concern = claim.concern, target = claim.target } },
      },
    },
  }
end

-- Re-check this concern's never-claims plus the seeding claim, against disk.
local function recheck(reason)
  if not active then
    return
  end
  local glass = require("scry.glass")
  local config = require("scry").config
  local root = active.root
  local mapmod = require("scry.map")
  local holdout = require("scry.holdout")

  local hold = holdout.load(root, config)
  local nevers = {}
  for _, c in ipairs(hold.claims) do
    if c.kind == "never" and c.concern == active.concern then
      nevers[#nevers + 1] = c
    end
  end
  if #nevers > 0 then
    local m = mapmod.load(root .. "/" .. config.map_path)
    local concern = mapmod.concern(m, active.concern)
    require("scry.check").run(hold, {
      root = root,
      claims = nevers,
      resolver = require("scry.resolver").get(config.resolver ~= "" and config.resolver or nil),
    }, function(report)
      for _, c in ipairs(nevers) do
        local v = report.verdicts[mapmod.claim_id(c)]
        if v and v.status == "violated" then
          local e = v.evidence and v.evidence[1]
          vim.notify(
            ("[scry] never-claim VIOLATED (%s): %s%s"):format(
              reason,
              c.target,
              e and (" — " .. e.path .. ":" .. e.lnum) or ""
            ),
            vim.log.levels.WARN
          )
        end
      end
      -- the concern's globs matter for the never check; if the map has none
      -- the resolver searched the whole root, which is still honest
      local _ = concern
      glass.check()
    end)
  else
    glass.check()
  end
end

--- Seed the list from the claim under the cursor and (optionally) hand off
--- to conjurer. Registers a save-triggered re-check for the seeded file.
function M.start()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_get_current_buf() == state.buf) then
    vim.notify("[scry] :ScryCascade works in the glass buffer", vim.log.levels.WARN)
    return
  end
  local mapmod = require("scry.map")
  local m = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false))
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local claim
  for _, c in ipairs(m.claims) do
    if c.lnum == lnum then
      claim = c
      break
    end
  end
  if not claim then
    vim.notify("[scry] no claim on this line", vim.log.levels.WARN)
    return
  end
  if claim.kind ~= "contains" then
    vim.notify("[scry] cascade supports contains claims (this is a " .. claim.kind .. " claim)", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Conjure: ", default = "define " .. claim.target:match(":([%w_.]+)$") }, function(intent)
    if not intent or intent == "" then
      return
    end
    M.seed(state.root, claim, intent, true)
  end)
end

--- The seeding half, separated so specs can drive it without vim.ui.
---@param root string
---@param claim scry.Claim
---@param intent string
---@param handoff boolean Call conjurer's :ConjureAll after seeding?
function M.seed(root, claim, intent, handoff)
  local config = require("scry").config
  local holdout = require("scry.holdout")
  local built = M.build(claim, intent)

  -- The tripwire: nothing that leaves here may contain never-pattern text.
  local hold = holdout.load(root, config)
  local nevers = {}
  for _, c in ipairs(hold.claims) do
    if c.kind == "never" then
      nevers[#nevers + 1] = c.target
    end
  end
  local outgoing = { built.intent, built.items[1].text }
  holdout.assert_clean(outgoing, nevers)

  vim.fn.setqflist({}, " ", {
    title = "scry: " .. claim.concern,
    items = built.items,
  })

  if active and active.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, active.augroup)
  end
  local group = vim.api.nvim_create_augroup("scry.cascade", { clear = true })
  active = {
    root = root,
    concern = claim.concern,
    target = claim.target,
    files = { built.file },
    augroup = group,
  }
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = root .. "/" .. built.file,
    callback = function()
      recheck("on save")
    end,
  })

  if handoff then
    local ok, conjurer_qf = pcall(require, "conjurer.quickfix")
    if ok then
      conjurer_qf.all(built.intent)
    else
      vim.notify("[scry] seeded the quickfix list (conjurer not installed — cast it yourself)")
    end
  end
  return built
end

--- Clear the cascade's save watcher.
function M.stop()
  if active and active.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, active.augroup)
  end
  active = nil
end

M._recheck = recheck

return M
