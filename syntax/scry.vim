" The map is a language, so it is colored like one.
"
" Until this file existed the glass set `filetype=scry` and then rendered
" every line in Normal: the feature you were looking for, the prose you were
" meant to skim, and the claim you were about to conjure all looked alike,
" and the only color on the page came from the verdicts hanging off the
" right. The text carries as much of the meaning as the verdicts do.
"
" Indentation is the grammar (see |scry-map|), so it is also the syntax:
"   col 0     feature <name>, or prose
"   2 spaces  contains / calls / never / exercises
"   4 spaces  a claim
"
" THE RULE THIS FILE KEEPS: it may never color something as grammar that
" the parser reads as prose. A syntax file that disagrees with the parser
" is worse than none, because it tells you a line is checked when nothing
" will ever check it.
if exists("b:current_syntax")
  finish
endif

" Prose first, deliberately: later items win at the same start position in
" Vim's syntax engine, so everything specific below overrides this. Prose is
" whatever the parser did not recognize, and it is never checked — dimming it
" is honest rather than merely calm.
syn match scryProse "^.*$"

" GRAMMAR EXISTS ONLY INSIDE A FEATURE. map.parse walks the buffer and skips
" every line until the first `feature` (`elseif feature then`), so a
" `contains` above it opens nothing and the target under that is not a
" claim — they are prose, and they have to look like prose. Scoping the
" items to this region is what keeps that promise; the last block runs to
" the end of the buffer.
syn region scryFeatureBlock
      \ start="^feature\s"
      \ end="^feature\s"me=s-1
      \ keepend
      \ contains=scryFeatureLine,scryNeverBlock,scrySection,scryClaim,scryProse

" A feature: one thing a user can accomplish. The name carries the page.
syn match scryFeatureLine "^feature\s.*$" contained contains=scryKeyword,scryFeatureName
syn match scryKeyword "^feature\>" contained
syn match scryFeatureName "\%(^feature\s\+\)\@<=.\+$" contained

" Section headers. `never` is set apart from the others on purpose: the other
" three say what the code contains, and it says what the code must not — and
" it is the one whose text lives outside the repository.
syn match scrySection "^  \%(contains\|calls\|exercises\)\s*$" contained

" A never-block runs until the next section header, feature, or dedented
" line. A BLANK LINE DOES NOT END IT — that is the map's rule, not a
" shortcut here, and matching it means a prohibition after a blank line
" still reads as a prohibition instead of quietly looking like a path.
syn region scryNeverBlock
      \ start="^  never\s*$"
      \ end="^\%(\S\|  \S\)"me=s-1
      \ keepend contained contains=scryNever,scryPattern
syn match scryNever "^  never\s*$" contained
syn match scryPattern "^    \S.*$" contained contains=scryStamp

" A claim, split like a quickfix row: the path you navigate by, the
" punctuation that recedes, the symbol you are actually claiming.
syn match scryClaim "^    \S.*$" contained contains=scryPath,scrySeparator,scrySymbol,scryStamp
syn match scryPath "\%(^    \)\@<=[^ :]\+" contained
syn match scrySeparator ":" contained
syn match scrySymbol "\%(:\)\@<=[A-Za-z0-9_.]\+" contained

" Stamps from the ratification era still parse and no longer mean anything,
" so they are rendered as the residue they are.
syn match scryStamp "\s\+--\s\+@\S\+\s\+\S\+\s\+\S\+$" contained

hi def link scryProse ScryProse
hi def link scryKeyword ScryKeyword
hi def link scryFeatureName ScryFeatureName
hi def link scrySection ScrySection
hi def link scryNever ScryNever
hi def link scryPattern ScryNever
hi def link scryPath ScryPath
hi def link scrySeparator ScrySeparator
hi def link scrySymbol ScrySymbol
hi def link scryStamp ScryStamp

let b:current_syntax = "scry"
