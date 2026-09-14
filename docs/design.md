# Décisions produit

## Confirmé

- Organisation commune à tous les magasins.
- Plusieurs listes peuvent coexister, qu’elles soient personnelles ou partagées.
- La dernière liste consultée est rouverte en priorité au lancement de l’application.
- Une liste personnelle existante peut devenir partagée sans perdre son contenu.
- Une liste partagée peut accueillir plusieurs participants.
- Si son propriétaire la supprime ou arrête son partage, elle disparaît de l’application des participants sans création automatique d’une copie personnelle.
- Tous les participants d’une liste partagée peuvent en modifier le contenu.
- Seul le propriétaire peut inviter ou retirer des participants et arrêter le partage.
- La propriété d’une liste partagée n’est pas transférable. Si le propriétaire arrête le partage, la liste disparaît pour tous les participants.
- Chaque liste possède ses propres rayons et leur ordre, son propre catalogue de produits et ses propres corrections mémorisées.
- Les participants peuvent créer, renommer, réordonner et supprimer les rayons d’une liste partagée.
- Les données apprises dans une liste ne sont pas réutilisées automatiquement dans les autres listes.
- Les modifications simultanées de champs différents d’un même élément sont fusionnées.
- Lorsque plusieurs participants modifient simultanément le même champ, la dernière modification synchronisée l’emporte sans résolution manuelle.
- Une suppression simultanée à une modification l’emporte sur cette modification.
- L’ajout simultané du même produit est dédoublonné selon l’identité de produit de la liste.
- Une nouvelle liste contient les rayons et le catalogue initiaux, mais aucun élément à acheter.
- Caddie reste utilisable sans compte iCloud et hors connexion. Les modifications locales sont synchronisées lorsque iCloud et le réseau redeviennent disponibles.
- Lorsque iCloud devient disponible, toutes les listes locales sont automatiquement synchronisées dans la base privée du compte sans devenir partagées.
- Les listes personnelles synchronisées sont disponibles sur tous les appareils connectés au même compte iCloud.
- Lors d’une déconnexion ou d’un changement de compte iCloud, les listes de l’ancien compte sont retirées de l’interface ; les listes créées ensuite hors iCloud restent locales.
- Un participant peut quitter une liste partagée, ce qui la retire de son application sans affecter les autres membres.
- Le propriétaire peut arrêter le partage ou supprimer la liste ; la suppression la retire à tous les participants.
- L’utilisateur peut ajouter et supprimer des rayons, et corriger le classement d’un produit.
- Lorsqu’aucun rayon existant ne convient précisément au produit, le modèle peut suggérer à l’utilisateur d’en créer un nouveau.
- Le choix corrigé par l’utilisateur est mémorisé pour les prochains ajouts du produit.
- Supprimer un rayon déplace ses éléments dans « À classer ».
- Privilégier un rayon existant adapté plutôt que proposer un rayon plus spécifique.
- Une suggestion de nouveau rayon accompagne un produit ajouté dans « À classer ». L’accepter crée le rayon et y déplace le produit ; l’ignorer laisse le produit dans « À classer ».
- Commencer avec une dizaine de rayons et des exemples pour accompagner la découverte de l’application. Les rayons sont réordonnables.
- Le champ du nom propose une autocomplétion : « bav » peut proposer « bavette ».
- Une deuxième ligne sous le nom accueille la quantité ou les précisions comme texte secondaire.
- Supprimer un rayon oublie également les corrections mémorisées qui le désignaient.
- Les éléments cochés restent visibles en bas. Une action permet de supprimer tous les éléments cochés.
- Lorsque le modèle est indisponible, conserver l’ajout et le classement manuels.
- Autocomplétion à partir d’un petit catalogue initial enrichi par les produits ajoutés, avec priorité aux produits habituels. Supprimer un élément de liste conserve le produit pour l’autocomplétion.
- Impossible d’ajouter un produit déjà présent dans la liste, y compris parmi les éléments cochés.
- Le nom suffisamment précis détermine le rayon (exemple : « Tomates en conserve »). La note contient la quantité ou des indications d’achat et n’influence pas le classement.
- Dix rayons initiaux : Fruits et légumes, Boucherie, Poissonnerie, Charcuterie, Produits laitiers et œufs, Boulangerie, Épicerie, Surgelés, Boissons, Hygiène et entretien.
- Exemples présentés pendant la découverte ; liste vide pour commencer ses courses.
- Le nom, la note et le rayon d’un élément sont modifiables après ajout.
- Les rayons peuvent être renommés en conservant leurs produits, leur position et les corrections mémorisées.
- Les produits présents restent visibles dans l’autocomplétion avec « Déjà dans la liste » ou « Acheté ». Leur sélection retrouve l’élément existant ; décocher un élément le remet à acheter.
- La reconnaissance d’un produit ignore les majuscules et les espaces superflus, et utilise les variantes connues du catalogue, dont les pluriels. Le modèle ne fusionne pas librement les noms proches. Cette identité sert à éviter les doublons et retrouver les corrections mémorisées.
- Changer le nom d’un élément remplace son produit et recalcule le classement, en respectant une éventuelle correction mémorisée pour le produit cible. La note est conservée ; le produit précédent reste dans le catalogue avec son classement mémorisé. La modification est bloquée si le produit cible est déjà dans la liste.
- Le choix manuel de « À classer » est mémorisé et prioritaire. Une arrivée automatique dans « À classer » ne constitue pas un choix mémorisé : une nouvelle suggestion reste possible lors d’un prochain ajout.
- Les produits à acheter sont affichés par ordre d’ajout dans chaque rayon.
- Les rayons vides sont masqués dans la liste et restent accessibles dans la gestion des rayons.
- « À classer » apparaît en premier lorsqu’il contient des produits à acheter ; tous les éléments cochés sont regroupés en bas.

## Orientation technique

- Utiliser le modèle embarqué Apple Intelligence pour proposer le classement.
- Application native SwiftUI ciblant iOS 26 et ultérieur.
- Faire évoluer la sauvegarde JSON locale atomique vers un cache local multi-listes synchronisé par CloudKit, tout en préservant le fonctionnement hors ligne et la migration du fichier historique dans Application Support.
- Foundation Models avec schéma de génération dynamique limité aux noms exacts des rayons existants et à « À classer ». Les UUID restent internes : le nom choisi est résolu vers l’identifiant du rayon dans l’instantané utilisé pour la requête. Les noms sont triés pour ne pas dépendre de l’ordre d’affichage.
- Le classement s’appuie sur la nature, l’usage et les précisions du nom complet, sans exemples orientant le modèle ni table de correspondance entre produits et rayons. Un nom ambigu reste « À classer » sans suggestion ; une famille identifiable sans rayon adapté peut donner lieu à une suggestion.
- Deux requêtes locales séparent l’identification de la famille commerciale, sans liste de rayons pour l’influencer, du choix parmi les rayons disponibles. Cette séparation augmente le temps de classement mais évite certaines confusions entre produit fini et matière première. La description intermédiaire est indicative, non persistée ; les corrections manuelles et les protections contre les réponses périmées restent prioritaires.
- Les réponses tardives sont ignorées après correction manuelle, changement de produit ou modification des rayons.

## État du cadrage

Les décisions des questions Q1 à Q23 et la synthèse globale sont validées. L’utilisateur a demandé le démarrage de l’implémentation le 12 septembre 2026.
