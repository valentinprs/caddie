# Validation de la première version

Vérifications effectuées le 12 septembre 2026 avec Xcode 26.6.

- Huit tests XCTest du moteur métier : tous réussis.
- Compilation iPhone sans signature : réussie.
- Compilation simulateur iOS : réussie.
- Installation et lancement sur simulateur iPhone 17 Pro, iOS 26.5 : réussis.
- Parcours vérifié visuellement : découverte, liste vide, saisie « bav », suggestion « Bavette », ajout avec note « 2 pièces », correction manuelle vers Boucherie, produit coché visible dans l’autocomplétion, ouverture de cet élément existant et remise à acheter.
- L’appel réel à Foundation Models a échoué dans ce simulateur. Le produit a été conservé dans « À classer » et la correction manuelle a fonctionné. La précision du classement et la suggestion de nouveaux rayons restent à valider sur iPhone compatible.

Les tests automatisés couvrent les variantes et doublons cochés, la mémoire des corrections, la suppression et le renommage des rayons, les réponses de classement périmées, le remplacement d’un produit, les suggestions, la sauvegarde et les erreurs de lecture.

Le simulateur contient un produit de démonstration ajouté pendant ces vérifications. Une installation neuve conserve bien une liste initialement vide.

## Vérification du classement avec le modèle réel

`Tests/ClassificationChecks.swift` exerce le classificateur de l’application et l’application
du résultat dans la liste. Il reçoit des couples nom de produit / rayon attendu en arguments,
sans table de correspondance dans le classificateur. Chaque cas est exécuté avec de nouveaux
UUID et dans les deux ordres de rayons. Un mauvais rayon, une suggestion accompagnant un
rayon existant ou une indisponibilité du modèle fait échouer la commande.

Sur un Mac compatible avec Apple Intelligence et le français, avec Xcode 26 :

```sh
swiftc Courses/Core/ShoppingList.swift Courses/App/Intelligence.swift \
  Tests/ClassificationChecks.swift -o /tmp/courses-classification-checks
LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8 /tmp/courses-classification-checks \
  "NOM_DU_PRODUIT" "RAYON_ATTENDU" -AppleLanguages '(fr)' -AppleLocale fr_FR
```

Fournir plusieurs couples pour couvrir des familles différentes, des noms composés et des
précisions de conservation. Ce contrôle nécessite le vrai modèle local ; les tests Swift
du moteur métier ne mesurent pas sa précision sémantique. Un succès sur Mac ne remplace
pas la validation sur iPhone et ne garantit pas les réponses des futures versions du modèle.

### Résultat du renforcement du 12 septembre 2026

- Le classement erroné signalé a été reproduit avec le modèle local, puis corrigé
  en remplaçant les UUID proposés au modèle par les noms de rayons.
- Le parcours final en deux étapes a donné 18 réponses correctes sur 20 appels
  (10 produits, deux ordres et de nouveaux UUID), couvrant les dix rayons initiaux.
- Une erreur persiste pour « Lentilles en conserve », envoyé vers « Produits laitiers
  et œufs » au lieu d’« Épicerie » dans les deux ordres. La commande termine donc
  en échec : ce résultat n’est pas une validation complète de la précision du modèle.
- Les huit tests du moteur métier et la compilation simulateur ont réussi.

Les consignes restent générales : aucune exception par produit n’a été ajoutée pour
faire passer les cas mesurés. Les corrections manuelles restent nécessaires lorsque
le modèle se trompe.
