/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Triggers - pruebas
Archivo: 02_pruebas_triggers.sql
Descripción:
  Pruebas de los 20 triggers. Cada bloque abre una transacción y termina
  en ROLLBACK, así los datos originales no se modifican.
Requisitos:
  DDL, DML y triggers creados. Se fija la fecha de referencia de los
  datos (jueves 2026-10-01 12:00) para que los ids usados existan en el
  estado esperado (reserva 499 en curso, entrada 2978 abierta, etc.).
*/
USE coworking_grupo5;
SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');
-- ---------------------------------------------------------------------
-- T1. Fecha de vencimiento automatica (PREMIUM = +1 anio)
--     Esperado: fecha_fin = fecha_inicio + 1 anio
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO suscripciones (id_usuario, id_membresia, fecha_inicio, fecha_fin)
VALUES (55, 4, CURDATE(), CURDATE());          -- fecha_fin es un valor temporal
SELECT id_suscripcion, fecha_inicio, fecha_fin, estado
FROM suscripciones WHERE id_suscripcion = LAST_INSERT_ID();
ROLLBACK;

-- ---------------------------------------------------------------------
-- T6, T7, T8, T11, T12, T13, T2. Flujo completo reserva -> pago
--     Esperado: reserva PENDIENTE al crearse; tras el pago la reserva queda
--     CONFIRMADA y la factura PAGADA con saldo 0 (la factura la crea el trigger).
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO reservas (id_espacio, id_usuario, fecha_inicio, fecha_fin, cantidad_personas, estado)
VALUES (1, 55, '2026-12-01 10:00:00', '2026-12-01 11:00:00', 1, 'CONFIRMADA');  -- se fuerza PENDIENTE
SET @reserva = LAST_INSERT_ID();
SELECT id_reserva, estado FROM reservas WHERE id_reserva = @reserva;            -- PENDIENTE

INSERT INTO ventas (id_usuario, total) VALUES (55, 6.00);
SET @venta = LAST_INSERT_ID();
INSERT INTO detalles_venta (id_venta, id_reserva, concepto, precio)
VALUES (@venta, @reserva, 'RESERVA', 6.00);

INSERT INTO pagos (id_venta, id_metodo_pago, monto, estado)
VALUES (@venta, 2, 7.14, 'PAGADO');

SELECT estado FROM reservas WHERE id_reserva = @reserva;                        -- CONFIRMADA
SELECT numero_factura, total, saldo_pendiente, estado
FROM facturas WHERE id_venta = @venta;                                          -- PAGADA, saldo 0
ROLLBACK;

-- ---------------------------------------------------------------------
-- T12. Pago parcial. Esperado: factura PENDIENTE con saldo 3.57
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO ventas (id_usuario, total) VALUES (55, 6.00);
SET @venta = LAST_INSERT_ID();
INSERT INTO pagos (id_venta, id_metodo_pago, monto, estado) VALUES (@venta, 2, 3.57, 'PAGADO');
SELECT total, saldo_pendiente, estado FROM facturas WHERE id_venta = @venta;
ROLLBACK;

-- ---------------------------------------------------------------------
-- T6. Reserva solapada. Esperado: ERROR 'El espacio ya esta reservado en ese horario'
--     (la reserva 499 ocupa el espacio 4 el 2026-10-01 de 08:00 a 17:00)
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO reservas (id_espacio, id_usuario, fecha_inicio, fecha_fin, cantidad_personas)
VALUES (4, 55, '2026-10-01 10:00:00', '2026-10-01 11:00:00', 2);
ROLLBACK;

-- ---------------------------------------------------------------------
-- T14. Eliminar un pago con factura. Esperado: ERROR
-- ---------------------------------------------------------------------
START TRANSACTION;
DELETE FROM pagos WHERE id_pago = 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- T15. Anular un pago. Esperado: fila ANULACION_PAGO en log_auditoria,
--      saldo de la factura nuevamente > 0 y factura de nuevo PENDIENTE
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE pagos SET estado = 'CANCELADO' WHERE id_pago = 1;
SELECT * FROM log_auditoria ORDER BY id_log DESC LIMIT 1;
SELECT id_venta, saldo_pendiente, estado FROM facturas WHERE id_venta = 10;
ROLLBACK;

-- ---------------------------------------------------------------------
-- T5. Eliminar membresia de usuario con reserva CONFIRMADA vigente.
--     Esperado: ERROR 'No se puede eliminar la membresia...'
-- ---------------------------------------------------------------------
START TRANSACTION;
DELETE FROM suscripciones WHERE id_suscripcion = 330;
ROLLBACK;

-- ---------------------------------------------------------------------
-- T4. Cambio de tipo de membresia. Esperado: log 'Usuario 55: MENSUAL -> PREMIUM'
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE suscripciones SET id_membresia = 4 WHERE id_suscripcion = 463;
SELECT * FROM log_auditoria ORDER BY id_log DESC LIMIT 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- T10. Cancelar una reserva. Esperado: log CANCELACION
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE reservas SET estado = 'CANCELADA' WHERE id_reserva = 513;
SELECT * FROM log_auditoria ORDER BY id_log DESC LIMIT 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- T3. Suspension por impago. La factura 481 (venta 134, usuario 55) aun no
--     vence; se fuerza una fecha pasada para la prueba.
--     Esperado: suscripcion 463 pasa de PENDIENTE a SUSPENDIDA
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE facturas SET fecha_vencimiento = '2026-09-01', fecha_emision = '2026-08-17'
 WHERE id_venta = 134;
SELECT id_suscripcion, estado FROM suscripciones WHERE id_suscripcion = 463;
ROLLBACK;

-- ---------------------------------------------------------------------
-- T17/T16/T18/T20. Accesos
--     a) Usuario 55 (membresia PENDIENTE, sin reserva hoy)
--        Esperado: DENEGADO / MEMBRESIA_INACTIVA + log ACCESO_RECHAZADO
--     b) Usuario 3 (membresia ACTIVA)
--        Esperado: PERMITIDO + asistencia nueva + ultimo_acceso actualizado
--     c) Fuera de horario (06:00)
--        Esperado: DENEGADO / FUERA_DE_HORARIO
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO control_acceso (id_usuario, id_sede_coworking, fecha, hora_entrada, metodo, resultado)
VALUES (55, 1, CURDATE(), '10:00:00', 'QR', 'PERMITIDO');
SELECT id_control, resultado, motivo_rechazo FROM control_acceso WHERE id_control = LAST_INSERT_ID();
SELECT * FROM log_auditoria ORDER BY id_log DESC LIMIT 1;

INSERT INTO control_acceso (id_usuario, id_sede_coworking, fecha, hora_entrada, metodo, resultado)
VALUES (3, 1, CURDATE(), '16:00:00', 'RFID', 'PERMITIDO');
SELECT id_control, resultado FROM control_acceso WHERE id_control = LAST_INSERT_ID();
SELECT * FROM registro_asistencias ORDER BY id_registro DESC LIMIT 1;
SELECT id_usuario, ultimo_acceso FROM usuarios WHERE id_usuario = 3;

INSERT INTO control_acceso (id_usuario, id_sede_coworking, fecha, hora_entrada, metodo, resultado)
VALUES (3, 1, CURDATE(), '06:00:00', 'RFID', 'PERMITIDO');
SELECT id_control, resultado, motivo_rechazo FROM control_acceso WHERE id_control = LAST_INSERT_ID();
ROLLBACK;

-- ---------------------------------------------------------------------
-- T19. Reingreso sin salida previa.
--      El usuario 3 ya tiene una entrada abierta hoy (control 2978).
--      Esperado: log SALIDA_AUTOMATICA. (La hora de salida de la entrada
--      anterior la completa el procedimiento sp_registrar_entrada.)
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO control_acceso (id_usuario, id_sede_coworking, fecha, hora_entrada, metodo, resultado)
VALUES (3, 1, CURDATE(), '14:00:00', 'RFID', 'PERMITIDO');
SELECT * FROM log_auditoria WHERE accion = 'SALIDA_AUTOMATICA' ORDER BY id_log DESC LIMIT 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- Verificacion: listar los triggers creados (25 fisicos = 20 logicos)
-- ---------------------------------------------------------------------
SELECT EVENT_OBJECT_TABLE AS tabla, TRIGGER_NAME, ACTION_TIMING, EVENT_MANIPULATION
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = 'coworking_grupo5'
ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION, ACTION_ORDER;

SET timestamp = DEFAULT;
