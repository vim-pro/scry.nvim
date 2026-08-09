local M = {}

function M.check()
  local health = vim.health
  local root = vim.fn.getcwd()
  -- The config IN EFFECT here, not the global one. checkhealth is where you
  -- go to find out what scry thinks, so reporting a `sources` or `map_path`
  -- that .scry/config.json has already overridden is worse than saying
  -- nothing — you would go and change the wrong setting.
  local config = require("scry.project").resolve(root)

  health.start("scry")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim 0.10+ is required")
  end

  -- The resolver's two legs.
  if vim.fn.executable("rg") == 1 then
    health.ok("ripgrep found (references and prohibitions)")
  else
    health.error("ripgrep not found — never claims cannot be checked", {
      "brew install ripgrep",
    })
  end
  -- WHICH RUNG A `def` GETS, per language. A `def` is answerable everywhere
  -- now; the question health can settle is whether it will be GROUNDED in a
  -- definition node or read off a line that looks like one.
  -- The same one thing the glass offers, so health and the buffer can never
  -- disagree about what would help most.
  local advice = require("scry.advice")
  local missing, fix = advice.crucial()
  if missing then
    health.error(missing, { fix })
  end

  local defs = require("scry.defs")
  local parsed, missing = defs.available()
  if #parsed > 0 then
    health.ok(("definitions parsed in: %s"):format(table.concat(parsed, ", ")))
  end
  if #missing > 0 then
    health.warn(("no grammar here for: %s — those fall to the text rung"):format(table.concat(missing, ", ")))
  end
  health.info("every other language gets `✓ defined (text)`: a line that looks like a definition,")
  health.info("which cannot tell a definition from the same words inside a comment")

  local ok_parser = pcall(vim.treesitter.language.inspect, "lua")
  if ok_parser then
    health.ok("lua treesitter parser available (definitions)")
  else
    health.warn("no lua treesitter parser — contains claims will render as unchecked")
  end

  -- Reach needs nothing installed. It follows import specifiers with a file
  -- read, so there is no engine to provision and nothing to report as
  -- missing -- which is most of what this section used to say.
  local reach = require("scry.reach")
  local cached = 0
  for _ in pairs(reach.cache_load(root)) do
    cached = cached + 1
  end
  health.ok(("reach: follows imports, no engine required (%d feature(s) recorded)"):format(cached))

  -- Where the map and the holdout live.
  local map_path = root .. "/" .. config.map_path
  if vim.fn.filereadable(map_path) == 1 then
    local m = require("scry.map").load(map_path)
    health.ok(("map: %s (%d features, %d claims)"):format(config.map_path, #m.features, #m.claims))
  else
    health.info(("map: %s (not created yet — :Scry starts one)"):format(config.map_path))
  end

  local holdout = require("scry.holdout")
  local hpath = holdout.path(root, config)
  if holdout.in_repo(root, config) then
    health.warn(("holdout is INSIDE the repo (%s)"):format(vim.fn.fnamemodify(hpath, ":.")), {
      "never-claims keep their checking value, but a repo-reading generator",
      "can see them — the independence of the holdout is lost.",
      "Leave holdout_path empty to store them outside the repo.",
    })
  else
    health.ok("holdout is outside the repo: " .. hpath)
    health.info("withheld from requests: guaranteed and tested. Hidden from a")
    health.info("repo-reading generator: yes. Hidden from one told to hunt the")
    health.info("filesystem: no. Independence is against leakage, not adversaries.")
  end

  -- Dynamic evidence: only usable if scry knows how to run one spec.
  local cmd = (config.test or {}).cmd or {}
  local map_ = require("scry.map").load(root .. "/" .. config.map_path)
  local specs = #require("scry.run").specs(map_)
  if #cmd > 0 then
    health.ok(("test command: %s <spec>  (%d spec%s exercised)"):format(
      table.concat(cmd, " "),
      specs,
      specs == 1 and "" or "s"
    ))
    health.info("runs happen on :ScryExercise only — checking never executes anything")
  elseif specs > 0 then
    health.warn(("%d exercises claim%s but no test command"):format(specs, specs == 1 and "" or "s"), {
      "They render '– unrun', which is honest but never becomes evidence.",
      "Set test = { cmd = {...} } in setup(); the spec path is appended.",
    })
  else
    health.info("no exercises claims (set test.cmd to use them)")
  end

  -- Optional neighbors.
  -- Both directions of the arrow go through conjurer: :Conjure casts a claim
  -- into code, and drafting casts the code back into claims.
  if pcall(require, "conjurer.quickfix") and pcall(require, "conjurer.operator") then
    health.ok("conjurer.nvim found (:Conjure casts claims, + in the glass drafts them)")
  else
    health.error("conjurer.nvim is REQUIRED — install vim-pro/conjurer.nvim")
  end
  if pcall(require, "quickfix-pro") then
    health.ok("quickfix-pro found (seeded entries get decorated)")
  else
    health.info("quickfix-pro not found (optional)")
  end
end

return M
