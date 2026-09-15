# Configuration et validation iCloud

Caddie utilise une zone CloudKit personnalisée par liste dans le conteneur `iCloud.com.valentin.caddie`. Les listes du propriétaire résident dans sa base privée; les invitations donnent accès à la même zone depuis la base partagée des participants. Le cache local `Application Support/Courses/store-v2/snapshot.json` reste la source immédiate de l’interface et contient, dans une écriture atomique, l’état métier et les changements en attente.

## Configuration Apple requise

1. Dans le compte Developer associé à l’équipe de signature, créer ou sélectionner `iCloud.com.valentin.caddie` et l’associer à l’identifiant d’app `com.valentin.caddie`. Les identifiants de conteneur iCloud ne peuvent pas être renommés : créer le nouveau conteneur isole les anciennes données et les partages de l’ancien conteneur.
2. Dans Xcode, vérifier les capacités iCloud/CloudKit, Push Notifications et Background Modes > Remote notifications. Le dépôt contient les entitlements et les clés d’Info.plist correspondantes; le profil de provisionnement doit les autoriser.
3. Dans CloudKit Development, importer et valider `Caddie/CloudKitSchema.ckdb` avec `xcrun cktool`. Le schéma définit les types `List`, `Aisle`, `Product` et `ListItem` et leurs champs, tels qu’utilisés par `CloudSchema.swift`.
4. Créer au moins un partage depuis une build Development : CloudKit ajoute alors son type système `cloudkit.share`. Ne promouvoir le schéma en Production qu’après cette étape et une validation complète sur appareils. `cktool` importe les schémas en Development, tandis que la promotion vers Production se confirme dans CloudKit Console. Cette promotion ne remplace pas le déploiement TestFlight et les changements de schéma de production sont difficiles à retirer.

## Validation avant livraison

Utiliser deux iPhone sous iOS 26 avec deux comptes iCloud, puis un troisième participant pour le partage multiple. Vérifier la création et la modification sur deux appareils du propriétaire, l’invitation lorsque Caddie est fermé, les modifications simultanées, un appareil hors ligne puis reconnecté, la suppression d’un rayon, les doubles ajouts d’un même produit, le départ d’un participant, l’arrêt du partage, la suppression par le propriétaire et un changement aller-retour de compte iCloud.

Le simulateur et `swift test` valident le modèle, la migration et la compilation, mais pas la distribution des notifications, l’acceptation système d’une invitation ni la convergence entre comptes.

## Diagnostic respectueux des données

Les diagnostics doivent se limiter à la portée de base, au type d’événement, au code `CKError`, au nombre de records et aux identifiants techniques de zone. Ne jamais journaliser le nom d’une liste, un produit, une note ou l’identité d’un participant. Une erreur temporaire laisse les changements dans le journal local; une erreur durable apparaît dans l’interface et peut être retentée au prochain passage au premier plan.
