/// The demo key compiled into the app at build time, or '' when none was given.
///
/// Set it with `--dart-define=SIMPLEAPI_KEY=<key>` (the Pages workflow passes
/// the SIMPLEAPI_KEY repository variable). Anything passed this way ends up
/// readable in the public JavaScript, so only ever use a dedicated throwaway
/// key here, never your real one. The key is not stored in this repository.
const configuredKey = String.fromEnvironment('SIMPLEAPI_KEY');

/// Where people can get their own free key for this API.
const getKeyUrl = 'https://keys.simpleapi.dev/?product=auth';
