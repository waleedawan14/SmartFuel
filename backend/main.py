"""
SmartFuel Backend API Service
FastAPI implementation for telemetry, station management, and real-time dashboard data.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timezone
import random

app = FastAPI(
    title="SmartFuel API",
    description="Backend service for SmartFuel Dashboard",
    version="1.0.0"
)

# Enable CORS for Flutter Web & Mobile clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def read_root():
    return {
        "status": "online",
        "service": "SmartFuel Backend API",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/telemetry/latest")
def get_latest_telemetry():
    """
    Returns simulated real-time telemetry data for fuel tanks and sensors.
    """
    return {
        "tank_id": "TK-4029",
        "station_name": "Central Station #1",
        "fuel_level_liters": round(random.uniform(3500.0, 4800.0), 2),
        "capacity_liters": 5000.0,
        "temperature_celsius": round(random.uniform(18.5, 24.2), 1),
        "pressure_psi": round(random.uniform(14.2, 15.1), 2),
        "quality_index": "98.5%",
        "status": "NORMAL",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/health")
def health_check():
    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
