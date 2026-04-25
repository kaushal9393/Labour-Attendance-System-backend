# Garage Attendance System

Face-recognition attendance app — ArcFace + MediaPipe liveness, Flutter frontend, FastAPI backend.

---

## Project Structure

```
Labour System/
├── database/
│   └── schema.sql          ← Run this in Neon SQL Editor first
├── backend/                ← Python FastAPI
│   ├── main.py
│   ├── routers/
│   ├── core/
│   ├── models/
│   ├── utils/
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .env.example
└── frontend/               ← Flutter app
    ├── lib/
    │   ├── main.dart
    │   ├── core/
    │   ├── screens/
    │   │   ├── kiosk/
    │   │   └── admin/
    │   ├── widgets/
    │   ├── services/
    │   ├── models/
    │   └── providers/
    └── pubspec.yaml
```

---

## Step 1 — Database Setup (Neon)

1. Create a free project at **neon.tech**
2. Open SQL Editor → paste and run `database/schema.sql`
3. Copy the connection string (Settings → Connection Details)

---

## Step 2 — Backend Setup

```bash
cd backend
cp .env.example .env
# Fill in DATABASE_URL, JWT_SECRET, Cloudinary, Firebase values

pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Swagger UI: http://localhost:8000/docs

### Deploy to Render.com

1. Push backend folder to GitHub
2. New Web Service → connect repo
3. Build command: `pip install -r requirements.txt`
4. Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
5. Add environment variables from `.env`

---

## Step 3 — Flutter Setup

```bash
cd frontend
flutter pub get
```

Update the API base URL in `lib/core/constants.dart`:
```dart
static const String baseUrl = 'https://YOUR-APP.onrender.com/api';
```

### Firebase Setup
1. Create Firebase project → add Android app
2. Download `google-services.json` → place in `frontend/android/app/`
3. Enable Cloud Messaging in Firebase Console

### Run

```bash
flutter run                     # debug
flutter build apk --release     # production APK
```

---

## Default Test Login

| Field        | Value           |
|--------------|-----------------|
| Company Code | `GARAGE2024`    |
| Email        | `owner@garage.com` |
| Password     | `Admin@1234`    |

> Change the password hash in `database/schema.sql` before production.  
> Generate a new hash: `python -c "from passlib.context import CryptContext; print(CryptContext(schemes=['bcrypt']).hash('YourPassword'))"`

---

## App Modes

| Mode       | Device        | Entry Point        |
|------------|---------------|--------------------|
| Kiosk Mode | Android Tablet | `/kiosk/splash`   |
| Admin Mode | Owner Phone   | `/admin/login`     |

**Kiosk Admin PIN** (to access panel from kiosk): `1234`  
Change in `lib/core/constants.dart` → `kioskAdminPin`

---

## API Endpoints

| Method | Path                          | Description           |
|--------|-------------------------------|-----------------------|
| POST   | /api/auth/login               | Admin login           |
| GET    | /api/employees                | List employees        |
| POST   | /api/employees/register       | Register + face setup |
| PUT    | /api/employees/{id}           | Update employee       |
| DELETE | /api/employees/{id}           | Deactivate employee   |
| POST   | /api/attendance/scan          | Face scan (check-in)  |
| GET    | /api/attendance/today         | Today's attendance    |
| GET    | /api/attendance/monthly       | Monthly attendance    |
| GET    | /api/salary/monthly           | Salary breakdown      |
| GET    | /api/reports/monthly-summary  | Full month report     |
| GET    | /api/settings                 | Get settings          |
| PUT    | /api/settings                 | Update settings       |

---

## Environment Variables

```env
DATABASE_URL=postgresql+asyncpg://user:pass@host/dbname?ssl=require
JWT_SECRET=your_long_random_secret
JWT_EXPIRE_MINUTES=1440
CLOUDINARY_CLOUD_NAME=xxx
CLOUDINARY_API_KEY=xxx
CLOUDINARY_API_SECRET=xxx
FIREBASE_SERVICE_ACCOUNT=serviceAccount.json
```
