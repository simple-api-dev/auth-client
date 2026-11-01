# SimpleAPI Auth API: Flutter web sample

A small Flutter web app that shows how to call the free [SimpleAPI Auth API](https://auth.simpleapi.dev) from a browser, with no backend of your own.

**[Live demo](https://simple-api-dev.github.io/auth-client/)** | **[API docs](https://auth.simpleapi.dev/docs)** | **[Get a free key](https://keys.simpleapi.dev/?product=auth)**

![The sample app](docs/screenshot.png)

## Run it

```bash
flutter pub get
flutter test
flutter run -d chrome --dart-define=SIMPLEAPI_KEY=YOUR_KEY
```

The live demo opens on the login screen. **Try the demo account** logs in as the shared demo user with one click, so there is nothing to sign up for. The app uses only the key it was built with (see [Use your own key](#use-your-own-key)). Never commit a key.

## How it calls the API

Every request goes to `https://auth.simpleapi.dev` and carries your key as the `apikey` query parameter. Calls for a logged-in user also send the session token as a bearer token. The API allows any origin (CORS), so the browser calls it directly.

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

| Screen | What it does | API call |
| --- | --- | --- |
| Log in, Try the demo account | One click logs in as `demo@simpleapi.dev`; the same screen has the normal form | `POST /api/users/login` |
| Log in | Log in; shows the 15 minute lockout after 5 wrong passwords | `POST /api/users/login` |
| Create an account | Register and be logged in | `POST /api/users/register` |
| Reset password, step 1 | Email a 6-digit code | `POST /api/users/forgot` |
| Reset password, step 2 | Set a new password with the code | `POST /api/users/reset` |
| Your account: Profile | Show the profile, edit the name | `GET /api/users/me`, `PUT /api/users/me` |
| Verify your email | Email a code, then confirm it | `POST /api/users/me/email/send-code`, `POST /api/users/me/email/verify` |
| Change email, Change password | Needs the current password | `PUT /api/users/me` |
| Log out | This device, or all devices | `POST /api/users/logout` (`?all=true` for all) |
| Delete account | Needs the password | `DELETE /api/users/me` |

The admin calls (`/api/users`, `/api/users/{id}`) are for the owner of the key and are not used here. Errors are turned into plain text in one function, `describeError` in `lib/auth_api.dart`.

## Use your own key

```bash
flutter run -d chrome --dart-define=SIMPLEAPI_KEY=YOUR_KEY
```

Get a free key at [keys.simpleapi.dev](https://keys.simpleapi.dev/?product=auth). The live demo uses a shared demo key that is compiled into the site; the app has no screen for entering a key.

## The shared demo account

- **One account for everyone.** `demo@simpleapi.dev` with password `try-the-demo` (public by design, constants in `lib/config.dart`). Data resets every night.
- **It cannot be changed or deleted.** Deleting it, changing its email or password, or resetting its password is refused in the app with a short message, so one visitor cannot lock out the rest. Anyone can still register their own account to try those screens.
- **25 users per key on the free tier.** When the shared key is full, registering shows "The demo is full. It resets every night."
- Every top-level screen has a back arrow (tooltip "Back to SimpleAPI") that opens https://simpleapi.dev in the same tab.

## Good to know

- Passwords are 8 to 72 characters. Emails are not case sensitive.
- Five wrong passwords lock that email for 15 minutes (`429`). Reset and verification codes work once, last 15 minutes and allow 5 wrong tries. A key can send 20 reset and verification emails a day.
- Wrong login `401`, wrong password when deleting an account `403`, duplicate email `409`, malformed JSON `400`, validation `422`, rate limit `429` (60 requests a minute per IP address), keys service down `503`.
- The session token is kept in memory only, so reloading the page logs you out.
- The only dependency besides Flutter is the `http` package.

## Project layout

| File | Purpose |
| --- | --- |
| `lib/auth_api.dart` | The whole API client, `ApiException` and `describeError` |
| `lib/models.dart` | `User` and `Session` |
| `lib/app_state.dart` | App state (logged-in user) as a `ChangeNotifier` |
| `lib/config.dart` | The build-time key (`SIMPLEAPI_KEY`) and the public demo account constants |
| `lib/open_url*.dart` | Opens a link in the same tab (the back arrow) |
| `lib/screens/` | One file per screen, and `ui.dart` with the shared widgets |
| `test/` | Unit and widget tests with a mocked HTTP client, and `live_shapes/` with the API's answers replayed through the client |

## Deploy to GitHub Pages

`.github/workflows/pages.yml` runs `flutter analyze` and `flutter test`, builds with `--base-href /auth-client/`, and deploys with the official Pages actions on every push to `main`. In the repository settings, set Pages > Source to GitHub Actions once.

The demo key is passed with `--dart-define=SIMPLEAPI_KEY=${{ vars.SIMPLEAPI_KEY }}`. Create a repository variable named `SIMPLEAPI_KEY` under Settings > Secrets and variables > Actions > Variables. If it is missing the site still builds, without a key.

Anything passed with `--dart-define` is readable in the public JavaScript of the site. Use a dedicated key registered to a spare email address, never your own key or address. Expect strangers to use it and fill it up.

## License

MIT, see [LICENSE](LICENSE).
