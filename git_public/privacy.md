**AttendMate** ("we," "our," or "the App") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and protect your information when you use our mobile application, including attendance tracking, location & geofencing services, calendar synchronization, and Google Drive cloud backup features.
## 1. Information We Process
AttendMate operates on a **local-first architecture**. All your personal data, schedule information, and app preferences remain stored strictly on your device in a secure private database. We process:
- **Timetable & Attendance Schedules:** Subject names, acronyms, slot times, instructor names, and attendance records created or imported by you.
- **Location & Geofencing Data:** Optional classroom/campus geographic coordinates (latitude, longitude, geofence radius, and location names) configured by you for automated attendance reminders and proximity verification.
- **Google Account & Cloud Storage Credentials:** Your Google profile email address and OAuth tokens, used strictly to authenticate and sync events directly with your Google Calendar, and to maintain an optional cloud backup in your Google Drive.
## 2. Location & Geofencing Privacy
If you enable location features and grant location permissions:
- **On-Device Processing:** Location coordinates and geofences are evaluated solely on your physical device to trigger localized attendance verification and reminders when entering or leaving designated classroom areas.
- **Zero Remote Storage or Tracking:** Your location data is **never** transmitted to remote servers, uploaded to cloud databases, shared with third parties, or used for location tracking or advertising.
- **Permission Control:** Location permissions (including precise location and optional background location for auto-detection) are completely optional. You can grant or revoke these permissions at any time via your device settings or disable geofencing inside the App.
## 3. How We Use Your Google Calendar & Google Drive Data
To enable timetable synchronization and optional cloud backups, the App requests permission for the following OAuth scopes:
- https://www.googleapis.com/auth/calendar.events (view and edit events on your calendars).
- https://www.googleapis.com/auth/drive.file (view and manage Google Drive files and folders that you have opened or created with this app).
**Google Calendar Sync:** We use calendar access exclusively for creating, updating, rescheduling, and deleting class and lecture events inside your selected Google Calendar or Device Calendar.
**Google Drive Cloud Backup:** We use Google Drive access exclusively for storing a single backup file (attendmate_cloud_backup.json) in your personal Google Drive storage once daily at midnight (or upon manual trigger). AttendMate strictly uses the least-permissive drive.file scope and has **no access** to any other files or folders in your Google Drive.
## 4. Data Sharing & Third-Party Access
**Your data is private.** We do not share, sell, rent, or transmit your personal information, location data, calendar events, or email address with any third parties or remote analytics services.
- **No Remote Servers:** The App does not operate a backend server.
- **Direct API Communication:** Google OAuth authentication tokens and API requests are transmitted directly to Google's official API endpoints and nowhere else.
## 5. Security & Data Protection Mechanisms
We implement industry-standard security measures to protect your data on-device and in transit:
- **Encryption in Transit:** All network communication with Google APIs occurs over secure HTTPS (SSL/TLS 1.2 or TLS 1.3).
- **On-Device Security:** Google OAuth credentials and sensitive preferences are stored securely using Android's hardware-backed Keystore and encrypted storage mechanisms.
- **Application Sandboxing:** Your local SQLite database containing timetables, attendance history, and geofence locations is protected by system-level Android application sandboxing and Linux user isolation.
- **No Remote Server Retention:** Because there are no backend servers, your data cannot be exposed in remote database breaches.
## 6. Access Revocation and Data Deletion
You retain complete control over your data:
- **Google Account Disconnect:** You can disconnect your Google Account at any time in the App settings under Google Integrations, which immediately purges all stored OAuth tokens from your device.
- **Revoking Google Permissions:** You can revoke the App's access anytime via [Google Account Security](https://myaccount.google.com/permissions).
- **Location Permission Revocation:** You can revoke location access at any time through Android system settings.
- **Local Data Erasure:** Uninstalling the App or selecting "Clear App Data" in app settings permanently deletes all local attendance, timetable, and location data from your device.
- **Cloud Backup Deletion:** You can delete your cloud backup file at any time directly through Google Drive or by turning off cloud backup in the App.
## 7. Compliance with Google API Services User Data Policy
AttendMate's use and transfer of information received from Google APIs to any other app will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.
**Contact Me**
If you have any questions or feedback regarding this Privacy Policy, please contact me at:
Email: [venkatpiyush327@gmail.com](mailto:venkatpiyush327@gmail.com)
