" Show line numbers
set number

" Wrap text after 80 characters and highlight column 80
set textwidth=80
set colorcolumn=80
highlight ctermbg=DarkGrey guibg=DarkGrey

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
set shiftround          " Automatically round indents to multiple of 'shiftwidth'

" Enable auto-indent
set autoindent smartindent

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
map - :nohlsearch<CR>   " Turn off search highlight with '-'

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

" Change to directory contain file when editing
set autochdir

" Set 1000 commands to undo
set undolevels=1000

" Keep at least 4 lines above and below the current line
set scrolloff=4

" Make cursor behave as expected for long lines
inoremap <Down> <C-o>gj
inoremap <Up> <C-o>gk

" Switch to COMMAND mode from INSERT mode by entering 'ii'
imap ii <C-[>

" Remap <Ctrl>+<Space> to word completion
noremap! <Nul> <C-n>

" Shortcuts for switching between buffers in INSERT mode
map <C-j> :bprev<CR>
map <C-k> :bnext<CR>

" Highlight the word under cursor
highlight flicker cterm=bold ctermfg=white
au CursorMoved <buffer> exe 'match flicker /\V\<'.escape(expand('<cword>'), '/').'\>/'

" Allow saving file owned by root if Vim not opened using sudo
" Tip:  We use the 'w!!' command to follow pattern from shell of '!!' to
"       re-run previous command with sudo.
" https://stackoverflow.com/questions/2600783/how-does-the-vim-write-with-sudo-trick-work
cmap w!! w !sudo tee > /dev/null %
