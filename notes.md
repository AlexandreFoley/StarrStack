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

## Roadmap

- Add optional support for Lidarr, Readarr, and Whisparr to the image and
  service configuration.
- Keep their existing installer branches until each service has a complete
  container integration: version/build arguments, service definition, image
  wiring, configuration, and tests.

## Updating the Unpackerr repository script

`scripts/repo.sh` is maintained upstream by GoLift and is copied from
`https://golift.io/repo.sh`. Keep the upstream script intact instead of
removing support for platforms that this image does not currently use.

When refreshing it:

1. Download the upstream script to a temporary file with `curl --fail
   --location --silent --show-error`.
2. Review the diff, especially repository URLs, signing-key handling, package
   installation commands, and shell compatibility.
3. Replace `scripts/repo.sh` only after confirming the script still supports
   the UBI/YUM path used for Unpackerr.
4. Run `bash -n scripts/repo.sh`, build the UBI image, and run `just test`.
5. Commit the upstream refresh separately, recording the source URL and
   retrieval date in the commit message.

The long-term improvement is a scheduled update check that downloads the
upstream copy, opens or reports a reviewable diff, and never replaces the
checked-in script automatically.

