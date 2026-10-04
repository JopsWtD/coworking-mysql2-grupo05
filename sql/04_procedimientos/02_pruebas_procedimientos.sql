/*
Proyecto: Gestión de Coworking
Grupo: 05
Módulo: Procedimientos almacenados - pruebas
Archivo: 02_pruebas_procedimientos.sql
Descripción:
  Pruebas de los 20 procedimientos. Cada bloque abre una transacción y
  termina en ROLLBACK, así los datos originales no cambian. Se pueden
  ejecutar todos juntos o cada bloque por separado.
Requisitos:
  DDL, DML, funciones, procedimientos y triggers ya creados.
  Se fija la fecha de referencia de los datos (jueves 2026-10-01 12:00).
*/
USE coworking_grupo5;
SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');

-- =========================================
-- P01. Registrar membresía (usuario 59 no tiene ninguna)
-- Esperado: suscripción PENDIENTE 2026-10-01 -> 2026-11-01 y su venta.
-- P01b. Membresía acumulable (usuario 48 ya tiene pagado hasta 2026-11-02)
-- Esperado: la nueva empieza el 2026-11-02.
-- =========================================
START TRANSACTION;
CALL sp_registrar_membresia(59, 'MENSUAL', NULL, @id_sus);
CALL sp_registrar_membresia(48, 'MENSUAL', NULL, @id_sus2);
ROLLBACK;

-- =========================================
-- P02. Renovar membresía
--   a) Usuario 44 (venció en agosto)      -> empieza hoy, 2026-10-01
--   b) Usuario 60 (vigente hasta 10-03)   -> empieza el 2026-10-03
--   c) Usuario 53 (SUSPENDIDA por deuda)  -> ERROR
-- =========================================
START TRANSACTION;
CALL sp_renovar_membresia(44, @r1);
CALL sp_renovar_membresia(60, @r2);
ROLLBACK;
START TRANSACTION;
CALL sp_renovar_membresia(53, @r3);   -- ERROR esperado
ROLLBACK;

-- =========================================
-- P03. Membresías vencidas (simulando el 2026-10-10)
-- Esperado: varias ACTIVAS pasan a VENCIDA.
-- =========================================
SET timestamp = UNIX_TIMESTAMP('2026-10-10 06:00:00');
START TRANSACTION;
CALL sp_actualizar_membresias_vencidas(@vencidas);
ROLLBACK;
SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');

-- =========================================
-- P04. Suspender membresías con facturas vencidas hace más de 10 días
-- =========================================
START TRANSACTION;
CALL sp_suspender_membresias_morosas(10, @suspendidas);
SELECT * FROM notificaciones ORDER BY id_notificacion DESC LIMIT 1;
ROLLBACK;

-- =========================================
-- P05. Verificar disponibilidad
-- Esperado: 1) Disponible  2) Ya reservado  3) Sede cerrada el domingo
--           4) Espacio en mantenimiento    5) Fuera del horario
-- =========================================
CALL sp_verificar_disponibilidad(5,  '2026-10-20 09:00', '2026-10-20 11:00', @ok, @m); SELECT @ok, @m;
CALL sp_verificar_disponibilidad(5,  '2026-10-06 09:30', '2026-10-06 10:30', @ok, @m); SELECT @ok, @m;
CALL sp_verificar_disponibilidad(10, '2026-10-18 10:00', '2026-10-18 11:00', @ok, @m); SELECT @ok, @m;
CALL sp_verificar_disponibilidad(11, '2026-10-20 09:00', '2026-10-20 11:00', @ok, @m); SELECT @ok, @m;
CALL sp_verificar_disponibilidad(5,  '2026-10-20 20:00', '2026-10-20 22:00', @ok, @m); SELECT @ok, @m;

-- =========================================
-- P06 + P07. Crear reserva y confirmarla con pago
-- Esperado: reserva PENDIENTE con venta de $60 (2 h x $30);
--           tras el pago: CONFIRMADA, factura PAGADA, saldo 0.
-- P06b. Usuario corporativo activo (usuario 1): queda CONFIRMADA sin venta.
-- P06c. Más personas que la capacidad -> ERROR
-- =========================================
START TRANSACTION;
CALL sp_crear_reserva(56, 5, '2026-10-20 09:00', '2026-10-20 11:00', 4, @res);
CALL sp_confirmar_reserva_pago(@res, 2, @pago);
CALL sp_crear_reserva(1, 6, '2026-10-20 14:00', '2026-10-20 16:00', 6, @res_corp);
ROLLBACK;
START TRANSACTION;
CALL sp_crear_reserva(56, 5, '2026-10-20 09:00', '2026-10-20 11:00', 20, @res); -- ERROR esperado
ROLLBACK;

-- =========================================
-- P08. Cancelar reservas
--   a) 514: CONFIRMADA y pagada, faltan más de 48 h -> reembolso 100 %
--   b) 513: PENDIENTE sin pago                      -> sin reembolso
--   c) 517 cancelada el 2026-10-14 (menos de 48 h)   -> reembolso 50 %
-- =========================================
START TRANSACTION;
CALL sp_cancelar_reserva(514, NULL, @re1);
CALL sp_cancelar_reserva(513, NULL, @re2);
SELECT * FROM reembolsos ORDER BY id_reembolso DESC LIMIT 1;
SELECT * FROM log_auditoria ORDER BY id_log DESC LIMIT 2;
ROLLBACK;
SET timestamp = UNIX_TIMESTAMP('2026-10-14 12:00:00');
START TRANSACTION;
CALL sp_cancelar_reserva(517, NULL, @re3);
ROLLBACK;
SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');

-- =========================================
-- P09. Liberar reservas PENDIENTES creadas hace más de 2 horas
-- =========================================
START TRANSACTION;
CALL sp_liberar_reservas_no_confirmadas(2, @liberadas);
SELECT id_reserva, estado FROM reservas WHERE id_reserva IN (513, 515, 528);
ROLLBACK;

-- =========================================
-- P10. Factura de una membresía nueva y su pago
-- Esperado: factura PENDIENTE de $214.20; tras pagar, factura PAGADA y
--           membresía ACTIVA (trigger de pagos).
-- =========================================
START TRANSACTION;
CALL sp_registrar_membresia(59, 'MENSUAL', NULL, @sus);
CALL sp_generar_factura_membresia(@sus, @fac);
CALL sp_generar_factura_membresia(@sus, @fac2);          -- no duplica: misma factura
SELECT id_venta, saldo_pendiente INTO @venta, @saldo FROM facturas WHERE id_factura = @fac;
INSERT INTO pagos (id_venta, id_metodo_pago, monto, estado) VALUES (@venta, 4, @saldo, 'PAGADO');
SELECT f.numero_factura, f.estado, f.saldo_pendiente, s.estado AS estado_membresia
  FROM facturas f JOIN suscripciones s ON s.id_suscripcion = @sus
 WHERE f.id_factura = @fac;
ROLLBACK;

-- =========================================
-- P11. Factura consolidada de Innovatek (empresa 1) de octubre 2026
-- Esperado: agrupa los servicios consumidos por sus empleados el 1 de octubre.
-- =========================================
START TRANSACTION;
CALL sp_generar_factura_empresa(1, 2026, 10, @fac_emp);
CALL sp_generar_factura_empresa(1, 2026, 10, @fac_emp2);  -- ERROR: ya no hay cargos
ROLLBACK;

-- =========================================
-- P12. Recargo del 5 % a facturas vencidas hace más de 15 días
-- A la fecha de referencia los recargos ya están aplicados (0 facturas).
-- Simulando el 2026-10-31 aparecen nuevas facturas vencidas.
-- =========================================
SET timestamp = UNIX_TIMESTAMP('2026-10-31 06:00:00');
START TRANSACTION;
CALL sp_aplicar_recargos(15, 5, @recargos);
SELECT numero_factura, fecha_vencimiento, subtotal, recargo, total, saldo_pendiente
  FROM facturas WHERE recargo > 0 ORDER BY fecha_vencimiento DESC LIMIT 3;
ROLLBACK;
SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');

-- =========================================
-- P13. Bloquear servicios de usuarios con facturas vencidas (> 10 días)
-- =========================================
START TRANSACTION;
CALL sp_bloquear_servicios_morosos(10, @bloq, @desbloq);
ROLLBACK;

-- =========================================
-- P14 + P15. Entradas y salidas
--   a) Usuario 3 entra (ya tenía una entrada abierta a las 08:01):
--      PERMITIDO y la entrada anterior recibe salida automática.
--   b) Código inexistente -> DENEGADO / CODIGO_INVALIDO
--   c) Usuario 44 (membresía vencida) -> DENEGADO / MEMBRESIA_INACTIVA
--   d) Usuario 3 registra su salida a las 15:30
--   e) Entrada a las 22:30 -> DENEGADO / FUERA_DE_HORARIO
-- =========================================
START TRANSACTION;
CALL sp_registrar_entrada('RFID-181860', 1, 'RFID', @c1, @r1, @m1);
SELECT id_control, hora_entrada, hora_salida FROM control_acceso WHERE id_control = 2978;
CALL sp_registrar_entrada('QR-000000', 1, 'QR', @c2, @r2, @m2);
CALL sp_registrar_entrada('RFID-812986', 2, 'RFID', @c3, @r3, @m3);
SET timestamp = UNIX_TIMESTAMP('2026-10-01 15:30:00');
CALL sp_registrar_salida('RFID-181860', @cs);
SET timestamp = UNIX_TIMESTAMP('2026-10-01 22:30:00');
CALL sp_registrar_entrada('RFID-181860', 1, 'RFID', @c4, @r4, @m4);
ROLLBACK;
SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');

-- =========================================
-- P16. Reporte diario de asistencias del 30 de septiembre
-- =========================================
CALL sp_reporte_diario_asistencias('2026-09-30');

-- =========================================
-- P17. No show y penalización (simulando el 2026-10-07)
-- Esperado: la reserva del 2026-10-06 sin asistencia pasa a NO_SHOW y
--           genera una venta PENALIZACION del 20 %.
-- =========================================
SET timestamp = UNIX_TIMESTAMP('2026-10-07 08:00:00');
START TRANSACTION;
CALL sp_marcar_no_show(20, @marcadas, @penalizadas);
SELECT d.id_reserva, d.concepto, d.precio FROM detalles_venta d
 WHERE d.concepto = 'PENALIZACION' ORDER BY d.id_detalle DESC LIMIT 3;
ROLLBACK;
SET timestamp = UNIX_TIMESTAMP('2026-10-01 12:00:00');

-- =========================================
-- P18. Lote de empleados para Andina Consultores (empresa 2)
-- =========================================
START TRANSACTION;
CALL sp_registrar_lote_empleados(2, '[
  {"tipo_documento":"CC","numero_documento":"1090111222","primer_nombre":"Kevin",
   "primer_apellido":"Duarte","fecha_nacimiento":"1998-04-12","telefono":"3001112233",
   "email":"kevin.duarte@andinaconsultores.co","contrasena":"$2b$12$abcdefghijklmnopqrstuuJ7lQe3Zc1xY0b9kT5mN2pR8sV4wU6",
   "nombre_usuario":"kduarte","codigo_acceso":"QR-900001"},
  {"tipo_documento":"CC","numero_documento":"1090333444","primer_nombre":"Paola",
   "segundo_nombre":"Andrea","primer_apellido":"Lizcano","fecha_nacimiento":"1995-11-30",
   "email":"paola.lizcano@andinaconsultores.co","contrasena":"$2b$12$zyxwvutsrqponmlkjihgfeQ1aB2cD3eF4gH5iJ6kL7mN8oP9qR0s"}
]', '2026-10-01', @registrados);
ROLLBACK;

-- =========================================
-- P19. Cancelar todas las reservas futuras del usuario 39
-- Esperado: 5 reservas canceladas con reembolso del 100 %.
-- =========================================
START TRANSACTION;
CALL sp_cancelar_reservas_futuras(39, @canceladas);
ROLLBACK;

-- =========================================
-- P20. Reporte de ingresos mensuales acumulados de 2026
-- =========================================
CALL sp_reporte_ingresos_mensuales(2026);

SET timestamp = DEFAULT;
