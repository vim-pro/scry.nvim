local M = {}

function M.check()
  local health = vim.health
  local scry = require("scry")
  local config = scry.config

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

  -- Where the map and the holdout live.
  local root = vim.fn.getcwd()
  local map_path = root .. "/" .. config.map_path
  if vim.fn.filereadable(map_path) == 1 then
    local m = require("scry.map").load(map_path)
    health.ok(("map: %s (%d concerns, %d claims)"):format(config.map_path, #m.concerns, #m.claims))
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

  -- Optional neighbours.
  if pcall(require, "conjurer.quickfix") then
    health.ok("conjurer.nvim found (:ScryCascade can hand off casting)")
  else
    health.info("conjurer.nvim not found — :ScryCascade seeds the list, you cast it")
  end
  if pcall(require, "quickfix-pro") then
    health.ok("quickfix.pro found (seeded entries get decorated)")
  else
    health.info("quickfix.pro not found (optional)")
  end
end

return M
