# Masari / مساري | Visual Identity & UI Design System

> Status: **Design Foundation v1.0 (proposed for Masari 2.3)**. Maintains the existing brand and app icon. This is a product UI guide, not a logo replacement or a claim that all screens have been redesigned.

## 1. Brand idea | فكرة الهوية

**مساري: خطتك الدراسية في مكان واحد.**

Masari should feel calm, organized, trustworthy and student-focused. The interface puts the next useful action ahead of decorative dashboards. Preserve the existing bilingual product name **مساري / Masari** and the registered Android identity `com.mohammedemad333.masari`.

Brand personality: clear, encouraging, practical, private-by-default. Avoid confusing status colors, excessive gradients, gamified pressure and unnecessary animations.

## 2. Logo & existing assets | الشعار

- Preserve the current launcher icon and the in-app name. Source: `android/app/src/main/res/drawable-nodpi/masari_launcher.webp` and the existing Android resources.
- Do not stretch, recolor or place text over the launcher artwork. Keep generous padding around it.
- Dark/light app surfaces must not depend on a differently signed or newly identified Android app.
- A redesigned icon, splash screen or marketing illustration requires a separately reviewed brand proposal; this phase does **not** change them.

## 3. Color system | الألوان

| Role / الاستخدام | Hex | Notes |
| --- | --- | --- |
| Brand Primary / الأزرق الأساسي | **#0D63C8** | Main actions, links and brand anchors in light mode |
| Deep Navy / الكحلي | **#102843** | Headings, hero gradient end and dark foreground on bright backgrounds |
| Teal / الفيروزي | **#17A398** | Decorative progress and positive accents; not small text on white |
| Warm Gold / الذهبي | **#F3B95F** | Supportive highlights, not a standalone error or warning indicator |
| Canvas Light / خلفية فاتحة | **#F4F7FB** | Light page background |
| Surface Light / سطح فاتح | **#FFFFFF** | Cards and fields |
| Canvas Dark / خلفية داكنة | **#0C1628** | Dark page background |
| Surface Dark / سطح داكن | **#172B45** | Dark cards and fields |
| Primary Dark / تفاعل داكن | **#8DBBFF** | Primary controls on dark surfaces |

**Semantic color rules:** use `Theme.of(context).colorScheme` for text, error, surfaces and state feedback. Never rely on teal/gold/blue alone to communicate urgency, completion or an error. Pair color with icons and descriptive copy. Verify text contrast (WCAG AA: 4.5:1 for normal text, 3:1 for large text and non-text UI boundaries).

**Hero treatment:** restrained gradient `#0D63C8 → #102843`, white type, maximum one hero region per primary screen. Do not put long paragraphs over a gradient.

## 4. Typography | الخطوط

- Phase 1 uses Flutter platform fallback typography with Arabic and English shaping; no new external font files or network requests.
- Heading hierarchy: display 28 / section 20 / card title 16 / body 14–16 / meta 12–14 logical pixels, with user text scaling respected.
- Avoid all-caps in Arabic, artificial RTL reversal and fixed heights that truncate text.
- Keep user-supplied course names, file names, notes and deadlines in their original language.
- Use `TextDirection` and `AlignmentDirectional` rather than manually reversing every icon or string.

## 5. Spacing, shapes & interaction | المسافات والمكونات

| Token | dp | Purpose |
| --- | ---: | --- |
| `xs` | 4 | Compact icon-text spacing |
| `sm` | 8 | Related labels |
| `md` | 12 | Item gaps |
| `lg` | 16 | Standard horizontal page padding |
| `xl` | 24 | Section and card breathing room |
| `xxl` | 32 | Large separation |
| `radiusSm` | 12 | Small controls |
| `radiusMd` | 16 | Inputs and actions |
| `radiusLg` | 24 | Cards and hero surfaces |

Primary buttons and icon targets should be at least **48 × 48 dp**. Support 320dp phones and large text scale without clipping. Use purposeful, brief transitions and avoid animation on critical alerts.

**Initial component inventory (Flutter):** `MasariSectionHeader`, `MasariEmptyState`, `MasariSettingsSection` and global `MasariTheme` / `MasariColors` / `MasariSpacing` / `MasariRadii`. New screens should consume these tokens, not invent one-off colors and radii.

## 6. Navigation information architecture | هيكلة التنقّل

**Current production:** Home, Tasks, Study plan, Calendar, Courses, Settings (six bottom destinations).

**Planned redesign (later PR, not Phase 1):**

1. **الرئيسية / Home**: today overview, next deadline and focused shortcuts.
2. **المهام / Tasks**: upcoming, completed, course filters and manual task creation.
3. **جدولي / My schedule**: unified calendar, weekly plan and Pomodoro.
4. **المساقات / Courses**: Moodle courses and the local study library.
5. **المزيد / More**: account, syncing, backup, settings and the opt-in assistant entry point.

Before changing navigation, map existing deep links, `IndexedStack` tab state, account screens, offline flows and the action that opens the assistant. Keep functionality discoverable, avoid destructive migrations and test back behavior.

## 7. UX writing, RTL & accessibility | الكتابة والاتجاه

- Arabic-first review with equivalent English labels. Avoid untranslated technical errors on end-user screens.
- Provide loading, offline, empty, error, permission-denied and retry states, with the next action stated clearly.
- Navigation labels and date formats follow the selected language; dates and course titles remain correctly formatted.
- Do not expose calendar access tokens, Firebase/Oracle bearer tokens or file paths in UI captures.
- Semantics for actionable icons, high contrast, text scaling, screen-reader order and large tap targets are acceptance requirements.
- On Arabic screens, directional icons must be mirrored or replaced with direction-neutral symbols where appropriate.

## 8. Phase-by-phase implementation | خطة التنفيذ

| PR phase | Scope | Guardrail |
| --- | --- | --- |
| 1. Foundation | Brand guide, palette, ThemeData, reusable UI primitives and widget tests | No navigation or business-model changes |
| 2. Navigation | Five-destination information architecture, account/settings grouping | Preserve all routes, action entry points and tab state |
| 3. Dashboard | Next deadline, daily focus, insights, offline and sync feedback | Do not change calendar sync or scheduling logic |
| 4. Tasks + calendar | Search, filter, agenda, timeline and task cards | Existing deadlines and completion IDs remain unchanged |
| 5. Courses + library | Course folders, chapter/file hierarchy, ZIP import/share UX | Keep local files and ZIP safety intact |
| 6. Settings + assistant | Connection, backup, profile, AI consent states | Preserve existing Oracle/Firebase security flows |
| 7. Release QA | Golden/widget/accessibility tests, real-device QA and APK | Publish a new version only after explicit release gate |

## 9. Files, owners & quality gates

- Canonical document: `docs/brand/MASARI_VISUAL_IDENTITY.md`.
- Source of truth for tokens: `lib/theme/masari_theme.dart` and `lib/theme/masari_components.dart`.
- Tests: `test/masari_design_system_test.dart` and existing application regression suite.
- All brand/design changes go through a feature branch, pull request and full Flutter CI. Do not merge unreviewed designs into a release branch.
- **No app version bump during the foundation phase**: production `v2.2.19` stays released as-is. Main-branch CI automatically invokes an official APK publishing workflow; avoid triggering it until the release impact is intentional.

## 10. Definition of done for Phase 1

- [ ] Theme builds in light and dark modes, with primary/surface contrast checks.
- [ ] Shared widgets render correctly in Arabic RTL and English LTR at narrow widths.
- [ ] Home screen uses the shared components without losing any screen or action.
- [ ] `dart format`, `flutter analyze`, `flutter test`, APK smoke and AAB smoke pass on the PR commit.
- [ ] Brand guide and implementation stay in sync; no persistent data schema, signing keys, package IDs or back-end changes.

---

**Design direction, not a finished-screen claim.** The existing app continues to be the baseline until the individual PRs pass their QA gates.
