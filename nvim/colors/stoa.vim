" ╔══════════════════════════════════════════════════════════════╗
" ║  STOA LINUX — Neovim Colorscheme                            ║
" ║  "Conhece a ti mesmo." — inscrito no Templo de Delfos       ║
" ╚══════════════════════════════════════════════════════════════╝

set background=dark
highlight clear
if exists("syntax_on")
    syntax reset
endif
let g:colors_name = "stoa"

" ── Backgrounds ──
let s:bg_dark   = "#1a1714"
let s:bg        = "#211e19"
let s:bg_light  = "#2d2921"

" ── Foregrounds ──
let s:fg        = "#d4cfc4"
let s:fg_dim    = "#a89f91"
let s:fg_dark   = "#7a7267"

" ── Acentos ──
let s:bronze      = "#c49a5c"
let s:gold        = "#d4a84b"
let s:parchment   = "#c4b08a"
let s:tan         = "#a89272"
let s:olive       = "#8a9a6c"
let s:laurel      = "#6b7f52"
let s:marble      = "#9e9a92"
let s:stone       = "#6e6a62"
let s:terracotta  = "#b36b5a"
let s:rust        = "#945a4a"
let s:azure       = "#5a7a8a"
let s:sea         = "#4a6a7a"
let s:magenta     = "#946a7a"

" Função auxiliar
function! s:hi(group, fg, bg, attr)
    let l:cmd = "highlight " . a:group
    if a:fg != ""
        let l:cmd .= " guifg=" . a:fg
    endif
    if a:bg != ""
        let l:cmd .= " guibg=" . a:bg
    endif
    if a:attr != ""
        let l:cmd .= " gui=" . a:attr
    endif
    execute l:cmd
endfunction

" ── UI ──
call s:hi("Normal",        s:fg,         s:bg,        "")
call s:hi("NormalFloat",   s:fg,         s:bg_light,  "")
call s:hi("FloatBorder",   s:stone,      s:bg_light,  "")
call s:hi("CursorLine",    "",           s:bg_light,  "NONE")
call s:hi("CursorLineNr",  s:bronze,     s:bg_light,  "bold")
call s:hi("LineNr",        s:stone,      "",          "")
call s:hi("SignColumn",    s:stone,      s:bg,        "")
call s:hi("ColorColumn",   "",           s:bg_dark,   "")
call s:hi("Visual",        "",           "#3a352e",   "")
call s:hi("VisualNOS",     "",           "#3a352e",   "")
call s:hi("Search",        s:bg,         s:gold,      "")
call s:hi("IncSearch",     s:bg,         s:bronze,    "bold")
call s:hi("MatchParen",    s:gold,       s:bg_light,  "bold")

call s:hi("Pmenu",         s:fg,         s:bg_light,  "")
call s:hi("PmenuSel",      s:bg,         s:bronze,    "")
call s:hi("PmenuSbar",     "",           s:bg_light,  "")
call s:hi("PmenuThumb",    "",           s:stone,     "")

call s:hi("StatusLine",    s:fg,         s:bg_light,  "")
call s:hi("StatusLineNC",  s:fg_dark,    s:bg_dark,   "")
call s:hi("TabLine",       s:fg_dim,     s:bg_dark,   "")
call s:hi("TabLineFill",   "",           s:bg_dark,   "")
call s:hi("TabLineSel",    s:fg,         s:bg_light,  "bold")

call s:hi("VertSplit",     s:stone,      s:bg,        "")
call s:hi("Folded",        s:fg_dim,     s:bg_dark,   "italic")
call s:hi("FoldColumn",    s:stone,      s:bg,        "")

call s:hi("NonText",       s:stone,      "",          "")
call s:hi("SpecialKey",    s:stone,      "",          "")
call s:hi("Whitespace",    s:stone,      "",          "")
call s:hi("EndOfBuffer",   s:bg,         "",          "")

call s:hi("ErrorMsg",      s:terracotta, "",          "bold")
call s:hi("WarningMsg",    s:gold,       "",          "bold")
call s:hi("ModeMsg",       s:bronze,     "",          "bold")
call s:hi("MoreMsg",       s:olive,      "",          "")
call s:hi("Question",      s:olive,      "",          "")
call s:hi("Title",         s:bronze,     "",          "bold")
call s:hi("Directory",     s:azure,      "",          "")
call s:hi("WildMenu",      s:bg,         s:bronze,    "")

" ── Diff ──
call s:hi("DiffAdd",       "",           "#2a3025",   "")
call s:hi("DiffChange",    "",           "#2a2820",   "")
call s:hi("DiffDelete",    s:rust,       "#2a2020",   "")
call s:hi("DiffText",      "",           "#3a3525",   "bold")

" ── Sintaxe ──
call s:hi("Comment",       s:fg_dark,    "",          "italic")
call s:hi("Constant",      s:parchment,  "",          "")
call s:hi("String",        s:olive,      "",          "")
call s:hi("Character",     s:olive,      "",          "")
call s:hi("Number",        s:tan,        "",          "")
call s:hi("Boolean",       s:bronze,     "",          "")
call s:hi("Float",         s:tan,        "",          "")

call s:hi("Identifier",    s:fg,         "",          "")
call s:hi("Function",      s:bronze,     "",          "")
call s:hi("Statement",     s:parchment,  "",          "")
call s:hi("Conditional",   s:parchment,  "",          "")
call s:hi("Repeat",        s:parchment,  "",          "")
call s:hi("Label",         s:gold,       "",          "")
call s:hi("Operator",      s:marble,     "",          "")
call s:hi("Keyword",       s:parchment,  "",          "bold")
call s:hi("Exception",     s:terracotta, "",          "")

call s:hi("PreProc",       s:azure,      "",          "")
call s:hi("Include",       s:azure,      "",          "")
call s:hi("Define",        s:azure,      "",          "")
call s:hi("Macro",         s:azure,      "",          "")
call s:hi("PreCondit",     s:azure,      "",          "")

call s:hi("Type",          s:gold,       "",          "")
call s:hi("StorageClass",  s:gold,       "",          "")
call s:hi("Structure",     s:gold,       "",          "")
call s:hi("Typedef",       s:gold,       "",          "")

call s:hi("Special",       s:bronze,     "",          "")
call s:hi("SpecialChar",   s:bronze,     "",          "")
call s:hi("Tag",           s:bronze,     "",          "")
call s:hi("Delimiter",     s:marble,     "",          "")
call s:hi("SpecialComment",s:tan,        "",          "italic")
call s:hi("Debug",         s:terracotta, "",          "")

call s:hi("Underlined",    s:azure,      "",          "underline")
call s:hi("Ignore",        s:stone,      "",          "")
call s:hi("Error",         s:terracotta, s:bg_dark,   "bold")
call s:hi("Todo",          s:gold,       s:bg_dark,   "bold")

" ── Diagnósticos ──
call s:hi("DiagnosticError",   s:terracotta, "", "")
call s:hi("DiagnosticWarn",    s:gold,       "", "")
call s:hi("DiagnosticInfo",    s:azure,      "", "")
call s:hi("DiagnosticHint",    s:olive,      "", "")

" ── Git Signs ──
call s:hi("GitSignsAdd",       s:olive,      "", "")
call s:hi("GitSignsChange",    s:bronze,     "", "")
call s:hi("GitSignsDelete",    s:terracotta, "", "")

" ── Treesitter (nvim 0.8+) ──
call s:hi("@variable",        s:fg,         "", "")
call s:hi("@function",        s:bronze,     "", "")
call s:hi("@function.builtin", s:tan,       "", "")
call s:hi("@keyword",         s:parchment,  "", "bold")
call s:hi("@string",          s:olive,      "", "")
call s:hi("@type",            s:gold,       "", "")
call s:hi("@type.builtin",    s:gold,       "", "italic")
call s:hi("@comment",         s:fg_dark,    "", "italic")
call s:hi("@punctuation",     s:marble,     "", "")
call s:hi("@constant",        s:parchment,  "", "")
call s:hi("@constant.builtin",s:bronze,     "", "")
call s:hi("@property",        s:fg_dim,     "", "")
call s:hi("@parameter",       s:fg,         "", "")
call s:hi("@tag",             s:bronze,     "", "")
call s:hi("@tag.attribute",   s:tan,        "", "")
call s:hi("@tag.delimiter",   s:marble,     "", "")
