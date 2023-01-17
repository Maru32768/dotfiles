#!/bin/bash

rm ~/.vimrc
ln -s ~/dotfiles/vim/.vimrc ~/.vimrc

touch ~/.bashrc
echo 'source ~/dotfiles/.bashrc' >> ~/.bashrc

touch ~/.bash_profile
echo 'source ~/dotfiles/.bash_profile' >> ~/.bash_profile

source ~/.bash_profile 2> /dev/null

sudo add-apt-repository ppa:neovim-ppa/stable

sudo apt install -y build-essential curl git unzip neovim tmux python-is-python3 libncurses5-dev python3-dev

curl https://sh.rustup.rs -sSf -o /tmp/rustup.rs 
sh /tmp/rustup.rs -y

curl -fsSL https://deno.land/install.sh | sh

curl https://get.volta.sh | bash

# ----- go -----
curl -L https://go.dev/dl/$(curl https://go.dev/VERSION?m=text).linux-amd64.tar.gz -o go.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go.tar.gz
rm -rf go.tar.gz

go install golang.org/x/tools/cmd/goimports@latest
go install github.com/x-motemen/ghq@latest
# --------------

# -----build vim-----
sudo apt remove vim
sudo apt autoremove vim

ghq get https://github.com/vim/vim
cd ~/ghq/github.com/vim/vim/src

~/dotfiles/build_vim.sh && make && sudo make install && cd -

curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
# -------------------

# ----- git settings -----
git config --global user.name "Maru32768"
git config --global core.editor 'vim -c "set fenc=utf-8"'
git config --global color.diff auto
git config --global color.status auto
git config --global color.branch auto
git config --global color.ui true
git config --global push.default simple
git config --global core.ignorecase false
git config --global core.quotepath false
git config --global core.autocrlf true
git config --global merge.tool vimdiff
git config --global merge.conflictstyle diff3
git config --global mergetool.prompt false
# ------------------------

sudo apt install wslu
WINHOME="$(wslpath "$(wslvar USERPROFILE)")"
mv $WINHOME/.ssh $WINHOME/.ssh_bak$(date +%s)
mkdir $WINHOME/.ssh
cp -r ~/.ssh/* $WINHOME
rm -r ~/.ssh
ln -s $WINHOME/.ssh ~/.ssh

mkdir -p $WINHOME/.config/git
mv $WINHOME/.config/git $WINHOME/.config/git_bak$(date +%s)
cp -r ~/.config/git $WINHOME/.config/git
rm -r ~/.config/git
ln -s $WINHOME/.config/git ~/.config/git

mv $WINHOME/.gitconfig $WINHOME/.gitconfig_bak$(date +%s)
cp ~/.gitconfig $WINHOME/.gitconfig
rm ~/.gitconfig
ln -s $WINHOME/.gitconfig ~/.gitconfig

sudo touch /etc/wsl.conf
echo "[automount]" | sudo tee -a /etc/wsl.conf
echo "options = "metadata"" | sudo tee -a /etc/wsl.conf

source ~/.bash_profile

