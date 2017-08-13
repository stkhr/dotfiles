"構文の強調表現
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

