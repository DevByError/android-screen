import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:io' show Platform;
import 'dart:convert';
import 'dart:math' as Math;

final String SERVER_URL = Platform.isAndroid
    ? 'http://10.0.2.2:3002'
    : 'http://localhost:3002';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const ScreenSetupGate(),
    );
  }
}

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
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monitor, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                "Setup Display",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const Text("Enter the Screen ID assigned in the Dashboard"),
              const SizedBox(height: 32),
              TextField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: "Screen ID",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (_idController.text.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MediaDisplayScreen(
                            screenId: _idController.text.trim(),
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    "Launch Display",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MediaDisplayScreen extends StatefulWidget {
  final String screenId;
  const MediaDisplayScreen({super.key, required this.screenId});
  @override
  State<MediaDisplayScreen> createState() => _MediaDisplayScreenState();
}

class _MediaDisplayScreenState extends State<MediaDisplayScreen> {
  IO.Socket? socket;
  bool isConnected = false;

  // For playlist slideshow
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
      socket!.emit('register-device', {
        'type': 'android',
        'screenId': widget.screenId,
      });
    });
    socket!.onDisconnect((_) {
      if (mounted) setState(() => isConnected = false);
    });
    socket!.on('mobile-design-json', (data) {
      _handlePlaylistJson(data);
    });
  }

  void _handlePlaylistJson(dynamic data) {
    debugPrint('🎨 PLAYLIST JSON RECEIVED: $data');
    if (data == null) return;

    if (data['content'] == null) {
      debugPrint('❌ No content field in data');
      return;
    }
    final playlist = jsonDecode(data['content']);
    debugPrint('🎨 Parsed playlist: $playlist');
    final designRefs = playlist['designReferences'] as List;
    debugPrint('🎨 designReferences count: ${designRefs.length}');
    List<Map<String, dynamic>> designs = [];
    for (var ref in designRefs) {
      debugPrint('🎨 DESIGN REF: $ref');
      if (ref['designJSON'] != null) {
        debugPrint('🎨 designJSON: ${ref['designJSON']}');
        if (ref['designJSON']['elements'] != null) {
          debugPrint('🎨 ELEMENTS: ${ref['designJSON']['elements']}');
        } else {
          debugPrint('❌ No elements in designJSON');
        }
        designs.add(Map<String, dynamic>.from(ref['designJSON']));
      } else {
        debugPrint('❌ No designJSON in design reference');
      }
    }

    setState(() {
      _designs = designs;
      _designRefs = designRefs;
      _currentIndex = 0;
      _slideshowActive = true;
    });

    if (designs.isNotEmpty) {
      _showDesign(0);
    }
  }

  void _showDesign(int idx) {
    if (_designs == null || _designs!.isEmpty) return;
    setState(() {
      _currentDesign = _designs![idx];
      _currentMetadata = Map<String, dynamic>.from(
        _currentDesign?['metadata'] ?? {},
      );
      _currentIndex = idx;
    });
    // Schedule next design
    if (_designRefs != null) {
      int duration = (_designRefs![idx]['duration'] ?? 5).toInt();
      Future.delayed(Duration(seconds: duration), () {
        if (_slideshowActive) {
          int nextIdx = (idx + 1) % _designs!.length; // Loop back to 0
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
          Center(child: _buildDesignCanvas()),
          Positioned(
            top: 40,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
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
                    "${widget.screenId} - ${isConnected ? 'LIVE' : 'OFFLINE'}",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesignCanvas() {
    if (_currentDesign == null || _currentMetadata == null) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_download, color: Colors.white24, size: 64),
          SizedBox(height: 16),
          Text(
            "Standing by for content...",
            style: TextStyle(color: Colors.white24),
          ),
        ],
      );
    }

    double designW = (_currentMetadata!['canvasWidth'] ?? 1280).toDouble();
    double designH = (_currentMetadata!['canvasHeight'] ?? 720).toDouble();
    Color bg = _parseColor(_currentMetadata!['canvasColor'] ?? '#FFFFFF');

    final elements = (_currentDesign!['elements'] is List)
        ? (_currentDesign!['elements'] as List)
              .whereType<Map<String, dynamic>>()
              .toList()
        : <Map<String, dynamic>>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        double screenW = constraints.maxWidth;
        double screenH = constraints.maxHeight;

        double scale = Math.min(screenW / designW, screenH / designH);

        return Container(
          color: bg,
          alignment: Alignment.center,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: designW,
              height: designH,
              child: elements.isEmpty
                  ? const Center(
                      child: Text(
                        "No elements found in this design.",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    )
                  : Stack(
                      children: elements.map<Widget>((map) {
                        Widget child;
                        final type = (map['type'] ?? '')
                            .toString()
                            .toLowerCase();

                        switch (type) {
                          case 'rect':
                          case 'rectangle':
                            child = Container(
                              width: (map['width'] ?? 100).toDouble(),
                              height: (map['height'] ?? 100).toDouble(),
                              decoration: BoxDecoration(
                                color: _parseColor(
                                  map['fillColor'] ?? '#FFFFFF',
                                ),
                                borderRadius: map['borderRadius'] != null
                                    ? BorderRadius.circular(
                                        (map['borderRadius'] ?? 0).toDouble(),
                                      )
                                    : null,
                              ),
                            );
                            break;

                          case 'circle':
                            child = Container(
                              width: (map['width'] ?? 100).toDouble(),
                              height: (map['height'] ?? 100).toDouble(),
                              decoration: BoxDecoration(
                                color: _parseColor(
                                  map['fillColor'] ?? '#FFFFFF',
                                ),
                                shape: BoxShape.circle,
                              ),
                            );
                            break;

                          case 'image':
                            child = Image.network(
                              map['content'] ?? '',
                              fit: BoxFit.cover,
                            );
                            break;

                          case 'text':
                            child = SizedBox(
                              width: (map['width'] ?? 200).toDouble(),
                              height: (map['height'] ?? 50).toDouble(),
                              child: Text(
                                map['content'] ?? '',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _parseColor(map['color'] ?? '#000000'),
                                  fontSize: (map['fontSize'] ?? 20).toDouble(),
                                  fontWeight:
                                      (map['textStyle']?['bold'] ?? false)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            );
                            break;

                          default:
                            child = Container(
                              width: (map['width'] ?? 100).toDouble(),
                              height: (map['height'] ?? 100).toDouble(),
                              color: Colors.red.withOpacity(0.2),
                              child: Center(
                                child: Text('Unknown: ${map['type']}'),
                              ),
                            );
                        }

                        // Rotation
                        if (map['rotation'] != null && map['rotation'] != 0) {
                          child = Transform.rotate(
                            angle: (map['rotation'] as num) * Math.pi / 180,
                            child: child,
                          );
                        }

                        // Opacity
                        if (map['opacity'] != null && map['opacity'] < 1.0) {
                          child = Opacity(
                            opacity: (map['opacity'] as num).toDouble(),
                            child: child,
                          );
                        }

                        // Animation
                        if (map['animation'] != null &&
                            map['animation'] is Map) {
                          child = AnimatedElement(
                            animation: Map<String, dynamic>.from(
                              map['animation'],
                            ),
                            child: child,
                          );
                        }

                        return Positioned(
                          left: (map['x'] ?? 0).toDouble(),
                          top: (map['y'] ?? 0).toDouble(),
                          child: child,
                        );
                      }).toList(),
                    ),
            ),
          ),
        );
      },
    );
  }
}

// Robust color parser
Color _parseColor(String? hex) {
  if (hex == null) return Colors.white;
  hex = hex.replaceAll('#', '');
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length == 8) {
    try {
      return Color(int.parse('0x$hex'));
    } catch (_) {}
  }
  return Colors.white;
}

// --- Custom Painters for Shapes ---

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PolygonPainter extends CustomPainter {
  final int sides;
  final Color color;
  _PolygonPainter({required this.sides, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    final angle = (2 * Math.pi) / sides;
    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < sides; i++) {
      final x = center.dx + radius * Math.cos(angle * i - Math.pi / 2);
      final y = center.dy + radius * Math.sin(angle * i - Math.pi / 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StarPainter extends CustomPainter {
  final Color color;
  _StarPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    final n = 5;
    final r = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < n * 2; i++) {
      final isEven = i % 2 == 0;
      final radius = isEven ? r : r / 2.5;
      final angle = (Math.pi / n) * i - Math.pi / 2;
      final x = center.dx + radius * Math.cos(angle);
      final y = center.dy + radius * Math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeartPainter extends CustomPainter {
  final Color color;
  _HeartPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(size.width / 2, size.height * 0.8);
    path.cubicTo(
      size.width * 1.2,
      size.height * 0.5,
      size.width * 0.8,
      size.height * 0.1,
      size.width / 2,
      size.height * 0.3,
    );
    path.cubicTo(
      size.width * 0.2,
      size.height * 0.1,
      -size.width * 0.2,
      size.height * 0.5,
      size.width / 2,
      size.height * 0.8,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TrapezoidPainter extends CustomPainter {
  final Color color;
  _TrapezoidPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width * 0.2, 0)
      ..lineTo(size.width * 0.8, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CrescentPainter extends CustomPainter {
  final Color color;
  _CrescentPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..addOval(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromLTWH(size.width * 0.2, 0, size.width, size.height));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CrossPainter extends CustomPainter {
  final Color color;
  _CrossPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    final thickness = w * 0.2;
    final path = Path()
      ..addRect(Rect.fromLTWH(w * 0.4, 0, thickness, h))
      ..addRect(Rect.fromLTWH(0, h * 0.4, w, thickness));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- Animation Widget ---

class AnimatedElement extends StatefulWidget {
  final Map<String, dynamic> animation;
  final Widget child;

  const AnimatedElement({
    required this.animation,
    required this.child,
    Key? key,
  }) : super(key: key);

  @override
  State<AnimatedElement> createState() => _AnimatedElementState();
}

class _AnimatedElementState extends State<AnimatedElement>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late String type;
  late double begin;
  late double end;
  late int duration;
  late int delay;

  @override
  void initState() {
    super.initState();
    type = widget.animation['type'] ?? 'fadeIn';
    begin = widget.animation['begin']?.toDouble() ?? 0.0;
    end = widget.animation['end']?.toDouble() ?? 1.0;
    duration = ((widget.animation['duration'] ?? 1.0) * 1000).toInt();
    delay = ((widget.animation['delay'] ?? 0.0) * 1000).toInt();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    );

    switch (type) {
      case 'fadeIn':
        _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
        break;
      case 'scale':
        _animation = Tween<double>(begin: begin, end: end).animate(_controller);
        break;
      default:
        _animation = Tween<double>(begin: begin, end: end).animate(_controller);
    }

    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case 'fadeIn':
        return FadeTransition(opacity: _animation, child: widget.child);
      case 'scale':
        return ScaleTransition(scale: _animation, child: widget.child);
      default:
        return widget.child;
    }
  }
}
