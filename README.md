# scry.nvim

**A ledger of what you believe about your codebase, continuously audited
against what the code actually does.**

`:h scry`

Git records what happened. scry records what you *think is true*, and tells
you the moment the code stops agreeing.

You write a plain-language model of what your project does. scry checks it
against the real code and shows what's backed, what's claimed but missing,
and what's violated. The beliefs are yours, so they can be wrong — and that's
the point. A lint failure means the code is wrong; a **divergence means
someone is wrong, and deciding who is the product.**

```
scry · 7 claims · 5 backed · 1 missing · 1 violated · 2 unratified   checked 40s ago (files on disk)

# providers
  files lua/conjurer/providers/*.lua

  The provider layer turns a Request into text and calls back once on the
  main loop. Transport only: no UI, no lists.

  contains
    lua/conjurer/providers/cli.lua:request    -- @michael 2026-07-26 3f9a01   ✓ defined
    lua/conjurer/providers/known.lua:resolve_api                              ✓ defined · ∅ unratified
  calls
    known.lua::resolve_api                    -- @michael 2026-07-26 b71e00   ✓ referenced (text)
    stream.lua::parse_sse                                                     ✗ absent · ∅ unratified
  never
    vim\.ui\.                                                                 ✓ no matches (rg)
    vim\.fn\.setqflist                                                        ✗ VIOLATED
        └ lua/conjurer/providers/cli.lua:88 → vim.fn.setqflist(...)
```

One editable buffer. The claims are your text; everything to the right is
scry's answer, computed and never stored.

## The four ideas

**The map is prose plus claims.** Write as much explanation as you like —
prose is preserved verbatim and never checked. The sentences carry the
theory; the claims carry the check. That split is the whole trick.

**Ratification is the loop.** `:ScryRatify` stamps a claim with your name and
a hash of its text — so **editing a claim un-ratifies it**, mechanically, no
hooks. Why bother? Clicking "accept" is free, which is why approval
degenerates into LGTM. You cannot write down a belief without having one, and
a careless one diverges later with your name on it.

**Prohibitions are a holdout.** `never` claims are withheld from the model
that writes your code and checked afterwards. If the generator is shown the
prohibition, its output satisfying it tells you nothing — it was asked to.
A rule it never saw, checked after, is real evidence. That's why prohibitions
are stored outside the repo by default.

**Theory-debt is a number.** How much of your system has nobody put their
name on? Conjuring generates that debt at machine speed; ratification is the
only thing that pays it down. `scry 14c ✓11 ✗2 ∅3`.

## The cascade

An absent claim is a piece of work:

```vim
:ScryCascade      " on a ✗ absent claim
```

scry seeds the quickfix list with the target site and your intent, then hands
off to [conjurer.nvim](https://github.com/vim-pro/conjurer.nvim) — which owns
the casting and per-site review. **scry never conjures anything itself.**

When you save the file, the withheld prohibitions run against the new code and
the claim re-checks: `✗ absent` becomes `✓ defined · ∅ unratified`, and
ratifying it finishes the loop. If the generated code trips a rule it never
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
  author = "",                  -- "" = git config user.name
  resolver = "",                -- "" = treesitter + ripgrep
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
