/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Seguridad - permisos
Archivo: 02_permisos.sql
Descripción:
  Asigna los permisos de los 5 roles (principio de mínimo privilegio).
  Seguridad por fila: los roles Usuario y Gerente Corporativo NO tienen
  acceso directo a las tablas con datos personales o financieros. Usan
  vistas (v_mi_..., v_..._mi_empresa) que filtran por la cuenta MySQL
  conectada: la cuenta debe llamarse igual que usuarios.nombre_usuario.
  Las vistas y procedimientos son SQL SECURITY DEFINER: se ejecutan con
  los permisos de quien los creó, y USER() devuelve la cuenta que llama.
Requisitos:
  Ejecutar después de 01_roles.sql, con los procedimientos y funciones
  ya creados. Ejecutar con el cliente mysql o MySQL Workbench (DELIMITER).
*/
USE coworking_grupo5;

-- =====================================================================
--  1. VISTAS DE SEGURIDAD POR FILA
-- =====================================================================

-- Perfil del usuario conectado
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mi_perfil AS
SELECT u.id_usuario, u.nombre_usuario, u.codigo_acceso, u.fecha_registro,
       u.ultimo_acceso, u.servicios_bloqueados,
       p.tipo_documento, p.numero_documento, p.primer_nombre, p.segundo_nombre,
       p.primer_apellido, p.segundo_apellido, p.fecha_nacimiento, p.telefono, p.email
FROM usuarios u
JOIN personas p ON p.id_persona = u.id_persona
WHERE u.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1);

-- Historial de membresías del usuario conectado
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_membresias AS
SELECT s.id_suscripcion, m.tipo_membresia, s.fecha_inicio, s.fecha_fin, s.estado
FROM suscripciones s
JOIN membresias m ON m.id_membresia = s.id_membresia
JOIN usuarios u   ON u.id_usuario   = s.id_usuario
WHERE u.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1);

-- Historial de reservas del usuario conectado
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_reservas AS
SELECT r.id_reserva, sc.nombre_sede, e.nombre AS espacio, e.tipo_espacio,
       r.fecha_inicio, r.fecha_fin, r.cantidad_personas, r.estado, r.fecha_creacion
FROM reservas r
JOIN espacios e         ON e.id_espacio = r.id_espacio
JOIN sedes_coworking sc ON sc.id_sede_coworking = e.id_sede_coworking
JOIN usuarios u         ON u.id_usuario = r.id_usuario
WHERE u.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1);

-- Historial de asistencias del usuario conectado
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_asistencias AS
SELECT c.fecha, c.hora_entrada, c.hora_salida, sc.nombre_sede, c.metodo,
       c.resultado, c.motivo_rechazo, c.id_reserva
FROM control_acceso c
JOIN sedes_coworking sc ON sc.id_sede_coworking = c.id_sede_coworking
JOIN usuarios u         ON u.id_usuario = c.id_usuario
WHERE u.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1);

-- Facturas del usuario conectado ("descargar facturas")
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_mis_facturas AS
SELECT f.numero_factura, f.fecha_emision, f.fecha_vencimiento, f.subtotal, f.iva,
       f.recargo, f.total, f.saldo_pendiente, f.estado, f.motivo_anulacion,
       d.concepto, d.precio AS valor_item,
       COALESCE(m.tipo_membresia, e.nombre, sv.nombre) AS descripcion_item
FROM facturas f
JOIN ventas v              ON v.id_venta = f.id_venta
JOIN usuarios u            ON u.id_usuario = v.id_usuario
JOIN detalles_venta d      ON d.id_venta = v.id_venta
LEFT JOIN suscripciones s  ON s.id_suscripcion = d.id_suscripcion
LEFT JOIN membresias m     ON m.id_membresia = s.id_membresia
LEFT JOIN reservas r       ON r.id_reserva = d.id_reserva
LEFT JOIN espacios e       ON e.id_espacio = r.id_espacio
LEFT JOIN servicio_usuario su ON su.id_servicio_usuario = d.id_servicio_usuario
LEFT JOIN servicios sv     ON sv.id_servicio = su.id_servicio
WHERE u.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1);

-- Empleados de la empresa del gerente conectado
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_empleados_mi_empresa AS
SELECT em.razon_social, ue.id_usuario, ue.nombre_usuario,
       CONCAT_WS(' ', p.primer_nombre, p.primer_apellido) AS nombre,
       p.email, p.telefono, ee.es_gerente,
       (SELECT s.estado FROM suscripciones s
         WHERE s.id_usuario = ue.id_usuario
         ORDER BY s.fecha_fin DESC LIMIT 1)                AS estado_membresia,
       ue.ultimo_acceso
FROM usuarios ug
JOIN empleados_empresa eg ON eg.id_persona = ug.id_persona AND eg.es_gerente
JOIN empresas em          ON em.id_empresa = eg.id_empresa
JOIN empleados_empresa ee ON ee.id_empresa = em.id_empresa
JOIN personas p           ON p.id_persona  = ee.id_persona
JOIN usuarios ue          ON ue.id_persona = ee.id_persona
WHERE ug.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1);

-- Facturación consolidada de la empresa del gerente conectado
CREATE OR REPLACE SQL SECURITY DEFINER VIEW v_facturacion_mi_empresa AS
SELECT em.razon_social, f.numero_factura, f.fecha_emision, f.fecha_vencimiento,
       f.subtotal, f.iva, f.recargo, f.total, f.saldo_pendiente, f.estado,
       (SELECT COUNT(*) FROM detalles_venta d WHERE d.id_venta = v.id_venta) AS cargos
FROM usuarios ug
JOIN empleados_empresa eg ON eg.id_persona = ug.id_persona AND eg.es_gerente
JOIN empresas em          ON em.id_empresa = eg.id_empresa
JOIN ventas v             ON v.id_empresa  = em.id_empresa
JOIN facturas f           ON f.id_venta    = v.id_venta
WHERE ug.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1);

-- =====================================================================
--  2. PROCEDIMIENTOS DE AUTOSERVICIO (validan que el dato sea del que llama)
-- =====================================================================
DELIMITER $$

-- Reservar un espacio a nombre del usuario conectado
DROP PROCEDURE IF EXISTS sp_usuario_reservar $$
CREATE PROCEDURE sp_usuario_reservar(
    IN p_id_espacio INT, IN p_inicio DATETIME, IN p_fin DATETIME, IN p_personas INT)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_id_usuario INT;
    DECLARE v_id_reserva INT;
    SELECT id_usuario INTO v_id_usuario FROM usuarios
     WHERE nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1);
    IF v_id_usuario IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cuenta MySQL no corresponde a ningun usuario del coworking';
    END IF;
    CALL sp_crear_reserva(v_id_usuario, p_id_espacio, p_inicio, p_fin, p_personas, v_id_reserva);
END $$

-- Cancelar una reserva propia (aplica la política de reembolso)
DROP PROCEDURE IF EXISTS sp_usuario_cancelar_reserva $$
CREATE PROCEDURE sp_usuario_cancelar_reserva(IN p_id_reserva INT)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_monto DECIMAL(10,2);
    IF NOT EXISTS (SELECT 1 FROM reservas r JOIN usuarios u ON u.id_usuario = r.id_usuario
                    WHERE r.id_reserva = p_id_reserva
                      AND u.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe o no pertenece al usuario conectado';
    END IF;
    CALL sp_cancelar_reserva(p_id_reserva, NULL, v_monto);
END $$

-- Registrar empleados en la empresa del gerente conectado
DROP PROCEDURE IF EXISTS sp_gerente_registrar_empleados $$
CREATE PROCEDURE sp_gerente_registrar_empleados(IN p_empleados JSON, IN p_fecha_inicio DATE)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_id_empresa INT;
    DECLARE v_registrados INT;
    SELECT ee.id_empresa INTO v_id_empresa
      FROM usuarios u
      JOIN empleados_empresa ee ON ee.id_persona = u.id_persona AND ee.es_gerente
     WHERE u.nombre_usuario = SUBSTRING_INDEX(USER(), '@', 1)
     LIMIT 1;
    IF v_id_empresa IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cuenta conectada no es gerente de ninguna empresa';
    END IF;
    CALL sp_registrar_lote_empleados(v_id_empresa, p_empleados, p_fecha_inicio, v_registrados);
END $$

DELIMITER ;

-- =====================================================================
--  3. ROL ADMINISTRADOR: acceso total a la base de datos
-- =====================================================================
GRANT ALL PRIVILEGES ON coworking_grupo5.* TO 'rol_administrador' WITH GRANT OPTION;

-- =====================================================================
--  4. ROL RECEPCIONISTA: usuarios, membresías y reservas
-- =====================================================================
-- Consulta de la operación diaria
GRANT SELECT ON coworking_grupo5.personas             TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.usuarios             TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.empresas             TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.empleados_empresa    TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.membresias           TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.suscripciones        TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.sedes_coworking      TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.horarios_atencion    TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.espacios             TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.servicios            TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.servicio_espacio     TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.reservas             TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.control_acceso       TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.registro_asistencias TO 'rol_recepcionista';
GRANT SELECT ON coworking_grupo5.metodos_pago         TO 'rol_recepcionista';
GRANT SELECT, UPDATE (leida) ON coworking_grupo5.notificaciones TO 'rol_recepcionista';
-- Registro de usuarios
GRANT INSERT, UPDATE ON coworking_grupo5.personas          TO 'rol_recepcionista';
GRANT INSERT, UPDATE ON coworking_grupo5.usuarios          TO 'rol_recepcionista';
GRANT INSERT         ON coworking_grupo5.empleados_empresa TO 'rol_recepcionista';
GRANT INSERT         ON coworking_grupo5.servicio_usuario  TO 'rol_recepcionista';
-- Membresías, reservas y accesos a través de procedimientos
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_registrar_membresia       TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_renovar_membresia         TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_generar_factura_membresia TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_verificar_disponibilidad  TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_crear_reserva             TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_confirmar_reserva_pago    TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_cancelar_reserva          TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_registrar_entrada         TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_registrar_salida          TO 'rol_recepcionista';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_reporte_diario_asistencias TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_membresia_activa          TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_estado_membresia          TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_tipo_membresia            TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_dias_restantes_membresia  TO 'rol_recepcionista';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_reservas_activas          TO 'rol_recepcionista';

-- =====================================================================
--  5. ROL USUARIO: reservar, consultar su historial, descargar facturas
-- =====================================================================
-- Catálogo público (no contiene datos personales)
GRANT SELECT ON coworking_grupo5.sedes_coworking   TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.horarios_atencion TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.espacios          TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.servicios         TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.servicio_espacio  TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.membresias        TO 'rol_usuario';
-- Solo sus propios datos
GRANT SELECT ON coworking_grupo5.v_mi_perfil       TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.v_mis_membresias  TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.v_mis_reservas    TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.v_mis_asistencias TO 'rol_usuario';
GRANT SELECT ON coworking_grupo5.v_mis_facturas    TO 'rol_usuario';
-- Reservar y cancelar sus reservas
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_verificar_disponibilidad TO 'rol_usuario';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_usuario_reservar         TO 'rol_usuario';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_usuario_cancelar_reserva TO 'rol_usuario';

-- =====================================================================
--  6. ROL GERENTE CORPORATIVO: empleados de su empresa y facturación
--     consolidada. También es usuario del coworking (hereda rol_usuario).
-- =====================================================================
GRANT 'rol_usuario' TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking_grupo5.v_empleados_mi_empresa   TO 'rol_gerente_corporativo';
GRANT SELECT ON coworking_grupo5.v_facturacion_mi_empresa TO 'rol_gerente_corporativo';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_gerente_registrar_empleados TO 'rol_gerente_corporativo';

-- =====================================================================
--  7. ROL CONTADOR: ingresos y reportes financieros
-- =====================================================================
GRANT SELECT ON coworking_grupo5.ventas               TO 'rol_contador';
GRANT SELECT ON coworking_grupo5.detalles_venta       TO 'rol_contador';
GRANT SELECT ON coworking_grupo5.pagos                TO 'rol_contador';
GRANT SELECT ON coworking_grupo5.facturas             TO 'rol_contador';
GRANT SELECT ON coworking_grupo5.reembolsos           TO 'rol_contador';
GRANT SELECT ON coworking_grupo5.metodos_pago         TO 'rol_contador';
GRANT SELECT ON coworking_grupo5.empresas             TO 'rol_contador';
GRANT SELECT ON coworking_grupo5.membresias           TO 'rol_contador';
GRANT SELECT ON coworking_grupo5.servicios            TO 'rol_contador';
GRANT SELECT (id_usuario, nombre_usuario) ON coworking_grupo5.usuarios TO 'rol_contador';
GRANT SELECT, INSERT, UPDATE ON coworking_grupo5.reportes_financieros  TO 'rol_contador';
-- Anular facturas (solo esas dos columnas)
GRANT UPDATE (estado, motivo_anulacion) ON coworking_grupo5.facturas TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_generar_factura_membresia  TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_generar_factura_empresa    TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_aplicar_recargos           TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_bloquear_servicios_morosos TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_suspender_membresias_morosas TO 'rol_contador';
GRANT EXECUTE ON PROCEDURE coworking_grupo5.sp_reporte_ingresos_mensuales TO 'rol_contador';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_total_pagado               TO 'rol_contador';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_ingresos_por_mes           TO 'rol_contador';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_ingresos_por_membresias    TO 'rol_contador';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_ingresos_por_reservas      TO 'rol_contador';
GRANT EXECUTE ON FUNCTION  coworking_grupo5.fn_ingresos_por_empresa       TO 'rol_contador';

-- Verificación
SHOW GRANTS FOR 'rol_recepcionista';
SHOW GRANTS FOR 'rol_usuario';
SHOW GRANTS FOR 'rol_gerente_corporativo';
SHOW GRANTS FOR 'rol_contador';
