" The map is a language, so it is coloured like one.
"
" Until this file existed the glass set `filetype=scry` and then rendered
" every line in Normal: the feature you were looking for, the prose you were
" meant to skim, and the claim you were about to conjure all looked alike,
" and the only colour on the page came from the verdicts hanging off the
" right. The text carries as much of the meaning as the verdicts do.
"
" Indentation is the grammar (see |scry-map|), so it is also the syntax:
"   col 0     feature <name>, or prose
"   2 spaces  contains / calls / never / exercises
"   4 spaces  a claim
if exists("b:current_syntax")
  finish
endif

" Prose first, deliberately: later items win at the same start position in
" Vim's syntax engine, so everything specific below overrides this. Prose is
" whatever the parser did not recognise, and it is never checked — dimming it
" is honest rather than merely calm.
syn match scryProse "^.*$"

" A feature: one thing a user can accomplish. The name carries the page.
syn match scryFeatureLine "^feature\s.*$" contains=scryKeyword,scryFeatureName
syn match scryKeyword "^feature\>" contained
syn match scryFeatureName "\%(^feature\s\+\)\@<=.\+$" contained

" Section headers. `never` is set apart from the others on purpose: the other
" three say what the code contains, and it says what the code must not — and
" it is the one whose text lives outside the repository.
syn match scrySection "^  \%(contains\|calls\|exercises\)\s*$"
syn match scryNever "^  never\s*$"

" A never-block runs until the next section header, feature, or dedented
" line. A BLANK LINE DOES NOT END IT — that is the map's rule, not a
" shortcut here, and matching it means a prohibition after a blank line
" still reads as a prohibition instead of quietly looking like a path.
syn region scryNeverBlock
      \ start="^  never\s*$"
      \ end="^\%(\S\|  \S\)"me=s-1
      \ keepend contains=scryNever,scryPattern
syn match scryPattern "^    \S.*$" contained contains=scryStamp

" A claim, split like a quickfix row: the path you navigate by, the
" punctuation that recedes, the symbol you are actually claiming.
syn match scryClaim "^    \S.*$" contains=scryPath,scrySeparator,scrySymbol,scryStamp
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
