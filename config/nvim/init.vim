" ╔══════════════════════════════════════════════════════════════╗
" ║  STOA LINUX — Neovim                                        ║
" ║  "The impediment to action advances action." — M. Aurelius  ║
" ╚══════════════════════════════════════════════════════════════╝

" ── General ──
set termguicolors
set number
set relativenumber
set cursorline
set scrolloff=8
set signcolumn=yes
set mouse=a
set clipboard=unnamedplus
set updatetime=300
set timeoutlen=500

" ── Indentation ──
set expandtab
set shiftwidth=4
set tabstop=4
set smartindent

" ── Search ──
set ignorecase
set smartcase
set hlsearch
set incsearch

" ── Files ──
set noswapfile
set nobackup
set undofile
set undodir=~/.local/share/nvim/undo

" ── Appearance ──
set fillchars=vert:│,fold:─,eob:\
set showmode
set showcmd
set laststatus=2

" ── Stoic Theme ──
colorscheme stoa

" ── Minimalist Statusline ──
set statusline=
set statusline+=\ %{toupper(mode())}
set statusline+=\ │\ %f
set statusline+=%m%r
set statusline+=%=
set statusline+=%{&filetype}
set statusline+=\ │\ %l:%c
set statusline+=\ │\ %p%%\

" ── Leader ──
let mapleader = " "

" ── Keybinds ──
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>h :noh<CR>
nnoremap <leader>e :Explore<CR>

" Split navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Move lines in visual mode
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Center when navigating
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz
nnoremap n nzzzv
nnoremap N Nzzzv
