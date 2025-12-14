
cd
# install yay 
yes | sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
yes | makepkg -si
