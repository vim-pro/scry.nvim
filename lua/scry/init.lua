-- scry.nvim — the glass: a project rendered as one editable buffer of
-- authored beliefs, continuously checked against real code. Conjuring is
-- the arrow (conjurer.nvim); ratification is the loop; theory-debt is the
-- number. Verdicts are accounting, not correctness — see :h scry-honesty.
local M = {}

---@class scry.Config
---@field map_path string In-repo map file, relative to the project root.
---@field holdout_path string|"" Never-claims location; "" = stdpath state (outside the repo).
---@field author string|"" Ratification name; "" = git config user.name.
---@field resolver string|"" Resolver name; "" = the ts_rg default.
---@field test { cmd: string[] } How to run ONE spec: cmd with the spec path
---  appended. Exit 0 is passing. Empty = exercises claims stay unrun.

---@type scry.Config
M.config = {
  -- The belief map, versioned with the code it describes.
  map_path = ".scry/map.scry",
  -- Where never-claims live. Empty = outside the repo
  -- (stdpath("state")/scry/holdout/...), so a repo-reading conjurer never
  -- sees them. Setting an in-repo path weakens that guarantee — checkhealth
  -- will say so.
  holdout_path = "",
  -- Name written into ratification stamps. Empty = git config user.name.
  author = "",
  -- Claim-checking engine. Empty = treesitter + ripgrep (lua-first).
  resolver = "",
  -- How to run one spec, for `exercises` claims: the spec's path is appended
  -- and exit 0 means passing. Nothing here runs on :Scry — only on :ScryRun.
  -- Left empty, exercises claims render "– unrun", which is honest: scry
  -- would rather say it doesn't know than guess a project's test command.
  test = { cmd = {} },
}

--- Merge user options; define commands. Optional — zero-config works.
---@param opts scry.Config?
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

vim.api.nvim_create_user_command("Scry", function()
  require("scry.glass").open()
end, { desc = "Open the glass: the project's belief map, checked against the code" })

vim.api.nvim_create_user_command("ScryCheck", function()
  require("scry.glass").check(function()
    vim.notify("[scry] checked")
  end)
end, { desc = "Re-check every claim against the files on disk" })

vim.api.nvim_create_user_command("ScryRatify", function()
  require("scry.glass").ratify_current()
end, { desc = "Ratify the claim under the cursor (stamp it with your name)" })

vim.api.nvim_create_user_command("ScryCascade", function()
  require("scry.cascade").start()
end, { desc = "Conjure the absent claim under the cursor via the quickfix list" })

vim.api.nvim_create_user_command("ScryRun", function(a)
  require("scry.run").start({ concern = a.args ~= "" and a.args or nil })
end, { nargs = "?", desc = "Run the specs behind this map's exercises claims, then re-check" })

return M
