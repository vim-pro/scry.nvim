-- Project-local config: which keys the repo gets to set, and which it does
-- not. The refusals are the load-bearing part of this file.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local project = require("scry.project")

local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/.scry", "p")
local function config_json(tbl)
  vim.fn.writefile({ vim.json.encode(tbl) }, work .. "/.scry/config.json")
end

require("scry").setup({
  sources = { "from-setup/**" },
  test = { cmd = { "setup-runner" } },
  resolver = "",
  holdout_path = "",
})

-- 1) no file at all: your setup() is the whole story
H.eq(next(project.load(work)), nil, "a repo with no config file contributes nothing")
local base = project.resolve(work)
H.eq(base.sources[1], "from-setup/**", "so setup() stands")
H.eq(base.test.cmd[1], "setup-runner", "all of it")

-- 2) THE THREE KEYS THE REPO OWNS. `sources` and `test` are facts about the
-- repo, not about you — the right sources for this project is not the right
-- one for the next, and how to run these specs has nothing to do with how to
-- run another project's.
config_json({
  sources = { "lua/**/*.lua" },
  test = { cmd = { "./scripts/test" } },
  resolver = "ts_rg",
  map_path = "docs/product.scry",
})
local resolved = project.resolve(work)
H.eq(resolved.sources[1], "lua/**/*.lua", "the project's sources win")
H.eq(resolved.test.cmd[1], "./scripts/test", "and its test command")
H.eq(resolved.resolver, "ts_rg", "and its resolver")
-- map_path is honored while holdout_path is refused, and the asymmetry is
-- the point: the map is already committed, so moving it changes nothing
-- about who can read it. The holdout's whole value is being unreadable.
H.eq(resolved.map_path, "docs/product.scry", "and where its map lives")
H.eq(resolved.holdout_path, "", "the holdout's location above all")

-- 3) THE REFUSALS. holdout_path is why the holdout works: prohibitions live
-- outside the repo so a repo-reading generator cannot find them. A committed
-- file that could relocate them back INTO the repo is precisely how you would
-- defeat that — hand someone a project that quietly publishes its own rules.
config_json({ holdout_path = "PUBLISHED.scry", sources = { "lua/**" } })
local honored, warning = project.load(work)
H.eq(honored.holdout_path, nil, "the repo may NOT relocate the holdout")
H.eq(honored.sources[1], "lua/**", "the rest of the same file is still honored")
H.ok(warning ~= nil, "and the refusal is announced, not silent")
H.ok(warning:find("holdout_path", 1, true) ~= nil, "naming what was ignored: " .. warning)

-- 4) unknown keys are ignored quietly. A newer scry writing a key this one
-- does not know must not break the older one.
config_json({ sources = { "a/**" }, some_future_key = 42 })
local h4, w4 = project.load(work)
H.eq(h4.some_future_key, nil, "an unknown key is dropped")
H.eq(h4.sources[1], "a/**", "without disturbing the rest")
H.eq(w4, nil, "and without a warning — forward compatibility is not an error")

-- 5) a broken file must not stop you opening the glass
vim.fn.writefile({ "{ this is not json" }, work .. "/.scry/config.json")
local h5, w5 = project.load(work)
H.eq(next(h5), nil, "malformed JSON contributes nothing")
H.ok(w5 ~= nil and w5:find("not valid JSON", 1, true) ~= nil, "and says so once: " .. tostring(w5))
H.eq(project.resolve(work).sources[1], "from-setup/**", "resolve falls back to setup() rather than erroring")

-- 6) no root at all (a spec calling in without a project) returns setup()
H.eq(project.resolve(nil).sources[1], "from-setup/**", "no root means no project layer")

H.done("project_spec PASS")
