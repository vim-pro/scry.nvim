# scry.nvim

**Scry your software.** Look into your codebase and see the product it
describes. Then conjure the changes you want.

**[scry.vim.pro](https://scry.vim.pro)** · `:h scry`

Features, fixes, and refactors start in the glass, not in the code. One
buffer describes the product, and you work by changing the description: a
new feature is a part of the product that isn't real yet, a bug fix is a
behavior that doesn't hold yet. Your worklist and your product are the
same document.

`:Conjure` takes it from there: the check is conjured first (you read
it, it must fail), then the code — with the check and the feature's
prohibitions withheld from the model that writes it. The code is where you
review, not where you start.

The work leaves a trail: type a claim yourself, or conjure one and watch it
come true, and its `∅ untouched` marker clears. Edit a claim and its trail
resets — every event is keyed to a hash of the claim's text.

```
scry · 3 features · 1 building · 1 broken · 1 to do · 4 unclaimed files   checked 40s ago
      6 claims · 3 backed · 1 missing · 1 violated · 1 unchecked · 4 untouched

feature a user can reset their password                          ◐ 2 of 4
  Requests a link by email. The link burns on use.

  contains
    lua/auth/reset.lua:request_reset                             ✓ defined
    lua/auth/reset.lua:consume_link                              ✗ absent · ∅ untouched
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

**And `:ScryDraft` fills that gap — but a draft is not a belief.** The
scrying pass asks a conjurer to write features for the unclaimed files, into
the glass, where you read them. Drafted claims carry no ownership trail, so
they render *untouched* and the header counts them that way: a hundred
machine-written claims nobody has read is inventory, not understanding. One
becomes yours when you edit it. The machine types; you decide. See
`:h scry-drafting`.

**Features sit at sea level; claims are their evidence.** A feature is one
thing a user can accomplish, named the way they'd name it — not "the auth
system" (a grouping) and not "validate the token" (a subfunction, which is
what a claim already is). Cockburn's tests: one thing, one sitting, and it
matters that you can do many. A feature's scope is *derived* from the files
its claims name, never declared — see `:h scry-altitude`.

**The map is prose plus claims.** Write as much explanation as you like —
prose is preserved verbatim and never checked. The sentences carry the
theory; the claims carry the check.

**The work leaves a trail.** Authoring a claim, conjuring it, running its
check red then green — each marks the claim it touched, and the trail is
what clears `∅ untouched`. A trail can only exist if the work actually
passed through your hands, and editing a claim resets it.

**Prohibitions are a holdout.** `never` claims are withheld from the model
that writes your code and checked afterwards. If the generator is shown the
prohibition, its output satisfying it tells you nothing — it was asked to.
A rule it never saw, checked after, is real evidence. That's why prohibitions
are stored outside the repo by default.

**Theory-debt is a number.** How much of your system has no one engaged
with? Conjuring generates untouched claims at machine speed; working through
them is the only thing that pays it down. `scry 9f ✓6 ◐2 ✗1 ∅3`.

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
- **A feature's state is only as good as its claims.** `✓ done` means every
  claim under it holds and someone here has read it, not that the feature
  works. Backed but unread is its own state (`– unread`), because a fresh
  draft and a freshly cloned map both land there.

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
