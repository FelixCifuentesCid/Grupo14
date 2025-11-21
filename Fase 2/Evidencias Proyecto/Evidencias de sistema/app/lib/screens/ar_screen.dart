import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

// OJO: este archivo ahora es SOLO una pantalla.
// No definimos main(), la app arranca desde tu main.dart.

class TattooCylApp extends StatefulWidget {
  const TattooCylApp({super.key});

  @override
  State<TattooCylApp> createState() => _TattooCylAppState();
}

/* === TIPOS TOP-LEVEL === */
enum BoneId {
  rForearm,
  lForearm,
  rUpperArm,
  lUpperArm,
  rShin,
  lShin,
  rThigh,
  lThigh,
  torso,
  shoulders,
}

class Bone {
  final BoneId id;
  final Offset a;
  final Offset b;
  const Bone(this.id, this.a, this.b);
}

class BoneHit {
  final BoneId id;
  final double t;
  final Offset c;
  final Offset dir;
  final Offset n;
  const BoneHit(this.id, this.t, this.c, this.dir, this.n);
}

/* ========================= APP ========================= */
class _TattooCylAppState extends State<TattooCylApp> {
  CameraController? _cam;

  // Tamaño del frame “upright” (tras aplicar la rotación del sensor).
  // ¡Esto es lo que usa ML Kit para las coordenadas de pose!
  Size _uprightImageSize = const Size(1280, 720);

  late final PoseDetector _pose;
  Pose? _lastPose;
  bool _busyPose = false;

  // Tattoo
  ui.Image? _tattoo;

  // Anchor (tap)
  Offset? _tapWidget;
  BoneId? _anchorBone;
  double _anchorT = 0.5; // 0..1 a lo largo del segmento

  // Parámetros del parche cilíndrico
  double _halfLen = 120; // alto/2 del parche (en px pantalla)
  double _uScale = 1.0; // escala horizontal (ancho del parche)
  double _taper = 0.18; // forma cónica
  double _alpha = 0.9; // opacidad
  double _manualRadius = 46; // radio base en px (si quieres auto, lo cambiamos después)

  // Gestos
  double _gestureScale = 1.0; // escala de longitud (pinch)
  double _gestureRotation = 0.0; // giro alrededor (2 dedos)
  double _startScale = 1.0;
  double _startRotation = 0.0;

  // Malla
  static const int GRID_U = 28; // subdivisiones alrededor
  static const int GRID_V = 20; // subdivisiones a lo largo

  // Mostrar/ocultar panel de controles
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _pose = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadTattoo();
      await _initCamera();
    });
  }

  @override
  void dispose() {
    _cam?.dispose();
    _pose.close();
    super.dispose();
  }

  Future<void> _loadTattoo() async {
    // Asegúrate de que "assets/tattoo.png" esté declarado en pubspec.yaml
    final data = await DefaultAssetBundle.of(context).load('assets/tattoo.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    setState(() => _tattoo = frame.image);
  }

  Future<void> _initCamera() async {
    final perm = await Permission.camera.request();
    if (!perm.isGranted) return;

    final cams = await availableCameras();
    final back = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    final cam = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await cam.initialize();
    if (!mounted) return;
    _cam = cam;

    // Calcular tamaño "upright" según rotación del sensor (90/270 => swap).
    final rot = cam.description.sensorOrientation;
    final ps = cam.value.previewSize ?? const Size(1280, 720);
    _uprightImageSize =
        (rot == 90 || rot == 270) ? Size(ps.height, ps.width) : ps;

    await _cam!.startImageStream(_onFrame);
    setState(() {});
  }

  Future<void> _onFrame(CameraImage img) async {
    // Actualiza tamaño “upright” usando el frame real por si difiere del preview
    final rot = _cam!.description.sensorOrientation;
    final frameUpright = (rot == 90 || rot == 270)
        ? Size(img.height.toDouble(), img.width.toDouble())
        : Size(img.width.toDouble(), img.height.toDouble());
    _uprightImageSize = frameUpright;

    // Pose (throttle)
    if (!_busyPose) {
      _busyPose = true;
      try {
        final input = _toInputImage(img, _cam!.description);
        final poses = await _pose.processImage(input);
        if (poses.isNotEmpty) _lastPose = poses.first;
      } catch (_) {}
      _busyPose = false;
    }

    if (mounted) setState(() {});
  }

  // ==== YUV -> NV21 para ML Kit
  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width, height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;

    final out = BytesBuilder();

    // Y
    for (int y = 0; y < height; y++) {
      final row =
          yPlane.bytes.sublist(y * yRowStride, y * yRowStride + yRowStride);
      if (yPixelStride == 1) {
        out.add(row.sublist(0, width));
      } else {
        final line = Uint8List(width);
        for (int x = 0; x < width; x++) {
          line[x] = row[x * yPixelStride];
        }
        out.add(line);
      }
    }

    // UV (VU interleaved)
    final uRowStride = uPlane.bytesPerRow, vRowStride = vPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 2;
    final uvHeight = height ~/ 2, uvWidth = width ~/ 2;
    final uv = Uint8List(width * uvHeight);
    int k = 0;
    for (int y = 0; y < uvHeight; y++) {
      for (int x = 0; x < uvWidth; x++) {
        final v = vPlane.bytes[y * vRowStride + x * uvPixelStride];
        final u = uPlane.bytes[y * uRowStride + x * uvPixelStride];
        uv[k++] = v;
        uv[k++] = u;
      }
    }
    out.add(uv);
    return out.toBytes();
  }

  InputImage _toInputImage(CameraImage img, CameraDescription desc) {
    final nv21 = _yuv420ToNv21(img);
    final rotation =
        InputImageRotationValue.fromRawValue(desc.sensorOrientation) ??
            InputImageRotation.rotation0deg;
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(img.width.toDouble(), img.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: img.width,
      ),
    );
  }

  /* ====== MAPEOS usando BoxFit.cover ======
     CameraPreview usa Cover (escala = max, con recorte).
     ¡Esto era el desfase! Ahora el overlay usa la misma proyección. */
  Offset _imgToWidgetCover(Offset pImg, Size imageSize, Size widgetSize) {
    final iw = imageSize.width, ih = imageSize.height;
    final ww = widgetSize.width, wh = widgetSize.height;
    final scale = math.max(ww / iw, wh / ih); // COVER
    final ox = (ww - iw * scale) / 2.0;
    final oy = (wh - ih * scale) / 2.0;
    return Offset(pImg.dx * scale + ox, pImg.dy * scale + oy);
  }

  // Nota: la inversa solo se usa para utilidades (no dependemos de máscara ahora).
  Offset _widgetToImgCover(Offset pW, Size imageSize, Size widgetSize) {
    final iw = imageSize.width, ih = imageSize.height;
    final ww = widgetSize.width, wh = widgetSize.height;
    final scale = math.max(ww / iw, wh / ih);
    final ox = (ww - iw * scale) / 2.0;
    final oy = (wh - ih * scale) / 2.0;
    return Offset((pW.dx - ox) / scale, (pW.dy - oy) / scale);
  }

  /* ====== HUESOS (pose → segmentos) ====== */
  List<Bone> _bones(Size widgetSize) {
    if (_lastPose == null) return [];

    // Landmarks en coords de IMAGEN “upright”
    Offset? L(PoseLandmarkType t) =>
        _lastPose!.landmarks[t]?.let((l) => Offset(l.x, l.y));

    // Proyecta cada punto a WIDGET usando COVER y el tamaño “upright”
    Offset? w(Offset? img) =>
        img == null ? null : _imgToWidgetCover(img, _uprightImageSize, widgetSize);

    final rw = w(L(PoseLandmarkType.rightWrist));
    final re = w(L(PoseLandmarkType.rightElbow));
    final rs = w(L(PoseLandmarkType.rightShoulder));
    final lw = w(L(PoseLandmarkType.leftWrist));
    final le = w(L(PoseLandmarkType.leftElbow));
    final ls = w(L(PoseLandmarkType.leftShoulder));

    final rk = w(L(PoseLandmarkType.rightKnee));
    final ra = w(L(PoseLandmarkType.rightAnkle));
    final lk = w(L(PoseLandmarkType.leftKnee));
    final la = w(L(PoseLandmarkType.leftAnkle));

    final rh = w(L(PoseLandmarkType.rightHip));
    final lh = w(L(PoseLandmarkType.leftHip));

    final midHip = (rh != null && lh != null) ? (rh + lh) * 0.5 : null;
    final midSh = (rs != null && ls != null) ? (rs + ls) * 0.5 : null;

    final p = <Bone>[];
    if (rw != null && re != null) p.add(Bone(BoneId.rForearm, rw, re));
    if (lw != null && le != null) p.add(Bone(BoneId.lForearm, lw, le));
    if (re != null && rs != null) p.add(Bone(BoneId.rUpperArm, re, rs));
    if (le != null && ls != null) p.add(Bone(BoneId.lUpperArm, le, ls));

    if (ra != null && rk != null) p.add(Bone(BoneId.rShin, ra, rk));
    if (la != null && lk != null) p.add(Bone(BoneId.lShin, la, lk));
    if (rk != null && rh != null) p.add(Bone(BoneId.rThigh, rk, rh));
    if (lk != null && lh != null) p.add(Bone(BoneId.lThigh, lk, lh));

    if (midHip != null && midSh != null) {
      p.add(Bone(BoneId.torso, midHip, midSh));
    }
    if (ls != null && rs != null) {
      p.add(Bone(BoneId.shoulders, ls, rs));
    }

    return p;
  }

  BoneHit? _nearestBoneAtTap(Size widgetSize, Offset tapW) {
    final bones = _bones(widgetSize);
    if (bones.isEmpty) return null;

    double bestD = 1e9;
    Bone? best;
    double bestT = 0;

    for (final b in bones) {
      final ab = b.b - b.a;
      final len2 = (ab.dx * ab.dx + ab.dy * ab.dy);
      if (len2 < 1) continue;
      final ap = tapW - b.a;
      final t =
          ((ap.dx * ab.dx + ap.dy * ab.dy) / len2).clamp(0.0, 1.0);
      final c = b.a + ab * t;
      final d = (tapW - c).distance;
      if (d < bestD) {
        bestD = d;
        best = b;
        bestT = t;
      }
    }
    if (best == null) return null;

    final ab = best.b - best.a;
    final len = ab.distance;
    final dir = len == 0 ? const Offset(1, 0) : ab / len;
    final n = Offset(-dir.dy, dir.dx);
    final c = best.a + ab * bestT;
    return BoneHit(best.id, bestT, c, dir, n);
  }

  /* ====== Gestos ====== */
  void _onTap(Size size, TapUpDetails d) {
    _tapWidget = d.localPosition;
    final res = _nearestBoneAtTap(size, _tapWidget!);
    if (res != null) {
      _anchorBone = res.id;
      _anchorT = res.t;
    }
    setState(() {});
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _gestureScale;
    _startRotation = _gestureRotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _gestureScale = (_startScale * d.scale).clamp(0.5, 2.5);
      _gestureRotation = _startRotation + d.rotation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: (cam == null || !cam.value.isInitialized || _tattoo == null)
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (ctx, cons) {
                  final size = Size(cons.maxWidth, cons.maxHeight);

                  // Anchor actual → centro/dir/n
                  Offset? c;
                  Offset dir = const Offset(1, 0);
                  Offset n = const Offset(0, 1);
                  if (_anchorBone != null && _lastPose != null) {
                    final bones = _bones(size);
                    Bone? b;
                    for (final bb in bones) {
                      if (bb.id == _anchorBone) {
                        b = bb;
                        break;
                      }
                    }
                    if (b != null) {
                      final ab = b.b - b.a;
                      final len = ab.distance;
                      if (len > 1) {
                        dir = ab / len;
                        n = Offset(-dir.dy, dir.dx);
                        c = b.a + ab * _anchorT;
                      }
                    }
                  }

                  // Si aún no anclamos pero hay tap, busca 1 vez
                  if (c == null && _tapWidget != null) {
                    final res = _nearestBoneAtTap(size, _tapWidget!);
                    if (res != null) {
                      _anchorBone = res.id;
                      _anchorT = res.t;
                      c = res.c;
                      dir = res.dir;
                      n = res.n;
                    }
                  }

                  // Radio (manual por ahora; si quieres auto, lo activamos)
                  double radius =
                      _manualRadius.clamp(24.0, 160.0);

                  // Longitud efectiva y giro
                  final halfLen =
                      (_halfLen * _gestureScale).clamp(40.0, 300.0).toDouble();
                  final twist = _gestureRotation;

                  // === PATCH: calcula phiMax a partir del AR del PNG ===
                  final ar = _tattoo!.width / _tattoo!.height; // ancho/alto
                  double phiMax =
                      (ar * halfLen * _uScale) / math.max(radius, 1.0);
                  // límites razonables
                  phiMax = phiMax.clamp(
                    math.pi / 18,
                    math.pi * 0.75,
                  ).toDouble();

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTap(size, d),
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // CameraPreview ya usa Cover; nuestro overlay también.
                        CameraPreview(cam),

                        if (c != null)
                          CustomPaint(
                            painter: _CylTattooPainter(
                              tattoo: _tattoo!,
                              center: c,
                              dir: dir,
                              n: n,
                              radius: radius,
                              halfLen: halfLen,
                              phiMax: phiMax,
                              taper: _taper,
                              alpha: _alpha,
                              twist: twist,
                              gridU: GRID_U,
                              gridV: GRID_V,
                            ),
                          ),

                        // Botón flotante para mostrar/ocultar controles
                        Positioned(
                          top: 16,
                          right: 16,
                          child: SafeArea(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showControls = !_showControls;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showControls
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _showControls
                                          ? 'Ocultar'
                                          : 'Mostrar',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Controles (sliders) solo si _showControls = true
                        if (_showControls)
                          Positioned(
                            left: 12,
                            right: 12,
                            top: 60, // un poco más abajo para no chocar con el toggler
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 480),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  _slider(
                                    'Opacidad',
                                    _alpha,
                                    0.2,
                                    1.0,
                                    (v) => setState(() => _alpha = v),
                                  ),
                                  const SizedBox(height: 6),
                                  _slider(
                                    'Longitud (V)',
                                    _halfLen,
                                    60,
                                    260,
                                    (v) => setState(() => _halfLen = v),
                                  ),
                                  const SizedBox(height: 6),
                                  _slider(
                                    'Ancho (U) ×',
                                    _uScale,
                                    0.4,
                                    2.0,
                                    (v) => setState(() => _uScale = v),
                                  ),
                                  const SizedBox(height: 6),
                                  _slider(
                                    'Radio',
                                    _manualRadius,
                                    24,
                                    160,
                                    (v) => setState(
                                        () => _manualRadius = v),
                                  ),
                                  const SizedBox(height: 6),
                                  _slider(
                                    'Taper',
                                    _taper,
                                    0.0,
                                    0.6,
                                    (v) => setState(() => _taper = v),
                                  ),
                                  const SizedBox(height: 6),
                                  _pill(
                                    'Reset gestos',
                                    () {
                                      setState(() {
                                        _gestureScale = 1;
                                        _gestureRotation = 0;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    c == null
                                        ? 'Toca el brazo/pierna para anclar el parche.'
                                        : 'Pellizca = largo • 2 dedos = giro alrededor • “Ancho (U)” ajusta el parche horizontal.',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _pill(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );

  Widget _slider(
    String label,
    double v,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Expanded(
            child: Slider(
              value: v,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          Text(
            v.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/* ========================= PINTOR ========================= */
class _CylTattooPainter extends CustomPainter {
  final ui.Image tattoo;
  final Offset center;
  final Offset dir; // eje longitudinal
  final Offset n; // normal (perp en imagen)
  final double radius;
  final double halfLen;
  final double phiMax; // ¡derivado del AR del PNG + escala U!
  final double taper; // 0..0.6
  final double alpha;
  final double twist; // rotación alrededor del cilindro
  final int gridU, gridV;

  _CylTattooPainter({
    required this.tattoo,
    required this.center,
    required this.dir,
    required this.n,
    required this.radius,
    required this.halfLen,
    required this.phiMax,
    required this.taper,
    required this.alpha,
    required this.twist,
    required this.gridU,
    required this.gridV,
  });

  Float32List _f32(List<Offset> ps) {
    final out = Float32List(ps.length * 2);
    for (int i = 0; i < ps.length; i++) {
      out[i * 2] = ps[i].dx;
      out[i * 2 + 1] = ps[i].dy;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pos = <Offset>[];
    final tex = <Offset>[];
    final idx = <int>[];

    final imgW = tattoo.width.toDouble();
    final imgH = tattoo.height.toDouble();

    // Malla cilíndrica SOLO para el parche (no toda la circunferencia)
    // u ∈ [-phiMax,+phiMax], v ∈ [-halfLen,+halfLen]
    for (int j = 0; j <= gridV; j++) {
      final tv = j / gridV;
      final along = (tv - 0.5) * 2.0; // -1..+1
      final taperK = 1.0 + taper * (along);
      final rV = radius * taperK;

      for (int i = 0; i <= gridU; i++) {
        final tu = i / gridU;
        final phi = (tu - 0.5) * 2.0 * phiMax + twist;

        // Posición 2D: center + dir*(along*halfLen) + n*(r*sin(phi))
        final p = center +
            dir * (along * halfLen) +
            n * (rV * math.sin(phi));
        pos.add(p);

        // UV: mapeo directo a TODO el PNG (el PNG trae transparencia fuera del dibujo).
        tex.add(Offset(tu * imgW, tv * imgH));
      }
    }

    int at(int i, int j) => j * (gridU + 1) + i;
    for (int j = 0; j < gridV; j++) {
      for (int i = 0; i < gridU; i++) {
        final i0 = at(i, j);
        final i1 = at(i + 1, j);
        final i2 = at(i, j + 1);
        final i3 = at(i + 1, j + 1);
       idx.addAll([i0, i1, i2, i1, i3, i2]);
      }
    }

    final verts = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _f32(pos),
      textureCoordinates: _f32(tex),
      indices: Uint16List.fromList(idx),
    );

    final paint = Paint()
      ..shader = ImageShader(
        tattoo,
        TileMode.clamp,
        TileMode.clamp,
        Float64List.fromList(<double>[
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
        ]),
      )
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true
      ..color = Colors.white.withOpacity(alpha);

    canvas.drawVertices(verts, BlendMode.multiply, paint);
  }

  @override
  bool shouldRepaint(covariant _CylTattooPainter old) =>
      old.tattoo != tattoo ||
      old.center != center ||
      old.dir != dir ||
      old.n != n ||
      old.radius != radius ||
      old.halfLen != halfLen ||
      old.phiMax != phiMax ||
      old.taper != taper ||
      old.alpha != alpha ||
      old.twist != twist ||
      old.gridU != gridU ||
      old.gridV != gridV;
}

/* helper */
extension _Let<T> on T {
  R let<R>(R Function(T it) f) => f(this);
}
