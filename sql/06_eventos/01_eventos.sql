/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Eventos
Archivo: 01_eventos.sql
Descripción:
  20 eventos programados (5 por módulo): Membresías, Reservas, Pagos y
  Facturación, Accesos y Asistencias. Los "envíos" (recordatorios,
  reportes, alertas) se registran en la tabla notificaciones.
  Varios eventos reutilizan procedimientos almacenados (CALL sp_...).
Requisitos:
  Ejecutar al final, después de procedimientos y triggers.
  Requiere el programador de eventos activo (SET GLOBAL necesita el
  privilegio SYSTEM_VARIABLES_ADMIN o SUPER). Los eventos corren con la
  fecha real del servidor: al activarlos modificarán los datos de prueba
  (por ejemplo, cancelarán las reservas PENDIENTES de más de 2 horas).
*/
USE coworking_grupo5;
SET GLOBAL event_scheduler = ON;

-- =====================================================================
--  MÓDULO MEMBRESÍAS
-- =====================================================================

-- =========================================
-- EVENTO 01
-- Revisar diariamente las membresías vencidas y pasarlas a VENCIDA
-- (fecha_fin es exclusiva: el día fecha_fin ya no está cubierto).
-- Reutiliza el procedimiento sp_actualizar_membresias_vencidas.
-- =========================================
DROP EVENT IF EXISTS evt_membresias_vencidas;
CREATE EVENT evt_membresias_vencidas
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '00:05:00')
DO
  CALL sp_actualizar_membresias_vencidas(@evt_vencidas);

-- =========================================
-- EVENTO 02
-- Recordatorio de renovación 5 días antes de vencer
-- =========================================
DROP EVENT IF EXISTS evt_recordatorio_renovacion;
CREATE EVENT evt_recordatorio_renovacion
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '08:00:00')
DO
  INSERT INTO notificaciones (id_usuario, destinatario, tipo, mensaje)
  SELECT s.id_usuario,
         'USUARIO',
         'RECORDATORIO_RENOVACION',
         CONCAT('Tu membresía ', m.tipo_membresia, ' vence el ', s.fecha_fin,
                '. Renuévala para no perder el acceso.')
  FROM suscripciones AS s
  JOIN membresias AS m ON m.id_membresia = s.id_membresia
  WHERE s.estado = 'ACTIVA'
    AND s.fecha_fin = CURRENT_DATE() + INTERVAL 5 DAY;

-- =========================================
-- EVENTO 03
-- Suspender membresías sin pago después de 30 días
-- =========================================
DROP EVENT IF EXISTS evt_suspender_sin_pago;
CREATE EVENT evt_suspender_sin_pago
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '00:10:00')
DO
  UPDATE suscripciones
  SET estado = 'SUSPENDIDA'
  WHERE estado = 'PENDIENTE'
    AND fecha_inicio <= CURRENT_DATE() - INTERVAL 30 DAY;

-- =========================================
-- EVENTO 04
-- Reporte semanal de nuevas membresías al administrador
-- =========================================
DROP EVENT IF EXISTS evt_reporte_nuevas_membresias;
CREATE EVENT evt_reporte_nuevas_membresias
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '07:00:00')
DO
  INSERT INTO notificaciones (destinatario, tipo, mensaje)
  SELECT 'ADMINISTRADOR',
         'REPORTE_NUEVAS_MEMBRESIAS',
         CONCAT('Nuevas membresías en los últimos 7 días: ', COUNT(*))
  FROM suscripciones
  WHERE fecha_inicio >= CURRENT_DATE() - INTERVAL 7 DAY;

-- =========================================
-- EVENTO 05
-- Notificar diariamente a recepción las membresías suspendidas
-- =========================================
DROP EVENT IF EXISTS evt_notificar_suspendidas;
CREATE EVENT evt_notificar_suspendidas
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '07:30:00')
DO
  INSERT INTO notificaciones (destinatario, tipo, mensaje)
  SELECT 'RECEPCION',
         'MEMBRESIAS_SUSPENDIDAS',
         CONCAT('Membresías suspendidas actualmente: ', COUNT(*))
  FROM suscripciones
  WHERE estado = 'SUSPENDIDA'
  HAVING COUNT(*) > 0;

-- =====================================================================
--  MÓDULO RESERVAS
-- =====================================================================

-- =========================================
-- EVENTO 06
-- Cancelar reservas no confirmadas después de 2 horas
-- Reutiliza sp_liberar_reservas_no_confirmadas: además de cancelar,
-- anula los pagos pendientes y deja el log de cada cancelación.
-- =========================================
DROP EVENT IF EXISTS evt_cancelar_reservas_pendientes;
CREATE EVENT evt_cancelar_reservas_pendientes
ON SCHEDULE EVERY 5 MINUTE
STARTS CURRENT_TIMESTAMP + INTERVAL 5 MINUTE
DO
  CALL sp_liberar_reservas_no_confirmadas(2, @evt_liberadas);

-- =========================================
-- EVENTO 07
-- Recordatorio 1 hora antes de la reserva
-- =========================================
DROP EVENT IF EXISTS evt_recordatorio_reserva;
CREATE EVENT evt_recordatorio_reserva
ON SCHEDULE EVERY 5 MINUTE
STARTS CURRENT_TIMESTAMP + INTERVAL 5 MINUTE
DO
  INSERT INTO notificaciones (id_usuario, destinatario, tipo, mensaje)
  SELECT r.id_usuario,
         'USUARIO',
         'RECORDATORIO_RESERVA',
         CONCAT('Tu reserva #', r.id_reserva, ' inicia a las ', DATE_FORMAT(r.fecha_inicio, '%H:%i'))
  FROM reservas r
  WHERE r.estado = 'CONFIRMADA'
    AND r.fecha_inicio >  NOW() + INTERVAL 55 MINUTE
    AND r.fecha_inicio <= NOW() + INTERVAL 60 MINUTE
    AND NOT EXISTS (SELECT 1 FROM notificaciones n          -- sin duplicados
                     WHERE n.id_usuario = r.id_usuario
                       AND n.tipo = 'RECORDATORIO_RESERVA'
                       AND n.mensaje LIKE CONCAT('Tu reserva #', r.id_reserva, ' %'));

-- =========================================
-- EVENTO 08
-- Eliminar reservas pasadas no asistidas después de 7 días
-- =========================================
DROP EVENT IF EXISTS evt_eliminar_reservas_no_asistidas;
CREATE EVENT evt_eliminar_reservas_no_asistidas
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '01:00:00')
DO
  DELETE FROM reservas
  WHERE estado = 'NO_SHOW'
    AND fecha_fin < NOW() - INTERVAL 7 DAY
    AND NOT EXISTS (SELECT 1 FROM registro_asistencias ra WHERE ra.id_reserva = reservas.id_reserva)
    AND NOT EXISTS (SELECT 1 FROM control_acceso ca       WHERE ca.id_reserva = reservas.id_reserva)
    AND NOT EXISTS (SELECT 1 FROM servicio_usuario su     WHERE su.id_reserva = reservas.id_reserva)
    AND NOT EXISTS (SELECT 1 FROM detalles_venta dv       WHERE dv.id_reserva = reservas.id_reserva)
    AND NOT EXISTS (SELECT 1 FROM reembolsos rb           WHERE rb.id_reserva = reservas.id_reserva);

-- =========================================
-- EVENTO 09
-- Reporte semanal de ocupación de espacios al administrador
-- =========================================
DROP EVENT IF EXISTS evt_reporte_ocupacion_semanal;
CREATE EVENT evt_reporte_ocupacion_semanal
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '07:15:00')
DO
  INSERT INTO notificaciones (destinatario, tipo, mensaje)
  SELECT 'ADMINISTRADOR',
         'REPORTE_OCUPACION',
         CONCAT('Ocupación de los últimos 7 días: ',
                COALESCE(ROUND(SUM(TIMESTAMPDIFF(MINUTE, fecha_inicio, fecha_fin)) / 60, 2), 0),
                ' horas reservadas en ', COUNT(DISTINCT id_espacio), ' espacios')
  FROM reservas
  WHERE estado IN ('CONFIRMADA', 'FINALIZADA')
    AND fecha_inicio >= CURRENT_DATE() - INTERVAL 7 DAY
    AND fecha_inicio <  CURRENT_DATE();

-- =========================================
-- EVENTO 10
-- Liberar reservas que no se iniciaron en los primeros 15 minutos
-- =========================================
DROP EVENT IF EXISTS evt_liberar_reservas_no_iniciadas;
CREATE EVENT evt_liberar_reservas_no_iniciadas
ON SCHEDULE EVERY 5 MINUTE
STARTS CURRENT_TIMESTAMP + INTERVAL 5 MINUTE
DO
  UPDATE reservas
  SET estado = 'NO_SHOW'
  WHERE estado = 'CONFIRMADA'
    AND fecha_inicio <= NOW() - INTERVAL 15 MINUTE
    AND NOT EXISTS (
        SELECT 1
        FROM registro_asistencias AS ra
        WHERE ra.id_reserva = reservas.id_reserva
    );

-- =====================================================================
--  MÓDULO PAGOS Y FACTURACIÓN
-- =====================================================================

-- =========================================
-- EVENTO 11
-- Recordatorio de pago pendiente cada 3 días
-- Facturas de empresas: se notifica a su gerente corporativo.
-- =========================================
DROP EVENT IF EXISTS evt_recordatorio_pago;
CREATE EVENT evt_recordatorio_pago
ON SCHEDULE EVERY 3 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '08:00:00')
DO
  INSERT INTO notificaciones (id_usuario, destinatario, tipo, mensaje)
  SELECT COALESCE(v.id_usuario,
                  (SELECT u.id_usuario
                     FROM empleados_empresa ee
                     JOIN usuarios u ON u.id_persona = ee.id_persona
                    WHERE ee.id_empresa = v.id_empresa AND ee.es_gerente
                    LIMIT 1)),
         IF(v.id_usuario IS NULL, 'GERENTE_CORPORATIVO', 'USUARIO'),
         'RECORDATORIO_PAGO',
         CONCAT('Factura ', f.numero_factura, ' pendiente por $',
                f.saldo_pendiente, '. Vence el ', f.fecha_vencimiento)
  FROM facturas AS f
  JOIN ventas AS v ON v.id_venta = f.id_venta
  WHERE f.estado = 'PENDIENTE';

-- =========================================
-- EVENTO 12
-- Bloquear servicios adicionales con facturas vencidas hace más de 10 días
-- Reutiliza sp_bloquear_servicios_morosos: también bloquea a los empleados
-- de empresas morosas y desbloquea a quienes ya pagaron.
-- =========================================
DROP EVENT IF EXISTS evt_bloquear_servicios;
CREATE EVENT evt_bloquear_servicios
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '00:20:00')
DO
  CALL sp_bloquear_servicios_morosos(10, @evt_bloqueados, @evt_desbloqueados);

-- =========================================
-- EVENTO 13
-- Resumen de facturación mensual (mes anterior) en reportes_financieros
-- =========================================
DROP EVENT IF EXISTS evt_resumen_facturacion_mensual;
CREATE EVENT evt_resumen_facturacion_mensual
ON SCHEDULE EVERY 1 MONTH
STARTS TIMESTAMP(LAST_DAY(CURRENT_DATE) + INTERVAL 1 DAY, '00:15:00')
DO
  INSERT INTO reportes_financieros
         (fecha_inicio, fecha_fin, ingresos, iva_generado, total_recaudado, cantidad_facturas)
  SELECT DATE_FORMAT(CURRENT_DATE() - INTERVAL 1 MONTH, '%Y-%m-01'),
         LAST_DAY(CURRENT_DATE() - INTERVAL 1 MONTH),
         COALESCE(SUM(subtotal), 0),
         COALESCE(SUM(iva), 0),
         COALESCE(SUM(total), 0),
         COUNT(*)
  FROM facturas
  WHERE estado <> 'ANULADA'
    AND fecha_emision >= DATE_FORMAT(CURRENT_DATE() - INTERVAL 1 MONTH, '%Y-%m-01')
    AND fecha_emision <  DATE_FORMAT(CURRENT_DATE(), '%Y-%m-01');

-- =========================================
-- EVENTO 14
-- Recargo del 5% a facturas vencidas hace más de 15 días (una sola vez)
-- Reutiliza sp_aplicar_recargos. Al actualizar la factura, el trigger
-- trg_facturas_au_suspender_membresia suspende la membresía asociada.
-- =========================================
DROP EVENT IF EXISTS evt_recargo_facturas_vencidas;
CREATE EVENT evt_recargo_facturas_vencidas
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '00:30:00')
DO
  CALL sp_aplicar_recargos(15, 5, @evt_recargos);

-- =========================================
-- EVENTO 15
-- Reporte de ingresos acumulados del mes al contador (último día del mes)
-- =========================================
DROP EVENT IF EXISTS evt_reporte_ingresos_contador;
CREATE EVENT evt_reporte_ingresos_contador
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '23:55:00')
DO
  INSERT INTO notificaciones (destinatario, tipo, mensaje)
  SELECT 'CONTADOR',
         'REPORTE_INGRESOS_MES',
         CONCAT('Ingresos acumulados de ', DATE_FORMAT(CURRENT_DATE(), '%Y-%m'),
                ': $', COALESCE(SUM(subtotal), 0), ' sin IVA, IVA $', COALESCE(SUM(iva), 0),
                ', total facturado $', COALESCE(SUM(total), 0),
                ' en ', COUNT(*), ' facturas')
  FROM facturas
  WHERE estado <> 'ANULADA'
    AND fecha_emision >= DATE_FORMAT(CURRENT_DATE(), '%Y-%m-01')
    AND fecha_emision <= CURRENT_DATE()
  HAVING CURRENT_DATE() = LAST_DAY(CURRENT_DATE());

-- =====================================================================
--  MÓDULO ACCESOS Y ASISTENCIAS
-- =====================================================================

-- =========================================
-- EVENTO 16
-- Eliminar accesos con más de 1 año de antigüedad
-- =========================================
DROP EVENT IF EXISTS evt_eliminar_accesos_antiguos;
CREATE EVENT evt_eliminar_accesos_antiguos
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '02:00:00')
DO
  DELETE FROM control_acceso
  WHERE fecha < CURRENT_DATE() - INTERVAL 1 YEAR;

-- =========================================
-- EVENTO 17
-- Reporte diario de asistencias al administrador
-- =========================================
DROP EVENT IF EXISTS evt_reporte_asistencias_diario;
CREATE EVENT evt_reporte_asistencias_diario
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '23:55:00')
DO
  INSERT INTO notificaciones (destinatario, tipo, mensaje)
  SELECT 'ADMINISTRADOR',
         'REPORTE_ASISTENCIAS_DIARIO',
         CONCAT('Asistencias de hoy (', CURRENT_DATE(), '): ', COUNT(*),
                ' registros de ', COUNT(DISTINCT id_usuario), ' usuarios')
  FROM registro_asistencias
  WHERE fecha_hora >= CURRENT_DATE()
    AND fecha_hora <  CURRENT_DATE() + INTERVAL 1 DAY;

-- =========================================
-- EVENTO 18
-- Reporte semanal de usuarios inactivos (sin accesos en 7 días)
-- =========================================
DROP EVENT IF EXISTS evt_reporte_usuarios_inactivos;
CREATE EVENT evt_reporte_usuarios_inactivos
ON SCHEDULE EVERY 1 WEEK
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '07:45:00')
DO
  INSERT INTO notificaciones (destinatario, tipo, mensaje)
  SELECT 'ADMINISTRADOR',
         'REPORTE_USUARIOS_INACTIVOS',
         CONCAT('Usuarios sin accesos en los últimos 7 días: ', COUNT(*))
  FROM usuarios
  WHERE id_usuario NOT IN (
      SELECT id_usuario
      FROM control_acceso
      WHERE id_usuario IS NOT NULL
        AND resultado = 'PERMITIDO'
        AND fecha >= CURRENT_DATE() - INTERVAL 7 DAY
  );

-- =========================================
-- EVENTO 19
-- Alerta diaria de accesos fuera de horario (los del día anterior)
-- =========================================
DROP EVENT IF EXISTS evt_alerta_accesos_fuera_horario;
CREATE EVENT evt_alerta_accesos_fuera_horario
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '00:40:00')
DO
  INSERT INTO notificaciones (destinatario, tipo, mensaje)
  SELECT 'ADMINISTRADOR',
         'ALERTA_FUERA_DE_HORARIO',
         CONCAT('Accesos fuera de horario el ', CURRENT_DATE() - INTERVAL 1 DAY, ': ', COUNT(*))
  FROM control_acceso
  WHERE fecha = CURRENT_DATE() - INTERVAL 1 DAY
    AND motivo_rechazo = 'FUERA_DE_HORARIO'
  HAVING COUNT(*) > 0;

-- =========================================
-- EVENTO 20
-- Reporte mensual del top 10 de usuarios más frecuentes (mes anterior)
-- =========================================
DROP EVENT IF EXISTS evt_reporte_top_usuarios;
CREATE EVENT evt_reporte_top_usuarios
ON SCHEDULE EVERY 1 MONTH
STARTS TIMESTAMP(LAST_DAY(CURRENT_DATE) + INTERVAL 1 DAY, '00:30:00')
DO
  INSERT INTO notificaciones (destinatario, tipo, mensaje)
  SELECT 'ADMINISTRADOR',
         'REPORTE_TOP_USUARIOS',
         LEFT(CONCAT('Top 10 usuarios más frecuentes de ',
                     DATE_FORMAT(CURRENT_DATE() - INTERVAL 1 MONTH, '%Y-%m'), ': ',
                     GROUP_CONCAT(CONCAT(t.nombre_usuario, ' (', t.asistencias, ')')
                                  ORDER BY t.asistencias DESC SEPARATOR ', ')), 255)
  FROM (
      SELECT u.nombre_usuario, COUNT(*) AS asistencias
      FROM registro_asistencias AS ra
      JOIN usuarios AS u ON u.id_usuario = ra.id_usuario
      WHERE ra.fecha_hora >= DATE_FORMAT(CURRENT_DATE() - INTERVAL 1 MONTH, '%Y-%m-01')
        AND ra.fecha_hora <  DATE_FORMAT(CURRENT_DATE(), '%Y-%m-01')
      GROUP BY u.id_usuario, u.nombre_usuario
      ORDER BY asistencias DESC
      LIMIT 10
  ) AS t
  HAVING COUNT(*) > 0;
