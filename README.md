# SimpleApi Auth client (Flutter web sample)

A small Flutter web app that shows how to use the free **SimpleApi Auth API**
(user accounts and login) from a browser app with no backend of your own.

Live demo: https://simple-api-dev.github.io/auth-client/

## 1. Keys

The live demo opens straight on the **Log in / Create an account** screen. It
uses a demo key that is compiled into the site at build time, so visitors do
not have to paste anything.

- **Use your own key.** Open **Settings**, paste a key from
  **https://keys.simpleapi.dev/?product=auth**, and save. The key is checked
  with the API, stored only in your browser's `localStorage`, and overrides the
  demo key. **Go back to the demo key** in Settings removes it again.
- **Free tier: 25 users per key.** The shared demo key can fill up. When it
  does, registering shows "The demo is full" and points to Settings. Accounts on
  the demo are shared and public, so do not use a real password.
- **No key built in?** Then the app shows "This demo has no key configured" with
  a **Get a free key** button, and makes no API calls until a key is pasted.

### Setting the build-time demo key (site owner)

The key comes from `String.fromEnvironment('SIMPLEAPI_KEY')` in
`lib/config.dart`; it is never committed. The Pages workflow passes it with
`--dart-define=SIMPLEAPI_KEY=${{ vars.SIMPLEAPI_KEY }}`.

> **Anything passed with `--dart-define` ends up readable in the public
> JavaScript** of the deployed site. Use a dedicated throwaway key registered to
> a throwaway email address, never your real key or your real address. Expect it
> to be used (and filled up) by strangers.

1. Get a key at https://keys.simpleapi.dev/?product=auth using a throwaway email.
2. In the repository go to **Settings > Secrets and variables > Actions >
   Variables** and create a **repository variable** named `SIMPLEAPI_KEY` with
   the key as its value. (A variable, not a secret: the value is public anyway.)
3. Re-run **Deploy to GitHub Pages** (or push to `main`).

If the variable is missing the site still builds, in "no key" mode.

## 2. Screens and the API calls they use

The API lives at `https://auth.simpleapi.dev`. Every request carries your key
as the `apikey` **query parameter** (not a header). Protected calls also send
`Authorization: Bearer <token>`. The API allows any origin (CORS), so the
browser calls it directly. Interactive docs: https://auth.simpleapi.dev/docs

| Screen | What it does | API call |
| --- | --- | --- |
| Settings | Paste your own key, check it, go back to the demo key | `POST /api/users/login` with an empty body (a good key answers 422, a bad key 401); stored in localStorage |
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
errors, daily email limits, and the 25 user limit (a 403 on register).

## 3. Code tour

| File | Purpose |
| --- | --- |
| `lib/auth_api.dart` | The whole API client, with a comment per call naming its endpoint |
| `lib/app_controller.dart` | App state (key, logged-in user) as a `ChangeNotifier` |
| `lib/config.dart` | The build-time demo key (`SIMPLEAPI_KEY`) |
| `lib/key_store*.dart` | Remembers your own key in `localStorage` (via `dart:js_interop`) |
| `lib/screens/` | One file per screen |
| `lib/widgets.dart` | Small shared widgets and the busy/error helper for forms |
| `test/` | Unit and widget tests with a mocked HTTP client |

Dependencies: Flutter and the `http` package only. The session token is kept in
memory, so reloading the page logs you out; your own key (if any) stays saved.

## 4. Run locally

```bash
flutter pub get
flutter test
flutter run -d chrome --dart-define=SIMPLEAPI_KEY=<your key>
```

Without `--dart-define` the app starts in "no key" mode; you can then paste a
key under Settings instead. Never commit a key.

## 5. Deploy

`.github/workflows/pages.yml` runs `flutter analyze` and `flutter test`, builds with
`--base-href /auth-client/` and `--dart-define=SIMPLEAPI_KEY=${{ vars.SIMPLEAPI_KEY }}`, and deploys with the official Pages actions on
every push to `main`. In the repository settings, set **Pages > Source** to
**GitHub Actions** once.
