# Cherry Mary — Contexto permanente del proyecto

## 1. Identidad del proyecto

**Nombre:** Cherry Mary  
**Producto:** e-commerce de salud y bienestar sexual.  
**Público principal:** mujeres.  
**Público adicional:** parejas y hombres.

La experiencia debe transmitir:

- Confidencialidad.
- Discreción.
- Seguridad.
- Cercanía.
- Elegancia.
- Bienestar.
- Minimización de datos personales.

La privacidad forma parte de la arquitectura y no se limita a mensajes comerciales.

---

## 2. Contexto técnico actual

El proyecto utiliza:

- Astro.
- TypeScript.
- npm.
- Git.
- GitHub.
- Vercel.
- Supabase.
- PostgreSQL mediante Supabase.

Ruta local de referencia:

`/Users/jose/Documents/Proyectos/E-Comerce/helpless-halo`

El repositorio ya está conectado a GitHub y el proyecto ya está desplegado en Vercel.

Supabase ya está configurado mediante:

`src/lib/supabase/client.ts`

Variables públicas:

```env
PUBLIC_SUPABASE_URL
PUBLIC_SUPABASE_ANON_KEY
```

Los valores reales existen únicamente en `.env.local`.

`.env.local` está excluido de Git.

Existe `.env.example` con valores de ejemplo.

La dependencia oficial instalada es:

```text
@supabase/supabase-js
```

Nunca deben mostrarse, copiarse, documentarse ni subirse claves reales.

---

## 3. Estructura general del repositorio

```text
src/
  assets/
  components/
    admin/
    auth/
    cart/
    catalog/
    chat/
    common/
  layouts/
  lib/
    supabase/
  pages/
    admin/
    checkout/
    cuenta/
    paquetes/
    productos/
  services/
  stores/
  styles/
  utils/

docs/

supabase/
  migrations/
  functions/
```

La estructura existente debe respetarse.

No deben crearse carpetas, abstracciones, dependencias o archivos sin una necesidad inmediata y aprobada.

---

## 4. Flujo oficial de trabajo

Cherry Mary utiliza un flujo obligatorio de tres niveles.

### Nivel 1 — Guía de arquitectura e ingeniería de software

Existe una conversación utilizada como guía de arquitectura e ingeniería de software.

Responsabilidades:

- Definir qué se hará.
- Explicar por qué se hará.
- Analizar las necesidades del negocio.
- Revisar los entregables de la conversación del proyecto.
- Detectar riesgos, contradicciones, ambigüedades y decisiones abiertas.
- Aprobar, rechazar o solicitar ajustes.
- Mantener el alcance de cada módulo.
- Evitar código, SQL o tablas prematuras.
- Decidir si el siguiente paso corresponde a documentación, Supabase, configuración manual o Codex.
- Autorizar explícitamente el siguiente paso.

La guía es la autoridad principal sobre:

- Arquitectura.
- Dominio.
- Modelo de datos.
- Seguridad.
- Integraciones.
- Convenciones.
- Alcance.
- Orden de implementación.
- Decisiones de negocio.

La guía debe distinguir siempre entre:

- Propuesto.
- En revisión.
- Aprobado.
- Implementado.
- Validado.
- Cerrado.

No debe declarar terminado un módulo con decisiones críticas pendientes.

### Nivel 2 — Conversación del proyecto

Existe otra conversación llamada:

**Tienda online de sex shop**

Su función es elaborar los entregables detallados autorizados por la guía.

Responsabilidades:

- Recibir el siguiente paso autorizado.
- Desarrollar únicamente el punto solicitado.
- Organizar la información del dominio.
- Elaborar documentos, propuestas, relaciones y reglas.
- Identificar decisiones abiertas.
- No resolver decisiones de negocio implícitamente.
- No rediseñar la arquitectura.
- No ampliar el alcance.
- No comenzar código, SQL o migraciones sin autorización.
- Preparar, cuando corresponda, un documento o prompt para Codex.

Todo entregable debe regresar a la guía para revisión.

La conversación del proyecto no puede aprobarse a sí misma.

### Nivel 3 — Implementación

Solo después de una aprobación formal se decide la vía de implementación:

1. Configuración manual en Supabase u otro servicio.
2. Prompt aprobado para Codex.
3. Combinación controlada de ambas.

Codex es un ejecutor técnico.

Codex no decide:

- El modelo de negocio.
- La arquitectura.
- El alcance del MVP.
- Las entidades.
- Las relaciones.
- Las reglas de seguridad.
- Las integraciones.
- Las convenciones globales.

Codex implementa únicamente decisiones documentadas y aprobadas.

---

## 5. Ciclo obligatorio por módulo

1. La guía define el objetivo y el siguiente paso.
2. La conversación del proyecto produce el entregable.
3. El entregable regresa a la guía.
4. La guía revisa.
5. Se corrigen observaciones.
6. La guía aprueba formalmente.
7. Se redacta el prompt de implementación.
8. Codex inspecciona el repositorio.
9. Codex implementa solo el alcance aprobado.
10. Codex ejecuta validaciones.
11. Codex entrega un reporte.
12. La guía revisa los resultados.
13. El usuario realiza commit y push.
14. Se autoriza el siguiente módulo.

Ningún módulo comienza si el anterior no está aprobado conforme a sus criterios.

---

## 6. Reglas permanentes para Codex

Antes de modificar, Codex debe:

- Inspeccionar el repositorio.
- Revisar `git status`.
- Leer los archivos relevantes.
- Reutilizar lo existente.
- Informar diferencias entre el repositorio y el contexto.
- No asumir que un archivo está vacío o ausente.

Durante la implementación:

- Un único objetivo por módulo.
- Alcance cerrado.
- Solo archivos permitidos.
- No tocar archivos prohibidos.
- No preparar módulos futuros.
- No crear abstracciones sin uso inmediato.
- No instalar dependencias sin justificación.
- No cambiar arquitectura.
- No mostrar secretos.
- No modificar `.env.local`.
- No aprovechar la tarea para hacer cambios adicionales.

Al finalizar:

- Ejecutar las validaciones indicadas.
- Ejecutar `npm run build` cuando corresponda.
- Informar errores reales.
- Revisar el diff.
- Ejecutar `git status`.
- Entregar un reporte estructurado.

El reporte debe incluir:

1. Objetivo realizado.
2. Archivos creados.
3. Archivos modificados.
4. Dependencias instaladas.
5. Validaciones ejecutadas.
6. Resultado del build.
7. Errores o advertencias.
8. Riesgos detectados.
9. Criterios de aceptación cumplidos.
10. Cambios omitidos por estar fuera de alcance.
11. Confirmación de que no se expusieron secretos.
12. Estado final del repositorio.

Codex nunca debe ejecutar:

```text
git commit
git push
```

El usuario conserva el control de commits, push y despliegues.

---

## 7. Estructura obligatoria de los prompts para Codex

Cada prompt debe contener:

1. Identificador del módulo.
2. Contexto actual.
3. Objetivo único.
4. Estado inicial esperado.
5. Inspección obligatoria.
6. Alcance incluido.
7. Fuera de alcance.
8. Archivos que puede crear.
9. Archivos que puede modificar.
10. Archivos que no debe tocar.
11. Reglas arquitectónicas.
12. Pasos de implementación.
13. Validaciones obligatorias.
14. Criterios de aceptación.
15. Formato del reporte final.
16. Prohibición de commit y push.

No se permiten instrucciones ambiguas como:

> Construye el módulo de productos.

Debe indicarse exactamente qué hacer, qué no hacer y cómo verificarlo.

---

## 8. Definición de terminado

Un módulo termina únicamente cuando:

- Cumplió su objetivo único.
- No amplió el alcance.
- Pasó todas las validaciones.
- Mantiene la documentación actualizada.
- Entregó el reporte final.
- Fue revisado por la guía.
- Cumplió los criterios de aceptación.
- No conserva decisiones críticas pendientes.

Que algo compile no significa automáticamente que esté terminado.

---

## 9. Identificadores

Módulos actuales:

- `CM-M03.1` — Diseño de datos.
- `CM-M03.2` — Migraciones iniciales.
- `CM-M03.3` — Políticas de seguridad.
- `CM-M03.4` — Seed inicial.

El identificador debe aparecer en:

- Documento.
- Prompt.
- Registro de decisiones.
- Reporte final.
- Mensaje del commit realizado por el usuario.

Decisiones arquitectónicas:

- `CM-ADR-001`
- `CM-ADR-002`
- `CM-ADR-003`
- `CM-ADR-004`
- `CM-ADR-005`
- `CM-ADR-006`
- `CM-ADR-007`

Adendas aprobadas:

- `CM-ADR-007 — Adenda 01 — Conservación de evidencia logística`

La Adenda 01 complementa `CM-ADR-007`; no lo reemplaza y no crea `CM-ADR-008`.

Cada decisión debe registrar:

- Identificador.
- Fecha.
- Problema.
- Decisión.
- Alternativas consideradas.
- Impacto.
- Estado.

Estados posibles:

- propuesta
- aprobada
- reemplazada
- descartada

---

## 10. Principios arquitectónicos — CM-ARC-001

### Simplicidad primero

Elegir la solución más simple que resuelva correctamente la necesidad actual.

### Una fuente de verdad por dato

Cada dato debe tener un origen autoritativo definido.

### El dominio manda

La tecnología se adapta al negocio y no al revés.

### Seguridad por defecto

Todo acceso se considera restringido hasta que una regla explícita lo permita.

### Escalabilidad gradual

La arquitectura crece cuando aparecen necesidades reales.

### Trazabilidad de decisiones

Toda decisión relevante registra qué se decidió, por qué y qué alternativas se descartaron.

---

## 11. Reglas de comunicación y revisión

En tareas prácticas:

1. Dar una introducción breve.
2. Explicar qué se hará.
3. Dar únicamente el siguiente paso.
4. Esperar el resultado antes de continuar.

No entregar grandes bloques operativos de golpe, salvo que el usuario solicite un documento o prompt completo.

Cuando la conversación del proyecto esté trabajando, la guía debe esperar su entregable.

No debe:

- Inventar avances.
- Repetir preguntas ya enviadas.
- Cambiar el flujo.
- Proponer tareas paralelas.
- Dar por recibido un documento no entregado.
- Responder con generalidades cuando exista un entregable concreto.

Al revisar un entregable, la guía debe:

1. Confirmar qué recibió.
2. Evaluarlo contra el objetivo.
3. Identificar aciertos.
4. Identificar problemas o decisiones abiertas.
5. Asignar un estado.
6. Autorizar exactamente el siguiente paso.

Las revisiones importantes deben terminar con:

```text
Estado actual:
Decisiones pendientes:
Próximo paso autorizado:
```

---

## 12. Protocolo contra pérdida de contexto

Este documento es la fuente permanente de verdad del flujo.

Cuando una conversación sea larga:

- Revisar el último estado aprobado.
- Distinguir lo aprobado de lo propuesto.
- Pedir el último entregable si no está disponible.
- Señalar contradicciones.
- No reconciliar silenciosamente versiones distintas.
- No afirmar que un archivo, módulo o decisión existe sin evidencia.
- No continuar por inercia.
- Decir exactamente qué información falta.

Si el usuario indica que otra conversación está trabajando, debe esperarse el resultado.

---

## 13. Estado arquitectónico actual

Módulo actual:

`CM-M03.2 — Migraciones iniciales`

Estado general:

- `CM-M03.1 — Documento de dominio y diseño de datos`: **aprobado definitivamente y cerrado el 28 de julio de 2026**.
- `DP-01` a `DP-04`: **aprobadas y cerradas**.
- `PR-01` a `PR-03`: **aprobadas y cerradas**.
- `CM-ADR-001` a `CM-ADR-007`: **aprobadas**.
- `CM-ADR-007 — Adenda 01 — Conservación de evidencia logística`: **aprobada**.
- `CM-M03.2 — Migraciones iniciales`: **iniciado y en curso**.
- Fase de inspección técnica de `CM-M03.2`: **completada, validada y cerrada documentalmente**.
- `CM-M03.3 — RLS`: **no iniciado**.
- `CM-M03.4 — Seed inicial`: **no iniciado**.

El cierre conceptual de `CM-M03.1` permanece vigente. Las decisiones físicas y migraciones aprobadas posteriormente dentro de `CM-M03.2` no reabren ni modifican las decisiones de dominio ya cerradas.

CM-M03.1 comenzó con cuatro preguntas:

1. ¿Qué información necesita persistir?
2. ¿Qué entidades reales existen?
3. ¿Cómo se relacionan?
4. ¿Qué se almacena y qué se calcula?

Las cuatro preguntas fueron resueltas dentro del documento aprobado y cerrado de `CM-M03.1`.

La regla central es:

> Cherry Mary almacena hechos, identidades, decisiones, referencias, estados históricos y fotografías de operaciones. Calcula interpretaciones, conteos, porcentajes, tiempos, disponibilidad, métricas y resúmenes derivados.

Un valor matemáticamente calculable debe conservarse cuando forme parte de una operación histórica o contractual.

Ejemplos:

- Precio aplicado.
- Descuento aplicado.
- Costo de entrega.
- Impuestos.
- Total confirmado.
- Nombre comercial del producto al comprar.

### Estado de DP-01

`DP-01 — Variantes de producto` está **aprobada** y cerrada como decisión dentro de `CM-M03.1`.

Decisión registrada:

`CM-ADR-001 — Unidad vendible y variantes de producto`

- **Estado:** aprobada.
- **Fecha de aprobación:** 23 de julio de 2026.

Reglas aprobadas:

- Cherry Mary utiliza la presentación vendible como unidad universal de venta.
- Todo producto comercializable tiene al menos una presentación vendible.
- El producto conserva la información comercial compartida.
- Un producto con una sola presentación no necesita mostrar opciones al cliente.
- Un producto con varias presentaciones utiliza variantes seleccionables.
- SKU, precio vigente e inventario pertenecen únicamente a la presentación vendible.
- El producto no mantiene un segundo SKU, precio o inventario autoritativo.
- La partida del pedido conserva la presentación exacta adquirida y las condiciones históricas aplicadas.
- Los cambios posteriores del catálogo no modifican pedidos anteriores.
- Una imagen diferente no crea por sí sola una variante.
- Las imágenes específicas de una presentación son opcionales.
- El MVP no incluye configuradores avanzados ni generación automática de combinaciones.

### Estado de DP-02

`DP-02 — Inventario de paquetes` está **aprobada** y cerrada como decisión dentro de `CM-M03.1`.

Decisión registrada:

`CM-ADR-002 — Inventario de paquetes derivado de componentes`

- **Estado:** aprobada.
- **Fecha de aprobación:** 24 de julio de 2026.

Reglas aprobadas:

- Los paquetes del MVP no tienen inventario propio.
- El inventario autoritativo pertenece exclusivamente a las presentaciones vendibles componentes.
- La disponibilidad del paquete es derivada, no representa inventario propio y no constituye una reserva.
- Un paquete solo está comercialmente disponible cuando está activo, vigente, tiene una composición aplicable, todos sus componentes están autorizados para venderse dentro del paquete y existen cantidades suficientes.
- Cada componente corresponde a una presentación vendible concreta.
- La composición es fija para el MVP.
- Las cantidades repetidas de una misma presentación se consolidan.
- Distintos paquetes pueden compartir componentes, pero una misma unidad física solo puede consumirse una vez.
- La afectación de todos los componentes debe ser completa e indivisible; si no pueden afectarse todos, no se afecta ninguno.
- No existen reservas de inventario en el MVP. El carrito y el pedido pendiente no afectan inventario. El inventario se descuenta cuando se autoriza explícitamente la preparación; los componentes históricos de los paquetes se afectan completa e indivisiblemente y las reversiones se registran mediante movimientos compensatorios positivos.
- No se permiten sustituciones automáticas, implícitas ni silenciosas.
- No se permite selección libre de variantes dentro de los paquetes.
- Los paquetes prearmados y el modelo híbrido quedan fuera del MVP.
- El paquete puede tener un precio comercial propio, distinto de la suma de sus componentes.
- El pedido conserva históricamente el paquete, su nombre, precio, descuentos, presentaciones concretas y cantidad consolidada de cada presentación.
- Los cambios posteriores de composición no modifican pedidos anteriores.

### Estado de DP-03

`DP-03 — Carrito persistente` está **aprobada** y cerrada como decisión dentro de `CM-M03.1`.

Decisión registrada:

`CM-ADR-003 — Persistencia y propiedad del carrito`

- **Estado:** aprobada.
- **Fecha de aprobación:** 24 de julio de 2026.

Reglas aprobadas:

- Cherry Mary incluirá carrito persistente en el MVP mediante una estrategia gradual y limitada.
- Cada contexto de visitante tendrá un único carrito activo.
- El visitante podrá conservarlo sin proporcionar datos personales.
- El carrito visitante se limitará al mismo navegador o dispositivo.
- No existirá identidad anónima central.
- No habrá recuperación anónima entre dispositivos.
- El carrito visitante se eliminará obligatoriamente después de 30 días sin actividad.
- Cada cuenta autenticada tendrá un único carrito activo.
- El carrito autenticado podrá recuperarse entre sesiones y dispositivos autenticados.
- El contenido del carrito autenticado no permanecerá visible después de cerrar sesión.
- El carrito autenticado se eliminará obligatoriamente después de 60 días sin actividad.
- Si la cuenta no tiene carrito al iniciar sesión, el carrito visitante se transferirá.
- Si ambos carritos existen, se fusionarán de forma determinista.
- Las líneas de la misma presentación vendible acumularán cantidades.
- Los paquetes solo acumularán cantidades cuando representen la misma composición aplicable.
- Las composiciones diferentes no se fusionarán silenciosamente y deberán mostrarse como conflicto al cliente.
- Después de una asociación correcta no permanecerá una copia independiente del carrito visitante.
- El carrito representa una intención de compra.
- El carrito no es un pedido, una reserva ni una garantía de precio o disponibilidad.
- Agregar artículos al carrito no reserva inventario.
- Los precios y la disponibilidad son provisionales.
- Presentaciones, paquetes, cantidades, precios y composiciones deberán revalidarse antes del pedido.
- Solo el pedido conservará las condiciones históricas definitivas.
- Durante la vida activa, los artículos inválidos permanecerán visibles y bloqueados.
- Los cambios no se ocultarán mediante eliminación o reducción silenciosa.
- La simple visualización del carrito no reinicia el plazo de conservación.
- Solamente las modificaciones explícitas, transferencias o fusiones reinician el plazo.
- Cuando el carrito origine correctamente un pedido, su ciclo se cerrará y se habilitará un nuevo carrito vacío.
- El MVP no permitirá conversión parcial del carrito.
- El contenido del carrito no se utilizará para perfilado, promociones, segmentación, inferencias íntimas ni recomendaciones personalizadas sin una decisión posterior.
- El carrito no depende de que exista una cuenta.

### Estado de DP-04

`DP-04 — Chat en primera fase` está **aprobada y cerrada como decisión** dentro de `CM-M03.1`.

Decisión registrada:

`CM-ADR-004 — Canal de atención en la primera fase`

- **Estado:** aprobada.
- **Fecha de aprobación:** 24 de julio de 2026.

Reglas aprobadas:

- Cherry Mary no incluirá chat humano o automatizado en tiempo real durante la primera fase del MVP.
- No habrá chatbot basado en inteligencia artificial ni respuestas generativas autónomas.
- La atención utilizará información ampliada, preguntas frecuentes y solicitudes internas de atención asincrónica.
- La `Solicitud de atención asincrónica` es el concepto principal aprobado.
- Puede contener uno o varios mensajes, recibir respuestas, tener una finalidad y relacionarse opcionalmente con un producto, presentación, paquete, pedido o incidencia.
- La solicitud interna es la fuente autoritativa de la necesidad recibida, mensajes, respuestas, estado general, resolución, canalización y causa de cierre.
- El correo es únicamente un medio para entregar o avisar respuestas; no constituye un historial autoritativo separado.
- El pedido o la incidencia correspondiente conserva cambios de estado, acciones operativas, devoluciones, compensaciones, reembolsos, acciones de preparación o entrega y acuerdos ejecutados.
- Una solicitud de atención no modifica por sí sola un pedido.
- Visitantes y clientes pueden presentar solicitudes.
- No se requiere una cuenta ni nombre real para consultas comerciales cuando no sean necesarios.
- Solo se solicita un medio de contacto cuando sea necesario entregar una respuesta.
- Una solicitud pseudónima no se asocia con una cuenta sin acción expresa y finalidad legítima.
- No existe acceso automático al carrito, pedidos, historial de compras u otras solicitudes.
- El acceso del personal depende de la finalidad y del principio de mínima necesidad.
- Cuando una consulta comercial cambia a pedido o incidencia, el cambio es explícito, se informa a la persona, se solicita únicamente información adicional necesaria y cambia la política de acceso y conservación.
- El ciclo de vida sigue la secuencia: recepción, atención, resolución, canalización o cierre válido, conservación posterior al cierre y eliminación obligatoria.
- Una solicitud abierta o en atención no se elimina únicamente por el transcurso del tiempo.
- Cuando se necesita información del cliente y transcurren 14 días naturales sin respuesta, la solicitud puede cerrarse por abandono o falta de respuesta, sin marcarse como resuelta y siempre que Cherry Mary no mantenga una acción operativa pendiente.
- La falta de seguimiento del personal no constituye abandono.
- Ninguna solicitud debe permanecer 30 días sin actuación sustantiva o disposición expresa; este es un control administrativo interno, no un plazo de eliminación ni un tiempo de respuesta prometido.
- Las solicitudes sin pedido o incidencia se conservan 14 días naturales después del cierre válido y se eliminan obligatoriamente al concluir el día 14.
- Las solicitudes con pedido o incidencia se conservan 90 días naturales después del cierre válido y se eliminan obligatoriamente al concluir el día 90.
- El texto es la modalidad predeterminada.
- Los archivos solo pueden solicitarse para incidencias posteriores a la compra cuando sean realmente necesarios.
- Los archivos tienen acceso restringido y se eliminan cuando dejan de ser necesarios o, como máximo, junto con la solicitud.
- Si se recibe espontáneamente contenido sensible o innecesario, no se solicitan más detalles, se limita el acceso, no se reutiliza ni copia sin necesidad legítima y se elimina anticipadamente cuando no es necesario.
- La atención es comercial y operativa; no ofrece diagnóstico, tratamiento, prescripción, terapia, evaluación de síntomas ni recomendaciones clínicas personalizadas.
- Las solicitudes no se utilizan para perfilado, promociones, segmentación, inferencias íntimas, recomendaciones personalizadas, analítica individual ni entrenamiento de sistemas.

### Estado de PR-01

`PR-01 — Administrador` está **aprobada y cerrada como decisión** dentro de `CM-M03.1`.

Decisión registrada:

`CM-ADR-005 — Identidad operativa y privilegios administrativos`

- **Estado:** aprobada.
- **Fecha de aprobación:** 24 de julio de 2026.
- **Alternativa seleccionada:** `C — Tienda como negocio representado y Administrador como actor`.

Reglas aprobadas:

- Cherry Mary o Tienda representa al negocio en cuyo nombre se realizan las operaciones.
- `PR-01` no diseña todavía una entidad técnica, tabla o estructura denominada `Tienda`.
- La persona operativa es el actor humano real y responsable de las acciones internas.
- Administrador representa funcionalmente a la persona operativa cuando actúa administrativamente en nombre de Cherry Mary.
- Administrador no constituye una entidad independiente, una segunda identidad, una representación duplicada de Cherry Mary, una cuenta ni un permiso total automático.
- La cuenta operativa es el acceso individual utilizado para ingresar al panel administrativo.
- Cada cuenta operativa corresponde a una sola persona.
- Las capacidades delimitan expresamente las acciones que la persona puede realizar.
- El término Administrador no concede acceso total por defecto.
- El panel administrativo es una interfaz separada de la tienda pública.
- El panel no es persona, identidad, cuenta, fuente de permisos ni autorización de acceso total.
- Durante el inicio del MVP puede existir una persona propietaria denominada `Administrador general`.
- El Administrador general debe ser una persona operativa identificada, utilizar una cuenta individual y recibir capacidades amplias de forma expresa.
- Las capacidades del Administrador general son atribuibles, reducibles, suspendibles y revocables.
- El acceso amplio no se concede automáticamente a otras personas.
- El modelo permite incorporar posteriormente personal con capacidades limitadas.
- Las cuentas operativas compartidas están prohibidas.
- Cada persona utiliza su propio acceso y una cuenta no se transfiere a otra persona.
- La cuenta personal de cliente y la cuenta operativa permanecen separadas.
- Suspender el acceso operativo no bloquea automáticamente la cuenta personal.
- No existe acceso general a carritos.
- El acceso a pedidos, ventas y datos de clientes depende de la función y mínima necesidad.
- Las solicitudes de atención solo son accesibles conforme a su finalidad.
- Los archivos sensibles tienen acceso todavía más restringido.
- La función autorizada se denomina `Atender solicitudes de atención asincrónica`.
- Una respuesta de atención no sustituye una acción registrada en el pedido o incidencia.
- Las acciones relevantes deben atribuirse a la persona operativa, la cuenta utilizada y la capacidad ejercida.
- La suspensión o revocación no elimina la atribución histórica.
- Recuperar una cuenta no restaura automáticamente capacidades revocadas.
- Una reincorporación requiere un nuevo otorgamiento de capacidades.

### Estado de PR-02

`PR-02 — Preparación de pedido` está **aprobada y cerrada como decisión** dentro de `CM-M03.1`.

Decisión registrada:

`CM-ADR-006 — Naturaleza y ciclo de la preparación de pedido`

- **Estado:** aprobada.
- **Fecha de propuesta:** 24 de julio de 2026.
- **Fecha de aprobación:** 27 de julio de 2026.
- **Alternativa aprobada:** `C — Pedido con estado general y preparación operativa separada`.

Reglas aprobadas:

- El pedido es la fuente autoritativa de lo comprado, partidas, presentaciones exactas, cantidades, paquetes, composición histórica, precios y condiciones, cambios comerciales ejecutados, habilitación vigente para preparar y cancelación.
- La preparación es la fuente autoritativa de su situación operativa vigente, acciones realizadas, verificaciones, responsables, bloqueos, correcciones, invalidaciones, revalidaciones, reaperturas, finalización, terminación sin completar e historial operativo.
- Una decisión comercial autorizada puede originar la habilitación, pero una vez ejecutada debe quedar reflejada autoritativamente en el pedido. La preparación conserva la referencia o evidencia de la habilitación utilizada, pero no constituye su fuente autoritativa.
- La preparación no se autoriza a sí misma, no decide estados de pago, no decide reservas y no decide descuentos de inventario.
- El pedido puede presentar una situación general relacionada con preparación, pero no constituye una segunda fuente independiente y no puede contradecir la preparación.
- Un pedido no puede considerarse listo mientras la preparación esté pendiente, en curso, bloqueada, reabierta o terminada sin completar.
- Solo una preparación correctamente finalizada permite considerar al pedido listo para el siguiente proceso autorizado.
- Reabrir la preparación retira esa interpretación, pero conserva la finalización anterior en el historial.
- Un pedido puede no tener preparación antes de ser habilitado.
- Cada pedido que ingresa al proceso tiene una única preparación en el MVP.
- No existen preparaciones concurrentes.
- Varias sesiones, responsables, correcciones y reaperturas permanecen dentro de la misma preparación.
- Un pedido nuevo tiene su propia preparación.
- La unidad de preparación es el pedido completo.
- No se permite preparación parcial finalizable ni división del pedido para entrega.
- Los paquetes se preparan completos e indivisibles.
- No se permiten sustituciones automáticas, implícitas ni silenciosas.
- Cuando un cambio comercial válido afecta la preparación, no se continúa con información anterior; la preparación se bloquea o reabre, las verificaciones afectadas dejan de estar vigentes, se conservan la causa y el trabajo anterior y el contenido se revalida contra el pedido vigente.
- La persona preparadora no decide por sí sola el cambio comercial.
- Bloqueos, correcciones, invalidaciones, revalidaciones y reaperturas conservan causa, responsable e historial.
- Las acciones relevantes deben atribuirse a la persona operativa, la cuenta utilizada y la capacidad ejercida.
- La persona preparadora solo accede a la información necesaria para su función.
- No existe acceso automático a carritos, historial completo de compras, solicitudes completas de atención o archivos sensibles.
- Una preparación está correctamente finalizada cuando todo el contenido vigente fue reunido, presentaciones y cantidades fueron verificadas, los paquetes están completos, las verificaciones necesarias están vigentes, no existen bloqueos y una persona autorizada confirmó la finalización.
- `Preparada` no significa entregada, pagada, inventario reservado, inventario descontado ni inicio automático de entrega.
- `PR-02` termina cuando el pedido completo queda listo para el siguiente proceso autorizado.
- El inicio, ciclo e incidencias de entrega permanecen reservados para `PR-03`.

### Estado de PR-03

`PR-03 — Entrega` está **aprobada y cerrada como decisión** dentro de `CM-M03.1`.

Decisión registrada:

`CM-ADR-007 — Naturaleza y ciclo de la entrega`

- **Estado:** aprobada.
- **Fecha de propuesta:** 27 de julio de 2026.
- **Fecha de aprobación:** 27 de julio de 2026.
- **Alternativa aprobada:** `C — Pedido con situación general y entrega operativa separada`.

Reglas aprobadas:

- El pedido es la fuente autoritativa de la verdad comercial, destino autorizado vigente, destinatario o recepción autorizada, información de contacto e instrucciones logísticas aprobadas, habilitación vigente para entregar, cambios comerciales, cancelación y resoluciones comerciales posteriores.
- La preparación es la fuente autoritativa de la condición vigente de que el pedido completo está correctamente preparado y de los bloqueos o reaperturas que impiden continuar la entrega.
- La entrega es la fuente autoritativa de su situación logística vigente, custodia y transferencias de custodia, salida física, responsables y proveedores, intentos y resultados, incidencias, reprogramaciones, evidencia proporcional, correcciones y reaperturas, finalización logística e historial logístico.
- Una decisión autorizada puede originar la habilitación, pero una vez ejecutada debe quedar reflejada autoritativamente en el pedido. La entrega conserva la referencia o evidencia de la habilitación utilizada, pero no constituye su fuente autoritativa ni se habilita a sí misma.
- La entrega no decide estados de pago, reservas ni descuentos de inventario.
- La entrega se reconoce conceptualmente después de la habilitación y su ejecución logística comienza cuando una persona o proveedor autorizado acepta la custodia del pedido preparado.
- La habilitación, la transferencia de custodia, la salida física y el primer intento son hechos distintos.
- Un pedido tiene como máximo una entrega en el MVP.
- Una entrega puede contener varios intentos y no existen entregas concurrentes.
- Los cambios de responsable o proveedor, las reprogramaciones y el regreso al origen permanecen dentro de la misma entrega.
- Un pedido nuevo tiene su propia preparación y entrega.
- La unidad de entrega es el pedido completo preparado.
- No existen entregas parciales o divididas y los paquetes permanecen completos e indivisibles.
- Cada intento conserva su resultado; un intento fallido no termina automáticamente la entrega.
- La decisión de no realizar más intentos requiere una disposición autorizada reconocida por Cherry Mary.
- El proveedor puede comunicar una imposibilidad, pero no decide por sí solo la disposición final.
- Cuando cambia válidamente el destino, destinatario, contacto, instrucciones, cancelación o preparación, la entrega no continúa con información anterior; se bloquea, corrige o requiere nueva habilitación y conserva el historial.
- Una entrega es exitosa cuando el pedido completo fue presentado en el destino autorizado, la custodia final se transfirió al destinatario o receptor autorizado, existe evidencia mínima suficiente y proporcional, no hay contradicción pendiente y una fuente autorizada confirmó el resultado.
- Solo una entrega correctamente finalizada permite considerar al pedido entregado.
- Reabrir retira esa interpretación y conserva la finalización anterior.
- La evidencia mínima puede reconocer momento, resultado, responsable o proveedor, destino utilizado, confirmación mínima de recepción, causa proporcional de no entrega y fuente del evento.
- No quedan aprobados automáticamente fotografías, firmas, copias de documentos de identidad, códigos o mecanismos técnicos específicos.
- Toda evidencia aplica proporcionalidad, minimización, discreción, finalidad limitada, acceso restringido, conservación limitada y eliminación anticipada cuando proceda.
### CM-ADR-007 — Adenda 01 — Conservación de evidencia logística

- **Estado:** aprobada.
- **Fecha de decisión del propietario:** 28 de julio de 2026.

Política aprobada:

> Los hechos logísticos mínimos permanecen como parte del historial transaccional de la entrega. El contenido sensible sin disputa se elimina tan pronto deje de ser necesario y, como máximo, 14 días naturales después de la finalización logística válida. La evidencia asociada con una disputa o incidencia se conserva mientras permanezca abierta y se elimina, como máximo, 90 días naturales después de su cierre válido. Un plazo mayor requiere una obligación comercial o legal documentada, finalidad específica, acceso restringido y fecha de revisión.

Reglas complementarias aprobadas:

- La eliminación anticipada es obligatoria cuando la evidencia deja de ser necesaria.
- Los plazos de 14 y 90 días son máximos, no periodos mínimos obligatorios.
- Los hechos logísticos mínimos no se clasifican como archivos sensibles de evidencia.
- Un plazo mayor solo procede mediante una obligación comercial o legal documentada, una finalidad específica, acceso restringido y una fecha de revisión.
- La decisión es arquitectónica y de privacidad del proyecto.
- No constituye validación legal, fiscal o regulatoria.
- La adenda no modifica la naturaleza ni la cardinalidad aprobadas de la Entrega.

### Aclaración aprobada sobre Incidencia

> `Incidencia` permanece como concepto transversal no unificado. Los hechos autoritativos continúan en el pedido, la preparación o la entrega, según corresponda. No se crea todavía una fuente operativa independiente ni un modelo técnico unificado de incidencias.

Implicaciones:

- Pedido conserva decisiones y hechos comerciales ejecutados.
- Preparación conserva bloqueos, hallazgos, correcciones, invalidaciones y revalidaciones.
- Entrega conserva intentos, incidencias logísticas, resultados, correcciones y reaperturas.
- Solicitud de atención asincrónica conserva la conversación y su resolución de atención.
- `Incidencia` no constituye una fuente autoritativa independiente.
- La posible unificación futura se difiere a un módulo funcional posterior.
- La ausencia de un modelo unificado no bloquea el modelo conceptual aprobado ni autoriza crear una segunda fuente operativa durante la implementación.
- El proveedor externo se reconoce como organización participante, pero no es la única fuente de verdad.
- Cherry Mary conserva proveedor, referencia, fuente, resultado reconocido y si el evento fue aceptado, corregido o disputado.
- La identidad de una persona externa solo se conserva cuando esté disponible y resulte proporcional.
- Quien entrega no recibe por defecto nombres o descripciones de productos, precios, descuentos, historial, carritos, solicitudes completas, archivos sensibles ni información íntima.
- Las acciones de personal propio se atribuyen a la persona operativa, cuenta utilizada y capacidad ejercida.
- Los resultados incorrectos no se borran; las correcciones y reaperturas conservan motivo, fuente, responsable e historial.
- La entrega concluye con un resultado logístico reconocido y no decide reembolsos, compensaciones, reposiciones, devoluciones comerciales, logística inversa o inventario.

### Estado del módulo

`CM-M03.1 — Documento de dominio y diseño de datos` está **aprobado definitivamente y cerrado**.

- **Fecha de aprobación formal:** 28 de julio de 2026.
- **Alcance del cierre:** modelo conceptual del dominio y diseño de datos.
- **Implementación técnica de CM-M03.1:** no formó parte de su alcance. La implementación física posterior se desarrolla dentro de `CM-M03.2`, que está iniciado y en curso.

La aprobación confirma que, dentro del alcance conceptual de `CM-M03.1`, no permanecen bloqueos arquitectónicos, fuentes autoritativas duplicadas ni decisiones críticas ocultas.

#### Fuentes autoritativas consolidadas

- **Producto:** información comercial compartida.
- **Presentación vendible:** SKU, precio vigente e inventario autoritativo.
- **Paquete:** definición comercial vigente.
- **Composición del paquete:** relación vigente de componentes vendibles; la disponibilidad se deriva de ellos.
- **Carrito:** intención provisional de compra; no constituye pedido, reserva ni garantía de precio o disponibilidad.
- **Pedido y partidas:** fotografía histórica de la compra, condiciones aplicadas, habilitaciones y decisiones comerciales ejecutadas.
- **Composición histórica del pedido:** componentes concretos comprometidos en paquetes adquiridos.
- **Persona operativa:** actor humano real de las acciones internas.
- **Cuenta operativa:** medio individual de acceso al panel administrativo.
- **Capacidades:** límites expresos de actuación.
- **Preparación:** situación operativa vigente, acciones e historial de preparación.
- **Entrega:** situación logística vigente, custodia, intentos, resultados e historial logístico.
- **Solicitud de atención asincrónica:** conversación, mensajes, respuestas, resolución de atención y causa de cierre.
- **Pedido, preparación o entrega:** hechos autoritativos vinculados con una incidencia, según la naturaleza del hecho.

Las situaciones generales mostradas por el Pedido se derivan o se mantienen conceptualmente coordinadas con Preparación y Entrega; no constituyen fuentes independientes que puedan contradecirlas.

#### Relaciones y cardinalidades aprobadas para el MVP

- Un Producto tiene una o más Presentaciones vendibles.
- Un Paquete tiene uno o más componentes correspondientes a Presentaciones vendibles concretas.
- Un Carrito contiene cero o más líneas provisionales.
- Un Pedido contiene una o más Partidas históricas.
- Un Pedido que ingresa a preparación tiene una única Preparación.
- No existen Preparaciones concurrentes para el mismo Pedido.
- Un Pedido tiene como máximo una Entrega.
- Una Entrega puede contener varios Intentos.
- No existen Entregas concurrentes, parciales o divididas.
- Preparación y Entrega utilizan el Pedido completo como unidad de trabajo.
- Una Persona operativa utiliza una Cuenta operativa individual y actúa dentro de Capacidades vigentes.
- Las cuentas operativas compartidas están prohibidas.
- Visitantes y clientes pueden presentar Solicitudes de atención asincrónica conforme a identificación mínima y finalidad legítima.

#### Convenciones de dominio cerradas

- Cherry Mary conserva hechos, identidades, decisiones, referencias, estados históricos y fotografías de operaciones.
- Cherry Mary calcula interpretaciones, conteos, porcentajes, tiempos, disponibilidad, métricas y resúmenes derivados.
- Un valor calculable se conserva cuando forma parte de una operación histórica o contractual.
- Las fotografías históricas no se reconstruyen desde datos actuales.
- No se sustituyen silenciosamente Presentaciones, cantidades, componentes, destinos o resultados.
- Las correcciones, invalidaciones y reaperturas conservan el historial anterior.
- Cherry Mary o Tienda representa al negocio; no se diseña en `CM-M03.1` como entidad técnica.
- Persona operativa es el actor humano real.
- Administrador es una denominación funcional de la Persona operativa cuando actúa en nombre de Cherry Mary.
- Solicitud de atención asincrónica sustituye el concepto de chat en la primera fase.
- El pedido completo es la unidad de Preparación y Entrega en el MVP.

#### Correcciones documentales consolidadas

La versión definitiva de `CM-M03.1`:

- Separa claramente `Cliente` y `Cuenta personal`.
- En el cierre original de `CM-M03.1`, compra como invitado y cuenta opcional quedaron diferidas; posteriormente fueron aprobadas para `CM-M03.2`: Cherry Mary permite compra como invitado, la Cuenta personal es opcional y Cliente permanece separado de Cuenta personal.
- Utiliza `Persona operativa` como actor humano real.
- Mantiene `Administrador` como denominación funcional.
- Sustituye chat por `Solicitud de atención asincrónica`.
- Integra Preparación y Entrega como decisiones aprobadas.
- Mantiene una Preparación y como máximo una Entrega por Pedido.
- Mantiene el Pedido completo como unidad, sin parcialidad finalizable.
- Clasifica `Incidencia` como concepto transversal no unificado.
- Actualiza matrices de conceptos, relaciones, cardinalidades y fuentes autoritativas.
- Actualiza conservación, eliminación, riesgos, decisiones diferidas, criterios de aceptación y diagrama conceptual.

#### Criterios de aceptación de CM-M03.1

Todos los criterios de aceptación están cumplidos para el alcance conceptual aprobado:

- Relaciones críticas definidas para el alcance actual.
- Datos persistentes justificados.
- Reglas de negocio documentadas.
- Convenciones de dominio cerradas.
- Convenciones físicas diferidas.
- Entidades revisadas conjuntamente.
- Fuentes autoritativas sin duplicaciones.
- Decisiones pendientes clasificadas.
- Ausencia de decisiones críticas ocultas.
- Privacidad y conservación justificadas.
- Alcance del MVP delimitado.
- Ausencia de diseño técnico prematuro.

Durante `CM-M03.1` no se crearon ni diseñaron tablas, columnas, SQL, migraciones, RLS, seed, código, APIs, webhooks, triggers, integraciones, cambios en Supabase, modificaciones en `.env.local`, prompts para Codex ni `CM-ADR-008`. La implementación física posterior pertenece exclusivamente a `CM-M03.2` y no altera el cierre conceptual de `CM-M03.1`.

### Estado de CM-M03.2 — Migraciones iniciales

`CM-M03.2 — Migraciones iniciales` está **iniciado y en curso**.

La fase de inspección técnica local y remota fue **completada, validada y cerrada documentalmente**. Incluyó:

- Inspección técnica local del repositorio y de las ubicaciones existentes de Supabase.
- Resolución de autoridad entre el repositorio exterior y el repositorio anidado.
- Inspección remota del proyecto de Supabase mostrado como `charry-mary`.

#### Repositorio oficial

El repositorio oficial de Cherry Mary es:

`/Users/jose/Documents/Proyectos/E-Comerce/helpless-halo`

La decisión se sustenta en que el repositorio:

- Tiene historial Git.
- Tiene remoto `origin`.
- Tiene upstream `origin/main`.
- Contiene la aplicación Astro.
- Contiene `src/lib/supabase/client.ts`.
- Contiene `supabase/migrations/` y `supabase/functions/`.
- Presentó estado Git limpio durante la inspección.
- Coincide con la ruta documentada del proyecto.

El repositorio exterior:

`/Users/jose/Documents/Proyectos/E-Comerce`

permanece clasificado como **contenedor Git accidental o incompleto**.

No está autorizado:

- Eliminar o mover su `.git`.
- Limpiar su índice.
- Mover archivos entre repositorios.
- Copiar configuración de Vercel.
- Normalizar su estructura.

#### Versiones detectadas durante la inspección

Las versiones siguientes describen únicamente el entorno inspeccionado y no constituyen requisitos arquitectónicos ni autorizan actualizaciones, instalaciones o cambios de dependencias:

- Node.js: `v24.1.0`.
- npm: `11.3.0`.
- Astro: `7.1.3`.
- `@supabase/supabase-js`: `2.110.8`.

#### Línea base local inspeccionada

Al cierre de la inspección técnica, antes de crear las migraciones:

- `supabase/migrations/` existía y contenía únicamente `.gitkeep`.
- `supabase/functions/` existía y contenía únicamente `.gitkeep`.
- `supabase/config.toml` no existía.
- No existían migraciones SQL.
- `src/lib/supabase/client.ts` existía y debía reutilizarse.
- No existían referencias en el código a tablas, vistas, RPC, buckets o funciones Edge.
- Supabase CLI no estaba disponible.
- Docker no estaba disponible.
- `.env.local` no fue abierto, mostrado ni modificado.

La ubicación única y oficial de migraciones es:

`/Users/jose/Documents/Proyectos/E-Comerce/helpless-halo/supabase/migrations/`

No debe crearse otra carpeta de migraciones.

#### Estado actual de migraciones locales

`M01` a `M12` constituyen la colección de migraciones iniciales aprobadas e implementadas de `CM-M03.2`.

Las siguientes migraciones están **implementadas, validadas estáticamente, versionadas y publicadas** en el repositorio remoto de código:

| Módulo | Archivo | Commit |
|---|---|---|
| `M01 — catalog_core` | `supabase/migrations/20260730184009_catalog_core.sql` | `b57661a` |
| `M02 — packages_and_classifications` | `supabase/migrations/20260730193524_packages_and_classifications.sql` | `f12c3b2` |
| `M03 — operational_identity_foundation` | `supabase/migrations/20260730195356_operational_identity_foundation.sql` | `cc5f0d7` |
| `M04 — operational_accounts_and_assignments` | `supabase/migrations/20260803224626_operational_accounts_and_assignments.sql` | `5ad8672` |
| `M05 — customers_personal_accounts_addresses` | `supabase/migrations/20260803232057_customers_personal_accounts_addresses.sql` | `940fc40` |
| `M06 — authenticated_carts` | `supabase/migrations/20260805134237_authenticated_carts.sql` | `51c1cbe` |
| `M07 — orders_and_historical_snapshots` | `supabase/migrations/20260805140658_orders_and_historical_snapshots.sql` | `6e5bd15` |
| `M08 — inventory_movements` | `supabase/migrations/20260805144727_inventory_movements.sql` | `4db5b89` |
| `M09 — order_preparation` | `supabase/migrations/20260805150024_order_preparation.sql` | `96904e8` |
| `M10 — order_delivery` | `supabase/migrations/20260805154111_order_delivery.sql` | `c7e3ab4` |
| `M11 — asynchronous_support` | `supabase/migrations/20260810160112_asynchronous_support.sql` | `496f9c0` |
| `M12 — sensitive_evidence_and_catalog_resources` | `supabase/migrations/20260810164914_sensitive_evidence_and_catalog_resources.sql` | `0460448` |

“Publicadas” significa que las migraciones fueron versionadas y publicadas en `origin/main`. **Ninguna migración había sido aplicada localmente ni remotamente a Supabase en el momento de esta sincronización documental.**

Las validaciones realizadas sobre `M01` a `M12` fueron estáticas y de repositorio. No debe afirmarse que las migraciones fueron ejecutadas o validadas contra PostgreSQL o contra el proyecto remoto de Supabase.

#### Alcance físico implementado hasta M12

Sin alterar las fuentes autoritativas del dominio, las migraciones implementadas cubren:

- Catálogo base, Presentaciones vendibles e inventario vigente.
- Paquetes, componentes y clasificaciones comerciales.
- Persona operativa y catálogo estructural de Capacidades.
- Cuentas operativas individuales vinculadas con Supabase Auth y asignaciones históricas de Capacidades.
- Cliente, Cuenta personal opcional vinculada con Supabase Auth y Direcciones reutilizables.
- Carritos autenticados y líneas provisionales; el carrito visitante permanece únicamente en el navegador.
- Pedido, Partidas y fotografías históricas, componentes históricos de Paquetes, destino autorizado y habilitación comercial para Preparación.
- Movimientos de inventario append-only, sin reservas y sin automatización transaccional.
- Preparación, acciones históricas y verificaciones vigentes por Partida.
- Entrega, custodia, asignaciones, intentos y acciones logísticas históricas.
- Solicitudes de atención asincrónica y mensajes asociados.
- Recursos editoriales del catálogo y metadatos mínimos de evidencia logística sensible adicional.

Las cuentas personales y operativas permanecen separadas. Supabase Auth se utiliza como proveedor técnico de autenticación sin duplicar contraseñas, sesiones, tokens, JWT, claims, MFA ni credenciales en tablas propias.

#### Decisiones físicas aprobadas durante CM-M03.2

Además de las decisiones conceptuales de `CM-M03.1`, durante `CM-M03.2` quedaron aprobadas para los módulos implementados:

- Cherry Mary permite compra como invitado.
- La Cuenta personal es opcional.
- Cliente y Cuenta personal permanecen separados.
- Todo Pedido pertenece a un Cliente.
- En compra como invitado se crea un Cliente sin Cuenta personal.
- Las cuentas personales utilizan Supabase Auth.
- Las cuentas operativas utilizan Supabase Auth.
- Las cuentas personales y operativas permanecen completamente separadas.
- No existen reservas de inventario en el MVP.
- El carrito y el Pedido pendiente no afectan inventario.
- El inventario se descuenta cuando se autoriza explícitamente la Preparación.
- Los componentes históricos de los Paquetes se descuentan completa e indivisiblemente.
- Si no existe cantidad suficiente para todos los componentes, no debe afectarse ninguno.
- Las reversiones se registran mediante movimientos compensatorios positivos.
- `presentation_inventory` conserva el saldo vigente autoritativo.
- `inventory_movements` conserva el historial append-only.
- La aplicación futura deberá actualizar saldo y movimientos dentro de una única transacción; `M08` no implementa esa transacción, funciones ni triggers.
- Los estados comerciales permitidos en `M07` son `pending_confirmation`, `confirmed` y `cancelled`.
- La Preparación solo puede habilitarse mediante una acción comercial explícita registrada.
- Los estados técnicos permitidos en `preparations` son `pending`, `in_progress`, `blocked`, `completed`, `ended_incomplete` y `reopened`.
- Los estados de verificación permitidos son `pending`, `verified`, `invalidated` y `blocked`.
- Un Pedido tiene como máximo una Preparación y no existen Preparaciones concurrentes.
- La unidad de trabajo de la Preparación es el Pedido completo y no existe finalización parcial.
- Los Paquetes deben verificarse completos conforme a sus componentes históricos.
- Reabrir conserva la finalización anterior en `preparation_actions`.
- Los hechos logísticos mínimos permanecen en el historial de Entrega.
- La evidencia logística sensible adicional se conserva separada de los hechos mínimos de Entrega.
- La evidencia sensible adicional puede eliminarse anticipadamente y no sustituye el historial logístico.
- Los recursos editoriales del catálogo pueden pertenecer a Producto, Presentación vendible o Paquete, sin almacenar SKU, precio, inventario, bucket, URL, proveedor ni credenciales.
- La Solicitud de atención asincrónica conserva conversación, mensajes, resolución de atención y causa de cierre sin modificar por sí sola Pedido, Preparación o Entrega.
- `M13 — transversal_audit` permanece diferida a `CM-M03.3`; `public.audit_events` todavía no existe.

#### Línea base remota de Supabase

Proyecto verificado por la guía:

```text
Nombre:
charry-mary

Project ref:
dfikkwujpnxljcxvkozq
```

La conclusión verificada de la inspección fue:

> La línea base remota de negocio estaba vacía respecto de tablas propias de Cherry Mary, políticas asociadas a tablas, migraciones registradas y buckets antes de la aplicación de `M01` a `M12`.

Estado verificado:

- Esquema `public`: sin tablas propias de Cherry Mary antes de la aplicación de `M01` a `M12`.
- Políticas asociadas a tablas: ninguna.
- Triggers asociados a tablas del esquema `public`: ninguno visible.
- Historial remoto de migraciones: vacío antes de la aplicación de `M01` a `M12`.
- Buckets de Storage: ninguno.
- Políticas bajo `storage.objects`: ninguna.
- Políticas bajo `storage.buckets`: ninguna.
- Event trigger `ensure_rls`: existe, está habilitado, se ejecuta en `ddl_command_end` e invoca `public.rls_auto_enable`.
- Función `public.rls_auto_enable`: owner `postgres`, return type `event_trigger`.

Como ninguna migración había sido aplicada localmente ni remotamente al momento de esta sincronización documental, la publicación de `M01` a `M12` en Git no modifica por sí sola esta línea base remota.

#### Objetos remotos preexistentes `ensure_rls` y `public.rls_auto_enable`

`ensure_rls` y `public.rls_auto_enable` se clasifican como:

> Objetos remotos preexistentes aceptados como condición técnica para la aplicación controlada de `M01` a `M12`.

Estado verificado:

```text
Función:
public.rls_auto_enable

Owner:
postgres

Return type:
event_trigger

Event trigger asociado:
ensure_rls

Evento:
ddl_command_end

Estado:
habilitado

Función invocada por el event trigger:
public.rls_auto_enable
```

La definición inspeccionada recorre comandos DDL proporcionados por `pg_event_trigger_ddl_commands()` para `CREATE TABLE`, `CREATE TABLE AS` y `SELECT INTO`. Cuando el objeto creado corresponde a una tabla o tabla particionada del esquema `public`, intenta ejecutar `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`. La función registra el éxito o fallo mediante mensajes de log. No crea políticas RLS.

Habilitar RLS no crea políticas de acceso. Sin políticas aplicables, habilitar RLS por sí solo no concede acceso a las tablas ni sustituye el diseño de `CM-M03.3`.

`public.rls_auto_enable` no debe:

- Eliminarse.
- Modificarse.
- Recrearse.
- Incluirse en migraciones de Cherry Mary.
- Adoptarse como decisión de Cherry Mary.
- Utilizarse como sustituto de las políticas de `CM-M03.3`.
- Considerarse suficiente para permitir acceso a las tablas.

`ensure_rls` no debe:

- Eliminarse.
- Modificarse.
- Deshabilitarse.
- Recrearse.
- Incluirse en migraciones de Cherry Mary.
- Adoptarse como decisión de Cherry Mary.
- Utilizarse como sustituto de las políticas de `CM-M03.3`.

#### Vercel

La raíz de despliegue de Vercel permanece **no verificable** por falta de autenticación y queda diferida.

Esta situación:

- No autoriza modificar `astro.config.mjs`.
- No autoriza modificar configuración de Vercel.
- No bloqueó la creación local y estática de las migraciones.
- Debe revisarse en un paso posterior expresamente autorizado.

#### Módulos todavía no iniciados o diferidos

- `CM-M03.3 — RLS`: no iniciado.
- `CM-M03.4 — Seed inicial`: no iniciado.
- `M13 — transversal_audit`: diferida a `CM-M03.3`.
- `public.audit_events`: todavía no existe.

`M13` no forma parte de las migraciones aplicables de `CM-M03.2`. La materialización de auditoría transversal se retomará conjuntamente con `CM-M03.3`; en ese módulo deberán decidirse acceso, integridad, minimización y conservación antes de cerrar su diseño físico.

La existencia de `M01` a `M12` no autoriza automáticamente la aplicación remota, RLS policies, seed, Storage, funciones, triggers, código de aplicación ni cambios de infraestructura.

---

## 14. Decisiones del módulo

### Cierre de CM-M03.1

- `CM-M03.1 — Documento de dominio y diseño de datos`: **aprobado definitivamente y cerrado el 28 de julio de 2026**.
- `DP-01 — Variantes de producto`: **aprobada y cerrada**.
- `DP-02 — Inventario de paquetes`: **aprobada y cerrada**.
- `DP-03 — Carrito persistente`: **aprobada y cerrada**.
- `DP-04 — Chat en primera fase`: **aprobada y cerrada**.
- `PR-01 — Administrador`: **aprobada y cerrada**.
- `PR-02 — Preparación de pedido`: **aprobada y cerrada**.
- `PR-03 — Entrega`: **aprobada y cerrada**.
- `CM-ADR-001` a `CM-ADR-007`: **aprobadas**.
- `CM-ADR-007 — Adenda 01 — Conservación de evidencia logística`: **aprobada**.

Las decisiones conceptuales permanecen vigentes y no fueron reemplazadas por las migraciones físicas.

### Registros arquitectónicos aprobados

- `CM-ADR-001 — Unidad vendible y variantes de producto`.
- `CM-ADR-002 — Inventario de paquetes derivado de componentes`.
- `CM-ADR-003 — Persistencia y propiedad del carrito`.
- `CM-ADR-004 — Canal de atención en la primera fase`.
- `CM-ADR-005 — Identidad operativa y privilegios administrativos`.
- `CM-ADR-006 — Naturaleza y ciclo de la preparación de pedido`.
- `CM-ADR-007 — Naturaleza y ciclo de la entrega`.
- `CM-ADR-007 — Adenda 01 — Conservación de evidencia logística`.

La Adenda 01 complementa `CM-ADR-007`; no lo reemplaza y no crea `CM-ADR-008`.

### CM-M03.2 — Inspección técnica

**Estado:** completada, validada y cerrada documentalmente.

Decisiones y hallazgos vigentes:

1. `helpless-halo` es el repositorio oficial de Cherry Mary.
2. El repositorio exterior es un contenedor Git accidental o incompleto y no debe intervenirse.
3. La ubicación oficial de migraciones es `helpless-halo/supabase/migrations/`.
4. La línea base remota de negocio inspeccionada no contenía tablas propias, políticas asociadas a tablas, migraciones registradas ni buckets antes de aplicar `M01` a `M12`.
5. Triggers asociados a tablas del esquema `public`: ninguno visible durante la inspección.
6. `ensure_rls` existe, está habilitado, se ejecuta en `ddl_command_end` e invoca `public.rls_auto_enable`.
7. `public.rls_auto_enable` pertenece al esquema `public`, tiene owner `postgres` y return type `event_trigger`.
8. La definición inspeccionada intenta habilitar RLS para determinadas tablas nuevas del esquema `public`, registra éxito o fallo y no crea políticas.
9. `ensure_rls` y `public.rls_auto_enable` no forman parte de las decisiones aprobadas de Cherry Mary y no deben modificarse ni adoptarse.
10. La raíz de despliegue de Vercel permanece no verificable y diferida.

### Decisiones aprobadas durante CM-M03.2

#### Identidad y acceso

- Supabase Auth está aprobado para las cuentas operativas.
- Supabase Auth está aprobado para las cuentas personales.
- No se duplican contraseñas, sesiones, tokens, JWT, claims, MFA ni credenciales en tablas propias.
- Persona operativa permanece como actor humano real.
- Administrador permanece como denominación funcional; no existe una tabla `Administrador`.
- Cherry Mary o Tienda permanece como negocio representado; no existe una tabla `Tienda`.
- Las cuentas personales y operativas permanecen completamente separadas.

#### Cliente y compra como invitado

- Cherry Mary permite compra como invitado.
- La Cuenta personal es opcional.
- Cliente y Cuenta personal permanecen separados.
- Una Cuenta personal se vincula directamente con un Cliente.
- Un Cliente puede tener como máximo una Cuenta personal.
- Toda Cuenta personal creada pertenece a un Cliente.
- Una compra como invitado crea o utiliza un Cliente sin requerir Cuenta personal.
- Todo Pedido pertenece a un Cliente.

#### Carrito

- El carrito visitante permanece únicamente en el navegador.
- El carrito autenticado pertenece a `personal_accounts`.
- Cada Cuenta personal puede tener como máximo un carrito activo.
- Las líneas representan exactamente una Presentación vendible o un Paquete.
- El carrito no reserva inventario ni conserva precio contractual.

#### Pedido e historia contractual

- Los estados comerciales aprobados son `pending_confirmation`, `confirmed` y `cancelled`.
- No existen estados de pago, Preparación o Entrega dentro del estado comercial del Pedido.
- Se conservan importes históricos agregados y por Partida.
- No existe tabla de pagos ni desglose fiscal avanzado en `M07`.
- Pedido, Partidas, componentes históricos y destino autorizado no se reconstruyen desde el catálogo o direcciones vigentes.
- La Preparación solo se habilita mediante una acción comercial explícita registrada.

#### Inventario

- No existen reservas de inventario en el MVP.
- El carrito y el Pedido pendiente no afectan inventario.
- El inventario se descuenta cuando se autoriza explícitamente la Preparación.
- Los componentes históricos de Paquetes se descuentan completa e indivisiblemente.
- Si no existe cantidad suficiente para todos los componentes, no se afecta ninguno.
- Las reversiones se registran mediante movimientos compensatorios positivos.
- Los movimientos originales no se borran ni modifican.
- `presentation_inventory` conserva el saldo vigente autoritativo.
- `inventory_movements` conserva el historial append-only.
- La operación futura de saldo y movimientos debe ser transaccional; todavía no se implementaron funciones ni triggers para ella.

#### Preparación

- Los estados técnicos aprobados son `pending`, `in_progress`, `blocked`, `completed`, `ended_incomplete` y `reopened`.
- Los estados de verificación aprobados son `pending`, `verified`, `invalidated` y `blocked`.
- Un Pedido tiene como máximo una Preparación.
- No existen Preparaciones concurrentes.
- La unidad de trabajo es el Pedido completo.
- No existe finalización parcial.
- Los Paquetes se verifican completos conforme a sus componentes históricos.
- `preparation_actions` conserva un historial append-only con Persona operativa, Cuenta operativa y Capacidad ejercida.
- Reabrir conserva la finalización anterior en el historial.
- La Preparación no modifica la verdad comercial del Pedido.
- `M09` no altera inventario ni crea movimientos.

### Estado de implementación de CM-M03.2

- `M01` a `M12`: **implementadas, validadas estáticamente, versionadas y publicadas**.
- Aplicación local de migraciones: **no realizada**.
- Aplicación remota a Supabase: **no realizada**.
- `M13 — transversal_audit`: **diferida a `CM-M03.3`**.
- `public.audit_events`: **todavía no existe**.
- `CM-M03.3 — RLS`: **no iniciado**.
- `CM-M03.4 — Seed inicial`: **no iniciado**.

### Decisiones y trabajos todavía diferidos

Permanecen diferidos o requieren autorización posterior:

- Aplicación local o remota controlada de `M01` a `M12`.
- `M13 — transversal_audit`, diferida a `CM-M03.3`.
- Políticas RLS y matriz técnica de acceso de `CM-M03.3`.
- Seed de `CM-M03.4`.
- Diseño físico de `public.audit_events`, incluyendo acceso, integridad, minimización y conservación.
- Configuración y raíz de despliegue de Vercel.
- Normalización del repositorio exterior.
- Buckets, Storage, APIs, webhooks, funciones Edge e integraciones.
- Proveedor logístico concreto, máximo de intentos y reglas específicas de Entrega.
- Pagos, pagos fallidos, reintentos financieros, reembolsos, compensaciones comerciales, devoluciones y logística inversa completa.
- Recuperación de Pedidos de invitados.
- Matriz definitiva de Capacidades y políticas de acceso.
- Automatizaciones técnicas de conservación y eliminación.

Ninguna decisión diferida puede resolverse implícitamente durante la programación.

---

## 15. Próximo paso autorizado

El único próximo paso autorizado es:

> `CM-M03.2-REMOTE-APPLY — Aplicación remota controlada de M01 a M12`.

Esta autorización podrá ejecutarse solo después de:

1. Revisar y aprobar esta sincronización documental.
2. Realizar manualmente commit de `CHERRY_MARY_PROJECT_CONTEXT.md`.
3. Publicar ese commit en `origin/main`.
4. Volver a obtener `git status --short` limpio.

Hasta que esas condiciones se cumplan:

- No debe ejecutarse `CM-M03.2-REMOTE-APPLY`.
- No debe crearse M13.
- No debe crearse `public.audit_events`.
- No debe iniciarse `CM-M03.3 — RLS`.
- No debe iniciarse `CM-M03.4 — Seed inicial`.
- No deben crearse RLS policies.
- No debe crearse seed.
- No debe modificarse código de aplicación.
- No debe modificarse `public.rls_auto_enable`.
- No debe modificarse `ensure_rls`.
- No debe modificarse `.env.local`.
- No debe modificarse Vercel ni `astro.config.mjs`.
- No debe intervenirse el repositorio exterior.
- No deben ejecutarse `git add`, `git commit` ni `git push`.
