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
    health.error("ripgrep not found — calls and never claims cannot be checked", {
      "brew install ripgrep",
    })
  end
  local ok_parser = pcall(vim.treesitter.language.inspect, "lua")
  if ok_parser then
    health.ok("lua treesitter parser available (definitions)")
  else
    health.warn("no lua treesitter parser — contains claims will render as unchecked")
  end

  -- Reach, and what kind of answer it can give here. An engine that is not
  -- provisioned is not an error: reach falls back to a name match and says
  -- so every time. Reporting it as broken would be the wrong shape — the
  -- degraded answer is a real answer, just a weaker one.
  local reach = require("scry.reach")
  if not reach.sg() then
    -- Not an error either. Every verdict scry gives works without it; only
    -- :ScryReach and the divergence shrink go away, so this is a missing
    -- feature rather than a broken install.
    health.info("reach: stackgraphs.nvim not installed — :ScryReach and the divergence shrink are unavailable")
    health.info("  https://github.com/vim-pro/stackgraphs.nvim")
  else
    -- Which languages actually resolve, and by what. This is the fact that
    -- decides every reach answer, so it leads — the per-backend detail is
    -- only useful once you know there is nothing.
    local resolvable = require("stackgraphs").languages()
    local names = {}
    for lang, backend in pairs(resolvable) do
      names[#names + 1] = ("%s (%s)"):format(lang, backend)
    end
    table.sort(names)
    if #names > 0 then
      health.ok("reach: resolves " .. table.concat(names, ", "))
    else
      health.info("reach: nothing resolves here — :ScryReach answers by name match, labeled `text only`")
      health.info("  install a language server for your language, or a stack-graphs engine")
      health.info("  :h stackgraphs-backends")
    end
    for _, line in ipairs(reach.status()) do
      health.info("reach: " .. line)
    end
  end

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

  -- Optional neighbours.
  -- Both directions of the arrow go through conjurer: :Conjure casts a claim
  -- into code, and :ScryDraft casts the code back into claims.
  if pcall(require, "conjurer.quickfix") and pcall(require, "conjurer.operator") then
    health.ok("conjurer.nvim found (:Conjure casts claims, :ScryDraft drafts them)")
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
