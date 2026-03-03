# Adhiparasakthi Engineering College - Digital Clearance System

A high-security, role-based Flutter + Firebase application designed for streamlined digital fee clearance and certification at Adhiparasakthi Engineering College. The system eliminates manual paperwork, enforces automated payment verification through AI-powered OCR, and issues tamper-proof digital clearance certificates.

## 🎯 Project Goals

- **Zero Paperwork**: Move the entire clearance process to a secure digital workflow.
- **Financial Integrity**: Algorithmic verification of payments to prevent fraud.
- **Forgery Prevention**: Publicly verifiable certificates using unique cryptographic IDs and QR codes.
- **Automated Communication**: Multichannel alerts (FCM, Email, SMS) for parents and students.

---

## 👥 User Roles & Access Control

### 🎓 Students
- **Smart Registration**: Verify identity and provide parent contact details.
- **Fee Management**: View personalized fee structures based on Department, Batch, and Quota.
- **Flexible Payments**: Pay via UPI, QR Code, or Demand Draft (DD).
- **AI Receipt Submission**: Upload screenshots with automatic OCR detail extraction.
- **Digital No-Dues**: Generate and download secure PDFs once all dues are cleared.

### 💼 Staff / HODs
- **Departmental Dashboard**: Monitor all students within their specific department.
- **Live Status Tracking**: View real-time payment progress (PAID, OVERDUE, PENDING).
- **Audit Reports**: Download comprehensive Student Fee Statements as PDFs.
- **Departmental Approval**: Tracking clearance status for departmental records.

### 🛡️ Admin (Accounts/Office)
- **User Governance**: Approve or reject Student and Staff registration requests.
- **Dynamic Fee Engine**: Configure targeted fees for specific batches, quotas, and academic years.
- **Payment Verification**: Dual-view audit panel with text tampering detection (Original OCR vs. Student Submitted Data).
- **Bulk Reminders**: Trigger automated SMS/Email reminders to students approaching or past fee deadlines.
- **Reporting & Analytics**: Export comprehensive fee statements and audit logs for financial records.

---

## 🔍 Core Technologies & Algorithms

### 🤖 AI-Powered OCR (Google ML Kit)
The system uses on-device machine learning to scan receipts:
- **Regex Extraction**: Specialized patterns for Transaction IDs, Dates, and Amounts.
- **DD Support**: Native support for extracting Demand Draft numbers and issuing Bank/Branch details.
- **Probability Scoring**: An algorithm that calculates a 1-100 score for extracted amounts. Amounts matching the expected fee receive a **+100 boost** for automatic pre-filling.

### 🛡️ Text Tampering Detection
To ensure absolute data integrity:
- The system captures **Original OCR Data** and compares it with **Student Submitted Data**.
- Any discrepancy flags the payment for Admin review with a **"⚠️ Manual Entry"** alert, preventing digital forgery of screenshots.

### 🔏 Tamper-Proof Certificates
- **UUID Security**: Every certificate has a mathematically unique ID.
- **QR Verification**: A scannable QR code allows anyone (Public) to verify the document against the live database.

### 📱 Cloud Automation (Firebase V2)
- **Scheduled Reminders**: Daily at 10:00 AM IST for upcoming deadlines (7/3/1 days).
- **Registration Welcome**: Automatic SMS to parents with full fee breakdown and **HOD Signature**.
- **Instant Alerts**: SMS and Push notifications for fee changes and payment approvals.
- **Launcher/badge support**: mobile push notifications automatically update the external launcher icon with the unread count (Android & iOS) using the `flutter_app_badger` package. On web, the browser title shows `(<count>) A‑DACS` and the experimental Badge API (`navigator.setAppBadge`) is invoked when supported; this keeps users aware of pending items even when the tab is inactive.

  ⚠️ **Android notification icon** – the system uses the icon defined under `android/app/src/main/res/mipmap-*` for the launcher, but notifications themselves require a special _transparent_ monochrome icon (typically named `ic_stat_ic_notification.png`) placed under `drawable-` folders. If you see the Flutter logo instead of your app's symbol on incoming messages, add appropriate notification icon assets and set `android:icon="@mipmap/ic_launcher"` or use `AndroidNotificationDetails.icon` as shown in `notification_service.dart`.

---

## 🏗️ Technical Stack

| Layer | Technology |
|---|---|
| **Frontend** | Flutter 3.10.7+ (Android & Web) |
| **Backend** | Firebase (Firestore, Auth, Storage) |
| **Serverless** | Node.js Cloud Functions (V2) |
| **SMS Gateway** | Twilio API (Bilingual Support - English & Tamil) |
| **OCR** | Google ML Kit Text Recognition (On-Device) |
| **State Management** | Provider Pattern |
| **Notifications** | Firebase Cloud Messaging (FCM) |

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.10.7 or higher)
- Firebase CLI
- Node.js 18+ (for Cloud Functions)
- Twilio Account (for SMS notifications)

### Installation
```bash
# 1. Clone the repository
git clone https://github.com/Jayasrip08/A-DACS.git
cd apec_no_dues

# 2. Install Flutter dependencies
flutter pub get

# 3. Setup Firebase
firebase login
flutterfire configure

# 4. Setup Cloud Functions secrets
cd functions
npm install
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_AUTH_TOKEN
firebase functions:secrets:set TWILIO_PHONE_NUMBER

# 5. Deploy Cloud Functions
firebase deploy --only functions

# 6. Run the app
cd ..
flutter run -d chrome  # For web
flutter run -d android  # For Android
```

### 🔐 Master Admin Credentials (Bootstrap)
The system auto-creates a master admin on first run:
- **Email**: `sri17182021@gmail.com`
- **Password**: `ApecAdmin@2026` (must be changed after first login)
- **Role**: System Administrator
- **Employee ID**: `420422205001`

---

## 📚 Documentation

For detailed technical documentation, architecture details, and API specifications, see [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md).

---

## 🏫 Institution

**Adhiparasakthi Engineering College**  
Tamil Nadu, India  
An autonomous institution dedicated to quality engineering education.

---

## 📝 License

This project is proprietary to Adhiparasakthi Engineering College.

---

**Adhiparasakthi Engineering College - Digital Clearance System**  
Development Team | 2026  
**Repository**: https://github.com/Jayasrip08/A-DACS
