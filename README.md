# scry.nvim

**Scry your software.** Look into your codebase and see the product it
describes. Then conjure the changes you want.

**[scry.vim.pro](https://scry.vim.pro)** · `:h scry`

## Operators, one noun up

Vim's bargain is operators × text objects. `d2w`, `ci"`, `>ap` — small
orthogonal verbs applied to precisely addressed nouns, repeatable with `.`,
fannable with `:g`. That grammar is why vim survives every editor that
tried to replace it.

[conjurer.nvim](https://conjurer.vim.pro) ported the grammar to generated
edits: `~{motion}` is an operator whose effect is *rewrite this region
toward an intent*. Same verbs, same nouns, new effect.

**scry raises the noun.** Not a region in a file — a capability. The glass
is not a report you read; it is the noun-space you aim at.

Put the cursor on `Tailor a checklist to your own situation`, press `~`,
say what you want. The change lands across `compile.ts`, `c/[slug].astro`,
`copy.astro` and `c/index.astro`. Four files, one intent, and you never
opened one.

`.` repeats it on the next feature. `:g/^feature.*export/normal ~` fans it
across every capability that matches. Nothing new to learn — you already
know the grammar; scry just gives it a bigger noun.

You don't sit down wanting to look at a map. You sit down wanting to do
something, and the map is how scry finds the capability it belongs to — so
say what you want and it aims you:

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
what gets removed, what this change doesn't touch — one screen, with the
states rendered in the diff colors your scheme already has. Alter it by
editing lines; it's your buffer. Discard it with `u`. Build it with `~`,
pre-filled with what you said — the cast carries your edited notes, so it
executes the plan you approved rather than re-deriving one, and afterwards
each planned row flips to what actually happened. A planned member the cast
never touched reads `✗ skipped`, because an approved plan and a cast that
quietly did four fifths of it must not look the same.

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

Everything under the first line arrived by pressing one key. Typing member
paths by hand meant knowing the layout before you were allowed to describe
the product, which is backwards. It's an ordinary buffer edit, so `u` takes
it back.

Adding a capability is the same verb, because a member names its file
before the file exists: `route print` names `src/pages/print.astro` whether
or not anything is there yet. Write the feature you want with the members it
should have, and cast — absent members are files to create.

Everything else here exists to keep that noun real. The checks tell you
whether what you asked for actually landed; the kinds tell a member where
its file lives. Neither is the point. The point is that you can put a
cursor on a capability, and the rest keeps the map from lying about what
it's made of.

```
scry · 3 features · 1 building · 1 broken · 1 to do · 4 unclaimed files   checked 40s ago
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

One editable buffer. Features are the line you scan; claims are the evidence
under them. Everything to the right is scry's answer, computed and never
stored.

## The four ideas

**Every feature done is not the same as done.** A map whose features all
read `✓ done` can still describe a fraction of the product, so the header
counts the files no feature claims and `:ScryUnclaimed` lists them. Each one
is a decision: add a claim to the feature that owns it, or name the feature
nobody wrote down. This is reflexion's third verdict — see
`:h scry-divergence`.

**And `+` in the glass fills that gap — but a draft is not a belief.** The
scrying pass asks a conjurer to write features for the unclaimed files, into
the glass, where you read them — a dozen at a time, batch after batch, until
the project is described or you stop it. A drafted claim arrives *unchecked*
and stays that way until an engine answers it: a hundred machine-written
lines are inventory until something confirms them, and the verdicts are what
confirm them. The machine types; you decide. See `:h scry-drafting`.

**Features sit at sea level; claims are their evidence.** A feature is one
thing a user can accomplish, named the way they'd name it — not "the auth
system" (a grouping) and not "validate the token" (a subfunction, which is
what a claim already is). Cockburn's tests: one thing, one sitting, and it
matters that you can do many. A feature's scope is *derived* from the files
its claims name, never declared — see `:h scry-altitude`.

**The map is prose plus claims.** Write as much explanation as you like —
prose is preserved verbatim and never checked. The sentences carry the
theory; the claims carry the check.

**Prohibitions are a holdout.** `never` claims are withheld from the model
that writes your code and checked afterwards. If the generator is shown the
prohibition, its output satisfying it tells you nothing — it was asked to.
A rule it never saw, checked after, is real evidence. That's why prohibitions
are stored outside the repo by default.

**Theory-debt is a number.** How much of your system does the map fail to
describe, and how much of what it describes does not hold?
`scry 9f ✓6 ◐2 ✗1`.

## Two axes of evidence

`contains`, `calls` and `never` are **static** — a definition node, a text
match. Cheap and side-effect-free, so they run on every check. `exercises` is
**dynamic**: a spec was run and it passed.

Structural claims say *where things are*; an exercised claim says *what
holds*. Neither is the primary axis — adding a feature usually wants one of
each, and fixing a bug often wants only the second.

**Checking never runs anything.** `:Scry` reads what the last `:ScryExercise`
recorded; only `:ScryExercise` executes. A glass that shelled out to your test
suite whenever you opened it is a glass you'd stop opening. The price is
staleness, so a run fingerprints the feature's files as it starts — move any
of them and `✓ passing` degrades to `– stale`, which is not a pass.

Both `contains` and `exercises` can be conjured, and the order is the mechanism:
conjure the **check** first, confirm it goes **red**, then conjure
the code *with the spec withheld*. Two generations from one sentence share its
misreadings, so a suite written by whoever wrote the code proves only that the
generator was self-consistent. See `:h scry-independence`.

## Conjuring from the glass

An absent claim is a piece of work:

```vim
:Conjure          " in the glass, on a ✗ absent claim
```

scry seeds the quickfix list with the target site and your intent, then hands
off to [conjurer.nvim](https://github.com/vim-pro/conjurer.nvim) — which owns
the casting and per-site review. **scry never conjures anything itself.**

When you save the file, the withheld prohibitions run against the new code and
the claim re-checks: `✗ absent` becomes `✓ defined` — and because
you conjured it and it came true, it's yours. If the generated code trips a rule it never
saw, you find out with the evidence line.

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

Reach — what a feature's entry points actually pull in, so you don't
hand-enumerate them — needs nothing installed. It follows import specifiers
with a file read, which is why it works on `.astro` routes and Lua modules
that no name resolver reads.

`:Scry` to start. `:checkhealth scry` to verify.

In the glass, `<CR>` opens what the line under the cursor is about — the code
a claim points at, or a feature's fold. Claims jump to evidence when the last
check found some (a violated prohibition lands on the violation), and
otherwise to the definition, located by the same query that decided the
verdict. See `:h scry-mappings`.

## Configuration (defaults)

```lua
require("scry").setup({
  map_path = ".scry/map.scry",  -- versioned with the code it describes
  holdout_path = "",            -- "" = never-claims outside the repo
  resolver = "",                -- "" = treesitter + ripgrep
  test = { cmd = {} },          -- how to run ONE spec; the path is appended.
                                -- Empty = exercises claims stay "– unrun".
  sources = {},                 -- what divergence considers claimable.
                                -- Empty = everything ripgrep lists.
})
```

## What scry does not claim

This matters more than the feature list, and `:h scry-honesty` states it in
full. In short:

- **"backed" means accounted for, not correct.** claimed → backed →
  exercised; v0 tops out at backed. Nothing here says your code *works*.
- `contains ✓ defined` — a definition with that name exists. Nothing about
  its body.
- `calls ✓ referenced (text)` — the token occurs and the target exists. Not
  a resolved call, not reachability.
- `never ✓ no matches (rg)` — no textual match, **not** absence of behavior.
  The asymmetry is the useful part: a violation is proof (with its line); a
  clean result is evidence.
- Verdicts describe **saved files** at a timestamp, which the header carries.
- Holdout independence is against **leakage, not adversaries** — hidden from
  a generator that reads your repo, not from one told to hunt your disk.
- **Divergence is file-level and blunt.** A file a feature uses but never
  names reads as unclaimed, and `sources` decides what counts as a file. It
  answers "is anything undescribed", not "is the description any good".
  Narrowing `sources` is the one move that can make it lie — excluding a
  test runner is honest, excluding product to drop the count is not, and
  scry cannot tell the two apart for you.
- **`contains path` with no symbol claims only that the file exists.** It is
  there for files that define nothing nameable, so an unclaimed file always
  has a remedy. It renders `✓ present (file)` — a map of
  bare paths is a list of files, which is what features exist to prevent.
- **Scry tells you its own ceiling.** Once per project it names the one thing
  that would most improve your answers, counted from your own claims —
  *"12 claims stop at `defined (text)` — no grammar here for astro
  typescript"* — and refuses to open at all without ripgrep, because a
  prohibition that has quietly stopped being checked is worse than no glass.
- **A `def` is answerable in every language, at one of two rungs.** Where a
  treesitter grammar is installed you get `✓ defined` — a definition node.
  Everywhere else you get `✓ defined (text)`: a line that looks like one,
  which cannot tell a definition from the same words in a comment. The label
  is which rung answered. `:checkhealth scry` says what your machine parses.
- **A feature is only as strong as its weakest claim, and `done` costs a
  run.** Four claims that each say "the file is on disk" roll up to
  `✓ 4 files exist`, never `✓ done` — a feature cannot be better established
  than its least-established part. `✓ done` requires an `exercises` claim
  that actually ran. Press `g?` in the glass and it will say which rung you
  got and what it does not assert.

## Development

```sh
./scripts/test
```

## Notes

- The verb split: conjurer is the arrow, quickfix-pro is presentation, scry
  is the glass. conjurer is required; quickfix-pro is optional.
- v0 checks lua (treesitter definitions) and any language ripgrep can search
  (references, prohibitions). Other languages render `– unchecked`, never a
  pass.
