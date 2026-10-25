# Masari optional Firestore backup

1. Firebase Console > Build > Firestore Database > Create database for project `masari-bb658`.
2. Use **production mode**, choose the region, and paste `firebase/firestore.rules` into Firestore > Rules, then **Publish**.
3. Sign in using Google in Masari. Open the cloud icon to **Back up** or **Restore missing items**.
4. Backup runs only after a button press. It saves **manual tasks and task plans only**. Moodle ICS links, auth tokens, passwords, Moodle event cache, and browser sessions must NEVER be uploaded.
5. Restore is additive; existing tasks/plans are not overwritten. Before switching devices, create a backup on the previous device and restore on the new device.
6. This first implementation is *manual backup*, not continuous two-way sync. Cloud backup replacement is explicit and confirmed. Avoid backing up an empty device before restoring, because upload replaces the previous snapshot.
7. Store rules must be deployed from Firebase Console. Committing the rules file alone does **not** activate Firestore or protect data.
8. Verify isolation: two different Google accounts cannot read each other's `users/{uid}/backups/personal-v1` data.

## Optional encrypted Moodle feed URL backup

- Publish the **updated** `firebase/firestore.rules` from this branch to Firebase Console > Firestore > Rules before trying calendar backup. The prior rules only allow manual-task backups and will deny the new `calendarSecrets` document.
- In Masari, sign into Google, open **Cloud backup** and select **Encrypted Moodle calendar links**. Back up the primary and additional ICS feeds. A unique encryption password of 12+ characters is required on upload and restore; **the password is not stored** and cannot be reset. Use a strong unique passphrase, not a Moodle/Google password.
- The new Firestore document at `users/{uid}/calendarSecrets/v1` stores AES-256-GCM encrypted ciphertext, PBKDF2 salt, nonce and tag, but never a plaintext token or URL. The account's Firestore access rules restrict this document to the authenticated owner.
- Restore saves only missing links into Android secure storage, then the user restarts the app. Expired Moodle URLs/tokens may still need replacement. No login cookies, Moodle passwords, and no automatic token syncing are included.
- The user's cloud-backup passphrase is needed separately on each device; Google authentication alone is not sufficient to decrypt the URLs.
