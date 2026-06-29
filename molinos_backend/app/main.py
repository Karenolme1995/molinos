from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth, usuarios, empleados, maquinas, molinos, asistencias, checador
from fastapi.staticfiles import StaticFiles


app = FastAPI(
    title="Molinos Backend",
    version="1.0.0",
)

app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(auth.router, prefix="/api/v1/auth", tags=["Auth"])
app.include_router(usuarios.router, prefix="/api/v1/usuarios", tags=["Usuarios"])
app.include_router(empleados.router, prefix="/api/v1/empleados", tags=["Empleados"])
app.include_router(maquinas.router, prefix="/api/v1/maquinas", tags=["Maquinas"])
app.include_router(molinos.router, prefix="/api/v1/molinos", tags=["Molinos"])
app.include_router(asistencias.router, prefix="/api/v1/asistencias", tags=["Asistencias"])
app.include_router(checador.router, prefix="/api/v1/checador", tags=["Checador"])

@app.get("/")
def root():
    return {"message": "Molinos Backend funcionando"}