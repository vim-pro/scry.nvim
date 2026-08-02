-- The import graph: what a file pulls in, resolved to files in this repo.
--
-- This replaced a name resolver, and the assertions that matter most are the
-- ones the name resolver could not have passed. A grammar-based engine binds
-- names, so it can only answer for languages someone wrote a grammar for.
-- Following a file needs the specifier and the filesystem, so it answers for
-- astro, for svelte, for Lua — for anything that borrowed the syntax.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local imports = require("scry.imports")

-- 1) THE FOUR SHAPES. Between them: ESM, side-effect imports, dynamic
-- import, CommonJS, and Lua's require with or without parentheses.
local specs = imports.specifiers(table.concat({
  "import Layout from '../layouts/Layout.astro';",
  'import { a, b } from "./lib/db.js";',
  "import './styles/global.css';",
  "const m = await import('./lazy.ts');",
  "const fs = require('node:fs');",
  'local map = require("scry.map")',
  "export { x } from './re-export.js';",
}, "\n"))
local set = {}
for _, s in ipairs(specs) do
  set[s] = true
end
H.ok(set["../layouts/Layout.astro"], "from '…' — the ESM shape")
H.ok(set["./lib/db.js"], "double quotes too")
H.ok(set["./styles/global.css"], "a side-effect import is an import")
H.ok(set["./lazy.ts"], "dynamic import()")
H.ok(set["node:fs"], "require() — collected here, rejected later")
H.ok(set["scry.map"], "Lua's require, without parentheses")
H.ok(set["./re-export.js"], "a re-export pulls the file in just the same")

-- A COMMENTED LINE IS NOT AN IMPORT. This module's own doc comment contains
-- the words `require("scry.map")`, and without this it reported itself as
-- importing scry.map — which resolves, so nothing downstream dropped it. A
-- file excused from the unclaimed list by a sentence in a comment is the
-- over-claim scry exists to prevent.
local commented = imports.specifiers(table.concat({
  "-- see require('scry.map') for the parser",
  "--- `require(\"scry.runs\")` records a run",
  "// import { a } from './dead.js';",
  "# from 'python.comment' import thing",
  " * import '../block/comment.js';",
  "import { real } from './real.js';",
}, "\n"))
H.eq(#commented, 1, "one real import among five commented ones, got: " .. table.concat(commented, ", "))
H.eq(commented[1], "./real.js", "and it is the uncommented one")

-- 2) NORMALIZE, including the case that must refuse. A specifier that climbs
-- out of the repository names something this project does not contain, and
-- returning a path outside the root would put it in the reach of a feature.
H.eq(imports.normalize("src/pages/../lib/db.js"), "src/lib/db.js", "`..` collapses")
H.eq(imports.normalize("src/./a.js"), "src/a.js", "`.` disappears")
H.eq(imports.normalize("../outside.js"), nil, "climbing out of the repo is not a path")

-- 3) RESOLUTION, against a real tree — the probing order only means
-- something on a filesystem.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/src/pages", "p")
vim.fn.mkdir(root .. "/src/lib", "p")
vim.fn.mkdir(root .. "/src/comp/widget", "p")
vim.fn.mkdir(root .. "/lua/scry", "p")
vim.fn.writefile({ "export function all() {}" }, root .. "/src/lib/db.ts")
vim.fn.writefile({ "export const p = 1" }, root .. "/src/lib/site.js")
vim.fn.writefile({ "export default {}" }, root .. "/src/comp/widget/index.astro")
vim.fn.writefile({ "local M = {} return M" }, root .. "/lua/scry/map.lua")

-- THE `.js` THAT MEANS `.ts`. Under ESM you import `./db.js` and the file on
-- disk is `db.ts`. This is the exact chain a stack-graphs grammar failed to
-- follow on a real project — the failure that started all of this — and here
-- it is a probe.
H.eq(imports.resolve(root, "src/pages/x.astro", "../lib/db.js"), "src/lib/db.ts", "`.js` resolves to the `.ts` on disk")
H.eq(imports.resolve(root, "src/pages/x.astro", "../lib/site.js"), "src/lib/site.js", "and to `.js` when that is what is there")
H.eq(imports.resolve(root, "src/pages/x.astro", "../lib/db"), "src/lib/db.ts", "extensionless picks up the extension")
H.eq(imports.resolve(root, "src/pages/x.astro", "../comp/widget"), "src/comp/widget/index.astro", "a directory resolves to its index")
H.eq(imports.resolve(root, "src/pages/x.astro", "../lib/missing.js"), nil, "and nothing invents a file")

-- A BARE SPECIFIER IS NOT FIRST-PARTY. It resolves into node_modules or a
-- standard library, which is not code this project answers for and not
-- anywhere a footprint should wander.
H.eq(imports.resolve(root, "src/pages/x.astro", "react"), nil, "a package is not reach")
H.eq(imports.resolve(root, "src/pages/x.astro", "node:fs"), nil, "nor is the standard library")

-- A LUA MODULE PATH is a file path with the dots swapped, which is how scry
-- becomes able to describe itself.
H.eq(imports.resolve(root, "lua/scry/reach.lua", "scry.map"), "lua/scry/map.lua", "require('scry.map')")
H.eq(imports.resolve(root, "lua/scry/reach.lua", "plenary.async"), nil, "a module this repo does not contain is not reach")

-- 4) ONE HOP OUT OF A FILE TYPE NOTHING ELSE READS. checklists.org's map is
-- nine `route` members and every one is .astro; no stack-graphs grammar and
-- no installed language server resolves that file type, so reach from a
-- route computed nothing — on the project the design was built for.
vim.fn.writefile({
  "---",
  "import Layout from '../comp/widget';",
  "import { all } from '../lib/db.js';",
  "import '../lib/site.js';",
  "---",
  "<Layout>{all()}</Layout>",
}, root .. "/src/pages/index.astro")
local hop, readable = imports.of(root, "src/pages/index.astro")
H.eq(readable, true, "an astro file is readable, which is all this needs")
H.eq(#hop, 3, "three first-party imports out of a route: " .. table.concat(hop, ", "))
H.ok(vim.tbl_contains(hop, "src/lib/db.ts"), "including the .js-means-.ts one")
H.eq(vim.tbl_contains(hop, "src/pages/index.astro"), false, "a file is not its own one-hop import")

local _, missing = imports.of(root, "src/pages/nope.astro")
H.eq(missing, false, "a file that cannot be read says so rather than answering zero")

-- 5) CLOSURE is transitive and includes its seeds — a file is part of its own
-- footprint. `deep.ts` is reachable ONLY through db.ts, so it is the file
-- that tells a transitive walk from a one-hop one. Written first with a
-- second hop the seed also imported directly, which proved nothing.
vim.fn.writefile({ "import { d } from './deep.js';", "export function all() { return d }" }, root .. "/src/lib/db.ts")
vim.fn.writefile({ "export const d = 1" }, root .. "/src/lib/deep.ts")
vim.fn.writefile({ "export const orphan = 1" }, root .. "/src/lib/orphan.ts")
local all = imports.closure(root, { "src/pages/index.astro" })
H.ok(vim.tbl_contains(all, "src/pages/index.astro"), "the seed is in its own footprint")
H.ok(vim.tbl_contains(all, "src/lib/db.ts"), "one hop")
H.ok(vim.tbl_contains(all, "src/lib/deep.ts"), "two hops, reachable only through db.ts")
H.eq(vim.tbl_contains(all, "src/lib/orphan.ts"), false, "and what nothing imports stays out")

-- Unbounded by default, which is a deliberate difference from the resolver
-- this replaced. Depth was capped there because every hop was a subprocess;
-- a hop is a file read now, so the honest stopping condition is "nothing
-- new" rather than "three".
local shallow = imports.closure(root, { "src/pages/index.astro" }, { depth = 1 })
H.eq(vim.tbl_contains(shallow, "src/lib/deep.ts"), false, "depth 1 stops before the second hop")
H.ok(vim.tbl_contains(shallow, "src/lib/db.ts"), "but takes the first")

-- A CYCLE TERMINATES. Two files importing each other is ordinary, and a walk
-- that revisits is a walk that hangs.
vim.fn.writefile({ "import './b.js'" }, root .. "/src/lib/a.js")
vim.fn.writefile({ "import './a.js'" }, root .. "/src/lib/b.js")
local cyc = imports.closure(root, { "src/lib/a.js" })
H.eq(#cyc, 2, "a cycle settles at both files rather than spinning")

H.done("imports_spec PASS")
