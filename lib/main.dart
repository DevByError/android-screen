import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';

// Backend address. Pass --dart-define=SERVER_URL=http://<host>:5000 for a
// real device. The defaults work for the Android emulator and desktop.
const String _serverUrlOverride = String.fromEnvironment('SERVER_URL');
final String serverUrl = _serverUrlOverride.isNotEmpty
    ? _serverUrlOverride
    : (Platform.isAndroid ? 'http://10.0.2.2:5000' : 'http://localhost:5000');

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

// Single Socket.IO connection shared by the whole app.
class SocketManager {
  static final SocketManager _instance = SocketManager._internal();
  factory SocketManager() => _instance;
  SocketManager._internal();
  io.Socket? _socket;

  void init(String url) {
    if (_socket != null && _socket!.connected) return;
    _socket = io.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
    });
    _socket!.connect();
  }

  io.Socket get socket {
    if (_socket == null) init(serverUrl);
    return _socket!;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const ScreenSetupGate(),
    );
  }
}

// Asks for the screen ID and registers the device with the backend.
class ScreenSetupGate extends StatefulWidget {
  const ScreenSetupGate({super.key});
  @override
  State<ScreenSetupGate> createState() => _ScreenSetupGateState();
}

class _ScreenSetupGateState extends State<ScreenSetupGate> {
  final TextEditingController _idController = TextEditingController();
  bool _isChecking = false;

  void _handleLink() {
    String inputId = _idController.text.trim();
    if (inputId.isEmpty) return;

    setState(() => _isChecking = true);
    final manager = SocketManager();
    manager.init(serverUrl);
    final socket = manager.socket;

    socket.onConnect(
      (_) => socket.emit('register_screen', {'screenUUID': inputId}),
    );

    socket.on('registration_success', (data) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SmartPlayerEngine(
            screenUUID: data['screenId'],
            screenName: data['name'],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monitor, size: 60, color: Colors.deepPurple),
              const SizedBox(height: 20),
              TextField(
                controller: _idController,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  labelText: "Enter Screen ID",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isChecking ? null : _handleLink,
                child: Text(_isChecking ? "Connecting..." : "CONNECT"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Plays the scheduled content for one registered screen.
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

class _SmartPlayerEngineState extends State<SmartPlayerEngine> {
  final socket = SocketManager().socket;

  List<dynamic> _schedules = [];
  VideoPlayerController? _controller;
  String? _currentlyPlayingId;
  bool _isConnected = true;
  Timer? _timelineTimer;

  @override
  void initState() {
    super.initState();
    _setupSocket();
    _fetchScheduleFromServer(); // Initial sync

    // Check every 5 seconds if we need to switch content
    _timelineTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _evaluateTimeline();
    });
  }

  void _setupSocket() {
    socket.onConnect((_) => setState(() => _isConnected = true));
    socket.onDisconnect((_) => setState(() => _isConnected = false));

    // When backend says "refresh_content", we pull the new schedule
    socket.on('refresh_content', (_) {
      debugPrint("Nudge received from server. Refreshing...");
      _fetchScheduleFromServer();
    });
  }

  // A. GET INFORMATION FROM SERVER
  Future<void> _fetchScheduleFromServer() async {
    try {
      final response = await http.get(
        Uri.parse(
          '$serverUrl/design/getscreencontent?screenId=${widget.screenUUID}',
        ),
      );
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        setState(() {
          _schedules = result['data'];
        });
        _downloadAllVideos(); // Start storage process
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
  }

  // B. STORE VIDEO LOCALLY
  Future<void> _downloadAllVideos() async {
    final directory = await getApplicationDocumentsDirectory();
    Dio dio = Dio();

    for (var schedule in _schedules) {
      String url = schedule['videoUrl'];
      String fileName = url.split('/').last;
      String localPath = "${directory.path}/$fileName";

      if (!File(localPath).existsSync()) {
        debugPrint("Downloading: $fileName");
        try {
          await dio.download(url, localPath);
          debugPrint("Downloaded: $fileName");
        } catch (e) {
          debugPrint("Download Failed: $e");
        }
      }
    }
    _evaluateTimeline(); // Check if we can play something now
  }

  // C. TIMELINE LOGIC (Gapless + Timing)
  void _evaluateTimeline() async {
    final now = DateTime.now();
    Map<String, dynamic>? activeSchedule;

    for (var schedule in _schedules) {
      final start = DateTime.parse(schedule['startTime']);
      final end = DateTime.parse(schedule['endTime']);

      if (now.isAfter(start) && now.isBefore(end)) {
        activeSchedule = schedule;
        break;
      }
    }

    if (activeSchedule != null) {
      if (_currentlyPlayingId != activeSchedule['id']) {
        _playLocalVideo(activeSchedule);
      }
    } else {
      // Nothing scheduled for now
      if (_controller != null) {
        setState(() {
          _controller?.dispose();
          _controller = null;
          _currentlyPlayingId = null;
        });
      }
    }
  }

  double _intendedWidth = 1920;
  double _intendedHeight = 1080;

  Future<void> _playLocalVideo(Map<String, dynamic> schedule) async {
    final directory = await getApplicationDocumentsDirectory();
    String fileName = schedule['videoUrl'].split('/').last;
    File file = File("${directory.path}/$fileName");

    if (!file.existsSync()) return;

    final newController = VideoPlayerController.file(file);
    try {
      await newController.initialize();
      newController.setLooping(true);

      if (mounted) {
        setState(() {
          _controller?.dispose();
          _controller = newController;
          _currentlyPlayingId = schedule['id'];
          // STORE THE SIZES FROM THE SERVER
          _intendedWidth = (schedule['width'] ?? 1920).toDouble();
          _intendedHeight = (schedule['height'] ?? 1080).toDouble();
        });
        _controller!.play();
      }
    } catch (e) {
      debugPrint("Playback error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.fill, // This stretches to fill the screen
                child: SizedBox(
                  // USE THE INTENDED CANVAS SIZE FROM THE SERVER
                  width: _intendedWidth,
                  height: _intendedHeight,
                  child: VideoPlayer(_controller!),
                ),
              ),
            )
          else
            _buildStandbyScreen(),

          // --- Connectivity Indicator (Bottom Right) ---
          Positioned(
            bottom: 20,
            right: 20,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green : Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _isConnected
                        ? Colors.green.withValues(alpha: 0.5)
                        : Colors.red.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandbyScreen() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white24),
          const SizedBox(height: 20),
          Text(
            widget.screenName,
            style: const TextStyle(color: Colors.white38, fontSize: 24),
          ),
          const Text(
            "Waiting for scheduled content...",
            style: TextStyle(color: Colors.white10),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timelineTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}
