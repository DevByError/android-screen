import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:io' show Platform;

// --- CONFIGURATION ---
final String SERVER_URL = Platform.isAndroid
    ? 'http://10.0.2.2:5000'
    : 'http://localhost:5000';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    runApp(const MyApp());
  });
}

// ============================================================================
// 🧱 SOCKET MANAGER (SINGLETON) - KEEPS CONNECTION ALIVE
// ============================================================================
class SocketManager {
  static final SocketManager _instance = SocketManager._internal();
  factory SocketManager() => _instance;
  SocketManager._internal();

  IO.Socket? _socket;

  // Initialize and Connect
  void init(String url) {
    if (_socket != null && _socket!.connected) return;

    _socket = IO.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
    });
    _socket!.connect();
  }

  IO.Socket get socket {
    if (_socket == null) init(SERVER_URL);
    return _socket!;
  }

  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFF6B21A8),
      ),
      home: const ScreenSetupGate(),
    );
  }
}

// ============================================================================
// 1. SETUP SCREEN (Connects & Verifies)
// ============================================================================
class ScreenSetupGate extends StatefulWidget {
  const ScreenSetupGate({super.key});
  @override
  State<ScreenSetupGate> createState() => _ScreenSetupGateState();
}

class _ScreenSetupGateState extends State<ScreenSetupGate> {
  final TextEditingController _idController = TextEditingController();
  bool _isChecking = false;
  String _statusMessage = "";

  void _handleLink() {
    String inputId = _idController.text.trim();
    if (inputId.isEmpty) {
      _setStatus("Please enter a Screen ID.", isError: true);
      return;
    }

    setState(() {
      _isChecking = true;
      _setStatus("Connecting to server...");
    });

    // 1. Init Global Socket
    final manager = SocketManager();
    manager.init(SERVER_URL);
    final socket = manager.socket;

    // 2. Setup Listeners (One-time)
    socket.clearListeners(); // Clear old listeners to avoid duplicates

    socket.onConnect((_) {
      _setStatus("Verifying ID...");
      socket.emit('register_screen', {'screenUUID': inputId});
    });

    socket.on('registration_success', (data) {
      _setStatus("Success! Launching Player...");

      // ✅ NAVIGATE (Keep Socket Alive)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SmartPlayerEngine(
              screenUUID: data['screenId'], // Use Real UUID from Server
              screenName: data['name'],
            ),
          ),
        );
      });
    });

    socket.on('registration_failed', (data) {
      _setStatus("Error: ${data['msg']}", isError: true);
      setState(() => _isChecking = false);
    });

    // Handle timeout/connection error
    socket.onConnectError((data) {
      _setStatus("Connection Error. Check Server.", isError: true);
      setState(() => _isChecking = false);
    });

    // If already connected, emit immediately
    if (socket.connected) {
      socket.emit('register_screen', {'screenUUID': inputId});
    }
  }

  void _setStatus(String msg, {bool isError = false}) {
    if (!mounted) return;
    setState(() => _statusMessage = msg);
    if (isError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
            ),
            child: Column(
              children: [
                const Icon(Icons.monitor, size: 80, color: Color(0xFF6B21A8)),
                const SizedBox(height: 20),
                const Text(
                  "SignCraft Player",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _idController,
                  enabled: !_isChecking,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: "Screen ID",
                    hintText: "e.g. captain",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(
                      Icons.qr_code,
                      color: Color(0xFF6B21A8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _isChecking ? Colors.blue : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _handleLink,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B21A8),
                      foregroundColor: Colors.white,
                    ),
                    child: _isChecking
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "CONNECT DEVICE",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
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
// 2. PLAYER ENGINE (Uses Global Socket)
// ============================================================================
class SmartPlayerEngine extends StatefulWidget {
  final String screenUUID;
  final String screenName;

  const SmartPlayerEngine({
    super.key,
    required this.screenUUID,
    required this.screenName,
  });

  @override
  State<SmartPlayerEngine> createState() => _SmartPlayerEngineState();
}
// ... imports remain the same

class _SmartPlayerEngineState extends State<SmartPlayerEngine> {
  final socket = SocketManager().socket;
  bool _isConnected = true;
  Map<String, dynamic>? _activeSchedule;
  String _videoUrl = ""; // Only track ONE video URL now
  String _playlistName = "";
  VideoPlayerController? _videoController;
  bool _isActivePlaying = false;
  Timer? _scheduleTicker;

  @override
  void initState() {
    super.initState();
    _setupSocketListeners();
    _scheduleTicker = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _checkScheduleLogic(),
    );
  }

  void _setupSocketListeners() {
    socket.onConnect((_) {
      setState(() => _isConnected = true);
      socket.emit('register_screen', {'screenUUID': widget.screenUUID});
    });

    socket.onDisconnect((_) {
      if (mounted) setState(() => _isConnected = false);
    });

    // LISTEN FOR UPDATED VIDEO CONTENT
    socket.on('update_schedule', (data) {
      print("📥 VIDEO CONTENT RECEIVED: ${data['videoUrl']}");
      if (mounted) {
        setState(() {
          _activeSchedule = data['schedule'];
          _videoUrl = data['videoUrl'];
          _playlistName = data['playlistName'] ?? "Unknown";
          _resetPlayer();
        });
        _checkScheduleLogic();
      }
    });
  }

  void _resetPlayer() {
    _videoController?.dispose();
    _videoController = null;
    _isActivePlaying = false;
  }

  void _checkScheduleLogic() {
    if (_videoUrl.isEmpty || _activeSchedule == null) return;

    final bool isImmediate = _activeSchedule!['isImmediate'] == true;
    final DateTime start = DateTime.parse(_activeSchedule!['start']);
    final DateTime end = DateTime.parse(_activeSchedule!['end']);
    final DateTime now = DateTime.now();

    bool shouldPlay = isImmediate
        ? now.isBefore(end)
        : (now.isAfter(start) && now.isBefore(end));

    if (shouldPlay && !_isActivePlaying) {
      _startVideoPlayback();
    } else if (!shouldPlay && _isActivePlaying) {
      _stopPlayback();
    }
  }

  void _stopPlayback() {
    if (mounted) setState(() => _isActivePlaying = false);
    _videoController?.pause();
  }

  Future<void> _startVideoPlayback() async {
    if (_videoUrl.isEmpty) return;

    final newController = VideoPlayerController.networkUrl(
      Uri.parse(_videoUrl),
    );

    try {
      await newController.initialize();
      newController.setLooping(true); // Loop the entire playlist video

      if (mounted) {
        setState(() {
          _videoController?.dispose();
          _videoController = newController;
          _isActivePlaying = true;
        });
        await _videoController!.play();
      }
    } catch (e) {
      print("Playback Error: $e");
      // Retry in 5 seconds
      Future.delayed(const Duration(seconds: 5), () => _startVideoPlayback());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 📺 FULL SCREEN VIDEO PLAYER
          if (_isActivePlaying &&
              _videoController != null &&
              _videoController!.value.isInitialized)
            SizedBox.expand(
              // Fill entire screen
              child: FittedBox(
                fit: BoxFit.fill, // Stretch to cover screen without bars
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          else
            _buildStandbyScreen(),

          // Overlay ID and Connectivity
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: _isConnected ? Colors.green : Colors.red,
                    size: 10,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "ID: ${widget.screenUUID.substring(0, 6)}",
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Standby screen UI remains mostly the same...
  Widget _buildStandbyScreen() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.monitor, size: 80, color: Colors.white10),
          const SizedBox(height: 20),
          const Text(
            "SignCraft",
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w200,
            ),
          ),
          Text(
            _isConnected ? "Ready to Play" : "Connecting...",
            style: const TextStyle(color: Colors.white38),
          ),
          if (_videoUrl.isNotEmpty)
            Text(
              "Next: $_playlistName",
              style: const TextStyle(color: Colors.blueAccent),
            ),
        ],
      ),
    );
  }
}
