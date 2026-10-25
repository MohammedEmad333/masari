# Task plans: implementation and verification

## Scope
PR #107 introduces a local step model, persistence, and a bilingual task-plan screen reachable from the app bar. Task plans are keyed to the Moodle event stable key and stored apart from the ICS deadline cache.

## Required before merge
- [ ] Run `dart format lib/models/task_step.dart lib/services/task_plan_repository.dart lib/screens/task_plans_screen.dart lib/screens/home_shell.dart test/task_plan_test.dart`, commit the result, and confirm CI formatting passes.
- [ ] Run `flutter analyze` and correct analyzer warnings.
- [ ] Run `flutter test` and Android build checks.
- [ ] Test creating, completing, deleting steps and reboot persistence on device.
- [ ] Confirm the plan remains after Moodle ICS refresh and background sync.
- [ ] Verify layout on narrow screens and Arabic RTL.
- [ ] Confirm duplicate IDs and source changes do not cross-contaminate task plans.

## Next iteration
- Editing step titles and dates, and a confirmation for destructive deletion.
- Move the plan entry point into task details for context-sensitive access.
- Keep collaborative task assignments and AI scheduling in separate PRs; neither is part of this branch.
