// lib/main.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
// import '../models/channel.dart';
// import 'screens/dashboard_screen.dart';
// import 'screens/channel_manager_screen.dart';

void main() {
  runApp(const FlussonicProApp());
}

class FlussonicProApp extends StatelessWidget {
  const FlussonicProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flussonic Pro',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const DashboardScreen(),
        '/channels': (context) => const ChannelManagerScreen(),
      },
    );
  }
}

// lib/models/channel.dart
// lib/models/channel.dart
class Channel {
  final String name;
  final String inputUrl;
  final String outputIp;
  final String outputPort;
  final int pid;
  final String? interface;

  Channel({
    required this.name,
    required this.inputUrl,
    required this.outputIp,
    required this.outputPort,
    required this.pid,
    this.interface,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'inputUrl': inputUrl,
    'outputIp': outputIp,
    'outputPort': outputPort,
    'pid': pid,
    'interface': interface,
  };

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    name: json['name'],
    inputUrl: json['inputUrl'],
    outputIp: json['outputIp'],
    outputPort: json['outputPort'],
    pid: json['pid'],
    interface: json['interface'],
  );
}
// lib/screens/dashboard_screen.dart

// lib/screens/dashboard_screen.dart

// lib/screens/dashboard_screen.dart

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<Channel> channels = [];
  final Map<String, Process> processes = {};
  final Map<String, String> bitrates = {};
  final TextEditingController searchController = TextEditingController();
  final Set<String> stoppedManually = {}; // Track manually stopped channels
  Timer? retryTimer;

  @override
  void initState() {
    super.initState();
    _loadChannels();
    retryTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _retryDownChannels(),
    );
  }

  Future<void> _loadChannels() async {
    final file = await _getChannelsFile();
    if (await file.exists()) {
      final jsonString = await file.readAsString();
      final List<dynamic> data = jsonDecode(jsonString);
      setState(() {
        channels.clear();
        channels.addAll(data.map((e) => Channel.fromJson(e)).toList());
      });
    }
  }

  Future<File> _getChannelsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/channels.json');
  }

  void _startStream(Channel channel) async {
    if (processes.containsKey(channel.name)) return;
    stoppedManually.remove(channel.name);

    final cmd = [
      '-re',
      '-i',
      channel.inputUrl,
      '-c:v',
      'libx264',
      '-b:v',
      '3000k',
      '-maxrate',
      '5000k',
      '-bufsize',
      '5000k',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-map',
      '0',
      '-streamid',
      '0:${channel.pid}',
      '-f',
      'mpegts',
      'udp://${channel.outputIp}:${channel.outputPort}?localaddr=${channel.interface}',
    ];

    try {
      final proc = await Process.start('/snap/bin/ffmpeg', cmd);
      processes[channel.name] = proc;

      proc.stderr.transform(utf8.decoder).listen((line) {
        if (line.contains('bitrate=')) {
          final reg = RegExp(r'bitrate=\s*(\d+\s*kb/s)');
          final match = reg.firstMatch(line);
          if (match != null) {
            setState(() {
              bitrates[channel.name] = match.group(1) ?? '';
            });
          }
        }
        if (line.contains('404') || line.contains('error')) {
          proc.kill();
          processes.remove(channel.name);
        }
      });

      proc.exitCode.then((_) => setState(() => processes.remove(channel.name)));
    } catch (e) {
      debugPrint('Error starting stream for ${channel.name}: $e');
    }
  }

  void _stopStream(Channel channel) {
    processes[channel.name]?.kill();
    processes.remove(channel.name);
    stoppedManually.add(channel.name);
    setState(() {});
  }

  void _restartStream(Channel channel) {
    _stopStream(channel);
    Future.delayed(const Duration(seconds: 1), () => _startStream(channel));
  }

  void _retryDownChannels() {
    for (final channel in channels) {
      if (!processes.containsKey(channel.name) &&
          !stoppedManually.contains(channel.name)) {
        _startStream(channel);
      }
    }
  }

  @override
  void dispose() {
    retryTimer?.cancel();
    for (final proc in processes.values) {
      proc.kill();
    }
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredChannels = channels
        .where(
          (ch) => ch.name.toLowerCase().contains(
            searchController.text.toLowerCase(),
          ),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📡 Flussonic Pro Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/channels'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search channels...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white10,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: filteredChannels.length,
          itemBuilder: (context, index) {
            final channel = filteredChannels[index];
            final running = processes.containsKey(channel.name);
            final statusColor = running ? Colors.green : Colors.red;
            final bitrate = bitrates[channel.name] ?? '--';

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey[850],
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(backgroundColor: statusColor, radius: 6),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          channel.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Input: ${channel.inputUrl}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Output: ${channel.outputIp}:${channel.outputPort}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Bitrate: $bitrate',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.lightBlueAccent,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restart_alt),
                        color: Colors.amber,
                        onPressed: () => _restartStream(channel),
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        color: Colors.greenAccent,
                        onPressed: () => _startStream(channel),
                      ),
                      IconButton(
                        icon: const Icon(Icons.stop),
                        color: Colors.redAccent,
                        onPressed: () => _stopStream(channel),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// lib/screens/channel_manager_screen.dart
// lib/screens/channel_manager_screen.dart

class ChannelManagerScreen extends StatefulWidget {
  const ChannelManagerScreen({super.key});

  @override
  State<ChannelManagerScreen> createState() => _ChannelManagerScreenState();
}

class _ChannelManagerScreenState extends State<ChannelManagerScreen> {
  final List<Channel> channels = [];
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final inputUrlController = TextEditingController();
  final outputIpController = TextEditingController();
  final outputPortController = TextEditingController();
  final pidController = TextEditingController();
  final localInterfaceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = await _getFile();
    if (await file.exists()) {
      final jsonList = jsonDecode(await file.readAsString());
      setState(() {
        channels.clear();
        channels.addAll(jsonList.map<Channel>((e) => Channel.fromJson(e)));
      });
    }
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/channels.json');
  }

  Future<void> _save() async {
    final file = await _getFile();
    final data = channels.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
  }

  void _addOrUpdateChannel([int? editIndex]) {
    if (formKey.currentState!.validate()) {
      final channel = Channel(
        name: nameController.text.trim(),
        inputUrl: inputUrlController.text.trim(),
        outputIp: outputIpController.text.trim(),
        outputPort: outputPortController.text.trim(),
        pid: int.parse(pidController.text.trim()),
        interface: localInterfaceController.text.trim(),
      );
      setState(() {
        if (editIndex != null) {
          channels[editIndex] = channel;
        } else {
          channels.add(channel);
        }
      });
      _save();
      _clearForm();
    }
  }

  void _clearForm() {
    nameController.clear();
    inputUrlController.clear();
    outputIpController.clear();
    outputPortController.clear();
    pidController.clear();
    localInterfaceController.clear();
  }

  void _deleteChannel(int index) {
    setState(() {
      channels.removeAt(index);
    });
    _save();
  }

  void _fillForm(Channel ch) {
    nameController.text = ch.name;
    inputUrlController.text = ch.inputUrl;
    outputIpController.text = ch.outputIp;
    outputPortController.text = ch.outputPort;
    pidController.text = ch.pid.toString();
    localInterfaceController.text = ch.interface ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🧾 Manage Channels')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add / Edit Channel',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Channel Name',
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: inputUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Input URL',
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: outputIpController,
                              decoration: const InputDecoration(
                                labelText: 'Output IP',
                              ),
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: outputPortController,
                              decoration: const InputDecoration(
                                labelText: 'Output Port',
                              ),
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: pidController,
                        decoration: const InputDecoration(labelText: 'PID'),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: localInterfaceController,
                        decoration: const InputDecoration(
                          labelText: 'Output Network Interface (e.g., eno2)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () => _addOrUpdateChannel(),
                            child: const Text('Save Channel'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _clearForm,
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const Text(
              '📺 Existing Channels',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final ch = channels[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(ch.name),
                      subtitle: Text(
                        '${ch.inputUrl}\n${ch.outputIp}:${ch.outputPort} | PID: ${ch.pid} | IF: ${ch.interface ?? '-'}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              _fillForm(ch);
                              _addOrUpdateChannel(index);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteChannel(index),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
} // import 'dart:async';
// import 'dart:convert';
// import 'dart:io';

// import 'package:flutter/material.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:tray_manager/tray_manager.dart';
// import 'package:window_manager/window_manager.dart';

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await windowManager.ensureInitialized();
//   runApp(MyApp());
// }

// class StreamProfile {
//   String inputUrl;
//   String outputIp;
//   String outputPort;

//   StreamProfile({
//     required this.inputUrl,
//     required this.outputIp,
//     required this.outputPort,
//   });

//   Map<String, dynamic> toJson() => {
//     'inputUrl': inputUrl,
//     'outputIp': outputIp,
//     'outputPort': outputPort,
//   };

//   static StreamProfile fromJson(Map<String, dynamic> json) {
//     return StreamProfile(
//       inputUrl: json['inputUrl'],
//       outputIp: json['outputIp'],
//       outputPort: json['outputPort'],
//     );
//   }
// }

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Stream UDP Forwarder',
//       theme: ThemeData.dark(),
//       home: StreamHomePage(),
//     );
//   }
// }

// class StreamHomePage extends StatefulWidget {
//   @override
//   _StreamHomePageState createState() => _StreamHomePageState();
// }

// class _StreamHomePageState extends State<StreamHomePage> with TrayListener {
//   final inputController = TextEditingController();
//   final outputIpController = TextEditingController();
//   final outputPortController = TextEditingController();

//   Process? ffmpegProcess;
//   List<String> logs = [];
//   bool isStreaming = false;
//   List<StreamProfile> savedProfiles = [];

//   @override
//   void initState() {
//     super.initState();
//     trayManager.addListener(this);
//     _loadProfiles();
//     _initTray();
//   }

//   Future<void> _initTray() async {
//     await trayManager.setIcon('assets/icon.png'); // Optional icon
//     await trayManager.setContextMenu(
//       Menu(
//         items: [
//           MenuItem(key: 'show', label: 'Show'),
//           MenuItem(key: 'quit', label: 'Quit'),
//         ],
//       ),
//     );
//   }

//   void _startStreaming() async {
//     String input = inputController.text.trim();
//     String ip = outputIpController.text.trim();
//     String port = outputPortController.text.trim();

//     if (input.isEmpty || ip.isEmpty || port.isEmpty) return;

//     List<String> cmd = [
//       '-re',
//       '-i',
//       input,
//       '-c',
//       'copy',
//       '-f',
//       'mpegts',
//       'udp://$ip:$port',
//     ];

//     setState(() {
//       logs.add('Starting FFmpeg...');
//     });

//     Process.start('ffmpeg', cmd);
//     isStreaming = true;
//     setState(() {});

//     ffmpegProcess!.stdout.transform(utf8.decoder).listen((event) {
//       setState(() {
//         logs.add(event);
//       });
//     });

//     ffmpegProcess!.stderr.transform(utf8.decoder).listen((event) {
//       setState(() {
//         logs.add(event);
//       });
//     });

//     ffmpegProcess!.exitCode.then((code) {
//       setState(() {
//         logs.add("FFmpeg exited with code: $code");
//         isStreaming = false;
//       });
//       // Auto-reconnect
//       Future.delayed(Duration(seconds: 5), () {
//         if (!isStreaming) _startStreaming();
//       });
//     });
//   }

//   void _stopStreaming() {
//     ffmpegProcess?.kill();
//     isStreaming = false;
//     setState(() {
//       logs.add("Stopped streaming.");
//     });
//   }

//   Future<void> _saveProfile() async {
//     final profile = StreamProfile(
//       inputUrl: inputController.text.trim(),
//       outputIp: outputIpController.text.trim(),
//       outputPort: outputPortController.text.trim(),
//     );
//     savedProfiles.add(profile);
//     await _writeProfilesToFile();
//     setState(() {
//       logs.add("Profile saved.");
//     });
//   }

//   Future<void> _loadProfiles() async {
//     final file = await _getProfileFile();
//     if (await file.exists()) {
//       final jsonString = await file.readAsString();
//       final List<dynamic> jsonList = jsonDecode(jsonString);
//       savedProfiles = jsonList.map((e) => StreamProfile.fromJson(e)).toList();
//       setState(() {});
//     }
//   }

//   Future<void> _writeProfilesToFile() async {
//     final file = await _getProfileFile();
//     final jsonString = jsonEncode(
//       savedProfiles.map((e) => e.toJson()).toList(),
//     );
//     await file.writeAsString(jsonString);
//   }

//   Future<File> _getProfileFile() async {
//     final dir = await getApplicationDocumentsDirectory();
//     return File('${dir.path}/stream_profiles.json');
//   }

//   @override
//   void dispose() {
//     trayManager.removeListener(this);
//     ffmpegProcess?.kill();
//     super.dispose();
//   }

//   @override
//   void onTrayIconMouseDown() async {
//     await windowManager.show();
//     await windowManager.focus();
//   }

//   @override
//   void onTrayMenuItemClick(MenuItem item) {
//     if (item.key == 'quit') {
//       _stopStreaming();
//       exit(0);
//     } else if (item.key == 'show') {
//       windowManager.show();
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text('HLS/TS to UDP Forwarder')),
//       body: Padding(
//         padding: EdgeInsets.all(16),
//         child: Column(
//           children: [
//             TextField(
//               controller: inputController,
//               decoration: InputDecoration(labelText: 'Input URL'),
//             ),
//             Row(
//               children: [
//                 Expanded(
//                   child: TextField(
//                     controller: outputIpController,
//                     decoration: InputDecoration(labelText: 'Output IP'),
//                   ),
//                 ),
//                 SizedBox(width: 10),
//                 Expanded(
//                   child: TextField(
//                     controller: outputPortController,
//                     decoration: InputDecoration(labelText: 'Output Port'),
//                   ),
//                 ),
//               ],
//             ),
//             Row(
//               children: [
//                 ElevatedButton(
//                   onPressed: isStreaming ? null : _startStreaming,
//                   child: Text('Start'),
//                 ),
//                 SizedBox(width: 10),
//                 ElevatedButton(
//                   onPressed: isStreaming ? _stopStreaming : null,
//                   child: Text('Stop'),
//                 ),
//                 SizedBox(width: 10),
//                 ElevatedButton(
//                   onPressed: _saveProfile,
//                   child: Text('Save Profile'),
//                 ),
//               ],
//             ),
//             Divider(),
//             Text(
//               'Saved Profiles',
//               style: TextStyle(fontWeight: FontWeight.bold),
//             ),
//             SizedBox(
//               height: 120,
//               child: ListView.builder(
//                 itemCount: savedProfiles.length,
//                 itemBuilder: (context, index) {
//                   final p = savedProfiles[index];
//                   return ListTile(
//                     title: Text(p.inputUrl),
//                     subtitle: Text('UDP: ${p.outputIp}:${p.outputPort}'),
//                     onTap: () {
//                       inputController.text = p.inputUrl;
//                       outputIpController.text = p.outputIp;
//                       outputPortController.text = p.outputPort;
//                     },
//                   );
//                 },
//               ),
//             ),
//             Divider(),
//             Text('Logs', style: TextStyle(fontWeight: FontWeight.bold)),
//             Expanded(
//               child: ListView(
//                 children: logs
//                     .map((log) => Text(log, style: TextStyle(fontSize: 12)))
//                     .toList(),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
