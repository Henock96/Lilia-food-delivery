import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_repository.g.dart';

class AuthRepository {
  final FirebaseAuth _auth;
  AuthRepository(this._auth);

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Émet à chaque renouvellement du jeton d'identité Firebase (~1 h).
  ///
  /// Distinct d'`authStateChanges`, qui ne parle que de connexion et
  /// déconnexion : un jeton renouvelé n'est pas un changement de session, et
  /// c'est pourtant l'événement dont le socket de tracking a besoin pour ne
  /// pas rejouer indéfiniment un jeton périmé.
  Stream<User?> idTokenChanges() => _auth.idTokenChanges();

  Future<String?> getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) => _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> signOut() => _auth.signOut();

  User? get currentUser => _auth.currentUser;
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) => AuthRepository(FirebaseAuth.instance);

@Riverpod(keepAlive: true)
Stream<User?> authStateChange(Ref ref) =>
    ref.watch(authRepositoryProvider).authStateChanges();

/// Jeton d'identité courant, réémis à chaque renouvellement Firebase.
@Riverpod(keepAlive: true)
Stream<String?> firebaseIdToken(Ref ref) => ref
    .watch(authRepositoryProvider)
    .idTokenChanges()
    .asyncMap((user) => user?.getIdToken());
