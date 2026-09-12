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
