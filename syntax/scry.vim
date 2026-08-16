" The map is a language, so it is colored like one.
"
" Indentation is the grammar (see |scry-map|), so it is also the syntax:
"   col 0     feature <name>, or prose
"   2 spaces  a typed member, a section keyword, or the feature's own prose
"   4 spaces  a claim under a section keyword, or a member's own intent
"
" TWO RULES THIS FILE KEEPS.
"
" It may never color something as grammar that the parser reads as prose. A
" syntax file that disagrees with the parser is worse than none, because it
" tells you a line is checked when nothing will ever check it.
"
" And it cannot guess a member from its shape. `  module src/page.tsx` and
" `  Search or browse published checklists.` are both two spaces, a word, a
" space and more text — so the kinds in force are handed in as
" b:scry_kinds, exactly as map.parse takes them. Shape alone once rendered
" the first word of a feature's description as a file path.
if exists("b:current_syntax")
  finish
endif

let s:kinds = get(b:, "scry_kinds", 'module\|def')

" Prose first, deliberately: later items win at the same start position, so
" everything specific below overrides this. Prose is whatever the parser did
" not recognize, and it is never checked.
syn match scryProse "^.*$"

" A flush-left line of prose between features is a HEADING — the one level
" of grouping the map has. Still prose to the parser: never checked, never
" a claim, lossless. It only reads differently.
syn match scryHeading "^\%(feature\s\)\@!\S.*$"

" GRAMMAR EXISTS ONLY INSIDE A FEATURE. map.parse skips every line until the
" first `feature`, so a `contains` above it opens nothing and the target
" under it is not a claim. Both are prose and must look like it.
" A flush-left line ends the block — the next feature, or a heading. Without
" the second end, a heading between features sat INSIDE the previous block's
" region, where only the contains list may match, and the same heading
" rendered as structure or as dimmed prose depending on nothing but its
" position.
syn region scryFeatureBlock
      \ start="^feature\s"
      \ end="^feature\s"me=s-1
      \ end="^\%(feature\s\)\@!\S"me=s-1
      \ keepend
      \ contains=scryFeatureLine,scryDescription,scryIntent,scrySectionBlock,scryNeverBlock,scryMemberLine,scryProse

syn match scryFeatureLine "^feature\s.*$" contained contains=scryKeyword,scryFeatureName
syn match scryKeyword "^feature\>" contained
syn match scryFeatureName "\%(^feature\s\+\)\@<=.\+$" contained

" THE FEATURE'S OWN DESCRIPTION — two-space prose that is not a member and
" not a section. Defined BEFORE those so they override it where they match.
" It is the sentence saying what the feature IS, and it was dimmed like
" every other unchecked line, which made the one piece of writing a reader
" most needs the hardest thing on the page to find.
syn match scryDescription "^  \S.*$" contained

" A member's intent: four-space prose under a member. Defined before the
" section blocks, which claim their own four-space lines.
syn match scryIntent "^    \S.*$" contained

" Section headers and the claims beneath them, as regions so a claim is
" distinguishable from a member's intent — the parser has always known which
" opened, and now so does this.
syn region scrySectionBlock
      \ start="^  \%(contains\|exercises\)\s*$"
      \ end="^\%(\S\|  \S\)"me=s-1
      \ keepend contained contains=scrySection,scryClaim
syn match scrySection "^  \%(contains\|exercises\)\s*$" contained

" A never-block runs until the next section header, feature, or dedented
" line. A BLANK LINE DOES NOT END IT — the map's rule, not a shortcut here.
syn region scryNeverBlock
      \ start="^  never\s*$"
      \ end="^\%(\S\|  \S\)"me=s-1
      \ keepend contained contains=scryNever,scryPattern
syn match scryNever "^  never\s*$" contained
syn match scryPattern "^    \S.*$" contained

" A claim, split like a quickfix row: the path you navigate by, the
" punctuation that recedes, the symbol you are actually claiming.
syn match scryClaim "^    \S.*$" contained contains=scryPath,scrySeparator,scrySymbol
syn match scryPath "[^ :]\+" contained
syn match scrySeparator ":" contained
syn match scrySymbol "\%(:\)\@<=[A-Za-z0-9_.]\+" contained

" A TYPED MEMBER, matched only for kinds this project actually has.
" Defined AFTER scryPath so the kind word is not eaten by it — at equal
" start positions Vim gives the later item priority.
execute 'syn match scryMemberLine "^  \%(' . s:kinds . '\)\s\+\S.*$" contained'
      \ . ' contains=scryKind,scryPath,scrySeparator,scrySymbol'
execute 'syn match scryKind "^  \zs\%(' . s:kinds . '\)\ze\s" contained'

hi def link scryProse ScryProse
hi def link scryHeading ScryHeading
hi def link scryDescription ScryDescription
hi def link scryIntent ScryIntent
hi def link scryKeyword ScryKeyword
hi def link scryFeatureName ScryFeatureName
hi def link scryKind ScryKind
hi def link scrySection ScrySection
hi def link scryNever ScryNever
hi def link scryPattern ScryNever
hi def link scryPath ScryPath
hi def link scrySeparator ScrySeparator
hi def link scrySymbol ScrySymbol

let b:current_syntax = "scry"
