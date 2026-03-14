# SRM JaAssure Lab Access System

A premium Lab Access Management System for SRM University, designed to streamline lab slot bookings, attendance tracking, and faculty approvals with a focus on **JaAssure** priority students.

## ✨ Features

- **Premium UI/UX**: Modern, responsive design using Flutter and Google Fonts.
- **Smart Booking**: Real-time capacity tracking for lab slots.
- **JaAssure Priority**: Automatic detection and prioritization of JaAssure students for high-demand slots.
- **Digital Entry Pass**: OTP-protected entry passes with QR Code support for seamless lab entry.
- **Faculty Dashboard**: Comprehensive control for faculty to create slots, approve requests, and monitor lab usage.
- **Persistent Logs**: History of all lab usage and approvals.

## 🛠️ Tech Stack

- **Frontend**: Flutter
- **Backend**: Supabase (PostgreSQL, Auth, Realtime)
- **State Management**: Provider
- **Design System**: Custom AppTheme with Outfit & Inter fonts

## 🚀 Getting Started

1. **Clone the repo**
   ```bash
   git clone https://github.com/abhirambuilds/SRMJaAsure.git
   ```
2. **Setup Supabase**
   - Import the `supabase_schema.sql` into your Supabase SQL Editor.
   - Configure your `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `lib/app_config.dart`.
3. **Run the App**
   ```bash
   flutter pub get
   flutter run
   ```

## 📸 Screenshots

*(Add screenshots here)*

## 📄 License

MIT License. See `LICENSE` for details.
