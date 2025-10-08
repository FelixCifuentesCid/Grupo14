import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data'; // BytesBuilder / Float32List / Uint16List / Float64List
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

enum AnchorMode { autoPose, manualTap }
enum BodyRegion {
  rightForearm, // muñeca-codo derecho
  leftForearm,  // muñeca-codo izquierdo
  rightUpperArm, // codo-hombro derecho
  leftUpperArm,  // codo-hombro izquierdo
  rightThigh,   // rodilla-cadera derecha
  leftThigh,    // rodilla-cadera izquierda
  chest         // hombro izq - hombro der (parche en pecho)
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: TattooApp()));
}

class TattooApp extends StatefulWidget {
  const TattooApp({super.key});
  @override
  State<TattooApp> createState() => _TattooAppState();
}

class _TattooAppState extends State<TattooApp> {
  CameraController? _cam;
  late final PoseDetector _pose;
  Pose? _lastPose;
  bool _busy = false;

  ui.Image? _tattoo;
  Size _previewSize = const Size(1280, 720);

  AnchorMode _mode = AnchorMode.autoPose;
  BodyRegion _region = BodyRegion.rightForearm;

  // Quad manual (4 taps)
  final List<Offset> _manualQuad = [];
  // Parámetros
  double _alpha = 0.85;
  double _scale = 1.0;
  // Malla
  static const int GRID_N = 10; // columnas
  static const int GRID_M = 12; // filas

  @override
  void initState() {
    super.initState();
    _pose = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
    _loadTattoo();
    _initCamera();
  }

  Future<void> _loadTattoo() async {
    final data = await DefaultAssetBundle.of(context).load('assets/tattoo.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    setState(() => _tattoo = frame.image);
  }

  Future<void> _initCamera() async {
    if (await Permission.camera.request().isDenied) return;

    final cams = await availableCameras();
    final back = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    _cam = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _cam!.initialize();
    if (!mounted) return;

    _previewSize =
        Size(_cam!.value.previewSize?.width ?? 1280, _cam!.value.previewSize?.height ?? 720);

    await _cam!.startImageStream(_onFrame);
    setState(() {});
  }

  Future<void> _onFrame(CameraImage img) async {
    if (_busy) return;
    _busy = true;
    try {
      final input = _toInputImage(img, _cam!.description);
      final poses = await _pose.processImage(input);
      if (poses.isNotEmpty) {
        _lastPose = poses.first;
        if (mounted) setState(() {});
      }
    } catch (_) {
      // silenciar
    } finally {
      _busy = false;
    }
  }

  // ====== YUV_420_888 -> NV21 (necesario para que ML Kit procese bien el frame) ======

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;

    final uRowStride = uPlane.bytesPerRow;
    final uPixelStride = uPlane.bytesPerPixel ?? 2;

    final vRowStride = vPlane.bytesPerRow;
    final vPixelStride = vPlane.bytesPerPixel ?? 2;

    final out = Uint8List(width * height + (width * height ~/ 2));

    // Copiar Y (luma)
    int outIndex = 0;
    final yBytes = yPlane.bytes;
    for (int y = 0; y < height; y++) {
      int yRowStart = y * yRowStride;
      for (int x = 0; x < width; x++) {
        out[outIndex++] = yBytes[yRowStart + x * yPixelStride];
      }
    }

    // Copiar UV intercalado en orden VU (NV21)
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    int uvIndex = width * height;

    for (int y = 0; y < height ~/ 2; y++) {
      int uRowStart = y * uRowStride;
      int vRowStart = y * vRowStride;
      for (int x = 0; x < width ~/ 2; x++) {
        final v = vBytes[vRowStart + x * vPixelStride];
        final u = uBytes[uRowStart + x * uPixelStride];
        out[uvIndex++] = v;
        out[uvIndex++] = u;
      }
    }

    return out;
  }

  InputImage _toInputImage(CameraImage img, CameraDescription desc) {
    // Convertimos a NV21 y lo declaramos como tal
    final nv21 = _yuv420ToNv21(img);

    final rotation =
        InputImageRotationValue.fromRawValue(desc.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(img.width.toDouble(), img.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21, // <- clave
        bytesPerRow: img.width,        // stride efectivo para NV21
      ),
    );
  }

  @override
  void dispose() {
    _cam?.dispose();
    _pose.close();
    super.dispose();
  }

  // ==== QUAD de región corporal usando landmarks ====

  Offset _imgToWidget(Offset pImg, Size widgetSize) {
    // CameraPreview rota 90°: mapear (x,y) imagen → widget
    final sx = widgetSize.width / _previewSize.height;
    final sy = widgetSize.height / _previewSize.width;
    // usar dx/dy (no x/y)
    return Offset(pImg.dy * sx, pImg.dx * sy);
  }

  List<Offset>? _quadFromRegion(Size widgetSize) {
    final pose = _lastPose;
    if (pose == null) return null;

    PoseLandmark? L(PoseLandmarkType t) => pose.landmarks[t];

    late Offset aImg, bImg; // segmento principal para orientar el parche
    double widthK = 0.25;   // ancho relativo al largo del segmento
    double heightK = 0.6;   // alto relativo al largo

    switch (_region) {
      case BodyRegion.rightForearm:
        if (L(PoseLandmarkType.rightWrist) == null || L(PoseLandmarkType.rightElbow) == null) return null;
        aImg = Offset(L(PoseLandmarkType.rightWrist)!.x, L(PoseLandmarkType.rightWrist)!.y);
        bImg = Offset(L(PoseLandmarkType.rightElbow)!.x, L(PoseLandmarkType.rightElbow)!.y);
        widthK = 0.30; heightK = 0.65;
        break;
      case BodyRegion.leftForearm:
        if (L(PoseLandmarkType.leftWrist) == null || L(PoseLandmarkType.leftElbow) == null) return null;
        aImg = Offset(L(PoseLandmarkType.leftWrist)!.x, L(PoseLandmarkType.leftWrist)!.y);
        bImg = Offset(L(PoseLandmarkType.leftElbow)!.x, L(PoseLandmarkType.leftElbow)!.y);
        widthK = 0.30; heightK = 0.65;
        break;
      case BodyRegion.rightUpperArm:
        if (L(PoseLandmarkType.rightElbow) == null || L(PoseLandmarkType.rightShoulder) == null) return null;
        aImg = Offset(L(PoseLandmarkType.rightElbow)!.x, L(PoseLandmarkType.rightElbow)!.y);
        bImg = Offset(L(PoseLandmarkType.rightShoulder)!.x, L(PoseLandmarkType.rightShoulder)!.y);
        widthK = 0.35; heightK = 0.6;
        break;
      case BodyRegion.leftUpperArm:
        if (L(PoseLandmarkType.leftElbow) == null || L(PoseLandmarkType.leftShoulder) == null) return null;
        aImg = Offset(L(PoseLandmarkType.leftElbow)!.x, L(PoseLandmarkType.leftElbow)!.y);
        bImg = Offset(L(PoseLandmarkType.leftShoulder)!.x, L(PoseLandmarkType.leftShoulder)!.y);
        widthK = 0.35; heightK = 0.6;
        break;
      case BodyRegion.rightThigh:
        if (L(PoseLandmarkType.rightKnee) == null || L(PoseLandmarkType.rightHip) == null) return null;
        aImg = Offset(L(PoseLandmarkType.rightKnee)!.x, L(PoseLandmarkType.rightKnee)!.y);
        bImg = Offset(L(PoseLandmarkType.rightHip)!.x, L(PoseLandmarkType.rightHip)!.y);
        widthK = 0.35; heightK = 0.7;
        break;
      case BodyRegion.leftThigh:
        if (L(PoseLandmarkType.leftKnee) == null || L(PoseLandmarkType.leftHip) == null) return null;
        aImg = Offset(L(PoseLandmarkType.leftKnee)!.x, L(PoseLandmarkType.leftKnee)!.y);
        bImg = Offset(L(PoseLandmarkType.leftHip)!.x, L(PoseLandmarkType.leftHip)!.y);
        widthK = 0.35; heightK = 0.7;
        break;
      case BodyRegion.chest:
        if (L(PoseLandmarkType.leftShoulder) == null || L(PoseLandmarkType.rightShoulder) == null) return null;
        aImg = Offset(L(PoseLandmarkType.leftShoulder)!.x, L(PoseLandmarkType.leftShoulder)!.y);
        bImg = Offset(L(PoseLandmarkType.rightShoulder)!.x, L(PoseLandmarkType.rightShoulder)!.y);
        widthK = 0.6; heightK = 0.45;
        break;
    }

    // Pasa a coords del widget
    final a = _imgToWidget(Offset(aImg.dx, aImg.dy), widgetSize);
    final b = _imgToWidget(Offset(bImg.dx, bImg.dy), widgetSize);

    // Segmento
    final v = (b - a);
    final len = v.distance;
    final dir = len == 0 ? const Offset(1, 0) : v / len;

    // Normal 2D (perp)
    final n = Offset(-dir.dy, dir.dx);

    final halfW = len * widthK * _scale * 0.5;
    final halfH = len * heightK * _scale * 0.5;

    // Centro del parche: punto medio del segmento
    final c = a + v * 0.5;

    // Esquinas en orden: TL, TR, BL, BR (para bilinear estable)
    final tl = c - dir * halfH - n * halfW;
    final tr = c + dir * halfH - n * halfW;
    final bl = c - dir * halfH + n * halfW;
    final br = c + dir * halfH + n * halfW;

    return [tl, tr, bl, br];
  }

  // ==== UI & Rendering ====

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final tattoo = _tattoo;

    return Scaffold(
      backgroundColor: Colors.black,
      body: cam == null || !cam.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    if (_mode == AnchorMode.manualTap) {
                      setState(() {
                        if (_manualQuad.length < 4) _manualQuad.add(d.localPosition);
                        if (_manualQuad.length > 4) {
                          _manualQuad
                            ..clear()
                            ..add(d.localPosition);
                        }
                      });
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(cam),
                      CustomPaint(
                        painter: _MeshPainter(
                          tattoo: tattoo,
                          quad: _mode == AnchorMode.manualTap
                              ? (_manualQuad.length == 4 ? _manualQuad : null)
                              : _quadFromRegion(size),
                          alpha: _alpha,
                          gridN: GRID_N,
                          gridM: GRID_M,
                        ),
                      ),
                      _topBar(),
                      _bottomControls(),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 30,
      left: 12,
      right: 12,
      child: Row(
        children: [
          _chip(
            label: _mode == AnchorMode.autoPose ? 'Modo: AUTO (Pose)' : 'Modo: MANUAL (4 toques)',
            onTap: () {
              setState(() {
                _mode = _mode == AnchorMode.autoPose ? AnchorMode.manualTap : AnchorMode.autoPose;
                _manualQuad.clear();
              });
            },
          ),
          const SizedBox(width: 8),
          if (_mode == AnchorMode.autoPose)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<BodyRegion>(
                    dropdownColor: Colors.black87,
                    value: _region,
                    items: BodyRegion.values.map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Text(
                          r.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _region = v!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomControls() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _slider('Opacidad', _alpha, 0.2, 1.0, (v) => setState(() => _alpha = v)),
          const SizedBox(height: 8),
          _slider('Escala parche', _scale, 0.6, 1.8, (v) => setState(() => _scale = v)),
          if (_mode == AnchorMode.manualTap)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _manualQuad.length < 4
                    ? 'Toca ${4 - _manualQuad.length} punto(s) más para definir el quad'
                    : 'Quad listo: toca de nuevo 4 puntos para reubicar',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white))),
          Expanded(
            child: Slider(
              value: v,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final ui.Image? tattoo;
  final List<Offset>? quad; // [TL, TR, BL, BR]
  final double alpha;
  final int gridN, gridM;

  _MeshPainter({
    required this.tattoo,
    required this.quad,
    required this.alpha,
    required this.gridN,
    required this.gridM,
  });

  Float32List _offsetsToFloat32(List<Offset> ps) {
    final data = Float32List(ps.length * 2);
    for (int i = 0; i < ps.length; i++) {
      data[i * 2] = ps[i].dx;
      data[i * 2 + 1] = ps[i].dy;
    }
    return data;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (tattoo == null || quad == null) return;
    if (quad!.length != 4) return;

    final tl = quad![0];
    final tr = quad![1];
    final bl = quad![2];
    final br = quad![3];

    // Generar malla bilineal
    final pos = <Offset>[];
    final tex = <Offset>[];
    final idxs = <int>[];

    final imgW = tattoo!.width.toDouble();
    final imgH = tattoo!.height.toDouble();

    for (int j = 0; j <= gridM; j++) {
      final v = j / gridM;
      for (int i = 0; i <= gridN; i++) {
        final u = i / gridN;

        // Bilinear: P(u,v) = (1-u)(1-v)*tl + u(1-v)*tr + (1-u)v*bl + uv*br
        final p = tl * (1 - u) * (1 - v) +
            tr * u * (1 - v) +
            bl * (1 - u) * v +
            br * u * v;

        pos.add(p);
        tex.add(Offset(u * imgW, v * imgH));
      }
    }

    // Triangulación de la malla
    int idx(int i, int j) => j * (gridN + 1) + i;
    for (int j = 0; j < gridM; j++) {
      for (int i = 0; i < gridN; i++) {
        final i0 = idx(i, j);
        final i1 = idx(i + 1, j);
        final i2 = idx(i, j + 1);
        final i3 = idx(i + 1, j + 1);
        // Dos triángulos: (i0,i1,i2) y (i1,i3,i2)
        idxs.addAll([i0, i1, i2, i1, i3, i2]);
      }
    }

    final verts = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _offsetsToFloat32(pos),
      textureCoordinates: _offsetsToFloat32(tex),
      indices: Uint16List.fromList(idxs),
    );

    // Shader de imagen (matriz identidad 4x4)
    final paint = Paint()
      ..shader = ImageShader(
        tattoo!,
        TileMode.clamp,
        TileMode.clamp,
        Float64List.fromList(<double>[
          1, 0, 0, 0,
          0, 1, 0, 0,
          0, 0, 1, 0,
          0, 0, 0, 1,
        ]),
      )
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true
      ..color = Colors.white.withOpacity(alpha);

    canvas.drawVertices(verts, BlendMode.srcOver, paint);

    // // (Opcional) dibuja el quad para depurar
    // final debug = Paint()
    //   ..color = Colors.greenAccent.withOpacity(0.6)
    //   ..strokeWidth = 2
    //   ..style = PaintingStyle.stroke;
    // final path = Path()
    //   ..moveTo(tl.dx, tl.dy)
    //   ..lineTo(tr.dx, tr.dy)
    //   ..lineTo(br.dx, br.dy)
    //   ..lineTo(bl.dx, bl.dy)
    //   ..close();
    // canvas.drawPath(path, debug);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter old) =>
      old.tattoo != tattoo || old.quad != quad || old.alpha != alpha || old.gridN != gridN || old.gridM != gridM;
}
