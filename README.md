# scry.nvim

[![CI](https://github.com/vim-pro/scry.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/vim-pro/scry.nvim/actions/workflows/ci.yml)

**Scry your software.** A map of what your project does — plain sentences,
checked against the code — that you can aim AI edits at.

**[scry.vim.pro](https://scry.vim.pro)** · `:h scry`

## Operators, one noun up

Vim's grammar is operators × text objects: `d2w`, `ci"`, `>ap` — verbs
applied to addressed nouns, repeatable with `.`, fannable with `:g`.
[conjurer.nvim](https://conjurer.vim.pro) applies it to generated edits:
`~{motion}` rewrites a region toward an intent.

**scry raises the noun** from a region in a file to a capability. Put the
cursor on `Tailor a checklist to your own situation`, press `~`, say what
you want. The change lands across `compile.ts`, `c/[slug].astro`,
`copy.astro` and `c/index.astro` — four files, one intent, without opening
any of them. `.` repeats it on the next feature;
`:g/^feature.*export/normal ~` fans it across every capability that
matches.

Usually you start from an intent, not from the map:

```
:Scry add a PDF export
```

The cursor lands on the capability that work is about — matching a feature
you already have, or writing one — and aiming ends in a **plan**, in the
map's own grammar:

```
feature Take a checklist away as a PDF
  Turns the on-screen checklist into a clean sheet of paper.
  route c/[slug]           src/pages/c/[slug].astro   ✓ present (file)
    add a print button that opens the print view
  def src/styles/global.css                           ✓ present (file)
    add the @media print block; remove the dark-mode force
  module src/lib/site.js                              ✓ present (file)
  route print              src/pages/print.astro      ✗ absent
    the print-only sheet: steps, notes, no chrome
```

What exists, what will change (`~ change`), what gets created (`+ create`),
and what this change doesn't touch — on one screen, in the diff colors your
scheme already has. Alter the plan by editing lines; discard it with `u`;
build it with `~`, pre-filled with what you said. The cast carries your
edited notes, so it executes the plan you approved rather than re-deriving
one, and afterwards each planned row flips to what actually happened — a
planned member the cast never touched reads `✗ skipped`.

The cast ends in a review tab: the glass on top — the plan still in view —
and below it, what's on disk against what the cast wrote, in vim's own
diff, cursor on the first hunk. `]q` walks the files with both panes moving
together; `:w` keeps one; closing the tab is closing the review.

Or write the sentence yourself and press `+` on it, and scry finds the files
it's made of:

```
feature Read a checklist as markdown or JSON instead of a web page
  Every checklist is fetchable as its source markdown or as structured
  JSON, enough for an agent to use the library without parsing HTML.
  module src/pages/[slug].md.ts
  module src/pages/[slug].json.ts
  module src/pages/index.json.ts
```

Everything under the first line arrived by pressing one key, so you don't
need to know the file layout before you can describe the product. It's an
ordinary buffer edit; `u` takes it back.

Adding a capability is the same verb, because a member names its file
before the file exists: `route print` names `src/pages/print.astro` whether
or not anything is there yet. Write the feature you want with the members it
should have, and cast — absent members are files to create.

The rest of scry keeps that map accurate. Checks say whether each claim
holds; kinds say which file a member names. Open the glass and every line
is checked as it renders:

```
scry · 3 features · 1 building · 1 broken · 1 to do · 4 of 10 files undescribed   checked 40s ago
      6 claims · 3 backed · 1 missing · 1 violated · 1 unchecked

feature a user can reset their password                          ◐ 2 of 4
  Requests a link by email. The link burns on use.

  contains
    lua/auth/reset.lua:request_reset                             ✓ defined
    lua/auth/reset.lua:consume_link                              ✗ absent
  never
    token.*log                                                   ✓ no matches (rg)
  exercises
    tests/reset_spec.lua:the link burns on use                   – unrun (:ScryExercise)

feature an admin can revoke a session                            ✗ broken (1 of 2)
  contains
    lua/auth/admin.lua:revoke                                    ✓ defined
  never
    session.*delete_all                                          ✗ VIOLATED
        └ lua/auth/admin.lua:22 → store.session_delete_all()

feature sessions expire                                          – no evidence yet
  Named, with nothing checkable under it yet.
```

One editable buffer. Feature lines carry a rolled-up state; the claims
under them carry per-claim verdicts. Verdicts are computed on every check
and never stored in the file.

## How the map stays accurate

**Features are user-level; claims are their evidence.** A feature is one
thing a user can accomplish, named the way they'd name it — not "the auth
system" (a grouping) and not "validate the token" (that's a claim). A
feature's scope is derived from the files its claims name, never declared.
Prose between claims is preserved and never checked. See `:h scry-altitude`.

**Coverage is checked too.** Every feature can read done while the map
describes a fraction of the product, so the header counts the files no
feature claims and `:ScryUnclaimed` lists them. `+` fills the gap: a
conjurer drafts features for the undescribed files, into the glass, where
you review them — checked like anything you typed, `u` to discard, nothing
saved until `:w`. See `:h scry-drafting`.

**Rules are told and enforced.** A feature's `never` claims ride along with
every cast, so the generator can follow them — and the same patterns are
re-checked against the code once it lands, whoever wrote it. A violation is
reported with the line that proves it.

**Generated tests are kept independent of generated code.** Conjure the
check first, confirm it fails, then conjure the code with the spec withheld
from the request. A test and an implementation generated from the same
sentence share the same misreadings, so a passing suite would only show the
generator agreed with itself. See `:h scry-independence`.

## Evidence, briefly

`contains` and `never` are **static** — a definition node, a text match —
so they re-run on every check. `exercises` is **dynamic**: a spec ran and
passed. **Checking never runs anything** — only `:ScryExercise` executes,
and a pass whose files have since moved degrades to `– stale`, which is not
a pass.

A single absent claim is also a piece of work: `:Conjure` on it seeds the
quickfix list and hands off to conjurer — the smaller sibling of `~` on the
whole feature. On save, the claim re-checks: `✗ absent` becomes `✓ defined`.

## Install

```lua
-- vim.pack (Neovim 0.12+)
vim.pack.add({ "https://github.com/vim-pro/scry.nvim" })
-- lazy.nvim
{ "vim-pro/scry.nvim", opts = {} }
```

Requires Neovim 0.10+, **ripgrep**, and the lua treesitter parser (bundled).
**Requires [conjurer.nvim](https://github.com/vim-pro/conjurer.nvim)** —
scry conjures through it. [quickfix-pro.nvim](https://quickfix.vim.pro) is
optional polish for the list.

Reach — finding what a feature's entry points pull in, so you don't
hand-enumerate them — needs nothing installed: it follows import specifiers
by reading files, so it works on `.astro` routes and Lua modules that no
name resolver handles.

`:Scry` to start. `:checkhealth scry` to verify. Bringing scry to an
existing repository — what to configure first, what to describe by hand,
when to draft — is `:h scry-quickstart`.

In the glass, `<CR>` opens what the line under the cursor is about — the code
a claim points at, or a feature's fold. Claims jump to evidence when the last
check found some (a violated prohibition lands on the violation), and
otherwise to the definition, located by the same query that decided the
verdict. See `:h scry-mappings`.

## Configuration (defaults)

```lua
require("scry").setup({
  map_path = ".scry/map.scry",  -- versioned with the code it describes
  resolver = "",                -- "" = treesitter + ripgrep
  test = { cmd = {} },          -- how to run ONE spec; the path is appended.
                                -- Empty = exercises claims stay "– unrun".
  sources = {},                 -- what divergence considers claimable.
                                -- Empty = everything ripgrep lists.
})
```

## What scry does not claim

The full list is `:h scry-honesty`. In short:

- **"backed" means accounted for, not correct.** Nothing here says your
  code *works*.
- `contains ✓ defined` — a definition with that name exists. Nothing about
  its body.
- `never ✓ no matches (rg)` — no textual match, **not** absence of behavior.
  A violation is proof (with its line); a clean result is only evidence.
- Verdicts describe **saved files** at a timestamp, which the header carries.
- **Divergence is file-level.** A file a feature uses but never names reads
  as unclaimed, and `sources` decides what counts as a file. It answers "is
  anything undescribed", not "is the description any good" — and narrowing
  `sources` to shrink the count is a lie scry can't detect.
- **`contains path` with no symbol claims only that the file exists.** It
  exists for files that define nothing nameable, and renders
  `✓ present (file)`.
- **Scry reports its own limits.** Once per project it names the one thing
  that would most improve its answers — e.g. *"12 claims stop at
  `defined (text)` — no grammar here for astro typescript"* — and it
  refuses to open without ripgrep, since without it `never` claims would
  silently stop being checked.
- **A `def` is answerable in every language, at one of two levels.** With a
  treesitter grammar installed you get `✓ defined` — a definition node.
  Otherwise `✓ defined (text)`: a line that looks like a definition, which
  could be a comment. The label says which one answered; `:checkhealth
  scry` says what your machine parses.
- **A feature reads as its weakest claim, and `done` requires a run.** Four
  claims that each say "the file is on disk" roll up to `✓ 4 files exist`,
  never `✓ done`. `✓ done` requires an `exercises` claim that actually ran.
  `g?` in the glass explains each verdict's limits inline.

## Development

```sh
./scripts/test
```

## Notes

- Division of labor: conjurer generates edits, quickfix-pro presents lists,
  scry holds the map. conjurer is required; quickfix-pro is optional.
- v0 checks lua definitions with treesitter and any language ripgrep can
  search (file presence, prohibitions). Other languages render
  `– unchecked`, never a pass.
