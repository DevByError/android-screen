import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:io' show Platform;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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

    // Parse playlist JSON
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

    double designW = (_currentMetadata?['canvasWidth'] ?? 1280).toDouble();
    double designH = (_currentMetadata?['canvasHeight'] ?? 720).toDouble();
    Color bg = Colors.white;
    if (_currentMetadata?['canvasColor'] != null) {
      try {
        bg = Color(
          int.parse(_currentMetadata!['canvasColor'].replaceFirst('#', '0xff')),
        );
      } catch (_) {}
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        double screenW = constraints.maxWidth;
        double screenH = constraints.maxHeight;
        double scale = (screenW / designW).clamp(0.0, screenH / designH);
        if (designW / designH > screenW / screenH) {
          scale = screenW / designW;
        } else {
          scale = screenH / designH;
        }
        return Container(
          color: bg,
          alignment: Alignment.center,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: designW,
              height: designH,
              child: Stack(
                children: (_currentDesign?['elements'] as List).map<Widget>((
                  e,
                ) {
                  final type = (e['type'] ?? '').toString().toLowerCase();
                  switch (type) {
                    case 'rect':
                    case 'rectangle':
                      return Positioned(
                        left: (e['x'] ?? 0).toDouble(),
                        top: (e['y'] ?? 0).toDouble(),
                        child: Container(
                          width: (e['width'] ?? 100).toDouble(),
                          height: (e['height'] ?? 100).toDouble(),
                          color: e['fillColor'] != null
                              ? Color(
                                  int.parse(
                                    e['fillColor'].replaceFirst('#', '0xff'),
                                  ),
                                )
                              : Colors.white,
                        ),
                      );
                    case 'diamond':
                      return Positioned(
                        left: (e['x'] ?? 0).toDouble(),
                        top: (e['y'] ?? 0).toDouble(),
                        child: Transform.rotate(
                          angle: 0.785398, // 45 degrees in radians
                          child: Container(
                            width: (e['width'] ?? 100).toDouble(),
                            height: (e['height'] ?? 100).toDouble(),
                            color: e['fillColor'] != null
                                ? Color(
                                    int.parse(
                                      e['fillColor'].replaceFirst('#', '0xff'),
                                    ),
                                  )
                                : Colors.white,
                          ),
                        ),
                      );
                    case 'triangle':
                      return Positioned(
                        left: (e['x'] ?? 0).toDouble(),
                        top: (e['y'] ?? 0).toDouble(),
                        child: CustomPaint(
                          size: Size(
                            (e['width'] ?? 100).toDouble(),
                            (e['height'] ?? 100).toDouble(),
                          ),
                          painter: _TrianglePainter(
                            color: e['fillColor'] != null
                                ? Color(
                                    int.parse(
                                      e['fillColor'].replaceFirst('#', '0xff'),
                                    ),
                                  )
                                : Colors.white,
                          ),
                        ),
                      );
                    // Add more cases for other shapes
                    default:
                      return const SizedBox.shrink();
                  }
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

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
