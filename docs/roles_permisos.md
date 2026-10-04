# Roles y permisos — Sistema de Gestión de Coworking (Grupo 05)

El sistema define **5 roles** de MySQL (prefijo `rol_`). Los scripts están en `sql/07_seguridad/`:

| Archivo | Contenido |
|---|---|
| `01_roles.sql` | `CREATE ROLE` de los 5 roles |
| `02_permisos.sql` | Vistas de seguridad por fila, procedimientos de autoservicio y todos los `GRANT` |
| `03_usuarios_ejemplo.sql` | Una cuenta de ejemplo por rol, con su rol como predeterminado |

## Principios

1. **Mínimo privilegio.** Cada rol recibe solo las tablas, columnas y rutinas que necesita.
2. **Operaciones sensibles por procedimientos.** Crear reservas, registrar membresías, pagos o accesos se hace con `CALL sp_...`, de modo que siempre se aplican las validaciones y los triggers. Las rutinas son `SQL SECURITY DEFINER`: quien las ejecuta no necesita permisos sobre las tablas internas.
3. **Seguridad por fila para Usuario y Gerente.** Estos roles no leen tablas con datos personales o financieros. Usan vistas que filtran por la cuenta conectada con `SUBSTRING_INDEX(USER(), '@', 1)`. Por eso **la cuenta MySQL debe llamarse igual que `usuarios.nombre_usuario`**.
4. **Permisos por columna** cuando basta con una parte de la tabla: el contador ve `usuarios(id_usuario, nombre_usuario)` pero no la contraseña ni el código de acceso, y solo puede modificar `facturas(estado, motivo_anulacion)`.

## Matriz de permisos

| Recurso | Administrador | Recepcionista | Usuario | Gerente corporativo | Contador |
|---|:-:|:-:|:-:|:-:|:-:|
| Toda la base de datos | ALL + GRANT OPTION | — | — | — | — |
| `personas`, `usuarios` | ✔ | SELECT, INSERT, UPDATE | solo su fila (`v_mi_perfil`) | su fila + empleados de su empresa | `usuarios(id_usuario, nombre_usuario)` |
| `empresas`, `empleados_empresa` | ✔ | SELECT, INSERT | — | `v_empleados_mi_empresa` | SELECT `empresas` |
| Catálogo: sedes, horarios, espacios, servicios, membresías | ✔ | SELECT | SELECT | SELECT (hereda Usuario) | SELECT membresías y servicios |
| `suscripciones` | ✔ | SELECT + procedimientos | `v_mis_membresias` | `v_mis_membresias` | — |
| `reservas` | ✔ | SELECT + procedimientos | `v_mis_reservas` + `sp_usuario_reservar` / `sp_usuario_cancelar_reserva` | igual que Usuario | — |
| `control_acceso`, `registro_asistencias` | ✔ | SELECT + `sp_registrar_entrada` / `sp_registrar_salida` | `v_mis_asistencias` | igual que Usuario | — |
| `servicio_usuario` | ✔ | INSERT | — | — | — |
| `ventas`, `detalles_venta`, `pagos`, `reembolsos` | ✔ | — | — | — | SELECT |
| `facturas` | ✔ | — | `v_mis_facturas` | `v_facturacion_mi_empresa` | SELECT + UPDATE(estado, motivo_anulacion) |
| `reportes_financieros` | ✔ | — | — | — | SELECT, INSERT, UPDATE |
| `notificaciones` | ✔ | SELECT, UPDATE(leida) | — | — | — |
| Funciones | todas | membresía y reservas | — | — | ingresos y total pagado |

### Procedimientos por rol

| Rol | Procedimientos con `EXECUTE` |
|---|---|
| Administrador | Todos |
| Recepcionista | `sp_registrar_membresia`, `sp_renovar_membresia`, `sp_generar_factura_membresia`, `sp_verificar_disponibilidad`, `sp_crear_reserva`, `sp_confirmar_reserva_pago`, `sp_cancelar_reserva`, `sp_registrar_entrada`, `sp_registrar_salida`, `sp_reporte_diario_asistencias` |
| Usuario | `sp_verificar_disponibilidad`, `sp_usuario_reservar`, `sp_usuario_cancelar_reserva` |
| Gerente corporativo | Los de Usuario (hereda `rol_usuario`) + `sp_gerente_registrar_empleados` |
| Contador | `sp_generar_factura_membresia`, `sp_generar_factura_empresa`, `sp_aplicar_recargos`, `sp_bloquear_servicios_morosos`, `sp_suspender_membresias_morosas`, `sp_reporte_ingresos_mensuales` |

Los procedimientos de autoservicio (`sp_usuario_reservar`, `sp_usuario_cancelar_reserva`, `sp_gerente_registrar_empleados`) obtienen el usuario o la empresa a partir de la cuenta conectada, así nadie puede reservar a nombre de otro ni registrar empleados en otra empresa.

## Cuentas de ejemplo

| Cuenta MySQL | Contraseña de ejemplo | Rol | Corresponde a |
|---|---|---|---|
| `admin_coworking` | `Admin#Cowork2026` | `rol_administrador` | — |
| `recepcion_centro` | `Recepcion#2026` | `rol_recepcionista` | — |
| `nflorez56` | `Usuario#2026` | `rol_usuario` | Usuario 56 (cliente independiente) |
| `vpabon1` | `Gerente#2026` | `rol_gerente_corporativo` | Usuario 1, gerente de Innovatek S.A.S. |
| `contador_coworking` | `Contador#2026` | `rol_contador` | — |

> Contraseñas solo para pruebas. En un entorno real se deben cambiar.

## Crear un usuario y asignarle un rol

```sql
CREATE USER 'jperez'@'localhost' IDENTIFIED BY 'ClaveSegura#1';
GRANT 'rol_recepcionista' TO 'jperez'@'localhost';
SET DEFAULT ROLE ALL TO 'jperez'@'localhost';   -- el rol queda activo al iniciar sesión
```

Si el rol es `rol_usuario` o `rol_gerente_corporativo`, el nombre de la cuenta (`jperez`) debe existir en `usuarios.nombre_usuario`.

Para revisar los permisos: `SHOW GRANTS FOR 'rol_contador';` o, con la sesión iniciada, `SELECT CURRENT_ROLE();`.

## Pruebas realizadas

Conectando con cada cuenta de ejemplo se verificó que:

- `nflorez56` ve solo sus 12 reservas y sus 16 facturas, puede reservar con `sp_usuario_reservar` y recibe *SELECT command denied* al consultar `reservas` directamente o la facturación de empresas. Si intenta cancelar una reserva ajena, recibe un error.
- `vpabon1` ve los 14 empleados de Innovatek y sus 19 facturas consolidadas, pero no puede leer la tabla `facturas`.
- `contador_coworking` consulta todas las facturas y las funciones de ingresos, pero no puede leer `usuarios.contrasena` ni borrar pagos.
- `recepcion_centro` usa las funciones de membresía pero no puede ver facturas.
