# Masari language & device QA checklist (v2.2.10)

Automated Flutter tests verify translated notification text, proper nouns,
saved language, selected reminder rescheduling, data compatibility, and source
language propagation. They cannot prove OEM battery or foreground/background
notification behavior. Run the following checks on an installed, **official
signed APK**, not a CI smoke build.

## User actions

1. **Switch languages:** Settings → Language → Arabic and then English.
   Confirm home, tasks, study plan, calendar, courses, settings, dialogs,
   date/time pickers, errors and navigation labels change immediately.
   Restart Masari and confirm the chosen language persists.
2. **Immediate notification:** Select Arabic → Settings → Test notification.
   Confirm the title, description, and Android channel text are Arabic, say
   «مساري», and no longer say «Moodle Reminder». Repeat in English.
3. **Scheduled Arabic notification:** Create a task due in 10 minutes with a
   reminder 5 minutes before due. Exit to the home screen (do not force-stop
   the app). Confirm the notification arrives ~5 minutes later and labels
   are Arabic; task title remains as entered.
4. **Language switch with pending reminder:** Create a second task reminder,
   switch to English **before** it fires, then confirm the pending reminder
   uses English labels. Repeat in reverse to verify Arabic.
5. **Restart / reboot:** Create another reminder, close the app normally and
   reopen it; confirm the task and selected language remain. Reboot the phone
   and test scheduled delivery; OEM alarm policies can vary.
6. **Xiaomi/MIUI restrictions:** Verify notifications enabled, and if reminders
   are late, review the app's battery/background settings. Exact scheduling
   is not guaranteed when Android only permits inexact alarms.
7. **ICS calendar connection:** Test a private Moodle calendar link that
   downloads ICS in Chrome incognito, then test Connect → Refresh. If the
   link returns `Invalid authentication` even in incognito, it is a
   server-side token rejection and cannot be fixed by translating the app.
   Confirm connection errors follow the selected language.
8. **Offline:** Disconnect network and open the cached task/course list.
   Confirm tasks remain visible and offline/sync warning text is localized.
9. **Courses and sharing:** Add a local course with a chapter and a file,
   view its QR sharing dialog in Arabic and English, scan/import its link,
   and confirm saved course/file names are left unchanged.
10. **Widgets:** Place the Masari home-screen widget, select Arabic inside
    Masari while the phone's system locale remains English, and confirm
    the widget's fallback text/date switch to Arabic. Repeat for English.
11. **Other screens:** Check Pomodoro, study plan and course ZIP import
    preview. Open Moodle in the embedded WebView and confirm the **Masari**
    guidance and error banners match the selected language. Moodle's own
    remote web pages use the language configured on the university server.
12. **English test:** Change Masari to English and repeat one manual task
    creation, edit, delete, and an immediate notification.

## Expected limitations

- Moodle task/course titles, user notes, file names and imported content
  remain in their original languages; Masari does not silently translate them.
- Android system settings and university-hosted Moodle pages are outside
  Masari's own language selection.
- Flutter CI passing confirms code/Android build checks, not delivery of
  reminders under all battery/background restrictions.
- Do not share private calendar tokens in issue reports or screenshots.
