# scry.nvim

**The surface you write software from.**

`:h scry`

Features, fixes, and refactors start in the glass, not in the code. One
buffer describes the product — prose at the altitude you think at, with
checkable claims underneath — and you work by changing the description: a
new feature is a claim that isn't true yet (`✗ absent`), a bug fix is a
check that doesn't pass yet.

`:ScryCascade` takes it from there: the check is conjured first (you read
it, it must fail), then the code — with the check and the concern's
prohibitions withheld from the model that writes it. The code is where you
review, not where you start.

The work leaves a trail: type a claim yourself, or cascade one and watch it
come true, and its `∅ untouched` marker clears. Edit a claim and its trail
resets — every event is keyed to a hash of the claim's text.

```
scry · 8 claims · 5 backed · 1 missing · 1 violated · 1 unchecked · 2 untouched   checked 40s ago (files on disk)

# providers
  files lua/conjurer/providers/*.lua

  The provider layer turns a Request into text and calls back once on the
  main loop. Transport only: no UI, no lists.

  contains
    lua/conjurer/providers/cli.lua:request    -- @michael 2026-07-26 3f9a01   ✓ defined
    lua/conjurer/providers/known.lua:resolve_api                              ✓ defined · ∅ untouched
  calls
    known.lua::resolve_api                    -- @michael 2026-07-26 b71e00   ✓ referenced (text)
    stream.lua::parse_sse                                                     ✗ absent · ∅ untouched
  never
    vim\.ui\.                                                                 ✓ no matches (rg)
    vim\.fn\.setqflist                                                        ✗ VIOLATED
        └ lua/conjurer/providers/cli.lua:88 → vim.fn.setqflist(...)
  exercises
    tests/cli_spec.lua                                                        – unrun (:ScryRun)
```

One editable buffer. The claims are your text; everything to the right is
scry's answer, computed and never stored.

## The four ideas

**The map is prose plus claims.** Write as much explanation as you like —
prose is preserved verbatim and never checked. The sentences carry the
theory; the claims carry the check. That split is the whole trick.

**The work leaves a trail.** Authoring a claim, cascading it, running its
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
them is the only thing that pays it down. `scry 14c ✓11 ✗2 ∅3`.

## Two axes of evidence

`contains`, `calls` and `never` are **static** — a definition node, a text
match. Cheap and side-effect-free, so they run on every check. `exercises` is
**dynamic**: a spec was run and it passed.

Structural claims say *where things are*; an exercised claim says *what
holds*. Neither is the primary axis — adding a feature usually wants one of
each, and fixing a bug often wants only the second.

**Checking never runs anything.** `:Scry` reads what the last `:ScryRun`
recorded; only `:ScryRun` executes. A glass that shelled out to your test
suite whenever you opened it is a glass you'd stop opening. The price is
staleness, so a run fingerprints the concern's files as it starts — move any
of them and `✓ passing` degrades to `– stale`, which is not a pass.

Both `contains` and `exercises` cascade, and the order is the mechanism:
conjure the **check** first, confirm it goes **red**, then conjure
the code *with the spec withheld*. Two generations from one sentence share its
misreadings, so a suite written by whoever wrote the code proves only that the
generator was self-consistent. See `:h scry-independence`.

## The cascade

An absent claim is a piece of work:

```vim
:ScryCascade      " on a ✗ absent claim
```

scry seeds the quickfix list with the target site and your intent, then hands
off to [conjurer.nvim](https://github.com/vim-pro/conjurer.nvim) — which owns
the casting and per-site review. **scry never conjures anything itself.**

When you save the file, the withheld prohibitions run against the new code and
the claim re-checks: `✗ absent` becomes `✓ defined` — and because
you cascaded it and it came true, it's yours. If the generated code trips a rule it never
saw, you find out with the evidence line.

## Install

```lua
-- vim.pack (Neovim 0.12+)
vim.pack.add({ "https://github.com/vim-pro/scry.nvim" })
-- lazy.nvim
{ "vim-pro/scry.nvim", opts = {} }
```

Requires Neovim 0.10+, **ripgrep**, and the lua treesitter parser (bundled).
conjurer.nvim and quickfix.pro are optional — scry works without them, you
just cast the seeded list yourself.

`:Scry` to start. `:checkhealth scry` to verify.

## Configuration (defaults)

```lua
require("scry").setup({
  map_path = ".scry/map.scry",  -- versioned with the code it describes
  holdout_path = "",            -- "" = never-claims outside the repo
  resolver = "",                -- "" = treesitter + ripgrep
  test = { cmd = {} },          -- how to run ONE spec; the path is appended.
                                -- Empty = exercises claims stay "– unrun".
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
- `never ✓ no matches (rg)` — no textual match, **not** absence of behaviour.
  The asymmetry is the useful part: a violation is proof (with its line); a
  clean result is evidence.
- Verdicts describe **saved files** at a timestamp, which the header carries.
- Holdout independence is against **leakage, not adversaries** — hidden from
  a generator that reads your repo, not from one told to hunt your disk.
- Theory-debt is **coverage-blind** until scry can report unclaimed code, so
  the claim count is rendered first: `0 diverged / 3 claims` means a thin
  map, not a healthy repo.

## Development

```sh
./scripts/test
```

## Notes

- The verb split: conjurer is the arrow, quickfix.pro is presentation, scry
  is the glass. This plugin depends on neither.
- v0 checks lua (treesitter definitions) and any language ripgrep can search
  (references, prohibitions). Other languages render `– unchecked`, never a
  pass.
