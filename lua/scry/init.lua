-- scry.nvim — the surface you write software from: one buffer describing
-- the product, checked against the real code. Conjuring is how code arrives
-- (conjurer.nvim); ownership is inferred from the work, never signed.
-- Verdicts are accounting, not correctness — see :h scry-honesty.
local M = {}

---@class scry.Config
---@field map_path string In-repo map file, relative to the project root.
---@field holdout_path string|"" Never-claims location; "" = stdpath state (outside the repo).
---@field resolver string|"" Resolver name; "" = the ts_rg default.
---@field test { cmd: string[] } How to run ONE spec: cmd with the spec path
---  appended. Exit 0 is passing. Empty = exercises claims stay unrun.
---@field sources string[] Which files count as claimable, for divergence
---  (|scry-divergence|). Empty = everything ripgrep lists.

---@type scry.Config
M.config = {
  -- The belief map, versioned with the code it describes.
  map_path = ".scry/map.scry",
  -- Where never-claims live. Empty = outside the repo
  -- (stdpath("state")/scry/holdout/...), so a repo-reading conjurer never
  -- sees them. Setting an in-repo path weakens that guarantee — checkhealth
  -- will say so.
  holdout_path = "",
  -- Claim-checking engine. Empty = treesitter + ripgrep (lua-first).
  resolver = "",
  -- How to run one spec, for `exercises` claims: the spec's path is appended
  -- and exit 0 means passing. Nothing here runs on :Scry — only on :ScryExercise.
  -- Left empty, exercises claims render "– unrun", which is honest: scry
  -- would rather say it doesn't know than guess a project's test command.
  test = { cmd = {} },
  -- Which files divergence considers claimable. Empty means everything
  -- ripgrep lists, which respects .gitignore — scry does not presume to know
  -- which of your files are product. Narrow it when the noise outweighs the
  -- signal; having to narrow it is itself information about the repo.
  sources = {},
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

vim.api.nvim_create_user_command("ScryUnclaimed", function(a)
  require("scry.divergence").to_quickfix({ all = a.bang })
end, {
  bang = true,
  desc = "Where the code nothing describes is (! for every file, however many)",
})

vim.api.nvim_create_user_command("ScryDraft", function()
  require("scry.recover").start()
end, { desc = "Draft features for the files no feature claims (the scrying pass)" })

-- A pass runs until the project is described, which on a large one is a
-- great many requests. Ending it is a command rather than a prompt because
-- the answer is almost always "keep going" and being asked every twelve
-- files would be its own kind of tax.
-- How the map READS, as against whether it is true. Every other check asks
-- the code a question; this one asks nothing of the code at all.
-- The verb. Vim aims an operator at a precisely addressed noun; this aims
-- one at a capability, and the address is every file the capability is made
-- of. You do not open the files.
vim.api.nvim_create_user_command("ScryConjure", function()
  require("scry.compose").start()
end, { desc = "Cast an intent across the whole feature under the cursor" })

-- Drafting gathers re-opened blocks as each batch lands; this is for a map
-- written before it did.
vim.api.nvim_create_user_command("ScryTidy", function()
  require("scry.recover").tidy()
end, { desc = "Gather every block of a re-opened feature into one" })

vim.api.nvim_create_user_command("ScryLint", function()
  require("scry.lint").to_quickfix()
end, { desc = "Flag feature names that are hard to read (never a verdict — the wording is yours)" })

vim.api.nvim_create_user_command("ScryDraftStop", function()
  require("scry.recover").stop()
end, { desc = "End the drafting pass after the batch in flight" })

vim.api.nvim_create_user_command("ScryExercise", function(a)
  require("scry.run").start({ feature = a.args ~= "" and a.args or nil })
end, { nargs = "?", desc = "Run the specs behind this map's exercises claims, then re-check" })

return M
