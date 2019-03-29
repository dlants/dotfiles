call plug#begin('~/.vim/plugged')
set nocompatible " be iMproved, required
filetype off     " required
set t_Co=256
set shell=/bin/bash

" ale and neomake aren't loaded together
" let g:ale_emit_conflict_warnings = 0

Plug 'takac/vim-hardtime'

" language server / typescript
Plug 'neoclide/coc.nvim', {'tag': '*', 'do': { -> coc#util#install()}}

" completion
"Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
" Plug 'Shougo/echodoc.vim'
" Plug 'Shougo/neoinclude.vim' " <- deoplete source for relative / project files
" Plug 'roxma/nvim-completion-manager'

"Plug 'ncm2/ncm2'
" Plug 'roxma/nvim-yarp'

" some completion sources
" Plug 'ncm2/ncm2-bufword'
" Plug 'fgrsnau/ncm2-otherbuf', {'branch': 'ncm2'}
" Plug 'wellle/tmux-complete.vim'
" Plug 'ncm2/ncm2-path'

" files / navigation
" commit because
" https://github.com/jremmen/vim-ripgrep/issues/29
" Plug 'jremmen/vim-ripgrep', {'commit': 'f7c1549c0ba6010a399023e95d86e6274526aeb4'}

Plug 'mhinz/vim-grepper'

" fzf installed through homebrew, to use it with shell commands as well
set rtp+=/usr/local/opt/fzf
Plug 'junegunn/fzf.vim'

" tmux
Plug 'christoomey/vim-tmux-navigator'
" Plug 'benmills/vimux'

" show errors
" Plug 'vim-syntastic/syntastic', {'for': ['purescript', 'idris']}
" Plug 'neomake/neomake'

" status line
" Plug 'bling/vim-airline'
Plug 'itchyny/lightline.vim'

" pretty colors
Plug 'nanotech/jellybeans.vim'
" Plug 'dracula/vim', {'as': 'dracula'}
" Plug 'NLKNguyen/papercolor-theme'

" trim whitespace on save
Plug 'ntpeters/vim-better-whitespace'
"Plug 'Valloric/YouCompleteMe', {'do': './install.py'}

" git
Plug 'mhinz/vim-signify'
" Plug 'airblade/vim-gitgutter'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-rhubarb'

" vim enhancements (motion, repeatability)
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-unimpaired'
Plug 'tpope/vim-abolish'
Plug 'tpope/vim-endwise'
Plug 'tpope/vim-repeat'

" extra objects
Plug 'tpope/vim-surround' " work on surrounding parens, quotes, tags
" Plug 'michaeljsmith/vim-indent-object' " work with indentation levels
" Plug 'wellle/targets.vim' " separators, arguments

" jump around
Plug 'easymotion/vim-easymotion'

" language support
Plug 'dag/vim-fish'
Plug 'ElmCast/elm-vim', {'for': 'elm'}
" Plug 'roxma/ncm-elm-oracle'

" idris
Plug 'idris-hackers/idris-vim', {'for': 'idris'}

" purescript
Plug 'raichoo/purescript-vim', {'for': 'purescript'}
Plug 'frigoeu/psc-ide-vim', {'for': 'purescript'}
"Plug 'coot/psc-ide-vim', {'branch': 'sync-purescript-0.11'}

" Plug 'let-def/ocp-indent-vim'
Plug 'bitc/vim-hdevtools', {'for': 'haskell'}
Plug 'itchyny/vim-haskell-indent', {'for': 'haskell'}
Plug 'eagletmt/neco-ghc', {'for': 'haskell'}

" typescript
" Plug 'leafgarland/typescript-vim', {'for': 'typescript'} " ts syntax highlighting
Plug 'HerringtonDarkholme/yats.vim'
" Plug 'ianks/vim-tsx' " tsx syntax highlighting
" Plug 'Quramy/tsuquyomi'
" Plug 'Quramy/vim-js-pretty-template'
" Plug 'jason0x43/vim-js-indent' " better indentation
" Plug 'mhartington/nvim-typescript', {'do': './install.sh'}
" Plug 'ncm2/nvim-typescript', {'for': 'typescript', 'do': './install.sh'}
" Plug 'w0rp/ale', {'for': ['typescript', 'typescript.tsx', 'elm']}

" post install (yarn install | npm install) then load plugin only for editing supported files
Plug 'prettier/vim-prettier', {
  \ 'do': 'yarn install',
  \ 'for': ['javascript', 'typescript', 'typescript.tsx', 'css', 'less', 'scss', 'json', 'graphql', 'markdown', 'vue'] }

"Plug 'neovim/node-host', { 'branch': 'next'} " , 'do': 'npm install -g neovim@next' }
"Plug 'neovim/node-host', {'do': 'npm install'}
"Plug 'dlants/ts-neovim-ts', {'for': 'typescript', 'do': 'npm install; :UpdateRemotePlugins'}

" Plug 'runoshun/tscompletejob'

" js
Plug 'pangloss/vim-javascript'
Plug 'mtscout6/vim-cjsx'
Plug 'iloginow/vim-stylus'
Plug 'kchmck/vim-coffee-script'
Plug 'elzr/vim-json'
Plug 'digitaltoad/vim-jade', {'for': 'pug'}

" racket
Plug 'wlangstroth/vim-racket', {'for': 'racket'}

" reason
Plug 'reasonml-editor/vim-reason-plus' , {'for': ['reasonml', 'ocaml']}

" prose
Plug 'reedes/vim-pencil'

" LanguageClient
"Plug 'autozimu/LanguageClient-neovim', {
"    \ 'branch': 'next',
"    \ 'do': 'bash install.sh',
"    \ 'for': ['reasonml', 'ocaml']
"    \ }

call plug#end()

filetype plugin indent on " required
" ---------- Other config ------------
" basics
let mapleader = " "
let maplocalleader = "\\"
syntax enable
set synmaxcol=200


"au BufNewFile,BufRead *.es6 setf javascript.jsx
au BufNewFile,BufRead *.jade setf pug

set background=dark
set nowrap
set number
" set relativenumber
set cursorline
set cursorcolumn
set colorcolumn=120
set noshowmode

" change highlight colors

" default register is clipboard
set clipboard=unnamed

" tabs and spaces!
set tabstop=2
set shiftwidth=2
set softtabstop=0
set expandtab

" command line completion
set wildmode=list:longest
set wildmenu

" faster pane resize
" noshift resizes vertically
nnoremap <leader>= :resize +5<CR>
nnoremap <leader>- :resize -5<CR>
" with shift resizes horizontally
nnoremap <leader>+ :vertical resize +5<CR>
nnoremap <leader>_ :vertical resize -5<CR>

" vimux (vim + tmux)
" open in a horizontal split ( like | )
" let g:VimuxOrientation = "h"
" let g:VimuxHeight = "50"

let g:signify_vcs_list = [ 'git' ]

" opens a tmux split and opens ranger (for manipulating files)
" nnoremap <leader>tr :call VimuxRunCommandInDir("ranger", 0)<CR>

" open a tmux pane and run zsh
" nnoremap <leader>tz :VimuxRunCommand("zsh")<CR>

" send stuff to tmux pane
" function! VimuxSlime()
" call VimuxSendText(@v)
" call VimuxSendKeys("Enter")
" endfunction

" If text is selected, save it in the v buffer and send that buffer it to tmux
" vmap <LocalLeader>vs "vy :call VimuxSlime()<CR>

" Select current paragraph and send it to tmux
" nmap <LocalLeader>vs vip<LocalLeader>vs<CR>

" [] followed by j to jump forward or back in history
nnoremap [j <C-O>
nnoremap ]j <C-I>

" quickfix always takes up full width
au FileType qf wincmd J

" search
set ignorecase
set smartcase
set incsearch
set hlsearch

" hardtime
let g:hardtime_default_on = 1
let g:hardtime_ignore_quickfix = 1
let g:hardtime_ignore_buffer_patterns= ["fzf"]

" python support
let g:python_host_prog = '/usr/bin/python2.7'
let g:python3_host_prog = '/Library/Frameworks/Python.framework/Versions/3.5/bin/python3.5'

" ncm2
" enable for all buffers
" autocmd BufEnter * call ncm2#enable_for_buffer()

set shortmess+=c " suppress 'x of y' messages
set completeopt=noinsert,menuone,noselect

" ctrl-c doesn't trigger the InsertLeave autocmd . map to <ESC> instead.
inoremap <c-c> <ESC>

" Tab selects popup
" inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
" inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" pencil filetype detection
augroup pencil
  autocmd!
  autocmd FileType markdown,mkd call pencil#init()
  autocmd FileType text         call pencil#init()
augroup END

" complete stylus
" call ncm2#register_source({'name' : 'stylus',
"             \ 'priority': 9,
"             \ 'subscope_enable': 1,
"             \ 'scope': ['stylus'],
"             \ 'mark': 'styl',
"             \ 'word_pattern': '[\w\-]+',
"             \ 'complete_pattern': ':\s*',
"             \ 'on_complete': ['ncm2#on_complete#omni',
"             \               'stylcomplete#CompleteStyl'],
"             \ })
"
" easymotion bindings
map <Leader>f <Plug>(easymotion-bd-f)
map <Leader>t <Plug>(easymotion-bd-t)
map <Leader>w <Plug>(easymotion-bd-w)
map <Leader>b <Plug>(easymotion-bd-w)
map <Leader>j <Plug>(easymotion-j)
map <Leader>k <Plug>(easymotion-k)
map <Leader>n <Plug>(easymotion-n)
map <Leader>N <Plug>(easymotion-N)
map <Leader>/ <Plug>(easymotion-sn)
omap <Leader>/ <Plug>(easymotion-tn)
map s <Plug>(easymotion-s)
map S <Plug>(easymotion-s2)

let g:EasyMotion_smartcase = 1
let g:EasyMotion_use_smartsign_us = 1

" au User CmSetup call cm#register_source({'name': 'cm-purescript',
"         \ 'priority': 9,
"         \ 'scoping': 1,
"         \ 'scopes': ['purescript'],
"         \ 'abbreviation': 'purs',
"         \ 'word_pattern': '[\w\-]+',
"         \ 'cm_refresh_patterns':['[\w\-]+\s*:\s+'],
"         \ 'cm_refresh': {'omnifunc': 'PSCIDEomni'},
"         \ })

" ale
" let g:ale_linters = {
"   \ 'typescript': ['tslint']
"   \ }
"
" let g:ale_fixers = {
"   \ 'typescript': ['tslint']
"   \}
"
" let g:ale_set_loclist=0
" let g:ale_set_quickfix=0
"
" let g:ale_lint_on_text_changed = 'never'

" Prettier async format on save
let g:prettier#autoformat = 0
let g:prettier#quickfix_enabled = 0
nmap <Leader>` <Plug>(Prettier)

" format on save
" autocmd BufWritePre *.js,*.jsx,*.mjs,*.ts,*.tsx,*.css,*.less,*.scss,*.json,*.graphql,*.md,*.vue PrettierAsync

" deoplete + echodoc
" let g:deoplete#enable_at_startup = 1
" let g:deoplete#enable_smart_case = 1
" let g:deoplete#enable_camel_case = 1
" let g:deoplete#file#enable_buffer_path = 1
" "
" let g:deoplete#omni#input_patterns = {}
" let g:deoplete#omni#input_patterns.default = '\h\w*'

" don't pop up the preview window
set completeopt-=preview
"let g:deoplete#omni#input_patterns.purescript = '[^. *\t]'
autocmd CompleteDone * pclose!

" LanguageClient configuration
let g:LanguageClient_serverCommands = {
    \ 'reason': ['ocaml-language-server', '--stdio'],
    \ 'ocaml': ['ocaml-language-server', '--stdio'],
    \ }

"    \ 'typescript': ['typescript-language-server', '--stdio'],
let g:LanguageClient_diagnosticsList = "Location"

" let g:LanguageClient_rootMarkers = {
"   \ 'typescript': ['tsconfig.json']
"   \ }

autocmd FileType ocaml nnoremap <silent> <leader>t :call LanguageClient_textDocument_hover()<cr>
autocmd FileType ocaml nnoremap <silent> <leader>d :call LanguageClient_textDocument_definition()<cr>
autocmd FileType ocaml nnoremap <silent> <leader>D :call LanguageClient_textDocument_typeDefinition()<cr>
autocmd FileType ocaml nnoremap <silent> <leader>r :call LanguageClient_textDocument_references()<cr>
autocmd FileType ocaml nnoremap <silent> <leader>R :call LanguageClient_textDocument_rename()<cr>
autocmd FileType ocaml nnoremap <silent> <leader>` :call LanguageClient_textDocument_formatting()<cr>

autocmd FileType reason nnoremap <silent> <leader>t :call LanguageClient_textDocument_hover()<cr>
autocmd FileType reason nnoremap <silent> <leader>d :call LanguageClient_textDocument_definition()<cr>
autocmd FileType reason nnoremap <silent> <leader>D :call LanguageClient_textDocument_typeDefinition()<cr>
autocmd FileType reason nnoremap <silent> <leader>r :call LanguageClient_textDocument_references()<cr>
autocmd FileType reason nnoremap <silent> <leader>R :call LanguageClient_textDocument_rename()<cr>
autocmd FileType reason nnoremap <silent> <leader>` :call LanguageClient_textDocument_formatting()<cr>

" neomake
" let g:neomake_verbose = 3
" autocmd! BufWritePost * Neomake

" syntastic recommended
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 2
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

" fzf
" position
let g:fzf_layout = {'up': '~50%'}
nnoremap <leader>p :GFiles<CR>
nnoremap <leader>o :Files<CR>

" Mapping selecting mappings
nmap <leader><tab> <plug>(fzf-maps-n)
xmap <leader><tab> <plug>(fzf-maps-x)
omap <leader><tab> <plug>(fzf-maps-o)

" Insert mode completion
imap <c-x><c-k> <plug>(fzf-complete-word)
imap <c-x><c-f> <plug>(fzf-complete-path)
imap <c-x><c-j> <plug>(fzf-complete-file-ag)
imap <c-x><c-l> <plug>(fzf-complete-line)

" Rg
" let g:rg_highlight = 1
" let g:rg_derive_root = 1
" cmap Gg Rg

" grepper
runtime plugin/grepper.vim    " initialize g:grepper with default values
let g:grepper.prompt_quote = 2
let g:grepper.tools = ['rg']
nnoremap <leader>g :Grepper<CR>

" javascript
let g:jsx_ext_required = 0 " allow jsx in all files

" typescript
" disable maker for typescript -- we use nvim-typescript for this
" let g:neomake_typescript_enabled_makers = []
" let g:typescript_indent_disable = 1
" let g:nvim_typescript#diagnosticsEnable = 1
" let g:nvim_typescript#refs_to_loc_list = 1

" run TSSyncErr on write
" autocmd! BufWritePost *.ts,*.tsx TSSyncErr
" autocmd FileType typescript nmap <buffer> <Leader>n :TSRename<CR>
" autocmd FileType typescript nmap <buffer> <Leader>t :TSType<CR>
" autocmd FileType typescript nmap <buffer> <Leader>T :TSDoc<CR>
" autocmd FileType typescript nmap <buffer> <Leader>d :TSDef<CR>
" autocmd FileType typescript nmap <buffer> <Leader>D :TSTypeDef<CR>
" autocmd FileType typescript nmap <buffer> <Leader>r :TSRefs<CR>
"
" autocmd FileType typescript.tsx nmap <buffer> <Leader>n :TSRename<CR>
" autocmd FileType typescript.tsx nmap <buffer> <Leader>t :TSType<CR>
" autocmd FileType typescript.tsx nmap <buffer> <Leader>T :TSDoc<CR>
" autocmd FileType typescript.tsx nmap <buffer> <Leader>d :TSDef<CR>
" autocmd FileType typescript.tsx nmap <buffer> <Leader>D :TSTypeDef<CR>
" autocmd FileType typescript.tsx nmap <buffer> <Leader>r :TSRefs<CR>

" coc
" Use tab for trigger completion with characters ahead and navigate.
" Use command ':verbose imap <tab>' to make sure tab is not mapped by other plugin.
inoremap <expr> <TAB> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"



function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use <cr> for confirm completion, `<C-g>u` means break undo chain at current position.
" Coc only does snippet and additional edit on confirm.
" inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"

" Use `[c` and `]c` for navigate diagnostics
nmap <silent> <Leader>e <Plug>(coc-diagnostic-info)
nmap <silent> [c <Plug>(coc-diagnostic-prev)
nmap <silent> ]c <Plug>(coc-diagnostic-next)

" Remap keys for gotos
nmap <silent> <Leader>d <Plug>(coc-definition)
nmap <silent> <Leader>D <Plug>(coc-type-definition)
nmap <silent> <Leader>i <Plug>(coc-implementation)
nmap <silent> <Leader>r <Plug>(coc-references)

" Use K for show documentation in preview window
nnoremap <silent> <Leader>t :call <SID>show_documentation()<CR>

function! s:show_documentation()
  if &filetype == 'vim'
    execute 'h '.expand('<cword>')
  else
    call CocAction('doHover')
  endif
endfunction

" Highlight symbol under cursor on CursorHold
autocmd CursorHold * silent call CocActionAsync('highlight')

" Remap for rename current word
nmap <leader>rn <Plug>(coc-rename)

" Add diagnostic info for https://github.com/itchyny/lightline.vim
let g:lightline = {
      \ 'colorscheme': 'jellybeans',
      \ 'active': {
      \   'left': [ [ 'mode', 'paste' ],
      \             [ 'gitbranch', 'cocstatus', 'readonly', 'relativepath', 'modified' ] ]
      \ },
      \ 'component_function': {
      \   'cocstatus': 'coc#status',
      \   'gitbranch': 'fugitive#head'
      \ },
      \ }

" Using CocList
" Show all diagnostics
"nnoremap <silent> <space>a  :<C-u>CocList diagnostics<cr>
"" Manage extensions
"nnoremap <silent> <space>e  :<C-u>CocList extensions<cr>
"" Show commands
"nnoremap <silent> <space>c  :<C-u>CocList commands<cr>
"" Find symbol of current document
"nnoremap <silent> <space>o  :<C-u>CocList outline<cr>
"" Search workspace symbols
"nnoremap <silent> <space>s  :<C-u>CocList -I symbols<cr>
"" Do default action for next item.
"nnoremap <silent> <space>j  :<C-u>CocNext<CR>
"" Do default action for previous item.
"nnoremap <silent> <space>k  :<C-u>CocPrev<CR>
"" Resume latest coc list
"nnoremap <silent> <space>p  :<C-u>CocListResume<CR>
"" end coc
"
" elm-vim
" formatd elm on save
let g:elm_jump_to_error = 1
let g:elm_format_autosave = 1
let g:elm_detailed_complete = 1
" let g:elm_syntastic_show_warnings = 1
" autocmd FileType elm nmap <buffer> <Leader>x :ALEFix<CR>
autocmd FileType elm nmap <buffer> <Leader>d :ElmBrowseDocs<CR>
autocmd FileType elm nmap <buffer> <Leader>t :ElmShowDocs<CR>
autocmd FileType elm nmap <buffer> <Leader>T :ElmTest<CR>
autocmd FileType elm nmap <buffer> <Leader>e :ElmErrorDetail<CR>
autocmd FileType elm nmap <buffer> <Leader>f :ElmFormat<CR>
autocmd FileType elm nmap <buffer> <Leader>m :ElmMake<CR>
autocmd FileType elm nmap <buffer> <Leader>M :ElmMakeMain<CR>

" psc-ide-vim
let g:psc_ide_syntastic_mode = 0
let g:psc_ide_server_port = 4088
" let g:psc_ide_log_level = 3
let g:neomake_purescript_enabled_makers = []

au FileType purescript nmap <leader>b :!pulp build<CR>
" au FileType purescript nmap <leader>e :Neomake<CR>
au FileType purescript nmap <leader>i :sp<CR>:terminal<CR>psci<CR>
au FileType purescript nmap <leader>t :Ptype<CR>
au FileType purescript nmap <leader>s :Papply<CR>
au FileType purescript nmap <leader>a :PaddType<CR>
au FileType purescript nmap <leader>c :PaddClause<CR>
au FileType purescript nmap <leader>d :Pgoto<CR>
au FileType purescript nmap <leader>m :Pimport<CR>

" better whitespace
" strip whitespace on save
autocmd BufWritePre * StripWhitespace

" load colorscheme last...
colorscheme jellybeans
" colorscheme dracula
" colorscheme PaperColor

" neovim stuff
" faster esc
" set esckeys
set nottimeout

" weird characters bug
" https://github.com/neovim/neovim/issues/7002
" https://github.com/neovim/neovim/wiki/FAQ#nvim-shows-weird-symbols-2-q-when-changing-modes
set guicursor=
" Workaround some broken plugins which set guicursor indiscriminately.
autocmd OptionSet guicursor noautocmd set guicursor=

" something was overriding escape ... wtf
nnoremap <Esc> <Esc>
nnoremap - -

" psc-ide-vim debugging
"let g:psc_ide_log_level = 3

" nvim-typescript debugging
" let g:deoplete#enable_debug = 1
" let g:deoplete#enable_profile = 1
" call deoplete#enable_logging('DEBUG', '/tmp/deoplete.log')

" Syntax debugging
function! SynStack()
  if !exists("*synstack")
    return
  endif
  echo map(synstack(line('.'), col('.')), 'synIDattr(v:val, "name")')
endfunc
