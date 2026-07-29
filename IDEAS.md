# The ideas scry is built on

scry recombines established work. This document records what each piece
contributes, **what we decided because of it**, and what is ours rather than
borrowed. It is a design record, not a reading list — every entry ends in a
consequence.

Provenance note: entries marked ✓ were read directly and quoted during design.
The rest come by way of the vim-pro whitepaper's prior-art review, which claims
primary-source verification; they have not been re-verified here.

---

## 1. Why the model is authored, not extracted

**The negative results.** Automatic recovery of high-level structure from code
does not work well enough to trust. Architecture recovery tops out around 56%
against verified ground truth [6]. Feature location does no better — roughly
half at best, with no agreed benchmark, which is why its own survey leaves
finding features a manual task [9] ✓. And mechanically syncing a high-level
model to code is a documented failure: of 50 engineers, 35 use no UML and 3 use
it for code generation [4]; across 450 practitioners, whole-system generation is
rare [5].

**Decision.** The map is written by a person. A model may *draft* it — a draft
arrives untouched, and working through it is what makes it yours. scry never
silently promotes recovered structure into belief.

**Consequence for the LLM pass** (designed, not yet built): recovery may produce
*objects*, never *features*. The machine finds what exists; the human names what
it is for.

---

## 2. What checking a model against code is called

**Software Reflexion Models** [3]. You author a high-level model and a mapping
to source; the tool reports three verdicts — **convergence** (model and code
agree), **divergence** (code has structure the model omits), **absence** (model
claims structure the code lacks).

**Decision.** scry's verdict vocabulary is this trichotomy, and its gap is
precise: we implement convergence (`✓ defined`) and absence (`✗ absent`) but
**not divergence**. We cannot report code that no claim covers, which is why the
claim count leads every render — a clean map may simply be an empty one.

**Now implemented, file-level.** `:ScryUnclaimed` reports the files no
feature's footprint names, and the header carries the count. Deliberately
coarse: enumerating definitions produces a list of `chomp` and `clip`, which
is vim-pro's documented failure. A file is a sentence you can act on.

**It earned its keep on first use.** Pointed at scry itself, divergence found
9 of 25 files described by nothing — including `check.lua`, `resolver.lua`,
and the whole resolver directory. The feature axis alone said nothing was
wrong.

---

## 3. What a "concern" actually is

**Concern Graphs and FEAT** [7]. A concern is a **hand-picked set of code
elements scattered across files**, which the tool keeps consistent as the code
changes, detecting members that no longer resolve.

**Decision, and a correction — now implemented.** scry borrowed the word and
implemented a directory glob (`files lua/x/*.lua`). A glob is the one thing a
concern specifically is not — "a user can reset their password" is not a
directory. As of the feature layer, a footprint is **derived** from the union
of its claims' locations and `files` is gone. An empty footprint is
meaningful: a prohibition with nowhere to look reports `– unscoped` rather
than searching the whole project.

---

## 4. What altitude a feature sits at ✓

The deepest finding, and the one that reshapes the map.

**Cockburn's goal levels** [14] ✓. Goals sit at cloud (strategic), kite, **sea
level (user goal)**, fish, and clam (too low). Sea level is privileged, with
three mechanical tests:

> Is it done by one person, in one place, at one time (2-20 minutes)?
> Can I go to lunch as soon as this goal is completed?
> Can I ask for a raise if I do many of these?

The discriminator: *"Does your job performance depend on how many of these you
do today?"* — "Log on" fails; "Register a new customer" passes. And the line
that governs the whole design:

> The shortest summary of the function of a system is the list of blue level
> goals it supports.

**Independent convergence.** Cockburn notes sea level corresponds to the
**elementary business process** from business-process engineering [16] ✓, which
has a formal definition: *a task performed by one person in one place at one
time, in response to a business event, that adds measurable business value and
leaves data in a consistent state.* Two literatures arrived at the same
granularity.

**Dit's constraint** [9] ✓: a feature is *"a functionality that is defined by
requirements and accessible to developers and users."* If a user cannot observe
it, it is not a feature.

**The diagnosis this produced.** Cockburn's anecdote is scry's map exactly:

> I was once sent over a hundred pages of use cases, all "indigo", or below sea
> level… The sender later sent me the six user-goal use cases that had replaced
> them, and said everyone found them easier.

Every checkable line scry has — `contains path:symbol`, `calls symbol` — is
below sea level. With no sea-level layer above them, the indigo floated to the
top and became the product.

**Decision — three strata, and we already own the bottom one:**

| altitude | in scry | status |
|---|---|---|
| kite / cloud | optional grouping, for navigation only | not built, not needed yet |
| **sea level** | **the feature: one thing a user can accomplish** | **built** |
| fish / clam | `contains` · `calls` · `never` · `exercises` | built |

Claims are not promoted to product altitude; they are **subordinated** to a
feature as its evidence. No general tree, no recursion.

**Design scope generalizes it.** Every test above assumes a human at a business
task. Cockburn's answer for other systems is *design scope*: sea level is
relative to the actor of the system under discussion. For a library the user is
the calling programmer. For conjurer, `~ip` conjuring over a paragraph is sea
level; `parse_sse` is a subfunction.

**Kent Beck's Three Bears** [14] ✓. Cockburn teaches sea level by having you
write the same goal too high, then too low, then judge the middle —
calibration by contrast rather than by rule. Recorded in `:h scry-altitude`
as the fallback when the three tests don't settle it; still a natural fit for
the drafting pass, which could offer the kite and fish framings alongside
each proposed feature.

**What implementing it taught us.** A feature's state must be *derived*,
never authored, or the map gains a second thing that can drift from the
code. And "partial" has to require real progress — at least one claim
actually holding. A feature whose claims were merely never answered is
`unknown`, and since that is every feature before the first check settles,
calling it partial would be a lie told at the least useful moment.

---

## 5. Why editing the model cannot mechanically produce code

**Bidirectional transformations / lenses** [1][2][8]. A *get* reads a view out
of a source; a *put* writes an edited view back. Reading up is a function;
writing down is not — and the more the view abstracts away, the more
underdetermined the write-back.

**Decision.** This is why scry's editing ladder is graded by altitude rather
than by danger. `:write` on the map is mechanical because the glass is a lens
whose get is near-identity (parse → serialize is byte-exact, spec-pinned).
Conjuring is the high-altitude put where information is genuinely missing, so it
**proposes** and you review. The cascade seeding a file's first line is not a
limitation to apologize for — it is the view-update problem, and the review is
where it is resolved.

---

## 6. What it costs to know a reference is real

**Stack graphs** [11]. Name bindings as a graph, so resolving a reference to its
definition is path-finding — precise and file-incremental.

**Decision.** The resolver is an interface, and today's `ts_rg` is honest about
being the floor: `calls ✓ referenced (text)` is ripgrep, not resolution. The
rung ladder — referenced < resolved < exercised — is stated in the manual so the
verdict can never imply more than the engine delivered.

**Noted during review:** a working stack-graphs integration already exists in
the archived vim-pro (~110 lines, provisioned, verified resolving a shadowed
local). It covers JS/TS only, so it would buy scry's Lua-first case nothing
today — but the seam is real and the prior art is ours.

---

## 7. Why any of this matters

**Naur, "Programming as Theory Building"** [10]. A program's theory lives in the
people who built it and cannot be fully externalized. A program whose theory is
lost cannot be revived by reading the code.

**Decision, stated carefully.** scry does **not** repair the theory and must
never claim to. What it does is narrow the drift — keep the checkable surface of
your understanding honest, and make the moment you stopped understanding
something visible instead of silent. The manual's introduction was rewritten
once already for overclaiming here ("ratifying a claim is the small act that
fixes that" → it doesn't fix it).

This matters *more*, not less, as less code is written by hand.

---

## 8. Where the interface lives

**Magit and oil.nvim** [12][13]. Render system state as editable text in an
ordinary buffer; edit it; on save the diff is applied as real changes, and
discard reverts. The buffer is the interface, and undo is the safety model in
place of confirmation dialogs.

**Decision.** `scry://glass` is an `acwrite` buffer. Verdicts are extmarks —
computed, never stored — so the buffer's text is your beliefs and everything
beside it is scry's answer.

---

## What is ours

Not found in the literature above; these are scry's own arguments.

**The holdout.** A `never` claim is withheld from the generator and checked
afterward. If the model writing the code is shown the prohibition, its output
satisfying that prohibition tells you nothing — it was asked to. The argument is
imported from experimental method (held-out validation, pre-registration) rather
than from software engineering. Two guarantees, never conflated: request-level
withholding is hard and spec-tested; filesystem invisibility holds against a
repo-reading generator, not against one told to hunt.

**Check before code, and the vacuity gate.** When both the test and the
implementation are generated from one sentence, they are two samples from one
generator and share its misreadings. So the check is conjured first, the spec
path is withheld from the code request, and a check that passes before the
feature exists is flagged `– vacuous?` rather than counted. Red-green as a
machine-enforced precondition.

**Inferred provenance.** Ownership is not performed. Authoring a claim,
conjuring it, watching its proof go red then green — the trail those actions
leave is what clears `∅ untouched`, and editing a claim resets it. Replaces an
earlier hash-stamped signing ceremony that was, in the end, one keystroke and
therefore worthless.

**Two evidence axes.** `contains`/`calls`/`never` are static reads — cheap,
recomputed every check. `exercises` is dynamic — something ran. Structural
claims say *where things are*; exercised claims say *what holds*. Neither is
primary. Checking never executes anything; running is explicit, and a result
whose dependencies moved degrades to `– stale`.

---

## Open questions

- ~~**Divergence** (§2) needs object recovery.~~ Built: `:ScryDraft` sends the
  unclaimed files to a conjurer and the features come back into the glass.
  The resolution to the tension with §1 (recovered models are half right) is
  that a **draft is not a belief** — no ownership trail, so it renders
  untouched and the header counts it as untouched. Inventory until read.
  Dogfooding surfaced one thing first: divergence is file-level while
  footprints are symbol-derived, so a file that defines nothing could be
  accused with no remedy available. `contains <path>` with no symbol closes
  that, at `✓ present (file, no symbol named)` fidelity.
- **Does the sea-level 2–20 minute test have any analogue** for a library or a
  plugin? The completeness test ("can I go to lunch") probably transfers;
  duration probably does not. The manual drops duration and keeps the other
  two.
- **Do features nest at all?** Still one flat list. Nothing has needed a
  grouping level; the question reopens when a real map gets long.
- **Is `– unscoped` right** for a feature carrying prose and prohibitions but
  no located claims, or should that be refused at write time?
- ~~**`sources` and `map_path` are project-scoped but live in a global
  `setup()`.**~~ Answered: `.scry/config.json` honors `sources`, `test`,
  `resolver`, and `map_path`, and refuses `holdout_path`. The refusal is the
  interesting half — a committed file that could relocate the holdout back
  into the repo is exactly how you would defeat it.
- **An unrun `exercises` claim keeps its whole feature out of `done`.** That
  is correct — unrun is not a pass — but it means a map leaning on exercised
  evidence reads as all-building until `:ScryExercise` has run once. Worth
  knowing before it looks like a bug.
- **Does `calls` earn its place** at `✓ referenced (text)` fidelity, or should it
  move up to tree-sitter identifiers before it is trustworthy?
- ~~**What a machine-drafted feature list does to ownership**~~ — answered by
  making it literal rather than by argument: drafted claim ids are registered,
  the glass watcher declines to record them as authored, and they sit in the
  untouched count until edited. A hundred untouched claims READS as inventory
  because that is what the header says it is.

  Dogfooding the pass immediately found that this was not enough. Every
  drafted claim was untouched and the header said so — on the second line,
  among the claim counts — while the first line read `2 features · 2 done`.
  The untouched count was never the line anyone scans. So `unread` is now a
  feature state that displaces `done`: backed evidence plus no engagement is
  its own thing, and it covers a freshly cloned map as well as a fresh draft,
  since the trail is per-machine and does not travel with the file.

  Still open: whether *drafted* and *never-engaged-with* should read
  differently. Both are `unread` today and they are not quite the same thing.

---

## Sources

1. Foster, Greenwald, Moore, Pierce, Schmitt. *Combinators for Bidirectional
   Tree Transformations: A Linguistic Approach to the View-Update Problem.* ACM
   TOPLAS 29(3), 2007.
2. Bancilhon, Spyratos. *Update Semantics of Relational Views.* ACM TODS 6(4),
   1981, 557–575.
3. Murphy, Notkin, Sullivan. *Software Reflexion Models: Bridging the Gap
   Between Source and High-Level Models.* ACM SIGSOFT FSE, 1995.
4. Petre. *UML in Practice.* ICSE, 2013.
5. Hutchinson, Whittle, Rouncefield, Kristoffersen. *Empirical Assessment of MDE
   in Industry.* ICSE, 2011.
6. Garcia, Ivkovic, Medvidović. *A Comparative Analysis of Software Architecture
   Recovery Techniques.* ASE, 2013.
7. Robillard, Murphy. *Concern Graphs: Finding and Describing Concerns Using
   Structural Program Dependencies.* ICSE, 2002.
8. Hofmann, Pierce, Wagner. *Symmetric Lenses.* POPL, 2011.
9. ✓ Dit, Revelle, Gethers, Poshyvanyk. *Feature Location in Source Code: A
   Taxonomy and Survey.* J. Software: Evolution and Process 25(1), 2013.
   <https://www.cs.wm.edu/~denys/pubs/JSME-FL-SurveyCRCV1.pdf>
10. Naur. *Programming as Theory Building.* Microprocessing and
    Microprogramming 15(5), 1985, 253–261.
11. Creager, van Antwerpen. *Stack Graphs: Name Resolution at Scale.* EVCS, 2023.
12. Magit — a Git porcelain inside Emacs. <https://magit.vc>
13. oil.nvim — edit your filesystem like a buffer.
    <https://github.com/stevearc/oil.nvim>
14. ✓ Cockburn. *Writing Effective Use Cases.* 1999. Goal levels at pp. 47–49;
    Three Bears at pp. 153–154.
    <https://people.inf.elte.hu/molnarba/Informaciorendszerek_ELTE/Writing_effective_Use_cases_Cockburn.pdf>
15. ✓ Cockburn. *Unifying User Stories, Use Cases, Story Maps.*
    <https://alistaircockburn.com/Unifying%20us%20uc%20sm.pdf>
16. ✓ Elementary Business Processes.
    <https://www.glossaria.net/en/object-oriented-analysis-and-design/elementary-business-processes>
    · Larman, *Applying UML and Patterns*, ch. 6.
    <https://www.cs.wm.edu/~kemper/cs435/slides/l5.pdf>
