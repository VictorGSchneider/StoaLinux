" ╔══════════════════════════════════════════════════════════════╗
" ║  STOA LINUX — Neovim                                        ║
" ║  "O impedimento à ação avança a ação." — Marco Aurélio      ║
" ╚══════════════════════════════════════════════════════════════╝

" ── Geral ──
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

" ── Indentação ──
set expandtab
set shiftwidth=4
set tabstop=4
set smartindent

" ── Busca ──
set ignorecase
set smartcase
set hlsearch
set incsearch

" ── Arquivos ──
set noswapfile
set nobackup
set undofile
set undodir=~/.local/share/nvim/undo

" ── Aparência ──
set fillchars=vert:│,fold:─,eob:\
set showmode
set showcmd
set laststatus=2

" ── Tema Estoico ──
colorscheme stoa

" ── Statusline Minimalista ──
set statusline=
set statusline+=\ %{toupper(mode())}
set statusline+=\ │\ %f
set statusline+=%m%r
set statusline+=%=
set statusline+=%{&filetype}
set statusline+=\ │\ %l:%c
set statusline+=\ │\ %p%%\

" ── Líder ──
let mapleader = " "

" ── Atalhos ──
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>h :noh<CR>
nnoremap <leader>e :Explore<CR>

" Navegação entre splits
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Mover linhas em modo visual
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Centralizar ao navegar
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz
nnoremap n nzzzv
nnoremap N Nzzzv
