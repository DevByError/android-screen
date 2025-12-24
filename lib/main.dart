import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'dart:io' show Platform;
import 'dart:convert';
import 'dart:math' as Math;

// --- CONFIGURATION ---
final String SERVER_URL = Platform.isAndroid
    ? 'http://10.0.2.2:3002' // Android Emulator
    : 'http://localhost:3002'; // Web/Desktop/iOS Sim

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 1. FORCE LANDSCAPE. Digital Signage is almost always horizontal.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    // Hide status bar for full immersion
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SignCraft Player',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: Colors.black, // Cinema feel
      ),
      home: const ScreenSetupGate(),
    );
  }
}

// ============================================================================
// --- SETUP SCREEN ---
// ============================================================================
class ScreenSetupGate extends StatefulWidget {
  const ScreenSetupGate({super.key});
  @override
  State<ScreenSetupGate> createState() => _ScreenSetupGateState();
}

class _ScreenSetupGateState extends State<ScreenSetupGate> {
  final TextEditingController _idController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cast_connected, size: 60, color: Colors.blue),
                const SizedBox(height: 24),
                const Text(
                  "Player Setup",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Enter Screen ID to connect",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _idController,
                  decoration: const InputDecoration(
                    labelText: "Screen ID",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.monitor),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (_idController.text.isNotEmpty) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MediaDisplayScreen(
                              screenId: _idController.text.trim(),
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text("START PLAYER"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// --- MAIN PLAYER SCREEN ---
// ============================================================================
class MediaDisplayScreen extends StatefulWidget {
  final String screenId;
  const MediaDisplayScreen({super.key, required this.screenId});
  @override
  State<MediaDisplayScreen> createState() => _MediaDisplayScreenState();
}

class _MediaDisplayScreenState extends State<MediaDisplayScreen> {
  IO.Socket? socket;
  bool isConnected = false;

  // Data
  List<Map<String, dynamic>>? _designs;
  List<dynamic>? _designRefs;
  int _currentIndex = 0;
  Map<String, dynamic>? _currentDesign;
  Map<String, dynamic>? _currentMetadata;
  bool _slideshowActive = false;

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  void _connectSocket() {
    socket = IO.io(SERVER_URL, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    socket!.connect();
    socket!.onConnect((_) {
      if (mounted) setState(() => isConnected = true);
      print("✅ Socket Connected: ${widget.screenId}");
      socket!.emit('register-device', {
        'type': 'android',
        'screenId': widget.screenId,
      });
    });
    socket!.onDisconnect((_) {
      if (mounted) setState(() => isConnected = false);
    });
    socket!.on('mobile-design-json', (data) => _handlePlaylistJson(data));
  }

  void _handlePlaylistJson(dynamic data) {
    if (data == null || data['content'] == null) return;
    try {
      print("📥 New Playlist Received");
      final playlist = jsonDecode(data['content']);
      final designRefs = playlist['designReferences'] as List;
      List<Map<String, dynamic>> designs = [];

      for (var ref in designRefs) {
        if (ref['designJSON'] != null) {
          designs.add(Map<String, dynamic>.from(ref['designJSON']));
        }
      }

      setState(() {
        _designs = designs;
        _designRefs = designRefs;
        _currentIndex = 0;
        _slideshowActive = true;
      });

      if (designs.isNotEmpty) _showDesign(0);
    } catch (e) {
      debugPrint("❌ Parse Error: $e");
    }
  }

  void _showDesign(int idx) {
    if (_designs == null || _designs!.isEmpty) return;
    if (!mounted) return;

    setState(() {
      _currentDesign = _designs![idx];
      _currentMetadata = Map<String, dynamic>.from(
        _currentDesign?['metadata'] ?? {},
      );
      _currentIndex = idx;
    });

    // Handle duration
    if (_designRefs != null && _designRefs!.length > idx) {
      int duration = (_designRefs![idx]['duration'] ?? 10).toInt();
      Future.delayed(Duration(seconds: duration), () {
        if (_slideshowActive && mounted) {
          int nextIdx = (idx + 1) % _designs!.length;
          _showDesign(nextIdx);
        }
      });
    }
  }

  @override
  void dispose() {
    socket?.disconnect();
    _slideshowActive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. The Design Renderer
          Center(child: _buildVirtualCanvas()),

          // 2. Status Overlay (Top Left)
          Positioned(
            top: 20,
            left: 20,
            child: AnimatedOpacity(
              opacity: isConnected ? 0.3 : 1.0, // Fade out when connected
              duration: const Duration(seconds: 1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${widget.screenId}",
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- VIRTUAL CANVAS STRATEGY ---
  // We create a container exactly the size of the design (e.g. 1920x1080)
  // and then scale it down to fit the phone screen.
  // This guarantees identical layout to the web.
  Widget _buildVirtualCanvas() {
    if (_currentDesign == null || _currentMetadata == null) {
      return const CircularProgressIndicator();
    }

    // 1. Get Design Resolution (from Web Metadata)
    double targetW = (_currentMetadata!['canvasWidth'] ?? 1920).toDouble();
    double targetH = (_currentMetadata!['canvasHeight'] ?? 1080).toDouble();
    Color bg = _parseColor(_currentMetadata!['canvasColor'] ?? '#FFFFFF');

    final elements = (_currentDesign!['elements'] is List)
        ? (_currentDesign!['elements'] as List)
              .whereType<Map<String, dynamic>>()
              .toList()
        : <Map<String, dynamic>>[];

    // Sort by zIndex
    elements.sort((a, b) => (a['zIndex'] ?? 0).compareTo(b['zIndex'] ?? 0));

    return LayoutBuilder(
      builder: (context, constraints) {
        // 2. Calculate Scale Factor to fit phone screen
        return FittedBox(
          fit: BoxFit.contain,
          child: Container(
            width: targetW,
            height: targetH,
            clipBehavior: Clip.hardEdge, // Clip anything outside canvas
            decoration: BoxDecoration(
              color: bg,
              boxShadow: [BoxShadow(color: Colors.black, blurRadius: 20)],
            ),
            child: Stack(
              children: elements.map<Widget>((map) {
                return _buildElement(map, targetW, targetH);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildElement(
    Map<String, dynamic> map,
    double canvasW,
    double canvasH,
  ) {
    // --- COORDINATE NORMALIZATION ---
    // If web sends 0.5, it means 50%. If it sends 500, it means 500px.
    double rawW = (map['width'] ?? 0).toDouble();
    double rawH = (map['height'] ?? 0).toDouble();
    double rawX = (map['x'] ?? 0).toDouble();
    double rawY = (map['y'] ?? 0).toDouble();

    // Logic: If value is <= 1.0 (and not explicitly 0), treat as %.
    // Otherwise treat as px.
    double w = (rawW <= 1.0 && rawW > 0) ? rawW * canvasW : rawW;
    double h = (rawH <= 1.0 && rawH > 0) ? rawH * canvasH : rawH;
    double x = (rawX <= 1.0 && rawX > 0) ? rawX * canvasW : rawX;
    double y = (rawY <= 1.0 && rawY > 0) ? rawY * canvasH : rawY;

    // Safety: Ensure visible size
    if (w < 1) w = 100;
    if (h < 1) h = 100;

    String type = (map['type'] ?? '').toString().toLowerCase();

    // Font Scaling
    double fontSize = (map['fontSize'] ?? 24).toDouble();
    if (fontSize <= 1.0) fontSize = fontSize * canvasH;

    // Colors
    String colorHex =
        map['fillColor'] ?? map['backgroundColor'] ?? map['color'] ?? '#000000';
    Color color = _parseColor(colorHex);
    Color? strokeColor = map['strokeColor'] != null
        ? _parseColor(map['strokeColor'])
        : null;
    double strokeWidth = (map['strokeWidth'] ?? 0).toDouble();

    Widget child;

    // --- ELEMENT RENDERER ---
    switch (type) {
      case 'rect':
      case 'rectangle':
        child = Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(
              (map['borderRadius'] ?? 0).toDouble(),
            ),
            border: strokeColor != null
                ? Border.all(color: strokeColor, width: strokeWidth)
                : null,
          ),
        );
        break;

      case 'circle':
        child = Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: strokeColor != null
                ? Border.all(color: strokeColor, width: strokeWidth)
                : null,
          ),
        );
        break;

      // --- SHAPES ---
      case 'triangle':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'triangle', color: color),
        );
        break;
      case 'star':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'star', color: color),
        );
        break;
      case 'heart':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'heart', color: color),
        );
        break;
      case 'pentagon':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'poly', sides: 5, color: color),
        );
        break;
      case 'hexagon':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'poly', sides: 6, color: color),
        );
        break;
      case 'octagon':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'poly', sides: 8, color: color),
        );
        break;
      case 'trapezoid':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'trapezoid', color: color),
        );
        break;
      case 'crescent':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'crescent', color: color),
        );
        break;
      case 'cross': // Also handles "plus"
      case 'plus':
        child = CustomPaint(
          size: Size(w, h),
          painter: _ShapePainter(type: 'cross', color: color),
        );
        break;
      case 'diamond':
        child = Transform.rotate(
          angle: 45 * Math.pi / 180,
          child: Container(width: w / 1.4, height: h / 1.4, color: color),
        );
        break;

      // --- MEDIA ---
      case 'image':
      case 'gif':
      case 'web-image':
        child = Image.network(
          _sanitizeUrl(map['content'] ?? ''),
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image),
          ),
        );
        break;

      case 'video':
      case 'web-video':
        child = SizedBox(
          width: w,
          height: h,
          child: SmartVideoPlayer(url: _sanitizeUrl(map['content'] ?? '')),
        );
        break;

      case 'youtube':
        child = SizedBox(
          width: w,
          height: h,
          child: SmartYouTubePlayer(url: map['content'] ?? ''),
        );
        break;

      // --- TEXT ---
      case 'text':
        child = SizedBox(
          width: w,
          height: h,
          child: Align(
            alignment: _getTextAlign(map['textStyle']?['textAlign']),
            child: Text(
              map['content'] ?? '',
              textAlign: _getTextAlignEnum(map['textStyle']?['textAlign']),
              style: TextStyle(
                color: _parseColor(map['color'] ?? '#000000'),
                fontSize: fontSize,
                fontFamily: map['textStyle']?['fontFamily'],
                fontWeight: (map['textStyle']?['bold'] ?? false)
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontStyle: (map['textStyle']?['italic'] ?? false)
                    ? FontStyle.italic
                    : FontStyle.normal,
                decoration: (map['textStyle']?['underline'] ?? false)
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
            ),
          ),
        );
        break;

      default:
        child = SizedBox(width: w, height: h);
    }

    // --- ANIMATION WRAPPER ---
    String? animName;
    if (map['animation'] is String)
      animName = map['animation'];
    else if (map['animation'] is Map)
      animName = map['animation']['type'];

    // We pass a Key to force the animation to restart when the slide index changes
    Widget finalWidget = AdvancedAnimator(
      key: ValueKey("${map['id']}_$_currentIndex"),
      animationName: animName,
      child: child,
    );

    // Apply Static Transforms (Rotation, Opacity)
    // Note: Rotation is degrees in web usually
    if (map['rotation'] != null && map['rotation'] != 0) {
      finalWidget = Transform.rotate(
        angle: (map['rotation'] as num) * Math.pi / 180,
        child: finalWidget,
      );
    }
    if (map['opacity'] != null) {
      double op = (map['opacity'] as num).toDouble();
      if (op < 1.0) finalWidget = Opacity(opacity: op, child: finalWidget);
    }

    return Positioned(
      left: x,
      top: y,
      child: SizedBox(width: w, height: h, child: finalWidget),
    );
  }

  // --- HELPERS ---
  String _sanitizeUrl(String url) {
    if (Platform.isAndroid && url.contains('localhost')) {
      return url.replaceAll('localhost', '10.0.2.2');
    }
    return url;
  }

  Alignment _getTextAlign(String? align) {
    switch (align) {
      case 'right':
        return Alignment.topRight;
      case 'center':
        return Alignment.topCenter;
      case 'justify':
        return Alignment.topLeft;
      default:
        return Alignment.topLeft;
    }
  }

  TextAlign _getTextAlignEnum(String? align) {
    switch (align) {
      case 'right':
        return TextAlign.right;
      case 'center':
        return TextAlign.center;
      case 'justify':
        return TextAlign.justify;
      default:
        return TextAlign.left;
    }
  }
}

Color _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return Colors.black;
  try {
    hex = hex.replaceAll('#', '');
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse('0x$hex'));
  } catch (_) {
    return Colors.black;
  }
}

// ============================================================================
// --- ANIMATION ENGINE (ADVANCED) ---
// ============================================================================
class AdvancedAnimator extends StatefulWidget {
  final String? animationName;
  final Widget child;
  const AdvancedAnimator({
    super.key,
    required this.animationName,
    required this.child,
  });

  @override
  State<AdvancedAnimator> createState() => _AdvancedAnimatorState();
}

class _AdvancedAnimatorState extends State<AdvancedAnimator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // Transforms
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  late Animation<double> _scale;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _setupAnimations();

    if (widget.animationName != null && widget.animationName!.isNotEmpty) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  void _setupAnimations() {
    String name = (widget.animationName ?? '').toLowerCase().replaceAll(
      ' ',
      '',
    );

    // 1. Base State (No change)
    _opacity = Tween<double>(begin: 1.0, end: 1.0).animate(_controller);
    _slide = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_controller);
    _scale = Tween<double>(begin: 1.0, end: 1.0).animate(_controller);
    _rotate = Tween<double>(begin: 0.0, end: 0.0).animate(_controller);

    // 2. Map Keywords
    // ENTRANCE ANIMATIONS
    if (name.contains('fade') || name == 'dissolve') {
      _opacity = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    } else if (name.contains('pop') ||
        name.contains('zoom') ||
        name.contains('scale')) {
      _scale = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    } else if (name.contains('rise') || name.contains('up')) {
      _slide = Tween<Offset>(
        begin: const Offset(0.0, 1.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    } else if (name.contains('down')) {
      _slide = Tween<Offset>(
        begin: const Offset(0.0, -1.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    } else if (name.contains('left') ||
        name.contains('slide') ||
        name.contains('pan')) {
      _slide = Tween<Offset>(
        begin: const Offset(-1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    } else if (name.contains('right')) {
      _slide = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    } else if (name.contains('rotate') || name.contains('spin')) {
      _rotate = Tween<double>(begin: -1.0, end: 0.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      );
      _scale = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    }
    // LOOPING ATTENTION ANIMATIONS
    else if (name.contains('pulse') || name.contains('heartbeat')) {
      _controller.repeat(reverse: true);
      _scale = Tween<double>(
        begin: 1.0,
        end: 1.1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    } else if (name.contains('shake') || name.contains('wiggle')) {
      _controller.repeat(reverse: true);
      _rotate = Tween<double>(
        begin: -0.05,
        end: 0.05,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 0), // Base offset
          child: SlideTransition(
            // Apply Slide
            position: _slide,
            child: Transform.rotate(
              angle: _rotate.value * 2 * Math.pi,
              child: Transform.scale(
                scale: _scale.value,
                child: Opacity(opacity: _opacity.value, child: widget.child),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// --- MEDIA PLAYERS ---
// ============================================================================
class SmartVideoPlayer extends StatefulWidget {
  final String url;
  const SmartVideoPlayer({super.key, required this.url});
  @override
  State<SmartVideoPlayer> createState() => _SmartVideoPlayerState();
}

class _SmartVideoPlayerState extends State<SmartVideoPlayer> {
  VideoPlayerController? _controller;
  @override
  void initState() {
    super.initState();
    if (widget.url.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize()
            .then((_) {
              _controller!.setLooping(true);
              _controller!.play();
              if (mounted) setState(() {});
            })
            .catchError((e) => debugPrint("Video Err: $e"));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized)
      return const SizedBox();
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
}

class SmartYouTubePlayer extends StatefulWidget {
  final String url;
  const SmartYouTubePlayer({super.key, required this.url});
  @override
  State<SmartYouTubePlayer> createState() => _SmartYouTubePlayerState();
}

class _SmartYouTubePlayerState extends State<SmartYouTubePlayer> {
  late YoutubePlayerController _controller;
  @override
  void initState() {
    super.initState();
    String? id = YoutubePlayer.convertUrlToId(widget.url);
    _controller = YoutubePlayerController(
      initialVideoId: id ?? '',
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        loop: true,
        hideControls: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayer(
      controller: _controller,
      showVideoProgressIndicator: false,
    );
  }
}

// ============================================================================
// --- UNIFIED SHAPE PAINTER ---
// ============================================================================
class _ShapePainter extends CustomPainter {
  final String type;
  final Color color;
  final int? sides; // For Polygons

  _ShapePainter({required this.type, required this.color, this.sides});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    switch (type) {
      case 'triangle':
        path.moveTo(cx, 0);
        path.lineTo(w, h);
        path.lineTo(0, h);
        path.close();
        break;

      case 'star':
        int n = 5;
        double R = w / 2;
        double r = R / 2.0;
        for (int i = 0; i < n * 2; i++) {
          double radius = i.isEven ? R : r;
          double angle = (i * Math.pi / n) - Math.pi / 2;
          double x = cx + radius * Math.cos(angle);
          double y = cy + radius * Math.sin(angle);
          if (i == 0)
            path.moveTo(x, y);
          else
            path.lineTo(x, y);
        }
        path.close();
        break;

      case 'heart':
        path.moveTo(cx, h * 0.8);
        path.cubicTo(w * 1.2, h * 0.5, w * 0.8, h * 0.1, cx, h * 0.3);
        path.cubicTo(w * 0.2, h * 0.1, -w * 0.2, h * 0.5, cx, h * 0.8);
        break;

      case 'poly':
        int s = sides ?? 6;
        double radius = w / 2;
        double offset = -Math.pi / 2;
        for (int i = 0; i < s; i++) {
          double angle = (2 * Math.pi) / s;
          double x = cx + radius * Math.cos(angle * i + offset);
          double y = cy + radius * Math.sin(angle * i + offset);
          if (i == 0)
            path.moveTo(x, y);
          else
            path.lineTo(x, y);
        }
        path.close();
        break;

      case 'trapezoid':
        path.moveTo(w * 0.2, 0);
        path.lineTo(w * 0.8, 0);
        path.lineTo(w, h);
        path.lineTo(0, h);
        path.close();
        break;

      case 'crescent':
        path.arcTo(Rect.fromLTWH(0, 0, w, h), 0.5, 5.5, true);
        path.arcTo(Rect.fromLTWH(w * 0.3, 0, w * 0.8, h), 0, 6.28, false);
        path.fillType = PathFillType.evenOdd;
        break;

      case 'cross':
        double t = w * 0.25; // Thickness
        path.addRect(
          Rect.fromCenter(center: Offset(cx, cy), width: t, height: h),
        );
        path.addRect(
          Rect.fromCenter(center: Offset(cx, cy), width: w, height: t),
        );
        break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
