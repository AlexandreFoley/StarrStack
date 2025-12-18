- structure:
    - one custom container for sonarr,radarr,prowlarr,etc
    - one container for buildarr
        - Maybe later
        - it's incomplete and looks abandonned (no updates in a year).
        - build my own based on golift/starr?
    - one container for qbittorrent+VPN

- Image custom pour les *arr:
    - ubi9-init fonctionne assé bien, mais fais une image pas mal grosse.
        - Basé sur RHEL. le package manager est yum/dnf
        - il faut un script d'installation custom. arrstack-install.sh 
            - La source de ce script n'est pas pour la construction d'une image, mais pour l'installation sur fedora bare-metal. Donc quelques modification sont nécéssaire.
    - Les arr supporte un fichier package_info et des variable d'environement pour controller plusieur aspect du fonctionnement des applications.
        - Les variables d'environment seront utilisé pour les APIKey et la methode d'Authentication.
        - package_info pour désactivé les mecanisme d'update.
    - l'image de unpackerr fait seulement 8MB, mais installé unpacker dans ubi semble l'avoir fait gonflé de ~40MB.
        - il faut que je vois le dockerfile de leur image.
- QbitTorrent + VPN : https://hotio.dev/containers/qbittorrent/

Alternative basé sur Alpine pour *arr:
    - Possibilité d'utilisé AplineLinux + OpenRC + systemctl-alpine pour gérer les services. Ça devrait sauvé ~ 250MB à l'image.
        - OpenRC est le point d'entré dans ce cas, je crois.
        - les scripts et dockerfile de linuxserver.io devrait formé une bonne base.
        - https://medium.com/@mfranzon/how-to-create-and-manage-a-service-in-an-alpine-linux-container-93a97d5dad80
        - https://stackoverflow.com/questions/78269734/is-there-a-better-way-to-run-openrc-in-a-container-than-enabling-softlevel
