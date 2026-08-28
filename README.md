# ⛽ SmartFuel Dashboard & Management System

[![Flutter](https://img.shields.io/badge/Frontend-Flutter-blue?logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI-green?logo=fastapi)](https://fastapi.tiangolo.com)
[![Firebase](https://img.shields.io/badge/Database-Firebase-FFCA28?logo=firebase)](https://firebase.google.com)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

SmartFuel is a comprehensive fuel telemetry, station management, and consumption monitoring dashboard system. It provides real-time sensor monitoring, station location tracking, fuel quality analysis, and backend API integration for modern fuel station networks.

---

## 📁 Repository Structure

```
SmartFuel/
├── 📱 frontend/              # Flutter Dashboard Application
│   ├── lib/                  # Application source code (Pages, Widgets, Telemetry)
│   ├── android/              # Android native configuration
│   ├── ios/                  # iOS native configuration
│   ├── web/                  # Web app entrypoint & assets
│   ├── pubspec.yaml          # Flutter dependencies
│   ├── .env.example          # Frontend environment variables template
│   └── README.md             # Frontend setup guide
│
├── ⚙️ backend/               # FastAPI Backend Service
│   ├── main.py               # Telemetry & Station API endpoints
│   ├── requirements.txt      # Python dependencies
│   ├── .env.example          # Backend environment variables template
│   └── README.md             # Backend setup guide
│
├── .gitignore                # Git exclusion rules (Secures .env & credentials)
└── README.md                 # Main repository documentation
```

---

## 🚀 Quick Setup & Installation

### 1️⃣ Frontend Setup (Flutter App)

1. Navigate to the `frontend` folder:
   ```bash
   cd frontend
   ```

2. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

3. Open `.env` and fill in your backend URL and Firebase API keys:
   ```env
   BACKEND_BASE_URL=http://127.0.0.1:8000
   FIREBASE_PROJECT_ID=your_firebase_project_id
   FIREBASE_WEB_API_KEY=your_web_api_key
   FIREBASE_ANDROID_API_KEY=your_android_api_key
   ```

4. Install dependencies and run:
   ```bash
   flutter pub get
   flutter run
   ```

---

### 2️⃣ Backend Setup (FastAPI Service)

1. Navigate to the `backend` folder:
   ```bash
   cd backend
   ```

2. Setup virtual environment and install requirements:
   ```bash
   python -m venv venv
   # On Windows:
   .\venv\Scripts\activate
   # On Linux/macOS:
   source venv/bin/activate

   pip install -r requirements.txt
   ```

3. Run the backend server:
   ```bash
   python main.py
   ```
   *The backend will start at `http://127.0.0.1:8000` with interactive API docs at `http://127.0.0.1:8000/docs`.*

---

## 🔐 Security Note

All API keys, database URLs, and private IP addresses are strictly excluded from version control using `.gitignore`.  
- Do **NOT** commit your `.env` or `google-services.json` files to public repositories.
- Use `.env.example` and `google-services.json.example` as reference templates.

---

## 🌐 Repository URL

- **GitHub Repository**: [https://github.com/waleedawan14/SmartFuel.git](https://github.com/waleedawan14/SmartFuel.git)
