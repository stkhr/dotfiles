"エンコーディング
set encoding=utf-8
scriptencoding utf-8

"構文の強調表現
syntax enable
syntax on

"カッコ閉じた際に閉じたカッコに移動
set nostartofline

"カッコ自動閉じる
inoremap { {}<LEFT>
inoremap [ []<LEFT>
inoremap ( ()<LEFT>
inoremap " ""<LEFT>
inoremap ' ''<LEFT>
vnoremap { "zdi^V{<C-R>z}<ESC>
vnoremap [ "zdi^V[<C-R>z]<ESC>
vnoremap ( "zdi^V(<C-R>z)<ESC>
vnoremap " "zdi^V"<C-R>z^V"<ESC>
vnoremap ' "zdi'<C-R>z'<ESC>

"タブ幅はスペース4個分
set tabstop=4

"タブをスペースに変換する。自動インデントに使用する文字幅は4個
set expandtab
set shiftwidth=4

"インクリメントサーチ
set incsearch

"カーソル位置表示
set ruler

"行番号表示
set number

"オートインデント
set autoindent

"ペースト時に自動インデントで崩れるのを防ぐ
if &term =~ "xterm"
    let &t_SI .= "\e[?2004h"
    let &t_EI .= "\e[?2004l"
    let &pastetoggle = "\e[201~"

    function XTermPasteBegin(ret)
        set paste
        return a:ret
    endfunction

    inoremap <special> <expr> <Esc>[200~ XTermPasteBegin("")
endif

"color schemeを設定 http://vimcolors.com/
colorscheme monokai_pro
