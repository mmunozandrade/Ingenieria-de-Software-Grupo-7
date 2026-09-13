from fastapi import FastAPI, Depends, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from fastapi.responses import Response
from pydantic import BaseModel
from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta
import psycopg2
import os
from dotenv import load_dotenv
import zipfile
import io
import re
import secrets
import string
import datetime as dt
import calendar
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
import resend
from dateutil.relativedelta import relativedelta
import openpyxl
from pypdf import PdfReader
from pypdf.errors import PdfReadError
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

load_dotenv()

app = FastAPI(title="API Remuneraciones Aconcagua")

# ── CORS ──────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── CACHE DE MEMORIA (solo dentro de una misma peticion) ──────
# Evita que una sola peticion (ej: "Costo Total Empleador", que
# internamente llama a AFP+AFC+Impuesto Unico juntos) recalcule
# calcular_total_imponible_interno 2 o 3 veces desde cero.
# Se limpia OBLIGATORIAMENTE al inicio de cada peticion nueva
# (middleware de abajo), asi que jamas puede sobrevivir de un
# clic al siguiente, ni mostrar un dato desactualizado.
_cache_total_imponible: dict = {}


@app.middleware("http")
async def limpiar_cache_por_peticion(request, call_next):
    _cache_total_imponible.clear()
    response = await call_next(request)
    return response

# ── JWT ───────────────────────────────────────────────────────
SECRET_KEY = "aconcagua_secret_key_2024_remuneraciones"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60

# ── BCRYPT ────────────────────────────────────────────────────
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=12)
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

# ── CONEXIÓN SUPABASE ─────────────────────────────────────────
def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        sslmode='require'
    )

# ── RESEND EMAIL ──────────────────────────────────────────────
def enviar_email(destinatario: str, asunto: str, contenido_html: str) -> bool:
    try:
        resend.api_key = os.getenv("RESEND_API_KEY")
        params = {
            "from": os.getenv("RESEND_FROM_EMAIL", "onboarding@resend.dev"),
            "to": [destinatario],
            "subject": asunto,
            "html": contenido_html,
        }
        resend.Emails.send(params)
        return True
    except Exception as e:
        print(f"ERROR enviando email: {e}")
        return False

# ── VERIFICACION DE CUENTA (correo de activacion) ───────────────
FRONTEND_URL = os.getenv("FRONTEND_URL", "https://tu-frontend.vercel.app")

def generar_y_enviar_verificacion(cuenta_id: int, correo: str) -> bool:
    """
    Genera un token unico de activacion (valido 24 horas), lo guarda
    en verificacion_cuenta, y envia el correo con el enlace usando la
    misma funcion enviar_email() ya usada en el resto del sistema.
    Se usa tanto en el registro inicial como en cada reenvio.
    """
    token = secrets.token_urlsafe(32)
    expiracion = datetime.utcnow() + timedelta(hours=24)

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO verificacion_cuenta (cuenta_id, token, fecha_expiracion)
           VALUES (%s, %s, %s)""",
        (cuenta_id, token, expiracion)
    )
    conn.commit(); cursor.close(); conn.close()

    link_activacion = f"{FRONTEND_URL}/verificar-cuenta/{token}"
    html = f"""
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background-color: #001E42; padding: 20px; text-align: center;">
            <h1 style="color: white; margin: 0;">Clínica Aconcagua</h1>
        </div>
        <div style="padding: 30px; background-color: #f8fafc;">
            <h2 style="color: #001E42;">Activa tu cuenta</h2>
            <p>Gracias por registrarte en el Sistema de Remuneraciones de Clínica Aconcagua.</p>
            <p>Para activar tu cuenta, haz clic en el siguiente enlace. Este enlace es válido por
            <strong>24 horas</strong> a partir de este momento:</p>
            <div style="text-align: center; margin: 30px 0;">
                <a href="{link_activacion}"
                   style="background-color: #001E42; color: white; padding: 14px 28px;
                          text-decoration: none; border-radius: 8px; font-weight: bold;">
                    Activar mi cuenta
                </a>
            </div>
            <p style="font-size: 12px; color: #64748B;">Si el botón no funciona, copia y pega este
            enlace en tu navegador: {link_activacion}</p>
            <p style="font-size: 12px; color: #64748B;">Si este enlace expira, puedes solicitar uno
            nuevo desde la pantalla de inicio de sesión.</p>
            <p>Atentamente,<br><strong>Sistema de Remuneraciones</strong><br>Clínica Aconcagua</p>
        </div>
    </div>
    """
    return enviar_email(
        destinatario=correo,
        asunto="Activa tu cuenta - Sistema de Remuneraciones Clínica Aconcagua",
        contenido_html=html,
    )

# ── SEGURIDAD ─────────────────────────────────────────────────
def verificar_contrasena(contrasena_plana: str, contrasena_hash: str) -> bool:
    try:
        return pwd_context.verify(contrasena_plana, contrasena_hash)
    except Exception:
        return contrasena_plana == contrasena_hash

def encriptar_contrasena(contrasena: str) -> str:
    return pwd_context.hash(contrasena[:72])

def crear_token(data: dict) -> str:
    datos = data.copy()
    expiracion = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    datos.update({"exp": expiracion})
    return jwt.encode(datos, SECRET_KEY, algorithm=ALGORITHM)

def verificar_token(token: str = Depends(oauth2_scheme)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        correo = payload.get("sub")
        if correo is None:
            raise HTTPException(status_code=401, detail="Token invalido")
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Token expirado o invalido")

def manejar_error_interno(e: Exception, modulo: str = "General", nivel: str = "Critico", payload: dict = None) -> str:
    """
    Registra el error tecnico real tanto en el log del servidor (para
    revision inmediata) como en la tabla log_errores_tecnicos (para
    auditoria formal, #21), y devuelve al usuario un mensaje generico
    en español, sin exponer detalles internos, codigos ni trazas.

    Si se pasa el 'payload' del admin autenticado (cuando existe),
    tambien se guarda quien estaba usando el sistema en ese momento.
    """
    descripcion = f"{type(e).__name__}: {e}"
    print(f"[ERROR INTERNO] {modulo}: {descripcion}")
    try:
        administrador_id = None
        if payload:
            persona_id_payload = payload.get("persona_id")
            if persona_id_payload:
                conn_lookup = get_connection()
                cursor_lookup = conn_lookup.cursor()
                cursor_lookup.execute(
                    "SELECT administrador_id FROM administrador WHERE persona_id = %s",
                    (persona_id_payload,)
                )
                admin_row = cursor_lookup.fetchone()
                administrador_id = admin_row[0] if admin_row else None
                cursor_lookup.close(); conn_lookup.close()

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO log_errores_tecnicos (modulo, descripcion_tecnica, nivel_criticidad, administrador_id)
               VALUES (%s, %s, %s, %s)""",
            (modulo, descripcion[:2000], nivel, administrador_id)
        )
        conn.commit(); cursor.close(); conn.close()
    except Exception:
        # Si ni siquiera se puede registrar el error, no dejamos que
        # esto tumbe la respuesta original al usuario.
        pass
    return (
        "No se pudo completar la operación. Verifica la información "
        "ingresada e intenta nuevamente. Si el problema continúa, "
        "contacta al equipo técnico."
    )


def validar_pdf_estructuralmente(contenido: bytes) -> bool:
    """
    Valida que un archivo sea un PDF estructuralmente integro: que se
    pueda abrir, que no este corrupto, y que tenga al menos 1 pagina
    legible. #23. Retorna True si es valido, False si no.
    """
    try:
        lector = PdfReader(io.BytesIO(contenido))
        if len(lector.pages) == 0:
            return False
        _ = lector.pages[0]  # fuerza a leer la primera pagina
        return True
    except (PdfReadError, Exception):
        return False


@app.get("/admin/auditoria-bono-descuento")
def ver_auditoria_bono_descuento(tipo_ajuste: str = None, payload: dict = Depends(verificar_token)):
    """
    Consulta de la pista de auditoria especifica de Bonos
    Excepcionales y Descuentos por Inasistencia — los 6 campos
    exactos que exige el requisito, en formato dedicado (no la
    tabla generica log_auditoria).
    """
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        query = """SELECT nombre_administrador_historico, rut_administrador_historico, fecha_hora,
                          rut_trabajador_historico, tipo_ajuste, concepto, monto_clp
                   FROM auditoria_bono_descuento WHERE 1=1"""
        params = []
        if tipo_ajuste:
            query += " AND tipo_ajuste = %s"
            params.append(tipo_ajuste)
        query += " ORDER BY fecha_hora DESC LIMIT 500"
        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "registros": [
                {
                    "nombre_administrador_historico": r[0],
                    "rut_administrador_historico": r[1],
                    "fecha_hora": r[2].strftime("%d/%m/%Y %H:%M:%S") if r[2] else "—",
                    "rut_trabajador_historico": r[3],
                    "tipo_ajuste": r[4],
                    "concepto": r[5],
                    "monto_clp": r[6],
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/tecnico/log-errores")
def ver_log_errores_tecnicos(nivel: str = None, payload: dict = Depends(verificar_token)):
    """
    Consulta del log de errores tecnicos — reservada exclusivamente
    al equipo tecnico (rol admin, ya que el sistema no modela un rol
    "tecnico" separado). #21
    """
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        query = "SELECT error_id, modulo, descripcion_tecnica, nivel_criticidad, fecha_hora FROM log_errores_tecnicos WHERE 1=1"
        params = []
        if nivel:
            query += " AND nivel_criticidad = %s"
            params.append(nivel)
        query += " ORDER BY fecha_hora DESC LIMIT 500"
        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "errores": [
                {
                    "error_id": r[0],
                    "modulo": r[1],
                    "descripcion_tecnica": r[2],
                    "nivel_criticidad": r[3],
                    "fecha_hora": r[4].strftime("%d/%m/%Y %H:%M:%S") if r[4] else "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": f"Error al consultar el log: {e}"}


def verificar_rol(payload: dict, roles_permitidos: list):
    rol = payload.get("rol", "")
    if rol not in roles_permitidos:
        raise HTTPException(status_code=403, detail="No tienes permiso para esta accion")

def get_id_cuenta(payload: dict) -> int:
    return int(payload.get("cuenta_id", 0))

def get_persona_id(payload: dict) -> int:
    return int(payload.get("persona_id", 0))

# ── MODELOS ───────────────────────────────────────────────────
class LoginRequest(BaseModel):
    correo: str
    contrasena: str

class RegistroRequest(BaseModel):
    correo: str
    contrasena: str

class ReenviarVerificacionRequest(BaseModel):
    correo: str

class ActualizarFichaRequest(BaseModel):
    telefono: str
    direccion: str

class ActualizarVacacionesRequest(BaseModel):
    dias_adicionales: int
    dias_totales: int

class SolicitudVacacionesRequest(BaseModel):
    fecha_inicio: str
    fecha_fin: str
    dias_habiles: int
    tipo_dias: str  # 'normal' o 'progresivo'

class DecisionVacacionesRequest(BaseModel):
    estado: str
    observacion: str = ""

class CotizacionesRequest(BaseModel):
    meses_cotizados_previos: int
    afp: str

class EmpleadoRequest(BaseModel):
    rut: str
    primer_nombre: str
    segundo_nombre: str = ""
    apellido_paterno: str
    apellido_materno: str
    correo: str
    telefono: str = ""
    direccion: str = ""
    tipo_salud: str
    afp: str
    cargo: str
    tipo_contrato: str
    fecha_ingreso: str
    sueldo_base: int
    jornada_semanal_horas: float = 44.0
    discapacidad: str = ""
    fecha_nacimiento: str = None
    rol: str = "usuario"

# ── MODELO SOLICITUD DE DATOS PERSONALES (Ley 19.628) ─────────
class SolicitudDatosRequest(BaseModel):
    tipo_solicitud: str  # 'Correccion' | 'Eliminacion'
    campo_afectado: str = None
    detalle:        str


class ResolverSolicitudDatosRequest(BaseModel):
    solicitud_id: int
    estado:       str  # 'Aprobada' | 'Rechazada'
    respuesta_admin: str = None


class RolRequest(BaseModel):
    rol: str
    trabajadores_equipo: list[int] = None  # solo se usa cuando rol == 'jefe'

class CompletarCuentaRequest(BaseModel):
    cuenta_id:          int
    rut:                str
    primer_nombre:      str
    segundo_nombre:     str = ""
    apellido_paterno:   str
    apellido_materno:   str
    telefono:           str = ""
    direccion:          str = ""
    tipo_salud:         str | None = None
    afp:                str | None = None
    cargo:              str | None = None
    tipo_contrato:      str
    fecha_ingreso:      str
    sueldo_base:        int | None = None
    jornada_semanal_horas: float = 44.0
    discapacidad:       str = ""
    fecha_nacimiento:   str = None

# ── MODELOS COMPENSACION PROGRESIVA ──────────────────────────
class SolicitudCompensacion(BaseModel):
    dias_a_compensar: int
    monto_calculado:  int = None  # ya no se usa: el servidor recalcula el monto real, ver solicitar_compensacion

class DecisionCompensacion(BaseModel):
    estado:      str
    observacion: str = ""

class CompensacionProgresiva(BaseModel):
    dias_a_compensar: int
    monto_calculado:  int


# ── MODELO DESCUENTOS ─────────────────────────────────────────
class DescuentoRequest(BaseModel):
    persona_id:      int
    tipo_descuento:  str   # 'Inasistencia' | 'Retraso' | 'Prestamo'
    monto_clp:       int = None    # Inasistencia/Retraso: monto directo
    fecha_evento:    str = None    # Inasistencia/Retraso: 'YYYY-MM-DD'
    dias_evento:     float = None  # Inasistencia: cantidad de dias ingresados
    # ── Solo para tipo_descuento == 'Prestamo' ──────────────────
    subtipo_prestamo: str = None   # 'Interno' | 'CajaCompensacion'
    monto_prestamo:   int = None   # 'Interno': monto total del prestamo (la cuota se calcula dividiendo)
    monto_cuota_manual: int = None # 'CajaCompensacion': monto de la cuota ingresado directamente
    cantidad_cuotas:  int = None
    mes_inicio:       int = None   # 1-12
    anio_inicio:      int = None   # AAAA


# ── MODELO BONOS IMPONIBLES ───────────────────────────────────
class BonoImponibleRequest(BaseModel):
    persona_id:     int
    tipo_bono:      str   # 'Bonificacion' | 'Bonificacion de Produccion' | 'Bonificacion por Turno' | 'Otros'
    monto_clp:      int
    periodo:        str   # 'MM/AAAA'
    concepto_otros: str = ""  # obligatorio solo si tipo_bono == 'Otros'


# ── MODELO LICENCIAS MEDICAS ──────────────────────────────────
class LicenciaMedicaRequest(BaseModel):
    persona_id:       int
    fecha_inicio:     str   # 'YYYY-MM-DD'
    fecha_fin:        str   # 'YYYY-MM-DD'
    tipo_de_licencia: str = "Licencia medica comun"
    entidad_emisora:  str = ""


# ── MODELO HORAS EXTRAS ────────────────────────────────────────
class HorasExtrasRequest(BaseModel):
    persona_id:     int
    periodo:        str    # 'MM/AAAA'
    cantidad_horas: float  # total de horas extra trabajadas en el mes (admite decimales, ej: 22.12)


# ── MODELO VALOR UTM ───────────────────────────────────────────
class ValorUtmRequest(BaseModel):
    valor_clp: int
    periodo:   str  # 'MM/AAAA'


# ── MODELOS MOVILIZACION Y COLACION ───────────────────────────
class TopeNoImponibleRequest(BaseModel):
    concepto:            str    # 'Movilizacion' | 'Colacion'
    monto_exento_diario: int


class AsignacionNoImponibleRequest(BaseModel):
    persona_id:           int
    concepto:             str    # 'Movilizacion' | 'Colacion'
    monto_total_mensual:  int
    dias_periodo:         int    # dias del periodo considerados para el tope (1-31)
    periodo:              str    # 'MM/AAAA'


# ── MODELO MOVILIZACION Y COLACION (valores fijos, sin tope) ──
class MovilizacionColacionFijaRequest(BaseModel):
    persona_id: int
    periodo:    str  # 'MM/AAAA'


class ConfirmarMovilizacionColacionRequest(BaseModel):
    periodo: str  # 'MM/AAAA'


# ── MODELO PROGRESO DEL WIZARD ─────────────────────────────────
class ProgresoWizardRequest(BaseModel):
    persona_id:  int
    periodo:     str  # 'MM/AAAA'
    paso_actual: int = 0


# ── MODELOS TASAS AFP Y SALUD ──────────────────────────────────
class TasaAfpRequest(BaseModel):
    nombre_afp:            str
    tasa_total_porcentaje: float


class TasaSaludRequest(BaseModel):
    institucion:      str  # 'Fonasa' | 'Isapre'
    tasa_porcentaje:  float


# ── MODELOS GRATIFICACION E IMM ───────────────────────────────
class ValorImmRequest(BaseModel):
    valor_clp: int
    periodo:   str  # 'MM/AAAA'


# ── MODELO VALOR UF (3 valores independientes: UF, tope AFP/Salud, tope AFC) ──
class ValorUfRequest(BaseModel):
    valor_uf:       float
    tope_afp_salud: float
    tope_afc:       float
    periodo:        str  # 'MM/AAAA'


# ── MODELOS LIQUIDACION HONORARIOS ─────────────────────────────
class RetencionHonorarioRequest(BaseModel):
    tasa_retencion: float
    anio:           int


class LiquidacionHonorarioRequest(BaseModel):
    persona_id:          int
    periodo:             str  # 'MM/AAAA'
    numero_boleta:       str | None = None
    fecha_emision:       str | None = None  # 'YYYY-MM-DD'
    numero_cuenta:       str | None = None
    periodo_prestacion:  str | None = None  # texto libre, ej. '2 de marzo a 2 de agosto'
    descripcion_trabajo: str
    honorario_bruto:     float


# ── MODELO ACTUALIZAR UN TRAMO DE IMPUESTO (edicion celda por celda) ──
class ActualizarTramoRequest(BaseModel):
    tramo_numero: int
    desde_utm:    float
    hasta_utm:    float = None   # None = sin tope (ultimo tramo)
    factor:       float
    rebaja_utm:   float


class ConfigGratificacionRequest(BaseModel):
    modalidad:          str    # 'Proporcional' | 'Anual'
    porcentaje_mensual: float = 25.0
    limite_imm_anual:   float = 4.75
    porcentaje_anual:   float = 30.0


# ── MODELO APORTES EMPLEADOR ──────────────────────────────────
class AporteEmpleadorRequest(BaseModel):
    concepto:        str   # 'SIS_AFP' | 'Salud_Empleador' | 'Expectativa_Vida' | 'Aporte_Capitalizacion'
    tasa_porcentaje: float


# ── MODELO ANTICIPO DE SUELDO ─────────────────────────────────
# ── MODELOS CONCEPTOS DE REMUNERACION ──────────────────────────
class ConceptoRemuneracionRequest(BaseModel):
    nombre:        str
    tipo:          str   # 'Fijo' | 'Variable'
    clasificacion: str   # 'Imponible' | 'No imponible'
    descripcion:   str = ""


class EstadoConceptoRequest(BaseModel):
    activo: bool


# ── MODELOS BONOS/INCENTIVOS CONDICIONALES ────────────────────
class BonoReglaRequest(BaseModel):
    nombre_concepto:  str
    condicion_texto:  str
    clasificacion:    str            # 'Imponible' | 'No imponible'
    monto_fijo_clp:   int   | None = None
    porcentaje_base:  float | None = None


class EstadoBonoReglaRequest(BaseModel):
    activo: bool


class AplicacionBonoReglaRequest(BaseModel):
    persona_id:       int
    bono_id:          int
    periodo:          str    # 'MM/AAAA'
    cumple_condicion: bool


# ── MODELO BONO EXCEPCIONAL ────────────────────────────────────
class BonoExcepcionalRequest(BaseModel):
    persona_id:    int
    concepto:      str    # 3-100 caracteres, texto libre
    monto_clp:     int
    clasificacion: str    # 'Imponible' | 'No imponible'
    periodo:       str    # 'MM/AAAA'


class AnticipoSueldoRequest(BaseModel):
    persona_id:          int
    monto_clp:           int
    periodo:             str   # 'MM/AAAA' - periodo en que se descontara
    folio_autorizacion:  str   # 1-20 caracteres alfanumericos (con guiones permitidos)


# ── MODELO CIERRE DE LIQUIDACION ──────────────────────────────
class CerrarLiquidacionRequest(BaseModel):
    persona_id: int
    periodo:    str  # 'MM/AAAA'


class LiquidacionComplementariaRequest(BaseModel):
    persona_id: int
    periodo:    str
    concepto:   str   # texto libre describiendo la correccion
    monto_clp:  int    # puede ser positivo (haber adicional) o negativo (descuento adicional)


# ── MODELO CALCULO PROPORCIONAL (Art. 41) ─────────────────────
class CalculoProporcionalRequest(BaseModel):
    persona_id:       int
    periodo:          str    # 'MM/AAAA'
    motivo:           str    # 'Ingreso' | 'Egreso'
    fecha_referencia: str | None = None  # 'YYYY-MM-DD' — solo para 'Egreso' (ultimo dia trabajado)


# ── CALCULO DIAS PROGRESIVOS (Art. 68) — INTERPRETACION B ────
def calcular_dias_progresivos(fecha_ingreso, meses_previos: int) -> dict:
    """
    Algoritmo Art. 68 Codigo del Trabajo Chile - Interpretacion B.

    El derecho a feriado progresivo nace cuando el trabajador acredita:
      - 10 anios de cotizaciones previsionales (120 meses), con el empleador
        actual o anteriores, Y ADEMAS
      - 3 anios de antiguedad en el empleador actual, contados desde que
        se cumple el requisito anterior.

    Los dias progresivos son ACUMULATIVOS anio a anio (no solo el nivel
    vigente): 1+1+1+2+2 = 7, no el ultimo valor (2).
    """
    hoy = dt.date.today()
    meses_previos_lim = min(int(meses_previos or 0), 120)

    meses_faltantes_10anios = max(120 - meses_previos_lim, 0)
    meses_hasta_beneficio = meses_faltantes_10anios + 36

    fecha_inicio_ben = fecha_ingreso + relativedelta(months=meses_hasta_beneficio)

    if hoy < fecha_inicio_ben:
        return {
            "dias_prog_calculados":   0,
            "fecha_inicio_beneficio": fecha_inicio_ben,
            "anos_desde_inicio":      0,
            "cumple_progresivos":     False,
            "meses_faltantes":        meses_hasta_beneficio,
        }

    total_acumulado = 0
    ano_iter = fecha_inicio_ben.year

    while True:
        try:
            fecha_ese_ano = dt.date(ano_iter, fecha_inicio_ben.month, fecha_inicio_ben.day)
        except ValueError:
            fecha_ese_ano = dt.date(ano_iter, fecha_inicio_ben.month, 28)

        if fecha_ese_ano > hoy:
            break

        anos_transcurridos = relativedelta(fecha_ese_ano, fecha_inicio_ben).years
        nivel_ese_ano = (anos_transcurridos // 3) + 1
        total_acumulado += nivel_ese_ano
        ano_iter += 1

    anos_completos = relativedelta(hoy, fecha_inicio_ben).years

    return {
        "dias_prog_calculados":   total_acumulado,
        "fecha_inicio_beneficio": fecha_inicio_ben,
        "anos_desde_inicio":      anos_completos,
        "cumple_progresivos":     True,
        "meses_faltantes":        0,
    }

# ── HELPER: SALDO NORMAL REAL DISPONIBLE ─────────────────────
def calcular_saldo_normal_disponible(fecha_ingreso, meses_previos, dias_acumulados, dias_utilizados) -> int:
    """
    Misma formula que usa /mi-balance-vacaciones para 'dias_disponibles':
    NO se basa en la columna saldo_vacaciones.dias_disponibles (esa columna
    quedo obsoleta/legacy), sino en acumulado_final - dias_utilizados.
    Se reusa aqui para que el panel de admin muestre el mismo numero
    que ve el trabajador.
    """
    hoy = dt.date.today()
    if fecha_ingreso:
        meses_clinica = (hoy.year - fecha_ingreso.year) * 12 + (hoy.month - fecha_ingreso.month)
        if hoy.day < fecha_ingreso.day:
            meses_clinica -= 1
        meses_clinica = max(0, meses_clinica)
    else:
        meses_clinica = 0

    meses_previos_limitados = min(meses_previos or 0, 120)
    # FIX: el feriado normal (Art. 67 - 15 dias/año) se calcula SOLO con
    # la antiguedad en la clinica actual. Las cotizaciones previas
    # (meses_previos) solo aplican al feriado progresivo (Art. 68),
    # no deben sumarse aqui.
    acumulado_teorico = round(meses_clinica * 1.25, 4)

    # FIX: siempre se usa la formula (meses_clinica * 1.25), nunca el
    # valor guardado en dias_acumulados. Ese valor podia arrastrar
    # incrementos manuales de cargas de datos o del mecanismo de
    # "+15 anual" ya eliminado, duplicando el crecimiento.
    acumulado_final = acumulado_teorico
    utilizados = int(dias_utilizados or 0)
    return max(0, round(acumulado_final - utilizados))


# ── HELPER: ART. 70 — PERIODOS ACUMULADOS SIN USAR ───────────
def calcular_periodos_articulo_70(dias_disponibles: int) -> dict:
    """
    Art. 70 Codigo del Trabajo: maximo 2 periodos anuales consecutivos
    de feriado acumulados sin usar (cada periodo = 15 dias). Al
    acumular el 2do periodo sin tomar licencia, se alerta al
    administrador. Al llegar al 3er periodo sin uso, se bloquea la
    acumulacion hasta que el trabajador registre al menos un periodo
    de vacaciones normales efectivamente utilizado.

    Se calcula directamente desde el saldo de dias normales
    DISPONIBLES en este momento (no desde la fecha de la ultima
    solicitud), porque lo que la ley limita es cuantos dias sin usar
    se acumulan, no hace cuanto tiempo fue la ultima vez que se
    tomaron vacaciones. Esto evita dos casos incorrectos:
      - Alguien con un saldo enorme pero que tomo un dia hace poco
        (no deberia librarse de la alerta solo por eso).
      - Alguien con saldo bajo pero sin solicitudes registradas en el
        sistema (no deberia aparecer en alerta por falta de datos).
    """
    dias = max(0, int(dias_disponibles or 0))
    periodos_acumulados = dias // 15

    return {
        "periodos_acumulados":  periodos_acumulados,
        "alerta_articulo_70":   periodos_acumulados >= 2,
        "bloqueo_articulo_70":  periodos_acumulados >= 3,
    }


# ── ROOT ──────────────────────────────────────────────────────
@app.get("/")
def root():
    return {"mensaje": "API Remuneraciones Aconcagua OK"}

# ── LOGIN ─────────────────────────────────────────────────────
@app.post("/login")
def login(data: LoginRequest):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT ca.cuenta_id, ca.contrasena, ca.rol,
                    COALESCE(p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno, 'Usuario') AS nombre_completo,
                    COALESCE(p.cargo, '—') AS cargo,
                    ca.activo, ca.intentos_fallidos, ca.bloqueada_hasta,
                    COALESCE(p.persona_id, 0) AS persona_id,
                    ca.cuenta_verificada
            FROM cuenta_acceso ca
            LEFT JOIN persona p ON p.persona_id = ca.persona_id
            WHERE ca.correo_institucional = %s""",
            (data.correo,)
        )
        result = cursor.fetchone()
        cursor.close()
        conn.close()

        if not result:
            return {"success": False, "mensaje": "Correo o contrasena incorrectos"}

        cuenta_id, contrasena_bd, rol, nombre_completo, cargo, activo, intentos_fallidos, bloqueada_hasta, persona_id, cuenta_verificada = result

        if not activo:
            return {"success": False, "mensaje": "Tu cuenta esta desactivada. Contacta al administrador."}

        if not cuenta_verificada:
            return {"success": False, "mensaje": "Debes activar tu cuenta antes de iniciar sesion. Revisa el correo de verificacion que te enviamos, o solicita uno nuevo si ya expiro.", "cuenta_no_verificada": True}

        if bloqueada_hasta and datetime.utcnow() < bloqueada_hasta:
            minutos_restantes = int((bloqueada_hasta - datetime.utcnow()).seconds / 60) + 1
            return {"success": False, "mensaje": f"Cuenta bloqueada. Intenta nuevamente en {minutos_restantes} minuto(s)."}

        if not verificar_contrasena(data.contrasena, contrasena_bd):
            nuevos_intentos = intentos_fallidos + 1
            conn2 = get_connection()
            cursor2 = conn2.cursor()
            if nuevos_intentos >= 5:
                bloqueo_hasta = datetime.utcnow() + timedelta(minutes=15)
                cursor2.execute(
                    "UPDATE cuenta_acceso SET intentos_fallidos = %s, bloqueada_hasta = %s WHERE cuenta_id = %s",
                    (nuevos_intentos, bloqueo_hasta, cuenta_id)
                )
                conn2.commit(); cursor2.close(); conn2.close()
                return {"success": False, "mensaje": "Cuenta bloqueada por 15 minutos tras 5 intentos fallidos."}
            else:
                cursor2.execute(
                    "UPDATE cuenta_acceso SET intentos_fallidos = %s WHERE cuenta_id = %s",
                    (nuevos_intentos, cuenta_id)
                )
                conn2.commit(); cursor2.close(); conn2.close()
                return {"success": False, "mensaje": f"Contrasena incorrecta. Intentos fallidos: {nuevos_intentos}/5"}

        conn2 = get_connection()
        cursor2 = conn2.cursor()
        cursor2.execute(
            "UPDATE cuenta_acceso SET intentos_fallidos = 0, bloqueada_hasta = NULL WHERE cuenta_id = %s",
            (cuenta_id,)
        )
        conn2.commit(); cursor2.close(); conn2.close()

        token = crear_token({
            "sub": data.correo,
            "cuenta_id": int(cuenta_id),
            "persona_id": int(persona_id),
            "rol": rol,
            "nombre_completo": nombre_completo or "",
            "cargo": cargo or ""
        })

        return {
            "success": True,
            "access_token": token,
            "token_type": "bearer",
            "cuenta_id": int(cuenta_id),
            "persona_id": int(persona_id),
            "nombre_completo": nombre_completo or "",
            "rol": rol,
            "cargo": cargo or ""
        }

    except Exception as e:
        return {"success": False, "mensaje": f"Error del servidor: {str(e)}"}

# ── REGISTRO ──────────────────────────────────────────────────
@app.post("/registro")
def registro(data: RegistroRequest):
    try:
        if not re.match(r'^[a-zA-Z0-9.\-]+@accaconcagua\.cl$', data.correo):
            return {"success": False, "mensaje": "Debes usar tu correo institucional @accaconcagua.cl"}
        if len(data.correo) > 100:
            return {"success": False, "mensaje": "El correo no puede superar 100 caracteres"}
        if len(data.contrasena) < 8 or len(data.contrasena) > 64:
            return {"success": False, "mensaje": "La contraseña debe tener entre 8 y 64 caracteres"}
        if ' ' in data.contrasena:
            return {"success": False, "mensaje": "La contraseña no puede contener espacios"}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT cuenta_id FROM cuenta_acceso WHERE correo_institucional = %s", (data.correo,))
        if cursor.fetchone():
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Este correo ya esta registrado"}

        cursor.execute("SELECT persona_id FROM persona WHERE correo_institucional = %s", (data.correo,))
        persona = cursor.fetchone()
        contrasena_hash = encriptar_contrasena(data.contrasena)

        if persona:
            cursor.execute(
                """INSERT INTO cuenta_acceso (correo_institucional, contrasena, rol, persona_id)
                   VALUES (%s, %s, 'usuario', %s) RETURNING cuenta_id""",
                (data.correo, contrasena_hash, persona[0])
            )
        else:
            cursor.execute(
                """INSERT INTO cuenta_acceso (correo_institucional, contrasena, rol)
                   VALUES (%s, %s, 'usuario') RETURNING cuenta_id""",
                (data.correo, contrasena_hash)
            )

        nuevo_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()

        generar_y_enviar_verificacion(nuevo_id, data.correo)

        return {
            "success": True,
            "mensaje": "Cuenta creada exitosamente. Revisa tu correo institucional para activarla.",
            "cuenta_id": nuevo_id,
        }

    except Exception as e:
        return {"success": False, "mensaje": f"Error del servidor: {str(e)}"}

# ── VERIFICAR CUENTA (click en el enlace del correo) ────────────
@app.get("/verificar-cuenta/{token}")
def verificar_cuenta(token: str):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT verificacion_id, cuenta_id, fecha_expiracion, usado FROM verificacion_cuenta WHERE token = %s",
            (token,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El enlace de activacion no es valido."}

        registro_id, cuenta_id, fecha_expiracion, usado = r

        if usado:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Este enlace ya fue utilizado. Si tu cuenta ya esta activa, puedes iniciar sesion."}

        if datetime.utcnow() > fecha_expiracion:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Este enlace de activacion ha expirado (valido por 24 horas). Solicita uno nuevo desde la pantalla de inicio de sesion.", "expirado": True}

        cursor.execute("UPDATE verificacion_cuenta SET usado = TRUE WHERE verificacion_id = %s", (registro_id,))
        cursor.execute("UPDATE cuenta_acceso SET cuenta_verificada = TRUE WHERE cuenta_id = %s", (cuenta_id,))
        conn.commit(); cursor.close(); conn.close()

        return {"success": True, "mensaje": "Tu cuenta ha sido activada correctamente. Ya puedes iniciar sesion."}
    except Exception as e:
        return {"success": False, "mensaje": f"Error del servidor: {str(e)}"}

# ── REENVIAR CORREO DE VERIFICACION ──────────────────────────────
@app.post("/reenviar-verificacion")
def reenviar_verificacion(data: ReenviarVerificacionRequest):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT cuenta_id, cuenta_verificada FROM cuenta_acceso WHERE correo_institucional = %s",
            (data.correo,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No existe una cuenta registrada con ese correo."}

        cuenta_id, cuenta_verificada = r

        if cuenta_verificada:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Esta cuenta ya esta activada. Puedes iniciar sesion directamente."}

        # Solo se puede reenviar si el ultimo enlace enviado ya expiro
        # (no se deja reenviar mientras el anterior sigue vigente).
        cursor.execute(
            """SELECT fecha_expiracion, usado FROM verificacion_cuenta
               WHERE cuenta_id = %s ORDER BY fecha_creacion DESC LIMIT 1""",
            (cuenta_id,)
        )
        ultimo = cursor.fetchone()
        if ultimo and not ultimo[1] and datetime.utcnow() < ultimo[0]:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El enlace que ya te enviamos todavia esta vigente. Revisa tu correo antes de pedir uno nuevo."}

        # Maximo 3 reenvios por cuenta: el primer envio (al registrarse)
        # cuenta como el envio original, no como un reenvio -- asi que
        # el limite real son 4 filas en total para esa cuenta_id.
        cursor.execute(
            "SELECT COUNT(*) FROM verificacion_cuenta WHERE cuenta_id = %s",
            (cuenta_id,)
        )
        total_envios = cursor.fetchone()[0]
        cursor.close(); conn.close()

        if total_envios >= 4:
            return {"success": False, "mensaje": "Ya alcanzaste el maximo de 3 reenvios permitidos para esta cuenta. Contacta al administrador."}

        generar_y_enviar_verificacion(cuenta_id, data.correo)
        return {"success": True, "mensaje": "Te enviamos un nuevo correo de activacion. Revisa tu bandeja de entrada."}
    except Exception as e:
        return {"success": False, "mensaje": f"Error del servidor: {str(e)}"}

# ── MI FICHA ──────────────────────────────────────────────────
@app.get("/mi-ficha")
def get_ficha(payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno,
                      p.rut, p.correo_institucional, p.telefono, p.direccion,
                      sv.dias_disponibles, sv.dias_progresivos,
                      p.fecha_ingreso, t.meses_cotizados_previos,
                      p.tipo_afp, p.cargo, p.fecha_nacimiento,
                      p.institucion_salud
               FROM persona p
               LEFT JOIN trabajador t ON t.persona_id = p.persona_id
               LEFT JOIN saldo_vacaciones sv ON sv.trabajador_id = t.trabajador_id
               WHERE p.persona_id = %s""",
            (persona_id,)
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()
        if not r:
            return {"success": False, "mensaje": "Empleado no encontrado"}
        return {
            "success": True,
            "nombre_completo": r[0] or "",
            "rut": r[1] or "",
            "correo": r[2] or "",
            "telefono": r[3] or "",
            "direccion": r[4] or "",
            "dias_vacaciones": r[5] or 15,
            "dias_vacaciones_prog": r[6] or 0,
            "fecha_ingreso": str(r[7]) if r[7] else None,
            "meses_cotizados_previos": r[8] or 0,
            "afp": r[9] or "",
            "cargo": r[10] or "",
            "fecha_nacimiento": str(r[11]) if r[11] else None,
            "tipo_salud": r[12] or ""
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

@app.put("/mi-ficha")
def update_ficha(data: ActualizarFichaRequest, payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE persona SET telefono = %s, direccion = %s WHERE persona_id = %s",
            (data.telefono, data.direccion, persona_id)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Datos actualizados correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── MIS VACACIONES ────────────────────────────────────────────
@app.get("/mis-vacaciones")
def get_mis_vacaciones(payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT sv.dias_disponibles FROM saldo_vacaciones sv
               JOIN trabajador t ON t.trabajador_id = sv.trabajador_id
               WHERE t.persona_id = %s""",
            (persona_id,)
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()
        return {"success": True, "dias_disponibles": r[0] if r else 15}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── SOLICITAR VACACIONES ──────────────────────────────────────
@app.post("/solicitar-vacaciones")
def solicitar_vacaciones(data: SolicitudVacacionesRequest, payload: dict = Depends(verificar_token)):
    try:
        if data.tipo_dias not in ('normal', 'progresivo'):
            return {"success": False, "mensaje": "tipo_dias invalido"}

        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id,))
        t = cursor.fetchone()
        if not t:
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = t[0]

        cursor.execute(
            "SELECT dias_disponibles, dias_progresivos FROM saldo_vacaciones WHERE trabajador_id = %s",
            (trabajador_id,)
        )
        saldo = cursor.fetchone()
        dias_normales_disp = (saldo[0] if saldo else 15) or 15
        dias_prog_disp = (saldo[1] if saldo else 0) or 0

        if data.tipo_dias == 'normal' and data.dias_habiles > dias_normales_disp:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"No puedes solicitar mas de {dias_normales_disp} dias normales disponibles"}
        if data.tipo_dias == 'progresivo' and data.dias_habiles > dias_prog_disp:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"No puedes solicitar mas de {dias_prog_disp} dias progresivos disponibles"}

        cursor.execute(
            """INSERT INTO solicitud_vacaciones
               (trabajador_id, fecha_inicio, fecha_fin, dias_habiles, tipo_dias, estado)
               VALUES (%s, %s, %s, %s, %s, 'Pendiente')""",
            (trabajador_id, data.fecha_inicio, data.fecha_fin, data.dias_habiles, data.tipo_dias)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Solicitud enviada correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── MIS SOLICITUDES VACACIONES ────────────────────────────────
@app.get("/mis-solicitudes-vacaciones")
def get_mis_solicitudes(anio: int = None, payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        query = """
            SELECT sv.solicitud_id, sv.fecha_inicio, sv.fecha_fin,
                   sv.dias_habiles, sv.estado, sv.observacion,
                   sv.fecha_solicitud, sv.fecha_decision
            FROM solicitud_vacaciones sv
            JOIN trabajador t ON t.trabajador_id = sv.trabajador_id
            WHERE t.persona_id = %s
        """
        params = [persona_id]
        if anio:
            query += " AND EXTRACT(YEAR FROM sv.fecha_inicio) = %s"
            params.append(anio)
        query += " ORDER BY sv.fecha_solicitud DESC"
        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        solicitudes = []
        for r in rows:
            solicitudes.append({
                "id_solicitud":    r[0],
                "fecha_inicio":    r[1].strftime("%d/%m/%Y") if r[1] else "—",
                "fecha_fin":       r[2].strftime("%d/%m/%Y") if r[2] else "—",
                "dias_habiles":    r[3],
                "estado":          r[4],
                "observacion":     r[5] or "",
                "fecha_solicitud": r[6].strftime("%d/%m/%Y") if r[6] else "—",
                "fecha_decision":  r[7].strftime("%d/%m/%Y") if r[7] else None,
            })
        return {"success": True, "solicitudes": solicitudes}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── ADMIN: VER SOLICITUDES ────────────────────────────────────
@app.get("/admin/solicitudes-vacaciones")
def get_solicitudes_admin(estado: str = None, anio: int = None, payload: dict = Depends(verificar_token)):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        query = """
            SELECT sv.solicitud_id, sv.fecha_inicio, sv.fecha_fin,
                   sv.dias_habiles, sv.estado, sv.observacion,
                   sv.fecha_solicitud, sv.revisado_por, sv.tipo_dias,
                   p.primer_nombre || ' ' || p.apellido_paterno AS nombre,
                   p.cargo, p.fecha_ingreso,
                   t.meses_cotizados_previos,
                   sal.dias_acumulados, sal.dias_utilizados, sal.dias_progresivos,
                   p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
            FROM solicitud_vacaciones sv
            JOIN trabajador t ON t.trabajador_id = sv.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN saldo_vacaciones sal ON sal.trabajador_id = t.trabajador_id
            LEFT JOIN administrador a ON a.administrador_id = sv.revisado_por
            LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
            WHERE 1=1
        """
        params = []
        if estado and estado != 'Todas':
            query += " AND sv.estado = %s"
            params.append(estado)
        if anio:
            query += " AND EXTRACT(YEAR FROM sv.fecha_inicio) = %s"
            params.append(anio)
        query += " ORDER BY sv.fecha_solicitud DESC"
        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        solicitudes = []
        for r in rows:
            (solicitud_id, fecha_inicio, fecha_fin, dias_habiles, estado_sol, observacion,
             fecha_solicitud, revisado_por, tipo_dias, nombre, cargo, fecha_ingreso,
             meses_previos, dias_acumulados, dias_utilizados, dias_progresivos, nombre_admin) = r

            tipo_dias = tipo_dias or 'normal'

            if tipo_dias == 'progresivo':
                saldo = int(dias_progresivos or 0)
            else:
                saldo = calcular_saldo_normal_disponible(fecha_ingreso, meses_previos, dias_acumulados, dias_utilizados)

            solicitudes.append({
                "id_solicitud":    solicitud_id,
                "fecha_inicio":    fecha_inicio.strftime("%d/%m/%Y") if fecha_inicio else "—",
                "fecha_fin":       fecha_fin.strftime("%d/%m/%Y") if fecha_fin else "—",
                "dias_habiles":    dias_habiles,
                "estado":          estado_sol,
                "observacion":     observacion or "",
                "fecha_solicitud": fecha_solicitud.strftime("%d/%m/%Y") if fecha_solicitud else "—",
                "tipo_dias":       tipo_dias,
                "nombre":          nombre,
                "cargo":           cargo or "—",
                "saldo_actual":    saldo,
                "saldo_despues":   max(0, saldo - dias_habiles),
                "nombre_admin":    nombre_admin or "",
                "expandida":       False,
            })
        return {"success": True, "solicitudes": solicitudes}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── ADMIN: APROBAR O RECHAZAR ─────────────────────────────────
@app.put("/admin/solicitudes-vacaciones/{id_solicitud}")
def decidir_solicitud(id_solicitud: int, data: DecisionVacacionesRequest, payload: dict = Depends(verificar_token)):
    try:
        if data.estado not in ['Aprobada', 'Rechazada']:
            return {"success": False, "mensaje": "Estado invalido"}
        if data.estado == 'Rechazada' and len(data.observacion.strip()) < 10:
            return {"success": False, "mensaje": "Observacion obligatoria al rechazar (minimo 10 caracteres)"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin = cursor.fetchone()
        administrador_id = admin[0] if admin else None

        cursor.execute(
            """SELECT sv.trabajador_id, sv.dias_habiles, sv.tipo_dias,
                      sv.fecha_inicio, sv.fecha_fin,
                      p.primer_nombre || ' ' || p.apellido_paterno, p.rut,
                      sal.dias_progresivos, sal.dias_utilizados, sal.saldo_id
               FROM solicitud_vacaciones sv
               JOIN trabajador t ON t.trabajador_id = sv.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN saldo_vacaciones sal ON sal.trabajador_id = t.trabajador_id
               WHERE sv.solicitud_id = %s""",
            (id_solicitud,)
        )
        r = cursor.fetchone()
        if not r:
            return {"success": False, "mensaje": "Solicitud no encontrada"}

        (trabajador_id, dias, tipo_dias, fi, ff, nombre, rut,
         saldo_prog_actual, dias_utilizados_actual, saldo_id) = r

        cursor.execute(
            """UPDATE solicitud_vacaciones
               SET estado = %s, observacion = %s,
                   revisado_por = %s, fecha_decision = NOW()
               WHERE solicitud_id = %s""",
            (data.estado, data.observacion, administrador_id, id_solicitud)
        )

        if data.estado == 'Aprobada' and saldo_id:
            if tipo_dias == 'progresivo':
                nuevo_saldo_prog = max(0, (saldo_prog_actual or 0) - dias)
                cursor.execute(
                    "UPDATE saldo_vacaciones SET dias_progresivos = %s, ultima_actualizacion = NOW() WHERE saldo_id = %s",
                    (nuevo_saldo_prog, saldo_id)
                )
            else:
                # FIX: /mi-balance-vacaciones calcula "dias_disponibles" como
                # acumulado_final - dias_utilizados (NO lee la columna
                # dias_disponibles). Por eso hay que incrementar
                # dias_utilizados, no decrementar dias_disponibles,
                # o el saldo mostrado al trabajador nunca cambia.
                nuevo_utilizados = (dias_utilizados_actual or 0) + dias
                cursor.execute(
                    "UPDATE saldo_vacaciones SET dias_utilizados = %s, ultima_actualizacion = NOW() WHERE saldo_id = %s",
                    (nuevo_utilizados, saldo_id)
                )

        conn.commit()

        if data.estado == 'Rechazada':
            conn3 = get_connection()
            cursor3 = conn3.cursor()
            cursor3.execute(
                """SELECT p.correo_institucional FROM trabajador t
                   JOIN persona p ON p.persona_id = t.persona_id
                   WHERE t.trabajador_id = %s""",
                (trabajador_id,)
            )
            r3 = cursor3.fetchone()
            cursor3.close(); conn3.close()
            if r3:
                html = f"""
                <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                    <div style="background-color: #001E42; padding: 20px; text-align: center;">
                        <h1 style="color: white; margin: 0;">Clínica Aconcagua</h1>
                    </div>
                    <div style="padding: 30px; background-color: #f8fafc;">
                        <h2 style="color: #EF4444;">Solicitud de Vacaciones Rechazada</h2>
                        <p>Estimado/a <strong>{nombre}</strong>,</p>
                        <p>Su solicitud de vacaciones ({'progresivas' if tipo_dias == 'progresivo' else 'normales'}) para el periodo
                        <strong>{fi.strftime('%d/%m/%Y') if fi else '—'}</strong> al
                        <strong>{ff.strftime('%d/%m/%Y') if ff else '—'}</strong>
                        ha sido <strong style="color: #EF4444;">rechazada</strong>.</p>
                        <div style="background-color: #FEE2E2; padding: 15px; border-radius: 8px; margin: 20px 0;">
                            <p style="margin: 0;"><strong>Motivo:</strong> {data.observacion}</p>
                        </div>
                        <p>Para más información, contacte al área de Recursos Humanos.</p>
                        <p>Atentamente,<br><strong>Sistema de Remuneraciones</strong><br>Clínica Aconcagua</p>
                    </div>
                </div>
                """
                enviar_email(
                    destinatario=r3[0],
                    asunto="Solicitud de Vacaciones Rechazada - Clínica Aconcagua",
                    contenido_html=html,
                )

        cursor.close(); conn.close()
        return {"success": True, "pdf_disponible": data.estado == 'Aprobada', "mensaje": f"Solicitud {data.estado.lower()} correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ══════════════════════════════════════════════════════════════
# DESCUENTOS (inasistencia, retraso, prestamo)
# ══════════════════════════════════════════════════════════════

TIPOS_DESCUENTO_VALIDOS = ('Inasistencia', 'Retraso', 'Prestamo')

# ── ADMIN: REGISTRAR DESCUENTO ────────────────────────────────
@app.post("/admin/descuentos")
def registrar_descuento(data: DescuentoRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if data.tipo_descuento not in TIPOS_DESCUENTO_VALIDOS:
            return {"success": False, "mensaje": f"Tipo de descuento invalido. Debe ser uno de: {', '.join(TIPOS_DESCUENTO_VALIDOS)}"}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """SELECT t.trabajador_id, p.rut, p.primer_nombre || ' ' || p.apellido_paterno AS nombre
               FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               WHERE p.persona_id = %s""",
            (data.persona_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id, rut_trabajador, nombre_trabajador = r

        persona_id_admin = get_persona_id(payload)
        cursor.execute(
            """SELECT p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre_admin,
                      p.rut AS rut_admin, a.administrador_id
               FROM administrador a
               JOIN persona p ON p.persona_id = a.persona_id
               WHERE p.persona_id = %s""",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        nombre_admin = admin_row[0] if admin_row else "Administrador"
        rut_admin = admin_row[1] if admin_row else ""
        administrador_id = admin_row[2] if admin_row else None

        # ══════════════════════════════════════════════════════
        # RAMA 1: PRESTAMO (Interno/Empresa o Caja de Compensacion)
        # Se genera UNA fila por cada cuota/periodo.
        # ══════════════════════════════════════════════════════
        if data.tipo_descuento == "Prestamo":
            if data.subtipo_prestamo not in ("Interno", "CajaCompensacion"):
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "Debes indicar el subtipo de prestamo: 'Interno' o 'CajaCompensacion'"}
            if not data.cantidad_cuotas or data.cantidad_cuotas < 1 or data.cantidad_cuotas > 60:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "La cantidad de cuotas debe ser un entero entre 1 y 60"}
            if not data.mes_inicio or not data.anio_inicio or data.mes_inicio < 1 or data.mes_inicio > 12:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "Debes indicar el mes y año de inicio del descuento"}

            _, error_periodo_inicio = validar_periodo_mm_aaaa(f"{data.mes_inicio:02d}/{data.anio_inicio}")
            if error_periodo_inicio:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": error_periodo_inicio}

            if data.subtipo_prestamo == "Interno":
                # Interno/Empresa: se ingresa el monto TOTAL del prestamo,
                # y la cuota se calcula automaticamente dividiendo.
                if not data.monto_prestamo or data.monto_prestamo <= 0:
                    cursor.close(); conn.close()
                    return {"success": False, "mensaje": "El monto del prestamo debe ser un entero positivo mayor a 0"}
                if data.monto_prestamo >= 10**9:
                    cursor.close(); conn.close()
                    return {"success": False, "mensaje": "El monto del prestamo no puede superar 9 digitos"}
                monto_cuota = round(data.monto_prestamo / data.cantidad_cuotas)
                monto_prestamo_total = data.monto_prestamo
            else:
                # Caja de Compensacion: se ingresa DIRECTAMENTE el monto
                # de la cuota (no se calcula dividiendo nada).
                if not data.monto_cuota_manual or data.monto_cuota_manual <= 0:
                    cursor.close(); conn.close()
                    return {"success": False, "mensaje": "El monto de la cuota debe ser un entero positivo mayor a 0"}
                if data.monto_cuota_manual >= 10**9:
                    cursor.close(); conn.close()
                    return {"success": False, "mensaje": "El monto de la cuota no puede superar 9 digitos"}
                monto_cuota = data.monto_cuota_manual
                monto_prestamo_total = monto_cuota * data.cantidad_cuotas

            # Calcular la lista de periodos (mes/anio) que cubre el prestamo
            periodos_cuotas = []
            mes_iter, anio_iter = data.mes_inicio, data.anio_inicio
            for _ in range(data.cantidad_cuotas):
                periodos_cuotas.append(f"{mes_iter:02d}/{anio_iter}")
                mes_iter += 1
                if mes_iter > 12:
                    mes_iter = 1
                    anio_iter += 1

            # Verificar que ningun periodo objetivo ya este cerrado
            for periodo_cuota in periodos_cuotas:
                if verificar_liquidacion_cerrada(trabajador_id, periodo_cuota):
                    cursor.close(); conn.close()
                    return {"success": False, "mensaje": f"No se puede registrar: la liquidacion del periodo {periodo_cuota} ya fue cerrada"}

            descuento_ids = []
            for i, periodo_cuota in enumerate(periodos_cuotas, start=1):
                mes_p, anio_p = periodo_cuota.split("/")
                fecha_evento_cuota = dt.date(int(anio_p), int(mes_p), 1)
                cursor.execute(
                    """INSERT INTO descuento
                       (tipo_descuento, monto_clp, fecha_evento, trabajador_id, periodo, registrado_por,
                        subtipo_prestamo, monto_prestamo_total, numero_cuota, total_cuotas)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                       RETURNING descuento_id""",
                    (data.tipo_descuento, monto_cuota, fecha_evento_cuota, trabajador_id, periodo_cuota, administrador_id,
                     data.subtipo_prestamo, monto_prestamo_total, i, data.cantidad_cuotas)
                )
                descuento_ids.append(cursor.fetchone()[0])

            subtipo_legible = "Interno/Empresa" if data.subtipo_prestamo == "Interno" else "Caja de Compensación"
            cursor.execute(
                """INSERT INTO log_auditoria
                   (tabla_afectada, registro_id, tipo_de_operacion, campo_modificado,
                    modulo, nombre_completo, informacion_personal, valor_nuevo, rut_administrador)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (
                    "descuento",
                    ",".join(str(i) for i in descuento_ids),
                    "INSERT",
                    "tipo_descuento, monto_clp (prestamo en cuotas)",
                    "Remuneraciones - Descuentos",
                    nombre_admin,
                    f"RUT trabajador afectado: {rut_trabajador} ({nombre_trabajador})",
                    f"Prestamo {subtipo_legible}: monto total ${monto_prestamo_total} CLP en {data.cantidad_cuotas} cuotas de ${monto_cuota} CLP; periodos {periodos_cuotas[0]} a {periodos_cuotas[-1]}",
                    rut_admin,
                )
            )

            conn.commit(); cursor.close(); conn.close()
            return {
                "success": True,
                "mensaje": f"Préstamo registrado en {data.cantidad_cuotas} cuota(s) correctamente",
                "descuento_ids": descuento_ids,
                "monto_cuota": monto_cuota,
                "periodo_inicio": periodos_cuotas[0],
                "periodo_fin": periodos_cuotas[-1],
            }

        # ══════════════════════════════════════════════════════
        # RAMA 2: INASISTENCIA / RETRASO (comportamiento original)
        # ══════════════════════════════════════════════════════
        if data.monto_clp is None or data.monto_clp <= 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El monto debe ser un entero positivo mayor a 0"}
        if data.monto_clp >= 10**9:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El monto no puede superar 9 digitos"}
        if not data.fecha_evento:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Debes indicar la fecha del evento"}
        try:
            fecha_evento = dt.datetime.strptime(data.fecha_evento, "%Y-%m-%d").date()
        except ValueError:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Fecha de evento invalida (formato esperado AAAA-MM-DD)"}
        if fecha_evento > dt.date.today():
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "La fecha del evento no puede ser futura"}

        periodo = fecha_evento.strftime("%m/%Y")
        _, error_periodo = validar_periodo_mm_aaaa(periodo)
        if error_periodo:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": error_periodo}

        if verificar_liquidacion_cerrada(trabajador_id, periodo):
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede modificar esta liquidacion porque ya ha sido cerrada"}

        cursor.execute(
            """INSERT INTO descuento
               (tipo_descuento, monto_clp, fecha_evento, dias_evento, trabajador_id, periodo, registrado_por)
               VALUES (%s, %s, %s, %s, %s, %s, %s)
               RETURNING descuento_id""",
            (data.tipo_descuento, data.monto_clp, fecha_evento, data.dias_evento, trabajador_id, periodo, administrador_id)
        )
        descuento_id = cursor.fetchone()[0]

        cursor.execute(
            """INSERT INTO log_auditoria
               (tabla_afectada, registro_id, tipo_de_operacion, campo_modificado,
                modulo, nombre_completo, informacion_personal,
                valor_nuevo, rut_administrador)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                "descuento",
                str(descuento_id),
                "INSERT",
                "tipo_descuento, monto_clp",
                "Remuneraciones - Descuentos",
                nombre_admin,
                f"RUT trabajador afectado: {rut_trabajador} ({nombre_trabajador})",
                f"tipo={data.tipo_descuento}; monto=${data.monto_clp} CLP; fecha_evento={fecha_evento.strftime('%d/%m/%Y')}",
                rut_admin,
            )
        )

        # ── Pista de auditoria especifica (6 campos exactos) ──
        # Solo aplica al caso puntual del requisito: descuento por
        # "no presentarse" = Inasistencia. Retraso y Prestamo no
        # corresponden a este requisito especifico.
        if data.tipo_descuento == "Inasistencia":
            cursor.execute(
                """INSERT INTO auditoria_bono_descuento
                   (administrador_id, nombre_administrador_historico, rut_administrador_historico,
                    trabajador_id, rut_trabajador_historico, tipo_ajuste, concepto, monto_clp)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                (administrador_id, nombre_admin, rut_admin, trabajador_id, rut_trabajador,
                 "Descuento", f"Inasistencia - {fecha_evento.strftime('%d/%m/%Y')}"[:100], int(data.monto_clp))
            )

        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Descuento registrado correctamente", "descuento_id": descuento_id}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: LISTAR DESCUENTOS ───────────────────────────────────
@app.get("/admin/descuentos")
def listar_descuentos(trabajador_id: int = None, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()

        query = """
            SELECT d.descuento_id, d.tipo_descuento, d.monto_clp, d.fecha_evento,
                   d.periodo, p.primer_nombre || ' ' || p.apellido_paterno AS nombre,
                   p.rut, p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin,
                   d.subtipo_prestamo, d.numero_cuota, d.total_cuotas, d.monto_prestamo_total
            FROM descuento d
            JOIN trabajador t ON t.trabajador_id = d.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN administrador a ON a.administrador_id = d.registrado_por
            LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
            WHERE 1=1
        """
        params = []
        if trabajador_id:
            query += " AND d.trabajador_id = %s"
            params.append(trabajador_id)
        if periodo:
            query += " AND d.periodo = %s"
            params.append(periodo)
        query += " ORDER BY d.fecha_evento DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        descuentos = []
        for r in rows:
            (descuento_id, tipo, monto, fecha_evento, periodo_r, nombre, rut, nombre_admin,
             subtipo_prestamo, numero_cuota, total_cuotas, monto_prestamo_total) = r
            descuentos.append({
                "descuento_id":   descuento_id,
                "tipo_descuento": tipo,
                "monto_clp":      int(monto),
                "fecha_evento":   fecha_evento.strftime("%d/%m/%Y") if fecha_evento else "—",
                "periodo":        periodo_r or "—",
                "nombre_trabajador": nombre,
                "rut":            rut,
                "subtipo_prestamo": subtipo_prestamo,
                "numero_cuota":      numero_cuota,
                "total_cuotas":      total_cuotas,
                "monto_prestamo_total": int(monto_prestamo_total) if monto_prestamo_total else None,
                "nombre_admin":   nombre_admin or "—",
            })
        return {"success": True, "descuentos": descuentos}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# BONOS IMPONIBLES
# ══════════════════════════════════════════════════════════════

TIPOS_BONO_VALIDOS = ('Bonificacion', 'Bonificacion de Produccion', 'Bonificacion por Turno', 'Otros')

# Salario minimo mensual (CLP) vigente. Debe mantenerse igual al
# valor usado en el frontend (fichaEmpleadoAdmin.dart, _salarioMinimo).
SALARIO_MINIMO = 553553


def validar_periodo_mm_aaaa(periodo: str):
    """
    Valida formato MM/AAAA: mes 01-12, año de 4 digitos, no futuro
    al mes actual ni anterior a 2000. Retorna (mes, anio) o None si
    es invalido (en cuyo caso ademas retorna el mensaje de error).
    """
    partes = periodo.split("/")
    if len(partes) != 2:
        return None, "Formato de periodo invalido (debe ser MM/AAAA)"
    mes_str, anio_str = partes
    if not (mes_str.isdigit() and anio_str.isdigit() and len(mes_str) == 2 and len(anio_str) == 4):
        return None, "Formato de periodo invalido (debe ser MM/AAAA)"

    mes = int(mes_str)
    anio = int(anio_str)

    if mes < 1 or mes > 12:
        return None, "El mes del periodo debe estar entre 01 y 12"
    if anio < 2000:
        return None, "El año del periodo no puede ser anterior a 2000"

    hoy = dt.date.today()
    if (anio, mes) > (hoy.year, hoy.month):
        return None, "El periodo no puede ser futuro al mes actual"

    return (mes, anio), None


# ── ADMIN: REGISTRAR BONO IMPONIBLE ───────────────────────────
@app.post("/admin/bonos-imponibles")
def registrar_bono_imponible(data: BonoImponibleRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if data.tipo_bono not in TIPOS_BONO_VALIDOS:
            return {"success": False, "mensaje": f"Tipo de bono invalido. Debe ser uno de: {', '.join(TIPOS_BONO_VALIDOS)}"}

        if data.monto_clp <= 0:
            return {"success": False, "mensaje": "El monto debe ser un entero positivo mayor a 0"}

        if data.monto_clp >= 10**9:
            return {"success": False, "mensaje": "El monto no puede superar 9 digitos"}

        _, error_periodo = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        concepto_otros = data.concepto_otros.strip()
        if data.tipo_bono == "Otros":
            if len(concepto_otros) < 3 or len(concepto_otros) > 100:
                return {"success": False, "mensaje": "El concepto de 'Otros' debe tener entre 3 y 100 caracteres"}
        else:
            concepto_otros = None

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """SELECT t.trabajador_id FROM trabajador t
               WHERE t.persona_id = %s""",
            (data.persona_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = r[0]

        if verificar_liquidacion_cerrada(trabajador_id, data.periodo):
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede modificar esta liquidacion porque ya ha sido cerrada"}

        persona_id_admin = get_persona_id(payload)
        cursor.execute(
            "SELECT administrador_id FROM administrador WHERE persona_id = %s",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO bono_imponible
               (trabajador_id, tipo_bono, monto_clp, periodo, concepto_otros, registrado_por)
               VALUES (%s, %s, %s, %s, %s, %s)
               RETURNING bono_id""",
            (trabajador_id, data.tipo_bono, data.monto_clp, data.periodo, concepto_otros, administrador_id)
        )
        bono_id = cursor.fetchone()[0]

        # ── Registro de auditoria automatico ──────────────────
        cursor.execute(
            "SELECT p.rut FROM trabajador t JOIN persona p ON p.persona_id = t.persona_id WHERE t.trabajador_id = %s",
            (trabajador_id,)
        )
        rut_row = cursor.fetchone()
        rut_trabajador = rut_row[0] if rut_row else ""

        cursor.execute(
            """SELECT p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre_admin,
                      p.rut AS rut_admin
               FROM persona p WHERE p.persona_id = %s""",
            (persona_id_admin,)
        )
        admin_info = cursor.fetchone()
        nombre_admin = (admin_info[0] if admin_info else "Administrador")[:120]
        rut_admin = admin_info[1] if admin_info else ""

        cursor.execute(
            """INSERT INTO log_auditoria
               (tabla_afectada, registro_id, tipo_de_operacion, campo_modificado,
                modulo, nombre_completo, informacion_personal, valor_anterior, valor_nuevo, rut_administrador)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                "bono_imponible",
                str(bono_id),
                "INSERT",
                "tipo_bono, monto_clp",
                "Remuneraciones - Bonos Imponibles",
                nombre_admin,
                f"RUT trabajador beneficiado: {rut_trabajador}",
                None,
                f"tipo={data.tipo_bono}; monto=${data.monto_clp} CLP; periodo={data.periodo}",
                rut_admin,
            )
        )
        conn.commit(); cursor.close(); conn.close()

        return {"success": True, "mensaje": "Bono registrado correctamente", "bono_id": bono_id}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: LISTAR BONOS IMPONIBLES ────────────────────────────
@app.get("/admin/bonos-imponibles")
def listar_bonos_imponibles(trabajador_id: int = None, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()

        query = """
            SELECT b.bono_id, b.tipo_bono, b.monto_clp, b.periodo, b.fecha_registro,
                   b.concepto_otros,
                   p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut,
                   p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
            FROM bono_imponible b
            JOIN trabajador t ON t.trabajador_id = b.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN administrador a ON a.administrador_id = b.registrado_por
            LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
            WHERE 1=1
        """
        params = []
        if trabajador_id:
            query += " AND b.trabajador_id = %s"
            params.append(trabajador_id)
        if periodo:
            query += " AND b.periodo = %s"
            params.append(periodo)
        query += " ORDER BY b.fecha_registro DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        bonos = []
        for r in rows:
            bono_id, tipo, monto, periodo_r, fecha_registro, concepto_otros, nombre, rut, nombre_admin = r
            bonos.append({
                "bono_id":        bono_id,
                "tipo_bono":      tipo,
                "concepto_otros": concepto_otros,
                "monto_clp":      int(monto),
                "periodo":        periodo_r,
                "fecha_registro": fecha_registro.strftime("%d/%m/%Y %H:%M") if fecha_registro else "—",
                "nombre_trabajador": nombre,
                "rut":            rut,
                "nombre_admin":   nombre_admin or "—",
            })
        return {"success": True, "bonos": bonos}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# LICENCIAS MEDICAS
# ══════════════════════════════════════════════════════════════

# ── ADMIN: REGISTRAR LICENCIA MEDICA ──────────────────────────
@app.post("/admin/licencias-medicas")
def registrar_licencia_medica(data: LicenciaMedicaRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        try:
            fecha_inicio = dt.datetime.strptime(data.fecha_inicio, "%Y-%m-%d").date()
        except ValueError:
            return {"success": False, "mensaje": "Fecha de inicio invalida (formato esperado AAAA-MM-DD)"}

        try:
            fecha_fin = dt.datetime.strptime(data.fecha_fin, "%Y-%m-%d").date()
        except ValueError:
            return {"success": False, "mensaje": "Fecha de fin invalida (formato esperado AAAA-MM-DD)"}

        if fecha_fin < fecha_inicio:
            return {"success": False, "mensaje": "La fecha de fin debe ser igual o posterior a la fecha de inicio"}

        # Dias de licencia: inclusive (cuenta el dia de inicio y el de fin)
        dias_licencia = (fecha_fin - fecha_inicio).days + 1
        if dias_licencia < 1:
            return {"success": False, "mensaje": "Los dias de licencia deben ser al menos 1"}

        tipo_de_licencia = data.tipo_de_licencia.strip() or "Licencia medica comun"
        if len(tipo_de_licencia) > 50:
            return {"success": False, "mensaje": "El tipo de licencia no puede superar 50 caracteres"}

        entidad_emisora = data.entidad_emisora.strip() or None

        conn = get_connection()
        cursor = conn.cursor()

        # Obtener trabajador_id y sueldo base imponible (del contrato activo)
        cursor.execute(
            """SELECT t.trabajador_id, c.sueldo_base
               FROM trabajador t
               LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE t.persona_id = %s""",
            (data.persona_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id, sueldo_base = r

        if not sueldo_base or float(sueldo_base) <= 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El trabajador no tiene un sueldo base activo registrado"}

        # ── Descuento proporcional: (sueldo base / 30) x dias de licencia ──
        # Resultado como entero en CLP
        descuento_proporcional = round((float(sueldo_base) / 30) * dias_licencia)

        # Periodo de aplicacion: mes/año de la fecha de inicio
        periodo = fecha_inicio.strftime("%m/%Y")

        if verificar_liquidacion_cerrada(trabajador_id, periodo):
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede modificar esta liquidacion porque ya ha sido cerrada"}


        persona_id_admin = get_persona_id(payload)
        cursor.execute(
            "SELECT administrador_id FROM administrador WHERE persona_id = %s",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO licencia_medica
               (tipo_de_licencia, fecha_inicio, fecha_fin, entidad_emisora,
                descuento_proporcional, periodo, trabajador_id, ingresado_por)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
               RETURNING licencia_id""",
            (tipo_de_licencia, fecha_inicio, fecha_fin, entidad_emisora,
             descuento_proporcional, periodo, trabajador_id, administrador_id)
        )
        licencia_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()

        return {
            "success": True,
            "mensaje": "Licencia medica registrada correctamente",
            "licencia_id": licencia_id,
            "dias_licencia": dias_licencia,
            "descuento_proporcional": descuento_proporcional,
            "periodo": periodo,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: LISTAR LICENCIAS MEDICAS ───────────────────────────
@app.get("/admin/licencias-medicas")
def listar_licencias_medicas(trabajador_id: int = None, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()

        query = """
            SELECT l.licencia_id, l.tipo_de_licencia, l.fecha_inicio, l.fecha_fin,
                   l.entidad_emisora, l.descuento_proporcional, l.periodo,
                   p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut,
                   p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
            FROM licencia_medica l
            JOIN trabajador t ON t.trabajador_id = l.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN administrador a ON a.administrador_id = l.ingresado_por
            LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
            WHERE 1=1
        """
        params = []
        if trabajador_id:
            query += " AND l.trabajador_id = %s"
            params.append(trabajador_id)
        if periodo:
            query += " AND l.periodo = %s"
            params.append(periodo)
        query += " ORDER BY l.fecha_inicio DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        licencias = []
        for r in rows:
            (licencia_id, tipo, fecha_inicio, fecha_fin, entidad_emisora,
             descuento, periodo_r, nombre, rut, nombre_admin) = r
            dias = (fecha_fin - fecha_inicio).days + 1
            licencias.append({
                "licencia_id":      licencia_id,
                "tipo_de_licencia": tipo,
                "fecha_inicio":     fecha_inicio.strftime("%d/%m/%Y") if fecha_inicio else "—",
                "fecha_fin":        fecha_fin.strftime("%d/%m/%Y") if fecha_fin else "—",
                "dias_licencia":    dias,
                "entidad_emisora":  entidad_emisora or "—",
                "descuento_proporcional": int(descuento or 0),
                "periodo":          periodo_r or "—",
                "nombre_trabajador": nombre,
                "rut":              rut,
                "nombre_admin":     nombre_admin or "—",
            })
        return {"success": True, "licencias": licencias}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# HORAS EXTRAS (Art. 32 - recargo 50%)
# ══════════════════════════════════════════════════════════════

# ── ADMIN: REGISTRAR HORAS EXTRAS ─────────────────────────────
@app.post("/admin/horas-extras")
def registrar_horas_extras(data: HorasExtrasRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        if data.cantidad_horas <= 0:
            return {"success": False, "mensaje": "La cantidad de horas debe ser mayor a 0"}

        # Tope mensual de referencia (Art. 31: maximo 2 horas extra por
        # dia). Como aqui se ingresa el TOTAL del mes (no por dia), se
        # valida contra un maximo razonable de 2 horas x 31 dias = 62,
        # como resguardo ante datos claramente fuera de rango.
        if data.cantidad_horas > 62:
            return {"success": False, "mensaje": "El total de horas extra del mes no puede superar 62 horas (2 horas/dia, Art. 31)"}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """SELECT t.trabajador_id, c.sueldo_base, c.jornada_semanal_horas
               FROM trabajador t
               LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE t.persona_id = %s""",
            (data.persona_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id, sueldo_base, jornada_semanal = r

        if not sueldo_base or float(sueldo_base) <= 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Error, por el momento no se puede realizar el cálculo. Por favor intente más tarde."}

        if not jornada_semanal or float(jornada_semanal) <= 0:
            cursor.close(); conn.close()
            return {
                "success": False,
                "mensaje": "El trabajador no tiene registrada su jornada semanal. Complétala en su ficha antes de registrar horas extra."
            }

        if verificar_liquidacion_cerrada(trabajador_id, data.periodo):
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede modificar esta liquidacion porque ya ha sido cerrada"}

        # ── Calculo Art. 32 (formula por jornada semanal) ─────
        # El valor de la hora SIEMPRE se calcula con el sueldo base
        # mensual COMPLETO del contrato -- no con el sueldo proporcional
        # (aunque el trabajador haya tenido ingreso/egreso ese mes, o
        # dias descontados por inasistencia/licencia). La ley pacta un
        # sueldo mensual fijo del que se deriva la hora ordinaria; ese
        # valor no cambia por cuantos dias se haya trabajado ese mes
        # en particular.
        # Valor 1 hora normal = (sueldo_base / 30 * 28) / (jornada_semanal * 4)
        valor_hora_normal = round((float(sueldo_base) / 30 * 28) / (float(jornada_semanal) * 4), 4)
        # Recargo 50% sobre la hora normal
        recargo_50 = round(valor_hora_normal * 0.5, 4)
        # Valor 1 hora extra = hora normal + recargo
        valor_hora_extra = round(valor_hora_normal + recargo_50, 4)
        # Total HHEE a pagar en el mes
        monto_total = round(valor_hora_extra * data.cantidad_horas)

        persona_id_admin = get_persona_id(payload)
        cursor.execute(
            "SELECT administrador_id FROM administrador WHERE persona_id = %s",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        # Se guarda valor_hora_normal en la columna valor_hora_ordinaria
        # (mismo nombre de columna que ya existia); el resto del sistema
        # que consume este valor sigue funcionando igual, ya que
        # valor_hora_extra = valor_hora_ordinaria * 1.5 en ambos casos.
        cursor.execute(
            """INSERT INTO horas_extras
               (cantidad_horas, valor_hora_ordinaria, estado, periodo, fecha_aprobacion, trabajador_id, revisado_por)
               VALUES (%s, %s, 'Aprobada', %s, NOW(), %s, %s)
               ON CONFLICT (trabajador_id, periodo) DO UPDATE
               SET cantidad_horas = EXCLUDED.cantidad_horas,
                   valor_hora_ordinaria = EXCLUDED.valor_hora_ordinaria,
                   fecha_aprobacion = NOW(),
                   revisado_por = EXCLUDED.revisado_por
               RETURNING horas_id""",
            (data.cantidad_horas, valor_hora_normal, data.periodo, trabajador_id, administrador_id)
        )
        horas_id = cursor.fetchone()[0]

        # Escribe TAMBIEN en la tabla normalizada calculo_horas
        # (ademas de guardar valor_hora_ordinaria fusionado arriba,
        # para esta rama de prueba donde se separan de verdad las
        # tablas normalizadas del MER).
        cursor.execute(
            """INSERT INTO calculo_horas (monto_clp, horas_id)
               VALUES (%s, %s)
               ON CONFLICT (horas_id) DO UPDATE
               SET monto_clp = EXCLUDED.monto_clp""",
            (monto_total, horas_id)
        )

        conn.commit(); cursor.close(); conn.close()

        return {
            "success": True,
            "mensaje": "Horas extras registradas correctamente",
            "horas_id": horas_id,
            "jornada_semanal_horas": float(jornada_semanal),
            "valor_hora_normal": valor_hora_normal,
            "recargo_50": recargo_50,
            "valor_hora_extra": valor_hora_extra,
            "monto_total": monto_total,
            "periodo": data.periodo,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: LISTAR HORAS EXTRAS ─────────────────────────────────
@app.get("/admin/horas-extras")
def listar_horas_extras(trabajador_id: int = None, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()

        query = """
            SELECT h.horas_id, h.cantidad_horas, h.valor_hora_ordinaria, h.periodo,
                   h.fecha_aprobacion, h.estado,
                   p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut,
                   p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
            FROM horas_extras h
            JOIN trabajador t ON t.trabajador_id = h.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN administrador a ON a.administrador_id = h.revisado_por
            LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
            WHERE 1=1
        """
        params = []
        if trabajador_id:
            query += " AND h.trabajador_id = %s"
            params.append(trabajador_id)
        if periodo:
            query += " AND h.periodo = %s"
            params.append(periodo)
        query += " ORDER BY h.fecha_aprobacion DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        registros = []
        for r in rows:
            (horas_id, cantidad_horas, valor_hora_normal, periodo_r,
             fecha_aprobacion, estado, nombre, rut, nombre_admin) = r
            recargo_50 = round(float(valor_hora_normal) * 0.5, 4)
            valor_hora_extra = round(float(valor_hora_normal) + recargo_50, 4)
            monto_total = round(valor_hora_extra * float(cantidad_horas))
            registros.append({
                "horas_id":             horas_id,
                "cantidad_horas":       float(cantidad_horas),
                "valor_hora_normal":    float(valor_hora_normal),
                "monto_total":          monto_total,
                "periodo":              periodo_r,
                "fecha_registro":       fecha_aprobacion.strftime("%d/%m/%Y %H:%M") if fecha_aprobacion else "—",
                "estado":               estado,
                "nombre_trabajador":    nombre,
                "rut":                  rut,
                "nombre_admin":         nombre_admin or "—",
            })
        return {"success": True, "registros": registros}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# VALOR UTM MENSUAL
# ══════════════════════════════════════════════════════════════

def hay_utm_para_periodo(periodo: str) -> bool:
    """
    Helper reutilizable para cuando se construya el cierre de
    remuneraciones: retorna True si ya existe un valor UTM cargado
    para el periodo MM/AAAA indicado.
    """
    (mes_anio, error) = validar_periodo_mm_aaaa(periodo)
    if error:
        return False
    mes, anio = mes_anio
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT 1 FROM valor_utm WHERE mes = %s AND anio = %s", (mes, anio))
    existe = cursor.fetchone() is not None
    cursor.close(); conn.close()
    return existe


def obtener_valor_utm_periodo(periodo: str):
    """
    Retorna el valor UTM (float) cargado para el periodo MM/AAAA,
    o None si no ha sido registrado.
    """
    (mes_anio, error) = validar_periodo_mm_aaaa(periodo)
    if error:
        return None
    mes, anio = mes_anio
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT valor_clp FROM valor_utm WHERE mes = %s AND anio = %s", (mes, anio))
    row = cursor.fetchone()
    cursor.close(); conn.close()
    return float(row[0]) if row else None


# ── ADMIN: REGISTRAR/ACTUALIZAR VALOR UTM ─────────────────────
@app.post("/admin/valor-utm")
def registrar_valor_utm(data: ValorUtmRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if data.valor_clp <= 0:
            return {"success": False, "mensaje": "El valor UTM debe ser un entero positivo mayor a 0"}
        if data.valor_clp >= 10**7:
            return {"success": False, "mensaje": "El valor UTM no puede superar 7 digitos"}

        (mes_anio, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}
        mes, anio = mes_anio

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT administrador_id FROM administrador WHERE persona_id = %s",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        # UPSERT: si ya existe un valor para ese mes/anio, se actualiza
        cursor.execute(
            """INSERT INTO valor_utm (valor_clp, mes, anio, ingresado_por)
               VALUES (%s, %s, %s, %s)
               ON CONFLICT (mes, anio) DO UPDATE
               SET valor_clp = EXCLUDED.valor_clp,
                   ingresado_por = EXCLUDED.ingresado_por,
                   fecha_ingreso = NOW()
               RETURNING utm_id""",
            (data.valor_clp, mes, anio, administrador_id)
        )
        utm_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()

        return {"success": True, "mensaje": "Valor UTM registrado correctamente", "utm_id": utm_id}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: LISTAR VALORES UTM ──────────────────────────────────
@app.get("/admin/valor-utm")
def listar_valor_utm(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT u.utm_id, u.valor_clp, u.mes, u.anio, u.fecha_ingreso,
                      p.primer_nombre || ' ' || p.apellido_paterno AS nombre_admin
               FROM valor_utm u
               LEFT JOIN administrador a ON a.administrador_id = u.ingresado_por
               LEFT JOIN persona p ON p.persona_id = a.persona_id
               ORDER BY u.anio DESC, u.mes DESC"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        valores = []
        for r in rows:
            utm_id, valor_clp, mes, anio, fecha_ingreso, nombre_admin = r
            valores.append({
                "utm_id":         utm_id,
                "valor_clp":      int(valor_clp),
                "periodo":        f"{str(mes).zfill(2)}/{anio}",
                "fecha_ingreso":  fecha_ingreso.strftime("%d/%m/%Y %H:%M") if fecha_ingreso else "—",
                "nombre_admin":   nombre_admin or "—",
            })
        return {"success": True, "valores": valores}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# CALCULO PROPORCIONAL POR DIAS TRABAJADOS (Art. 41)
# ══════════════════════════════════════════════════════════════

MOTIVOS_PROPORCIONAL_VALIDOS = ('Ingreso', 'Egreso')

# ── ADMIN: REGISTRAR CALCULO PROPORCIONAL ─────────────────────
@app.post("/admin/calculo-proporcional")
def registrar_calculo_proporcional(data: CalculoProporcionalRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if data.motivo not in MOTIVOS_PROPORCIONAL_VALIDOS:
            return {"success": False, "mensaje": f"Motivo invalido. Debe ser uno de: {', '.join(MOTIVOS_PROPORCIONAL_VALIDOS)}"}

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        mes_periodo, anio_periodo = (int(x) for x in data.periodo.split("/"))
        ultimo_dia_mes = calendar.monthrange(anio_periodo, mes_periodo)[1]

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """SELECT t.trabajador_id, c.sueldo_base, c.fecha_ingreso
               FROM trabajador t
               LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE t.persona_id = %s""",
            (data.persona_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id, sueldo_base, fecha_ingreso_contrato = r

        if not sueldo_base or float(sueldo_base) <= 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El trabajador no tiene un sueldo base activo registrado"}

        # ── Calcula los dias trabajados segun el motivo ──────────
        if data.motivo == "Ingreso":
            if not fecha_ingreso_contrato:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "El trabajador no tiene fecha de ingreso registrada en su contrato"}
            if fecha_ingreso_contrato.year != anio_periodo or fecha_ingreso_contrato.month != mes_periodo:
                cursor.close(); conn.close()
                return {
                    "success": False,
                    "mensaje": f"La fecha de ingreso del contrato ({fecha_ingreso_contrato.strftime('%d/%m/%Y')}) no corresponde al período {data.periodo}"
                }
            dias_trabajados = ultimo_dia_mes - fecha_ingreso_contrato.day + 1
            fecha_usada = fecha_ingreso_contrato
        else:  # Egreso
            if not data.fecha_referencia:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "Debes indicar la fecha del último día trabajado (motivo Egreso)"}
            try:
                fecha_egreso = dt.date.fromisoformat(data.fecha_referencia)
            except ValueError:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "Fecha de referencia invalida, usa formato YYYY-MM-DD"}
            if fecha_egreso.year != anio_periodo or fecha_egreso.month != mes_periodo:
                cursor.close(); conn.close()
                return {
                    "success": False,
                    "mensaje": f"La fecha del último día trabajado ({fecha_egreso.strftime('%d/%m/%Y')}) no corresponde al período {data.periodo}"
                }
            dias_trabajados = fecha_egreso.day  # el mes siempre parte el dia 1: dia - 1 + 1 = dia
            fecha_usada = fecha_egreso

        if dias_trabajados < 1 or dias_trabajados > ultimo_dia_mes:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Los días trabajados calculados quedaron fuera de rango, revisa la fecha"}

        # ── Colacion/Locomocion: usa lo confirmado para el periodo en
        #    Parametros del Sistema; si nadie confirmo aun, usa el
        #    monto fijo por defecto del sistema ──────────────────
        cursor.execute(
            "SELECT monto_movilizacion, monto_colacion FROM confirmacion_movilizacion_colacion WHERE periodo = %s",
            (data.periodo,)
        )
        confirmacion_row = cursor.fetchone()
        monto_locomocion_base = float(confirmacion_row[0]) if confirmacion_row else MONTO_FIJO_MOVILIZACION
        monto_colacion_base = float(confirmacion_row[1]) if confirmacion_row else MONTO_FIJO_COLACION

        # ── Calculo Art. 41 ──────────────────────────────────
        sueldo_diario = round(float(sueldo_base) / 30, 4)
        monto_proporcional = round(sueldo_diario * dias_trabajados)
        colacion_proporcional = round((monto_colacion_base / 30) * dias_trabajados)
        locomocion_proporcional = round((monto_locomocion_base / 30) * dias_trabajados)

        persona_id_admin = get_persona_id(payload)
        cursor.execute(
            "SELECT administrador_id FROM administrador WHERE persona_id = %s",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO calculo_proporcional
               (trabajador_id, dias_trabajados, sueldo_diario, monto_proporcional,
                colacion_proporcional, locomocion_proporcional,
                periodo, motivo, registrado_por)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
               ON CONFLICT (trabajador_id, periodo) DO UPDATE
               SET dias_trabajados = EXCLUDED.dias_trabajados,
                   sueldo_diario = EXCLUDED.sueldo_diario,
                   monto_proporcional = EXCLUDED.monto_proporcional,
                   colacion_proporcional = EXCLUDED.colacion_proporcional,
                   locomocion_proporcional = EXCLUDED.locomocion_proporcional,
                   motivo = EXCLUDED.motivo,
                   registrado_por = EXCLUDED.registrado_por,
                   fecha_registro = NOW()
               RETURNING calculo_id""",
            (trabajador_id, dias_trabajados, sueldo_diario, monto_proporcional,
             colacion_proporcional, locomocion_proporcional,
             data.periodo, data.motivo, administrador_id)
        )
        calculo_id = cursor.fetchone()[0]

        # Escribe TAMBIEN en la tabla normalizada calculo_monto_proporcional
        # (ademas de guardarlo fusionado arriba, para esta rama de prueba
        # donde se separan de verdad las tablas normalizadas del MER).
        cursor.execute(
            """INSERT INTO calculo_monto_proporcional (monto_proporcional, calculo_id)
               VALUES (%s, %s)
               ON CONFLICT (calculo_id) DO UPDATE
               SET monto_proporcional = EXCLUDED.monto_proporcional""",
            (monto_proporcional, calculo_id)
        )

        conn.commit(); cursor.close(); conn.close()

        return {
            "success": True,
            "mensaje": "Calculo proporcional registrado correctamente",
            "calculo_id": calculo_id,
            "dias_trabajados": dias_trabajados,
            "fecha_usada": fecha_usada.strftime("%d/%m/%Y"),
            "sueldo_diario": sueldo_diario,
            "monto_proporcional": monto_proporcional,
            "colacion_proporcional": colacion_proporcional,
            "locomocion_proporcional": locomocion_proporcional,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}



# ── ADMIN: LISTAR CALCULOS PROPORCIONALES ─────────────────────
@app.get("/admin/calculo-proporcional")
def listar_calculo_proporcional(trabajador_id: int = None, persona_id: int = None, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()

        if persona_id and not trabajador_id:
            cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id,))
            r_trab = cursor.fetchone()
            if not r_trab:
                cursor.close(); conn.close()
                return {"success": True, "calculos": []}
            trabajador_id = r_trab[0]

        query = """
            SELECT c.calculo_id, c.dias_trabajados, c.sueldo_diario, c.monto_proporcional,
                   c.colacion_proporcional, c.locomocion_proporcional,
                   c.periodo, c.motivo, c.fecha_registro,
                   p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut,
                   p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
            FROM calculo_proporcional c
            JOIN trabajador t ON t.trabajador_id = c.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN administrador a ON a.administrador_id = c.registrado_por
            LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
            WHERE 1=1
        """
        params = []
        if trabajador_id:
            query += " AND c.trabajador_id = %s"
            params.append(trabajador_id)
        if periodo:
            query += " AND c.periodo = %s"
            params.append(periodo)
        query += " ORDER BY c.fecha_registro DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        calculos = []
        for r in rows:
            (calculo_id, dias, sueldo_diario, monto, colacion, locomocion, periodo_r, motivo,
             fecha_registro, nombre, rut, nombre_admin) = r
            calculos.append({
                "calculo_id":              calculo_id,
                "dias_trabajados":         dias,
                "sueldo_diario":           float(sueldo_diario),
                "monto_proporcional":      int(monto),
                "colacion_proporcional":   int(colacion) if colacion is not None else 0,
                "locomocion_proporcional": int(locomocion) if locomocion is not None else 0,
                "periodo":                 periodo_r,
                "motivo":                  motivo,
                "fecha_registro":          fecha_registro.strftime("%d/%m/%Y %H:%M") if fecha_registro else "—",
                "nombre_trabajador":       nombre,
                "rut":                     rut,
                "nombre_admin":            nombre_admin or "—",
            })
        return {"success": True, "calculos": calculos}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# MOVILIZACION Y COLACION (topes no imponibles)
# ══════════════════════════════════════════════════════════════

CONCEPTOS_NO_IMPONIBLES_VALIDOS = ('Movilizacion', 'Colacion')

# ── ADMIN: VER CONFIGURACION DE TOPES ─────────────────────────
@app.get("/admin/config-topes-no-imponibles")
def ver_topes_no_imponibles(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT concepto, monto_exento_diario, fecha_modificacion
               FROM config_topes_no_imponibles ORDER BY concepto"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        topes = [
            {
                "concepto": r[0],
                "monto_exento_diario": int(r[1]),
                "fecha_modificacion": r[2].strftime("%d/%m/%Y %H:%M") if r[2] else "—",
            }
            for r in rows
        ]
        return {"success": True, "topes": topes}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: ACTUALIZAR TOPE (por si cambia el valor legal real) ─
@app.put("/admin/config-topes-no-imponibles")
def actualizar_tope_no_imponible(data: TopeNoImponibleRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if data.concepto not in CONCEPTOS_NO_IMPONIBLES_VALIDOS:
            return {"success": False, "mensaje": f"Concepto invalido. Debe ser uno de: {', '.join(CONCEPTOS_NO_IMPONIBLES_VALIDOS)}"}
        if data.monto_exento_diario <= 0:
            return {"success": False, "mensaje": "El monto exento debe ser un entero positivo mayor a 0"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT administrador_id FROM administrador WHERE persona_id = %s",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """UPDATE config_topes_no_imponibles
               SET monto_exento_diario = %s, fecha_modificacion = NOW(), modificado_por = %s
               WHERE concepto = %s""",
            (data.monto_exento_diario, administrador_id, data.concepto)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Tope de {data.concepto} actualizado correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: REGISTRAR ASIGNACION DE MOVILIZACION/COLACION ──────
@app.post("/admin/asignaciones-no-imponibles")
def registrar_asignacion_no_imponible(data: AsignacionNoImponibleRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if data.concepto not in CONCEPTOS_NO_IMPONIBLES_VALIDOS:
            return {"success": False, "mensaje": f"Concepto invalido. Debe ser uno de: {', '.join(CONCEPTOS_NO_IMPONIBLES_VALIDOS)}"}
        if data.monto_total_mensual <= 0:
            return {"success": False, "mensaje": "El monto debe ser un entero positivo mayor a 0"}
        if data.dias_periodo < 1 or data.dias_periodo > 31:
            return {"success": False, "mensaje": "Los dias del periodo deben estar entre 1 y 31"}

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (data.persona_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = r[0]

        cursor.execute(
            "SELECT monto_exento_diario FROM config_topes_no_imponibles WHERE concepto = %s",
            (data.concepto,)
        )
        tope_row = cursor.fetchone()
        if not tope_row:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No hay tope configurado para este concepto"}
        tope_diario = float(tope_row[0])

        # ── Calculo del tope mensual y el excedente imponible ──
        tope_mensual = tope_diario * data.dias_periodo
        monto_exento = min(float(data.monto_total_mensual), tope_mensual)
        monto_excedente = max(0.0, float(data.monto_total_mensual) - tope_mensual)

        persona_id_admin = get_persona_id(payload)
        cursor.execute(
            "SELECT administrador_id FROM administrador WHERE persona_id = %s",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO asignacion_no_imponible
               (trabajador_id, concepto, monto_total_mensual, dias_periodo,
                monto_exento, monto_excedente, periodo, registrado_por)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
               ON CONFLICT (trabajador_id, periodo, concepto) DO UPDATE
               SET monto_total_mensual = EXCLUDED.monto_total_mensual,
                   dias_periodo = EXCLUDED.dias_periodo,
                   monto_exento = EXCLUDED.monto_exento,
                   monto_excedente = EXCLUDED.monto_excedente,
                   registrado_por = EXCLUDED.registrado_por,
                   fecha_registro = NOW()
               RETURNING asignacion_id""",
            (trabajador_id, data.concepto, data.monto_total_mensual, data.dias_periodo,
             monto_exento, monto_excedente, data.periodo, administrador_id)
        )
        asignacion_id = cursor.fetchone()[0]

        # Escribe TAMBIEN en la tabla normalizada calculo_monto_no_imponible
        # (ademas de guardarlo fusionado arriba, para esta rama de prueba).
        cursor.execute(
            """INSERT INTO calculo_monto_no_imponible (monto_exento, monto_excedente, asignacion_id)
               VALUES (%s, %s, %s)
               ON CONFLICT (asignacion_id) DO UPDATE
               SET monto_exento = EXCLUDED.monto_exento,
                   monto_excedente = EXCLUDED.monto_excedente""",
            (monto_exento, monto_excedente, asignacion_id)
        )

        conn.commit(); cursor.close(); conn.close()

        return {
            "success": True,
            "mensaje": "Asignacion registrada correctamente",
            "asignacion_id": asignacion_id,
            "tope_mensual": round(tope_mensual),
            "monto_exento": round(monto_exento),
            "monto_excedente": round(monto_excedente),
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: LISTAR ASIGNACIONES ─────────────────────────────────
@app.get("/admin/asignaciones-no-imponibles")
def listar_asignaciones_no_imponibles(trabajador_id: int = None, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()

        query = """
            SELECT a.asignacion_id, a.concepto, a.monto_total_mensual, a.dias_periodo,
                   a.monto_exento, a.monto_excedente, a.periodo, a.fecha_registro,
                   p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut,
                   p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
            FROM asignacion_no_imponible a
            JOIN trabajador t ON t.trabajador_id = a.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN administrador ad ON ad.administrador_id = a.registrado_por
            LEFT JOIN persona p2 ON p2.persona_id = ad.persona_id
            WHERE 1=1
        """
        params = []
        if trabajador_id:
            query += " AND a.trabajador_id = %s"
            params.append(trabajador_id)
        if periodo:
            query += " AND a.periodo = %s"
            params.append(periodo)
        query += " ORDER BY a.fecha_registro DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        asignaciones = []
        for r in rows:
            (asignacion_id, concepto, monto_total, dias_periodo, monto_exento,
             monto_excedente, periodo_r, fecha_registro, nombre, rut, nombre_admin) = r
            asignaciones.append({
                "asignacion_id":        asignacion_id,
                "concepto":             concepto,
                "monto_total_mensual":  int(monto_total),
                "dias_periodo":         dias_periodo,
                "monto_exento":         int(monto_exento),
                "monto_excedente":      int(monto_excedente),
                "periodo":              periodo_r,
                "fecha_registro":       fecha_registro.strftime("%d/%m/%Y %H:%M") if fecha_registro else "—",
                "nombre_trabajador":    nombre,
                "rut":                  rut,
                "nombre_admin":         nombre_admin or "—",
            })
        return {"success": True, "asignaciones": asignaciones}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── MOVILIZACION Y COLACION CON VALORES FIJOS (sin tope diario) ──
# La ley no fija un monto maximo exacto para estos conceptos (se
# evalua por "razonabilidad"), asi que la clinica definio montos
# fijos mensuales en vez de un tope diario: se registran siempre
# integramente como no imponibles, sin excedente.
MONTO_FIJO_MOVILIZACION = 50000
MONTO_FIJO_COLACION = 60000


@app.post("/admin/movilizacion-colacion-fija")
def registrar_movilizacion_colacion_fija(data: MovilizacionColacionFijaRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (data.persona_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = r[0]

        if verificar_liquidacion_cerrada(trabajador_id, data.periodo):
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede modificar esta liquidacion porque ya ha sido cerrada"}

        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        for concepto, monto in (("Movilizacion", MONTO_FIJO_MOVILIZACION), ("Colacion", MONTO_FIJO_COLACION)):
            cursor.execute(
                """INSERT INTO asignacion_no_imponible
                   (trabajador_id, concepto, monto_total_mensual, dias_periodo,
                    monto_exento, monto_excedente, periodo, registrado_por)
                   VALUES (%s, %s, %s, 30, %s, 0, %s, %s)
                   ON CONFLICT (trabajador_id, periodo, concepto) DO UPDATE
                   SET monto_total_mensual = EXCLUDED.monto_total_mensual,
                       monto_exento = EXCLUDED.monto_exento,
                       monto_excedente = 0,
                       registrado_por = EXCLUDED.registrado_por,
                       fecha_registro = NOW()
                   RETURNING asignacion_id""",
                (trabajador_id, concepto, monto, monto, data.periodo, administrador_id)
            )
            asignacion_id = cursor.fetchone()[0]

            # Escribe TAMBIEN en la tabla normalizada calculo_monto_no_imponible
            cursor.execute(
                """INSERT INTO calculo_monto_no_imponible (monto_exento, monto_excedente, asignacion_id)
                   VALUES (%s, 0, %s)
                   ON CONFLICT (asignacion_id) DO UPDATE
                   SET monto_exento = EXCLUDED.monto_exento,
                       monto_excedente = 0""",
                (monto, asignacion_id)
            )

        conn.commit(); cursor.close(); conn.close()
        return {
            "success": True,
            "mensaje": "Movilización y colación registradas correctamente",
            "monto_movilizacion": MONTO_FIJO_MOVILIZACION,
            "monto_colacion": MONTO_FIJO_COLACION,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.post("/admin/confirmar-movilizacion-colacion")
def confirmar_movilizacion_colacion(data: ConfirmarMovilizacionColacionRequest, payload: dict = Depends(verificar_token)):
    """
    Confirma los montos fijos de Movilizacion/Colacion para TODO el
    periodo de una sola vez (no por trabajador). A partir de esta
    confirmacion, el calculo del total imponible de cualquier
    trabajador que NO tenga ya un registro individual en
    asignacion_no_imponible para ese periodo, aplica automaticamente
    estos montos fijos.
    """
    try:
        verificar_rol(payload, ["admin"])

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        conn = get_connection()
        cursor = conn.cursor()

        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO confirmacion_movilizacion_colacion
               (periodo, monto_movilizacion, monto_colacion, administrador_id, fecha_confirmacion)
               VALUES (%s, %s, %s, %s, NOW())
               ON CONFLICT (periodo) DO UPDATE
               SET monto_movilizacion = EXCLUDED.monto_movilizacion,
                   monto_colacion = EXCLUDED.monto_colacion,
                   administrador_id = EXCLUDED.administrador_id,
                   fecha_confirmacion = NOW()""",
            (data.periodo, MONTO_FIJO_MOVILIZACION, MONTO_FIJO_COLACION, administrador_id)
        )
        conn.commit(); cursor.close(); conn.close()
        return {
            "success": True,
            "mensaje": f"Movilización (${MONTO_FIJO_MOVILIZACION}) y Colación (${MONTO_FIJO_COLACION}) confirmadas para {data.periodo}. Se aplicarán automáticamente a todos los trabajadores.",
            "monto_movilizacion": MONTO_FIJO_MOVILIZACION,
            "monto_colacion": MONTO_FIJO_COLACION,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/estado-movilizacion-colacion")
def estado_movilizacion_colacion(periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT cmc.monto_movilizacion, cmc.monto_colacion, cmc.fecha_confirmacion,
                      p.primer_nombre, p.apellido_paterno
               FROM confirmacion_movilizacion_colacion cmc
               LEFT JOIN administrador a ON a.administrador_id = cmc.administrador_id
               LEFT JOIN persona p ON p.persona_id = a.persona_id
               WHERE cmc.periodo = %s""",
            (periodo,)
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()
        if not r:
            return {"success": True, "confirmado": False}
        return {
            "success": True,
            "confirmado": True,
            "monto_movilizacion": float(r[0]),
            "monto_colacion": float(r[1]),
            "fecha_confirmacion": r[2].isoformat() if r[2] else None,
            "confirmado_por": f"{r[3]} {r[4]}".strip() if r[3] else None,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/historial-movilizacion-colacion")
def historial_movilizacion_colacion(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT cmc.periodo, cmc.monto_movilizacion, cmc.monto_colacion,
                      cmc.fecha_confirmacion, p.primer_nombre, p.apellido_paterno
               FROM confirmacion_movilizacion_colacion cmc
               LEFT JOIN administrador a ON a.administrador_id = cmc.administrador_id
               LEFT JOIN persona p ON p.persona_id = a.persona_id
               ORDER BY cmc.periodo DESC"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "confirmaciones": [
                {
                    "periodo": r[0],
                    "monto_movilizacion": float(r[1]),
                    "monto_colacion": float(r[2]),
                    "fecha_confirmacion": r[3].strftime("%d/%m/%Y %H:%M") if r[3] else "—",
                    "confirmado_por": f"{r[4]} {r[5]}".strip() if r[4] else "—",
                }
                for r in rows
            ],
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# PROGRESO DEL WIZARD "CALCULO DE LIQUIDACION TOTAL"
# ══════════════════════════════════════════════════════════════

@app.get("/admin/wizard-progreso")
def obtener_progreso_wizard(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": True, "existe": False}
        trabajador_id = r[0]

        cursor.execute(
            """SELECT p.paso_actual, p.fecha_actualizacion, a2.persona_id
               FROM progreso_liquidacion_wizard p
               LEFT JOIN administrador a2 ON a2.administrador_id = p.administrador_id
               WHERE p.trabajador_id = %s AND p.periodo = %s""",
            (trabajador_id, periodo)
        )
        row = cursor.fetchone()
        cursor.close(); conn.close()
        if not row:
            return {"success": True, "existe": False}
        return {
            "success": True,
            "existe": True,
            "paso_actual": row[0],
            "fecha_actualizacion": row[1].strftime("%d/%m/%Y %H:%M") if row[1] else None,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.post("/admin/wizard-progreso")
def guardar_progreso_wizard(data: ProgresoWizardRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (data.persona_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = r[0]

        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO progreso_liquidacion_wizard (trabajador_id, periodo, paso_actual, administrador_id)
               VALUES (%s, %s, %s, %s)
               ON CONFLICT (trabajador_id, periodo) DO UPDATE
               SET paso_actual = EXCLUDED.paso_actual,
                   administrador_id = EXCLUDED.administrador_id,
                   fecha_actualizacion = NOW()""",
            (trabajador_id, data.periodo, data.paso_actual, administrador_id)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.delete("/admin/wizard-progreso")
def borrar_progreso_wizard(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": True}
        trabajador_id = r[0]
        cursor.execute(
            "DELETE FROM progreso_liquidacion_wizard WHERE trabajador_id = %s AND periodo = %s",
            (trabajador_id, periodo)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# RESUMEN DE REGISTROS DEL PERIODO ("Ya registrado: ...")
# ══════════════════════════════════════════════════════════════

@app.get("/admin/resumen-registros-periodo")
def resumen_registros_periodo(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = r[0]

        resumen = {}

        cursor.execute(
            "SELECT tipo_descuento, monto_clp, fecha_evento FROM descuento WHERE trabajador_id = %s AND periodo = %s ORDER BY descuento_id",
            (trabajador_id, periodo)
        )
        resumen["descuentos"] = [
            {"tipo": t, "monto": int(m), "fecha": f.strftime("%d/%m/%Y") if f else "—"}
            for (t, m, f) in cursor.fetchall()
        ]

        cursor.execute(
            "SELECT tipo_bono, monto_clp FROM bono_imponible WHERE trabajador_id = %s AND periodo = %s ORDER BY bono_id",
            (trabajador_id, periodo)
        )
        resumen["bonos_imponibles"] = [{"tipo": t, "monto": int(m)} for (t, m) in cursor.fetchall()]

        cursor.execute(
            "SELECT tipo_de_licencia, fecha_inicio, fecha_fin, descuento_proporcional FROM licencia_medica WHERE trabajador_id = %s AND periodo = %s ORDER BY licencia_id",
            (trabajador_id, periodo)
        )
        resumen["licencias"] = [
            {"tipo": t, "inicio": fi.strftime("%d/%m/%Y") if fi else "—", "fin": ff.strftime("%d/%m/%Y") if ff else "—", "monto": int(m)}
            for (t, fi, ff, m) in cursor.fetchall()
        ]

        cursor.execute(
            "SELECT cantidad_horas, valor_hora_ordinaria FROM horas_extras WHERE trabajador_id = %s AND periodo = %s",
            (trabajador_id, periodo)
        )
        horas_row = cursor.fetchone()
        if horas_row:
            resumen["horas_extras"] = float(horas_row[0])
            resumen["horas_extras_monto"] = round(float(horas_row[1]) * 1.5 * float(horas_row[0]))
        else:
            resumen["horas_extras"] = None
            resumen["horas_extras_monto"] = None

        cursor.execute(
            "SELECT dias_trabajados, motivo, monto_proporcional FROM calculo_proporcional WHERE trabajador_id = %s AND periodo = %s",
            (trabajador_id, periodo)
        )
        prop_row = cursor.fetchone()
        resumen["calculo_proporcional"] = (
            {"dias": prop_row[0], "motivo": prop_row[1], "monto": int(prop_row[2])} if prop_row else None
        )

        cursor.execute(
            "SELECT concepto, monto_total_mensual FROM asignacion_no_imponible WHERE trabajador_id = %s AND periodo = %s ORDER BY concepto",
            (trabajador_id, periodo)
        )
        resumen["movilizacion_colacion"] = [{"concepto": c, "monto": int(m)} for (c, m) in cursor.fetchall()]

        cursor.execute(
            "SELECT concepto, monto_clp, clasificacion FROM bono_excepcional WHERE trabajador_id = %s AND periodo = %s ORDER BY bono_id",
            (trabajador_id, periodo)
        )
        resumen["bonos_excepcionales"] = [
            {"concepto": c, "monto": int(m), "clasificacion": cl} for (c, m, cl) in cursor.fetchall()
        ]

        cursor.execute(
            "SELECT monto_clp, folio_autorizacion, estado FROM anticipo_sueldo WHERE trabajador_id = %s AND periodo = %s",
            (trabajador_id, periodo)
        )
        ant_row = cursor.fetchone()
        resumen["anticipo"] = (
            {"monto": int(ant_row[0]), "folio": ant_row[1], "estado": ant_row[2]} if ant_row else None
        )

        cursor.close(); conn.close()
        return {"success": True, "resumen": resumen}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# TOTAL IMPONIBLE (nucleo de la liquidacion)
# ══════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════
# TOTAL IMPONIBLE (nucleo de la liquidacion)
# ══════════════════════════════════════════════════════════════

def _gratificacion_para_total_imponible(persona_id: int, periodo: str) -> dict:
    """
    Version ligera del calculo de gratificacion, pensada para ser
    llamada DESDE calcular_total_imponible_interno sin generar
    dependencia circular (usa _obtener_base_gratificacion, que solo
    lee sueldo_base + horas_extras + bonos_imponibles directamente,
    NUNCA el total_imponible ya calculado).

    Retorna {"success": bool, "monto": int, "mensaje": str|None}.
    Si falta el valor IMM del periodo, bloquea con un mensaje
    especifico -- decision de negocio explicita: es mejor detener el
    calculo con un aviso claro, que dejar la Gratificacion en $0 de
    forma silenciosa y que la empresa no se percate del error.
    Si la modalidad es 'Anual' (requiere un dato manual que no
    siempre esta disponible en este flujo), retorna monto 0 sin
    bloquear -- ese caso no corresponde a un dato faltante por error.
    """
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT modalidad, porcentaje_mensual, limite_imm_anual
               FROM config_gratificacion ORDER BY config_id DESC LIMIT 1"""
        )
        config_row = cursor.fetchone()
        cursor.close(); conn.close()
        if not config_row or config_row[0] != "Proporcional":
            return {"success": True, "monto": 0, "mensaje": None}

        _, porcentaje_mensual, limite_imm_anual = config_row
        porcentaje_mensual = float(porcentaje_mensual or 25.0)
        limite_imm_anual = float(limite_imm_anual or 4.75)

        valor_imm = obtener_valor_imm_periodo(periodo)
        if valor_imm is None:
            return {
                "success": False,
                "monto": 0,
                "mensaje": "Es necesario ingresar el valor del IMM del periodo antes de calcular la gratificacion",
            }

        base_gratificacion = _obtener_base_gratificacion(persona_id, periodo)
        if not base_gratificacion.get("success"):
            return {"success": True, "monto": 0, "mensaje": None}

        gratificacion_sin_tope = round(base_gratificacion["base_calculo"] * porcentaje_mensual / 100)
        tope_mensual = round((limite_imm_anual * valor_imm) / 12)
        return {"success": True, "monto": min(gratificacion_sin_tope, tope_mensual), "mensaje": None}
    except Exception:
        return {"success": True, "monto": 0, "mensaje": None}


def calcular_total_imponible_interno(persona_id: int, periodo: str) -> dict:
    """
    Funcion interna reutilizable (no es un endpoint): calcula el total
    imponible de un trabajador para un periodo (MM/AAAA), recorriendo
    todos los conceptos imponibles ya registrados:
      - Sueldo base (o el monto proporcional si hubo ingreso/egreso ese mes)
      - Horas extras aprobadas del periodo (Art. 32)
      - Bonos imponibles del periodo
      - Excedente de movilizacion/colacion del periodo (la parte que
        supero el tope legal exento, que pasa a ser imponible)

    Retorna {"success": False, "mensaje": ...} si algo falla, o el
    diccionario completo con desglose y total_imponible si todo OK.
    Reutilizada por /admin/total-imponible, /admin/calculo-afc, y
    cuando se construya el cierre de remuneraciones.
    """
    (_, error_periodo) = validar_periodo_mm_aaaa(periodo)
    if error_periodo:
        return {"success": False, "mensaje": error_periodo}

    # Reutiliza el resultado si ya se calculo antes DENTRO de esta
    # misma peticion (ej: cuando "Costo Total Empleador" llama a
    # AFP+AFC+Impuesto Unico juntos). Nunca sobrevive a la peticion.
    _clave_cache = (persona_id, periodo)
    if _clave_cache in _cache_total_imponible:
        return _cache_total_imponible[_clave_cache]

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute(
        """SELECT t.trabajador_id, c.sueldo_base, c.tipo_contrato,
                  p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre,
                  p.rut
           FROM trabajador t
           JOIN persona p ON p.persona_id = t.persona_id
           LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
           WHERE t.persona_id = %s""",
        (persona_id,)
    )
    r = cursor.fetchone()
    if not r:
        cursor.close(); conn.close()
        return {"success": False, "mensaje": "Trabajador no encontrado"}
    trabajador_id, sueldo_base, tipo_contrato, nombre, rut = r

    if not sueldo_base or float(sueldo_base) <= 0:
        cursor.close(); conn.close()
        return {"success": False, "mensaje": "El trabajador no tiene un sueldo base activo registrado"}

    # ── 1. Sueldo base (o proporcional si hay ingreso/egreso ese mes),
    #    ya neto de Inasistencia y Licencia Medica: el sueldo, colacion
    #    y locomocion se pagan solo por los dias EFECTIVAMENTE
    #    trabajados (dias del proporcional, o 30 si no hay, menos los
    #    dias de inasistencia y de licencia del periodo). Por esto,
    #    Inasistencia y Licencia ya NO se restan de nuevo como
    #    descuentos aparte del liquido (se evita el doble descuento).
    cursor.execute(
        """SELECT monto_proporcional, dias_trabajados, motivo,
                  colacion_proporcional, locomocion_proporcional
           FROM calculo_proporcional
           WHERE trabajador_id = %s AND periodo = %s
           ORDER BY fecha_registro DESC LIMIT 1""",
        (trabajador_id, periodo)
    )
    prop_row = cursor.fetchone()

    cursor.execute(
        "SELECT COALESCE(SUM(dias_evento), 0) FROM descuento WHERE trabajador_id = %s AND periodo = %s AND tipo_descuento = 'Inasistencia'",
        (trabajador_id, periodo)
    )
    dias_inasistencia_total = float(cursor.fetchone()[0])
    cursor.execute(
        "SELECT COALESCE(SUM(fecha_fin - fecha_inicio + 1), 0) FROM licencia_medica WHERE trabajador_id = %s AND periodo = %s",
        (trabajador_id, periodo)
    )
    dias_licencia_total = float(cursor.fetchone()[0])

    dias_base_mes = float(prop_row[1]) if prop_row else 30.0
    dias_a_pagar = max(0.0, dias_base_mes - dias_inasistencia_total - dias_licencia_total)
    hay_ajuste_dias = prop_row is not None or dias_inasistencia_total > 0 or dias_licencia_total > 0

    if hay_ajuste_dias:
        sueldo_base_o_proporcional = round(float(sueldo_base) / 30 * dias_a_pagar)
        es_proporcional = True
        if prop_row:
            detalle_proporcional = f"{dias_a_pagar:g} dias trabajados netos ({prop_row[2]}: {prop_row[1]} dias proporcional, {dias_inasistencia_total:g} inasistencia, {dias_licencia_total:g} licencia)"
        else:
            detalle_proporcional = f"{dias_a_pagar:g} dias trabajados netos (30 dias del mes, {dias_inasistencia_total:g} inasistencia, {dias_licencia_total:g} licencia)"
    else:
        sueldo_base_o_proporcional = float(sueldo_base)
        es_proporcional = False
        detalle_proporcional = None

    # ── 2. Horas extras aprobadas del periodo ───────────────────
    cursor.execute(
        """SELECT cantidad_horas, valor_hora_ordinaria FROM horas_extras
           WHERE trabajador_id = %s AND periodo = %s AND estado = 'Aprobada'""",
        (trabajador_id, periodo)
    )
    horas_rows = cursor.fetchall()
    total_horas_extra = 0
    total_horas_extra_cantidad = 0.0
    cantidad_registros_horas = len(horas_rows)
    for cantidad_horas, valor_hora_ordinaria in horas_rows:
        valor_hora_extra = float(valor_hora_ordinaria) * 1.5
        total_horas_extra += round(valor_hora_extra * float(cantidad_horas))
        total_horas_extra_cantidad += float(cantidad_horas)

    # ── 3. Bonos imponibles del periodo (detalle por tipo) ───────
    cursor.execute(
        "SELECT tipo_bono, monto_clp FROM bono_imponible WHERE trabajador_id = %s AND periodo = %s ORDER BY bono_id",
        (trabajador_id, periodo)
    )
    bonos_imponibles_rows = cursor.fetchall()
    total_bonos_imponibles = sum(int(m) for (_, m) in bonos_imponibles_rows)
    detalle_bonos_imponibles = [
        {"tipo": tipo, "monto": int(monto)} for (tipo, monto) in bonos_imponibles_rows
    ]

    # ── 4. Movilizacion/colacion del periodo: exento (no imponible)
    #    y excedente (la parte que supero el tope, si aplica; con los
    #    valores fijos actuales normalmente no genera excedente).
    #    Igual que el sueldo, se pagan solo por los dias efectivos
    #    (dias_a_pagar), no por el monto fijo mensual completo, ni
    #    por los dias proporcionales brutos sin descontar ausencias.
    #    Prioridad para el monto FIJO base: 1) confirmacion mensual
    #    global de Parametros del Sistema, 2) valor fijo del sistema.
    total_locomocion_detalle = 0
    total_colacion_detalle = 0
    origen_movilizacion_colacion = None
    if hay_ajuste_dias:
        cursor.execute(
            "SELECT monto_movilizacion, monto_colacion FROM confirmacion_movilizacion_colacion WHERE periodo = %s",
            (periodo,)
        )
        confirmacion_row_mc = cursor.fetchone()
        monto_locomocion_base = float(confirmacion_row_mc[0]) if confirmacion_row_mc else MONTO_FIJO_MOVILIZACION
        monto_colacion_base = float(confirmacion_row_mc[1]) if confirmacion_row_mc else MONTO_FIJO_COLACION
        total_excedente_no_imponible = 0
        total_colacion_detalle = round(monto_colacion_base / 30 * dias_a_pagar)
        total_locomocion_detalle = round(monto_locomocion_base / 30 * dias_a_pagar)
        total_monto_exento_no_imponible = total_colacion_detalle + total_locomocion_detalle
        origen_movilizacion_colacion = "proporcional"
    else:
        cursor.execute(
            "SELECT COALESCE(SUM(monto_excedente), 0), COALESCE(SUM(monto_exento), 0) FROM asignacion_no_imponible WHERE trabajador_id = %s AND periodo = %s",
            (trabajador_id, periodo)
        )
        excedente_row = cursor.fetchone()
        total_excedente_no_imponible = int(excedente_row[0])
        total_monto_exento_no_imponible = int(excedente_row[1])

        if total_monto_exento_no_imponible == 0 and total_excedente_no_imponible == 0:
            # No hay registro individual para este trabajador: revisa si
            # el periodo completo ya fue confirmado en Parametros del
            # Sistema, y si es asi, aplica los montos fijos solo.
            cursor.execute(
                "SELECT monto_movilizacion, monto_colacion FROM confirmacion_movilizacion_colacion WHERE periodo = %s",
                (periodo,)
            )
            confirmacion_row = cursor.fetchone()
            if confirmacion_row:
                total_locomocion_detalle = int(confirmacion_row[0])
                total_colacion_detalle = int(confirmacion_row[1])
                total_monto_exento_no_imponible = total_colacion_detalle + total_locomocion_detalle
                origen_movilizacion_colacion = "confirmacion_mensual"
        else:
            # Registro individual: no separa cuanto es colacion vs
            # locomocion (queda como un solo total exento histórico).
            origen_movilizacion_colacion = "individual"

    # ── 5. Bonos/incentivos condicionales aplicados (cumple_condicion=TRUE) ──
    # Solo se suman al total imponible los que la regla clasifico como
    # 'Imponible'. Los 'No imponible' se muestran aparte, informativos,
    # sin afectar el total imponible ni las cotizaciones.
    cursor.execute(
        """SELECT COALESCE(SUM(ab.monto_aplicado), 0)
           FROM aplicacion_bono_regla ab
           JOIN bono_regla br ON br.bono_id = ab.bono_id
           WHERE ab.trabajador_id = %s AND ab.periodo = %s
             AND ab.cumple_condicion = TRUE AND br.clasificacion = 'Imponible'""",
        (trabajador_id, periodo)
    )
    total_bonos_condicionales_imponibles = int(cursor.fetchone()[0])

    cursor.execute(
        """SELECT COALESCE(SUM(ab.monto_aplicado), 0)
           FROM aplicacion_bono_regla ab
           JOIN bono_regla br ON br.bono_id = ab.bono_id
           WHERE ab.trabajador_id = %s AND ab.periodo = %s
             AND ab.cumple_condicion = TRUE AND br.clasificacion = 'No imponible'""",
        (trabajador_id, periodo)
    )
    total_bonos_condicionales_no_imponibles = int(cursor.fetchone()[0])

    # ── 6. Bonos excepcionales del periodo (imponibles y no imponibles) ──
    cursor.execute(
        "SELECT concepto, monto_clp, clasificacion FROM bono_excepcional WHERE trabajador_id = %s AND periodo = %s ORDER BY bono_id",
        (trabajador_id, periodo)
    )
    bono_excepcional_rows = cursor.fetchall()
    total_bono_excepcional_imponible = sum(
        int(m) for (_, m, c) in bono_excepcional_rows if c == 'Imponible'
    )
    total_bono_excepcional_no_imponible = sum(
        int(m) for (_, m, c) in bono_excepcional_rows if c == 'No imponible'
    )
    detalle_bono_excepcional = [
        {"concepto": concepto, "monto": int(monto), "clasificacion": clasificacion}
        for (concepto, monto, clasificacion) in bono_excepcional_rows
    ]

    cursor.close(); conn.close()

    # ── Excepcion 2: ningun haber imponible puede ser negativo ──────
    _componentes_a_validar = [
        (total_horas_extra, "Horas Extras"),
        (total_bonos_imponibles, "Bonos Imponibles"),
        (total_excedente_no_imponible, "Excedente de Movilización/Colación"),
        (total_monto_exento_no_imponible, "Movilización/Colación"),
        (total_bonos_condicionales_imponibles, "Bonos Condicionales (imponibles)"),
        (total_bonos_condicionales_no_imponibles, "Bonos Condicionales (no imponibles)"),
        (total_bono_excepcional_imponible, "Bono Excepcional (imponible)"),
        (total_bono_excepcional_no_imponible, "Bono Excepcional (no imponible)"),
    ]
    for valor, etiqueta in _componentes_a_validar:
        if valor < 0:
            return {"success": False, "mensaje": f"Error en el monto de {etiqueta}. Consulta con el administrador."}

    # ── 7. Gratificacion legal (si la modalidad es Proporcional y hay
    #    IMM cargado); es imponible por ley, se suma al total imponible
    #    sin generar circularidad (su propia base NO usa total_imponible)
    resultado_gratificacion = _gratificacion_para_total_imponible(persona_id, periodo)

    if not resultado_gratificacion["success"]:
        return {"success": False, "mensaje": resultado_gratificacion["mensaje"]}

    total_gratificacion = resultado_gratificacion["monto"]

    if total_gratificacion < 0:
        return {"success": False, "mensaje": "Error en el monto de Gratificación Legal. Consulta con el administrador."}

    # ── Descuento de atraso: se resta DIRECTO de la base, no solo al
    #    final del liquido — reduce Total Haberes, Total Imponible
    #    AFP/Salud y Total Imponible AFC, tal como corresponde.
    conn2 = get_connection()
    cursor2 = conn2.cursor()
    cursor2.execute(
        "SELECT COALESCE(SUM(monto_clp), 0), COALESCE(SUM(dias_evento), 0) FROM descuento WHERE trabajador_id = %s AND periodo = %s AND tipo_descuento = 'Retraso'",
        (trabajador_id, periodo)
    )
    _row_atraso = cursor2.fetchone()
    total_descuento_atraso = round(float(_row_atraso[0]))
    total_horas_atraso = float(_row_atraso[1])
    cursor2.close(); conn2.close()

    total_imponible = round(
        sueldo_base_o_proporcional
        + total_horas_extra
        + total_bonos_imponibles
        + total_excedente_no_imponible
        + total_bonos_condicionales_imponibles
        + total_bono_excepcional_imponible
        + total_gratificacion
        - total_descuento_atraso
    )

    # Bonos NO imponibles: movilizacion/colacion exenta + condicionales
    # y excepcionales clasificados como no imponibles. Junto con el
    # total_imponible, arman el TOTAL HABERES real (bruto completo).
    total_bonos_no_imponibles = (
        total_monto_exento_no_imponible
        + total_bonos_condicionales_no_imponibles
        + total_bono_excepcional_no_imponible
    )
    total_haberes = round(total_imponible + total_bonos_no_imponibles)

    _resultado_final = {
        "success": True,
        "trabajador_id": trabajador_id,
        "nombre": nombre,
        "rut": rut,
        "tipo_contrato": tipo_contrato,
        "periodo": periodo,
        "desglose": {
            "sueldo_base_original":      round(float(sueldo_base)),
            "sueldo_base_considerado":   round(sueldo_base_o_proporcional),
            "es_proporcional":           es_proporcional,
            "detalle_proporcional":      detalle_proporcional,
            "horas_extra_total":         total_horas_extra,
            "horas_extra_cantidad":      cantidad_registros_horas,
            "horas_extra_horas":         total_horas_extra_cantidad,
            "bonos_imponibles_total":    total_bonos_imponibles,
            "detalle_bonos_imponibles":  detalle_bonos_imponibles,
            "excedente_no_imponible_total": total_excedente_no_imponible,
            "monto_exento_no_imponible_total": total_monto_exento_no_imponible,
            "colacion_total":            total_colacion_detalle,
            "locomocion_total":          total_locomocion_detalle,
            "origen_movilizacion_colacion": origen_movilizacion_colacion,
            "bonos_no_imponibles_total": total_bonos_no_imponibles,
            "bonos_condicionales_imponibles_total":    total_bonos_condicionales_imponibles,
            "bonos_condicionales_no_imponibles_total": total_bonos_condicionales_no_imponibles,
            "bono_excepcional_imponible_total":    total_bono_excepcional_imponible,
            "bono_excepcional_no_imponible_total": total_bono_excepcional_no_imponible,
            "detalle_bono_excepcional":  detalle_bono_excepcional,
            "gratificacion_total": total_gratificacion,
            "descuento_atraso_total": total_descuento_atraso,
            "horas_atraso_total": total_horas_atraso,
            "dias_base_mes": dias_base_mes,
            "dias_inasistencia_total": dias_inasistencia_total,
            "dias_licencia_total": dias_licencia_total,
            "dias_proporcional": float(prop_row[1]) if prop_row else None,
            "dias_a_pagar": dias_a_pagar,
        },
        "total_imponible": total_imponible,
        "total_haberes": total_haberes,
    }
    _cache_total_imponible[_clave_cache] = _resultado_final
    return _resultado_final


@app.get("/admin/total-imponible")
def calcular_total_imponible(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        return calcular_total_imponible_interno(persona_id, periodo)
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


def _calcular_bases_topadas(persona_id: int, periodo: str) -> dict:
    """
    Calcula las 2 bases imponibles "con tope" que exige la ley:
      - Total Imponible para AFP y Salud: tope 90 UF
      - Total Imponible para AFC (Seguro de Cesantia): tope 135,2 UF
    Ambas parten de la MISMA base sin tope (sueldo + horas extras +
    bonos imponibles + bono excepcional imponible + gratificacion),
    y cada una se limita a su propio tope si lo supera.

    Requiere que el admin haya cargado los 3 valores de UF del
    periodo (Valor UF, Tope AFP/Salud, Tope AFC) de antemano.
    """
    base = calcular_total_imponible_interno(persona_id, periodo)
    if not base.get("success"):
        return base

    valores_uf = obtener_valores_uf_periodo(periodo)
    if valores_uf is None:
        return {
            "success": False,
            "mensaje": "Es necesario ingresar los valores de UF (Valor UF, Tope AFP/Salud y Tope AFC) del periodo antes de continuar"
        }

    base_sin_tope = base["total_imponible"]
    tope_afp_salud = valores_uf["tope_afp_salud"]
    tope_afc = valores_uf["tope_afc"]

    total_imponible_afp_salud = min(base_sin_tope, tope_afp_salud)
    total_imponible_afc = min(base_sin_tope, tope_afc)

    return {
        "success": True,
        "trabajador_id": base["trabajador_id"],
        "nombre": base["nombre"],
        "rut": base["rut"],
        "tipo_contrato": base["tipo_contrato"],
        "periodo": periodo,
        "desglose": base["desglose"],
        "base_sin_tope": base_sin_tope,
        "valor_uf": valores_uf["valor_uf"],
        "tope_afp_salud": tope_afp_salud,
        "tope_afc": tope_afc,
        "total_imponible_afp_salud": round(total_imponible_afp_salud),
        "total_imponible_afc": round(total_imponible_afc),
        "se_aplico_tope_afp_salud": base_sin_tope > tope_afp_salud,
        "se_aplico_tope_afc": base_sin_tope > tope_afc,
    }


@app.get("/admin/total-imponible-topado")
def ver_total_imponible_topado(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        return _calcular_bases_topadas(persona_id, periodo)
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# AFC — SEGURO DE CESANTIA
# ══════════════════════════════════════════════════════════════

@app.get("/admin/calculo-afc")
def calcular_afc(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    """
    Calcula la cotizacion al Seguro de Cesantia (AFC) segun el tipo
    de contrato, sobre el TOTAL IMPONIBLE PARA AFC (con tope de 135,2 UF):
      - Indefinido: 0.6% trabajador + 2.4% empleador
      - Plazo Fijo / Por obra: 3.0% empleador, sin descuento al trabajador
    """
    try:
        verificar_rol(payload, ["admin"])

        bases = _calcular_bases_topadas(persona_id, periodo)
        if not bases.get("success"):
            return bases

        tipo_contrato = (bases.get("tipo_contrato") or "").strip()
        tipo_contrato_normalizado = tipo_contrato.lower()
        total_imponible_afc = bases["total_imponible_afc"]

        if tipo_contrato_normalizado == "indefinido":
            porcentaje_trabajador = 0.6
            porcentaje_empleador = 2.4
        elif tipo_contrato_normalizado in ("plazo fijo", "por obra"):
            porcentaje_trabajador = 0.0
            porcentaje_empleador = 3.0
        else:
            return {
                "success": False,
                "mensaje": "Debe completar el tipo de contrato del trabajador antes de calcular el Seguro de Cesantía (AFC)."
            }

        descuento_trabajador = round(total_imponible_afc * porcentaje_trabajador / 100)
        aporte_empleador = round(total_imponible_afc * porcentaje_empleador / 100)

        return {
            "success": True,
            "nombre": bases["nombre"],
            "rut": bases["rut"],
            "periodo": periodo,
            "tipo_contrato": tipo_contrato,
            "total_imponible": bases["base_sin_tope"],
            "total_imponible_afc": total_imponible_afc,
            "tope_afc": bases["tope_afc"],
            "se_aplico_tope_afc": bases["se_aplico_tope_afc"],
            "porcentaje_trabajador": porcentaje_trabajador,
            "porcentaje_empleador": porcentaje_empleador,
            "descuento_trabajador": descuento_trabajador,
            "aporte_empleador": aporte_empleador,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# AFP Y SALUD
# ══════════════════════════════════════════════════════════════

# ── ADMIN: VER/ACTUALIZAR TASAS AFP ───────────────────────────
@app.get("/admin/config-tasas-afp")
def ver_tasas_afp(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT nombre_afp, tasa_total_porcentaje, fecha_modificacion FROM config_tasas_afp ORDER BY nombre_afp"
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "tasas": [
                {
                    "nombre_afp": r[0],
                    "tasa_total_porcentaje": float(r[1]),
                    "fecha_modificacion": r[2].strftime("%d/%m/%Y %H:%M") if r[2] else "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.put("/admin/config-tasas-afp")
def actualizar_tasa_afp(data: TasaAfpRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        if data.tasa_total_porcentaje <= 0:
            return {"success": False, "mensaje": "La tasa debe ser un valor positivo mayor a 0"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """UPDATE config_tasas_afp
               SET tasa_total_porcentaje = %s, fecha_modificacion = NOW(), modificado_por = %s
               WHERE nombre_afp = %s""",
            (data.tasa_total_porcentaje, administrador_id, data.nombre_afp)
        )
        if cursor.rowcount == 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"AFP '{data.nombre_afp}' no encontrada en la configuracion"}
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Tasa de {data.nombre_afp} actualizada correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: VER/ACTUALIZAR TASAS SALUD ─────────────────────────
@app.get("/admin/config-tasas-salud")
def ver_tasas_salud(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT institucion, tasa_porcentaje, fecha_modificacion FROM config_tasas_salud ORDER BY institucion"
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "tasas": [
                {
                    "institucion": r[0],
                    "tasa_porcentaje": float(r[1]),
                    "fecha_modificacion": r[2].strftime("%d/%m/%Y %H:%M") if r[2] else "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.put("/admin/config-tasas-salud")
def actualizar_tasa_salud(data: TasaSaludRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        if data.tasa_porcentaje <= 0:
            return {"success": False, "mensaje": "La tasa debe ser un valor positivo mayor a 0"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """UPDATE config_tasas_salud
               SET tasa_porcentaje = %s, fecha_modificacion = NOW(), modificado_por = %s
               WHERE institucion = %s""",
            (data.tasa_porcentaje, administrador_id, data.institucion)
        )
        if cursor.rowcount == 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"Institucion '{data.institucion}' no encontrada en la configuracion"}
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Tasa de {data.institucion} actualizada correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: CALCULO DE DESCUENTO AFP + SALUD ───────────────────
@app.get("/admin/calculo-afp-salud")
def calcular_afp_salud(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    """
    Calcula el descuento de AFP y de salud sobre el TOTAL IMPONIBLE
    PARA AFP Y SALUD (con tope de 90 UF), segun la AFP y la
    institucion de salud registradas en el contrato activo.
    """
    try:
        verificar_rol(payload, ["admin"])

        bases = _calcular_bases_topadas(persona_id, periodo)
        if not bases.get("success"):
            return bases

        total_imponible_afp_salud = bases["total_imponible_afp_salud"]

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT c.tipo_afp, c.institucion_salud
               FROM contrato c WHERE c.trabajador_id = %s AND c.estado = 'activo'""",
            (bases["trabajador_id"],)
        )
        contrato_row = cursor.fetchone()
        if not contrato_row:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El trabajador no tiene un contrato activo registrado"}
        tipo_afp, institucion_salud = contrato_row

        cursor.execute(
            "SELECT tasa_total_porcentaje FROM config_tasas_afp WHERE nombre_afp = %s",
            (tipo_afp,)
        )
        afp_row = cursor.fetchone()
        if not afp_row:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"No hay tasa configurada para '{tipo_afp}'. Ve a Tasas AFP y agrégala."}
        tasa_afp = float(afp_row[0])

        cursor.execute(
            "SELECT tasa_porcentaje FROM config_tasas_salud WHERE institucion = %s",
            (institucion_salud,)
        )
        salud_row = cursor.fetchone()
        if not salud_row:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"No hay tasa configurada para '{institucion_salud}'. Ve a Tasas Salud y agrégala."}
        tasa_salud = float(salud_row[0])

        cursor.close(); conn.close()

        descuento_afp = round(total_imponible_afp_salud * tasa_afp / 100)
        descuento_salud = round(total_imponible_afp_salud * tasa_salud / 100)

        return {
            "success": True,
            "nombre": bases["nombre"],
            "rut": bases["rut"],
            "periodo": periodo,
            "total_imponible": bases["base_sin_tope"],
            "total_imponible_afp_salud": total_imponible_afp_salud,
            "tope_afp_salud": bases["tope_afp_salud"],
            "se_aplico_tope_afp_salud": bases["se_aplico_tope_afp_salud"],
            "tipo_afp": tipo_afp,
            "tasa_afp": tasa_afp,
            "descuento_afp": descuento_afp,
            "institucion_salud": institucion_salud,
            "tasa_salud": tasa_salud,
            "descuento_salud": descuento_salud,
            "total_descuentos_previsionales": descuento_afp + descuento_salud,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# IMPUESTO UNICO DE SEGUNDA CATEGORIA
# ══════════════════════════════════════════════════════════════

@app.get("/admin/config-tramos-impuesto")
def ver_tramos_impuesto(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT tramo_numero, desde_utm, hasta_utm, factor, rebaja_utm
               FROM tabla_tramos_impuesto ORDER BY tramo_numero"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "tramos": [
                {
                    "tramo_numero": r[0],
                    "desde_utm": float(r[1]),
                    "hasta_utm": float(r[2]) if r[2] is not None else None,
                    "factor": float(r[3]),
                    "rebaja_utm": float(r[4]),
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.put("/admin/config-tramos-impuesto")
def actualizar_tramo_impuesto(data: ActualizarTramoRequest, payload: dict = Depends(verificar_token)):
    """
    Actualiza un tramo de la tabla del SII, celda por celda (cada
    tramo es independiente; editar uno NO actualiza los demas, asi
    que el admin es responsable de que no queden huecos o
    superposiciones entre tramos consecutivos).
    """
    try:
        verificar_rol(payload, ["admin"])

        if data.desde_utm < 0 or data.factor < 0 or data.rebaja_utm < 0:
            return {"success": False, "mensaje": "Los valores no pueden ser negativos"}
        if data.hasta_utm is not None and data.hasta_utm <= data.desde_utm:
            return {"success": False, "mensaje": "El límite 'hasta' debe ser mayor que el límite 'desde'"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """UPDATE tabla_tramos_impuesto
               SET desde_utm = %s, hasta_utm = %s, factor = %s, rebaja_utm = %s,
                   fecha_modificacion = NOW(), modificado_por = %s
               WHERE tramo_numero = %s""",
            (data.desde_utm, data.hasta_utm, data.factor, data.rebaja_utm, administrador_id, data.tramo_numero)
        )
        if cursor.rowcount == 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"Tramo {data.tramo_numero} no encontrado"}

        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Tramo {data.tramo_numero} actualizado correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


def _calcular_total_tributable(persona_id: int, periodo: str, payload: dict) -> dict:
    """
    TOTAL TRIBUTABLE = Base sin tope (sueldo + horas extras + bonos
    imponibles + bono excepcional imponible + gratificacion)
    - Descuento AFP - Descuento Salud - Descuento AFC (trabajador).

    No requiere la UTM (esa solo hace falta un paso despues, para
    convertir esta base a UTM y ubicar el tramo del impuesto).
    """
    resultado_afp_salud = calcular_afp_salud(persona_id, periodo, payload)
    if not resultado_afp_salud.get("success"):
        return resultado_afp_salud

    resultado_afc = calcular_afc(persona_id, periodo, payload)
    if not resultado_afc.get("success"):
        return resultado_afc

    total_imponible = resultado_afp_salud["total_imponible"]
    descuento_afp = resultado_afp_salud["descuento_afp"]
    descuento_salud = resultado_afp_salud["descuento_salud"]
    descuento_afc_trabajador = resultado_afc["descuento_trabajador"]

    base_tributable = total_imponible - descuento_afp - descuento_salud - descuento_afc_trabajador
    if base_tributable < 0:
        base_tributable = 0

    return {
        "success": True,
        "nombre": resultado_afp_salud["nombre"],
        "rut": resultado_afp_salud["rut"],
        "periodo": periodo,
        "total_imponible": total_imponible,
        "descuento_afp": descuento_afp,
        "descuento_salud": descuento_salud,
        "descuento_afc_trabajador": descuento_afc_trabajador,
        "total_tributable": round(base_tributable),
    }


@app.get("/admin/total-tributable")
def ver_total_tributable(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        return _calcular_total_tributable(persona_id, periodo, payload)
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/calculo-impuesto-unico")
def calcular_impuesto_unico(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    """
    Calcula el Impuesto Unico de Segunda Categoria:
      1. Total Tributable = Total Imponible - AFP - Salud - AFC trabajador
         (los descuentos previsionales son deducibles antes del impuesto)
      2. Total Tributable expresado en UTM (4 decimales), solo para
         ubicar el tramo correspondiente en la tabla del SII
      3. Impuesto (CLP) = base_tributable * factor - (rebaja_utm * valor_utm)
         -- calculo directo en pesos, sin redondear la base a UTM antes
         de aplicar el factor (evita diferencias de redondeo frente a
         un calculo manual directo en pesos)
    """
    try:
        verificar_rol(payload, ["admin"])

        valor_utm = obtener_valor_utm_periodo(periodo)
        if valor_utm is None:
            return {
                "success": False,
                "mensaje": "Es necesario ingresar el valor de la UTM del periodo antes de calcular el impuesto unico"
            }

        resultado_tributable = _calcular_total_tributable(persona_id, periodo, payload)
        if not resultado_tributable.get("success"):
            return resultado_tributable

        total_imponible = resultado_tributable["total_imponible"]
        descuento_afp = resultado_tributable["descuento_afp"]
        descuento_salud = resultado_tributable["descuento_salud"]
        descuento_afc_trabajador = resultado_tributable["descuento_afc_trabajador"]
        base_tributable = resultado_tributable["total_tributable"]

        base_tributable_utm = round(base_tributable / valor_utm, 4)

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT tramo_numero, desde_utm, hasta_utm, factor, rebaja_utm
               FROM tabla_tramos_impuesto
               WHERE desde_utm <= %s AND (hasta_utm IS NULL OR %s < hasta_utm)
               ORDER BY tramo_numero LIMIT 1""",
            (base_tributable_utm, base_tributable_utm)
        )
        tramo_row = cursor.fetchone()
        cursor.close(); conn.close()

        if not tramo_row:
            return {"success": False, "mensaje": "No se encontro un tramo aplicable para la base tributable calculada"}

        tramo_numero, desde_utm, hasta_utm, factor, rebaja_utm = tramo_row
        factor = float(factor)
        rebaja_utm = float(rebaja_utm)

        # Calculo directo en pesos (sin redondear la base a UTM antes
        # de aplicar el factor): base_tributable * factor - rebaja en CLP.
        rebaja_clp = rebaja_utm * valor_utm
        impuesto_clp = round((base_tributable * factor) - rebaja_clp)
        if impuesto_clp < 0:
            impuesto_clp = 0
        impuesto_utm = round(impuesto_clp / valor_utm, 4)

        return {
            "success": True,
            "nombre": resultado_tributable["nombre"],
            "rut": resultado_tributable["rut"],
            "periodo": periodo,
            "valor_utm": valor_utm,
            "total_imponible": total_imponible,
            "descuento_afp": descuento_afp,
            "descuento_salud": descuento_salud,
            "descuento_afc_trabajador": descuento_afc_trabajador,
            "base_tributable": round(base_tributable),
            "base_tributable_utm": base_tributable_utm,
            "tramo_numero": tramo_numero,
            "desde_utm": float(desde_utm),
            "hasta_utm": float(hasta_utm) if hasta_utm is not None else None,
            "factor": factor,
            "rebaja_utm": rebaja_utm,
            "impuesto_utm": impuesto_utm,
            "impuesto_unico": impuesto_clp,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# GRATIFICACION LEGAL (Art. 47 anual / Art. 50 proporcional mensual)
# ══════════════════════════════════════════════════════════════

def obtener_valor_imm_periodo(periodo: str):
    """Retorna el valor IMM (float) cargado para el periodo MM/AAAA, o None."""
    (mes_anio, error) = validar_periodo_mm_aaaa(periodo)
    if error:
        return None
    mes, anio = mes_anio
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT valor_clp FROM config_valor_imm WHERE mes = %s AND anio = %s", (mes, anio))
    row = cursor.fetchone()
    cursor.close(); conn.close()
    return float(row[0]) if row else None


# ── ADMIN: VALOR IMM MENSUAL ───────────────────────────────────
@app.post("/admin/valor-imm")
def registrar_valor_imm(data: ValorImmRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        if data.valor_clp <= 0:
            return {"success": False, "mensaje": "El valor IMM debe ser un entero positivo mayor a 0"}

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        mes, anio = data.periodo.split("/")
        cursor.execute(
            """INSERT INTO config_valor_imm (valor_clp, mes, anio, ingresado_por)
               VALUES (%s, %s, %s, %s)
               ON CONFLICT (mes, anio) DO UPDATE
               SET valor_clp = EXCLUDED.valor_clp, ingresado_por = EXCLUDED.ingresado_por, fecha_ingreso = NOW()
               RETURNING imm_id""",
            (data.valor_clp, int(mes), int(anio), administrador_id)
        )
        imm_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Valor IMM registrado correctamente", "imm_id": imm_id}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/valor-imm")
def listar_valor_imm(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT i.valor_clp, i.mes, i.anio, i.fecha_ingreso,
                      p.primer_nombre || ' ' || p.apellido_paterno AS nombre_admin
               FROM config_valor_imm i
               LEFT JOIN administrador a ON a.administrador_id = i.ingresado_por
               LEFT JOIN persona p ON p.persona_id = a.persona_id
               ORDER BY i.anio DESC, i.mes DESC"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "valores": [
                {
                    "valor_clp": int(r[0]),
                    "periodo": f"{str(r[1]).zfill(2)}/{r[2]}",
                    "fecha_ingreso": r[3].strftime("%d/%m/%Y %H:%M") if r[3] else "—",
                    "nombre_admin": r[4] or "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


def obtener_valores_uf_periodo(periodo: str):
    """
    Retorna {"valor_uf", "tope_afp_salud", "tope_afc"} cargados para
    el periodo MM/AAAA, o None si no se ha cargado nada aun.
    """
    (mes_anio, error) = validar_periodo_mm_aaaa(periodo)
    if error:
        return None
    mes, anio = mes_anio
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT valor_uf, tope_afp_salud, tope_afc FROM config_valor_uf WHERE mes = %s AND anio = %s",
        (mes, anio)
    )
    row = cursor.fetchone()
    cursor.close(); conn.close()
    if not row:
        return None
    return {"valor_uf": float(row[0]), "tope_afp_salud": float(row[1]), "tope_afc": float(row[2])}


# ── ADMIN: VALOR UF Y TOPES (AFP/Salud a 90 UF, AFC a 135,2 UF) ─
@app.post("/admin/valor-uf")
def registrar_valor_uf(data: ValorUfRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        if data.valor_uf <= 0 or data.tope_afp_salud <= 0 or data.tope_afc <= 0:
            return {"success": False, "mensaje": "Los 3 valores deben ser positivos y mayores a 0"}

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        mes, anio = data.periodo.split("/")
        cursor.execute(
            """INSERT INTO config_valor_uf (valor_uf, tope_afp_salud, tope_afc, mes, anio, ingresado_por)
               VALUES (%s, %s, %s, %s, %s, %s)
               ON CONFLICT (mes, anio) DO UPDATE
               SET valor_uf = EXCLUDED.valor_uf, tope_afp_salud = EXCLUDED.tope_afp_salud,
                   tope_afc = EXCLUDED.tope_afc, ingresado_por = EXCLUDED.ingresado_por, fecha_ingreso = NOW()
               RETURNING uf_id""",
            (data.valor_uf, data.tope_afp_salud, data.tope_afc, int(mes), int(anio), administrador_id)
        )
        uf_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Valores de UF registrados correctamente", "uf_id": uf_id}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/valor-uf")
def listar_valor_uf(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT u.valor_uf, u.tope_afp_salud, u.tope_afc, u.mes, u.anio, u.fecha_ingreso,
                      p.primer_nombre || ' ' || p.apellido_paterno AS nombre_admin
               FROM config_valor_uf u
               LEFT JOIN administrador a ON a.administrador_id = u.ingresado_por
               LEFT JOIN persona p ON p.persona_id = a.persona_id
               ORDER BY u.anio DESC, u.mes DESC"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "valores": [
                {
                    "valor_uf": float(r[0]),
                    "tope_afp_salud": float(r[1]),
                    "tope_afc": float(r[2]),
                    "periodo": f"{str(r[3]).zfill(2)}/{r[4]}",
                    "fecha_ingreso": r[5].strftime("%d/%m/%Y %H:%M") if r[5] else "—",
                    "nombre_admin": r[6] or "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# LIQUIDACION HONORARIOS
# ══════════════════════════════════════════════════════════════

@app.post("/admin/config-retencion-honorario")
def registrar_retencion_honorario(data: RetencionHonorarioRequest, payload: dict = Depends(verificar_token)):
    """
    % de retencion de impuesto para honorarios — se actualiza UNA
    VEZ AL AÑO (no cada mes). Queda un registro historico completo;
    nunca se sobreescribe el valor de un año anterior.
    """
    try:
        verificar_rol(payload, ["admin"])
        if data.tasa_retencion <= 0 or data.tasa_retencion > 100:
            return {"success": False, "mensaje": "La tasa de retención debe ser un porcentaje válido entre 0 y 100"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO config_retencion_honorario (tasa_retencion, anio, ingresado_por)
               VALUES (%s, %s, %s)
               ON CONFLICT (anio) DO UPDATE
               SET tasa_retencion = EXCLUDED.tasa_retencion, ingresado_por = EXCLUDED.ingresado_por, fecha_ingreso = NOW()
               RETURNING retencion_id""",
            (data.tasa_retencion, data.anio, administrador_id)
        )
        retencion_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()
        return {
            "success": True,
            "mensaje": f"Tasa de retención para el año {data.anio} guardada correctamente. Recuerda que este valor debe actualizarse cada año.",
            "retencion_id": retencion_id,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/config-retencion-honorario")
def listar_retencion_honorario(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT r.tasa_retencion, r.anio, r.fecha_ingreso,
                      p.primer_nombre || ' ' || p.apellido_paterno AS nombre_admin
               FROM config_retencion_honorario r
               LEFT JOIN administrador a ON a.administrador_id = r.ingresado_por
               LEFT JOIN persona p ON p.persona_id = a.persona_id
               ORDER BY r.anio DESC"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "valores": [
                {
                    "tasa_retencion": float(r[0]),
                    "anio": r[1],
                    "fecha_ingreso": r[2].strftime("%d/%m/%Y %H:%M") if r[2] else "—",
                    "nombre_admin": r[3] or "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.post("/admin/liquidacion-honorario")
def calcular_liquidacion_honorario(data: LiquidacionHonorarioRequest, payload: dict = Depends(verificar_token)):
    """
    Honorario Líquido = Honorario Bruto - (Honorario Bruto x % de
    retención del año vigente). No lleva AFP, Salud, AFC ni
    Gratificación — es el calculo simplificado de boleta de honorarios.
    """
    try:
        verificar_rol(payload, ["admin"])
        if data.honorario_bruto <= 0:
            return {"success": False, "mensaje": "El honorario bruto debe ser un monto mayor a 0"}
        if not data.descripcion_trabajo or len(data.descripcion_trabajo.strip()) < 3:
            return {"success": False, "mensaje": "Describe el tipo de trabajo realizado"}

        (mes_anio, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}
        _, anio_periodo = mes_anio

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (data.persona_id,))
        t = cursor.fetchone()
        if not t:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = t[0]

        cursor.execute("SELECT primer_nombre || ' ' || apellido_paterno, rut FROM persona WHERE persona_id = %s", (data.persona_id,))
        nombre, rut = cursor.fetchone()

        cursor.execute("SELECT tasa_retencion FROM config_retencion_honorario WHERE anio = %s", (anio_periodo,))
        tasa_row = cursor.fetchone()
        if not tasa_row:
            cursor.close(); conn.close()
            return {
                "success": False,
                "mensaje": f"No hay una tasa de retención cargada para el año {anio_periodo}. Ve a Parámetros y cárgala antes de continuar."
            }
        tasa_retencion = float(tasa_row[0])

        honorario_bruto = round(data.honorario_bruto)
        monto_retencion = round(honorario_bruto * tasa_retencion / 100)
        honorario_liquido = honorario_bruto - monto_retencion

        # El numero de cuenta bancaria es un dato sensible y NO se
        # guarda en la base de datos -- solo se usa como dato de paso
        # para el calculo y se vuelve a pedir directo al momento de
        # descargar el PDF (ver boleta_honorarios_pdf), sin persistir.
        numero_cuenta = data.numero_cuenta if data.numero_cuenta and data.numero_cuenta.strip() else "123456889"

        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO liquidacion_honorario
               (trabajador_id, periodo, numero_boleta, fecha_emision, periodo_prestacion, descripcion_trabajo, honorario_bruto,
                tasa_retencion_aplicada, registrado_por)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
               RETURNING liquidacion_honorario_id""",
            (trabajador_id, data.periodo, data.numero_boleta, data.fecha_emision, data.periodo_prestacion, data.descripcion_trabajo.strip(), honorario_bruto,
             tasa_retencion, administrador_id)
        )
        liquidacion_honorario_id = cursor.fetchone()[0]

        # Normalizacion real: monto_retencion y honorario_liquido son
        # valores calculados (dependen de honorario_bruto y
        # tasa_retencion_aplicada) — se guardan en su propia tabla,
        # relacion 1:1 con Liquidacion_Honorario.
        cursor.execute(
            """INSERT INTO calculo_monto_honorario
               (monto_retencion, honorario_liquido, liquidacion_honorario_id)
               VALUES (%s, %s, %s)""",
            (monto_retencion, honorario_liquido, liquidacion_honorario_id)
        )

        conn.commit(); cursor.close(); conn.close()

        return {
            "success": True,
            "liquidacion_honorario_id": liquidacion_honorario_id,
            "numero_boleta": data.numero_boleta,
            "numero_cuenta": numero_cuenta,
            "nombre": nombre,
            "rut": rut,
            "periodo": data.periodo,
            "descripcion_trabajo": data.descripcion_trabajo.strip(),
            "honorario_bruto": honorario_bruto,
            "tasa_retencion_aplicada": tasa_retencion,
            "monto_retencion": monto_retencion,
            "honorario_liquido": honorario_liquido,
            "honorario_liquido_palabras": numero_a_palabras_clp(honorario_liquido),
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/boleta-honorarios/{liquidacion_honorario_id}")
def boleta_honorarios_pdf(liquidacion_honorario_id: int, numero_cuenta: str = None, payload: dict = Depends(verificar_token)):
    """
    Genera un PDF con formato de boleta de honorarios (referencial,
    no reemplaza la boleta electronica real del SII), con los datos
    ya calculados y guardados de esta liquidacion de honorario.

    El numero de cuenta bancaria NO se guarda en la base de datos por
    ser un dato sensible -- se recibe como parametro de la propia
    peticion (query string), tomado directo del campo de texto que
    sigue en pantalla despues de calcular, y solo se usa para armar
    el PDF de esta descarga puntual.
    """
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT lh.liquidacion_honorario_id, lh.periodo, lh.numero_boleta, lh.fecha_emision, lh.periodo_prestacion, lh.descripcion_trabajo,
                      lh.honorario_bruto, lh.tasa_retencion_aplicada, lh.fecha_registro,
                      cmh.monto_retencion, cmh.honorario_liquido,
                      p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre,
                      p.rut
               FROM liquidacion_honorario lh
               JOIN calculo_monto_honorario cmh ON cmh.liquidacion_honorario_id = lh.liquidacion_honorario_id
               JOIN trabajador t ON t.trabajador_id = lh.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               WHERE lh.liquidacion_honorario_id = %s""",
            (liquidacion_honorario_id,)
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()
        if not r:
            return {"success": False, "mensaje": "Liquidación de honorario no encontrada"}

        (_id, periodo, numero_boleta, fecha_emision, periodo_prestacion, descripcion, honorario_bruto, tasa_retencion, fecha_registro,
         monto_retencion, honorario_liquido, nombre, rut) = r

        buffer = io.BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=letter,
                                topMargin=0.7*inch, bottomMargin=0.7*inch,
                                leftMargin=0.8*inch, rightMargin=0.8*inch)
        styles = getSampleStyleSheet()
        story = []

        story.append(Paragraph("Registro Honorario", styles['Title']))
        story.append(Spacer(1, 18))

        estilo_etiqueta = ParagraphStyle(
            'EtiquetaTabla', parent=styles['Normal'],
            fontName='Helvetica-Bold', fontSize=10, leading=13,
        )
        estilo_valor = ParagraphStyle(
            'ValorTabla', parent=styles['Normal'],
            fontName='Helvetica', fontSize=10, leading=13,
        )

        def _fila(etiqueta, valor):
            return [Paragraph(etiqueta, estilo_etiqueta), Paragraph(str(valor), estilo_valor)]

        datos_prestador = [
            _fila("Prestador de servicios (emisor)", nombre or "—"),
            _fila("RUT", rut or "—"),
            _fila("Período", periodo),
            _fila("Fecha de emisión", fecha_emision.strftime("%d/%m/%Y") if fecha_emision else (fecha_registro.strftime("%d/%m/%Y") if fecha_registro else "—")),
            _fila("Detalle del servicio prestado", descripcion or "—"),
            _fila("Numero de boleta", numero_boleta or "—"),
            _fila("Periodo de la prestación del servicio", periodo_prestacion or "—"),
            _fila("Numero de la cuenta bancaria del prestador de servicio", numero_cuenta or "—"),
        ]
        tabla_prestador = Table(datos_prestador, colWidths=[2.5*inch, 3.5*inch])
        tabla_prestador.setStyle(TableStyle([
            ('VALIGN',     (0,0), (-1,-1), 'TOP'),
            ('GRID',       (0,0), (-1,-1), 0.5, colors.HexColor('#E2E8F0')),
            ('PADDING',    (0,0), (-1,-1), 6),
        ]))
        story.append(tabla_prestador)
        story.append(Spacer(1, 14))

        data_tabla = [
            ["Concepto", "Monto"],
            ["Total honorario bruto", f"${honorario_bruto:,} CLP".replace(",", ".")],
            [f"Retención ({tasa_retencion}%)", f"-${monto_retencion:,} CLP".replace(",", ".")],
            ["TOTAL LÍQUIDO", f"${honorario_liquido:,} CLP".replace(",", ".")],
        ]
        tabla = Table(data_tabla, colWidths=[4*inch, 2*inch])
        tabla.setStyle(TableStyle([
            ('BACKGROUND',    (0,0), (-1,0), colors.HexColor('#001E42')),
            ('TEXTCOLOR',     (0,0), (-1,0), colors.white),
            ('FONTNAME',      (0,0), (-1,0), 'Helvetica-Bold'),
            ('FONTNAME',      (0,-1), (-1,-1), 'Helvetica-Bold'),
            ('FONTSIZE',      (0,0), (-1,-1), 11),
            ('ALIGN',         (1,0), (1,-1), 'RIGHT'),
            ('ROWBACKGROUNDS',(0,1), (-1,-2), [colors.white, colors.HexColor('#F8FAFC')]),
            ('BACKGROUND',    (0,-1), (-1,-1), colors.HexColor('#ECFDF5')),
            ('GRID',          (0,0), (-1,-1), 0.5, colors.HexColor('#E2E8F0')),
            ('PADDING',       (0,0), (-1,-1), 8),
        ]))
        story.append(tabla)

        doc.build(story)
        pdf_bytes = buffer.getvalue()
        buffer.close()

        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename=boleta_honorarios_{rut}_{periodo.replace('/', '-')}.pdf"}
        )
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/liquidacion-honorario")
def listar_liquidaciones_honorario(persona_id: int, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id,))
        t = cursor.fetchone()
        if not t:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = t[0]

        query = """SELECT lh.descripcion_trabajo, lh.honorario_bruto, lh.tasa_retencion_aplicada,
                          cmh.monto_retencion, cmh.honorario_liquido, lh.periodo, lh.fecha_registro
                   FROM liquidacion_honorario lh
                   JOIN calculo_monto_honorario cmh ON cmh.liquidacion_honorario_id = lh.liquidacion_honorario_id
                   WHERE lh.trabajador_id = %s"""
        params = [trabajador_id]
        if periodo:
            query += " AND lh.periodo = %s"
            params.append(periodo)
        query += " ORDER BY lh.fecha_registro DESC"
        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "liquidaciones": [
                {
                    "descripcion_trabajo": r[0],
                    "honorario_bruto": int(r[1]),
                    "tasa_retencion_aplicada": float(r[2]),
                    "monto_retencion": int(r[3]),
                    "honorario_liquido": int(r[4]),
                    "periodo": r[5],
                    "fecha_registro": r[6].strftime("%d/%m/%Y %H:%M") if r[6] else "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/config-gratificacion")
def ver_config_gratificacion(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT modalidad, porcentaje_mensual, limite_imm_anual, porcentaje_anual, fecha_modificacion
               FROM config_gratificacion ORDER BY config_id DESC LIMIT 1"""
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()
        if not r:
            return {"success": False, "mensaje": "No hay configuracion de gratificacion registrada"}
        return {
            "success": True,
            "modalidad": r[0],
            "porcentaje_mensual": float(r[1]) if r[1] is not None else 25.0,
            "limite_imm_anual": float(r[2]) if r[2] is not None else 4.75,
            "porcentaje_anual": float(r[3]) if r[3] is not None else 30.0,
            "fecha_modificacion": r[4].strftime("%d/%m/%Y %H:%M") if r[4] else "—",
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.put("/admin/config-gratificacion")
def actualizar_config_gratificacion(data: ConfigGratificacionRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        if data.modalidad not in ("Proporcional", "Anual"):
            return {"success": False, "mensaje": "Modalidad invalida. Debe ser 'Proporcional' o 'Anual'"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute("SELECT config_id FROM config_gratificacion ORDER BY config_id DESC LIMIT 1")
        existente = cursor.fetchone()

        if existente:
            cursor.execute(
                """UPDATE config_gratificacion
                   SET modalidad = %s, porcentaje_mensual = %s, limite_imm_anual = %s,
                       porcentaje_anual = %s, fecha_modificacion = NOW(), modificado_por = %s
                   WHERE config_id = %s""",
                (data.modalidad, data.porcentaje_mensual, data.limite_imm_anual,
                 data.porcentaje_anual, administrador_id, existente[0])
            )
        else:
            cursor.execute(
                """INSERT INTO config_gratificacion
                   (modalidad, porcentaje_mensual, limite_imm_anual, porcentaje_anual, modificado_por)
                   VALUES (%s, %s, %s, %s, %s)""",
                (data.modalidad, data.porcentaje_mensual, data.limite_imm_anual,
                 data.porcentaje_anual, administrador_id)
            )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Configuracion de gratificacion actualizada correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: CALCULO DE GRATIFICACION ────────────────────────────
def _obtener_base_gratificacion(persona_id: int, periodo: str) -> dict:
    """
    Base de calculo para la Gratificacion Proporcional (Art. 50):
    sueldo base + horas extras + bonos imponibles (de la tabla
    bono_imponible, sin incluir bonos condicionales, bonos
    excepcionales, ni el excedente de movilizacion/colacion).
    """
    (_, error_periodo) = validar_periodo_mm_aaaa(periodo)
    if error_periodo:
        return {"success": False, "mensaje": error_periodo}

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """SELECT t.trabajador_id, c.sueldo_base,
                  p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre,
                  p.rut
           FROM trabajador t
           JOIN persona p ON p.persona_id = t.persona_id
           LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
           WHERE t.persona_id = %s""",
        (persona_id,)
    )
    r = cursor.fetchone()
    if not r:
        cursor.close(); conn.close()
        return {"success": False, "mensaje": "Trabajador no encontrado"}
    trabajador_id, sueldo_base, nombre, rut = r

    if not sueldo_base or float(sueldo_base) <= 0:
        cursor.close(); conn.close()
        return {"success": False, "mensaje": "El trabajador no tiene un sueldo base activo registrado"}

    cursor.execute(
        """SELECT cantidad_horas, valor_hora_ordinaria FROM horas_extras
           WHERE trabajador_id = %s AND periodo = %s AND estado = 'Aprobada'""",
        (trabajador_id, periodo)
    )
    horas_extras_total = 0
    for cantidad_horas, valor_hora_ordinaria in cursor.fetchall():
        horas_extras_total += round(float(valor_hora_ordinaria) * 1.5 * float(cantidad_horas))

    cursor.execute(
        "SELECT COALESCE(SUM(monto_clp), 0) FROM bono_imponible WHERE trabajador_id = %s AND periodo = %s",
        (trabajador_id, periodo)
    )
    bonos_imponibles_total = int(cursor.fetchone()[0])

    # Bono excepcional: solo cuenta para la base de gratificacion si
    # fue clasificado como Imponible (si es No imponible, no aplica).
    cursor.execute(
        "SELECT COALESCE(SUM(monto_clp), 0) FROM bono_excepcional WHERE trabajador_id = %s AND periodo = %s AND clasificacion = 'Imponible'",
        (trabajador_id, periodo)
    )
    bono_excepcional_imponible = int(cursor.fetchone()[0])
    cursor.close(); conn.close()

    sueldo_base = round(float(sueldo_base))
    base_calculo = sueldo_base + horas_extras_total + bonos_imponibles_total + bono_excepcional_imponible

    return {
        "success": True,
        "nombre": nombre,
        "rut": rut,
        "sueldo_base": sueldo_base,
        "horas_extras": horas_extras_total,
        "bonos_imponibles": bonos_imponibles_total,
        "bono_excepcional_imponible": bono_excepcional_imponible,
        "base_calculo": base_calculo,
    }


@app.get("/admin/gratificacion-datos-base")
def ver_datos_base_gratificacion(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        return _obtener_base_gratificacion(persona_id, periodo)
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/calculo-gratificacion")
def calcular_gratificacion(persona_id: int, periodo: str, utilidad_liquida_anual: float = None, payload: dict = Depends(verificar_token)):
    """
    Calcula la gratificacion legal segun la modalidad configurada:
      - Proporcional (Art. 50): 25% del total imponible mensual, con
        tope de (4.75 IMM anuales / 12) por mes.
      - Anual (Art. 47): 30% de las ganancias liquidas del ejercicio,
        repartido en partes iguales entre los trabajadores activos
        (simplificacion academica: el sistema no modela un estado de
        resultados completo, asi que la utilidad se ingresa manualmente
        y se reparte por igual entre el personal activo).
    """
    try:
        verificar_rol(payload, ["admin"])

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT modalidad, porcentaje_mensual, limite_imm_anual, porcentaje_anual
               FROM config_gratificacion ORDER BY config_id DESC LIMIT 1"""
        )
        config_row = cursor.fetchone()
        if not config_row:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No hay configuracion de gratificacion registrada"}
        modalidad, porcentaje_mensual, limite_imm_anual, porcentaje_anual = config_row
        porcentaje_mensual = float(porcentaje_mensual or 25.0)
        limite_imm_anual = float(limite_imm_anual or 4.75)
        porcentaje_anual = float(porcentaje_anual or 30.0)

        if modalidad == "Proporcional":
            base_gratificacion = _obtener_base_gratificacion(persona_id, periodo)
            if not base_gratificacion.get("success"):
                cursor.close(); conn.close()
                return base_gratificacion

            valor_imm = obtener_valor_imm_periodo(periodo)
            if valor_imm is None:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "Es necesario ingresar el valor del IMM del periodo antes de calcular la gratificacion"}

            base_calculo = base_gratificacion["base_calculo"]
            gratificacion_sin_tope = round(base_calculo * porcentaje_mensual / 100)
            tope_mensual = round((limite_imm_anual * valor_imm) / 12)
            gratificacion_final = min(gratificacion_sin_tope, tope_mensual)

            cursor.close(); conn.close()
            return {
                "success": True,
                "modalidad": "Proporcional",
                "nombre": base_gratificacion["nombre"],
                "rut": base_gratificacion["rut"],
                "periodo": periodo,
                "sueldo_base": base_gratificacion["sueldo_base"],
                "horas_extras": base_gratificacion["horas_extras"],
                "bonos_imponibles": base_gratificacion["bonos_imponibles"],
                "base_calculo": base_calculo,
                "porcentaje_mensual": porcentaje_mensual,
                "gratificacion_sin_tope": gratificacion_sin_tope,
                "valor_imm": valor_imm,
                "limite_imm_anual": limite_imm_anual,
                "tope_mensual": tope_mensual,
                "gratificacion_final": gratificacion_final,
                "se_aplico_tope": gratificacion_sin_tope > tope_mensual,
            }

        else:  # modalidad == "Anual"
            if utilidad_liquida_anual is None or utilidad_liquida_anual <= 0:
                cursor.close(); conn.close()
                return {
                    "success": False,
                    "mensaje": "Para la modalidad Anual (Art. 47) debes ingresar la utilidad liquida anual de la empresa"
                }

            cursor.execute(
                """SELECT COUNT(*) FROM trabajador t JOIN persona p ON p.persona_id = t.persona_id
                   WHERE p.activo = TRUE"""
            )
            total_trabajadores = cursor.fetchone()[0]
            if total_trabajadores == 0:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "No hay trabajadores activos para repartir la gratificacion"}

            cursor.execute(
                """SELECT p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre, p.rut
                   FROM trabajador t JOIN persona p ON p.persona_id = t.persona_id
                   WHERE p.persona_id = %s""",
                (persona_id,)
            )
            trab_row = cursor.fetchone()
            cursor.close(); conn.close()
            if not trab_row:
                return {"success": False, "mensaje": "Trabajador no encontrado"}
            nombre, rut = trab_row

            monto_total_gratificacion = round(utilidad_liquida_anual * porcentaje_anual / 100)
            gratificacion_por_trabajador = round(monto_total_gratificacion / total_trabajadores)
            gratificacion_mensual_equivalente = round(gratificacion_por_trabajador / 12)

            return {
                "success": True,
                "modalidad": "Anual",
                "nombre": nombre,
                "rut": rut,
                "periodo": periodo,
                "utilidad_liquida_anual": utilidad_liquida_anual,
                "porcentaje_anual": porcentaje_anual,
                "monto_total_gratificacion": monto_total_gratificacion,
                "total_trabajadores_activos": total_trabajadores,
                "gratificacion_anual_trabajador": gratificacion_por_trabajador,
                "gratificacion_mensual_equivalente": gratificacion_mensual_equivalente,
                "nota": "Calculo simplificado: reparto en partes iguales entre trabajadores activos, ya que el sistema no modela un estado de resultados detallado por trabajador."
            }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# COSTO TOTAL EMPLEADOR
# ══════════════════════════════════════════════════════════════

@app.get("/admin/config-aportes-empleador")
def ver_aportes_empleador(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT concepto, tasa_porcentaje FROM config_aportes_empleador ORDER BY concepto")
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {"success": True, "aportes": [{"concepto": r[0], "tasa_porcentaje": float(r[1])} for r in rows]}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.put("/admin/config-aportes-empleador")
def actualizar_aporte_empleador(data: AporteEmpleadorRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        if data.concepto not in ("SIS_AFP", "Salud_Empleador", "Expectativa_Vida", "Aporte_Capitalizacion"):
            return {"success": False, "mensaje": "Concepto invalido"}
        if data.tasa_porcentaje < 0:
            return {"success": False, "mensaje": "La tasa no puede ser negativa"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """UPDATE config_aportes_empleador
               SET tasa_porcentaje = %s, fecha_modificacion = NOW(), modificado_por = %s
               WHERE concepto = %s""",
            (data.tasa_porcentaje, administrador_id, data.concepto)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Aporte {data.concepto} actualizado correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/costo-total-empleador")
def calcular_costo_total_empleador(persona_id: int, periodo: str, payload: dict = Depends(verificar_token), tasas_aporte_cache: dict = None):
    """
    Costo total mensual del trabajador para el empleador:
      sueldo bruto (total imponible) + aporte salud empleador
      + aporte AFP empleador (SIS) + aporte patronal AFC
    Muestra tambien el costo del trabajador (sus propios descuentos)
    para comparar lado a lado.

    tasas_aporte_cache es opcional: si quien llama a esta funcion
    dentro de un loop (ej. alertas_pre_cierre, recorriendo muchos
    trabajadores) ya trajo config_aportes_empleador una sola vez,
    puede pasarla aqui para no volver a consultarla en cada vuelta.
    """
    try:
        verificar_rol(payload, ["admin"])

        resultado_afp_salud = calcular_afp_salud(persona_id, periodo, payload)
        if not resultado_afp_salud.get("success"):
            return resultado_afp_salud

        resultado_afc = calcular_afc(persona_id, periodo, payload)
        if not resultado_afc.get("success"):
            return resultado_afc

        if tasas_aporte_cache is not None:
            tasas_aporte = tasas_aporte_cache
        else:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT concepto, tasa_porcentaje FROM config_aportes_empleador")
            aportes_rows = cursor.fetchall()
            cursor.close(); conn.close()
            tasas_aporte = {r[0]: float(r[1]) for r in aportes_rows}
        tasa_sis = tasas_aporte.get("SIS_AFP", 0.0)
        tasa_expectativa_vida = tasas_aporte.get("Expectativa_Vida", 0.0)
        tasa_aporte_capitalizacion = tasas_aporte.get("Aporte_Capitalizacion", 0.0)

        # Total Haberes: se reutiliza el resultado ya calculado en esta
        # misma peticion gracias al cache interno (misma clave
        # persona_id+periodo que ya calculo calcular_afp_salud arriba),
        # asi que llamar esto de nuevo no repite trabajo pesado.
        base_imponible = calcular_total_imponible_interno(persona_id, periodo)
        if not base_imponible.get("success"):
            return base_imponible
        total_haberes = base_imponible["total_haberes"]

        # Base sobre la que se calculan los aportes de la empresa: el
        # total imponible topado AFP/Salud, igual que en la pantalla
        # de Cotizaciones Previsionales.
        base_afp_salud = resultado_afp_salud["total_imponible_afp_salud"]

        aporte_afc_empleador = resultado_afc["aporte_empleador"]
        sis = round(base_afp_salud * tasa_sis / 100)
        expectativa_vida = round(base_afp_salud * tasa_expectativa_vida / 100)
        aporte_capitalizacion = round(base_afp_salud * tasa_aporte_capitalizacion / 100)

        cotizaciones_aporte_empresa = (
            aporte_afc_empleador + sis + expectativa_vida + aporte_capitalizacion
        )

        # Costo Total Empresa = Total Haberes + Cotizaciones Aporte Empresa
        costo_total_empleador = total_haberes + cotizaciones_aporte_empresa

        costo_trabajador = (
            resultado_afp_salud["descuento_afp"]
            + resultado_afp_salud["descuento_salud"]
            + resultado_afc["descuento_trabajador"]
        )
        sueldo_liquido_aproximado = total_haberes - costo_trabajador

        return {
            "success": True,
            "nombre": resultado_afp_salud["nombre"],
            "rut": resultado_afp_salud["rut"],
            "periodo": periodo,
            "total_haberes": total_haberes,
            "total_imponible_sin_tope": resultado_afp_salud["total_imponible"],
            "tasa_sis_afp": tasa_sis,
            "aporte_afp_empleador": sis,
            "tasa_expectativa_vida": tasa_expectativa_vida,
            "aporte_expectativa_vida": expectativa_vida,
            "tasa_aporte_capitalizacion": tasa_aporte_capitalizacion,
            "aporte_capitalizacion": aporte_capitalizacion,
            "aporte_afc_empleador": aporte_afc_empleador,
            "cotizaciones_aporte_empresa": cotizaciones_aporte_empresa,
            "costo_total_empleador": costo_total_empleador,
            "descuento_afp_trabajador": resultado_afp_salud["descuento_afp"],
            "descuento_salud_trabajador": resultado_afp_salud["descuento_salud"],
            "descuento_afc_trabajador": resultado_afc["descuento_trabajador"],
            "costo_total_trabajador": costo_trabajador,
            "sueldo_liquido_aproximado": sueldo_liquido_aproximado,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/cotizaciones-previsionales")
def ver_cotizaciones_previsionales(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    """
    Cuadro resumen de "Cotizaciones Previsionales + Impuestos para
    pagar": junta lo YA calculado en AFP/Salud/AFC/Impuesto (lo
    descontado al trabajador), mas los aportes propios de la empresa
    (Seguro de Cesantia empleador, SIS, Expectativa de Vida, Aporte
    Previsional de Capitalizacion Individual). Es solo informativo/de
    referencia contable — NO modifica el Liquido a Pagar del
    trabajador, que ya quedo resuelto en el Desglose de Liquidacion.
    """
    try:
        verificar_rol(payload, ["admin"])

        resultado_afp_salud = calcular_afp_salud(persona_id, periodo, payload)
        if not resultado_afp_salud.get("success"):
            return resultado_afp_salud

        resultado_afc = calcular_afc(persona_id, periodo, payload)
        if not resultado_afc.get("success"):
            return resultado_afc

        resultado_impuesto = calcular_impuesto_unico(persona_id, periodo, payload)
        if not resultado_impuesto.get("success"):
            return resultado_impuesto

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT concepto, tasa_porcentaje FROM config_aportes_empleador")
        tasas_aporte = {r[0]: float(r[1]) for r in cursor.fetchall()}
        cursor.close(); conn.close()

        tasa_sis = tasas_aporte.get("SIS_AFP", 0.0)
        tasa_expectativa_vida = tasas_aporte.get("Expectativa_Vida", 0.0)
        tasa_aporte_capitalizacion = tasas_aporte.get("Aporte_Capitalizacion", 0.0)

        base_afp_salud = resultado_afp_salud["total_imponible_afp_salud"]

        # ── Descontado al trabajador (ya calculado en otras pantallas) ──
        descuento_afp = resultado_afp_salud["descuento_afp"]
        descuento_salud = resultado_afp_salud["descuento_salud"]
        descuento_afc_trabajador = resultado_afc["descuento_trabajador"]
        impuesto_unico = resultado_impuesto["impuesto_unico"]

        # ── Aportes de la empresa ──
        aporte_afc_empleador = resultado_afc["aporte_empleador"]  # reutilizado, ya considera Indefinido/Plazo Fijo
        sis = round(base_afp_salud * tasa_sis / 100)
        expectativa_vida = round(base_afp_salud * tasa_expectativa_vida / 100)
        aporte_capitalizacion = round(base_afp_salud * tasa_aporte_capitalizacion / 100)

        total = (
            descuento_afp + descuento_salud + descuento_afc_trabajador + impuesto_unico
            + aporte_afc_empleador + sis + expectativa_vida + aporte_capitalizacion
        )

        tipo_afp = resultado_afp_salud["tipo_afp"]
        institucion_salud = resultado_afp_salud["institucion_salud"]

        return {
            "success": True,
            "nombre": resultado_afp_salud["nombre"],
            "rut": resultado_afp_salud["rut"],
            "periodo": periodo,
            "items": {
                "afp": {"monto": descuento_afp, "origen": "Descontado al Trabajador", "donde_pagar": f"La Empresa debe pagarlo en la {tipo_afp} donde está la persona"},
                "salud": {"monto": descuento_salud, "origen": "Descontado al Trabajador", "donde_pagar": f"La Empresa debe pagarlo en {institucion_salud} donde está la persona"},
                "seguro_cesantia_trabajador": {"monto": descuento_afc_trabajador, "origen": "Descontado al Trabajador", "donde_pagar": "La Empresa debe pagarlo en la AFC (administradora de fondo de cesantía)"},
                "impuesto_renta": {"monto": impuesto_unico, "origen": "Descontado al Trabajador", "donde_pagar": "La Empresa debe pagarlo en la declaración de Impuesto que corresponda"},
                "seguro_cesantia_empresa": {"monto": aporte_afc_empleador, "tasa": resultado_afc.get("porcentaje_empleador"), "origen": "Aporte de la Empresa", "donde_pagar": "La Empresa debe pagarlo en la AFC (administradora de fondo de cesantía)"},
                "sis": {"monto": sis, "tasa": tasa_sis, "origen": "Aporte de la Empresa", "donde_pagar": f"La Empresa debe pagarlo en la {tipo_afp} donde está la persona"},
                "expectativa_vida": {"monto": expectativa_vida, "tasa": tasa_expectativa_vida, "origen": "Aporte de la Empresa", "donde_pagar": f"La Empresa debe pagarlo en la {tipo_afp} donde está la persona"},
                "aporte_capitalizacion": {"monto": aporte_capitalizacion, "tasa": tasa_aporte_capitalizacion, "origen": "Aporte de la Empresa", "donde_pagar": f"La Empresa debe pagarlo en la {tipo_afp} donde está la persona"},
            },
            "total": round(total),
            "total_palabras": numero_a_palabras_clp(round(total)),
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# ANTICIPOS DE SUELDO (Art. 58 - tope 15% del liquido)
# ══════════════════════════════════════════════════════════════

def _folio_valido(folio: str) -> bool:
    """1-20 caracteres alfanumericos, guiones permitidos (ej: ANT-2025-001)."""
    return bool(re.match(r'^[A-Za-z0-9\-]{1,20}$', folio or ""))


@app.post("/admin/anticipos-sueldo")
def registrar_anticipo_sueldo(data: AnticipoSueldoRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if data.monto_clp <= 0:
            return {"success": False, "mensaje": "El monto debe ser un entero positivo mayor a 0"}
        if data.monto_clp >= 10**9:
            return {"success": False, "mensaje": "El monto no puede superar 9 digitos"}

        # Validacion de formato MM/AAAA (sin la restriccion de "no futuro"
        # que usa validar_periodo_mm_aaaa, ya que un anticipo SI puede
        # registrarse para un periodo futuro cercano)
        partes_periodo = data.periodo.split("/")
        if len(partes_periodo) != 2 or not (partes_periodo[0].isdigit() and partes_periodo[1].isdigit()
                                             and len(partes_periodo[0]) == 2 and len(partes_periodo[1]) == 4):
            return {"success": False, "mensaje": "Formato de periodo invalido (debe ser MM/AAAA)"}
        mes_periodo, anio_periodo = int(partes_periodo[0]), int(partes_periodo[1])
        if mes_periodo < 1 or mes_periodo > 12:
            return {"success": False, "mensaje": "El mes del periodo debe estar entre 01 y 12"}

        # El anticipo se descuenta de una liquidacion aun no cerrada,
        # asi que el periodo debe ser el mes actual o uno futuro
        # (no tiene sentido pedir un anticipo de un mes ya pasado).
        hoy = dt.date.today()
        if (anio_periodo, mes_periodo) < (hoy.year, hoy.month):
            return {"success": False, "mensaje": "El periodo del anticipo no puede ser un mes anterior al actual"}

        if not _folio_valido(data.folio_autorizacion):
            return {"success": False, "mensaje": "El folio de autorizacion debe tener entre 1 y 20 caracteres alfanumericos (ej: ANT-2025-001)"}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (data.persona_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id = r[0]

        if verificar_liquidacion_cerrada(trabajador_id, data.periodo):
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede modificar esta liquidacion porque ya ha sido cerrada"}

        # ── Restriccion: maximo un anticipo activo por periodo ─────
        cursor.execute(
            """SELECT 1 FROM anticipo_sueldo
               WHERE trabajador_id = %s AND periodo = %s AND estado IN ('pendiente', 'aprobado')""",
            (trabajador_id, data.periodo)
        )
        if cursor.fetchone():
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Ya se ha realizado un anticipo en ese periodo."}

        cursor.close(); conn.close()

        # ── Art. 58: tope 15% del sueldo liquido mensual ───────────
        costo = calcular_costo_total_empleador(data.persona_id, data.periodo, payload)
        if not costo.get("success"):
            return costo
        sueldo_liquido = costo["sueldo_liquido_aproximado"]

        # Sumar deducciones ya existentes del periodo (descuentos +
        # licencias medicas), para comprobar el tope junto con el nuevo anticipo
        conn2 = get_connection()
        cursor2 = conn2.cursor()
        cursor2.execute(
            "SELECT COALESCE(SUM(monto_clp), 0) FROM descuento WHERE trabajador_id = %s AND periodo = %s",
            (trabajador_id, data.periodo)
        )
        total_descuentos = float(cursor2.fetchone()[0])

        cursor2.execute(
            "SELECT COALESCE(SUM(descuento_proporcional), 0) FROM licencia_medica WHERE trabajador_id = %s AND periodo = %s",
            (trabajador_id, data.periodo)
        )
        total_licencias = float(cursor2.fetchone()[0])
        cursor2.close(); conn2.close()

        total_deducciones_existentes = total_descuentos + total_licencias
        nuevo_total_deducciones = total_deducciones_existentes + data.monto_clp
        limite_15_por_ciento = round(sueldo_liquido * 0.15)

        if nuevo_total_deducciones > limite_15_por_ciento:
            return {
                "success": False,
                "mensaje": (
                    f"El anticipo excede el limite legal (Art. 58): las deducciones totales "
                    f"(${round(nuevo_total_deducciones)}) superarian el 15% del sueldo liquido "
                    f"(tope: ${limite_15_por_ciento})"
                )
            }

        # ── Insertar el anticipo ────────────────────────────────
        persona_id_admin = get_persona_id(payload)
        conn3 = get_connection()
        cursor3 = conn3.cursor()
        cursor3.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor3.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor3.execute(
            """INSERT INTO anticipo_sueldo (monto_clp, periodo, folio_autorizacion, estado, trabajador_id, aprobado_por)
               VALUES (%s, %s, %s, 'aprobado', %s, %s)
               RETURNING anticipo_id""",
            (data.monto_clp, data.periodo, data.folio_autorizacion, trabajador_id, administrador_id)
        )
        anticipo_id = cursor3.fetchone()[0]
        conn3.commit(); cursor3.close(); conn3.close()

        return {
            "success": True,
            "mensaje": "Anticipo registrado correctamente",
            "anticipo_id": anticipo_id,
            "sueldo_liquido": sueldo_liquido,
            "limite_15_por_ciento": limite_15_por_ciento,
            "total_deducciones_con_anticipo": round(nuevo_total_deducciones),
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/anticipos-sueldo")
def listar_anticipos_sueldo(trabajador_id: int = None, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()

        query = """
            SELECT a.anticipo_id, a.monto_clp, a.periodo, a.folio_autorizacion, a.estado,
                   p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut,
                   p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
            FROM anticipo_sueldo a
            JOIN trabajador t ON t.trabajador_id = a.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN administrador ad ON ad.administrador_id = a.aprobado_por
            LEFT JOIN persona p2 ON p2.persona_id = ad.persona_id
            WHERE 1=1
        """
        params = []
        if trabajador_id:
            query += " AND a.trabajador_id = %s"
            params.append(trabajador_id)
        if periodo:
            query += " AND a.periodo = %s"
            params.append(periodo)
        query += " ORDER BY a.anticipo_id DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        anticipos = []
        for r in rows:
            anticipo_id, monto, periodo_r, folio, estado, nombre, rut, nombre_admin = r
            anticipos.append({
                "anticipo_id":      anticipo_id,
                "monto_clp":        int(monto),
                "periodo":          periodo_r,
                "folio_autorizacion": folio,
                "estado":           estado,
                "nombre_trabajador": nombre,
                "rut":              rut,
                "nombre_admin":     nombre_admin or "—",
            })
        return {"success": True, "anticipos": anticipos}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# CIERRE DE LIQUIDACION
# ══════════════════════════════════════════════════════════════

def verificar_liquidacion_cerrada(trabajador_id: int, periodo: str) -> bool:
    """
    Helper reutilizable: retorna True si ya existe una liquidacion
    'normal' con estado 'cerrada' para ese trabajador y periodo. Se
    usa para bloquear la edicion de datos ya facturados.
    """
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """SELECT 1 FROM liquidacion
           WHERE trabajador_id = %s AND periodo = %s
             AND tipo_liquidacion = 'normal' AND estado = 'cerrada'""",
        (trabajador_id, periodo)
    )
    existe = cursor.fetchone() is not None
    cursor.close(); conn.close()
    return existe


@app.get("/admin/liquidacion-cerrada")
def endpoint_liquidacion_cerrada(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    """
    Le permite al frontend avisar de entrada (antes de que el admin
    llene formularios) si la liquidacion de este trabajador/periodo
    ya esta cerrada, para no hacerle perder tiempo.
    """
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id,))
        r = cursor.fetchone()
        cursor.close(); conn.close()
        if not r:
            return {"success": True, "cerrada": False}
        trabajador_id = r[0]
        return {"success": True, "cerrada": verificar_liquidacion_cerrada(trabajador_id, periodo)}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.post("/admin/liquidacion/cerrar")
def cerrar_liquidacion(data: CerrarLiquidacionRequest, payload: dict = Depends(verificar_token)):
    """
    Consolida y CIERRA la liquidacion mensual de un trabajador:
    toma todos los calculos ya construidos (total imponible, AFP,
    salud, AFC, impuesto unico, gratificacion si aplica, descuentos,
    licencias, anticipos aprobados) y los guarda de forma permanente
    en la tabla liquidacion con estado='cerrada'. Una vez cerrada,
    ningun dato de ese periodo puede volver a editarse (ver
    verificar_liquidacion_cerrada, usado en los endpoints de registro).
    """
    try:
        verificar_rol(payload, ["admin"])

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT t.trabajador_id, c.contrato_id FROM trabajador t "
                        "LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo' "
                        "WHERE t.persona_id = %s", (data.persona_id,))
        r = cursor.fetchone()
        cursor.close(); conn.close()
        if not r:
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id, contrato_id = r

        # Bloqueo si ya esta cerrada
        if verificar_liquidacion_cerrada(trabajador_id, data.periodo):
            return {"success": False, "mensaje": "No se puede modificar esta liquidacion porque ya ha sido cerrada"}

        # Bloqueo si falta la UTM del periodo (requisito explicito)
        if not hay_utm_para_periodo(data.periodo):
            return {"success": False, "mensaje": "Es necesario ingresar el valor de la UTM del periodo antes de cerrar las remuneraciones"}

        # ── Reutiliza todos los calculos ya construidos ─────────
        base_imponible = calcular_total_imponible_interno(data.persona_id, data.periodo)
        if not base_imponible.get("success"):
            return base_imponible

        resultado_afp_salud = calcular_afp_salud(data.persona_id, data.periodo, payload)
        if not resultado_afp_salud.get("success"):
            return resultado_afp_salud

        resultado_afc = calcular_afc(data.persona_id, data.periodo, payload)
        if not resultado_afc.get("success"):
            return resultado_afc

        resultado_impuesto = calcular_impuesto_unico(data.persona_id, data.periodo, payload)
        if not resultado_impuesto.get("success"):
            return resultado_impuesto

        resultado_costo = calcular_costo_total_empleador(data.persona_id, data.periodo, payload)
        if not resultado_costo.get("success"):
            return resultado_costo

        # Descuentos varios del periodo. Solo Prestamo se suma aqui:
        # Inasistencia y Retraso (Atraso) ya estan reflejados dentro de
        # Total Haberes (el sueldo base ya viene reducido por los dias
        # de inasistencia, y el atraso se resta directo de Total
        # Haberes en el motor central) -- sumarlos aqui de nuevo
        # duplicaria el descuento sobre el liquido final.
        conn2 = get_connection()
        cursor2 = conn2.cursor()
        cursor2.execute(
            "SELECT COALESCE(SUM(monto_clp), 0) FROM descuento WHERE trabajador_id = %s AND periodo = %s AND tipo_descuento = 'Prestamo'",
            (trabajador_id, data.periodo)
        )
        total_descuentos_varios = float(cursor2.fetchone()[0])

        # Licencia Medica tampoco se sume aqui: su efecto ya esta
        # incluido en el sueldo base reducido (se paga solo por los
        # dias efectivamente trabajados). Se deja la variable en 0
        # solo para no romper el registro de auditoria mas abajo.
        total_licencias = 0.0

        cursor2.execute(
            "SELECT COALESCE(SUM(monto_clp), 0) FROM anticipo_sueldo WHERE trabajador_id = %s AND periodo = %s AND estado = 'aprobado'",
            (trabajador_id, data.periodo)
        )
        total_anticipos = float(cursor2.fetchone()[0])
        cursor2.close(); conn2.close()

        total_imponible = base_imponible["total_imponible"]
        total_haberes = base_imponible["total_haberes"]
        descuento_afp = resultado_afp_salud["descuento_afp"]
        descuento_salud = resultado_afp_salud["descuento_salud"]
        descuento_afc_trabajador = resultado_afc["descuento_trabajador"]
        impuesto_unico = resultado_impuesto["impuesto_unico"]
        gratificacion_monto = base_imponible["desglose"]["gratificacion_total"]

        total_descuento = (
            descuento_afp + descuento_salud + descuento_afc_trabajador + impuesto_unico
            + total_descuentos_varios + total_anticipos
        )
        liquido_a_pagar = max(0, round(total_haberes - total_descuento))

        mes, anio = data.periodo.split("/")
        persona_id_admin = get_persona_id(payload)
        conn3 = get_connection()
        cursor3 = conn3.cursor()
        cursor3.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor3.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor3.execute(
            """INSERT INTO liquidacion
               (mes, anio, periodo, sueldo_base, total_haberes_imponible,
                descuento_afp, descuento_salud, descuento_afc_trabajador,
                aporte_afc_empleador, impuesto_unico, gratificacion, total_descuento,
                liquido_a_pagar, costo_total_empleador, estado, fecha_cierre,
                tipo_liquidacion, trabajador_id, contrato_id, cerrada_por)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                       'cerrada', NOW(), 'normal', %s, %s, %s)
               RETURNING liquidacion_id""",
            (int(mes), int(anio), data.periodo, base_imponible["desglose"]["sueldo_base_considerado"],
             total_imponible, descuento_afp, descuento_salud, descuento_afc_trabajador,
             resultado_afc["aporte_empleador"], impuesto_unico, gratificacion_monto, round(total_descuento),
             liquido_a_pagar, resultado_costo["costo_total_empleador"],
             trabajador_id, contrato_id, administrador_id)
        )
        liquidacion_id = cursor3.fetchone()[0]
        conn3.commit(); cursor3.close(); conn3.close()

        # #26: se guarda una "foto" fija del detalle de calculo de
        # esta liquidacion — valores de entrada, formula/regla con
        # referencia legal, y resultado en CLP. Queda disponible tal
        # cual quedo en el momento del cierre, aunque despues cambien
        # las tasas o parametros usados.
        try:
            conn4 = get_connection()
            cursor4 = conn4.cursor()
            desglose_base = base_imponible["desglose"]
            items_detalle = [
                (
                    "Sueldo base",
                    f"Sueldo base considerado: ${desglose_base['sueldo_base_considerado']} CLP"
                    + (f" ({desglose_base.get('detalle_proporcional')})" if desglose_base.get("es_proporcional") else ""),
                    "Sueldo base pactado en el contrato (proporcional si hay ingreso/egreso a mitad de mes)",
                    "Art. 41 Código del Trabajo",
                    desglose_base["sueldo_base_considerado"],
                ),
                (
                    "Horas extras",
                    f"{desglose_base['horas_extra_cantidad']} registro(s), total ${desglose_base['horas_extra_total']} CLP",
                    "((Sueldo base ÷ 30 × 28) ÷ (Jornada semanal × 4)) × 1,5 × horas trabajadas",
                    "Art. 32 Código del Trabajo",
                    desglose_base["horas_extra_total"],
                ),
                (
                    "Gratificación legal",
                    f"Base: sueldo + horas extra + bonos imponibles = ${gratificacion_monto} CLP calculado",
                    "25% de la base imponible, con tope de 4,75 IMM anuales ÷ 12",
                    "Art. 50 Código del Trabajo",
                    gratificacion_monto,
                ),
                (
                    "Descuento AFP",
                    f"Base: ${resultado_afp_salud.get('total_imponible_afp_salud', total_imponible)} CLP, tasa {resultado_afp_salud.get('tasa_afp', '—')}%",
                    "Total Imponible para AFP y Salud (con tope 90 UF) × tasa de la AFP",
                    "DL 3.500",
                    descuento_afp,
                ),
                (
                    "Descuento Salud",
                    f"Base: ${resultado_afp_salud.get('total_imponible_afp_salud', total_imponible)} CLP, tasa {resultado_afp_salud.get('tasa_salud', '—')}%",
                    "Total Imponible para AFP y Salud (con tope 90 UF) × tasa de salud",
                    "Ley 18.933 / Ley 19.966",
                    descuento_salud,
                ),
                (
                    "Seguro de Cesantía (AFC)",
                    f"Base: ${resultado_afc.get('total_imponible_afc', total_imponible)} CLP, tasa trabajador {resultado_afc.get('porcentaje_trabajador', '—')}%",
                    "Total Imponible para AFC (con tope 135,2 UF) × 0,6% (Indefinido) o 0% (Plazo Fijo/Por obra)",
                    "Ley 19.728",
                    descuento_afc_trabajador,
                ),
                (
                    "Impuesto Único",
                    f"Total Tributable: ${resultado_impuesto.get('total_tributable', '—')} CLP = {resultado_impuesto.get('base_tributable_utm', '—')} UTM",
                    "Base tributable en CLP × factor del tramo − (rebaja del tramo × valor UTM del período) — cálculo directo en pesos",
                    "Art. 43 y 52 Ley de Impuesto a la Renta",
                    impuesto_unico,
                ),
                (
                    "Días descontados por Licencia Médica",
                    f"Días de licencia del período — su efecto ya está incluido en el 'Sueldo base' de arriba, no se resta aparte del líquido",
                    "Sueldo base ÷ 30 × (días base − días de licencia − días de inasistencia)",
                    "Código del Trabajo, Título II",
                    0,
                ),
                (
                    "Líquido a pagar",
                    f"Total Haberes: ${round(total_haberes)} CLP − Total Descuentos: ${round(total_descuento)} CLP",
                    "Total Haberes − (AFP + Salud + AFC + Impuesto + Otros descuentos + Anticipos) — Licencias, Inasistencias y Atrasos ya estan reflejados dentro de Total Haberes, no se restan de nuevo aqui",
                    None,
                    liquido_a_pagar,
                ),
            ]
            for concepto, valores_entrada, formula_regla, referencia_legal, resultado_clp in items_detalle:
                cursor4.execute(
                    """INSERT INTO detalle_calculo_liquidacion
                       (liquidacion_id, concepto, valores_entrada, formula_regla, referencia_legal, resultado_clp)
                       VALUES (%s, %s, %s, %s, %s, %s)""",
                    (liquidacion_id, concepto, valores_entrada, formula_regla, referencia_legal, round(resultado_clp))
                )
            conn4.commit(); cursor4.close(); conn4.close()
        except Exception:
            # Si el respaldo del detalle falla, no se bloquea el
            # cierre de la liquidacion (ya quedo guardada arriba).
            pass

        return {
            "success": True,
            "mensaje": "Liquidacion cerrada correctamente",
            "liquidacion_id": liquidacion_id,
            "nombre": base_imponible["nombre"],
            "rut": base_imponible["rut"],
            "periodo": data.periodo,
            "total_imponible": total_imponible,
            "descuento_afp": descuento_afp,
            "descuento_salud": descuento_salud,
            "descuento_afc_trabajador": descuento_afc_trabajador,
            "impuesto_unico": impuesto_unico,
            "gratificacion": gratificacion_monto,
            "total_descuentos_varios": round(total_descuentos_varios),
            "total_licencias": round(total_licencias),
            "total_anticipos": round(total_anticipos),
            "total_descuento": round(total_descuento),
            "liquido_a_pagar": liquido_a_pagar,
            "costo_total_empleador": resultado_costo["costo_total_empleador"],
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/liquidacion")
def ver_liquidacion(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT l.liquidacion_id, l.periodo, l.sueldo_base, l.total_haberes_imponible,
                      l.descuento_afp, l.descuento_salud, l.descuento_afc_trabajador,
                      l.aporte_afc_empleador, l.impuesto_unico, l.total_descuento,
                      l.liquido_a_pagar, l.costo_total_empleador, l.estado, l.tipo_liquidacion,
                      l.fecha_cierre, p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut,
                      l.observacion_complementaria
               FROM liquidacion l
               JOIN trabajador t ON t.trabajador_id = l.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               WHERE p.persona_id = %s AND l.periodo = %s
               ORDER BY l.tipo_liquidacion, l.liquidacion_id""",
            (persona_id, periodo)
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        if not rows:
            return {"success": False, "mensaje": "No hay liquidacion registrada para ese trabajador y periodo"}

        liquidaciones = []
        for r in rows:
            liquidaciones.append({
                "liquidacion_id":            r[0],
                "periodo":                   r[1],
                "sueldo_base":               float(r[2]) if r[2] is not None else None,
                "total_haberes_imponible":   float(r[3]) if r[3] is not None else None,
                "descuento_afp":             float(r[4]) if r[4] is not None else None,
                "descuento_salud":           float(r[5]) if r[5] is not None else None,
                "descuento_afc_trabajador":  float(r[6]) if r[6] is not None else None,
                "aporte_afc_empleador":      float(r[7]) if r[7] is not None else None,
                "impuesto_unico":            float(r[8]) if r[8] is not None else None,
                "total_descuento":           float(r[9]) if r[9] is not None else None,
                "liquido_a_pagar":           float(r[10]) if r[10] is not None else None,
                "costo_total_empleador":     float(r[11]) if r[11] is not None else None,
                "estado":                    r[12],
                "tipo_liquidacion":          r[13],
                "fecha_cierre":              r[14].strftime("%d/%m/%Y %H:%M") if r[14] else "—",
                "observacion_complementaria": r[17],
            })
        return {"success": True, "nombre": rows[0][15], "rut": rows[0][16], "liquidaciones": liquidaciones}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.post("/admin/liquidacion/complementaria")
def crear_liquidacion_complementaria(data: LiquidacionComplementariaRequest, payload: dict = Depends(verificar_token)):
    """
    Para corregir una liquidacion ya cerrada: NO se edita el registro
    original (queda intacto como historial), se crea una liquidacion
    complementaria (fila nueva) con el ajuste (positivo o negativo).
    """
    try:
        verificar_rol(payload, ["admin"])

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT t.trabajador_id, c.contrato_id FROM trabajador t "
                        "LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo' "
                        "WHERE t.persona_id = %s", (data.persona_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id, contrato_id = r

        if not verificar_liquidacion_cerrada(trabajador_id, data.periodo):
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No existe una liquidacion cerrada para ese periodo; no aplica una complementaria"}

        if not data.concepto or len(data.concepto.strip()) < 3:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El concepto de la correccion debe tener al menos 3 caracteres"}

        mes, anio = data.periodo.split("/")
        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO liquidacion
               (mes, anio, periodo, liquido_a_pagar, estado, fecha_cierre,
                tipo_liquidacion, observacion_complementaria, trabajador_id, contrato_id, cerrada_por)
               VALUES (%s, %s, %s, %s, 'cerrada', NOW(), 'complementaria', %s, %s, %s, %s)
               RETURNING liquidacion_id""",
            (int(mes), int(anio), data.periodo, data.monto_clp, data.concepto.strip(), trabajador_id, contrato_id, administrador_id)
        )
        liquidacion_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()

        return {
            "success": True,
            "mensaje": "Liquidacion complementaria registrada correctamente",
            "liquidacion_id": liquidacion_id,
            "concepto": data.concepto.strip(),
            "monto_clp": data.monto_clp,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# PARAMETRIZACION DE CONCEPTOS DE HABERES
# ══════════════════════════════════════════════════════════════

def _nombre_concepto_valido(nombre: str) -> bool:
    """3-100 caracteres; letras, numeros, espacios, punto, coma, guion y parentesis."""
    if not nombre or not (3 <= len(nombre) <= 100):
        return False
    return bool(re.match(r'^[A-Za-zÀ-ÿ0-9 .,\-()]+$', nombre))


@app.post("/admin/conceptos")
def crear_concepto(data: ConceptoRemuneracionRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if not _nombre_concepto_valido(data.nombre):
            return {"success": False, "mensaje": "Debe rellenar los campos obligatorios."}
        if data.tipo not in ("Fijo", "Variable"):
            return {"success": False, "mensaje": "Debe rellenar los campos obligatorios."}
        if data.clasificacion not in ("Imponible", "No imponible"):
            return {"success": False, "mensaje": "Debe rellenar los campos obligatorios."}
        if len(data.descripcion) > 500:
            return {"success": False, "mensaje": "Debe rellenar los campos obligatorios."}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT concepto_id FROM concepto_remuneracion WHERE nombre = %s", (data.nombre,))
        if cursor.fetchone():
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Ya existe un concepto con ese nombre"}

        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO concepto_remuneracion (nombre, tipo, clasificacion, descripcion, activo, es_base, modificado_por)
               VALUES (%s, %s, %s, %s, TRUE, FALSE, %s)
               RETURNING concepto_id""",
            (data.nombre, data.tipo, data.clasificacion, data.descripcion, administrador_id)
        )
        concepto_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Concepto creado correctamente", "concepto_id": concepto_id}
    except Exception as e:
        manejar_error_interno(e, payload=payload)
        return {"success": False, "mensaje": "Error en la validación, por favor intente más tarde."}


@app.get("/admin/conceptos")
def listar_conceptos(solo_activos: bool = False, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        query = "SELECT concepto_id, nombre, tipo, clasificacion, descripcion, activo, es_base FROM concepto_remuneracion"
        if solo_activos:
            query += " WHERE activo = TRUE"
        query += " ORDER BY es_base DESC, nombre"
        cursor.execute(query)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "conceptos": [
                {
                    "concepto_id": r[0],
                    "nombre": r[1],
                    "tipo": r[2],
                    "clasificacion": r[3],
                    "descripcion": r[4] or "",
                    "activo": r[5],
                    "es_base": r[6],
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.put("/admin/conceptos/{concepto_id}")
def editar_concepto(concepto_id: int, data: ConceptoRemuneracionRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if not _nombre_concepto_valido(data.nombre):
            return {"success": False, "mensaje": "Debe rellenar los campos obligatorios."}
        if data.tipo not in ("Fijo", "Variable"):
            return {"success": False, "mensaje": "Debe rellenar los campos obligatorios."}
        if data.clasificacion not in ("Imponible", "No imponible"):
            return {"success": False, "mensaje": "Debe rellenar los campos obligatorios."}
        if len(data.descripcion) > 500:
            return {"success": False, "mensaje": "Debe rellenar los campos obligatorios."}

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT es_base FROM concepto_remuneracion WHERE concepto_id = %s", (concepto_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Concepto no encontrado"}

        cursor.execute(
            "SELECT concepto_id FROM concepto_remuneracion WHERE nombre = %s AND concepto_id != %s",
            (data.nombre, concepto_id)
        )
        if cursor.fetchone():
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Ya existe otro concepto con ese nombre"}

        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """UPDATE concepto_remuneracion
               SET nombre = %s, tipo = %s, clasificacion = %s, descripcion = %s,
                   fecha_modificacion = NOW(), modificado_por = %s
               WHERE concepto_id = %s""",
            (data.nombre, data.tipo, data.clasificacion, data.descripcion, administrador_id, concepto_id)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Concepto actualizado correctamente"}
    except Exception as e:
        manejar_error_interno(e, payload=payload)
        return {"success": False, "mensaje": "Error en la validación, por favor intente más tarde."}


@app.put("/admin/conceptos/{concepto_id}/estado")
def cambiar_estado_concepto(concepto_id: int, data: EstadoConceptoRequest, payload: dict = Depends(verificar_token)):
    """
    Activa o desactiva un concepto. Los conceptos base (Sueldo base,
    Horas extras, AFP, Institucion de salud) no se pueden desactivar,
    ademas de nunca poder eliminarse. Desactivar un concepto NO afecta
    liquidaciones ya generadas, ya que estas no dependen de este
    catalogo para sus calculos (los conceptos son solo referenciales
    para elegir al registrar bonos/haberes).
    """
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT es_base, nombre FROM concepto_remuneracion WHERE concepto_id = %s", (concepto_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Concepto no encontrado"}
        es_base, nombre = r

        if es_base and not data.activo:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede desactivar."}

        cursor.execute(
            "UPDATE concepto_remuneracion SET activo = %s, fecha_modificacion = NOW() WHERE concepto_id = %s",
            (data.activo, concepto_id)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Concepto {'activado' if data.activo else 'desactivado'} correctamente"}
    except Exception as e:
        manejar_error_interno(e, payload=payload)
        return {"success": False, "mensaje": "Error en la validación, por favor intente más tarde."}


@app.delete("/admin/conceptos/{concepto_id}")
def eliminar_concepto(concepto_id: int, payload: dict = Depends(verificar_token)):
    """
    Elimina definitivamente un concepto personalizado. Los conceptos
    base (Sueldo base, Horas extras, AFP, Institucion de salud) nunca
    pueden eliminarse. concepto_remuneracion es solo un catalogo
    referencial (ninguna otra tabla lo usa como FK), asi que borrar un
    concepto personalizado es seguro y no deja registros huerfanos ni
    afecta liquidaciones ya generadas.
    """
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT es_base FROM concepto_remuneracion WHERE concepto_id = %s", (concepto_id,))
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Concepto no encontrado"}
        es_base = r[0]

        if es_base:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede eliminar."}

        cursor.execute("DELETE FROM concepto_remuneracion WHERE concepto_id = %s", (concepto_id,))
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Concepto eliminado correctamente"}
    except Exception as e:
        manejar_error_interno(e, payload=payload)
        return {"success": False, "mensaje": "Error en la validación, por favor intente más tarde."}


# ══════════════════════════════════════════════════════════════
# BONOS / INCENTIVOS CONDICIONALES
# ══════════════════════════════════════════════════════════════

def _condicion_valida(texto: str) -> bool:
    return bool(texto) and len(texto.strip()) <= 200 and len(texto.strip()) > 0


@app.post("/admin/bono-reglas")
def crear_bono_regla(data: BonoReglaRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if not (3 <= len(data.nombre_concepto.strip()) <= 100):
            return {"success": False, "mensaje": "El nombre del concepto debe tener entre 3 y 100 caracteres"}
        if not _condicion_valida(data.condicion_texto):
            return {"success": False, "mensaje": "La condicion de aplicacion debe tener entre 1 y 200 caracteres"}
        if data.clasificacion not in ("Imponible", "No imponible"):
            return {"success": False, "mensaje": "Clasificacion invalida. Debe ser 'Imponible' o 'No imponible'"}

        tiene_monto = data.monto_fijo_clp is not None and data.monto_fijo_clp > 0
        tiene_porcentaje = data.porcentaje_base is not None and 0.01 <= data.porcentaje_base <= 100

        if tiene_monto and tiene_porcentaje:
            return {"success": False, "mensaje": "Debes indicar SOLO un monto fijo O un porcentaje, no ambos"}
        if not tiene_monto and not tiene_porcentaje:
            return {"success": False, "mensaje": "Debes indicar un monto fijo (CLP > 0) o un porcentaje (0.01% a 100%)"}
        if data.monto_fijo_clp is not None and data.monto_fijo_clp >= 10**9:
            return {"success": False, "mensaje": "El monto no puede superar 9 digitos"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()

        cursor.execute(
            """INSERT INTO bono_regla (nombre_concepto, condicion_texto, monto_fijo_clp, porcentaje_base, clasificacion, activo)
               VALUES (%s, %s, %s, %s, %s, TRUE)
               RETURNING bono_id""",
            (
                data.nombre_concepto.strip(), data.condicion_texto.strip(),
                data.monto_fijo_clp if tiene_monto else None,
                data.porcentaje_base if tiene_porcentaje else None,
                data.clasificacion,
            )
        )
        bono_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Regla de bono creada correctamente", "bono_id": bono_id}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/bono-reglas")
def listar_bono_reglas(solo_activas: bool = False, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        query = """SELECT bono_id, nombre_concepto, condicion_texto, monto_fijo_clp,
                          porcentaje_base, clasificacion, activo FROM bono_regla"""
        if solo_activas:
            query += " WHERE activo = TRUE"
        query += " ORDER BY nombre_concepto"
        cursor.execute(query)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "reglas": [
                {
                    "bono_id": r[0],
                    "nombre_concepto": r[1],
                    "condicion_texto": r[2],
                    "monto_fijo_clp": int(r[3]) if r[3] is not None else None,
                    "porcentaje_base": float(r[4]) if r[4] is not None else None,
                    "clasificacion": r[5],
                    "activo": r[6],
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.put("/admin/bono-reglas/{bono_id}/estado")
def cambiar_estado_bono_regla(bono_id: int, data: EstadoBonoReglaRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE bono_regla SET activo = %s WHERE bono_id = %s", (data.activo, bono_id))
        if cursor.rowcount == 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Regla no encontrada"}
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Regla {'activada' if data.activo else 'desactivada'} correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.post("/admin/aplicar-bono-regla")
def aplicar_bono_regla(data: AplicacionBonoReglaRequest, payload: dict = Depends(verificar_token)):
    """
    Registra si un trabajador cumplio o no una regla de bono en un
    periodo. Si cumple, calcula el monto (fijo o % del sueldo base) y
    lo deja "congelado". Si no cumple, el bono queda registrado con
    monto 0 y no se incluye en ningun calculo.
    """
    try:
        verificar_rol(payload, ["admin"])

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """SELECT t.trabajador_id, c.sueldo_base FROM trabajador t
               LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE t.persona_id = %s""",
            (data.persona_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id, sueldo_base = r

        cursor.execute(
            "SELECT nombre_concepto, monto_fijo_clp, porcentaje_base, activo FROM bono_regla WHERE bono_id = %s",
            (data.bono_id,)
        )
        regla = cursor.fetchone()
        if not regla:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Regla de bono no encontrada"}
        nombre_concepto, monto_fijo, porcentaje_base, activa = regla

        if not activa:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Esta regla esta desactivada y no se puede aplicar"}

        if data.cumple_condicion:
            if monto_fijo is not None:
                monto_aplicado = float(monto_fijo)
            else:
                if not sueldo_base or float(sueldo_base) <= 0:
                    cursor.close(); conn.close()
                    return {"success": False, "mensaje": "El trabajador no tiene sueldo base activo para calcular el porcentaje"}
                monto_aplicado = round(float(sueldo_base) * float(porcentaje_base) / 100)
        else:
            monto_aplicado = 0

        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """INSERT INTO aplicacion_bono_regla (bono_id, trabajador_id, periodo, cumple_condicion, monto_aplicado, registrado_por)
               VALUES (%s, %s, %s, %s, %s, %s)
               ON CONFLICT (bono_id, trabajador_id, periodo) DO UPDATE
               SET cumple_condicion = EXCLUDED.cumple_condicion,
                   monto_aplicado = EXCLUDED.monto_aplicado,
                   registrado_por = EXCLUDED.registrado_por,
                   fecha_registro = NOW()
               RETURNING aplicacion_id""",
            (data.bono_id, trabajador_id, data.periodo, data.cumple_condicion, monto_aplicado, administrador_id)
        )
        aplicacion_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()

        return {
            "success": True,
            "mensaje": f"Bono '{nombre_concepto}' registrado correctamente",
            "aplicacion_id": aplicacion_id,
            "cumple_condicion": data.cumple_condicion,
            "monto_aplicado": round(monto_aplicado),
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/bono-reglas-aplicadas")
def listar_bono_reglas_aplicadas(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    """
    Muestra que reglas se aplicaron (o intentaron aplicarse) a un
    trabajador en un periodo, para que el administrador pueda
    verificarlo desde el detalle de la liquidacion.
    """
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT br.nombre_concepto, br.condicion_texto, br.clasificacion,
                      ab.cumple_condicion, ab.monto_aplicado, ab.fecha_registro
               FROM aplicacion_bono_regla ab
               JOIN bono_regla br ON br.bono_id = ab.bono_id
               JOIN trabajador t ON t.trabajador_id = ab.trabajador_id
               WHERE t.persona_id = %s AND ab.periodo = %s
               ORDER BY br.nombre_concepto""",
            (persona_id, periodo)
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "aplicaciones": [
                {
                    "nombre_concepto": r[0],
                    "condicion_texto": r[1],
                    "clasificacion": r[2],
                    "cumple_condicion": r[3],
                    "monto_aplicado": int(r[4]),
                    "fecha_registro": r[5].strftime("%d/%m/%Y %H:%M") if r[5] else "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# ALERTAS PRE-CIERRE
# ══════════════════════════════════════════════════════════════

@app.get("/admin/alertas-pre-cierre")
def alertas_pre_cierre(periodo: str, payload: dict = Depends(verificar_token)):
    """
    Revisa, para todos los trabajadores activos con contrato vigente,
    11 tipos de inconsistencias antes de cerrar las remuneraciones del
    periodo:
      1. Sueldo liquido por debajo del IMM vigente (si esta cargado).
      2. Total de descuentos superando el 100% del total imponible.
      3. Conceptos de remuneracion sin clasificacion imponible/no
         imponible definida (alerta a nivel de sistema, no de un
         trabajador especifico).
      4. Tasa de AFP del trabajador sin configurar en Tasas AFP.
      5. Tasa de Institucion de Salud del trabajador sin configurar
         en Tasas Salud.
      6. Movilizacion/Colacion del periodo sin confirmar a nivel
         general en Parametros del Sistema (alerta a nivel de
         sistema, no de un trabajador especifico).
      7. IMM sin cargar para el periodo (nivel de sistema).
      8. UTM sin cargar para el periodo (nivel de sistema).
      9. UF sin cargar para el periodo (nivel de sistema).
      10. Aportes del Empleador (SIS, Expectativa de Vida, AFC,
          Capitalizacion) sin ninguna tasa configurada (nivel sistema,
          no depende del periodo).
      11. Tabla de tramos del Impuesto Unico sin configurar (nivel
          sistema, no depende del periodo).

    Cada alerta incluye: nombre del trabajador afectado, tipo de
    inconsistencia y la accion correctiva sugerida.
    """
    try:
        verificar_rol(payload, ["admin"])

        (_, error_periodo) = validar_periodo_mm_aaaa(periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        alertas = []

        valor_imm = obtener_valor_imm_periodo(periodo)

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT p.persona_id, t.trabajador_id,
                      p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre
               FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE p.activo = TRUE AND c.sueldo_base IS NOT NULL AND c.sueldo_base > 0"""
        )
        trabajadores = cursor.fetchall()

        # ── Se traen agregados por trabajador de UNA sola vez (en vez de
        #    4 consultas por cada trabajador dentro del loop, que con
        #    muchos trabajadores hacia esto muy lento) ──────────────
        cursor.execute(
            "SELECT trabajador_id, COALESCE(SUM(monto_clp), 0) FROM descuento WHERE periodo = %s GROUP BY trabajador_id",
            (periodo,)
        )
        mapa_descuentos_varios = {tid: float(m) for (tid, m) in cursor.fetchall()}

        cursor.execute(
            "SELECT trabajador_id, COALESCE(SUM(descuento_proporcional), 0) FROM licencia_medica WHERE periodo = %s GROUP BY trabajador_id",
            (periodo,)
        )
        mapa_licencias = {tid: float(m) for (tid, m) in cursor.fetchall()}

        cursor.execute(
            "SELECT trabajador_id, COALESCE(SUM(monto_clp), 0) FROM anticipo_sueldo WHERE periodo = %s AND estado = 'aprobado' GROUP BY trabajador_id",
            (periodo,)
        )
        mapa_anticipos = {tid: float(m) for (tid, m) in cursor.fetchall()}

        cursor.execute("SELECT concepto, tasa_porcentaje FROM config_aportes_empleador")
        tasas_aporte_cache = {r[0]: float(r[1]) for r in cursor.fetchall()}

        cursor.execute("SELECT nombre_afp FROM config_tasas_afp")
        tasas_afp_cache = {r[0] for r in cursor.fetchall()}

        cursor.execute("SELECT institucion FROM config_tasas_salud")
        tasas_salud_cache = {r[0] for r in cursor.fetchall()}

        cursor.execute(
            """SELECT c.trabajador_id, c.tipo_afp, c.institucion_salud
               FROM contrato c WHERE c.estado = 'activo'"""
        )
        mapa_afp_salud = {tid: (afp, salud) for (tid, afp, salud) in cursor.fetchall()}

        for persona_id_t, trabajador_id_t, nombre_t in trabajadores:
            costo = calcular_costo_total_empleador(persona_id_t, periodo, payload, tasas_aporte_cache=tasas_aporte_cache)
            if not costo.get("success"):
                continue  # sin datos suficientes ese periodo, se omite

            total_imponible = costo["total_imponible_sin_tope"]
            sueldo_liquido = costo["sueldo_liquido_aproximado"]

            # ── Alerta 1: sueldo liquido bajo el minimo legal (IMM) ──
            if valor_imm is not None and sueldo_liquido < valor_imm:
                alertas.append({
                    "trabajador": nombre_t,
                    "tipo": "Sueldo bajo el mínimo legal",
                    "detalle": f"Sueldo líquido (${round(sueldo_liquido)}) es menor al IMM vigente (${round(valor_imm)})",
                    "accion_correctiva": "Revisar el sueldo base, descuentos o jornada del trabajador antes de cerrar la liquidación",
                })

            # ── Alerta 2: descuentos totales superan el 100% del imponible ──
            total_descuentos_varios = mapa_descuentos_varios.get(trabajador_id_t, 0.0)
            total_licencias = mapa_licencias.get(trabajador_id_t, 0.0)
            total_anticipos = mapa_anticipos.get(trabajador_id_t, 0.0)

            total_descuentos_generales = (
                costo["descuento_afp_trabajador"] + costo["descuento_salud_trabajador"]
                + costo["descuento_afc_trabajador"] + total_descuentos_varios
                + total_licencias + total_anticipos
            )

            if total_descuentos_generales > total_imponible:
                alertas.append({
                    "trabajador": nombre_t,
                    "tipo": "Descuentos superan el total imponible",
                    "detalle": f"Total de descuentos (${round(total_descuentos_generales)}) supera el 100% del total imponible (${total_imponible})",
                    "accion_correctiva": "Revisar y ajustar los descuentos, licencias o anticipos registrados para este trabajador y periodo",
                })

            # ── Alerta 5: tasa de AFP del trabajador sin configurar ──
            tipo_afp_t, institucion_salud_t = mapa_afp_salud.get(trabajador_id_t, (None, None))
            if tipo_afp_t and tipo_afp_t not in tasas_afp_cache:
                alertas.append({
                    "trabajador": nombre_t,
                    "tipo": "Tasa de AFP sin configurar",
                    "detalle": f"No hay una tasa configurada para la AFP '{tipo_afp_t}' de este trabajador",
                    "accion_correctiva": "Ir a Parámetros del Sistema → Tasas AFP, y agregar la tasa para esta AFP",
                })

            # ── Alerta 6: tasa de Institucion de Salud del trabajador sin configurar ──
            if institucion_salud_t and institucion_salud_t not in tasas_salud_cache:
                alertas.append({
                    "trabajador": nombre_t,
                    "tipo": "Tasa de Institución de Salud sin configurar",
                    "detalle": f"No hay una tasa configurada para la institución de salud '{institucion_salud_t}' de este trabajador",
                    "accion_correctiva": "Ir a Parámetros del Sistema → Tasas Salud, y agregar la tasa para esta institución",
                })

        cursor.close(); conn.close()

        # ── Alerta 4: conceptos sin clasificacion definida (nivel sistema) ──
        conn2 = get_connection()
        cursor2 = conn2.cursor()
        cursor2.execute("SELECT nombre FROM concepto_remuneracion WHERE clasificacion IS NULL OR clasificacion = ''")
        conceptos_sin_clasificar = cursor2.fetchall()
        cursor2.close(); conn2.close()

        for (nombre_concepto,) in conceptos_sin_clasificar:
            alertas.append({
                "trabajador": "—",
                "tipo": "Concepto sin clasificación",
                "detalle": f"El concepto '{nombre_concepto}' no tiene clasificación imponible/no imponible definida",
                "accion_correctiva": "Editar el concepto en Parametrización de Conceptos y definir su clasificación",
            })

        # ── Alerta 5: Movilizacion/Colacion del periodo sin confirmar (nivel sistema) ──
        conn3 = get_connection()
        cursor3 = conn3.cursor()
        cursor3.execute(
            "SELECT 1 FROM confirmacion_movilizacion_colacion WHERE periodo = %s",
            (periodo,)
        )
        movilizacion_confirmada = cursor3.fetchone() is not None
        cursor3.close(); conn3.close()

        if not movilizacion_confirmada:
            alertas.append({
                "trabajador": "—",
                "tipo": "Movilización/Colación sin confirmar",
                "detalle": f"El período {periodo} aún no tiene los montos de Movilización y Colación confirmados a nivel general. Los trabajadores sin un registro individual quedarán con $0 en este concepto.",
                "accion_correctiva": "Ir a Parámetros del Sistema → Movilización y Colación, y confirmar los montos para este período antes de cerrar",
            })

        # ── Alerta 6: IMM sin cargar para el periodo (nivel sistema) ──
        if valor_imm is None:
            alertas.append({
                "trabajador": "—",
                "tipo": "IMM sin cargar",
                "detalle": f"El período {periodo} no tiene un valor de Ingreso Mínimo Mensual (IMM) registrado. No se puede verificar si algún sueldo líquido queda bajo el mínimo legal, y el tope de la Gratificación Proporcional puede calcularse mal.",
                "accion_correctiva": "Ir a Parámetros del Sistema → Configuración de Gratificación, y cargar el valor IMM de este período",
            })

        # ── Alerta 7: UTM sin cargar para el periodo (nivel sistema) ──
        if obtener_valor_utm_periodo(periodo) is None:
            alertas.append({
                "trabajador": "—",
                "tipo": "UTM sin cargar",
                "detalle": f"El período {periodo} no tiene un valor de UTM registrado. El Impuesto Único de todos los trabajadores de este período no se puede calcular correctamente sin este valor.",
                "accion_correctiva": "Ir a Parámetros del Sistema → Valor UTM, y cargar el valor de este período",
            })

        # ── Alerta 8: UF sin cargar para el periodo (nivel sistema) ──
        mes_periodo_uf, anio_periodo_uf = (int(x) for x in periodo.split("/"))
        conn4 = get_connection()
        cursor4 = conn4.cursor()
        cursor4.execute(
            "SELECT 1 FROM config_valor_uf WHERE mes = %s AND anio = %s",
            (mes_periodo_uf, anio_periodo_uf)
        )
        uf_cargada = cursor4.fetchone() is not None
        cursor4.close(); conn4.close()

        if not uf_cargada:
            alertas.append({
                "trabajador": "—",
                "tipo": "UF sin cargar",
                "detalle": f"El período {periodo} no tiene un valor de UF registrado. Los topes de AFP/Salud y AFC (que se calculan en UF) no se pueden aplicar correctamente sin este valor.",
                "accion_correctiva": "Ir a Parámetros del Sistema → Valor UF, y cargar el valor de este período",
            })

        # ── Alerta 7: Aportes del Empleador (SIS, Expectativa de Vida, AFC, Capitalizacion) sin configurar (nivel sistema) ──
        if not tasas_aporte_cache:
            alertas.append({
                "trabajador": "—",
                "tipo": "Aportes del Empleador sin configurar",
                "detalle": "No hay ninguna tasa de Aportes del Empleador (SIS, Expectativa de Vida, AFC, Aporte Capitalización) configurada en el sistema. El Costo Total Empleador no se puede calcular sin estos valores.",
                "accion_correctiva": "Ir a Parámetros del Sistema → Aportes del Empleador, y configurar las tasas correspondientes",
            })

        # ── Alerta 8: tabla de tramos del Impuesto Unico sin configurar (nivel sistema) ──
        conn5 = get_connection()
        cursor5 = conn5.cursor()
        cursor5.execute("SELECT 1 FROM tabla_tramos_impuesto LIMIT 1")
        hay_tramos_impuesto = cursor5.fetchone() is not None
        cursor5.close(); conn5.close()

        if not hay_tramos_impuesto:
            alertas.append({
                "trabajador": "—",
                "tipo": "Tabla de tramos del Impuesto Único sin configurar",
                "detalle": "No hay ningún tramo de la tabla del Impuesto Único de Segunda Categoría configurado en el sistema. El Impuesto Único de todos los trabajadores no se puede calcular sin esta tabla.",
                "accion_correctiva": "Ir a Parámetros del Sistema → Impuesto Único, y configurar los tramos según la tabla vigente del SII",
            })

        return {"success": True, "periodo": periodo, "total_alertas": len(alertas), "alertas": alertas}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# BONO EXCEPCIONAL (con auditoria automatica)
# ══════════════════════════════════════════════════════════════

@app.post("/admin/bono-excepcional")
def registrar_bono_excepcional(data: BonoExcepcionalRequest, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        concepto = data.concepto.strip()
        if not (3 <= len(concepto) <= 100):
            return {"success": False, "mensaje": "El concepto debe tener entre 3 y 100 caracteres"}
        if data.monto_clp <= 0:
            return {"success": False, "mensaje": "El monto debe ser un entero positivo mayor a 0"}
        if data.monto_clp >= 10**9:
            return {"success": False, "mensaje": "El monto no puede superar 9 digitos"}
        if data.clasificacion not in ("Imponible", "No imponible"):
            return {"success": False, "mensaje": "Clasificacion invalida. Debe ser 'Imponible' o 'No imponible'"}

        (_, error_periodo) = validar_periodo_mm_aaaa(data.periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """SELECT t.trabajador_id, p.rut FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               WHERE t.persona_id = %s""",
            (data.persona_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        trabajador_id, rut_trabajador = r

        if verificar_liquidacion_cerrada(trabajador_id, data.periodo):
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se puede modificar esta liquidacion porque ya ha sido cerrada"}

        persona_id_admin = get_persona_id(payload)
        cursor.execute(
            """SELECT p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre_admin,
                      p.rut AS rut_admin, a.administrador_id
               FROM administrador a JOIN persona p ON p.persona_id = a.persona_id
               WHERE p.persona_id = %s""",
            (persona_id_admin,)
        )
        admin_row = cursor.fetchone()
        nombre_admin = (admin_row[0] if admin_row else "Administrador")[:120]
        rut_admin = admin_row[1] if admin_row else ""
        administrador_id = admin_row[2] if admin_row else None

        cursor.execute(
            """INSERT INTO bono_excepcional (trabajador_id, concepto, monto_clp, clasificacion, periodo, registrado_por)
               VALUES (%s, %s, %s, %s, %s, %s)
               RETURNING bono_id""",
            (trabajador_id, concepto, data.monto_clp, data.clasificacion, data.periodo, administrador_id)
        )
        bono_id = cursor.fetchone()[0]

        # ── Registro de auditoria automatico ──────────────────
        cursor.execute(
            """INSERT INTO log_auditoria
               (tabla_afectada, registro_id, tipo_de_operacion, campo_modificado,
                modulo, nombre_completo, informacion_personal, valor_nuevo, rut_administrador)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                "bono_excepcional",
                str(bono_id),
                "INSERT",
                "concepto, monto_clp, clasificacion",
                "Remuneraciones - Bono Excepcional",
                nombre_admin,
                f"RUT trabajador beneficiado: {rut_trabajador}",
                f"concepto={concepto}; monto=${data.monto_clp} CLP; clasificacion={data.clasificacion}; periodo={data.periodo}",
                rut_admin,
            )
        )

        # ── Pista de auditoria especifica (6 campos exactos) ──
        cursor.execute(
            """INSERT INTO auditoria_bono_descuento
               (administrador_id, nombre_administrador_historico, rut_administrador_historico,
                trabajador_id, rut_trabajador_historico, tipo_ajuste, concepto, monto_clp)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
            (administrador_id, nombre_admin, rut_admin, trabajador_id, rut_trabajador,
             "Bono", concepto[:100], int(data.monto_clp))
        )

        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Bono excepcional registrado correctamente", "bono_id": bono_id}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/bono-excepcional")
def listar_bono_excepcional(trabajador_id: int = None, periodo: str = None, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        query = """
            SELECT b.bono_id, b.concepto, b.monto_clp, b.clasificacion, b.periodo, b.fecha_registro,
                   p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut,
                   p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
            FROM bono_excepcional b
            JOIN trabajador t ON t.trabajador_id = b.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN administrador a ON a.administrador_id = b.registrado_por
            LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
            WHERE 1=1
        """
        params = []
        if trabajador_id:
            query += " AND b.trabajador_id = %s"
            params.append(trabajador_id)
        if periodo:
            query += " AND b.periodo = %s"
            params.append(periodo)
        query += " ORDER BY b.fecha_registro DESC"
        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "bonos": [
                {
                    "bono_id": r[0],
                    "concepto": r[1],
                    "monto_clp": int(r[2]),
                    "clasificacion": r[3],
                    "periodo": r[4],
                    "fecha_registro": r[5].strftime("%d/%m/%Y %H:%M:%S") if r[5] else "—",
                    "nombre_trabajador": r[6],
                    "rut": r[7],
                    "nombre_admin": r[8] or "—",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# DESGLOSE DE LIQUIDACION (visible para ADMIN y para el USUARIO)
# ══════════════════════════════════════════════════════════════

DESCRIPCIONES_CONCEPTOS = {
    "sueldo_base": "Remuneración base mensual pactada en el contrato de trabajo.",
    "bonos_imponibles": "Bonificaciones fijas o condicionales que sí generan cotizaciones previsionales y pagan impuesto (bonos imponibles, bonos condicionales cumplidos, bonos excepcionales imponibles).",
    "bonos_no_imponibles": "Montos que no generan cotizaciones previsionales ni impuesto: la parte exenta de movilización/colación y los bonos marcados como no imponibles.",
    "horas_extras": "Recargo del 50% sobre el valor de la hora ordinaria por horas trabajadas fuera de la jornada (Art. 32).",
    "excedente_no_imponible": "Parte de la movilización/colación que superó el tope legal exento y por eso pasa a tratarse como sueldo normal (imponible y tributable).",
    "gratificacion": "Gratificación legal (25% de sueldo base + horas extra + bonos imponibles, con tope de 4,75 IMM anuales). Es imponible: paga AFP, salud e impuesto igual que el resto del sueldo.",
    "descuento_afp": "Cotización previsional obligatoria descontada según la AFP del trabajador.",
    "descuento_salud": "Cotización de salud (Fonasa o Isapre) descontada mensualmente.",
    "descuento_afc": "Seguro de Cesantía (AFC): 0,6% si el contrato es Indefinido, 0% si es Plazo Fijo o Por obra.",
    "impuesto_unico": "Impuesto Único de Segunda Categoría, calculado según la tabla de tramos del SII sobre la base tributable.",
    "descuento_inasistencia_retraso": "Descuentos por inasistencias o atrasos registrados en el período.",
    "descuento_inasistencia": "Descuento por días no trabajados sin licencia médica ni permiso, calculado como sueldo diario × días de inasistencia.",
    "descuento_retraso": "Descuento por atrasos en la hora de llegada, calculado según el valor de la hora del trabajador.",
    "otros_descuentos": "Otros descuentos del período: préstamos, licencias médicas y anticipos de sueldo aprobados.",
    "descuento_prestamo": "Cuota del período de un préstamo interno o de la Caja de Compensación solicitado por el trabajador.",
    "descuento_licencia_medica": "Descuento proporcional a los días cubiertos por licencia médica en el período (no pagados directamente por la clínica).",
    "descuento_anticipo": "Anticipo de sueldo aprobado en el período, descontado del líquido a pagar.",
    "liquido_a_pagar": "Total de haberes menos el total de descuentos: lo que efectivamente recibe el trabajador.",
}


_UNIDADES = ["", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve"]
_ESPECIALES_10_19 = ["diez", "once", "doce", "trece", "catorce", "quince", "dieciséis", "diecisiete", "dieciocho", "diecinueve"]
_VEINTIS = ["veinte", "veintiuno", "veintidós", "veintitrés", "veinticuatro", "veinticinco", "veintiséis", "veintisiete", "veintiocho", "veintinueve"]
_DECENAS = ["", "", "veinte", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa"]
_CENTENAS = ["", "ciento", "doscientos", "trescientos", "cuatrocientos", "quinientos", "seiscientos", "setecientos", "ochocientos", "novecientos"]


def _grupo_a_palabras(n: int) -> str:
    """Convierte un numero de 0 a 999 a palabras."""
    if n == 0:
        return ""
    if n == 100:
        return "cien"
    palabras = []
    centena = n // 100
    resto = n % 100
    if centena > 0:
        palabras.append(_CENTENAS[centena])
    if resto > 0:
        if resto < 10:
            palabras.append(_UNIDADES[resto])
        elif resto < 20:
            palabras.append(_ESPECIALES_10_19[resto - 10])
        elif resto < 30:
            palabras.append(_VEINTIS[resto - 20])
        else:
            decena = resto // 10
            unidad = resto % 10
            if unidad == 0:
                palabras.append(_DECENAS[decena])
            else:
                palabras.append(f"{_DECENAS[decena]} y {_UNIDADES[unidad]}")
    return " ".join(palabras)


def numero_a_palabras_clp(monto: int) -> str:
    """
    Convierte un monto entero en CLP a su escritura en palabras,
    en español chileno (ej: 1.450.550 -> 'un millón cuatrocientos
    cincuenta mil quinientos cincuenta pesos').
    """
    monto = abs(int(round(monto)))
    if monto == 0:
        return "cero pesos"

    millones = monto // 1_000_000
    resto_millones = monto % 1_000_000
    miles = resto_millones // 1_000
    resto_miles = resto_millones % 1_000

    partes = []

    if millones > 0:
        if millones == 1:
            partes.append("un millón")
        else:
            partes.append(f"{_grupo_a_palabras(millones)} millones")

    if miles > 0:
        if miles == 1:
            partes.append("mil")
        else:
            partes.append(f"{_grupo_a_palabras(miles)} mil")

    if resto_miles > 0:
        partes.append(_grupo_a_palabras(resto_miles))

    if monto == 1:
        return "Un peso"

    texto = " ".join(partes).strip()
    # Apocope: "uno" se convierte en "un" cuando queda pegado a "pesos"
    # (un peso, veintiún... en realidad "veintiún" es otra excepcion,
    # pero para montos en CLP basta con la forma "un" mas comun)
    palabras_texto = texto.split(" ")
    if palabras_texto[-1] == "uno":
        palabras_texto[-1] = "un"
        texto = " ".join(palabras_texto)
    texto = texto[0].upper() + texto[1:] if texto else "Cero"
    # "un millón DE pesos" cuando es un multiplo exacto de millon
    # (sin miles ni resto); si hay mas numeros despues, no lleva "de"
    if millones > 0 and miles == 0 and resto_miles == 0:
        return f"{texto} de pesos"
    return f"{texto} pesos"


def _armar_desglose_liquidacion(persona_id: int, periodo: str) -> dict:
    (_, error_periodo) = validar_periodo_mm_aaaa(periodo)
    if error_periodo:
        return {"success": False, "mensaje": error_periodo}

    base = calcular_total_imponible_interno(persona_id, periodo)
    if not base.get("success"):
        # Cualquier motivo por el que no se pueda armar el desglose
        # (trabajador no encontrado, sin contrato activo, etc.) se le
        # muestra al usuario/admin con un mensaje unico y generico.
        return {"success": False, "mensaje": "La liquidación no se encuentra disponible por el momento."}

    trabajador_id = base["trabajador_id"]
    desglose_base = base["desglose"]

    conn = get_connection()
    cursor = conn.cursor()

    # Datos de cabecera del trabajador para el encabezado del desglose:
    # sueldo base completo del contrato, fecha de ingreso y cargo.
    cursor.execute(
        """SELECT c.sueldo_base, p.fecha_ingreso, p.cargo
           FROM contrato c
           JOIN trabajador t ON t.trabajador_id = c.trabajador_id
           JOIN persona p ON p.persona_id = t.persona_id
           WHERE c.trabajador_id = %s AND c.estado = 'activo'""",
        (trabajador_id,)
    )
    _r_cabecera = cursor.fetchone()
    sueldo_base_completo = round(float(_r_cabecera[0])) if (_r_cabecera and _r_cabecera[0]) else None
    fecha_ingreso_trabajador = _r_cabecera[1].strftime("%d/%m/%Y") if (_r_cabecera and _r_cabecera[1]) else None
    cargo_trabajador = _r_cabecera[2] if _r_cabecera else None

    # Bonos imponibles (bono_imponible + condicionales + excepcionales imponibles)
    bonos_imponibles_total = (
        desglose_base["bonos_imponibles_total"]
        + desglose_base["bonos_condicionales_imponibles_total"]
        + desglose_base["bono_excepcional_imponible_total"]
    )

    # Bonos NO imponibles: exento de movilizacion/colacion + condicionales/excepcionales no imponibles.
    # Usa el mismo colacion_total/locomocion_total ya calculado (y neto
    # de dias de inasistencia/licencia) en el motor central -- antes
    # esto se recalculaba aqui por separado usando los dias brutos del
    # proporcional, lo que descuadraba contra Total Haberes.
    monto_exento_no_imponible = (
        desglose_base["colacion_total"] + desglose_base["locomocion_total"]
    )
    bonos_no_imponibles_total = (
        monto_exento_no_imponible
        + desglose_base["bonos_condicionales_no_imponibles_total"]
        + desglose_base["bono_excepcional_no_imponible_total"]
    )

    # Descuentos por inasistencia y retraso del periodo, POR SEPARADO
    cursor.execute(
        "SELECT COALESCE(SUM(monto_clp), 0) FROM descuento WHERE trabajador_id = %s AND periodo = %s AND tipo_descuento = 'Inasistencia'",
        (trabajador_id, periodo)
    )
    descuento_inasistencia = int(cursor.fetchone()[0])
    cursor.execute(
        "SELECT COALESCE(SUM(monto_clp), 0) FROM descuento WHERE trabajador_id = %s AND periodo = %s AND tipo_descuento = 'Retraso'",
        (trabajador_id, periodo)
    )
    descuento_retraso = int(cursor.fetchone()[0])
    descuento_inasistencia_retraso = descuento_inasistencia + descuento_retraso

    # Prestamo, Licencia medica y Anticipo de sueldo, POR SEPARADO
    # (antes se sumaban juntos en "otros descuentos" sin distinguir)
    cursor.execute(
        "SELECT COALESCE(SUM(monto_clp), 0) FROM descuento WHERE trabajador_id = %s AND periodo = %s AND tipo_descuento = 'Prestamo'",
        (trabajador_id, periodo)
    )
    descuento_prestamo = round(float(cursor.fetchone()[0]))
    cursor.execute(
        "SELECT COALESCE(SUM(descuento_proporcional), 0) FROM licencia_medica WHERE trabajador_id = %s AND periodo = %s",
        (trabajador_id, periodo)
    )
    descuento_licencia_medica = round(float(cursor.fetchone()[0]))
    cursor.execute(
        "SELECT COALESCE(SUM(monto_clp), 0) FROM anticipo_sueldo WHERE trabajador_id = %s AND periodo = %s AND estado = 'aprobado'",
        (trabajador_id, periodo)
    )
    descuento_anticipo = round(float(cursor.fetchone()[0]))
    # Licencia Medica ya NO se suma a "otros descuentos": su efecto ya
    # esta reflejado en el sueldo base reducido (se paga solo por los
    # dias efectivamente trabajados). Sumarla de nuevo aqui duplicaria
    # el descuento.
    otros_descuentos = descuento_prestamo + descuento_anticipo

    cursor.close(); conn.close()

    # AFP / Salud
    afp_salud = calcular_afp_salud(persona_id, periodo, {"rol": "admin", "sub": "", "cuenta_id": 0, "persona_id": persona_id})
    if not afp_salud.get("success"):
        descuento_afp = 0
        descuento_salud = 0
        total_imponible_afp_salud = None
    else:
        descuento_afp = afp_salud["descuento_afp"]
        descuento_salud = afp_salud["descuento_salud"]
        total_imponible_afp_salud = afp_salud["total_imponible_afp_salud"]

    # AFC del trabajador (faltaba en este desglose; ya se restaba
    # correctamente en Costo Total Empleador y en el Cierre)
    afc = calcular_afc(persona_id, periodo, {"rol": "admin", "sub": "", "cuenta_id": 0, "persona_id": persona_id})
    descuento_afc = afc["descuento_trabajador"] if afc.get("success") else 0
    total_imponible_afc = afc["total_imponible_afc"] if afc.get("success") else None

    # Total Tributable (base sin tope - AFP - Salud - AFC)
    tributable = _calcular_total_tributable(persona_id, periodo, {"rol": "admin", "sub": "", "cuenta_id": 0, "persona_id": persona_id})
    total_tributable = tributable["total_tributable"] if tributable.get("success") else None

    # Impuesto unico (puede no estar disponible si falta la UTM del periodo)
    impuesto = calcular_impuesto_unico(persona_id, periodo, {"rol": "admin", "sub": "", "cuenta_id": 0, "persona_id": persona_id})
    impuesto_unico = impuesto["impuesto_unico"] if impuesto.get("success") else 0
    impuesto_disponible = impuesto.get("success", False)

    sueldo_base = desglose_base["sueldo_base_considerado"]
    horas_extras = desglose_base["horas_extra_total"]
    excedente_no_imponible = desglose_base["excedente_no_imponible_total"]
    gratificacion = desglose_base["gratificacion_total"]
    descuento_atraso = desglose_base["descuento_atraso_total"]
    horas_atraso_total = desglose_base["horas_atraso_total"]

    total_haberes = sueldo_base + bonos_imponibles_total + bonos_no_imponibles_total + horas_extras + excedente_no_imponible + gratificacion - descuento_atraso
    # El atraso ya se resto DIRECTO de Total Haberes (linea de arriba).
    # Inasistencia y Licencia Medica TAMPOCO se restan aqui: su efecto
    # ya esta reflejado en el sueldo base reducido, que se paga solo
    # por los dias efectivamente trabajados (dias_a_pagar). Restarlas
    # de nuevo aqui duplicaria el descuento.
    total_descuentos = descuento_afp + descuento_salud + descuento_afc + impuesto_unico + otros_descuentos
    liquido_a_pagar = max(0, round(total_haberes - total_descuentos))

    return {
        "success": True,
        "nombre": base["nombre"],
        "rut": base["rut"],
        "periodo": periodo,
        "sueldo_base_completo": sueldo_base_completo,
        "fecha_ingreso": fecha_ingreso_trabajador,
        "cargo": cargo_trabajador,
        "impuesto_disponible": impuesto_disponible,
        "bases_calculo": {
            "total_imponible_afp_salud": total_imponible_afp_salud,
            "total_imponible_afc": total_imponible_afc,
            "total_tributable": total_tributable,
        },
        "items": {
            "sueldo_base": sueldo_base,
            "bonos_imponibles": bonos_imponibles_total,
            "bonos_no_imponibles": bonos_no_imponibles_total,
            "movilizacion_colacion": monto_exento_no_imponible,
            "bonos_no_imponibles_otros": (
                desglose_base["bonos_condicionales_no_imponibles_total"]
                + desglose_base["bono_excepcional_no_imponible_total"]
            ),
            "horas_extras": horas_extras,
            "excedente_no_imponible": excedente_no_imponible,
            "gratificacion": gratificacion,
            "descuento_atraso": descuento_atraso,
            "descuento_afp": descuento_afp,
            "descuento_salud": descuento_salud,
            "descuento_afc": descuento_afc,
            "impuesto_unico": impuesto_unico,
            "descuento_inasistencia_retraso": descuento_inasistencia,
            "descuento_inasistencia": descuento_inasistencia,
            "descuento_retraso": descuento_retraso,
            "otros_descuentos": otros_descuentos,
            "descuento_prestamo": descuento_prestamo,
            "descuento_licencia_medica": descuento_licencia_medica,
            "descuento_anticipo": descuento_anticipo,
        },
        "detalle_haberes": {
            "es_proporcional": desglose_base["es_proporcional"],
            "detalle_proporcional": desglose_base["detalle_proporcional"],
            "horas_extra_horas": desglose_base["horas_extra_horas"],
            "horas_atraso_total": desglose_base["horas_atraso_total"],
            "detalle_bonos_imponibles": desglose_base["detalle_bonos_imponibles"],
            "detalle_bono_excepcional": desglose_base["detalle_bono_excepcional"],
            "colacion_total": desglose_base["colacion_total"],
            "locomocion_total": desglose_base["locomocion_total"],
            "origen_movilizacion_colacion": desglose_base["origen_movilizacion_colacion"],
        },
        "total_haberes": round(total_haberes),
        "total_descuentos": round(total_descuentos),
        "liquido_a_pagar": liquido_a_pagar,
        "liquido_a_pagar_palabras": numero_a_palabras_clp(liquido_a_pagar),
        "descripciones": DESCRIPCIONES_CONCEPTOS,
    }


@app.get("/admin/desglose-liquidacion")
def desglose_liquidacion_admin(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        return _armar_desglose_liquidacion(persona_id, periodo)
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/detalle-calculo-liquidacion")
def detalle_calculo_liquidacion(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    """
    #26: Devuelve la "foto" guardada del detalle de calculo de una
    liquidacion ya CERRADA — valores de entrada, formula/regla usada
    (con referencia legal si corresponde), y el resultado en CLP,
    tal cual quedaron registrados al momento del cierre.
    """
    try:
        verificar_rol(payload, ["admin"])
        (_, error_periodo) = validar_periodo_mm_aaaa(periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT l.liquidacion_id, p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut, l.fecha_cierre
               FROM liquidacion l
               JOIN trabajador t ON t.trabajador_id = l.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               WHERE p.persona_id = %s AND l.periodo = %s AND l.estado = 'cerrada'
               ORDER BY l.liquidacion_id DESC LIMIT 1""",
            (persona_id, periodo)
        )
        liq_row = cursor.fetchone()
        if not liq_row:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No hay una liquidación cerrada para este trabajador en este período"}
        liquidacion_id, nombre, rut, fecha_cierre = liq_row

        cursor.execute(
            """SELECT concepto, valores_entrada, formula_regla, referencia_legal, resultado_clp
               FROM detalle_calculo_liquidacion
               WHERE liquidacion_id = %s
               ORDER BY detalle_id""",
            (liquidacion_id,)
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        return {
            "success": True,
            "liquidacion_id": liquidacion_id,
            "nombre": nombre,
            "rut": rut,
            "periodo": periodo,
            "fecha_cierre": fecha_cierre.strftime("%d/%m/%Y %H:%M") if fecha_cierre else "—",
            "detalle": [
                {
                    "concepto": r[0],
                    "valores_entrada": r[1],
                    "formula_regla": r[2],
                    "referencia_legal": r[3],
                    "resultado_clp": r[4],
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# #8 — LEY 19.628: SOLICITUD DE CORRECCION/ELIMINACION DE DATOS
# ══════════════════════════════════════════════════════════════

@app.post("/mis-datos/solicitud")
def crear_solicitud_datos(data: SolicitudDatosRequest, payload: dict = Depends(verificar_token)):
    """
    Permite a cualquier USUARIO (o ADMINISTRADOR sobre sus propios
    datos) solicitar la correccion o eliminacion de su informacion
    personal, en conformidad con la Ley 19.628. La solicitud queda
    pendiente de revision — no se ejecuta automaticamente, ya que
    corregir/eliminar datos de nomina o previsionales requiere
    verificacion humana (obligaciones tributarias, historial legal).
    """
    try:
        if data.tipo_solicitud not in ("Correccion", "Eliminacion"):
            return {"success": False, "mensaje": "Tipo de solicitud inválido. Debe ser Corrección o Eliminación"}
        if not data.detalle or len(data.detalle.strip()) < 5:
            return {"success": False, "mensaje": "Describe con más detalle tu solicitud"}

        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO solicitud_datos_personales (persona_id, tipo_solicitud, campo_afectado, detalle)
               VALUES (%s, %s, %s, %s) RETURNING solicitud_datos_id""",
            (persona_id, data.tipo_solicitud, data.campo_afectado, data.detalle.strip())
        )
        solicitud_id = cursor.fetchone()[0]
        conn.commit(); cursor.close(); conn.close()
        return {
            "success": True,
            "mensaje": "Tu solicitud fue registrada correctamente y será revisada por un administrador",
            "solicitud_id": solicitud_id,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/mis-datos/solicitudes")
def ver_mis_solicitudes_datos(payload: dict = Depends(verificar_token)):
    """El propio titular puede ver el estado de sus solicitudes."""
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT solicitud_datos_id, tipo_solicitud, campo_afectado, detalle, estado,
                      respuesta_admin, fecha_solicitud, fecha_respuesta
               FROM solicitud_datos_personales WHERE persona_id = %s
               ORDER BY fecha_solicitud DESC""",
            (persona_id,)
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "solicitudes": [
                {
                    "solicitud_id": r[0], "tipo_solicitud": r[1], "campo_afectado": r[2],
                    "detalle": r[3], "estado": r[4], "respuesta_admin": r[5],
                    "fecha_solicitud": r[6].strftime("%d/%m/%Y %H:%M") if r[6] else "—",
                    "fecha_respuesta": r[7].strftime("%d/%m/%Y %H:%M") if r[7] else None,
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/solicitudes-datos")
def listar_solicitudes_datos_admin(estado: str = None, payload: dict = Depends(verificar_token)):
    """El administrador ve todas las solicitudes, para poder revisarlas."""
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        query = """SELECT s.solicitud_datos_id, s.tipo_solicitud, s.campo_afectado, s.detalle, s.estado,
                          s.fecha_solicitud, p.primer_nombre || ' ' || p.apellido_paterno AS nombre, p.rut
                   FROM solicitud_datos_personales s
                   JOIN persona p ON p.persona_id = s.persona_id
                   WHERE 1=1"""
        params = []
        if estado:
            query += " AND s.estado = %s"
            params.append(estado)
        query += " ORDER BY s.fecha_solicitud DESC"
        cursor.execute(query, params)
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "solicitudes": [
                {
                    "solicitud_id": r[0], "tipo_solicitud": r[1], "campo_afectado": r[2],
                    "detalle": r[3], "estado": r[4],
                    "fecha_solicitud": r[5].strftime("%d/%m/%Y %H:%M") if r[5] else "—",
                    "nombre": r[6], "rut": r[7],
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.put("/admin/solicitudes-datos/resolver")
def resolver_solicitud_datos(data: ResolverSolicitudDatosRequest, payload: dict = Depends(verificar_token)):
    """El administrador aprueba o rechaza una solicitud, dejando constancia de su decisión."""
    try:
        verificar_rol(payload, ["admin"])
        if data.estado not in ("Aprobada", "Rechazada"):
            return {"success": False, "mensaje": "Estado inválido. Debe ser Aprobada o Rechazada"}

        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin_row = cursor.fetchone()
        administrador_id = admin_row[0] if admin_row else None

        cursor.execute(
            """UPDATE solicitud_datos_personales
               SET estado = %s, respuesta_admin = %s, fecha_respuesta = NOW(), resuelta_por = %s
               WHERE solicitud_datos_id = %s""",
            (data.estado, data.respuesta_admin, administrador_id, data.solicitud_id)
        )
        if cursor.rowcount == 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Solicitud no encontrada"}
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Solicitud marcada como '{data.estado}'"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/mi-desglose-liquidacion")
def mi_desglose_liquidacion(periodo: str, payload: dict = Depends(verificar_token)):
    """
    Version para el propio USUARIO (trabajador): usa su persona_id
    tomado del token, no requiere rol admin.
    """
    try:
        persona_id = get_persona_id(payload)
        return _armar_desglose_liquidacion(persona_id, periodo)
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# INFORME DE REMUNERACIONES (exportable a Excel y PDF)
# ══════════════════════════════════════════════════════════════

def _obtener_datos_informe_remuneraciones(persona_id: int, periodo: str) -> dict:
    """
    Arma las 7 columnas exactas que pide el informe de remuneraciones:
    Sueldo base | Bonos no imponibles | Bonos imponibles |
    Deducciones previsionales | Impuesto unico | Otras deducciones |
    Monto neto a pagar.

    Reutiliza el desglose de liquidacion, que ya incluye el AFC del
    trabajador dentro de items['descuento_afc'].
    """
    desglose = _armar_desglose_liquidacion(persona_id, periodo)
    if not desglose.get("success"):
        return desglose

    items = desglose["items"]

    sueldo_base = items["sueldo_base"]
    bonos_no_imponibles = items["bonos_no_imponibles"]
    # Bonos sujetos a impuesto: bonos imponibles + horas extras + el
    # excedente de movilizacion/colacion que supero el tope exento
    # (ambas son haberes imponibles distintos del sueldo base; el
    # informe solo pide 7 columnas, asi que se agrupan aqui)
    bonos_imponibles = items["bonos_imponibles"] + items["horas_extras"] + items["excedente_no_imponible"] + items["gratificacion"]

    deducciones_previsionales = items["descuento_afp"] + items["descuento_salud"] + items["descuento_afc"]
    impuesto_unico = items["impuesto_unico"]
    otras_deducciones = items["descuento_inasistencia_retraso"] + items["otros_descuentos"]

    monto_neto = round(
        sueldo_base + bonos_no_imponibles + bonos_imponibles
        - deducciones_previsionales - impuesto_unico - otras_deducciones
    )
    if monto_neto < 0:
        monto_neto = 0

    return {
        "success": True,
        "nombre": desglose["nombre"],
        "rut": desglose["rut"],
        "periodo": periodo,
        "sueldo_base": round(sueldo_base),
        "bonos_no_imponibles": round(bonos_no_imponibles),
        "bonos_imponibles": round(bonos_imponibles),
        "deducciones_previsionales": round(deducciones_previsionales),
        "impuesto_unico": round(impuesto_unico),
        "otras_deducciones": round(otras_deducciones),
        "monto_neto_a_pagar": monto_neto,
    }


@app.get("/admin/informe-consolidado-remuneraciones")
def informe_consolidado_remuneraciones(periodo: str, payload: dict = Depends(verificar_token)):
    """
    Informe consolidado de remuneraciones (RF-45): UNA fila por cada
    trabajador activo con contrato vigente ese periodo, mostrando su
    costo para el empleado (lo que se le descuenta) al lado de su
    costo para el empleador (Total Haberes + aportes patronales), mas
    el total general del periodo.

    Excepcion 2: si no existe NINGUN trabajador con datos calculables
    para el periodo (nadie tiene liquidacion/costo disponible ese
    mes), no genera el informe y avisa que no hay datos.
    """
    try:
        verificar_rol(payload, ["admin"])

        (_, error_periodo) = validar_periodo_mm_aaaa(periodo)
        if error_periodo:
            return {"success": False, "mensaje": error_periodo}

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT p.persona_id, p.rut,
                      p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre
               FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE p.activo = TRUE AND c.sueldo_base IS NOT NULL AND c.sueldo_base > 0
               ORDER BY p.apellido_paterno, p.primer_nombre"""
        )
        trabajadores = cursor.fetchall()

        cursor.execute("SELECT concepto, tasa_porcentaje FROM config_aportes_empleador")
        tasas_aporte_cache = {r[0]: float(r[1]) for r in cursor.fetchall()}
        cursor.close(); conn.close()

        filas = []
        total_costo_trabajador_general = 0
        total_costo_empleador_general = 0

        for persona_id_t, rut_t, nombre_t in trabajadores:
            costo = calcular_costo_total_empleador(persona_id_t, periodo, payload, tasas_aporte_cache=tasas_aporte_cache)
            if not costo.get("success"):
                continue  # sin datos suficientes ese trabajador/periodo, se omite

            filas.append({
                "persona_id": persona_id_t,
                "rut": rut_t,
                "nombre": nombre_t,
                "costo_trabajador": costo["costo_total_trabajador"],
                "costo_empleador": costo["costo_total_empleador"],
                "diferencia": costo["costo_total_empleador"] - costo["costo_total_trabajador"],
            })
            total_costo_trabajador_general += costo["costo_total_trabajador"]
            total_costo_empleador_general += costo["costo_total_empleador"]

        if not filas:
            return {
                "success": False,
                "mensaje": f"No existen liquidaciones disponibles para el período {periodo}. No se generó el informe."
            }

        return {
            "success": True,
            "periodo": periodo,
            "cantidad_trabajadores": len(filas),
            "filas": filas,
            "total_costo_trabajador_general": round(total_costo_trabajador_general),
            "total_costo_empleador_general": round(total_costo_empleador_general),
            "total_general_palabras": numero_a_palabras_clp(round(total_costo_empleador_general)),
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/informe-remuneraciones")
def ver_informe_remuneraciones(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        return _obtener_datos_informe_remuneraciones(persona_id, periodo)
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/informe-remuneraciones/excel")
def exportar_informe_excel(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        datos = _obtener_datos_informe_remuneraciones(persona_id, periodo)
        if not datos.get("success"):
            return datos

        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "Informe Remuneraciones"

        azul_oscuro = PatternFill(start_color="001E42", end_color="001E42", fill_type="solid")
        fuente_blanca_negrita = Font(color="FFFFFF", bold=True, size=11)
        borde = Border(*[Side(style="thin", color="E2E8F0")] * 4)

        ws["A1"] = "CLINICA ACONCAGUA — INFORME DE REMUNERACIONES"
        ws["A1"].font = Font(bold=True, size=14, color="001E42")
        ws.merge_cells("A1:G1")

        ws["A2"] = f"Trabajador: {datos['nombre']} ({datos['rut']})"
        ws["A3"] = f"Periodo: {periodo}"
        ws.merge_cells("A2:G2")
        ws.merge_cells("A3:G3")

        encabezados = [
            "Sueldo base", "Bonos no sujetos a impuestos", "Bonos sujetos a impuestos",
            "Deducciones previsionales", "Impuesto unico", "Otras deducciones", "Monto neto a pagar",
        ]
        fila_encabezado = 5
        for col, titulo in enumerate(encabezados, start=1):
            celda = ws.cell(row=fila_encabezado, column=col, value=titulo)
            celda.fill = azul_oscuro
            celda.font = fuente_blanca_negrita
            celda.alignment = Alignment(horizontal="center", wrap_text=True)
            celda.border = borde

        valores = [
            datos["sueldo_base"], datos["bonos_no_imponibles"], datos["bonos_imponibles"],
            datos["deducciones_previsionales"], datos["impuesto_unico"], datos["otras_deducciones"],
            datos["monto_neto_a_pagar"],
        ]
        for col, valor in enumerate(valores, start=1):
            celda = ws.cell(row=fila_encabezado + 1, column=col, value=valor)
            celda.number_format = "#,##0"
            celda.alignment = Alignment(horizontal="center")
            celda.border = borde
            if col == 7:
                celda.font = Font(bold=True, color="059669")

        for col in range(1, 8):
            ws.column_dimensions[chr(64 + col)].width = 20

        buffer = io.BytesIO()
        wb.save(buffer)
        excel_bytes = buffer.getvalue()
        buffer.close()

        periodo_archivo = periodo.replace("/", "-")
        return Response(
            content=excel_bytes,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f"attachment; filename=informe_remuneraciones_{datos['rut']}_{periodo_archivo}.xlsx"}
        )
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/informe-remuneraciones/pdf")
def exportar_informe_pdf(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        datos = _obtener_datos_informe_remuneraciones(persona_id, periodo)
        if not datos.get("success"):
            return datos

        buffer = io.BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=letter, topMargin=inch, bottomMargin=inch, leftMargin=inch, rightMargin=inch)
        styles = getSampleStyleSheet()
        story = []
        story.append(Paragraph("CLINICA ACONCAGUA", styles['Title']))
        story.append(Paragraph("INFORME DE REMUNERACIONES", styles['Heading2']))
        story.append(Spacer(1, 12))
        story.append(Paragraph(f"Trabajador: {datos['nombre']} ({datos['rut']})", styles['Normal']))
        story.append(Paragraph(f"Periodo: {periodo}", styles['Normal']))
        story.append(Spacer(1, 20))

        data_tabla = [
            ["Concepto", "Monto (CLP)"],
            ["Sueldo base", f"${datos['sueldo_base']:,}".replace(",", ".")],
            ["Bonos no sujetos a impuestos", f"${datos['bonos_no_imponibles']:,}".replace(",", ".")],
            ["Bonos sujetos a impuestos", f"${datos['bonos_imponibles']:,}".replace(",", ".")],
            ["Deducciones previsionales", f"${datos['deducciones_previsionales']:,}".replace(",", ".")],
            ["Impuesto unico", f"${datos['impuesto_unico']:,}".replace(",", ".")],
            ["Otras deducciones", f"${datos['otras_deducciones']:,}".replace(",", ".")],
            ["MONTO NETO A PAGAR", f"${datos['monto_neto_a_pagar']:,}".replace(",", ".")],
        ]

        tabla = Table(data_tabla, colWidths=[3.5*inch, 2.5*inch])
        tabla.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#001E42')),
            ('TEXTCOLOR', (0,0), (-1,0), colors.white),
            ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
            ('FONTNAME', (0,-1), (-1,-1), 'Helvetica-Bold'),
            ('BACKGROUND', (0,-1), (-1,-1), colors.HexColor('#ECFDF5')),
            ('TEXTCOLOR', (0,-1), (-1,-1), colors.HexColor('#059669')),
            ('FONTSIZE', (0,0), (-1,-1), 11),
            ('ROWBACKGROUNDS', (0,1), (-1,-2), [colors.white, colors.HexColor('#F8FAFC')]),
            ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor('#E2E8F0')),
            ('PADDING', (0,0), (-1,-1), 8),
        ]))
        story.append(tabla)
        story.append(Spacer(1, 30))
        story.append(Paragraph("Este documento es un informe oficial de remuneraciones generado por el sistema.", styles['Normal']))
        doc.build(story)
        pdf_bytes = buffer.getvalue()
        buffer.close()

        periodo_archivo = periodo.replace("/", "-")
        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename=informe_remuneraciones_{datos['rut']}_{periodo_archivo}.pdf"}
        )
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ══════════════════════════════════════════════════════════════
# PANEL DE LIQUIDACION COMPLETA (vista consolidada tipo Talana)
# ══════════════════════════════════════════════════════════════

@app.get("/admin/panel-liquidacion-completa")
def panel_liquidacion_completa(persona_id: int, periodo: str, payload: dict = Depends(verificar_token)):
    """
    Junta en una sola respuesta todo lo que ya calculamos por
    separado (desglose, costo empleador) mas el detalle itemizado
    de cada concepto registrado para ese trabajador/periodo, para
    mostrarlo todo en un solo panel sin repetir logica de calculo.
    """
    try:
        verificar_rol(payload, ["admin"])

        desglose = _armar_desglose_liquidacion(persona_id, periodo)
        if not desglose.get("success"):
            return desglose

        costo = calcular_costo_total_empleador(persona_id, periodo, payload)

        trabajador_id = None
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id,))
        r = cursor.fetchone()
        if r:
            trabajador_id = r[0]

        estado_liquidacion = {"cerrada": False, "fecha_cierre": None}
        if trabajador_id:
            cursor.execute(
                """SELECT estado, fecha_cierre FROM liquidacion
                   WHERE trabajador_id = %s AND periodo = %s AND tipo_liquidacion = 'normal'
                   ORDER BY liquidacion_id DESC LIMIT 1""",
                (trabajador_id, periodo)
            )
            liq_row = cursor.fetchone()
            if liq_row and liq_row[0] == 'cerrada':
                estado_liquidacion = {
                    "cerrada": True,
                    "fecha_cierre": liq_row[1].strftime("%d/%m/%Y %H:%M") if liq_row[1] else None,
                }

        itemizado = {}
        if trabajador_id:
            cursor.execute(
                "SELECT tipo_descuento, monto_clp, fecha_evento FROM descuento WHERE trabajador_id = %s AND periodo = %s",
                (trabajador_id, periodo)
            )
            itemizado["descuentos"] = [
                {"tipo": t, "monto": int(m), "fecha": f.strftime("%d/%m/%Y") if f else "—"}
                for (t, m, f) in cursor.fetchall()
            ]

            cursor.execute(
                "SELECT tipo_bono, monto_clp FROM bono_imponible WHERE trabajador_id = %s AND periodo = %s",
                (trabajador_id, periodo)
            )
            itemizado["bonos_imponibles"] = [{"tipo": t, "monto": int(m)} for (t, m) in cursor.fetchall()]

            cursor.execute(
                "SELECT concepto, monto_clp, clasificacion FROM bono_excepcional WHERE trabajador_id = %s AND periodo = %s",
                (trabajador_id, periodo)
            )
            itemizado["bonos_excepcionales"] = [
                {"concepto": c, "monto": int(m), "clasificacion": cl}
                for (c, m, cl) in cursor.fetchall()
            ]

            cursor.execute(
                """SELECT br.nombre_concepto, ab.monto_aplicado, ab.cumple_condicion, br.clasificacion
                   FROM aplicacion_bono_regla ab JOIN bono_regla br ON br.bono_id = ab.bono_id
                   WHERE ab.trabajador_id = %s AND ab.periodo = %s""",
                (trabajador_id, periodo)
            )
            itemizado["bonos_condicionales"] = [
                {"concepto": c, "monto": int(m), "cumple": cu, "clasificacion": cl}
                for (c, m, cu, cl) in cursor.fetchall()
            ]

            cursor.execute(
                "SELECT tipo_de_licencia, descuento_proporcional, fecha_inicio, fecha_fin FROM licencia_medica WHERE trabajador_id = %s AND periodo = %s",
                (trabajador_id, periodo)
            )
            itemizado["licencias"] = [
                {"tipo": t, "monto": int(m), "inicio": fi.strftime("%d/%m/%Y") if fi else "—", "fin": ff.strftime("%d/%m/%Y") if ff else "—"}
                for (t, m, fi, ff) in cursor.fetchall()
            ]

            cursor.execute(
                "SELECT cantidad_horas, valor_hora_ordinaria FROM horas_extras WHERE trabajador_id = %s AND periodo = %s",
                (trabajador_id, periodo)
            )
            itemizado["horas_extras"] = [
                {"cantidad_horas": float(h), "valor_hora_extra": round(float(v) * 1.5, 4)}
                for (h, v) in cursor.fetchall()
            ]

            cursor.execute(
                "SELECT monto_clp, folio_autorizacion, estado FROM anticipo_sueldo WHERE trabajador_id = %s AND periodo = %s",
                (trabajador_id, periodo)
            )
            itemizado["anticipos"] = [
                {"monto": int(m), "folio": f, "estado": e}
                for (m, f, e) in cursor.fetchall()
            ]

            cursor.execute(
                "SELECT concepto, monto_total_mensual, monto_exento, monto_excedente FROM asignacion_no_imponible WHERE trabajador_id = %s AND periodo = %s",
                (trabajador_id, periodo)
            )
            itemizado["movilizacion_colacion"] = [
                {"concepto": c, "monto_total": int(mt), "exento": int(me), "excedente": int(mx)}
                for (c, mt, me, mx) in cursor.fetchall()
            ]
            if not itemizado["movilizacion_colacion"]:
                cursor.execute(
                    "SELECT monto_movilizacion, monto_colacion FROM confirmacion_movilizacion_colacion WHERE periodo = %s",
                    (periodo,)
                )
                confirmacion_row = cursor.fetchone()
                if confirmacion_row:
                    itemizado["movilizacion_colacion"] = [
                        {"concepto": "Movilizacion", "monto_total": int(confirmacion_row[0]), "exento": int(confirmacion_row[0]), "excedente": 0},
                        {"concepto": "Colacion", "monto_total": int(confirmacion_row[1]), "exento": int(confirmacion_row[1]), "excedente": 0},
                    ]

        cursor.close(); conn.close()

        return {
            "success": True,
            "resumen": desglose,
            "costo_empleador": costo if costo.get("success") else None,
            "estado_liquidacion": estado_liquidacion,
            "itemizado": itemizado,
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── ADMIN: ALERTAS ARTICULO 70 (feriado acumulado) ────────────
@app.get("/admin/alertas-articulo-70")
def get_alertas_articulo_70(payload: dict = Depends(verificar_token)):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT t.trabajador_id,
                      p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre,
                      p.cargo, p.fecha_ingreso,
                      t.meses_cotizados_previos,
                      sv.dias_acumulados, sv.dias_utilizados
               FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN saldo_vacaciones sv ON sv.trabajador_id = t.trabajador_id
               WHERE p.activo = TRUE"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        alertas = []
        for r in rows:
            (trabajador_id, nombre, cargo, fecha_ingreso, meses_previos,
             dias_acumulados, dias_utilizados) = r

            saldo = calcular_saldo_normal_disponible(fecha_ingreso, meses_previos, dias_acumulados, dias_utilizados)
            art70 = calcular_periodos_articulo_70(saldo)

            if art70["alerta_articulo_70"]:
                alertas.append({
                    "trabajador_id":         trabajador_id,
                    "nombre":                nombre or "",
                    "cargo":                 cargo or "—",
                    "periodos_acumulados":   art70["periodos_acumulados"],
                    "bloqueado":             art70["bloqueo_articulo_70"],
                    "dias_disponibles":      saldo,
                })

        alertas.sort(key=lambda a: a["periodos_acumulados"], reverse=True)
        return {"success": True, "alertas": alertas, "count": len(alertas)}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


# ── RECIBO PDF VACACIONES ─────────────────────────────────────
@app.get("/vacaciones/recibo/{id_solicitud}")
def generar_recibo_pdf(id_solicitud: int, payload: dict = Depends(verificar_token)):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT sv.fecha_inicio, sv.fecha_fin, sv.dias_habiles, sv.tipo_dias,
                      sv.estado, sv.observacion, sv.fecha_decision,
                      p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno,
                      p.rut, p.fecha_ingreso,
                      t.meses_cotizados_previos,
                      sal.dias_acumulados, sal.dias_utilizados, sal.dias_progresivos,
                      p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
               FROM solicitud_vacaciones sv
               JOIN trabajador t ON t.trabajador_id = sv.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN saldo_vacaciones sal ON sal.trabajador_id = t.trabajador_id
               LEFT JOIN administrador a ON a.administrador_id = sv.revisado_por
               LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
               WHERE sv.solicitud_id = %s""",
            (id_solicitud,)
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()

        if not r or r[4] != 'Aprobada':
            return {"success": False, "mensaje": "Recibo no disponible"}

        (fi, ff, dias, tipo_dias, estado, obs, fs, nombre, rut, fecha_ingreso,
         meses_previos, dias_acumulados, dias_utilizados, dias_progresivos, nombre_admin) = r

        tipo_dias = tipo_dias or 'normal'

        # FIX: usar el saldo real (misma fuente que /mi-balance-vacaciones y
        # el panel de admin) en vez de la columna dias_disponibles, que ya
        # no refleja el saldo real una vez que existen solicitudes normales.
        if tipo_dias == 'progresivo':
            # dias_progresivos ya viene neto (post-aprobacion, porque el
            # UPDATE de aprobacion ya se ejecuto antes de generar el PDF)
            saldo_post = int(dias_progresivos or 0)
        else:
            saldo_post = calcular_saldo_normal_disponible(fecha_ingreso, meses_previos, dias_acumulados, dias_utilizados)

        saldo_ant = saldo_post + dias

        buffer = io.BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=letter, topMargin=inch, bottomMargin=inch, leftMargin=inch, rightMargin=inch)
        styles = getSampleStyleSheet()
        story = []
        story.append(Paragraph("CLINICA ACONCAGUA", styles['Title']))
        story.append(Paragraph("RECIBO DE VACACIONES APROBADAS", styles['Heading2']))
        story.append(Spacer(1, 20))

        data_tabla = [
            ["Campo", "Valor"],
            ["Nombre completo", nombre or "—"],
            ["RUT", rut or "—"],
            ["Tipo de dias", "Progresivos" if tipo_dias == 'progresivo' else "Normales"],
            ["Fecha de inicio", fi.strftime("%d/%m/%Y") if fi else "—"],
            ["Fecha de termino", ff.strftime("%d/%m/%Y") if ff else "—"],
            ["Dias habiles", str(dias)],
            ["Saldo anterior", str(saldo_ant)],
            ["Saldo posterior", str(saldo_post)],
            ["Aprobado por", nombre_admin or "Administrador"],
            ["Fecha aprobacion", fs.strftime("%d/%m/%Y %H:%M") if fs else "—"],
            ["Observacion", obs or "Sin observacion"],
        ]

        tabla = Table(data_tabla, colWidths=[2.5*inch, 4*inch])
        tabla.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#001E42')),
            ('TEXTCOLOR', (0,0), (-1,0), colors.white),
            ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
            ('FONTSIZE', (0,0), (-1,-1), 11),
            ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, colors.HexColor('#F8FAFC')]),
            ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor('#E2E8F0')),
            ('PADDING', (0,0), (-1,-1), 8),
        ]))
        story.append(tabla)
        story.append(Spacer(1, 30))
        story.append(Paragraph("Este documento es un comprobante oficial de vacaciones aprobadas.", styles['Normal']))
        doc.build(story)
        pdf_bytes = buffer.getvalue()
        buffer.close()

        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename=recibo_vacaciones_{id_solicitud}.pdf"}
        )
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── SUBIR LIQUIDACIONES ZIP ───────────────────────────────────
def generar_codigo_verificacion(cursor) -> str:
    """
    Genera un codigo alfanumerico de exactamente 12 caracteres
    (A-Z, 0-9), verificando que no colisione con uno ya existente
    en liquidaciones_pdf (la probabilidad de choque es minima, pero
    se revisa igual para garantizar unicidad real).
    """
    alfabeto = string.ascii_uppercase + string.digits
    for _ in range(10):
        codigo = ''.join(secrets.choice(alfabeto) for _ in range(12))
        cursor.execute("SELECT 1 FROM liquidaciones_pdf WHERE codigo_verificacion = %s", (codigo,))
        if not cursor.fetchone():
            return codigo
    raise Exception("No se pudo generar un codigo de verificacion unico, intenta de nuevo")


@app.post("/subir-liquidaciones")
async def subir_liquidaciones(archivo: UploadFile = File(...), payload: dict = Depends(verificar_token)):
    try:
        import time as _time
        inicio = _time.monotonic()
        TIEMPO_MAXIMO_SEGUNDOS = 60

        persona_id = get_persona_id(payload)
        if not archivo.filename.endswith('.zip'):
            return {"success": False, "mensaje": "El archivo debe ser .zip"}

        contenido_zip = await archivo.read()

        with zipfile.ZipFile(io.BytesIO(contenido_zip)) as zf:
            procesados = []
            errores    = []
            no_procesados_por_tiempo = []
            archivos   = [f for f in zf.namelist() if f.endswith('.pdf')]
            todos_archivos = [f for f in zf.namelist() if not f.endswith('/') and '__MACOSX' not in f]
            no_pdf = [f for f in todos_archivos if not f.lower().endswith('.pdf')]

            if no_pdf:
                for archivo_invalido in no_pdf:
                    nombre_solo = archivo_invalido.split('/')[-1].split('\\')[-1]
                    errores.append(f"{nombre_solo}: formato incorrecto, solo se permiten documentos PDF")

            if len(archivos) > 50:
                return {"success": False, "mensaje": f"El ZIP contiene {len(archivos)} PDFs. Maximo permitido: 50"}

            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id,))
            admin = cursor.fetchone()
            administrador_id = admin[0] if admin else None

            for nombre_pdf in archivos:
                nombre_solo = nombre_pdf.split('/')[-1].split('\\')[-1]

                # #14: si ya se supero el tiempo maximo permitido para
                # la carga masiva, se detiene y se informa cuales
                # archivos quedaron sin procesar.
                if _time.monotonic() - inicio > TIEMPO_MAXIMO_SEGUNDOS:
                    no_procesados_por_tiempo.append(nombre_solo)
                    continue

                patron = r'^([\d\.]{7,11}-[\dkK])-(\d{6})\.pdf$'
                match = re.match(patron, nombre_solo)

                if not match:
                    errores.append(f"{nombre_solo}: nombre invalido (debe ser RUT-AAAAMM.pdf)")
                    continue

                rut     = match.group(1)
                periodo = match.group(2)
                pdf_bytes = zf.read(nombre_pdf)

                if len(pdf_bytes) > 5 * 1024 * 1024:
                    errores.append(f"{nombre_solo}: El archivo excede el tamaño máximo permitido.")
                    continue

                if not validar_pdf_estructuralmente(pdf_bytes):
                    errores.append(f"{nombre_solo}: el archivo PDF está dañado o no puede ser procesado")
                    continue

                cursor.execute(
                    """SELECT t.trabajador_id FROM trabajador t
                       JOIN persona p ON p.persona_id = t.persona_id
                       WHERE p.rut = %s""",
                    (rut,)
                )
                trabajador = cursor.fetchone()
                if not trabajador:
                    errores.append(f"{nombre_solo}: RUT {rut} no encontrado en el sistema")
                    continue

                # ── Codigo de verificacion (12 caracteres, unico) ────
                cursor.execute(
                    "SELECT codigo_verificacion FROM liquidaciones_pdf WHERE rut = %s AND periodo = %s",
                    (rut, periodo)
                )
                existente = cursor.fetchone()
                codigo_verificacion = existente[0] if (existente and existente[0]) else generar_codigo_verificacion(cursor)

                cursor.execute(
                    """INSERT INTO liquidaciones_pdf
                       (trabajador_id, rut, periodo, nombre_archivo, archivo_pdf, tamano_bytes, codigo_verificacion, subido_por)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                       ON CONFLICT (rut, periodo) DO UPDATE
                       SET archivo_pdf = EXCLUDED.archivo_pdf,
                           tamano_bytes = EXCLUDED.tamano_bytes,
                           codigo_verificacion = COALESCE(liquidaciones_pdf.codigo_verificacion, EXCLUDED.codigo_verificacion),
                           subido_por = EXCLUDED.subido_por,
                           fecha_subida = NOW()""",
                    (trabajador[0], rut, periodo, nombre_solo, pdf_bytes, len(pdf_bytes), codigo_verificacion, administrador_id)
                )
                procesados.append(f"{nombre_solo} (codigo: {codigo_verificacion})")

            conn.commit(); cursor.close(); conn.close()

            if no_procesados_por_tiempo:
                errores.append(
                    f"Se excedió el tiempo máximo de {TIEMPO_MAXIMO_SEGUNDOS} segundos. "
                    f"No se alcanzaron a procesar: {', '.join(no_procesados_por_tiempo)}"
                )

            return {
                "success": True,
                "procesados": len(procesados),
                "errores": len(errores),
                "detalle_procesados": procesados,
                "detalle_errores": errores,
                "mensaje": f"Se procesaron {len(procesados)} liquidaciones correctamente."
            }

    except zipfile.BadZipFile:
        return {"success": False, "mensaje": "El archivo ZIP esta danado o es invalido"}
    except Exception as e:
        return {"success": False, "mensaje": f"Error del servidor: {str(e)}"}

# ── VERIFICAR AUTENTICIDAD DE LIQUIDACION (publico, sin login) ─
@app.get("/verificar-liquidacion/{codigo}")
def verificar_liquidacion_por_codigo(codigo: str):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT lp.rut, lp.periodo, lp.fecha_subida, p.primer_nombre, p.apellido_paterno
               FROM liquidaciones_pdf lp
               JOIN trabajador t ON t.trabajador_id = lp.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               WHERE lp.codigo_verificacion = %s""",
            (codigo.strip().upper(),)
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()
        if not r:
            return {"success": False, "mensaje": "Codigo de verificacion no encontrado. El documento podria no ser autentico."}

        rut, periodo, fecha_subida, nombre, apellido = r
        return {
            "success": True,
            "autentico": True,
            "rut": rut,
            "nombre_trabajador": f"{nombre} {apellido}",
            "periodo": f"{periodo[4:]}/{periodo[:4]}" if len(periodo) == 6 else periodo,
            "fecha_emision": fecha_subida.strftime("%d/%m/%Y"),
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e)}


# ── MIS LIQUIDACIONES ─────────────────────────────────────────
@app.get("/mis-liquidaciones")
def get_liquidaciones(payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT lp.id, lp.nombre_archivo, lp.periodo,
                      lp.tamano_bytes, lp.fecha_subida, lp.codigo_verificacion
               FROM liquidaciones_pdf lp
               JOIN trabajador t ON t.trabajador_id = lp.trabajador_id
               WHERE t.persona_id = %s
               ORDER BY lp.periodo DESC""",
            (persona_id,)
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        liquidaciones = []
        for r in rows:
            anio    = r[2][:4]
            mes_num = int(r[2][4:])
            meses = ["","Enero","Febrero","Marzo","Abril","Mayo","Junio",
                     "Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"]
            liquidaciones.append({
                "id": r[0],
                "nombre_archivo": r[1],
                "periodo": f"{meses[mes_num]} {anio}",
                "tamano_kb": round(r[3] / 1024, 1),
                "fecha_subida": r[4].strftime("%d/%m/%Y"),
                "codigo_verificacion": r[5] or "—",
            })
        return {"success": True, "liquidaciones": liquidaciones}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── DESCARGAR PDF ─────────────────────────────────────────────
@app.get("/descargar-liquidacion/{id_liquidacion}")
def descargar_liquidacion(id_liquidacion: int, payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT lp.archivo_pdf, lp.nombre_archivo, lp.disponible
               FROM liquidaciones_pdf lp
               JOIN trabajador t ON t.trabajador_id = lp.trabajador_id
               WHERE lp.id = %s AND t.persona_id = %s""",
            (id_liquidacion, persona_id)
        )
        result = cursor.fetchone()
        cursor.close(); conn.close()

        if not result:
            return Response(content=b'{"success": false, "mensaje": "Liquidacion no disponible"}', media_type="application/json", status_code=404)

        pdf_bytes, nombre, disponible = result

        if disponible is not None and not disponible:
            return Response(content=b'{"success": false, "mensaje": "Liquidacion no disponible"}', media_type="application/json", status_code=403)

        if not pdf_bytes or len(bytes(pdf_bytes)) == 0:
            return Response(content=b'{"success": false, "mensaje": "Error al descargar la liquidacion, por favor intente mas tarde"}', media_type="application/json", status_code=500)

        return Response(
            content=bytes(pdf_bytes),
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={nombre}"}
        )
    except Exception as e:
        return Response(
            content=f'{{"success": false, "mensaje": "Error al descargar la liquidacion, por favor intente mas tarde"}}'.encode(),
            media_type="application/json",
            status_code=500
        )

# ── CREAR EMPLEADO ────────────────────────────────────────────
####################################################################
# ESTA PARTE DEL CODIGO NO SE CONSIDERA
# Este endpoint (POST /empleados) pertenecia al flujo viejo de la
# pantalla registroEmpleado.dart, donde el ADMINISTRADOR le asignaba
# una contrasena fija ("Aconcagua2024!") al crear un trabajador. Ese
# diseno se reemplazo por el flujo actual (cuentasPendientes.dart ->
# POST /admin/completar-cuenta), donde el propio trabajador define su
# contrasena al auto-registrarse, cumpliendo el requisito real.
# Se confirmo que ningun archivo .dart vigente llama a este endpoint
# (registroEmpleado.dart no se navega desde ninguna pantalla actual).
# Se deja el codigo intacto, sin usar, solo como referencia historica.
####################################################################
@app.post("/empleados")
def crear_empleado(data: EmpleadoRequest, payload: dict = Depends(verificar_token)):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT cuenta_id FROM cuenta_acceso WHERE correo_institucional = %s", (data.correo,))
        if cursor.fetchone():
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El correo ya esta registrado"}
        cursor.execute("SELECT persona_id FROM persona WHERE rut = %s", (data.rut,))
        if cursor.fetchone():
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El RUT ya esta registrado"}

        cursor.execute(
            """INSERT INTO persona
               (rut, primer_nombre, segundo_nombre, apellido_paterno, apellido_materno,
                correo_institucional, telefono, direccion, fecha_nacimiento,
                cargo, fecha_ingreso, tipo_afp, institucion_salud, activo)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,TRUE)
               RETURNING persona_id""",
            (data.rut, data.primer_nombre, data.segundo_nombre or None,
             data.apellido_paterno, data.apellido_materno,
             data.correo, data.telefono, data.direccion,
             data.fecha_nacimiento, data.cargo, data.fecha_ingreso,
             data.afp, data.tipo_salud)
        )
        persona_id = cursor.fetchone()[0]

        contrasena_hash = encriptar_contrasena("Aconcagua2024!")
        rol_valido = data.rol if data.rol in ['usuario', 'jefe'] else 'usuario'
        cursor.execute(
            """INSERT INTO cuenta_acceso (correo_institucional, contrasena, rol, persona_id)
               VALUES (%s, %s, %s, %s) RETURNING cuenta_id""",
            (data.correo, contrasena_hash, rol_valido, persona_id)
        )
        nueva_cuenta_id = cursor.fetchone()[0]

        cursor.execute(
            """INSERT INTO trabajador (persona_id, departamento_id, meses_cotizados_previos, discapacidad)
               VALUES (%s, (SELECT departamento_id FROM departamento WHERE codigo='SC' LIMIT 1), 0, %s)
               RETURNING trabajador_id""",
            (persona_id, data.discapacidad or None)
        )
        trabajador_id = cursor.fetchone()[0]

        cursor.execute(
            """INSERT INTO contrato (trabajador_id, tipo_contrato, fecha_ingreso, sueldo_base, cargo, tipo_afp, institucion_salud, estado)
               VALUES (%s, %s, %s, %s, %s, %s, %s, 'activo')""",
            (trabajador_id, data.tipo_contrato, data.fecha_ingreso, data.sueldo_base, data.cargo, data.afp, data.tipo_salud)
        )

        cursor.execute(
            "INSERT INTO saldo_vacaciones (trabajador_id, dias_disponibles, dias_progresivos) VALUES (%s, 15, 0)",
            (trabajador_id,)
        )

        conn.commit(); cursor.close(); conn.close()

        generar_y_enviar_verificacion(nueva_cuenta_id, data.correo)

        return {"success": True, "mensaje": "Empleado registrado correctamente. Se le envio un correo de activacion de cuenta."}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── EDITAR EMPLEADO ───────────────────────────────────────────
####################################################################
# ESTA PARTE DEL CODIGO NO SE CONSIDERA
# Este endpoint (PUT /empleados/{id}) tambien pertenece al flujo
# viejo de la pantalla registroEmpleado.dart (ver aviso identico mas
# arriba, en POST /empleados). Ningun archivo .dart vigente lo llama.
####################################################################
@app.put("/empleados/{persona_id_param}")
def editar_empleado(persona_id_param: int, data: EmpleadoRequest, payload: dict = Depends(verificar_token)):
    try:
        conn = get_connection()
        cursor = conn.cursor()

        # ── Obtener trabajador_id y sueldo_base actual (para auditoria) ──
        cursor.execute(
            """SELECT t.trabajador_id, c.sueldo_base, p.rut
               FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE t.persona_id = %s""",
            (persona_id_param,)
        )
        r = cursor.fetchone()
        trabajador_id, sueldo_base_anterior, rut_trabajador = (r if r else (None, None, None))

        # ── El sueldo base solo se puede cambiar antes del cierre del
        #    periodo actual (mes/año en curso) ────────────────────
        if trabajador_id:
            periodo_actual = dt.date.today().strftime("%m/%Y")
            if verificar_liquidacion_cerrada(trabajador_id, periodo_actual):
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "No se puede modificar el sueldo base: la liquidacion del periodo actual ya fue cerrada"}

        # ── El sueldo base no puede quedar bajo el salario minimo legal ──
        if data.sueldo_base is not None and float(data.sueldo_base) < SALARIO_MINIMO:
            cursor.close(); conn.close()
            return {
                "success": False,
                "mensaje": f"El sueldo base no puede ser menor al salario minimo legal vigente (${SALARIO_MINIMO:,}). Por favor corrigelo.".replace(",", ".")
            }

        cursor.execute(
            """UPDATE persona SET primer_nombre=%s, segundo_nombre=%s,
               apellido_paterno=%s, apellido_materno=%s,
               cargo=%s, fecha_ingreso=%s, tipo_afp=%s,
               institucion_salud=%s, telefono=%s, direccion=%s,
               fecha_nacimiento=%s WHERE persona_id=%s""",
            (data.primer_nombre, data.segundo_nombre or None,
             data.apellido_paterno, data.apellido_materno,
             data.cargo, data.fecha_ingreso, data.afp,
             data.tipo_salud, data.telefono, data.direccion,
             data.fecha_nacimiento, persona_id_param)
        )
        cursor.execute(
            """UPDATE contrato SET tipo_contrato=%s, sueldo_base=%s, cargo=%s, tipo_afp=%s, institucion_salud=%s, jornada_semanal_horas=%s
               WHERE trabajador_id=(SELECT trabajador_id FROM trabajador WHERE persona_id=%s) AND estado='activo'""",
            (data.tipo_contrato, data.sueldo_base, data.cargo, data.afp, data.tipo_salud, data.jornada_semanal_horas, persona_id_param)
        )

        # ── Auditoria: solo si el sueldo base realmente cambio ──────
        if sueldo_base_anterior is not None and float(sueldo_base_anterior) != float(data.sueldo_base):
            persona_id_admin = get_persona_id(payload)
            cursor.execute(
                """SELECT p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre_admin,
                          p.rut AS rut_admin
                   FROM persona p WHERE p.persona_id = %s""",
                (persona_id_admin,)
            )
            admin_row = cursor.fetchone()
            nombre_admin = (admin_row[0] if admin_row else "Administrador")[:120]
            rut_admin = admin_row[1] if admin_row else ""

            cursor.execute(
                """INSERT INTO log_auditoria
                   (tabla_afectada, registro_id, tipo_de_operacion, campo_modificado,
                    modulo, nombre_completo, informacion_personal,
                    valor_anterior, valor_nuevo, rut_administrador)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (
                    "contrato",
                    str(trabajador_id),
                    "UPDATE",
                    "sueldo_base",
                    "Remuneraciones - Ficha Empleado",
                    nombre_admin,
                    f"RUT trabajador afectado: {rut_trabajador}",
                    str(round(float(sueldo_base_anterior))),
                    str(data.sueldo_base),
                    rut_admin,
                )
            )

        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Empleado actualizado correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── BUSCAR EMPLEADOS ──────────────────────────────────────────
@app.get("/buscar-empleados")
def buscar_empleados(apellido: str = None, rut: str = None, payload: dict = Depends(verificar_token)):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        base_query = """
            SELECT p.persona_id, p.rut,
                   p.primer_nombre, p.segundo_nombre,
                   p.apellido_paterno, p.apellido_materno,
                   p.cargo, p.fecha_ingreso,
                   p.telefono, p.direccion,
                   p.tipo_afp, p.institucion_salud,
                   p.correo_institucional,
                   t.meses_cotizados_previos, t.discapacidad,
                   c.tipo_contrato, c.sueldo_base, c.fecha_vencimiento,
                   ca.rol, c.jornada_semanal_horas
            FROM persona p
            JOIN trabajador t ON t.persona_id = p.persona_id
            JOIN cuenta_acceso ca ON ca.persona_id = p.persona_id
            LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
            WHERE p.activo = TRUE
        """
        if rut:
            cursor.execute(base_query + " AND p.rut = %s", (rut,))
        elif apellido:
            if len(apellido) < 3:
                return {"success": False, "mensaje": "Minimo 3 caracteres para buscar por apellido"}
            cursor.execute(base_query + " AND (p.apellido_paterno ILIKE %s OR p.apellido_materno ILIKE %s) ORDER BY p.apellido_paterno",
                           (f'%{apellido}%', f'%{apellido}%'))
        else:
            return {"success": False, "mensaje": "Debes ingresar un apellido o RUT"}

        rows = cursor.fetchall()
        cursor.close(); conn.close()
        empleados = []
        for r in rows:
            fi = r[7]
            empleados.append({
                "id_empleado":      r[0],
                "rut":              r[1],
                "nombres":          f"{r[2]} {r[3] or ''}".strip(),
                "apellidos":        f"{r[4]} {r[5]}",
                "cargo":            r[6] or "—",
                "fecha_ingreso":    fi.strftime("%d/%m/%Y") if fi else "—",
                "telefono":         r[8] or "",
                "direccion":        r[9] or "",
                "afp":              r[10] or "",
                "tipo_salud":       r[11] or "",
                "correo":           r[12] or "",
                "meses_cotizados_previos": r[13] or 0,
                "discapacidad":     r[14] or "",
                "tipo_contrato":    r[15] or "",
                "sueldo_base":      r[16] or 0,
                "fecha_nacimiento": None,
                "primer_nombre":    r[2] or "",
                "segundo_nombre":   r[3] or "",
                "apellido_paterno": r[4] or "",
                "apellido_materno": r[5] or "",
                "jornada_semanal_horas": float(r[19]) if r[19] is not None else None,
            })
        return {"success": True, "empleados": empleados}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── COTIZACIONES ──────────────────────────────────────────────
@app.put("/empleados/{persona_id_param}/cotizaciones")
def actualizar_cotizaciones(persona_id_param: int, data: CotizacionesRequest, payload: dict = Depends(verificar_token)):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE trabajador SET meses_cotizados_previos = %s WHERE persona_id = %s", (data.meses_cotizados_previos, persona_id_param))
        # El motor de calculo (calcular_afp_salud) lee tipo_afp desde
        # 'contrato', pero la ficha del empleado MUESTRA el valor desde
        # 'persona' -- antes solo se actualizaba 'persona' (asi que el
        # cambio se veia en pantalla pero nunca se reflejaba en ningun
        # calculo real). Ahora se actualizan ambas para mantenerlas
        # sincronizadas.
        cursor.execute("UPDATE persona SET tipo_afp = %s WHERE persona_id = %s", (data.afp, persona_id_param))
        cursor.execute(
            """UPDATE contrato SET tipo_afp = %s
               WHERE trabajador_id = (SELECT trabajador_id FROM trabajador WHERE persona_id = %s)
                 AND estado = 'activo'""",
            (data.afp, persona_id_param)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Datos actualizados correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── CERTIFICADO AFP ───────────────────────────────────────────
@app.post("/empleados/{persona_id_param}/certificado-afp")
async def subir_certificado_afp(persona_id_param: int, certificado: UploadFile = File(...), payload: dict = Depends(verificar_token)):
    try:
        nombre_archivo = (certificado.filename or "").strip().lower()
        if not nombre_archivo.endswith(".pdf"):
            return {"success": False, "mensaje": "El archivo debe estar en formato PDF"}

        contenido = await certificado.read()
        if len(contenido) > 5 * 1024 * 1024:
            return {"success": False, "mensaje": "El archivo supera el tamaño máximo de 5 MB"}
        if not validar_pdf_estructuralmente(contenido):
            return {"success": False, "mensaje": "El archivo PDF está dañado o no puede ser procesado. Por favor, suba un archivo válido."}
        persona_id_admin = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT trabajador_id FROM trabajador WHERE persona_id = %s", (persona_id_param,))
        t = cursor.fetchone()
        if not t:
            return {"success": False, "mensaje": "Trabajador no encontrado"}
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        a = cursor.fetchone()
        cursor.execute(
            """INSERT INTO certificados_afp (trabajador_id, nombre_archivo, archivo_pdf, tamano_bytes, subido_por)
               VALUES (%s, %s, %s, %s, %s)
               ON CONFLICT (trabajador_id) DO UPDATE
               SET archivo_pdf = EXCLUDED.archivo_pdf,
                   nombre_archivo = EXCLUDED.nombre_archivo,
                   tamano_bytes = EXCLUDED.tamano_bytes,
                   subido_por = EXCLUDED.subido_por,
                   fecha_subida = NOW()""",
            (t[0], certificado.filename, contenido, len(contenido), a[0] if a else None)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Certificado guardado correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── PANEL JEFE ────────────────────────────────────────────────
@app.get("/jefe/panel-resumen")
def panel_resumen_jefe(payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT j.departamento_id, d.nombre FROM jefe j
               JOIN departamento d ON d.departamento_id = j.departamento_id
               WHERE j.persona_id = %s""",
            (persona_id,)
        )
        jefe_data = cursor.fetchone()
        if not jefe_data:
            return {"success": False, "mensaje": "No posee personal a cargo asignado"}
        id_depto, nombre_depto = jefe_data

        cursor.execute(
            """SELECT t.trabajador_id,
                      p.primer_nombre || ' ' || p.apellido_paterno AS nombre,
                      p.cargo, p.fecha_ingreso,
                      c.tipo_contrato, c.fecha_vencimiento
               FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE t.departamento_id = %s AND p.activo = TRUE
               ORDER BY p.apellido_paterno""",
            (id_depto,)
        )
        trabajadores = []
        contratos_por_vencer = []
        hoy = dt.date.today()
        for r in cursor.fetchall():
            fi = r[3]; fv = r[5]
            trabajadores.append({"id_empleado": r[0], "nombre": r[1], "cargo": r[2] or "—", "fecha_ingreso": fi.strftime("%d/%m/%Y") if fi else "—", "tipo_contrato": r[4] or "—"})
            if fv and 0 <= (fv - hoy).days <= 30:
                contratos_por_vencer.append({"nombre": r[1], "cargo": r[2] or "—", "vence": fv.strftime("%d/%m/%Y"), "dias_resta": (fv - hoy).days})

        cursor.execute(
            """SELECT p.primer_nombre || ' ' || p.apellido_paterno,
                      sv.fecha_inicio, sv.fecha_fin, sv.dias_habiles, sv.estado
               FROM solicitud_vacaciones sv
               JOIN trabajador t ON t.trabajador_id = sv.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               WHERE t.departamento_id = %s AND sv.estado = 'Pendiente'
               ORDER BY sv.fecha_inicio""",
            (id_depto,)
        )
        solicitudes_pendientes = [{"nombre": r[0], "fecha_inicio": r[1].strftime("%d/%m/%Y") if r[1] else "—", "fecha_fin": r[2].strftime("%d/%m/%Y") if r[2] else "—", "dias_habiles": r[3], "estado": r[4]} for r in cursor.fetchall()]

        cursor.execute(
            """SELECT p.primer_nombre || ' ' || p.apellido_paterno, sv.fecha_inicio, sv.fecha_fin
               FROM solicitud_vacaciones sv
               JOIN trabajador t ON t.trabajador_id = sv.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               WHERE t.departamento_id = %s AND sv.estado = 'Aprobada'
                 AND sv.fecha_inicio <= CURRENT_DATE AND sv.fecha_fin >= CURRENT_DATE""",
            (id_depto,)
        )
        en_vacaciones = [{"nombre": r[0], "fecha_inicio": r[1].strftime("%d/%m/%Y") if r[1] else "—", "fecha_fin": r[2].strftime("%d/%m/%Y") if r[2] else "—"} for r in cursor.fetchall()]

        cursor.close(); conn.close()
        return {"success": True, "departamento": nombre_depto, "trabajadores": trabajadores, "solicitudes_pendientes": solicitudes_pendientes, "en_vacaciones": en_vacaciones, "contratos_por_vencer": contratos_por_vencer}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── JEFE: VACACIONES TRABAJADOR ───────────────────────────────
@app.get("/jefe/vacaciones-trabajador/{trabajador_id}")
def vacaciones_trabajador(trabajador_id: int, estado: str = None, fecha_desde: str = None, fecha_hasta: str = None, payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT j.departamento_id FROM jefe j WHERE j.persona_id = %s", (persona_id,))
        j = cursor.fetchone()
        if not j:
            return {"success": False, "mensaje": "Area no encontrada"}
        cursor.execute(
            """SELECT t.trabajador_id, p.primer_nombre || ' ' || p.apellido_paterno,
                      p.cargo, sal.dias_disponibles, sal.dias_acumulados, sal.dias_utilizados
               FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN saldo_vacaciones sal ON sal.trabajador_id = t.trabajador_id
               WHERE t.trabajador_id = %s AND t.departamento_id = %s""",
            (trabajador_id, j[0])
        )
        tw = cursor.fetchone()
        if not tw:
            return {"success": False, "mensaje": "Trabajador no pertenece a su area"}

        query = """
            SELECT sv.solicitud_id, sv.fecha_inicio, sv.fecha_fin,
                   sv.dias_habiles, sv.estado, sv.observacion, sv.fecha_solicitud
            FROM solicitud_vacaciones sv WHERE sv.trabajador_id = %s
        """
        params = [trabajador_id]
        if estado:
            query += " AND sv.estado = %s"; params.append(estado)
        if fecha_desde:
            query += " AND sv.fecha_inicio >= %s"; params.append(fecha_desde)
        if fecha_hasta:
            query += " AND sv.fecha_fin <= %s"; params.append(fecha_hasta)
        query += " ORDER BY sv.fecha_solicitud DESC"
        cursor.execute(query, params)

        solicitudes = [{"solicitud_id": r[0], "fecha_inicio": r[1].strftime("%d/%m/%Y") if r[1] else "—", "fecha_fin": r[2].strftime("%d/%m/%Y") if r[2] else "—", "dias_habiles": r[3], "estado": r[4], "observacion": r[5] or "—", "fecha_solicitud": r[6].strftime("%d/%m/%Y") if r[6] else "—"} for r in cursor.fetchall()]

        cursor.close(); conn.close()
        return {"success": True, "nombre": tw[1], "cargo": tw[2] or "—", "saldo_disponible": tw[3] or 0, "saldo_acumulado": tw[4] or 0, "saldo_utilizado": tw[5] or 0, "solicitudes": solicitudes}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── JEFE: VACACIONES AREA ─────────────────────────────────────
@app.get("/jefe/vacaciones-area")
def vacaciones_area(estado: str = None, fecha_desde: str = None, fecha_hasta: str = None, payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT departamento_id FROM jefe WHERE persona_id = %s", (persona_id,))
        j = cursor.fetchone()
        if not j:
            return {"success": False, "mensaje": "Area no encontrada"}

        query = """
            SELECT p.primer_nombre || ' ' || p.apellido_paterno,
                   p.cargo, sv.fecha_inicio, sv.fecha_fin,
                   sv.dias_habiles, sv.estado, sal.dias_disponibles
            FROM solicitud_vacaciones sv
            JOIN trabajador t ON t.trabajador_id = sv.trabajador_id
            JOIN persona p ON p.persona_id = t.persona_id
            LEFT JOIN saldo_vacaciones sal ON sal.trabajador_id = t.trabajador_id
            WHERE t.departamento_id = %s
        """
        params = [j[0]]
        if estado:
            query += " AND sv.estado = %s"; params.append(estado)
        if fecha_desde:
            query += " AND sv.fecha_inicio >= %s"; params.append(fecha_desde)
        if fecha_hasta:
            query += " AND sv.fecha_fin <= %s"; params.append(fecha_hasta)
        query += " ORDER BY sv.fecha_inicio DESC"
        cursor.execute(query, params)

        solicitudes = [{"nombre": r[0], "cargo": r[1] or "—", "fecha_inicio": r[2].strftime("%d/%m/%Y") if r[2] else "—", "fecha_fin": r[3].strftime("%d/%m/%Y") if r[3] else "—", "dias_habiles": r[4], "estado": r[5], "saldo_total": r[6] or 15} for r in cursor.fetchall()]
        cursor.close(); conn.close()
        return {"success": True, "solicitudes": solicitudes}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── ACTUALIZAR VACACIONES PROGRESIVAS ─────────────────────────
@app.put("/actualizar-vacaciones-progresivas")
def actualizar_vacaciones(data: ActualizarVacacionesRequest, payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """UPDATE saldo_vacaciones SET dias_progresivos = %s, dias_disponibles = %s, ultima_actualizacion = NOW()
               WHERE trabajador_id = (SELECT trabajador_id FROM trabajador WHERE persona_id = %s)""",
            (data.dias_adicionales, data.dias_totales, persona_id)
        )
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Saldo actualizado correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── CAMBIAR ROL ───────────────────────────────────────────────
@app.put("/empleados/{persona_id_param}/rol")
def cambiar_rol(persona_id_param: int, data: RolRequest, payload: dict = Depends(verificar_token)):
    try:
        if data.rol not in ['usuario', 'jefe']:
            return {"success": False, "mensaje": "Rol invalido. Solo se permite: usuario, jefe"}

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE cuenta_acceso SET rol = %s WHERE persona_id = %s", (data.rol, persona_id_param))
        if cursor.rowcount == 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Empleado no encontrado"}

        if data.rol == "jefe":
            # Buscar el trabajador_id y el departamento actual de esta
            # persona (el equipo del jefe = su mismo departamento).
            cursor.execute(
                """SELECT t.trabajador_id, t.departamento_id, d.nombre
                   FROM trabajador t
                   LEFT JOIN departamento d ON d.departamento_id = t.departamento_id
                   WHERE t.persona_id = %s""",
                (persona_id_param,)
            )
            trab_row = cursor.fetchone()
            if not trab_row:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "No se encontró el registro de trabajador para esta persona"}
            trabajador_id, departamento_id, nombre_departamento = trab_row

            if departamento_id is None:
                cursor.close(); conn.close()
                return {"success": False, "mensaje": "Este trabajador no tiene un departamento asignado. Asígnale uno antes de convertirlo en Jefe."}

            # Crear (o actualizar, si ya existia) su fila en Jefe
            cursor.execute(
                """INSERT INTO jefe (persona_id, trabajador_id, departamento_id, area)
                   VALUES (%s, %s, %s, %s)
                   ON CONFLICT (trabajador_id) DO UPDATE
                   SET departamento_id = EXCLUDED.departamento_id, area = EXCLUDED.area""",
                (persona_id_param, trabajador_id, departamento_id, nombre_departamento or "Sin área")
            )

            # Asignar el equipo seleccionado: mover a esos trabajadores
            # al mismo departamento del jefe (Opcion A: "equipo" =
            # "mismo departamento"). Se excluye al propio jefe por si
            # quedo marcado sin querer en la lista.
            if data.trabajadores_equipo:
                equipo_sin_jefe = [tid for tid in data.trabajadores_equipo if tid != trabajador_id]
                if equipo_sin_jefe:
                    cursor.execute(
                        "UPDATE trabajador SET departamento_id = %s WHERE trabajador_id = ANY(%s)",
                        (departamento_id, equipo_sin_jefe)
                    )

        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Rol actualizado a '{data.rol}' correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}


@app.get("/admin/listar-trabajadores-simple")
def listar_trabajadores_simple(payload: dict = Depends(verificar_token)):
    """
    Lista liviana de todos los trabajadores activos (id, nombre, rut,
    departamento actual) — usada para armar el checklist de "equipo"
    al asignar el rol Jefe.
    """
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT t.trabajador_id, p.persona_id,
                      p.primer_nombre || ' ' || p.apellido_paterno AS nombre,
                      p.rut, d.nombre AS departamento_actual
               FROM trabajador t
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN departamento d ON d.departamento_id = t.departamento_id
               WHERE p.activo = TRUE
               ORDER BY p.apellido_paterno"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {
            "success": True,
            "trabajadores": [
                {
                    "trabajador_id": r[0],
                    "persona_id": r[1],
                    "nombre": r[2],
                    "rut": r[3],
                    "departamento_actual": r[4] or "Sin departamento",
                }
                for r in rows
            ]
        }
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── BALANCE VACACIONES ────────────────────────────────────────
@app.get("/mi-balance-vacaciones")
def get_balance_vacaciones(payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT
                p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre,
                p.fecha_ingreso,
                t.meses_cotizados_previos,
                sv.dias_acumulados,
                sv.dias_utilizados,
                sv.dias_disponibles,
                sv.dias_progresivos,
                sv.ultima_actualizacion,
                c.sueldo_base,
                sv.dias_vendidos,
                sv.ultimo_incremento_anual,
                sv.saldo_id
               FROM persona p
               JOIN trabajador t ON t.persona_id = p.persona_id
               JOIN saldo_vacaciones sv ON sv.trabajador_id = t.trabajador_id
               LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE p.persona_id = %s""",
            (persona_id,)
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()

        if not r:
            return {"success": False, "mensaje": "No se encontro informacion de vacaciones"}


        (nombre, fecha_ingreso, meses_previos, dias_acumulados,
         dias_utilizados, dias_disponibles, dias_progresivos,
         ultima_actualizacion, sueldo_base, dias_vendidos,
         ultimo_incremento_anual, saldo_id) = r

        # ── CALCULO DE DIAS ACUMULADOS: SIEMPRE EN VIVO ───────
        # FIX: antes existia un mecanismo que sumaba +15 "a mano" al
        # cumplirse el aniversario y guardaba ese numero en la BD.
        # Eso duplicaba el crecimiento, porque la formula por meses
        # (meses_clinica * 1.25) YA crece 15 dias por cada 12 meses de
        # forma continua (12 * 1.25 = 15). Sumarle un incremento anual
        # ADEMAS de recalcular por meses hacia que el numero mostrado
        # fuera mayor al que corresponde legalmente.
        #
        # Ahora el acumulado se calcula SIEMPRE desde cero con la
        # formula (meses en la clinica * 1.25), sin usar ni mutar
        # ningun valor guardado en dias_acumulados. La columna
        # ultimo_incremento_anual queda sin uso (se deja en la tabla
        # por si se decide revertir este cambio, pero ya no se lee
        # ni se escribe).
        incremento_anual_aplicado = False
        dias_acumulados_antes_incremento = None
        fecha_ultimo_incremento_str = None

        hoy = dt.date.today()
        if fecha_ingreso:
            meses_clinica = (hoy.year - fecha_ingreso.year) * 12 + (hoy.month - fecha_ingreso.month)
            if hoy.day < fecha_ingreso.day:
                meses_clinica -= 1
            meses_clinica = max(0, meses_clinica)
        else:
            meses_clinica = 0

        meses_previos_limitados = min(meses_previos or 0, 120)
        # El feriado normal (Art. 67 - 15 dias/año) se calcula SOLO
        # con la antiguedad en la clinica actual (meses_clinica). Las
        # cotizaciones previas (meses_previos) NO se suman aqui: esas
        # solo cuentan para el feriado progresivo (Art. 68, mas abajo).
        # total_meses se mantiene solo para mostrarlo informativamente
        # en el detalle, ya no se usa para calcular el acumulado.
        total_meses = meses_previos_limitados + meses_clinica
        acumulado_teorico_4dec = round(meses_clinica * 1.25, 4)

        # SIEMPRE se usa la formula por meses, nunca el valor guardado
        # en dias_acumulados (que podia arrastrar incrementos manuales
        # de cargas anteriores o del mecanismo ya eliminado).
        acumulado_final = acumulado_teorico_4dec
        acumulado_visual = round(acumulado_final)

        # #25: se respalda el valor exacto de 4 decimales en la BD
        # UNICAMENTE para fines de auditoria (columna ampliada a
        # NUMERIC(9,4)). OJO: esto es de solo ESCRITURA — el sistema
        # jamas vuelve a leer esta columna para ningun calculo (eso
        # fue justamente el bug que se corrigio antes). Se hace en
        # su propia conexion, sin afectar el resto de la funcion si
        # llegara a fallar por cualquier motivo.
        try:
            conn_audit = get_connection()
            cursor_audit = conn_audit.cursor()
            cursor_audit.execute(
                "UPDATE saldo_vacaciones SET dias_acumulados = %s WHERE saldo_id = %s",
                (acumulado_teorico_4dec, saldo_id)
            )
            conn_audit.commit(); cursor_audit.close(); conn_audit.close()
        except Exception:
            pass

        utilizados  = int(dias_utilizados or 0)
        disponibles = max(0, round(acumulado_final - utilizados))
        saldo_excedido = acumulado_final < utilizados

        # ── ART. 70: PERIODOS ACUMULADOS SIN USAR ─────────────
        # Se calcula directamente desde el saldo disponible actual
        # (ver docstring de calcular_periodos_articulo_70).
        art70 = calcular_periodos_articulo_70(disponibles)

        # ── CALCULO DIAS PROGRESIVOS (Art. 68) ────────────────
        dias_vendidos_int = int(dias_vendidos or 0)

        if fecha_ingreso:
            prog = calcular_dias_progresivos(fecha_ingreso, meses_previos_limitados)
            dias_prog_calculados  = prog["dias_prog_calculados"]
            cumple_progresivos    = prog["cumple_progresivos"]
            meses_faltantes       = prog["meses_faltantes"]
            anos_desde_inicio     = prog["anos_desde_inicio"]
            fecha_inicio_ben      = prog["fecha_inicio_beneficio"]
        else:
            dias_prog_calculados = 0
            cumple_progresivos   = False
            meses_faltantes      = max(0, 120 - meses_previos_limitados)
            anos_desde_inicio    = 0
            fecha_inicio_ben     = None

        # Descontar dias ya vendidos
        dias_prog_disponibles = max(0, dias_prog_calculados - dias_vendidos_int)
        dias_prog_final       = dias_prog_disponibles

        # Actualizar BD si el calculado neto es distinto al guardado
        if dias_prog_disponibles != int(dias_progresivos or 0):
            conn2 = get_connection()
            cursor2 = conn2.cursor()
            cursor2.execute(
                """UPDATE saldo_vacaciones
                   SET dias_progresivos = %s, ultima_actualizacion = NOW()
                   WHERE trabajador_id = (
                       SELECT trabajador_id FROM trabajador WHERE persona_id = %s
                   )""",
                (dias_prog_disponibles, persona_id)
            )
            conn2.commit()
            cursor2.close()
            conn2.close()

        return {
            "success":               True,
            "nombre":                nombre or "",
            "fecha_ingreso":         fecha_ingreso.strftime("%d/%m/%Y") if fecha_ingreso else "—",
            "meses_clinica":         meses_clinica,
            "meses_previos":         meses_previos_limitados,
            "total_meses":           total_meses,
            "factor_acumulacion":    1.25,
            "acumulado_4dec":        round(acumulado_final, 4),
            "dias_acumulados":       acumulado_visual,
            "dias_utilizados":       utilizados,
            "dias_disponibles":      disponibles,
            "dias_progresivos":      dias_prog_final,
            "dias_vendidos":         dias_vendidos_int,
            "anos_desde_inicio":     anos_desde_inicio,
            "cumple_progresivos":    cumple_progresivos,
            "meses_faltantes":       meses_faltantes,
            "fecha_inicio_beneficio": fecha_inicio_ben.strftime("%d/%m/%Y") if fecha_inicio_ben else "—",
            "sueldo_base":           float(sueldo_base or 0),
            "saldo_excedido":        saldo_excedido,
            "ultima_actualizacion":  ultima_actualizacion.strftime("%d/%m/%Y %H:%M") if ultima_actualizacion else "—",
            "periodos_acumulados_art70": art70["periodos_acumulados"],
            "alerta_articulo_70":        art70["alerta_articulo_70"],
            "bloqueo_articulo_70":       art70["bloqueo_articulo_70"],
            "incremento_anual_aplicado": incremento_anual_aplicado,
            "dias_acumulados_antes_incremento": (
                round(dias_acumulados_antes_incremento)
                if dias_acumulados_antes_incremento is not None else None
            ),
            "fecha_ultimo_incremento":   fecha_ultimo_incremento_str,
        }

    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── CUENTAS PENDIENTES ────────────────────────────────────────
@app.get("/admin/cuentas-pendientes")
def get_cuentas_pendientes(payload: dict = Depends(verificar_token)):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT cuenta_id, correo_institucional, rol FROM cuenta_acceso
               WHERE persona_id IS NULL ORDER BY cuenta_id DESC"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return {"success": True, "cuentas": [{"cuenta_id": r[0], "correo": r[1], "rol": r[2]} for r in rows]}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── COMPLETAR CUENTA ──────────────────────────────────────────
@app.post("/admin/completar-cuenta")
def completar_cuenta(data: CompletarCuentaRequest, payload: dict = Depends(verificar_token)):
    try:
        # Resguardo: sueldo_base solo puede faltar si el contrato es
        # Honorario (sin sueldo fijo). Para cualquier otro tipo de
        # contrato sigue siendo obligatorio, aunque alguien llame a
        # este endpoint directo sin pasar por el formulario.
        if data.tipo_contrato != "Honorario":
            if data.sueldo_base is None or data.sueldo_base < SALARIO_MINIMO:
                return {"success": False, "mensaje": f"El sueldo base es obligatorio para contrato {data.tipo_contrato} y no puede ser menor al salario minimo (${SALARIO_MINIMO})"}
            if not data.afp:
                return {"success": False, "mensaje": f"La AFP es obligatoria para contrato {data.tipo_contrato}"}
            if not data.cargo or len(data.cargo.strip()) < 2:
                return {"success": False, "mensaje": f"El cargo es obligatorio para contrato {data.tipo_contrato}"}
            if not data.tipo_salud:
                return {"success": False, "mensaje": f"La institución de salud es obligatoria para contrato {data.tipo_contrato}"}

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT persona_id FROM persona WHERE rut = %s", (data.rut,))
        if cursor.fetchone():
            return {"success": False, "mensaje": "El RUT ya esta registrado"}
        cursor.execute("SELECT correo_institucional FROM cuenta_acceso WHERE cuenta_id = %s", (data.cuenta_id,))
        cuenta = cursor.fetchone()
        if not cuenta:
            return {"success": False, "mensaje": "Cuenta no encontrada"}

        cursor.execute(
            """INSERT INTO persona
               (rut, primer_nombre, segundo_nombre, apellido_paterno, apellido_materno,
                correo_institucional, telefono, direccion, fecha_nacimiento,
                cargo, fecha_ingreso, tipo_afp, institucion_salud, activo)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,TRUE)
               RETURNING persona_id""",
            (data.rut, data.primer_nombre, data.segundo_nombre or None,
             data.apellido_paterno, data.apellido_materno,
             cuenta[0], data.telefono, data.direccion,
             data.fecha_nacimiento, data.cargo, data.fecha_ingreso,
             data.afp, data.tipo_salud)
        )
        persona_id = cursor.fetchone()[0]
        cursor.execute("UPDATE cuenta_acceso SET persona_id = %s WHERE cuenta_id = %s", (persona_id, data.cuenta_id))
        cursor.execute(
            """INSERT INTO trabajador (persona_id, departamento_id, meses_cotizados_previos)
               VALUES (%s, (SELECT departamento_id FROM departamento WHERE codigo='SC' LIMIT 1), 0)
               RETURNING trabajador_id""",
            (persona_id,)
        )
        trabajador_id = cursor.fetchone()[0]
        cursor.execute(
            """INSERT INTO contrato (trabajador_id, tipo_contrato, fecha_ingreso, sueldo_base, cargo, tipo_afp, institucion_salud, jornada_semanal_horas, estado)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'activo')""",
            (trabajador_id, data.tipo_contrato, data.fecha_ingreso, data.sueldo_base, data.cargo, data.afp, data.tipo_salud, data.jornada_semanal_horas)
        )
        cursor.execute("INSERT INTO saldo_vacaciones (trabajador_id, dias_disponibles, dias_progresivos) VALUES (%s, 15, 0)", (trabajador_id,))
        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": "Datos completados correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── PERFIL ────────────────────────────────────────────────────
@app.get("/perfil")
def perfil(payload: dict = Depends(verificar_token)):
    return {"correo": payload.get("sub"), "rol": payload.get("rol"), "nombre_completo": payload.get("nombre_completo")}


# ── COMPROBANTE PDF COMPENSACION ─────────────────────────────
@app.get("/comprobante-compensacion/{compensacion_id}")
def comprobante_compensacion(compensacion_id: int, payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """SELECT cp.compensacion_id, cp.dias_compensados, cp.monto_clp,
                      cp.estado, cp.fecha_solicitud, cp.fecha_decision, cp.observacion,
                      p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre,
                      p.rut,
                      p2.primer_nombre || ' ' || p2.apellido_paterno AS nombre_admin
               FROM compensacion_progresiva cp
               JOIN trabajador t ON t.trabajador_id = cp.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN administrador a ON a.administrador_id = cp.aprobado_por
               LEFT JOIN persona p2 ON p2.persona_id = a.persona_id
               WHERE cp.compensacion_id = %s AND t.persona_id = %s""",
            (compensacion_id, persona_id)
        )
        r = cursor.fetchone()
        cursor.close(); conn.close()

        if not r:
            return {"success": False, "mensaje": "Comprobante no encontrado"}

        comp_id, dias, monto, estado, fecha_sol, fecha_dec, obs, nombre, rut, nombre_admin = r

        if estado != 'aprobado':
            return {"success": False, "mensaje": "Comprobante solo disponible para compensaciones aprobadas"}

        # Generar PDF
        buffer = io.BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=letter,
                                topMargin=inch, bottomMargin=inch,
                                leftMargin=inch, rightMargin=inch)
        styles = getSampleStyleSheet()
        story = []

        story.append(Paragraph("CLINICA ACONCAGUA", styles['Title']))
        story.append(Paragraph("COMPROBANTE DE COMPENSACION PROGRESIVA", styles['Heading2']))
        story.append(Spacer(1, 20))

        data_tabla = [
            ["Campo", "Valor"],
            ["Nombre completo",    nombre or "—"],
            ["RUT",                rut or "—"],
            ["Dias compensados",   str(dias)],
            ["Monto pagado",       f"${int(monto):,} CLP"],
            ["Fecha solicitud",    fecha_sol.strftime("%d/%m/%Y %H:%M") if fecha_sol else "—"],
            ["Fecha aprobacion",   fecha_dec.strftime("%d/%m/%Y %H:%M") if fecha_dec else "—"],
            ["Aprobado por",       nombre_admin or "Administrador"],
            ["Observacion",        obs or "Sin observacion"],
        ]

        tabla = Table(data_tabla, colWidths=[2.5*inch, 4*inch])
        tabla.setStyle(TableStyle([
            ('BACKGROUND',    (0,0), (-1,0), colors.HexColor('#001E42')),
            ('TEXTCOLOR',     (0,0), (-1,0), colors.white),
            ('FONTNAME',      (0,0), (-1,0), 'Helvetica-Bold'),
            ('FONTSIZE',      (0,0), (-1,-1), 11),
            ('ROWBACKGROUNDS',(0,1), (-1,-1), [colors.white, colors.HexColor('#F8FAFC')]),
            ('GRID',          (0,0), (-1,-1), 0.5, colors.HexColor('#E2E8F0')),
            ('PADDING',       (0,0), (-1,-1), 8),
        ]))
        story.append(tabla)
        story.append(Spacer(1, 30))
        story.append(Paragraph(
            "Este documento certifica el pago de compensacion en efectivo por dias de vacaciones progresivas.",
            styles['Normal']
        ))
        story.append(Spacer(1, 10))
        story.append(Paragraph(
            "Art. 68 Codigo del Trabajo — Vacaciones Progresivas",
            styles['Normal']
        ))

        doc.build(story)
        pdf_bytes = buffer.getvalue()
        buffer.close()

        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename=comprobante_compensacion_{compensacion_id}.pdf"}
        )
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ══════════════════════════════════════════════════════════════
# COMPENSACION PROGRESIVA
# ══════════════════════════════════════════════════════════════

# ── SOLICITAR COMPENSACION (trabajador) ──────────────────────
@app.post("/solicitar-compensacion-progresiva")
def solicitar_compensacion(body: SolicitudCompensacion, payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """SELECT t.trabajador_id, sv.dias_progresivos,
                      t.meses_cotizados_previos, p.fecha_ingreso, c.sueldo_base
               FROM trabajador t
               JOIN saldo_vacaciones sv ON sv.trabajador_id = t.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               LEFT JOIN contrato c ON c.trabajador_id = t.trabajador_id AND c.estado = 'activo'
               WHERE t.persona_id = %s""",
            (persona_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "No se encontro informacion del trabajador"}

        trabajador_id, dias_progresivos_bd, meses_previos, fecha_ingreso, sueldo_base = r

        if not sueldo_base or float(sueldo_base) <= 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "El trabajador no tiene un sueldo base activo registrado"}

        meses_previos_lim = min(int(meses_previos or 0), 120)

        if fecha_ingreso:
            prog = calcular_dias_progresivos(fecha_ingreso, meses_previos_lim)
            dias_prog_calculados = prog["dias_prog_calculados"]
        else:
            dias_prog_calculados = 0

        dias_progresivos = max(int(dias_progresivos_bd or 0), dias_prog_calculados)

        if body.dias_a_compensar <= 0:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "La cantidad de dias debe ser mayor a 0"}

        if body.dias_a_compensar > dias_progresivos:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"No puedes compensar mas de {dias_progresivos} dias progresivos disponibles"}

        # El monto NUNCA se toma del valor que manda el cliente (body.monto_calculado
        # se ignora a propósito) -- se recalcula siempre en el servidor con el
        # sueldo real guardado en la base de datos, para que no se pueda
        # manipular el monto desde afuera.
        monto_calculado_servidor = round(float(sueldo_base) / 30 * body.dias_a_compensar)

        conn.commit()
        cursor.close()
        conn.close()

        conn2 = get_connection()
        cur2  = conn2.cursor()

        cur2.execute(
            """SELECT COUNT(*) FROM compensacion_progresiva
               WHERE trabajador_id = %s AND estado = 'pendiente'""",
            (trabajador_id,)
        )
        row = cur2.fetchone()
        pendientes = row[0] if row else 0

        if pendientes > 0:
            cur2.close(); conn2.close()
            return {"success": False, "mensaje": "Ya tienes una solicitud de compensacion pendiente de aprobacion"}

        cur2.execute(
            """INSERT INTO compensacion_progresiva
               (trabajador_id, dias_compensados, monto_clp, estado)
               VALUES (%s, %s, %s, 'pendiente')
               RETURNING compensacion_id""",
            (trabajador_id, body.dias_a_compensar, monto_calculado_servidor)
        )
        compensacion_id = cur2.fetchone()[0]
        conn2.commit(); cur2.close(); conn2.close()

        return {"success": True, "mensaje": "Solicitud enviada correctamente. Pendiente de aprobacion del administrador.", "compensacion_id": compensacion_id}

    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── MIS COMPENSACIONES (trabajador) ──────────────────────────
@app.get("/mis-compensaciones-progresivas")
def mis_compensaciones(payload: dict = Depends(verificar_token)):
    try:
        persona_id = get_persona_id(payload)
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT cp.compensacion_id, cp.dias_compensados, cp.monto_clp,
                      cp.estado, cp.fecha_solicitud, cp.observacion
               FROM compensacion_progresiva cp
               JOIN trabajador t ON t.trabajador_id = cp.trabajador_id
               WHERE t.persona_id = %s
               ORDER BY cp.compensacion_id DESC""",
            (persona_id,)
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        compensaciones = []
        for row in rows:
            comp_id, dias, monto_clp, estado, fecha_sol, obs = row
            compensaciones.append({
                "compensacion_id":  comp_id,
                "dias_compensados": dias,
                "monto_clp":        int(monto_clp or 0),
                "estado":           estado.capitalize() if estado else "Pendiente",
                "fecha_solicitud":  fecha_sol.strftime("%d/%m/%Y") if fecha_sol else "—",
                "observacion":      obs or "",
            })
        return {"success": True, "compensaciones": compensaciones}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── TODAS LAS COMPENSACIONES (admin) ─────────────────────────
@app.get("/compensaciones-pendientes")
def compensaciones_admin(payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT cp.compensacion_id,
                      p.primer_nombre || ' ' || p.apellido_paterno || ' ' || p.apellido_materno AS nombre,
                      cp.monto_clp, cp.dias_compensados, cp.estado,
                      cp.fecha_solicitud, cp.fecha_decision, cp.observacion
               FROM compensacion_progresiva cp
               JOIN trabajador t ON t.trabajador_id = cp.trabajador_id
               JOIN persona p ON p.persona_id = t.persona_id
               ORDER BY CASE WHEN cp.estado = 'pendiente' THEN 0 ELSE 1 END,
                        cp.compensacion_id DESC"""
        )
        rows = cursor.fetchall()
        cursor.close(); conn.close()

        compensaciones = []
        for row in rows:
            comp_id, nombre, monto_clp, dias, estado, fecha_sol, fecha_dec, obs = row
            compensaciones.append({
                "compensacion_id":   comp_id,
                "nombre_trabajador": nombre or "",
                "dias_compensados":  dias,
                "monto_clp":         int(monto_clp or 0),
                "estado":            estado.capitalize() if estado else "Pendiente",
                "fecha_solicitud":   fecha_sol.strftime("%d/%m/%Y") if fecha_sol else "—",
                "fecha_decision":    fecha_dec.strftime("%d/%m/%Y") if fecha_dec else None,
                "observacion":       obs or "",
            })
        return {"success": True, "compensaciones": compensaciones}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}

# ── APROBAR O RECHAZAR COMPENSACION (admin) ───────────────────
@app.put("/aprobar-compensacion/{compensacion_id}")
def aprobar_compensacion(compensacion_id: int, body: DecisionCompensacion, payload: dict = Depends(verificar_token)):
    try:
        verificar_rol(payload, ["admin"])

        if body.estado not in ["Aprobada", "Rechazada"]:
            return {"success": False, "mensaje": "Estado invalido"}
        if body.estado == "Rechazada" and not body.observacion.strip():
            return {"success": False, "mensaje": "El motivo de rechazo es obligatorio"}

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """SELECT trabajador_id, dias_compensados, estado
               FROM compensacion_progresiva WHERE compensacion_id = %s""",
            (compensacion_id,)
        )
        r = cursor.fetchone()
        if not r:
            cursor.close(); conn.close()
            return {"success": False, "mensaje": "Solicitud no encontrada"}

        trabajador_id, dias, estado_actual = r
        if estado_actual != "pendiente":
            cursor.close(); conn.close()
            return {"success": False, "mensaje": f"Esta solicitud ya fue procesada ({estado_actual})"}

        persona_id_admin = get_persona_id(payload)
        cursor.execute("SELECT administrador_id FROM administrador WHERE persona_id = %s", (persona_id_admin,))
        admin = cursor.fetchone()
        administrador_id = admin[0] if admin else None

        nuevo_estado = "aprobado" if body.estado == "Aprobada" else "rechazado"
        cursor.execute(
            """UPDATE compensacion_progresiva
               SET estado = %s, observacion = %s,
                   aprobado_por = %s, fecha_decision = NOW()
               WHERE compensacion_id = %s""",
            (nuevo_estado, body.observacion, administrador_id, compensacion_id)
        )

        if body.estado == "Aprobada" and dias > 0:
            cursor.execute(
                """UPDATE saldo_vacaciones
                   SET dias_progresivos    = GREATEST(0, dias_progresivos - %s),
                       dias_vendidos       = COALESCE(dias_vendidos, 0) + %s,
                       ultima_actualizacion = NOW()
                   WHERE trabajador_id = %s""",
                (dias, dias, trabajador_id)
            )

        conn.commit(); cursor.close(); conn.close()
        return {"success": True, "mensaje": f"Solicitud {body.estado.lower()} correctamente"}
    except Exception as e:
        return {"success": False, "mensaje": manejar_error_interno(e, payload=payload)}