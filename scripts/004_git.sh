#!/bin/bash
# git のグローバル設定。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "git のグローバル設定を適用"
git config --global user.name "Maru32768"
git config --global core.editor 'vim -c "set fenc=utf-8"'
git config --global color.diff auto
git config --global color.status auto
git config --global color.branch auto
git config --global color.ui true
git config --global push.default simple
git config --global core.ignorecase false
git config --global core.quotepath false
git config --global core.autocrlf input
git config --global merge.tool vimdiff
git config --global merge.conflictstyle diff3
git config --global mergetool.prompt false

# コミット署名 (docs/gpg.md)。.gitconfig は Windows と共有するので gpg.program にパスを書かない。
git config --global commit.gpgsign true
git config --global gpg.program gpg
git config --global user.signingkey "${GPG_SIGNING_FPR: -16}"
git config --global --unset user.signinkey || true # 過去のスペルミス
