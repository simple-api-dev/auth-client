# SimpleAPI Auth API: Flutter web sample

A small Flutter web app that shows how to call the free [SimpleAPI Auth API](https://auth.simpleapi.dev/docs) from a browser, with no backend of your own.

**[Live demo](https://simple-api-dev.github.io/auth-client/)** | **[API docs](https://auth.simpleapi.dev/docs)** | **[Get a free key](https://keys.simpleapi.dev/?product=auth)**

![The sample app](docs/screenshot.png)

## Run it

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable; CI uses 3.47.8) and a free key from [keys.simpleapi.dev](https://keys.simpleapi.dev/?product=auth).

```bash
git clone https://github.com/simple-api-dev/auth-client
cd auth-client
flutter pub get
flutter run -d chrome --dart-define=SIMPLEAPI_KEY=YOUR_KEY
```

The live demo opens on the login screen. **Try the demo account** logs in as the shared demo user with one click, so there is nothing to fill in. Run the tests with `flutter test`. All HTTP is mocked, so nothing calls the real API.

## How it calls the API

Every request goes to `https://auth.simpleapi.dev` and carries your key in the `apikey` query string. A logged-in user also sends a bearer token. The API allows any origin (CORS), so the browser calls it directly.

```dart
final uri = Uri.parse('https://auth.simpleapi.dev')
    .replace(path: '/api/users/me', queryParameters: {'apikey': apiKey});
final response = await http.get(uri, headers: {
  'Accept': 'application/json',
  'Authorization': 'Bearer $token', // only on calls that need a logged-in user
});
```

Login and register never send the bearer token. A `401` on a call made while logged in drops the token and shows the login screen again.

## Screens and API calls

| Screen | What it does | Calls |
| --- | --- | --- |
| Log in | **Try the demo account** logs in as `demo@simpleapi.dev` in one click. Below it are the normal form, which shows the 15 minute lockout after 5 wrong passwords, and the links to the other two screens | `POST /api/users/login` |
| Create an account | Register and be logged in | `POST /api/users/register` |
| Reset password, step 1 | Email a 6-digit code | `POST /api/users/forgot` |
| Reset password, step 2 | Set a new password with the code | `POST /api/users/reset` |
| Your account: Profile | Show the profile, edit the name. Dates read like `1 Nov 2026`. The demo account sees no edit | `GET /api/users/me`, `PUT /api/users/me` |
| Verify your email | Email a code, then confirm it | `POST /api/users/me/email/send-code`, `POST /api/users/me/email/verify` |
| Change email, Change password | Needs the current password | `PUT /api/users/me` |
| Log out | This device, or all devices | `POST /api/users/logout` (`?all=true` for all) |
| Delete account | Needs the password | `DELETE /api/users/me` |

The admin calls (`/api/users`, `/api/users/{id}`) are for the owner of the key and are not used here. Errors are turned into plain text in one function, `describeError` in `lib/auth_api.dart`.

## Use your own key

The live demo is built with a shared demo key. The app has no screen for entering a key: it uses only the key compiled in at build time. To run it with your own, pass it to Flutter:

```bash
flutter run -d chrome --dart-define=SIMPLEAPI_KEY=YOUR_KEY
```

Get a free key at [keys.simpleapi.dev](https://keys.simpleapi.dev/?product=auth).

## Good to know

- Passwords are 8 to 72 characters. Emails are not case sensitive.
- Five wrong passwords lock that email for 15 minutes (`429`). Reset and verification codes work once, last 15 minutes and allow 5 wrong tries. A key can send 20 reset and verification emails a day.
- Wrong login `401`, wrong password when deleting an account `403`, duplicate email `409`, malformed JSON `400`, validation `422`, rate limit `429` (60 requests a minute per IP address), key service down `503`.
- The session token is kept in memory only, so reloading the page logs you out.
- The only dependency besides Flutter is the `http` package.
- The demo account is `demo@simpleapi.dev` with password `try-the-demo`. It is public by design and shared by every visitor, and the live demo resets every night, so do not use a real password or any private details. When the demo key has no room for more users, registering shows "The demo is full. It resets every night."
- The app does not offer to rename the demo account, delete it or change its email or password. The API protects it too: `PUT /api/users/me`, `DELETE /api/users/me`, `users/forgot`, `users/reset` and the `users/me/email` routes answer `403` `The demo account cannot be changed.`, and `users/logout?all=true` ends only your own session. Register your own account to try those screens.
- A key holds 25 users on the free tier.

## Project layout

```
lib/auth_api.dart         the whole API client, ApiException and describeError
lib/models.dart           User and Session
lib/app_state.dart        the logged-in user (a ChangeNotifier)
lib/open_url*.dart        opens a link in the same tab (the back arrow)
lib/config.dart           the build-time key (SIMPLEAPI_KEY) and the demo account
lib/screens/              the screens, and ui.dart with the shared widgets
test/                     unit and widget tests, and the API's answers replayed through the client
```

## Deploy to GitHub Pages

[`.github/workflows/pages.yml`](.github/workflows/pages.yml) runs on every push to `main`. It runs `flutter analyze` and `flutter test`, builds with `flutter build web --release --base-href /auth-client/`, and publishes with the official Pages actions.

In your own copy:

1. Set **Settings, Pages, Source** to **GitHub Actions**.
2. Add a repository **variable** named `SIMPLEAPI_KEY` under **Settings, Secrets and variables, Actions, Variables**. The build passes it with `--dart-define=SIMPLEAPI_KEY=...`.
3. Push to `main`, or run the workflow.

Anything passed with `--dart-define` ends up in the compiled JavaScript, so anyone can read it from the deployed site. Use a free key made for a public demo. If you rename the repository, change `--base-href` to match.

## License

[MIT](LICENSE)
