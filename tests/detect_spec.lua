-- Detecting the tests a map is missing: a test file's direct imports,
-- intersected with feature footprints, are exercises claims waiting to be
-- written. Same graph reach follows, read the other way.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local detect = require("scry.detect")
local mapmod = require("scry.map")

-- 1) What counts as a test, by name.
for _, yes in ipairs({
  "shared/recurrence.test.ts",
  "server/src/__tests__/series.test.ts",
  "tests/record_spec.lua",
  "web/attendance.spec.tsx",
  "server/test/roster_test.go",
  "tests/test_roster.py",
}) do
  H.ok(detect.looks_like_test(yes), yes .. " is a test")
end
-- The FILENAME decides, never the directory: __tests__/helpers.ts got
-- claimed as a spec once, and a runner pointed at a helper refuses it.
for _, no in ipairs({
  "shared/recurrence.ts",
  "server/src/routes/series.ts",
  "web/src/pages/Testimonials.tsx",
  "server/src/__tests__/helpers.ts",
  "tests/fixtures.lua",
}) do
  H.ok(not detect.looks_like_test(no), no .. " is not")
end

-- 2) A real little repo: product files, one test importing them, one test
-- for a feature that does not claim it, one unrelated test.
local root = vim.fn.tempname()
for dir in ("shared server/src/domain server/src/__tests__ web"):gmatch("%S+") do
  vim.fn.mkdir(root .. "/" .. dir, "p")
end
local function write(path, lines)
  vim.fn.writefile(lines, root .. "/" .. path)
end
write("shared/recurrence.ts", { "export function expand() {}" })
write("shared/recurrence.test.ts", { 'import { expand } from "./recurrence"', "test0" })
write("server/src/domain/series.ts", { 'import { expand } from "../../../shared/recurrence"' })
write("server/src/__tests__/series.test.ts", { 'import { series } from "../domain/series"' })
write("web/unrelated.test.ts", { 'import { x } from "./nothing-the-map-claims"' })

local MAP = {
  "feature say a repeating schedule once",
  "  module shared/recurrence.ts",
  "  module shared/recurrence.test.ts",
  "",
  "feature practices keep coming",
  "  module server/src/domain/series.ts",
  "",
}
local m = mapmod.parse(MAP)
local files = {
  "shared/recurrence.ts",
  "shared/recurrence.test.ts",
  "server/src/domain/series.ts",
  "server/src/__tests__/series.test.ts",
  "web/unrelated.test.ts",
}
local found = detect.candidates(root, m, nil, files)
table.sort(found, function(a, b)
  return a.spec < b.spec
end)
H.eq(#found, 2, "two tests exercise mapped features; the unrelated one is left alone")
H.eq(found[1].spec, "server/src/__tests__/series.test.ts", "found through a relative import")
H.eq(found[1].feature, "practices keep coming", "credited to the feature whose footprint it imports")
H.eq(found[1].promote, nil, "not claimed before, so nothing to promote")
H.eq(found[2].spec, "shared/recurrence.test.ts", "the second test found")
H.eq(found[2].feature, "say a repeating schedule once", "in its own feature")
H.eq(found[2].promote, 3, "already a module row there — a promotion, with its line")

-- 3) Apply writes exercises sections and promotes module rows, as one edit.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, MAP)
H.eq(detect.apply(buf, m, found), 2, "both written")
local after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local text = table.concat(after, "\n")
H.ok(
  text:find("  module shared/recurrence.ts\n  exercises\n    shared/recurrence.test.ts", 1, true) ~= nil,
  "promoted: the exercises section replaces the module row"
)
local _, module_rows = text:gsub("module shared/recurrence%.test%.ts", "")
H.eq(module_rows, 0, "the promoted module row is gone")
H.ok(
  text:find("  module server/src/domain/series.ts\n  exercises\n    server/src/__tests__/series.test.ts", 1, true) ~= nil,
  "the addition lands at its feature's block end"
)

-- The result reparses: two features, each with one exercises claim.
local reparsed = mapmod.parse(after)
for _, f in ipairs(reparsed.features) do
  local ex = 0
  for _, c in ipairs(f.claims) do
    if c.kind == "exercises" then
      ex = ex + 1
    end
  end
  H.eq(ex, 1, f.name .. " has its exercises claim")
end

-- 4) Already-claimed tests are not suggested again.
local again = detect.candidates(root, reparsed, nil, files)
H.eq(#again, 0, "a second pass finds nothing — the detection converges")

H.done("detect_spec PASS")
