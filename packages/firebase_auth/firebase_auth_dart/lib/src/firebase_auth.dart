part of firebase_auth_dart;

/// The options used for all requests made by [Auth] instance.
class AuthOptions {
  // ignore: public_member_api_docs
  AuthOptions({
    required this.apiKey,
    required this.projectId,
    this.host = 'localhost',
    this.port = 9099,
    this.useEmulator = false,
  });

  /// The API key used for all requests made by DartAuth instance.
  ///
  /// Leave empty if `useEmulator` is true.
  final String apiKey;

  /// The Id of GCP or Firebase project.
  final String projectId;

  /// The Firebase Auth emulator host, defaults to `localhost`.
  final String? host;

  /// The Firebase Auth emulator port, defaults to `9099`,
  /// check your terminal for the port being used.
  final int? port;

  /// Whether to use Firebase Auth emulator for all requests.
  ///
  /// You must start the emulator in order to use it, see:
  /// https://firebase.google.com/docs/emulator-suite/install_and_configure#install_the_local_emulator_suite
  final bool useEmulator;
}

/// Pure Dart service wrapper around the Identity Platform REST API.
///
/// https://cloud.google.com/identity-platform/docs/use-rest-api
class Auth {
  // ignore: public_member_api_docs
  Auth({required this.options})
      : assert(
            options.apiKey.isNotEmpty,
            'API key must not be empty, please provide a valid API key, '
            'or a dummy one if you are using the emulator.') {
    _client = clientViaApiKey(options.apiKey);

    // Use auth emulator if available
    if (options.useEmulator) {
      final rootUrl =
          'http://${options.host}:${options.port}/www.googleapis.com/';

      _identityToolkit =
          IdentityToolkitApi(_client, rootUrl: rootUrl).relyingparty;
    } else {
      _identityToolkit = IdentityToolkitApi(_client).relyingparty;
    }

    _idTokenChangedController = StreamController<User?>.broadcast(sync: true);
    _changeController = StreamController<User?>.broadcast(sync: true);
  }

  /// The settings this instance is configured with.
  final AuthOptions options;

  late http.Client _client;

  /// The indentity toolkit API instance used to make all requests.
  late RelyingpartyResource _identityToolkit;

  // ignore: close_sinks
  late StreamController<User?> _changeController;

  // ignore: close_sinks
  late StreamController<User?> _idTokenChangedController;

  /// Sends events when the users sign-in state changes.
  ///
  /// If the value is `null`, there is no signed-in user.
  Stream<User?> get onAuthStateChanged {
    return _changeController.stream;
  }

  /// Sends events for changes to the signed-in user's ID token,
  /// which includes sign-in, sign-out, and token refresh events.
  ///
  /// If the value is `null`, there is no signed-in user.
  Stream<User?> get onIdTokenChanged {
    return _idTokenChangedController.stream;
  }

  /// The currently signed in user for this instance.
  User? currentUser;

  /// Sign users in using email and password.
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      final _response = await _identityToolkit.verifyPassword(
        IdentitytoolkitRelyingpartyVerifyPasswordRequest(
          returnSecureToken: true,
          password: password,
          email: email,
        ),
      );

      // Map the json response to an actual user.
      final user = User.fromResponse(_response.toJson());

      currentUser = user;
      _changeController.add(user);
      _idTokenChangedController.add(user);

      final providerId = AuthProvider.password.providerId;

      // Make a credential object based on the current sign-in method.
      return UserCredential(
        user: user,
        credential: AuthCredential(
          providerId: providerId,
          signInMethod: providerId,
        ),
        additionalUserInfo: AdditionalUserInfo(isNewUser: false),
      );
    } on DetailedApiRequestError catch (exception) {
      final authException = AuthException.fromErrorCode(exception.message);
      log('$authException', name: 'DartAuth/${authException.code}');

      throw authException;
    } catch (exception) {
      log('$exception', name: 'DartAuth');

      rethrow;
    }
  }

  /// Sign users up using email and password.
  Future<UserCredential> createUserWithEmailAndPassword(
      String email, String password) async {
    try {
      final _response = await _identityToolkit.signupNewUser(
        IdentitytoolkitRelyingpartySignupNewUserRequest(
          email: email,
          password: password,
        ),
      );

      final user = User.fromResponse(_response.toJson());

      currentUser = user;
      _changeController.add(user);
      _idTokenChangedController.add(user);

      final providerId = AuthProvider.password.providerId;

      return UserCredential(
        user: user,
        credential: AuthCredential(
          providerId: providerId,
          signInMethod: providerId,
        ),
        additionalUserInfo: AdditionalUserInfo(isNewUser: true),
      );
    } on DetailedApiRequestError catch (exception) {
      final authException = AuthException.fromErrorCode(exception.message);
      log('$authException', name: 'DartAuth/${authException.code}');

      throw authException;
    } catch (exception) {
      log('$exception', name: 'IPAuth/signUpWithEmailAndPassword');

      rethrow;
    }
  }

  /// Fetch the list of providers associated with a specified email.
  ///
  /// Throws **[AuthException]** with following possible codes:
  /// - `INVALID_EMAIL`: user doesn't exist
  /// - `INVALID_IDENTIFIER`: the identifier isn't a valid email
  Future<List<String>> fetchSignInMethodsForEmail(String email) async {
    try {
      final _response = await _identityToolkit.createAuthUri(
        IdentitytoolkitRelyingpartyCreateAuthUriRequest(
          identifier: email,
          continueUri: 'http://localhost:8080/app',
        ),
      );

      return _response.allProviders ?? [];
    } on DetailedApiRequestError catch (exception) {
      final authException = AuthException.fromErrorCode(exception.message);
      log('$authException', name: 'DartAuth/${authException.code}');

      throw authException;
    } catch (exception) {
      log('$exception', name: 'IPAuth/fetchSignInMethodsForEmail');

      rethrow;
    }
  }

  /// Send a password reset email.
  ///
  /// Throws **[AuthException]** with following possible codes:
  /// - `EMAIL_NOT_FOUND`: user doesn't exist
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      final _response = await _identityToolkit.getOobConfirmationCode(
        Relyingparty(
          email: email,
          requestType: 'PASSWORD_RESET',
          // have to be sent, otherwise the user won't be redirected to the app.
          // continueUrl: ,
        ),
      );

      return _response.email;
    } on DetailedApiRequestError catch (exception) {
      final authException = AuthException.fromErrorCode(exception.message);
      log('$authException', name: 'DartAuth/${authException.code}');

      throw authException;
    } catch (exception) {
      log('$exception', name: 'IPAuth/sendPasswordResetEmail');

      rethrow;
    }
  }

  /// Send a sign in link to email.
  ///
  /// Throws **[AuthException]** with following possible codes:
  /// - `EMAIL_NOT_FOUND`: user doesn't exist
  Future<String?> sendSignInLinkToEmail(String email) async {
    try {
      final _response = await _identityToolkit.getOobConfirmationCode(
        Relyingparty(
          email: email,
          requestType: 'EMAIL_SIGNIN',
          // have to be sent, otherwise the user won't be redirected to the app.
          // continueUrl: ,
        ),
      );

      return _response.email;
    } on DetailedApiRequestError catch (exception) {
      final authException = AuthException.fromErrorCode(exception.message);
      log('$authException', name: 'DartAuth/${authException.code}');

      throw authException;
    } catch (exception) {
      log('$exception', name: 'IPAuth/sendSignInLinkToEmail');

      rethrow;
    }
  }

  /// Sign in anonymous users.
  ///
  Future<UserCredential> signInAnonymously() async {
    try {
      final _response = await _identityToolkit.signupNewUser(
        IdentitytoolkitRelyingpartySignupNewUserRequest(),
      );

      final user = User.fromResponse(_response.toJson());

      currentUser = user;
      _changeController.add(user);
      _idTokenChangedController.add(user);

      final providerId = AuthProvider.anonymous.providerId;

      return UserCredential(
        user: user,
        credential: AuthCredential(
          providerId: providerId,
          signInMethod: providerId,
        ),
        additionalUserInfo: AdditionalUserInfo(isNewUser: true),
      );
    } on DetailedApiRequestError catch (exception) {
      final authException = AuthException.fromErrorCode(exception.message);
      log('$authException', name: 'DartAuth/${authException.code}');

      throw authException;
    } catch (exception) {
      log('$exception', name: 'IPAuth/signInAnonymously');

      rethrow;
    }
  }

  /// Sign user out by cleaning currentUser, local persistence and all streams.
  ///
  Future<void> signOut() async {
    try {
      currentUser = null;
      _changeController.add(null);
      _idTokenChangedController.add(null);
    } catch (exception) {
      log('$exception', name: 'IPAuth/signOut');

      rethrow;
    }
  }

  /// Check if an emulator is running, throws if there isn't.
  Future<void> useAuthEmulator(String host, int port) async {
    try {
      // 1. Get the emulator project configs, it must be initialized first.
      // http://localhost:9099/emulator/v1/projects/{project-id}/config

      final localEmulator = Uri(
        scheme: 'http',
        host: host,
        port: port,
        pathSegments: [
          'emulator',
          'v1',
          'projects',
          options.projectId,
          'config'
        ],
      );

      final resposne = await http.get(localEmulator);

      final Map emulatorProjectConfig = json.decode(resposne.body);

      // 2. Check if the emulator is in use, if it isn't an error will be returned.
      if (emulatorProjectConfig.containsKey('error')) {
        throw AuthException.fromErrorCode(
            emulatorProjectConfig['error']['status']);
      }
    } catch (exception) {
      log('$exception', name: 'IPAuth/useAuthEmulator');

      rethrow;
    }
  }
}