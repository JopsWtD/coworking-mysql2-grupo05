/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Estructura de la base de datos (DDL)
Archivo: 01_estructura.sql
Descripción:
  Crea la base de datos coworking_grupo5 con sus 25 tablas, llaves
  primarias y foráneas, restricciones UNIQUE y CHECK, índices secundarios
  y el catálogo de métodos de pago definido por el enunciado.
  Convenciones: tablas y columnas en snake_case; restricciones con
  prefijos pk_/fk_/uq_/chk_ e índices secundarios con prefijo idx_.
  Fechas: fecha_fin de una suscripción es exclusiva (la membresía cubre
  fecha_inicio <= día < fecha_fin). Montos de ventas/detalles SIN IVA.
Requisitos:
  MySQL 8.0.16 o superior (CHECK, roles, CTE recursivos, funciones de
  ventana y valores por defecto con expresiones).
*/

-- DROP DATABASE IF EXISTS coworking_grupo5;
CREATE DATABASE IF NOT EXISTS coworking_grupo5
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE coworking_grupo5;

-- =====================================================================
--  1. COWORKING, SEDES Y ESPACIOS
-- =====================================================================

CREATE TABLE coworking (
  id_coworking      INT AUTO_INCREMENT PRIMARY KEY,
  nombre_coworking  VARCHAR(150) NOT NULL UNIQUE
) ENGINE = InnoDB;

CREATE TABLE sedes_coworking (
  id_sede_coworking INT AUTO_INCREMENT PRIMARY KEY,
  id_coworking      INT NOT NULL,
  nombre_sede       VARCHAR(150) NOT NULL,
  CONSTRAINT uq_sede_nombre UNIQUE (id_coworking, nombre_sede),
  CONSTRAINT fk_sede_coworking FOREIGN KEY (id_coworking)
    REFERENCES coworking (id_coworking)
) ENGINE = InnoDB;

CREATE TABLE horarios_atencion (
  id_horario        INT AUTO_INCREMENT PRIMARY KEY,
  id_sede_coworking INT NOT NULL,
  dia_semana        ENUM('LUNES','MARTES','MIERCOLES','JUEVES','VIERNES','SABADO','DOMINGO') NOT NULL,
  hora_inicio       TIME NOT NULL,
  hora_fin          TIME NOT NULL,
  CONSTRAINT uq_horario_sede_dia UNIQUE (id_sede_coworking, dia_semana),
  CONSTRAINT chk_horario_horas CHECK (hora_fin > hora_inicio),
  CONSTRAINT fk_horario_sede FOREIGN KEY (id_sede_coworking)
    REFERENCES sedes_coworking (id_sede_coworking)
) ENGINE = InnoDB;

CREATE TABLE espacios (
  id_espacio        INT AUTO_INCREMENT PRIMARY KEY,
  id_sede_coworking INT NOT NULL,
  tipo_espacio      ENUM('ESCRITORIO_FLEXIBLE','OFICINA_PRIVADA','SALA_REUNIONES','SALA_EVENTOS') NOT NULL,
  nombre            VARCHAR(150) NOT NULL,
  capacidad         INT NOT NULL,
  precio_hora       DECIMAL(10,2) NOT NULL,
  estado            ENUM('DISPONIBLE','MANTENIMIENTO','INACTIVO') NOT NULL DEFAULT 'DISPONIBLE',
  CONSTRAINT uq_espacio_sede_nombre UNIQUE (id_sede_coworking, nombre),
  CONSTRAINT chk_espacio_capacidad CHECK (capacidad > 0),
  CONSTRAINT chk_espacio_precio CHECK (precio_hora >= 0),
  CONSTRAINT fk_espacio_sede FOREIGN KEY (id_sede_coworking)
    REFERENCES sedes_coworking (id_sede_coworking)
) ENGINE = InnoDB;

-- =====================================================================
--  2. SERVICIOS ADICIONALES (catálogo)
-- =====================================================================

CREATE TABLE servicios (
  id_servicio  INT AUTO_INCREMENT PRIMARY KEY,
  nombre       VARCHAR(100) NOT NULL UNIQUE,
  descripcion  VARCHAR(255) NULL,
  precio       DECIMAL(10,2) NOT NULL,
  CONSTRAINT chk_servicio_precio CHECK (precio >= 0)
) ENGINE = InnoDB;

CREATE TABLE servicio_espacio (
  id_servicio_espacio INT AUTO_INCREMENT PRIMARY KEY,
  id_servicio         INT NOT NULL,
  id_espacio          INT NOT NULL,
  CONSTRAINT uq_servicio_espacio UNIQUE (id_servicio, id_espacio),
  CONSTRAINT fk_se_servicio FOREIGN KEY (id_servicio)
    REFERENCES servicios (id_servicio),
  CONSTRAINT fk_se_espacio FOREIGN KEY (id_espacio)
    REFERENCES espacios (id_espacio)
) ENGINE = InnoDB;

-- =====================================================================
--  3. PERSONAS, EMPRESAS Y USUARIOS
-- =====================================================================

CREATE TABLE empresas (
  id_empresa        INT AUTO_INCREMENT PRIMARY KEY,
  nit_empresa       VARCHAR(20)  NOT NULL UNIQUE,
  razon_social      VARCHAR(150) NOT NULL,
  nombre_comercial  VARCHAR(150) NULL,
  email             VARCHAR(150) NOT NULL
) ENGINE = InnoDB;

CREATE TABLE personas (
  id_persona        INT AUTO_INCREMENT PRIMARY KEY,
  tipo_documento    ENUM('CC','CE','TI','PASAPORTE','PPT') NOT NULL,
  numero_documento  VARCHAR(20)  NOT NULL,
  primer_nombre     VARCHAR(30)  NOT NULL,
  segundo_nombre    VARCHAR(30)  NULL,
  primer_apellido   VARCHAR(30)  NOT NULL,
  segundo_apellido  VARCHAR(30)  NULL,
  fecha_nacimiento  DATE         NOT NULL,
  telefono          VARCHAR(15)  NULL,
  email             VARCHAR(150) NOT NULL UNIQUE,
  CONSTRAINT uq_persona_documento UNIQUE (tipo_documento, numero_documento)
) ENGINE = InnoDB;

CREATE TABLE empleados_empresa (
  id_empleado  INT AUTO_INCREMENT PRIMARY KEY,
  id_persona   INT NOT NULL,
  id_empresa   INT NOT NULL,
  es_gerente   BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT uq_empleado_empresa UNIQUE (id_persona, id_empresa),
  CONSTRAINT fk_empleado_persona FOREIGN KEY (id_persona)
    REFERENCES personas (id_persona),
  CONSTRAINT fk_empleado_empresa FOREIGN KEY (id_empresa)
    REFERENCES empresas (id_empresa)
) ENGINE = InnoDB;

CREATE TABLE usuarios (
  id_usuario            INT AUTO_INCREMENT PRIMARY KEY,
  id_persona            INT NOT NULL UNIQUE,              -- relación 1:1 con personas
  nombre_usuario        VARCHAR(30) NOT NULL UNIQUE,
  contrasena            VARCHAR(60) NOT NULL,             -- hash (bcrypt = 60 caracteres)
  codigo_acceso         VARCHAR(60) NOT NULL UNIQUE,      -- código RFID / QR
  fecha_registro        DATE NOT NULL DEFAULT (CURRENT_DATE),
  ultimo_acceso         TIMESTAMP NULL,
  servicios_bloqueados  BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_usuario_persona FOREIGN KEY (id_persona)
    REFERENCES personas (id_persona)
) ENGINE = InnoDB;

-- =====================================================================
--  4. MEMBRESÍAS Y SUSCRIPCIONES
-- =====================================================================

-- Duración por tipo (se calcula en el trigger de suscripciones):
--   DIARIA = 1 día | MENSUAL = 1 mes | CORPORATIVA = 1 mes | PREMIUM = 1 año
CREATE TABLE membresias (
  id_membresia    INT AUTO_INCREMENT PRIMARY KEY,
  tipo_membresia  ENUM('DIARIA','MENSUAL','CORPORATIVA','PREMIUM') NOT NULL UNIQUE,
  precio          DECIMAL(10,2) NOT NULL,
  CONSTRAINT chk_membresia_precio CHECK (precio >= 0)
) ENGINE = InnoDB;

-- PENDIENTE: creada pero aún sin pago (pasa a ACTIVA con un pago exitoso)
CREATE TABLE suscripciones (
  id_suscripcion  INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario      INT NOT NULL,
  id_membresia    INT NOT NULL,
  fecha_inicio    DATE NOT NULL,
  fecha_fin       DATE NOT NULL,                          -- la calcula el trigger
  estado          ENUM('PENDIENTE','ACTIVA','SUSPENDIDA','VENCIDA') NOT NULL DEFAULT 'PENDIENTE',
  CONSTRAINT chk_suscripcion_fechas CHECK (fecha_fin > fecha_inicio),
  CONSTRAINT fk_suscripcion_usuario FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario),
  CONSTRAINT fk_suscripcion_membresia FOREIGN KEY (id_membresia)
    REFERENCES membresias (id_membresia)
) ENGINE = InnoDB;

-- =====================================================================
--  5. RESERVAS Y CONSUMO DE SERVICIOS
-- =====================================================================

CREATE TABLE reservas (
  id_reserva         INT AUTO_INCREMENT PRIMARY KEY,
  id_espacio         INT NOT NULL,
  id_usuario         INT NOT NULL,
  fecha_inicio       TIMESTAMP NOT NULL,
  fecha_fin          TIMESTAMP NOT NULL,
  cantidad_personas  INT NOT NULL DEFAULT 1,
  estado             ENUM('PENDIENTE','CONFIRMADA','CANCELADA','FINALIZADA','NO_SHOW') NOT NULL DEFAULT 'PENDIENTE',
  fecha_creacion     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_reserva_fechas CHECK (fecha_fin > fecha_inicio),
  CONSTRAINT chk_reserva_personas CHECK (cantidad_personas > 0),
  CONSTRAINT fk_reserva_espacio FOREIGN KEY (id_espacio)
    REFERENCES espacios (id_espacio),
  CONSTRAINT fk_reserva_usuario FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario)
) ENGINE = InnoDB;

CREATE TABLE servicio_usuario (
  id_servicio_usuario INT AUTO_INCREMENT PRIMARY KEY,
  id_servicio         INT NOT NULL,
  id_usuario          INT NOT NULL,
  id_reserva          INT NULL,                           -- si se consumió dentro de una reserva
  fecha               DATE NOT NULL DEFAULT (CURRENT_DATE),
  cantidad            INT NOT NULL DEFAULT 1,
  CONSTRAINT chk_su_cantidad CHECK (cantidad > 0),
  CONSTRAINT fk_su_servicio FOREIGN KEY (id_servicio)
    REFERENCES servicios (id_servicio),
  CONSTRAINT fk_su_usuario FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario),
  CONSTRAINT fk_su_reserva FOREIGN KEY (id_reserva)
    REFERENCES reservas (id_reserva)
) ENGINE = InnoDB;

-- =====================================================================
--  6. CONTROL DE ACCESO Y ASISTENCIA
-- =====================================================================

CREATE TABLE control_acceso (
  id_control         INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario         INT NULL,                            -- NULL si el código no existe
  id_sede_coworking  INT NOT NULL,
  id_reserva         INT NULL,                            -- NULL si entró por membresía
  fecha              DATE NOT NULL DEFAULT (CURRENT_DATE),
  hora_entrada       TIME NOT NULL,                       -- hora del intento / entrada
  hora_salida        TIME NULL,                           -- NULL mientras no salga
  metodo             ENUM('RFID','QR') NOT NULL,
  resultado          ENUM('PERMITIDO','DENEGADO') NOT NULL,
  motivo_rechazo     ENUM('MEMBRESIA_INACTIVA','SIN_RESERVA','CODIGO_INVALIDO','FUERA_DE_HORARIO') NULL,
  CONSTRAINT chk_acceso_motivo CHECK (
    (resultado = 'PERMITIDO' AND motivo_rechazo IS NULL) OR
    (resultado = 'DENEGADO'  AND motivo_rechazo IS NOT NULL)
  ),
  CONSTRAINT chk_acceso_usuario CHECK (
    id_usuario IS NOT NULL OR motivo_rechazo = 'CODIGO_INVALIDO'
  ),
  CONSTRAINT fk_acceso_usuario FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario),
  CONSTRAINT fk_acceso_sede FOREIGN KEY (id_sede_coworking)
    REFERENCES sedes_coworking (id_sede_coworking),
  CONSTRAINT fk_acceso_reserva FOREIGN KEY (id_reserva)
    REFERENCES reservas (id_reserva)
) ENGINE = InnoDB;

CREATE TABLE registro_asistencias (
  id_registro        INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario         INT NOT NULL,
  id_sede_coworking  INT NOT NULL,
  id_reserva         INT NULL,
  fecha_hora         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_asistencia_usuario FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario),
  CONSTRAINT fk_asistencia_sede FOREIGN KEY (id_sede_coworking)
    REFERENCES sedes_coworking (id_sede_coworking),
  CONSTRAINT fk_asistencia_reserva FOREIGN KEY (id_reserva)
    REFERENCES reservas (id_reserva)
) ENGINE = InnoDB;

-- =====================================================================
--  7. VENTAS, PAGOS Y FACTURACIÓN
-- =====================================================================

CREATE TABLE metodos_pago (
  id_metodo_pago  INT AUTO_INCREMENT PRIMARY KEY,
  nombre          VARCHAR(70) NOT NULL UNIQUE
) ENGINE = InnoDB;

-- Quien paga: un usuario O una empresa (exactamente uno)
CREATE TABLE ventas (
  id_venta    INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario  INT NULL,
  id_empresa  INT NULL,
  fecha_hora  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  total       DECIMAL(10,2) NOT NULL DEFAULT 0,          -- valor SIN IVA (suma de los detalles)
  CONSTRAINT chk_venta_comprador CHECK ((id_usuario IS NULL) <> (id_empresa IS NULL)),
  CONSTRAINT chk_venta_total CHECK (total >= 0),
  CONSTRAINT fk_venta_usuario FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario),
  CONSTRAINT fk_venta_empresa FOREIGN KEY (id_empresa)
    REFERENCES empresas (id_empresa)
) ENGINE = InnoDB;

-- Qué se vende: exactamente uno de los tres FK, coherente con el concepto.
-- PENALIZACION = cargo por No Show, ligado a la reserva.
CREATE TABLE detalles_venta (
  id_detalle           INT AUTO_INCREMENT PRIMARY KEY,
  id_venta             INT NOT NULL,
  id_suscripcion       INT NULL UNIQUE,                   -- una suscripción se vende una sola vez
  id_reserva           INT NULL,
  id_servicio_usuario  INT NULL UNIQUE,                   -- un consumo se cobra una sola vez
  concepto             ENUM('MEMBRESIA','RESERVA','SERVICIO','PENALIZACION') NOT NULL,
  precio               DECIMAL(10,2) NOT NULL,            -- precio congelado al vender (sin IVA)
  CONSTRAINT chk_detalle_concepto CHECK (
    (concepto = 'MEMBRESIA'
       AND id_suscripcion IS NOT NULL AND id_reserva IS NULL AND id_servicio_usuario IS NULL) OR
    (concepto IN ('RESERVA','PENALIZACION')
       AND id_reserva IS NOT NULL AND id_suscripcion IS NULL AND id_servicio_usuario IS NULL) OR
    (concepto = 'SERVICIO'
       AND id_servicio_usuario IS NOT NULL AND id_suscripcion IS NULL AND id_reserva IS NULL)
  ),
  CONSTRAINT chk_detalle_precio CHECK (precio >= 0),
  CONSTRAINT fk_detalle_venta FOREIGN KEY (id_venta)
    REFERENCES ventas (id_venta),
  CONSTRAINT fk_detalle_suscripcion FOREIGN KEY (id_suscripcion)
    REFERENCES suscripciones (id_suscripcion),
  CONSTRAINT fk_detalle_reserva FOREIGN KEY (id_reserva)
    REFERENCES reservas (id_reserva),
  CONSTRAINT fk_detalle_servicio_usuario FOREIGN KEY (id_servicio_usuario)
    REFERENCES servicio_usuario (id_servicio_usuario)
) ENGINE = InnoDB;

-- Una venta puede tener varios pagos (pagos parciales / varios métodos)
CREATE TABLE pagos (
  id_pago         INT AUTO_INCREMENT PRIMARY KEY,
  id_venta        INT NOT NULL,
  id_metodo_pago  INT NOT NULL,
  monto           DECIMAL(10,2) NOT NULL,
  fecha_pago      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  estado          ENUM('PAGADO','PENDIENTE','CANCELADO') NOT NULL DEFAULT 'PENDIENTE',
  CONSTRAINT chk_pago_monto CHECK (monto > 0),
  CONSTRAINT fk_pago_venta FOREIGN KEY (id_venta)
    REFERENCES ventas (id_venta),
  CONSTRAINT fk_pago_metodo FOREIGN KEY (id_metodo_pago)
    REFERENCES metodos_pago (id_metodo_pago)
) ENGINE = InnoDB;

-- Relación 1:1 con ventas (id_venta UNIQUE)
CREATE TABLE facturas (
  id_factura         INT AUTO_INCREMENT PRIMARY KEY,
  id_venta           INT NOT NULL UNIQUE,
  numero_factura     VARCHAR(20) NOT NULL UNIQUE,
  fecha_emision      DATE NOT NULL DEFAULT (CURRENT_DATE),
  fecha_vencimiento  DATE NOT NULL,
  subtotal           DECIMAL(10,2) NOT NULL DEFAULT 0,    -- sin IVA
  iva                DECIMAL(10,2) NOT NULL DEFAULT 0,
  recargo            DECIMAL(10,2) NOT NULL DEFAULT 0,
  total              DECIMAL(10,2) NOT NULL DEFAULT 0,    -- subtotal + iva + recargo
  saldo_pendiente    DECIMAL(10,2) NOT NULL DEFAULT 0,
  estado             ENUM('PENDIENTE','PAGADA','ANULADA') NOT NULL DEFAULT 'PENDIENTE',
  motivo_anulacion   VARCHAR(255) NULL,
  CONSTRAINT chk_factura_fechas CHECK (fecha_vencimiento >= fecha_emision),
  CONSTRAINT chk_factura_valores CHECK (
    subtotal >= 0 AND iva >= 0 AND recargo >= 0 AND total >= 0
  ),
  CONSTRAINT chk_factura_saldo CHECK (saldo_pendiente >= 0 AND saldo_pendiente <= total),
  CONSTRAINT chk_factura_anulacion CHECK (
    (estado = 'ANULADA' AND motivo_anulacion IS NOT NULL) OR
    (estado <> 'ANULADA' AND motivo_anulacion IS NULL)
  ),
  CONSTRAINT fk_factura_venta FOREIGN KEY (id_venta)
    REFERENCES ventas (id_venta)
) ENGINE = InnoDB;

CREATE TABLE reembolsos (
  id_reembolso  INT AUTO_INCREMENT PRIMARY KEY,
  id_pago       INT NOT NULL,
  id_reserva    INT NULL,
  monto         DECIMAL(10,2) NOT NULL,
  motivo        VARCHAR(255) NOT NULL,
  fecha         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_reembolso_monto CHECK (monto > 0),
  CONSTRAINT fk_reembolso_pago FOREIGN KEY (id_pago)
    REFERENCES pagos (id_pago),
  CONSTRAINT fk_reembolso_reserva FOREIGN KEY (id_reserva)
    REFERENCES reservas (id_reserva)
) ENGINE = InnoDB;

-- =====================================================================
--  8. REPORTES, NOTIFICACIONES Y AUDITORÍA
-- =====================================================================

CREATE TABLE reportes_financieros (
  id_reporte         INT AUTO_INCREMENT PRIMARY KEY,
  fecha_inicio       DATE NOT NULL,
  fecha_fin          DATE NOT NULL,
  ingresos           DECIMAL(12,2) NOT NULL DEFAULT 0,    -- sin IVA
  iva_generado       DECIMAL(12,2) NOT NULL DEFAULT 0,
  total_recaudado    DECIMAL(12,2) NOT NULL DEFAULT 0,
  cantidad_facturas  INT NOT NULL DEFAULT 0,
  fecha_generacion   DATE NOT NULL DEFAULT (CURRENT_DATE),
  CONSTRAINT chk_reporte_fechas CHECK (fecha_fin >= fecha_inicio)
) ENGINE = InnoDB;

CREATE TABLE notificaciones (
  id_notificacion  INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario       INT NULL,
  destinatario     ENUM('USUARIO','ADMINISTRADOR','RECEPCION','CONTADOR','GERENTE_CORPORATIVO') NOT NULL,
  tipo             VARCHAR(50)  NOT NULL,
  mensaje          VARCHAR(255) NOT NULL,
  fecha_hora       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  leida            BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT chk_notificacion_usuario CHECK (destinatario <> 'USUARIO' OR id_usuario IS NOT NULL),
  CONSTRAINT fk_notificacion_usuario FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario)
) ENGINE = InnoDB;

CREATE TABLE log_auditoria (
  id_log          INT AUTO_INCREMENT PRIMARY KEY,
  tabla_afectada  VARCHAR(50)  NOT NULL,
  id_registro     INT          NULL,
  accion          VARCHAR(50)  NOT NULL,
  detalle         VARCHAR(255) NULL,
  fecha_hora      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

-- =====================================================================
--  9. ÍNDICES SECUNDARIOS
--  (las llaves foráneas ya crean su propio índice; estos aceleran las
--   búsquedas por fechas y estados que usan triggers, eventos y consultas)
-- =====================================================================

-- Validación de solapamiento de reservas (trigger 6 y sp_verificar_disponibilidad)
CREATE INDEX idx_reservas_espacio_fechas   ON reservas (id_espacio, fecha_inicio, fecha_fin);
-- Reservas por estado y fecha (eventos de liberación, no show, recordatorios)
CREATE INDEX idx_reservas_estado_fecha     ON reservas (estado, fecha_inicio);
-- Membresía vigente de un usuario (funciones fn_membresia_activa, validación de acceso)
CREATE INDEX idx_suscripciones_usuario_estado ON suscripciones (id_usuario, estado, fecha_fin);
-- Accesos del día por usuario (salida automática, reportes diarios)
CREATE INDEX idx_control_acceso_usuario_fecha ON control_acceso (id_usuario, fecha);
CREATE INDEX idx_control_acceso_fecha      ON control_acceso (fecha, resultado);
-- Asistencias por fecha (reportes y consultas de asistencia)
CREATE INDEX idx_registro_asistencias_fecha ON registro_asistencias (fecha_hora);
-- Facturas pendientes y vencidas (recargos, bloqueos, suspensiones)
CREATE INDEX idx_facturas_estado_vencimiento ON facturas (estado, fecha_vencimiento);
CREATE INDEX idx_facturas_emision          ON facturas (fecha_emision);
-- Pagos por estado y fecha (recaudo, reportes)
CREATE INDEX idx_pagos_estado_fecha        ON pagos (estado, fecha_pago);
-- Ventas por fecha (ingresos por mes)
CREATE INDEX idx_ventas_fecha              ON ventas (fecha_hora);

-- =====================================================================
--  10. DATOS BASE DEL CATÁLOGO (definidos por el enunciado)
-- =====================================================================

INSERT INTO metodos_pago (nombre) VALUES
  ('Efectivo'), ('Tarjeta'), ('Transferencia'), ('PayPal');
