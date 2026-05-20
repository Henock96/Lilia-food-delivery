# CLAUDE.local.md — Config locale lilia_food_delivery

## Environnement de dev

- **Flutter** : 3.41.9 (channel stable)
- **Dart** : 3.11.5
- **Org** : `com.dreesis`
- **Platform cibles** : Android, iOS

## Firebase à configurer

L'app nécessite Firebase. Pour l'instant `Firebase.initializeApp()` est appelé sans options
(il faut ajouter les fichiers de config) :

- Android : `android/app/google-services.json`
- iOS : `ios/Runner/GoogleService-Info.plist`

Utiliser le même projet Firebase que `lilia-app` (même backend, même auth).

## Lancer le projet

```bash
cd /Users/henokmipoks/Desktop/code/lilia_food_delivery
flutter run
```

## Notes dev

- Les `.g.dart` sont gitignorés normalement — toujours lancer `build_runner` après un pull
- Le backend de prod est sur Render — peut avoir un cold start de ~30s
