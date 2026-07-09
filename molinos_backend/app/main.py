import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth, usuarios, empleados, maquinas, molinos, asistencias, checador, bitacoras,areas
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, RedirectResponse


app = FastAPI(
    title="Molinos Backend",
    version="1.0.0",
)


# ============================================================
# NO CACHE
# Esto evita que Chrome guarde versiones viejas del Flutter Web
# ============================================================
@app.middleware("http")
async def no_cache_middleware(request, call_next):
    response = await call_next(request)

    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    return response

app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")


app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost",
        "http://localhost:8000",
        "http://localhost:8080",
        "http://127.0.0.1",
        "http://127.0.0.1:8000",
        "http://127.0.0.1:8080",
        "http://10.1.1.17",
        "http://10.1.1.17:8000",
        "http://10.1.1.17:8080",
    ],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1|10\.1\.1\.17)(:\d+)?",
    allow_credentials=True,
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
app.include_router(bitacoras.router, prefix="/api/v1/bitacoras", tags=["Bitacoras"])
app.include_router(areas.router, prefix="/api/v1/areas", tags=["Areas"])


@app.get("/")
def root():
    return {"message": "Molinos Backend funcionando"}



 # ============================================================
# FRONTEND FLUTTER WEB EN /molinosss/
# Copia aquí el contenido de build/web
# ============================================================
FRONTEND_DIR = r"C:\proyectos\molinos\molinos_frontend"


if os.path.isdir(FRONTEND_DIR):
    assets_dir = os.path.join(FRONTEND_DIR, "assets")

    if os.path.isdir(assets_dir):
        app.mount(
            "/molinos/assets",
            StaticFiles(directory=assets_dir),
            name="molinos_assets",
        )

    @app.get("/proyectos")
    async def redirect_proyectos():
        return RedirectResponse(url="/molinos/")

    @app.get("/molinos/")
    async def serve_molinos_index():
        index_path = os.path.join(FRONTEND_DIR, "index.html")
        return FileResponse(index_path)

    @app.get("/molinos/{full_path:path}")
    async def serve_molinos_flutter(full_path: str):
        file_path = os.path.join(FRONTEND_DIR, full_path)

        if os.path.isfile(file_path):
            return FileResponse(file_path)

        return FileResponse(os.path.join(FRONTEND_DIR, "index.html"))
    
