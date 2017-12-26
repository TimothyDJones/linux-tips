" Show line numbers
set number

" Change color of line numbers for easier reading
highlight LineNr term=bold cterm=NONE ctermfg=DarkGrey ctermbg=NONE gui=NONE guifg=DarkGrey guibg=NONE

" Highlight matching parentheses
highlight MatchParen ctermbg=4

" Enable <backspace>
set backspace=2

" Convert <Tab> to <Spaces>
set expandtab
set smarttab

" Set tab stops to 4 spaces/characters
set shiftwidth=4
set softtabstop=4

" Enable auto-indent
set autoindent

" Disable Vi compatibility to allow Vim advanced features
set nocompatible

" Display command as you type it
set showcmd

" Enable syntax highlighting
filetype on
filetype plugin on
syntax enable

" Enable English spell-checking, but don't check by default
if version >= 700
    set spl=en spell
    set nospell
endif

" Enable <Tab> completion functions
set wildmenu
set wildmode=list:longest,full

" Enable mouse in console
set mouse=a

" Disable case-sensitivty
set ignorecase

" Enable smart case-sensitivity
set smartcase

" Remap 'jj' to <Esc> in INSERT mode
inoremap jj <Esc>
nnoremap JJJJ <Nop>

" Enable incremental search and search highlighting
set incsearch
set hlsearch

" Show status line and format contents
set laststatus=2
set statusline=%F%m%r%h%w\ (%{&ff}){%Y}\ [%1,%v][%p%%]

" Create blank lines and stay in NORMAL mode
nnoremap <silent> zj o<Esc>
nnoremap <silent> zk O<Esc>

" Center window vertically on line of 'next' search result
map N Nzz
map n nzz

" Put all backup and temporary files in same directory
set backup
set backupdir=~/.vim/backup
set directory=~/.vim/tmp
