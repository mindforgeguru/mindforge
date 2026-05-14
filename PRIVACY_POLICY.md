# Privacy Policy for Mindforge

**Effective date:** [INSERT DATE BEFORE PUBLISHING]
**Last updated:** [INSERT DATE BEFORE PUBLISHING]

> **Note to the publisher:** Square-bracketed fields (e.g., `[School Name]`) must be filled in before this policy is published. This draft is a starting point and has not been reviewed by a lawyer. If you operate in regulated jurisdictions (EU, US, etc.) or process payments, you should have legal counsel review it before publishing.

---

## 1. Who we are

Mindforge ("Mindforge", "we", "us", "our") is a school-management application operated by **[School Name / Operator Legal Name]**, located at **[School Address]**.

For privacy questions, contact us at: **chinmay1975@gmail.com**

The school is the **data controller** for student, parent, teacher, and administrator data processed through Mindforge. Mindforge operates the application on behalf of the school.

## 2. Scope

This policy describes what data Mindforge collects, how we use it, who we share it with, how long we keep it, and the rights you have. It applies to the Mindforge mobile app (Android and iOS), the Mindforge web app, and the Mindforge backend API.

## 3. Information we collect

### 3.1 Information you provide

When an account is created (by the school administrator or via self-registration), we collect:

- **Account details:** username, role (student / teacher / parent / admin), MPIN (stored only as a one-way hash — we never store your raw MPIN), email address, phone number, profile picture (optional).
- **Student academic profile:** grade (8, 9, or 10), additional subjects selected, link to the parent account.
- **Teacher profile:** teachable subjects, short bio.
- **Academic activity:** attendance records, test scores and answers, homework submissions, fee payments and dues, timetable assignments, in-app feedback / problem reports you submit.
- **Gamification data:** XP, level, leaderboard standing, theme unlocks (students only).

### 3.2 Information collected automatically

- **Device & technical data:** device model, OS version, app version, language, time zone, IP address (logged transiently for security / abuse prevention).
- **Push-notification token:** a Firebase Cloud Messaging (FCM) token tied to your install, used only to deliver app notifications. Deleted on logout and on account deletion.
- **Crash & error reports:** when the app crashes or the backend errors, Firebase Crashlytics (app) and Sentry (backend) collect a stack trace, device metadata, and a non-personal user identifier so we can diagnose and fix the bug.
- **Analytics events:** Firebase Analytics records anonymous events such as screen views, button taps, and session duration so we can understand which features are used and where users get stuck. We do not link analytics events to your real name.

### 3.3 Information we do **not** collect

We do not collect: precise GPS location, contacts, photos beyond what you explicitly upload, microphone or camera input outside of features you actively use, advertising identifiers, or data from other apps on your device.

## 4. How we use your information

We use the information above to:

- Operate the core academic features (attendance, tests, homework, fees, timetable, dashboards).
- Authenticate you, keep your session secure, and enforce role-based access.
- Send you push notifications about attendance, tests, homework, fees, and school announcements.
- Communicate progress to parents linked to a student account.
- Diagnose crashes and bugs (Crashlytics / Sentry) and improve the product (Analytics).
- Comply with the school's record-keeping obligations and respond to legal requests.

We do **not** sell your personal information. We do **not** use your information for advertising or for profiling unrelated to school activity. We do **not** train AI models on student data.

## 5. AI features

Mindforge uses third-party AI services (**Google Gemini** and **Groq**) for features such as test grading and content generation. Where AI features process student-submitted content (e.g., a test answer), we send only the minimum data needed for the feature and do not send personally identifying fields (name, phone, email) as part of the AI prompt. Outputs are reviewed by teachers before being recorded.

**Teacher-uploaded source documents.** Teachers may upload chapter PDFs, old test papers, syllabus documents, and similar source material to power AI question generation. These files are transmitted to Google Gemini and/or Groq in their original form so the AI can read them. If a teacher uploads a document that itself contains student names or other personal information (for example, a scanned answer sheet or a previous year's exam with student names printed on it), that content will be sent to the AI provider as part of the source material. We recommend teachers redact or avoid uploading documents that contain personal information about identifiable students. Mindforge does not extract or store the contents of these documents beyond what is needed to generate the requested AI output.

## 6. Children's privacy

Mindforge is a school application; the majority of student users are minors. Because of this:

- Accounts for students under 18 are created and managed by the school under the school's authority and with parental notice obtained by the school at enrolment.
- A linked **parent account** is provided so parents can view their child's academic data, receive notifications, and exercise privacy rights on the child's behalf.
- Parents may at any time request deletion of their child's account via the in-app **"Delete my account"** button (Profile screen) or by emailing us.
- We do not knowingly collect data from children outside of the school-mediated enrolment process. We do not show advertising. We do not use children's data for any purpose other than operating the school's academic features.

If you are a parent or guardian and believe your child's data has been collected without proper consent, contact us at chinmay1975@gmail.com and we will delete it.

This processing is covered, where applicable, by India's Digital Personal Data Protection Act, 2023 (with the school acting as the consent-obtaining entity for minors), and by COPPA / GDPR-K equivalents in jurisdictions where they apply.

## 7. Who we share data with

We share data only with the parties needed to run the service:

| Recipient | Purpose | Data shared |
|---|---|---|
| **The school you belong to** | Day-to-day operation — teachers see their students, admins see their school | Academic records, profile data |
| **Linked parent account** | Parental oversight | Their child's attendance, tests, homework, fees |
| **Railway** (backend hosting) | Hosts the backend API and database | All stored data, encrypted in transit and at rest |
| **MinIO / object storage** | Stores profile pictures and uploaded documents | Uploaded files |
| **Firebase (Google) — Cloud Messaging** | Push notifications | Your FCM token, notification payload |
| **Firebase (Google) — Crashlytics** | Crash diagnostics | Crash stack traces, device metadata, anonymous user ID |
| **Firebase (Google) — Analytics** | Usage analytics | Anonymous event data |
| **Sentry** | Backend error tracking | Error stack traces, request metadata, anonymous user ID |
| **Google Gemini, Groq** | AI features (grading, content) | Minimum prompt content; no user PII fields. Teacher-uploaded source PDFs are sent in full — see Section 5. |

We do not share data with advertisers, data brokers, or unrelated third parties. We may disclose data when legally required (court order, lawful government request) or to protect against fraud, abuse, or harm to users.

## 8. Where your data is stored

Mindforge's backend and database are hosted on Railway (United States). Object storage and Firebase services are operated by their respective providers and may transfer data outside your country of residence. By using Mindforge you consent to this transfer; we rely on the providers' standard contractual and security measures for cross-border transfers.

## 9. How long we keep data

- **Active accounts:** for as long as the account is active at the school.
- **Soft-deleted accounts:** when you delete your account, we mark it as deleted, revoke your sessions, and clear your push-notification token immediately. Underlying records are retained for up to **[e.g., 12 months]** for audit and dispute-resolution purposes, then permanently removed, unless the school's record-keeping obligations require longer retention of academic records (e.g., grade transcripts).
- **Backups:** routine backups may retain a copy of deleted data for up to **[e.g., 30 days]** before being overwritten.
- **Crash and analytics data:** retained per Firebase / Sentry default retention windows (typically 90 days for crashes, up to 14 months for analytics).

## 10. Security

We protect your data with:

- MPINs are hashed with bcrypt — we never store or transmit them in plain text.
- All traffic is encrypted in transit (HTTPS / TLS).
- The mobile app uses **SSL certificate pinning** to prevent man-in-the-middle attacks.
- Session tokens are short-lived (60-minute access tokens, 30-day refresh tokens) and can be revoked server-side. Refresh tokens are stored in the device's secure storage (iOS Keychain / Android Keystore).
- Role-based access control restricts what each user can see and do.
- We log security-relevant events to an audit log.

No system is perfectly secure. If we become aware of a breach affecting your data, we will notify you and the relevant authorities as required by law.

## 11. Your rights

Depending on your jurisdiction, you have the right to:

- **Access** the personal data we hold about you.
- **Correct** inaccurate data.
- **Delete** your account and associated data — available in-app under **Profile → Privacy & Data → Delete my account**, or by emailing us.
- **Object to or restrict** certain processing.
- **Withdraw consent** where processing is based on consent.
- **Lodge a complaint** with the data-protection authority in your jurisdiction (in India: the Data Protection Board, once operational).

For students under 18, these rights are typically exercised by a parent or guardian.

To exercise any right, email **chinmay1975@gmail.com** with your username and the action you want to take. We will respond within 30 days.

## 12. Cookies and similar technologies

The Mindforge web app uses only essential cookies needed to keep you logged in. We do not use advertising cookies or third-party trackers on the web app.

## 13. Changes to this policy

We may update this policy from time to time. The "Last updated" date at the top reflects the most recent change. Material changes will be communicated via an in-app notice. Continued use of Mindforge after a change means you accept the updated policy.

## 14. Contact

Privacy questions, requests, or complaints:

**[School Name]**
**[School Address]**
Email: **chinmay1975@gmail.com**

---

*This policy is provided in good faith and is not legal advice.*
