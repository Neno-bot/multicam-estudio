# MultiCam Studio (Fases 1, 2 y 3)

Aplicación multicámara de producción en vivo en Flutter donde los teléfonos funcionan como **Cámaras Emisoras** y una Tablet actúa como **Director / Receptor Principal** dentro de la misma red Wi-Fi local.

## Funcionalidades incluidas

### Fase 1 — Núcleo Multicámara LAN
1. **Pantalla adaptativa de selección de modo:** Recomienda automáticamente **Modo Cámara (Teléfono)** o **Modo Director (Tablet)** según el tamaño de pantalla.
2. **Descubrimiento automático en Wi-Fi local (mDNS + UDP Broadcast):** La Tablet anuncia su servidor WebSocket local (`_multicam._tcp` + UDP puerto `45454`) y los teléfonos se conectan automáticamente.
3. **Video de baja latencia (`flutter_webrtc`):** Conexión directa P2P en LAN (`iceServers: []`) con buffer de candidatos ICE y cambio de cámara frontal/trasera en vivo.
4. **Interfaz Landscape del Director (Tablet):** Monitor principal **EN VIVO (PGM)** superior + cuadrícula inferior de **4 cámaras simultáneas** con conmutación en un toque y luz **Tally**.

### Fase 2 — Control de Producción en Vivo
5. **Emparejamiento de respaldo por QR e IP manual:** Código QR escaneable (`multicam://<ip>:<puerto>`), entrada manual de IP y renombrado de cámara en tiempo real.
6. **Gestión profesional de audio (`AFV` / `MIX`):** Modo **Audio Follows Video (AFV)** por defecto + silencio individual por cámara.
7. **Transiciones (`CUT` / `FADE`) y rótulos (`Lower Third`):** Fundido suave configurable y editor de gráficos animados en vivo sobre el Monitor Principal.
8. **Control remoto de cámaras:** Voltear cámara y alternar linterna de cada teléfono desde la Tablet Director.
9. **Grabación local MP4 (`REC`):** Grabación del monitor principal con temporizador y rotación automática de clips al cambiar de cámara.

### Fase 3 — Modo Estudio, Calidad Dinámica, Telemetría y Tests
10. **Modo Estudio (`PVW / PGM` + botón `TAKE`):** Divide la vista superior en monitor **PREVIO (verde)** + botón central **TAKE/FADE** + monitor **EN VIVO (rojo)** con intercambio automático de la cámara anterior a `PVW`.
11. **Tally Dual (Rojo = `EN VIVO` / Verde = `PREVIO`):** Los teléfonos muestran borde rojo al salir al aire y borde verde cuando el Director los prepara en `PVW`.
12. **Calidad y bitrate en vivo (`480p30` / `720p30` / `1080p30`):** Cambiable desde el teléfono o remotamente desde el Director sin cortar la sesión WebRTC (`sender.replaceTrack` + límite de `maxBitrate`).
13. **Telemetría WebRTC en tiempo real (`STATS`):** HUD con resolución real, FPS, bitrate (`kbps`/`Mbps`), latencia (`ms`) e indicador de salud de señal por cámara.
14. **Pruebas automatizadas (`test/`):** Tests unitarios de modelos y test de integración WebSocket en loopback para registro, Tally dual y comandos remotos.

## Cómo obtener el APK para Android sin instalar Android Studio (GitHub Actions)

Este proyecto incluye el workflow `.github/workflows/build-android-apk.yml`:

1. Crea un repositorio en [GitHub](https://github.com/new) (por ejemplo `multicam-studio`).
2. Sube todo el contenido de la carpeta `multicam_studio/` (incluyendo `.github/workflows/build-android-apk.yml`) usando [GitHub Desktop](https://desktop.github.com/) o `git push`.
3. Ve a la pestaña **Actions** en tu repositorio y espera ~3 a 5 minutos a que finalice **Build Android APK**.
4. Entra a la sección **Releases** (derecha del repositorio) y abre **`MultiCam Studio (Última compilación Android)`**.
5. Descarga **`MultiCam-Studio.apk`** directamente en tu **Teléfono Android** y tu **Tablet Android** e instálalo para empezar a probar.

## Cómo compilar y probar localmente (opcional)

> Si prefieres compilar en tu PC, instala el **Flutter SDK** (`>= 3.24`) y ejecuta dentro de `multicam_studio`:

```bash
flutter create . --platforms=android,ios
flutter pub get
flutter test
flutter run
```

*(Al ejecutar `flutter create .`, verifica que `android/app/src/main/AndroidManifest.xml` e `ios/Runner/Info.plist` conserven los permisos de cámara, micrófono, multicast y Bonjour `_multicam._tcp`.)*
