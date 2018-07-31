" Enable 256 colors
set t_Co=256

" Show line numbers
set number relativenumber

" Wrap text after 80 characters and highlight column 80
set textwidth=80
highlight ColorColumn ctermbg=LightGrey guibg=LightGrey
set colorcolumn=80

" Change color of line numbers for easier reading
highlight LineNr term=bold cterm=NONE ctermfg=DarkGrey ctermbg=NONE gui=NONE guifg=DarkGrey guibg=NONE

" Highlight EOL, extends, precedes and special characters like non-breaking spaces, <Tab>, trailing spaces, etc.
highlight NonText ctermfg=LightGrey guifg=LightGrey
highlight SpecialKey ctermfg=LightGrey guifg=LightGrey

" Highlight matching parentheses
highlight MatchParen ctermbg=4
set matchpairs=(:),{:},[:]

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

" Enable code folding/collapsing
set foldenable
set foldnestmax=10      " 10 nested fold max
set foldlevelstart=10   " open most folds by default
set foldmethod=syntax   " fold based on indent level
" space open/closes folds
nnoremap <space> za

" Remap 'jj' to <Esc> in INSERT mode
inoremap jj <Esc>
nnoremap JJJJ <Nop>

" Enable incremental search and search highlighting
set incsearch
set hlsearch
map - :nohlsearch<CR>   " Turn off search highlight with '-'

" Show status line and format contents
set laststatus=2
" set statusline=%F%m%r%h%w\ (%{&ff}){%Y}\ [%1\ %v][%p%%]
set statusline=%<%f\                      " Filename
set statusline+=%w%h%m%r                  " Options
set statusline+=\ [%{&ff}/%Y]             " filetype
set statusline+=\ [%{getcwd()}]           " current directory
set statusline+=\ [A=\%03.3b/H=\%02.2B]   " ASCII / Hex value of character at cursor
set statusline+=%=%-14.(%l,%c%V%)\ %p%%   " Right aligned file position info

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

" Toggle between regular and relative line numbering when in INSERT mode.
au InsertEnter * :set norelativenumber
au InsertLeave * :set relativenumber

" Disable auto-indent for top-level HTML tags.
let g:html_indent_autotags = "html,head,body"

" <Alt> + arrow navigation
" https://github.com/pyk/dotfiles/blob/master/vim/.vimrc
nmap <silent> <A-Up>    : wincmd k<CR>
nmap <silent> <A-Down>  : wincmd j<CR>
nmap <silent> <A-Left>  : wincmd h<CR>
nmap <silent> <A-Right> : wincmd l<CR>

" Strip trailing whitespaces on each save
" https://github.com/hukl/dotfiles/blob/master/.vimrc#L40
fun! <SID>StripTrailingWhitespaces()
    let l = line(".")
    let c = col(".")
    %s/\s\+$//e
    call cursor(l, c)
endfun
autocmd BufWritePre * :call <SID>StripTrailingWhitespaces()
