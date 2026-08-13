- structure:
    - one custom container for sonarr,radarr,prowlarr,etc
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
        - C'est le processus de checkpointing de la construction du container. 
            - "multi-stage" regle le problème.
- QbitTorrent + VPN : https://hotio.dev/containers/qbittorrent/
    - image ajuster: https://github.com/AlexandreFoley/qbittorrent

Alternative basé sur Alpine pour *arr:
    - Supervisord pour gérer plusieur services sans systemd.
    - Possibilité d'utilisé AplineLinux + OpenRC + systemctl-alpine pour gérer les services. Ça devrait sauvé ~ 250MB à l'image.
        - OpenRC est le point d'entré dans ce cas, je crois.
        - les scripts et dockerfile de linuxserver.io devrait formé une bonne base.
        - https://medium.com/@mfranzon/how-to-create-and-manage-a-service-in-an-alpine-linux-container-93a97d5dad80
        - https://stackoverflow.com/questions/78269734/is-there-a-better-way-to-run-openrc-in-a-container-than-enabling-softlevel
        - dépendence sur setfacl pour gérer les permissions des services sut les dossiers dans config. problème?

## TODO

- [ ] qbittorrent downloads land as subuid 101000:101000 (PUID/PGID=1000 in its rootless container): starr services get "other" perms only, so imports can't delete source files. Fix: give starr services SupplementaryGroups=1000 (shared subgid range makes it the same group in both containers); optionally move service groups to system gids and name gid 1000 "downloads". Also shelved: per-service idmapped /media mounts or bindfs for fully host-owned media files (complexity not justified yet).
- [ ] Verify whether unpackerr actually uses /config/unpackerr (its config lives at /opt/unpackerr.conf). If not make sure it uses /config for its configuration. non-urgent as unpacker should work without further conf.
