# Mes courses

Application iPhone native en SwiftUI, pour une liste personnelle permanente organisée par rayons. Données locales, sans compte ni serveur.

## Ouvrir et lancer

1. Ouvrir `Courses.xcodeproj` dans Xcode 26 ou ultérieur.
2. Sélectionner le schéma `Courses` et un simulateur iPhone sous iOS 26 ou ultérieur.
3. Lancer avec ⌘R.

Pour installer sur un iPhone, choisir sa propre équipe dans **Signing & Capabilities**, adapter le bundle identifier si nécessaire et sélectionner l’appareil. Aucune équipe de signature n’est imposée dans le projet.

Le classement automatique nécessite un iPhone compatible, Apple Intelligence activé et son modèle disponible en français. L’ajout, le classement manuel et les choix mémorisés restent utilisables sans modèle. Aucun appel réseau de substitution n’est effectué.

## Fonctionnalités

- Découverte avec exemples, dix rayons personnalisables et liste initialement vide.
- Catalogue de départ avec variantes connues, enrichissement local et autocomplétion privilégiant les habitudes.
- Nom et note secondaire, blocage des doublons y compris cochés, accès à l’élément déjà présent.
- Classement par Foundation Models, suggestions de nouveaux rayons à accepter ou ignorer.
- Corrections mémorisées, y compris le choix explicite de « À classer ».
- Modification et suppression des produits ; achats cochés regroupés en bas et suppression collective.
- Ajout, renommage, réorganisation et suppression des rayons.
- Sauvegarde atomique ; une erreur de lecture bloque les modifications afin de conserver le fichier existant.

## Organisation

- `Courses/Core/ShoppingList.swift` : identité des produits, règles de liste et persistance.
- `Courses/App/Store.swift` : coordination des changements et du classement asynchrone.
- `Courses/App/Intelligence.swift` : disponibilité du modèle et génération structurée.
- `Courses/App/ShoppingView.swift` : vues SwiftUI et découverte.
- `Tests/CoursesCoreTests` : tests des règles métier et de la persistance.
- `docs/design.md` et `CONTEXT.md` : décisions et vocabulaire validés.

## Vérifications

```sh
swift test
xcodebuild -project Courses.xcodeproj -scheme Courses -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Le modèle n’est pas simulé par les tests métier : la qualité du classement français doit être vérifiée sur un iPhone compatible avec Apple Intelligence. Exemples à essayer : Bavette → Boucherie, Comté → Produits laitiers et œufs, Tomates en conserve → Épicerie ; puis un produit sans rayon adapté, une correction manuelle et un nouvel ajout après suppression.

Cette première version n’inclut pas de synchronisation iCloud, de partage ni d’assets de publication App Store.

API Apple : [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession), [génération structurée](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation).
