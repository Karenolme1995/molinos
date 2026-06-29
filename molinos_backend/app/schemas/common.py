from pydantic import BaseModel
from typing import Optional

class LoginIn(BaseModel):
    usuario: str
    password: str

class UsuarioIn(BaseModel):
    nombre: str
    usuario: str
    password: Optional[str] = None
    tipo: str = "usuario"
    area_id: Optional[int] = None
    correo: Optional[str] = None
    activo: int = 1

class EmpleadoIn(BaseModel):
    numero_nomina: Optional[str] = None
    nombre: Optional[str] = None
    foto: Optional[str] = None
    puesto: Optional[str] = None
    responsabilidades: Optional[str] = None
    fecha_nacimiento: Optional[str] = None
    telefono: Optional[str] = None
    direccion: Optional[str] = None
    status: Optional[str] = None
    departamento: Optional[str] = "MOLINOS"
    activo: int = 1

class MaquinaIn(BaseModel):
    nombre: str
    descripcion: Optional[str] = None
    id_area: Optional[int] = None
    activo: int = 1

class AsignarEmpleadoIn(BaseModel):
    empleado_id: int
    maquina_id: int
    fecha_jornada: str

class CambiarEstadoMaquinaIn(BaseModel):
    maquina_id: int
    estado: str
    observaciones: Optional[str] = None

class AcotacionEmpleadoIn(BaseModel):
    empleado_id: int
    clave: str
    fecha: str
    observaciones: Optional[str] = None
