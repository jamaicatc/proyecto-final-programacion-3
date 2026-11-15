# Sistema de Gestión de Emergencias — Terminal Elixir

Versión de consola basada en los módulos de dominio existentes. La aplicación no depende de Phoenix, LiveView, HTML, CSS ni navegador.

## Requisitos
- Elixir 1.14 o superior
- Erlang/OTP compatible

## Preparar y ejecutar
```bash
mix deps.get
mix compile
iex -S mix
```

El archivo `.iex.exs` inicia el menú interactivo antes de mostrar el prompt de IEx. Al salir del menú, IEx queda disponible. Para ejecutar sin IEx (evita que la shell de IEx compita por la entrada estándar), también puede utilizarse:
```bash
mix run -e 'Emergencias.Terminal.start()'
```

Para abrir IEx sin entrar automáticamente al menú:
```bash
EMERGENCIAS_NO_CLI=1 iex -S mix
```

## Primer uso
1. Entre a **Gestión de usuarios → Registrar usuario**.
2. El primer usuario puede crearse con rol `administrador`.
3. Inicie sesión desde **Gestión de usuarios → Iniciar sesión**.
4. Registre zonas, centros, inventario y demás entidades.
5. Las operaciones de escritura se guardan sincrónicamente en `data/emergencias.txt`.

Los usuarios posteriores solo pueden ser registrados por un administrador conectado. Los roles y permisos se validan en el coordinador.

## Arquitectura
- `Emergencias.Terminal`: menús, lectura y presentación de consola.
- `Emergencias`: API pública.
- `Emergencias.Coordinator`: lógica de negocio y transacciones serializadas mediante GenServer.
- `Emergencias.Store`: persistencia textual Base64 de términos Erlang.
- `Emergencias.Application`: árbol de supervisión con Task.Supervisor y Coordinator.
- `Util.ex` / `Util2.ex`: utilidades originales de entrada/salida.

## Pruebas
```bash
mix test
mix format --check-formatted
```

La demostración de concurrencia crea un coordinador aislado, dispara dos procesos de salida simultáneos y verifica el inventario final. No altera el inventario operativo.

# Guía de opciones y respuestas del sistema

Esta guía describe las preguntas de la interfaz de consola, qué escribir y qué restricciones aplica el sistema. Se basa en las opciones disponibles en el menú interactivo.

## Reglas generales de entrada

- En los menús, escriba el número de la opción y presione **Enter**. El menú principal acepta del `1` al `11`; cada submenú acepta sus opciones numeradas y también `0` para volver. La última opción de cada submenú («Volver al menú principal») también regresa.
- Los campos se solicitan de uno en uno. Escriba una sola línea por campo y presione **Enter**. Se quitan los espacios al principio y al final; los espacios dentro del texto se conservan.
- Cuando un campo no tiene una lista de valores permitidos, puede escribir texto libre. No hay un formato especial para códigos, nombres, documentos, teléfonos o contraseñas, a menos que se indique en la sección de esa opción. Aun así, el sistema puede exigir que el dato no esté vacío, que no esté repetido o que coincida con un registro existente.
- Si un campo de texto libre no está marcado como obligatorio, la consola normalmente permite dejarlo vacío; algunos registros pueden quedar sin ese dato. Conviene completarlo siempre que lo conozca. Cuando se indica un valor predeterminado para un campo vacío, se especifica en la opción correspondiente.
- Los campos numéricos aceptan enteros, no decimales ni separadores. Por ejemplo, escriba `25`, no `25.0` ni `1.000`.
- Las listas cerradas muestran sus valores entre corchetes. Escriba uno de ellos; se acepta con mayúsculas o minúsculas, pero use el texto tal como aparece (por ejemplo, `critica`, sin tilde, cuando esa sea la opción impresa). Si la respuesta no es válida, el programa vuelve a preguntar.
- Cuando el programa muestra un identificador generado, guárdelo y úselo exactamente en las operaciones posteriores. Los identificadores son, por ejemplo, `N001` (necesidad), `P001` (persona), `M001` (mensaje) y `A001` (reporte de mascota).
- Las operaciones de registro y modificación suelen requerir una sesión iniciada. Si aparece el aviso de iniciar sesión, vaya a **Gestión de usuarios → Iniciar sesión**. Los listados y las consultas no requieren iniciar sesión.

## Menú principal

| Opción | Acción | Qué debe escribir |
|---|---|---|
| 1 | Gestión de usuarios | Un número del submenú de usuarios. |
| 2 | Gestión de zonas afectadas | Un número del submenú de zonas. |
| 3 | Gestión de necesidades | Un número del submenú de necesidades. |
| 4 | Gestión de recursos e inventario | Un número del submenú de recursos. |
| 5 | Gestión de personas y familiares | Un número del submenú de personas. |
| 6 | Gestión de mascotas perdidas y encontradas | Un número del submenú de mascotas. |
| 7 | Gestión de albergues | Un número del submenú de albergues. |
| 8 | Consultar estadísticas y reportes | No pide datos; muestra el resumen del sistema. |
| 9 | Demostración de concurrencia | No pide datos; ejecuta una demostración aislada de inventario. |
| 10 | Guardar información | No pide datos; guarda la información. |
| 11 | Salir | Pregunta si desea salir. Responda `s`, `si` o `sí` para confirmar. Cualquier otra respuesta cancela la salida. |

Después de ejecutar una opción de un submenú o la demostración, el programa puede pedir **«Presione Enter para continuar...»**. En ese punto basta con presionar Enter.

## 1. Gestión de usuarios

| Opción | Preguntas y respuestas |
|---|---|
| 1. Registrar usuario | **Nombre de usuario:** texto libre; debe ser único y no puede quedar vacío. **Contraseña:** texto libre; no puede quedar vacía. Se escribe visible en la consola. **Nombre completo:** texto libre; si se deja vacío, se usa el nombre de usuario. **Rol:** elija `ciudadano`, `voluntario`, `coordinador` o `administrador`. **Zona (código o sin_zona):** escriba el código de zona o `sin_zona`; si lo deja vacío, el sistema usa `sin_zona`. El primer usuario debe tener rol `administrador`; los siguientes solo los registra un administrador conectado. |
| 2. Iniciar sesión | **Usuario** y **Contraseña:** escriba las credenciales del usuario ya registrado. Deben coincidir con las usadas al registrarlo. |
| 3. Cerrar sesión | No pide datos. Cierra la sesión actual. Si no hay sesión, informa que no hay una iniciada. |
| 4. Consultar usuarios | No pide datos. |
| 5. Consultar usuario conectado | No pide datos. Muestra el usuario actual; requiere sesión iniciada. |
| 6. Volver al menú principal | No pide datos. |

## 2. Gestión de zonas afectadas

| Opción | Preguntas y respuestas |
|---|---|
| 1. Registrar zona | **Código:** texto libre, obligatorio y único. Este código identifica la zona. **Nombre:** texto libre. **Nivel:** `critico`, `alto`, `medio` o `bajo`. **Personas afectadas:** entero mayor o igual a `0`. Se necesita sesión de coordinador o administrador. |
| 2. Registrar sector | **Código de zona:** código de una zona registrada. **Código de sector:** texto libre, obligatorio y único dentro de esa zona. **Nombre:** texto libre. **Nivel:** `critico`, `alto`, `medio` o `bajo`. **Personas afectadas:** entero mayor o igual a `0`. |
| 3. Registrar punto de atención | **Zona:** código de la zona registrada. **Sector:** código de un sector dentro de esa zona. **Código del punto:** texto libre, obligatorio y único dentro del sector. **Nombre:** texto libre. **Personas afectadas:** entero mayor o igual a `0`. |
| 4. Consultar zonas | No pide datos. |
| 5. Consultar sectores | No pide datos. Muestra los sectores registrados dentro de las zonas. |
| 6. Consultar puntos de atención | No pide datos. Muestra los puntos registrados dentro de los sectores. |
| 7. Consultar estadísticas por zona | **Código de zona:** código de una zona registrada. |
| 8. Volver al menú principal | No pide datos. |

Los códigos no tienen una estructura obligatoria (pueden ser, por ejemplo, `NORTE` o `Z-01`), pero al consultar o relacionar registros debe escribir el mismo código usado al crearlos.

## 3. Gestión de necesidades

| Opción | Preguntas y respuestas |
|---|---|
| 1. Registrar necesidad | **Tipo/categoría de necesidad:** texto libre obligatorio (por ejemplo, `agua`, `alimentos` o `medicamentos`). **Descripción:** texto libre; puede explicar el contexto o lo solicitado. **Cantidad:** entero mínimo `1`. **Zona:** código de una zona registrada o `sin_zona`. **Prioridad:** `baja`, `media`, `alta` o `critica`. El sistema asigna un ID, como `N001`. |
| 2. Consultar todas las necesidades | No pide datos. |
| 3. Buscar necesidades por zona | **Zona:** código de zona. La búsqueda compara el código sin distinguir mayúsculas y minúsculas. |
| 4. Buscar por prioridad | **Prioridad:** `baja`, `media`, `alta` o `critica`. |
| 5. Buscar por estado | **Estado:** `pendiente`, `asignada`, `en_atencion`, `atendida` o `cancelada`. |
| 6. Asignar recursos a una necesidad | **ID necesidad:** identificador generado, por ejemplo `N001`. **Código recurso:** código de un recurso registrado. **Cantidad:** entero mínimo `1`. La cantidad debe caber tanto en lo pendiente de la necesidad como en el inventario; además, el tipo de la necesidad debe coincidir con el nombre o la categoría del recurso. |
| 7. Cambiar estado de una necesidad | **ID necesidad:** identificador, por ejemplo `N001`. **Estado:** uno de los estados indicados en la opción 5. No se puede cambiar al mismo estado ni reabrir una necesidad `atendida` o `cancelada`; volver a `pendiente` solo se permite si ya estaba `pendiente`. |
| 8. Cancelar necesidad | **ID necesidad:** identificador, por ejemplo `N001`. La acción establece el estado `cancelada`; las necesidades atendidas o canceladas no se pueden volver a modificar. |
| 9. Volver al menú principal | No pide datos. |

## 4. Gestión de recursos e inventario

| Opción | Preguntas y respuestas |
|---|---|
| 1. Registrar recurso | **Código:** texto libre obligatorio y único. **Nombre:** texto libre. **Categoría:** texto libre (por ejemplo, `agua`). **Cantidad inicial:** entero mínimo `0`. **Unidad:** texto libre (por ejemplo, `litros`, `cajas` o `unidades`). **Zona:** texto libre, normalmente el código de la zona donde se encuentra. **Centro (vacío si no aplica):** escriba el código de un centro de apoyo registrado o deje vacío si no corresponde. El sistema exige que el centro exista si se proporciona. |
| 2. Consultar inventario | No pide datos. |
| 3. Buscar por categoría | **Categoría:** escriba la categoría del recurso. La comparación no distingue mayúsculas y minúsculas, pero debe coincidir con la categoría registrada. |
| 4. Buscar por zona | **Zona:** escriba el código de zona usado en el recurso. |
| 5. Registrar entrada | **Código recurso:** código existente. **Cantidad a ingresar:** entero mínimo `1`. **Motivo:** texto libre que explica el ingreso. |
| 6. Registrar salida | **Código recurso:** código existente. **Cantidad a retirar:** entero mínimo `1` y no mayor al inventario disponible. **Motivo:** texto libre que explica el retiro. |
| 7. Asignar recurso a necesidad | **ID necesidad**, **Código recurso** y **Cantidad:** igual que en la opción 6 de necesidades. La cantidad debe estar disponible y ser compatible con la necesidad. |
| 8. Transferir recursos entre centros | **Código recurso:** código existente. **Origen:** ubicación, zona o centro actual del recurso; también puede dejarse vacío para no comprobar el origen. **Centro destino:** destino distinto del origen; no puede quedar vacío. Si coincide con un centro registrado, se usa ese centro; si no, se toma como ubicación/zona de destino. **Cantidad:** entero mínimo `1`, no mayor a la cantidad disponible. |
| 9. Consultar historial de movimientos | No pide datos. |
| 10. Registrar centro de apoyo | **Código centro:** texto libre obligatorio y único. **Nombre:** texto libre obligatorio. **Zona:** texto libre; escriba el código de zona correspondiente. |
| 11. Consultar centros de apoyo | No pide datos. |
| 12. Volver al menú principal | No pide datos. |

## 5. Gestión de personas y familiares

| Opción | Preguntas y respuestas |
|---|---|
| 1. Registrar persona afectada | **Documento:** texto libre obligatorio y único. No se impone formato numérico: puede incluir letras si así se identifica el documento. **Nombre completo:** texto libre. **Zona:** código o referencia de zona como texto. **Edad (opcional):** entero mayor o igual a `0`, o Enter para dejarla sin informar. |
| 2. Buscar por nombre | **Nombre o parte del nombre:** texto libre. Busca coincidencias parciales y no distingue mayúsculas/minúsculas. |
| 3. Buscar por documento | **Documento:** escriba el documento de la persona. |
| 4. Buscar por zona | **Zona:** escriba la zona asociada a la persona. |
| 5. Consultar por estado | **Estado:** `sin_informacion`, `reportada`, `localizada`, `trasladada`, `en_albergue` o `reunificada`. |
| 6. Actualizar estado | **Documento:** documento ya registrado. **Nuevo estado:** `localizada`, `trasladada`, `en_albergue` o `reunificada`. El cambio debe ser válido desde el estado actual. `reunificada` es un estado final. |
| 7. Registrar mensaje familiar | **Documento destinatario:** documento de una persona ya registrada. **Mensaje familiar:** texto libre obligatorio; escriba el contenido que se debe transmitir. |
| 8. Consultar mensajes familiares | **Documento (vacío para todos):** escriba el documento para filtrar, o presione Enter sin texto para mostrar todos. |
| 9. Cambiar estado de entrega de mensajes | **ID mensaje:** identificador generado, por ejemplo `M001`. Solo se puede marcar como entregado un mensaje pendiente; esta operación requiere un usuario voluntario, coordinador o administrador. |
| 10. Consultar historial de estados | **Documento para consultar historial:** documento de la persona registrada. |
| 11. Volver al menú principal | No pide datos. |

Los estados de las personas solo pueden avanzar mediante transiciones válidas. Si el programa indica que el cambio es inválido, consulte primero el estado actual de la persona.

## 6. Gestión de mascotas

| Opción | Preguntas y respuestas |
|---|---|
| 1. Registrar mascota perdida | Se solicitan los mismos campos que para una mascota encontrada: **Especie**, **Nombre (desconocido si no se sabe)**, **Color**, **Tamaño**, **Zona**, **Contacto** y **Características**. La especie es obligatoria; los demás datos son texto libre y pueden dejarse vacíos. Si no se conoce el nombre, escriba literalmente `desconocido` para que la comparación de coincidencias lo trate como desconocido. |
| 2. Registrar mascota encontrada | Los mismos campos de la opción 1. |
| 3. Consultar reportes | No pide datos. |
| 4. Buscar por especie | **Especie:** texto usado al registrar el reporte. |
| 5. Buscar por zona | **Zona:** texto usado al registrar el reporte. |
| 6. Buscar posibles coincidencias | No pide datos. Busca reportes compatibles; requiere sesión de voluntario, coordinador o administrador. La puntuación compara especie, color, tamaño, zona y nombre; muestra candidatos con al menos `3/5` atributos coincidentes. |
| 7. Confirmar coincidencia | **ID reporte perdido** y **ID reporte encontrado:** escriba los IDs `A...` que aparecen en los reportes. Debe indicar primero el reporte perdido y luego el encontrado. Requiere coordinador o administrador. |
| 8. Resolver reportes | No pide datos. Muestra los reportes con estado de posible coincidencia; no solicita confirmación adicional. |
| 9. Volver al menú principal | No pide datos. |

Para especie, color, tamaño y zona, use descripciones consistentes entre los reportes. La especie se compara exactamente para puntuar; color, tamaño, zona y nombre se comparan sin distinguir mayúsculas/minúsculas.

## 7. Gestión de albergues

| Opción | Preguntas y respuestas |
|---|---|
| 1. Registrar albergue | **Código:** texto libre obligatorio y único. **Nombre:** texto libre. **Zona:** texto libre, normalmente el código de zona. **Capacidad:** entero mínimo `1`. |
| 2. Consultar albergues | No pide datos. |
| 3. Consultar capacidad disponible | **Código albergue:** código de un albergue registrado. |
| 4. Registrar entrada de persona | **Código albergue:** albergue registrado. **Documento persona:** documento de una persona registrada. Debe haber cupo, la persona no debe estar ya alojada y su estado debe permitir el cambio a `en_albergue`. |
| 5. Registrar salida de persona | **Código albergue** y **Documento persona:** deben corresponder a un albergue y una persona registrada que esté alojada allí. Al salir, la persona cambia a `localizada` si la transición de estado es válida. |
| 6. Asociar recursos | **Código albergue:** albergue registrado. **Código recurso:** recurso registrado. |
| 7. Consultar necesidades asociadas | No pide datos. Muestra las necesidades asociadas en el sistema. |
| 8. Mostrar ocupación | No pide datos. |
| 9. Albergue con mayor ocupación | No pide datos. |
| 10. Volver al menú principal | No pide datos. |

## Roles y permisos que pueden afectar una respuesta

- **Administrador:** puede registrar usuarios después del primero y realizar las operaciones administrativas.
- **Coordinador:** necesario para registrar zonas, sectores, puntos de atención y centros; también puede confirmar coincidencias de mascotas.
- **Voluntario:** puede gestionar inventario, necesidades, albergues y entrega de mensajes; también puede buscar coincidencias de mascotas.
- **Ciudadano:** puede iniciar sesión y realizar las operaciones que solo requieren autenticación, como registrar necesidades, personas, mascotas o mensajes; no tiene los permisos reservados a voluntarios, coordinadores o administradores.

Aunque un texto libre no tenga una expresión o formato obligatorio, algunas operaciones requieren que el código o documento corresponda a un registro existente. Si la operación falla, revise el mensaje mostrado, el identificador usado y los permisos del rol conectado.