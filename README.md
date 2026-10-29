# SimpleApi Auth client (Flutter web sample)

A small Flutter web app that shows how to use the free **SimpleApi Auth API**
(user accounts and login) from a browser app with no backend of your own.

Live demo (after Pages is enabled): https://simple-api-dev.github.io/auth-client/

## 1. Get a free key

Get a key at **https://keys.simpleapi.dev/?product=auth** and paste it into the
app's first screen. The key is saved only in your browser's `localStorage`; it
is not in the source code. The free tier allows 25 users per key.

## 2. Screens and the API calls they use

The API lives at `https://auth.simpleapi.dev`. Every request carries your key
as the `apikey` **query parameter** (not a header). Protected calls also send
`Authorization: Bearer <token>`. The API allows any origin (CORS), so the
browser calls it directly. Interactive docs: https://auth.simpleapi.dev/docs

| Screen | What it does | API call |
| --- | --- | --- |
| Key | Paste and save your key | none (stored in localStorage) |
| Log in | Log in; shows the 15 minute lockout after 5 wrong passwords | `POST /api/users/login` |
| Create an account | Register and be logged in | `POST /api/users/register` |
| Forgot password, step 1 | Email a 6 digit code | `POST /api/users/forgot` |
| Forgot password, step 2 | Set a new password with the code | `POST /api/users/reset` |
| Your account: Profile | Show the profile, edit the name | `GET /api/users/me`, `PUT /api/users/me` |
| Verify your email | Email a code, then confirm it | `POST /api/users/me/email/send-code`, `POST /api/users/me/email/verify` |
| Change email / Change password | Needs the current password | `PUT /api/users/me` |
| Log out | This device, or all devices | `POST /api/users/logout` (`{"all": true}` for all) |
| Delete account | Needs the password | `DELETE /api/users/me` |

The admin routes (`/api/users`, `/api/users/{id}`) are for the key owner and
are not used here.

Error messages are turned into plain language in `ApiException.plain`
(`lib/auth_api.dart`): wrong password, lockout, bad key, expired session, code
errors, daily email limits, and the 25 user limit.

## 3. Code tour

| File | Purpose |
| --- | --- |
| `lib/auth_api.dart` | The whole API client, with a comment per call naming its endpoint |
| `lib/app_controller.dart` | App state (key, logged-in user) as a `ChangeNotifier` |
| `lib/key_store*.dart` | Remembers the key in `localStorage` (via `dart:js_interop`) |
| `lib/screens/` | One file per screen |
| `lib/widgets.dart` | Small shared widgets and the busy/error helper for forms |
| `test/` | Unit and widget tests with a mocked HTTP client |

Dependencies: Flutter and the `http` package only. The session token is kept in
memory, so reloading the page logs you out; the key stays saved.

## 4. Run locally

```bash
flutter pub get
flutter test
flutter run -d chrome
```

## 5. Deploy

`.github/workflows/pages.yml` runs `flutter test`, builds with
`--base-href /auth-client/` and deploys with the official Pages actions on
every push to `main`. In the repository settings, set **Pages > Source** to
**GitHub Actions** once.
