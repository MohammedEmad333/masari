# Masari assistant — safe prototype (phase 1)

This feature is an **offline, read-only proof of concept**, not an AI model
integration. From the **Tasks** tab, open **Assistant preview** and try:

- `مهامي اليوم` / `Tasks today`
- `اعرض مهامي المتأخرة` / `Show overdue tasks`
- `مهامي الأسبوع القادم` / `Upcoming tasks this week` (means next 7 × 24 hours)
- `ذكّرني قبل ١٠ دقائق` / `Remind me 10 minutes before` (preview only)

## Phase 1 guarantees and limitations

- No HTTP calls, API keys, model access, remote service or new permissions.
- Reads only the already-loaded `activeDeadlines` passed to the screen.
- Does not inspect, display or transmit calendar URLs, Moodle auth tokens,
  event descriptions, stored credentials or cloud backup data.
- No writes: cannot create, edit, cancel, complete or reschedule a task, nor
  create notifications. Reminder text is a suggestion requiring manual action.
- Only simple Arabic/English examples are supported. Unsupported, ambiguous
  and mutation requests fail closed without making guesses.
- The time windows use instants for comparisons, and local calendar days for
  `today`. Only explicitly cancelled events are filtered; completed tasks
  have already been excluded by `AppController.activeDeadlines`.
- Recurring events are displayed only as their already-imported occurrences.
  The prototype does not generate future occurrences or expand rules.
- It is not a replacement for the existing reminders or calendar scheduler.

## Proposed phase 2: TokenRouter through an authenticated backend proxy

**Do not embed TokenRouter API keys in Flutter, `--dart-define`, GitHub source,
a public Firebase Remote Config value or any APK.** A client-side secret can
be extracted.

1. Deploy a dedicated HTTPS proxy. Store `TOKENROUTER_API_KEY` only in
   server-side secret storage.
2. Authenticate each request with a verified Firebase ID token (validate
   issuer, audience, expiration, signature). Enforce authorization,
   per-user rate limits, request body size limits, timeouts and cost quotas.
3. Require explicit user consent before sending task metadata outside the
   phone. Default to minimal task IDs, short titles and due instants,
   excluding personal notes, Moodle URLs, calendar tokens and credentials.
4. Never trust generated instructions as executable operations. Accept
   strictly validated JSON proposals such as:
   `{"intent":"preview_reminder","task_id":"...","minutes_before":10}`.
   Reject nonexistent/ambiguous task IDs, cancelled deadlines, malformed
   date/times, out-of-range durations and unauthorized users.
5. Display the exact target task, source timezone, due time and proposed
   change for explicit confirmation. Revalidate against current local
   state immediately before a separately audited write action.
6. Keep Moodle/Google synchronization, backup and notification scheduling
   unchanged until the new approval workflow is tested on a real device.
7. Use backend-only telemetry without prompt bodies or secrets, and document
   TokenRouter retention and provider policies before production use.

## Tests / release gate

Run `dart format --output=none --set-exit-if-changed lib test`,
`flutter analyze`, and `flutter test` in the existing Flutter CI. Check:

- Arabic-Indic digits and reminder intervals outside the permitted range
- cancelled and historical events
- local-day boundaries and upcoming time window
- ambiguous / destructive requests rejected
- no changes to Moodle, Google synchronization, notifications, storage or
  the APK signing pipeline

No live TokenRouter integration or claims of AI-generated answers are made
by this phase.
