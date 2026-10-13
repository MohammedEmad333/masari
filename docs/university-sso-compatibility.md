# University SSO / OAuth compatibility

Moodle authentication and Web Services authorization are separate capabilities. A successful login in a university browser session does **not** give Moodle Reminder permission to read assignments.

## Current behavior

- The app can open a user-supplied Moodle HTTPS login page in the **external browser**. No university password is collected by the app.
- This browser visit does not establish a session in Moodle Reminder, intercept a token, or silently connect Moodle Web Services.
- Existing iCalendar and user-provisioned Web Services token integrations stay independent.

## Requirements before implementing connected SSO

1. Obtain the university Moodle base URL and confirm the actual login mechanism (SAML, CAS, OIDC, Moodle mobile SSO, or an institution-specific authorization provider).
2. Obtain written configuration for a supported public-client authorization flow, registered app redirect URI, allowed scopes/functions and token revocation.
3. Use authorization code with PKCE where supported; require state validation and external-browser redirects. Never capture passwords or scrape pages.
4. Validate that issued credentials can call `core_webservice_get_site_info`, `core_enrol_get_users_courses`, and `mod_assign_get_assignments`. A browser login alone is insufficient.
5. Confirm that the selected callback and token mechanism can be safely used by this *independent app*. Do not assume Moodle's official mobile-app callback scheme or tokens are portable to Moodle Reminder.
6. Keep iCalendar available for institutions that do not grant third-party Web Services API access.

Reference: https://moodledev.io/docs/5.1/apis/subsystems/external

## Security caveat

The open-browser helper accepts only a Moodle HTTPS base URL without userinfo, query, or fragment. No access tokens are embedded in browser URLs.
