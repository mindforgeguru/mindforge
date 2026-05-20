# Privacy Policy for Mindforge

**Effective date:** 19 May 2026
**Last updated:** 19 May 2026

> **Note to the publisher:** This policy has not been reviewed by a lawyer. If you operate in regulated jurisdictions (EU, US) or process payments, you should have legal counsel review it before publishing.

---

## 1. Who we are

Mindforge ("Mindforge", "we", "us", "our") is a school-management application operated by Chinmay Jobanputra, located at F-7 Maharaja Arcade, near Agrasen Bhavan, Citylight, Surat, India 395007.

For privacy questions, contact us at: chinmay1975@gmail.com

The school is the data controller for student, parent, teacher, and administrator data processed through Mindforge. Mindforge operates the application on behalf of the school.

## 2. Scope

This policy describes what data Mindforge collects, how we use it, who we share it with, how long we keep it, and the rights you have. It applies to the Mindforge mobile app (Android and iOS), the Mindforge web app, and the Mindforge backend API.

## 3. Information we collect

### 3.1 Information you provide

When an account is created (by the school administrator or via self-registration), we collect:

- Account details: username, role (student / teacher / parent / admin), MPIN (stored only as a one-way hash — we never store your raw MPIN), email address, phone number, profile picture (optional).
- Student academic profile: grade (8, 9, or 10), additional subjects selected, link to the parent account.
- Teacher profile: teachable subjects, short bio.
- Academic activity: attendance records, test scores and answers, homework submissions, fee payments and dues, timetable assignments, in-app feedback / problem reports you submit.
- Gamification data: XP, level, leaderboard standing, theme unlocks (students only).

### 3.2 Information collected automatically

- Device & technical data: device model, OS version, app version, language, time zone, IP address (recorded in audit-log entries for security and abuse prevention; retained per §9).
- Push-notification token: a Firebase Cloud Messaging (FCM) token tied to your install, used only to deliver app notifications. Deleted on logout and on account deletion.
- Crash & error reports: when the app crashes or the backend errors, Firebase Crashlytics (app) and Sentry (backend) collect a stack trace, device metadata, and a non-personal user identifier so we can diagnose and fix the bug.
- Analytics events: Firebase Analytics records anonymous events such as screen views, button taps, and session duration so we can understand which features are used and where users get stuck. We do not link analytics events to your real name.

### 3.3 Information we do not collect

We do not collect: precise GPS location, contacts, photos beyond what you explicitly upload, microphone or camera input outside of features you actively use, advertising identifiers, or data from other apps on your device.

## 4. How we use your information

We use the information above to:

- Operate the core academic features (attendance, tests, homework, fees, timetable, dashboards).
- Authenticate you, keep your session secure, and enforce role-based access.
- Send you push notifications about attendance, tests, homework, fees, and school announcements.
- Communicate progress to parents linked to a student account.
- Diagnose crashes and bugs (Crashlytics / Sentry) and improve the product (Analytics).
- Comply with the school's record-keeping obligations and respond to legal requests.

We do not sell your personal information. We do not use your information for advertising or for profiling unrelated to school activity. We do not train any AI models on student data. The AI providers we use (Google Gemini and Groq) operate under their own data-use terms — see their respective privacy policies for how they handle content submitted to their APIs.

## 5. AI features

Mindforge uses third-party AI services (Google Gemini and Groq) for features such as test grading and content generation. Where AI features process student-submitted content (e.g., a test answer), we send only the minimum data needed for the feature and do not send personally identifying fields (name, phone, email) as part of the AI prompt. Outputs are reviewed by teachers before being recorded.

Teachers may also upload source documents (chapter scans, past test papers, answer keys) when generating tests or grading. These files are sent in full to the AI provider so that questions, answer keys, or graded responses can be extracted. Such documents may incidentally contain identifying information (e.g., student names on a scanned answer sheet); we recommend teachers redact identifiable student information before uploading.

## 6. Children's privacy

Mindforge is a school application; the majority of student users are minors. Because of this:

- Accounts for students under 18 are created and managed by the school under the school's authority and with parental notice obtained by the school at enrolment.
- A linked parent account is provided so parents can view their child's academic data, receive notifications, and exercise privacy rights on the child's behalf.
- Parents may delete their child's account at any time by deleting their own linked parent account from the **Profile** screen — the linked student account is automatically deleted at the same time. Parents may also request the school admin to remove a specific student. Students cannot delete their own account from the app.
- We do not knowingly collect data from children outside of the school-mediated enrolment process. We do not show advertising. We do not use children's data for any purpose other than operating the school's academic features.

If you are a parent or guardian and believe your child's data has been collected without proper consent, contact us at chinmay1975@gmail.com and we will delete it.

This processing is covered, where applicable, by India's Digital Personal Data Protection Act, 2023 (with the school acting as the consent-obtaining entity for minors), and by COPPA / GDPR-K equivalents in jurisdictions where they apply.

## 7. Who we share data with

We share data only with the parties needed to run the service:

| Recipient | Purpose | Data shared |
|---|---|---|
| **The school you belong to** | Day-to-day operation — teachers see their students, admins see their school | Academic records, profile data |
| **Linked parent account** | Parental oversight | Their child's attendance, tests, homework, fees |
| **Railway** (backend hosting) | Hosts the backend API, database, and self-hosted object storage (MinIO) for profile pictures and uploaded documents | All stored data, encrypted in transit and at rest |
| **Firebase (Google) — Cloud Messaging** | Push notifications | Your FCM token, notification payload |
| **Firebase (Google) — Crashlytics** | Crash diagnostics | Crash stack traces, device metadata, anonymous user ID |
| **Firebase (Google) — Analytics** | Usage analytics | Anonymous event data |
| **Sentry** | Backend error tracking | Error stack traces, request metadata, anonymous user ID |
| **Google Gemini, Groq** | AI features (grading, content) | Only the minimum prompt content; no PII |

We do not share data with advertisers, data brokers, or unrelated third parties. We may disclose data when legally required (court order, lawful government request) or to protect against fraud, abuse, or harm to users.

## 8. Where your data is stored

Mindforge's backend, database, and object storage are hosted on Railway (United States). Firebase services are operated by their respective providers and may transfer data outside your country of residence. By using Mindforge you consent to this transfer; we rely on the providers' standard contractual and security measures for cross-border transfers.

For users in India, cross-border transfer of personal data is permitted under the conditions set by the Digital Personal Data Protection Act, 2023 and any rules or notifications issued thereunder by the Central Government.

## 9. How long we keep data

- **Active accounts:** for as long as the account is active at the school.
- **Soft-deleted accounts:** when you delete your account, we mark it as deleted, revoke your sessions, and clear your push-notification token immediately so the account can no longer be used. Underlying records are retained for at least 36 months for audit and dispute-resolution purposes, and then removed in accordance with the school's record-keeping schedule. Some academic records (such as grade transcripts) may be retained longer where the school is required to preserve them.
- **Database backups:** encrypted daily snapshots are taken by our hosting provider (Railway) and retained for **30 days** before being overwritten. Deleted account data may persist in these backups for up to 30 days after deletion, after which the snapshot containing it is permanently removed.
- **Crash and analytics data:** retained per Firebase / Sentry default retention windows (typically 90 days for crashes, up to 14 months for analytics).

## 10. Security

We protect your data with:

- MPINs are hashed with bcrypt — we never store or transmit them in plain text.
- All traffic is encrypted in transit (HTTPS / TLS).
- The mobile app uses SSL certificate pinning to prevent man-in-the-middle attacks.
- Session tokens are short-lived (60-minute access tokens, 30-day refresh tokens) and can be revoked server-side. Refresh tokens are stored in the device's secure storage (iOS Keychain / Android Keystore).
- Role-based access control restricts what each user can see and do.
- We log security-relevant events to an audit log.

No system is perfectly secure. If we become aware of a breach affecting your data, we will notify you and the relevant authorities as required by law.

## 11. Your rights

Depending on your jurisdiction, you have the right to:

- **Access** the personal data we hold about you.
- **Correct** inaccurate data.
- **Export** a machine-readable copy of your data — email us at chinmay1975@gmail.com to request one. We will respond within 30 days.
- **Delete** your account and associated data:
  - **Parents** — use **Profile → Privacy & Data → Delete my account**. Your linked student's account is deleted at the same time.
  - **Teachers** — use **Profile → Privacy & Data → Delete my account**.
  - **Students** — students cannot self-delete from the app. Ask your linked parent to delete their account (which also removes yours), or contact the school admin.
  - **Anyone** may also request deletion by emailing us at chinmay1975@gmail.com.
- **Object to or restrict** certain processing.
- **Withdraw consent** where processing is based on consent.
- **Lodge a complaint** with the data-protection authority in your jurisdiction (in India: the Data Protection Board, once operational).

For students under 18, these rights are typically exercised by a parent or guardian.

To exercise any right, email **chinmay1975@gmail.com** with your username and the action you want to take. We will respond within 30 days.

## 12. Cookies and browser storage

The Mindforge web app stores a short-lived session token and your role in your browser's `localStorage` so you stay logged in across page reloads. These tokens are removed automatically when you log out. We do not set advertising cookies and do not use third-party trackers on the web app.

## 13. Changes to this policy

We may update this policy from time to time. The "Last updated" date at the top reflects the most recent change. Material changes will be communicated via an in-app notice. Continued use of Mindforge after a change means you accept the updated policy.

## 14. App permissions

Mindforge requests the following operating-system permissions. Each is requested only at the point of first use, and the app continues to function (with the corresponding feature disabled) if you decline.

| Permission | When requested | Why |
|---|---|---|
| **Notifications** (iOS / Android) | First launch after login | To deliver attendance, test, homework, fee, and announcement alerts via Firebase Cloud Messaging. |
| **Photo library** (iOS / Android) | When you tap "upload profile picture" or attach a file to homework | To pick the image / document you want to upload. |
| **Camera** (iOS / Android) | When you choose "take a photo" instead of picking from the library | Same purpose as above. |
| **Storage** (Android) | When you download a generated test PDF or other document | To save the file to your device. |

We do not request: precise location, microphone, contacts, calendar, or background location.

## 15. Contact

Privacy questions, requests, or complaints:

**Grievance Officer:** Chinmay Jobanputra
**Mindforge** (operated by Chinmay Jobanputra)
**F-7 Maharaja Arcade, near Agrasen Bhavan, Citylight, Surat, India 395007**
Email: **chinmay1975@gmail.com**

We aim to acknowledge privacy requests within 7 working days and resolve them within 30 days.

---

*This policy is provided in good faith and is not legal advice.*
