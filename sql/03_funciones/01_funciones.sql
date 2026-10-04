/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Funciones
Archivo: 01_funciones.sql
Descripción:
  20 funciones definidas por el usuario (5 por módulo): Membresías,
  Reservas, Pagos y Facturación, Accesos y Asistencias.
  Criterios:
    * Membresía activa = suscripción ACTIVA con fecha_inicio <= hoy < fecha_fin
                         (fecha_fin es exclusiva, igual que en el resto del sistema).
    * Reserva activa   = reserva PENDIENTE o CONFIRMADA que aún no terminó.
    * "Ingresos"       = valor SIN IVA de ventas con factura PAGADA.
    * "Total pagado"   = suma de pagos PAGADO (incluye IVA).
Requisitos:
  Ejecutar previamente DDL y DML. Ejecutar con el cliente mysql o
  MySQL Workbench (usa DELIMITER). Con binlog activo, el usuario que las
  cree necesita privilegio SUPER o log_bin_trust_function_creators = 1.
*/
USE coworking_grupo5;
DELIMITER $$

-- ---------------------------------------------------------------------
--  MEMBRESÍAS (5)
-- ---------------------------------------------------------------------

-- =========================================
-- FUNCION 01: fn_membresia_activa(usuario_id)
-- Devuelve TRUE (1) si el usuario tiene una membresía activa y vigente.
-- =========================================
DROP FUNCTION IF EXISTS fn_membresia_activa $$
CREATE FUNCTION fn_membresia_activa(p_usuario_id INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
  RETURN (SELECT COUNT(*) > 0
            FROM suscripciones
           WHERE id_usuario = p_usuario_id
             AND estado = 'ACTIVA'
             AND CURDATE() >= fecha_inicio
             AND CURDATE() <  fecha_fin);      -- fecha_fin es exclusiva
END $$

-- =========================================
-- FUNCION 02: fn_dias_restantes_membresia(usuario_id)
-- Días de vigencia que le quedan (0 si no tiene membresía activa).
-- Como las membresías son acumulables, cuenta hasta el final de la
-- última membresía ACTIVA ya pagada (aunque empiece en el futuro).
-- =========================================
DROP FUNCTION IF EXISTS fn_dias_restantes_membresia $$
CREATE FUNCTION fn_dias_restantes_membresia(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
  IF NOT fn_membresia_activa(p_usuario_id) THEN
    RETURN 0;
  END IF;
  RETURN (SELECT DATEDIFF(MAX(fecha_fin), CURDATE())
            FROM suscripciones
           WHERE id_usuario = p_usuario_id
             AND estado = 'ACTIVA'
             AND fecha_fin > CURDATE());
END $$

-- =========================================
-- FUNCION 03: fn_tipo_membresia(usuario_id)
-- Tipo de la membresía actual (NULL si no tiene una activa).
-- =========================================
DROP FUNCTION IF EXISTS fn_tipo_membresia $$
CREATE FUNCTION fn_tipo_membresia(p_usuario_id INT)
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
  RETURN (SELECT m.tipo_membresia
            FROM suscripciones s
            JOIN membresias m ON m.id_membresia = s.id_membresia
           WHERE s.id_usuario = p_usuario_id
             AND s.estado = 'ACTIVA'
             AND CURDATE() >= s.fecha_inicio
             AND CURDATE() <  s.fecha_fin
           ORDER BY s.fecha_fin DESC
           LIMIT 1);
END $$

-- =========================================
-- FUNCION 04: fn_renovaciones_membresia(usuario_id)
-- Número de veces que renovó = suscripciones pagadas (ACTIVA, VENCIDA o
-- SUSPENDIDA) menos la primera. Las PENDIENTES no cuentan porque
-- todavía no se han pagado.
-- =========================================
DROP FUNCTION IF EXISTS fn_renovaciones_membresia $$
CREATE FUNCTION fn_renovaciones_membresia(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
  RETURN GREATEST((SELECT COUNT(*)
                     FROM suscripciones
                    WHERE id_usuario = p_usuario_id
                      AND estado IN ('ACTIVA', 'VENCIDA', 'SUSPENDIDA')) - 1, 0);
END $$

-- =========================================
-- FUNCION 05: fn_estado_membresia(usuario_id)
-- Devuelve: ACTIVA, SUSPENDIDA, VENCIDA, PENDIENTE o SIN_MEMBRESIA.
-- Se basa en la suscripción más reciente (por fecha_fin).
-- =========================================
DROP FUNCTION IF EXISTS fn_estado_membresia $$
CREATE FUNCTION fn_estado_membresia(p_usuario_id INT)
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
  DECLARE v_estado VARCHAR(20);
  DECLARE v_fin    DATE;

  IF fn_membresia_activa(p_usuario_id) THEN
    RETURN 'ACTIVA';
  END IF;

  SELECT estado, fecha_fin INTO v_estado, v_fin
    FROM suscripciones
   WHERE id_usuario = p_usuario_id
   ORDER BY fecha_fin DESC, id_suscripcion DESC
   LIMIT 1;

  IF v_estado IS NULL THEN
    RETURN 'SIN_MEMBRESIA';
  END IF;
  IF v_estado = 'ACTIVA' THEN
    -- marcada ACTIVA pero fuera de vigencia: venció, o aún no empieza
    RETURN IF(v_fin <= CURDATE(), 'VENCIDA', 'PENDIENTE');
  END IF;
  RETURN v_estado;
END $$

-- ---------------------------------------------------------------------
--  RESERVAS (5)
-- ---------------------------------------------------------------------

-- =========================================
-- FUNCION 06: fn_total_reservas(usuario_id)
-- Cantidad total de reservas del usuario (en cualquier estado).
-- =========================================
DROP FUNCTION IF EXISTS fn_total_reservas $$
CREATE FUNCTION fn_total_reservas(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
  RETURN (SELECT COUNT(*) FROM reservas WHERE id_usuario = p_usuario_id);
END $$

-- =========================================
-- FUNCION 07: fn_horas_reservadas(usuario_id, mes, año)
-- Total de horas reservadas en el mes (excluye las CANCELADAS).
-- =========================================
DROP FUNCTION IF EXISTS fn_horas_reservadas $$
CREATE FUNCTION fn_horas_reservadas(p_usuario_id INT, p_mes INT, p_anio INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
  RETURN IFNULL((SELECT ROUND(SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)) / 60, 2)
                   FROM reservas
                  WHERE id_usuario = p_usuario_id
                    AND estado <> 'CANCELADA'
                    AND MONTH(fecha_inicio) = p_mes
                    AND YEAR(fecha_inicio)  = p_anio), 0);
END $$

-- =========================================
-- FUNCION 08: fn_espacio_mas_reservado()
-- ID del espacio con más reservas (sin contar canceladas).
-- =========================================
DROP FUNCTION IF EXISTS fn_espacio_mas_reservado $$
CREATE FUNCTION fn_espacio_mas_reservado()
RETURNS INT
READS SQL DATA
BEGIN
  RETURN (SELECT id_espacio
            FROM reservas
           WHERE estado <> 'CANCELADA'
           GROUP BY id_espacio
           ORDER BY COUNT(*) DESC, id_espacio
           LIMIT 1);
END $$

-- =========================================
-- FUNCION 09: fn_reservas_activas(usuario_id)
-- Cantidad de reservas activas (PENDIENTE/CONFIRMADA que no han terminado).
-- =========================================
DROP FUNCTION IF EXISTS fn_reservas_activas $$
CREATE FUNCTION fn_reservas_activas(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
  RETURN (SELECT COUNT(*)
            FROM reservas
           WHERE id_usuario = p_usuario_id
             AND estado IN ('PENDIENTE', 'CONFIRMADA')
             AND fecha_fin >= NOW());
END $$

-- =========================================
-- FUNCION 10: fn_duracion_promedio_reservas(espacio_id)
-- Promedio de duración (en horas) de las reservas de un espacio.
-- =========================================
DROP FUNCTION IF EXISTS fn_duracion_promedio_reservas $$
CREATE FUNCTION fn_duracion_promedio_reservas(p_espacio_id INT)
RETURNS DECIMAL(6,2)
READS SQL DATA
BEGIN
  RETURN (SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)) / 60, 2)
            FROM reservas
           WHERE id_espacio = p_espacio_id
             AND estado <> 'CANCELADA');
END $$

-- ---------------------------------------------------------------------
--  PAGOS Y FACTURACIÓN (5)
-- ---------------------------------------------------------------------

-- =========================================
-- FUNCION 11: fn_total_pagado(usuario_id)
-- Total pagado por un usuario (pagos en estado PAGADO).
-- =========================================
DROP FUNCTION IF EXISTS fn_total_pagado $$
CREATE FUNCTION fn_total_pagado(p_usuario_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
  RETURN (SELECT IFNULL(SUM(p.monto), 0)
            FROM pagos p
            JOIN ventas v ON v.id_venta = p.id_venta
           WHERE v.id_usuario = p_usuario_id
             AND p.estado = 'PAGADO');
END $$

-- =========================================
-- FUNCION 12: fn_ingresos_por_mes(mes, año)
-- Ingresos (sin IVA) de las ventas del mes con factura PAGADA.
-- =========================================
DROP FUNCTION IF EXISTS fn_ingresos_por_mes $$
CREATE FUNCTION fn_ingresos_por_mes(p_mes INT, p_anio INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
  RETURN (SELECT IFNULL(SUM(v.total), 0)
            FROM ventas v
            JOIN facturas f ON f.id_venta = v.id_venta
                           AND f.estado   = 'PAGADA'
           WHERE MONTH(v.fecha_hora) = p_mes
             AND YEAR(v.fecha_hora)  = p_anio);
END $$

-- =========================================
-- FUNCION 13: fn_ingresos_por_membresias()
-- Total de ingresos (sin IVA) por venta de membresías.
-- =========================================
DROP FUNCTION IF EXISTS fn_ingresos_por_membresias $$
CREATE FUNCTION fn_ingresos_por_membresias()
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
  RETURN (SELECT IFNULL(SUM(dv.precio), 0)
            FROM detalles_venta dv
            JOIN facturas f ON f.id_venta = dv.id_venta
                           AND f.estado   = 'PAGADA'
           WHERE dv.concepto = 'MEMBRESIA');
END $$

-- =========================================
-- FUNCION 14: fn_ingresos_por_reservas()
-- Total de ingresos (sin IVA) por reservas. No incluye penalizaciones.
-- =========================================
DROP FUNCTION IF EXISTS fn_ingresos_por_reservas $$
CREATE FUNCTION fn_ingresos_por_reservas()
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
  RETURN (SELECT IFNULL(SUM(dv.precio), 0)
            FROM detalles_venta dv
            JOIN facturas f ON f.id_venta = dv.id_venta
                           AND f.estado   = 'PAGADA'
           WHERE dv.concepto = 'RESERVA');
END $$

-- =========================================
-- FUNCION 15: fn_ingresos_por_empresa(empresa_id)
-- Ingresos (sin IVA) de las ventas hechas a nombre de la empresa
-- (ventas.id_empresa) con factura PAGADA.
-- =========================================
DROP FUNCTION IF EXISTS fn_ingresos_por_empresa $$
CREATE FUNCTION fn_ingresos_por_empresa(p_empresa_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
  RETURN (SELECT IFNULL(SUM(v.total), 0)
            FROM ventas v
            JOIN facturas f ON f.id_venta = v.id_venta
                           AND f.estado   = 'PAGADA'
           WHERE v.id_empresa = p_empresa_id);
END $$

-- ---------------------------------------------------------------------
--  ACCESOS Y ASISTENCIAS (5)
-- ---------------------------------------------------------------------

-- =========================================
-- FUNCION 16: fn_total_asistencias(usuario_id)
-- Cantidad total de asistencias del usuario.
-- =========================================
DROP FUNCTION IF EXISTS fn_total_asistencias $$
CREATE FUNCTION fn_total_asistencias(p_usuario_id INT)
RETURNS INT
READS SQL DATA
BEGIN
  RETURN (SELECT COUNT(*)
            FROM registro_asistencias
           WHERE id_usuario = p_usuario_id);
END $$

-- =========================================
-- FUNCION 17: fn_asistencias_mes(usuario_id, mes, año)
-- Cantidad de asistencias del usuario en un mes.
-- =========================================
DROP FUNCTION IF EXISTS fn_asistencias_mes $$
CREATE FUNCTION fn_asistencias_mes(p_usuario_id INT, p_mes INT, p_anio INT)
RETURNS INT
READS SQL DATA
BEGIN
  RETURN (SELECT COUNT(*)
            FROM registro_asistencias
           WHERE id_usuario = p_usuario_id
             AND MONTH(fecha_hora) = p_mes
             AND YEAR(fecha_hora)  = p_anio);
END $$

-- =========================================
-- FUNCION 18: fn_top_usuario_asistencias()
-- ID del usuario con más asistencias.
-- =========================================
DROP FUNCTION IF EXISTS fn_top_usuario_asistencias $$
CREATE FUNCTION fn_top_usuario_asistencias()
RETURNS INT
READS SQL DATA
BEGIN
  RETURN (SELECT id_usuario
            FROM registro_asistencias
           GROUP BY id_usuario
           ORDER BY COUNT(*) DESC, id_usuario
           LIMIT 1);
END $$

-- =========================================
-- FUNCION 19: fn_ultima_asistencia(usuario_id)
-- Fecha y hora de la última asistencia (NULL si nunca asistió).
-- =========================================
DROP FUNCTION IF EXISTS fn_ultima_asistencia $$
CREATE FUNCTION fn_ultima_asistencia(p_usuario_id INT)
RETURNS DATETIME
READS SQL DATA
BEGIN
  RETURN (SELECT MAX(fecha_hora)
            FROM registro_asistencias
           WHERE id_usuario = p_usuario_id);
END $$

-- =========================================
-- FUNCION 20: fn_promedio_asistencias()
-- Promedio de asistencias por usuario registrado
-- (asistencias totales / total de usuarios).
-- =========================================
DROP FUNCTION IF EXISTS fn_promedio_asistencias $$
CREATE FUNCTION fn_promedio_asistencias()
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
  RETURN (SELECT ROUND(COUNT(*) / NULLIF((SELECT COUNT(*) FROM usuarios), 0), 2)
            FROM registro_asistencias);
END $$

DELIMITER ;

-- =====================================================================
--  EJEMPLOS DE USO DE LAS FUNCIONES (descomentar para probar)
-- =====================================================================
-- SELECT fn_membresia_activa(1), fn_tipo_membresia(1), fn_estado_membresia(1);
-- SELECT fn_horas_reservadas(1, 10, 2026);
-- SELECT fn_espacio_mas_reservado(), fn_duracion_promedio_reservas(1);
-- SELECT fn_total_pagado(1), fn_ingresos_por_mes(10, 2026);
-- SELECT fn_ingresos_por_membresias(), fn_ingresos_por_reservas(), fn_ingresos_por_empresa(1);
-- SELECT fn_total_asistencias(1), fn_asistencias_mes(1, 10, 2026), fn_ultima_asistencia(1);
-- SELECT fn_top_usuario_asistencias(), fn_promedio_asistencias();