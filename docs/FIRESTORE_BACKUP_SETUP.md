# Masari optional Firestore backup

1. Firebase Console > Build > Firestore Database > Create database for project `masari-bb658`.
2. Use **production mode**, choose the region, and paste `firebase/firestore.rules` into Firestore > Rules, then **Publish**.
3. Sign in using Google in Masari. Open the cloud icon to **Back up** or **Restore missing items**.
4. Backup runs only after a button press. It saves **manual tasks and task plans only**. Moodle ICS links, auth tokens, passwords, Moodle event cache, and browser sessions must NEVER be uploaded.
5. Restore is additive; existing tasks/plans are not overwritten. Before switching devices, create a backup on the previous device and restore on the new device.
6. This first implementation is *manual backup*, not continuous two-way sync. Cloud backup replacement is explicit and confirmed. Avoid backing up an empty device before restoring, because upload replaces the previous snapshot.
7. Store rules must be deployed from Firebase Console. Committing the rules file alone does **not** activate Firestore or protect data.
8. Verify isolation: two different Google accounts cannot read each other's `users/{uid}/backups/personal-v1` data.
