let mapleader = "\<space>"

call plug#begin()
Plug 'preservim/nerdtree'
Plug 'tpope/vim-vinegar'
Plug 'tpope/vim-surround'             " 括弧の変更や削除を容易にする
Plug 'tpope/vim-repeat'               " ドットコマンドをプラグインでも利用可能に
Plug 'tpope/vim-unimpaired'
Plug 'tpope/vim-abolish'              " 強化版substitute
Plug 'bkad/CamelCaseMotion'
Plug 'ctrlpvim/ctrlp.vim'             " ファジーファインダー
Plug 'mattn/ctrlp-matchfuzzy'         " 高速なCtrlP matcher
Plug 'mileszs/ack.vim'                " vimからackの結果を取り扱う
Plug 'easymotion/vim-easymotion'      " カーソル移動を便利にする
Plug 'junegunn/vim-plug'              " プラグイン管理
Plug 'simnalamburt/vim-mundo'         " undoツリー可視化
Plug 'tpope/vim-fugitive'             " Gitプラグイン
Plug 'airblade/vim-gitgutter'         " Gitの差分を行番号に表示
Plug 'christoomey/vim-tmux-navigator' " ペインとウィンドウ間のシームレスな移動キーマッピング
Plug 'vim-airline/vim-airline'        " ステータスバーをカスタマイズ
Plug 'vim-airline/vim-airline-themes' " vim-airlineのテーマ集
Plug 'cohama/lexima.vim'              " 閉じ括弧自動入力
Plug 'andymass/vim-matchup'           " %移動を強化
Plug 'kamykn/spelunker.vim'           " スペルチェッカー
Plug 'junegunn/vim-easy-align'        " 文字列整列
Plug 'tpope/vim-commentary'           " コメントアウト
Plug 'skanehira/translate.vim'        " 翻訳
Plug 'nelstrom/vim-visual-star-search' "現在の選択範囲を検索
Plug 'iamcco/markdown-preview.nvim', { 'do': { -> mkdp#util#install() }, 'for': ['markdown', 'vim-plug'] }   " Markdownプレビュー
Plug 'thinca/vim-quickrun', {'on': 'QuickRun'}
Plug 'Shougo/vimproc.vim', {'do': 'make'}
Plug 'vim-denops/denops.vim'    " DenoでVimプラグインを開発するためのプラグイン
Plug 'simeji/winresizer'
Plug 'mattn/vim-goimports'
Plug 'mattn/vim-goaddtags'
Plug 'mattn/vim-goimpl'
Plug 'doums/darcula'
Plug 'osyo-manga/vim-jplus'

Plug 'kana/vim-textobj-user'
Plug 'osyo-manga/vim-textobj-multiblock'
Plug 'sgur/vim-textobj-parameter'
Plug 'vim-scripts/argtextobj.vim'
Plug 'osyo-manga/vim-textobj-from_regexp'
Plug 'glts/vim-textobj-comment'

Plug 'Shougo/ddc.vim' " 補完
Plug 'Shougo/ddc-ui-native'
Plug 'Shougo/ddc-around'
Plug 'Shougo/ddc-matcher_head'
Plug 'Shougo/ddc-sorter_rank'
Plug 'shun/ddc-vim-lsp'
Plug 'matsui54/denops-popup-preview.vim'
Plug 'matsui54/denops-signature_help'
Plug 'LumaKernel/ddc-file'

Plug 'prabirshrestha/vim-lsp'
Plug 'mattn/vim-lsp-settings'
Plug 'mattn/vim-lsp-icons'
Plug 'hrsh7th/vim-vsnip'
Plug 'hrsh7th/vim-vsnip-integ'
call plug#end()

call ddc#custom#patch_global('ui', 'native')
call ddc#custom#patch_global('sources', [
            \ 'vim-lsp',
            \ 'file',
            \ 'around'
         \ ])
call ddc#custom#patch_global('sourceOptions', {
            \ 'vim-lsp': {
                \ 'mark': 'lsp',
                \ 'dup': v:true,
                \ 'forceCompletionPattern': "\\.|://s*|->",
                \ 'minAutoCompleteLength': 1,
            \},
            \ 'around': {'mark': 'A'},
            \ 'file': {
                \ 'mark': 'file',
                \ 'isVolatile': v:true,
                \ 'forceCompletionPattern': '\S/\S*',
            \},
            \ '_': {
                \ 'matchers': ['matcher_head'],
                \ 'sorters': ['sorter_rank'],
                \ 'ignoreCase': v:true
            \ },
        \ })
call ddc#custom#patch_global('sourceParams', {
            \ 'around': {'maxSize': 500},
        \ })
call ddc#custom#patch_filetype(
            \ ['ps1', 'dosbatch', 'autohotkey', 'registry'], 
            \ {
                \ 'sourceOptions': {
                    \ 'file': {
                        \ 'forceCompletionPattern': '\S\\\S*',
                    \ },
                \ },
                \ 'sourceParams': {
                    \ 'file': {
                        \ 'mode': 'win32',
                    \ }
                \ }
            \ }
        \ )

inoremap <silent><expr> <tab>
            \ ddc#map#pum_visible() ? '<down>' :
            \ (col('.') <= 1 <Bar><Bar> getline('.')[col('.') - 2] =~# '\s') ?
            \ '<tab>' : ddc#map#manual_complete()
inoremap <expr> <s-tab> ddc#map#pum_visible() ? '<up>' : '<c-h>'
call ddc#enable()

let g:lexima_no_default_rules = 1
call lexima#set_default_rules()
call lexima#insmode#map_hook('before', '<cr>', '')

"ctrl-p settings
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_show_hidden = 1
if exists('*matchfuzzy')
    let g:ctrlp_match_func = { 'match': 'ctrlp_matchfuzzy#matcher' }
endif

" vim-easy-align settings
xmap ga <plug>(EasyAlign)
nmap ga <plug>(EasyAlign)

" CamelCaseMotion settings
let g:camelcasemotion_key = '<leader>'
map <silent> w <Plug>CamelCaseMotion_w
map <silent> b <Plug>CamelCaseMotion_b
map <silent> e <Plug>CamelCaseMotion_e
map <silent> ge <Plug>CamelCaseMotion_ge
sunmap w
sunmap b
sunmap e
sunmap ge
omap <silent> iw <Plug>CamelCaseMotion_iw
xmap <silent> iw <Plug>CamelCaseMotion_iw
omap <silent> ib <Plug>CamelCaseMotion_ib
xmap <silent> ib <Plug>CamelCaseMotion_ib
omap <silent> ie <Plug>CamelCaseMotion_ie
xmap <silent> ie <Plug>CamelCaseMotion_ie

" spelunker.vim settings
set nospell
autocmd ColorScheme *
    \ highlight SpelunkerSpellBad cterm=underline ctermfg=247 gui=underline guifg=#9e9e9e |
    \ highlight SpelunkerComplexOrCompoundWord cterm=underline ctermfg=NONE gui=underline guifg=NONE

" vim-textobj-from-regexpの設定
omap <expr> <plug>(textobj-if-then)
\   textobj#from_regexp#mapexpr('if\s*\zs\_.\{-}\ze\s*{')
vmap <expr> <plug>(textobj-if-then)
\   textobj#from_regexp#mapexpr('if\s*\zs\_.\{-}\ze\s*{')

omap i<a-w> <plug>(textobj-if-then)
xmap i<a-w> <plug>(textobj-if-then)

" NERDTree settings
nnoremap <silent> <c-n> :NERDTreeFind<cr>
let g:NERDTreeShowBookmarks = 1
let NERDTreeShowHidden = 1
autocmd StdinReadPre * let s:std_in = 1 
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists('s:std_in') |
    \ execute 'NERDTree' argv()[0] | wincmd p | enew | execute 'cd '.argv()[0] | endif

" vim-lsp settings
if !empty(globpath(&rtp, 'autoload/lsp.vim'))
    function! s:on_lsp_buffer_enabled() abort
        setlocal omnifunc=lsp#complete
        setlocal signcolumn=yes
        nmap <buffer> <f4> <plug>(lsp-definition)
        nmap <buffer> <leader>d <plug>(lsp-definition)
        nmap <buffer> <f7> <plug>(lsp-references)
        nmap <buffer> <leader>r <plug>(lsp-references)
        nmap <buffer> <leader>i <plug>(lsp-implementation)
        nmap <buffer> <leader>f <plug>(lsp-type-definition)
        nmap <buffer> <s-f6> <plug>(lsp-rename)
        nmap <buffer> <leader>n <plug>(lsp-rename)
        nmap <buffer> [g <plug>(lsp-previous-diagnostic)
        nmap <buffer> ]g <plug>(lsp-next-diagnostic)
        nmap <buffer> <c-q> <plug>(lsp-hover) " bash_profileにstty start undefとstty stop undefを記述する必要有
        nmap <buffer> <leader>k <plug>(lsp-hover) 
        nnoremap <buffer> <expr><c-f> lsp#scroll(+4)
        nnoremap <buffer> <expr><c-d> lsp#scroll(-4)
    endfunction

    augroup lsp_install
        au!
        autocmd User lsp_buffer_enabled call s:on_lsp_buffer_enabled()
    augroup END
    command! LspDebug let lsp_log_verbose=1 | let lsp_log_file = expand('~/lsp.log')

    autocmd BufWritePre * silent! :LspDocumentFormatSync<cr>
    let g:goimports = 1

    let g:lsp_log_verbose = 0
    let g:lsp_log_file = ""
    let g:lsp_diagnostics_enabled = 1
    let g:lsp_diagnostics_echo_cursor = 1
    let g:asyncomplete_auto_popup = 1
    let g:asyncomplete_auto_completeopt = 0
    let asyncomplete_popup_delay = 0
    let g:lsp_text_edit_enabled = 1
endif

" vim-quickrun settings
nnoremap <silent><leader>q :QuickRun<cr>
let g:quickrun_config = {}
let g:quickrun_config._ = {
    \ 'outputter/error/success': 'buffer',
    \ 'outputter/error/error': 'quickfix',
    \ 'outputter/quickfix/open_cmd': 'copen',
    \ 'runner': 'vimproc',
    \ 'runner/vimproc/updatetime': 60,
    \ 'hook/time/enable': 1
    \ }
let g:quickrun_config.cpp = {
    \ 'command': 'g++',
    \ 'input': 'input', 
    \ 'runner': 'system'
    \ }

" winresizer settings
let g:winresizer_vert_resize = 3
let g:winresizer_horiz_resize = 1

" jplus.vim settings
nmap <leader>j <Plug>(jplus-getchar)
vmap <leader>j <Plug>(jplus-getchar)

" 挿入モードのカーソルを変更する
let &t_ti .= "\e[1 q"
let &t_SI .= "\e[5 q"
let &t_EI .= "\e[1 q"
let &t_te .= "\e[0 q"

if !has('nvim')
    set nocompatible                     " viとの互換性なし
    filetype plugin indent on
    syntax on                            " シンタックスハイライトを有効化
    set autoindent                       " 前の行のインデントを補zの
    set backspace=indent,eol,start       " 近代的なバックスペースの振る舞い
    set belloff=all                      " ベルを無効化
    set cscopeverbose                    " cscopeの出力を冗長化
    set complete-=i                      " 現在のファイルとインクルードされるファイルから補完しない
    set display=lastline                 " より多くのメッセージテキストを表示
    set encoding=utf-8
    set fenc=utf8
    set fillchars=vert:\|,fold:\         " セパレータ
    set formatoptions=tcqj               " より直感的なオートフォーマット
    set fsync                            " fscyn()を使った強固なファイル保存
    set history=10000                    " コマンド履歴を多く保存
    set hlsearch                         " 検索結果をハイライト
    set incsearch                        " インクリメンタルサーチ
    set langnoremap                      " マッピングが壊れるのを防ぐ手助けとなる
    set laststatus=2                     " 常にステータスラインを表示
    set nrformats=bin,hex                " <c-a>と<c-x>のための設定
    set ruler                            " 現在行を画面隅に表示
    set sessionoptions-=options          " セッションごとにオプションを持ち越さない
    set shortmess=F                      " より簡潔なファイル情報
    set sidescroll=1                     " スムーズな横方向のスクロール
    set scrolloff=5
    set smarttab                         " Tabキーを押した時の挙動の設定
    set tabpagemax=50                    " -pフラグで開かれるタブの上限
    set tags=./tags;,tags                " タグコマンドが探すファイル名
    set ttimeoutlen=50                   " キーシークエンスで次のキーを待つミリ秒数
    set ttyfast                          " 接続を高速に
    set viminfo+=!                       " セッションにグローバル変数を保存
    set wildmenu                         " 強化されたコマンドライン補完
    set ttymouse=xterm2
endif

set ignorecase                   " 検索時に大文字小文字を区別しない
set smartcase                    " 検索時に大文字を入力した場合,大文字小文字を区別する
set completeopt=menuone,noinsert " 補完1つでもポップアップ表示,マッチしたテキストが選択されるまで挿入しない
set textwidth=0
set clipboard+=unnamed           " 無名レジスタに入るデータを*レジスタにも入れる
set shortmess-=S                 " 検索時にマッチ数等を表示する
set number                       " 行番号を表示
set relativenumber               " 行番号を相対値に
set hidden                       " 編集中ファイルを保存しなくてもbufferを切り替え可能に
set autoread                     " 編集中のファイルが変更されたら自動で読み直す
set tabstop=4                    " tabをスペース4つ分に
set expandtab                    " tabを押したときにスペースを入力する
set shiftwidth=4                 " インデントのスペースの数
set softtabstop=-1               " Tabとしてカウントされるスペースの数をshiftwidthと同一に
set smartindent                  " インデントを考慮して改行
set cindent
set foldcolumn=1
set cursorline                   " 現在の行を強調表示
set linebreak
set virtualedit=block            " 矩形選択時にテキストがないところも選択可能に
set history=200
set mouse=a
set title
set showcmd
set confirm
silent! helptags ALL

" タブや空白,改行等を可視化
set list
set listchars=tab:»-,trail:-,eol:↲,extends:»,precedes:«,nbsp:% 
autocmd ColorScheme * highlight NonText    ctermbg=NONE ctermfg=59 guibg=NONE guifg=NONE
autocmd ColorScheme * highlight SpecialKey ctermbg=NONE ctermfg=59 guibg=NONE guifg=NONE

let g:airline_theme = 'simple'
colorscheme darcula
set termguicolors
highlight Constant cterm=NONE

let swapPath = expand("$HOME/.vim/swap//")
if !isdirectory(swapPath)
    call mkdir(swapPath, 'p')
endif
let &directory=swapPath

let backupPath = expand("$HOME/.vim/backup//")
if !isdirectory(backupPath)
    call mkdir(backupPath, 'p')
endif
let &backupdir=backupPath

" すべてのファイルについて永続undoを有効化
if has('persistent_undo')
    let undoPath = expand("$HOME/.vim/undo//")
    if !isdirectory(undoPath)
        call mkdir(undoPath, 'p')
    endif
    set undofile
    let &undodir=undoPath
endif

noremap <c-h> <c-w><c-h>
noremap <c-j> <c-w><c-j>
noremap <c-k> <c-w><c-k>
noremap <c-l> <c-w><c-l>
noremap <c-w><c-h> <c-w>H
noremap <c-w><c-j> <c-w>J
noremap <c-w><c-k> <c-w>K
noremap <c-w><c-l> <c-w>L
tnoremap <c-h> <c-w><c-h>
tnoremap <c-j> <c-w><c-j>
tnoremap <c-k> <c-w><c-k>
tnoremap <c-l> <c-w><c-l>
tnoremap <c-w><c-h> <c-w>H
tnoremap <c-w><c-j> <c-w>J
tnoremap <c-w><c-k> <c-w>K
tnoremap <c-w><c-l> <c-w>L

nnoremap j gj
nnoremap k gk
nnoremap GT gT
nnoremap GG G

inoremap <c-h> <left>
inoremap <c-j> <down>
inoremap <c-k> <up>
inoremap <c-l> <right>

noremap <leader>w :w<cr>
noremap <leader>, :so $MYVIMRC<cr>
noremap <f5> :MundoToggle<cr>
nnoremap <space> <nop>
nnoremap * *N
nnoremap U <c-r>
nnoremap & :&&<cr>
xnoremap & :&&<cr>
noremap : ;
noremap ; :
tnoremap <c-w>: <c-w>;
tnoremap <c-w>; <c-w>:
nnoremap <silent> <esc><esc> :noh<cr>
nnoremap H ^
nnoremap L $
vnoremap H ^
vnoremap L $
inoremap <c-d> <del>
nnoremap <c-_> :Commentary<cr>j
vnoremap <c-_> :Commentary<cr>gv
inoremap <c-t> <esc><left>"zx"zpa
vnoremap , <esc>ggVG

" カーソル下の単語をハイライトしてから置換
nnoremap # "zyiw:let @/ = '\<' . @z . '\>'<cr>:set hlsearch<cr>:%s/<c-r>///g<left><left>

" 行を移動
nnoremap <c-up> "zdd<up>"zP
nnoremap <c-down> "zdd"zp
vnoremap <c-up> "zx<up>"zP`[V`]
vnoremap <c-down> "zx"zp`[V`]

cnoremap <c-p> <up>
cnoremap <c-n> <down>
cnoremap <c-a> <home>
cnoremap <c-e> <end>
cnoremap <c-b> <left>
cnoremap <c-f> <right>
cnoremap <c-y> <c-r>"

" アクティブなファイルが含まれているディレクトリを%%で展開
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'

" WSLでヤンクでClipboardにコピー
if system('uname -a | grep microsoft') != ''
    augroup myYank
        autocmd!
        autocmd TextYankPost * :call system('cd /mnt/c; clip.exe &', @")
    augroup END
endif

" コマンドラインモード時は相対行番号を無効化
nnoremap ; :set norelativenumber<cr>:
au CmdLineLeave * set relativenumber

" *.[ch]ppファイル保存時に自動的にclang-formatを実行
function! s:clang_format()
  let now_line = line(".")
  silent exec ":%! clang-format --style=GNU"
  exec ":" . now_line
endfunction

