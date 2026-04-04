import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: SpikeScreen(),
    );
  }
}

class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  String _sdkVersion = 'Not fetched yet';

  Future<void> _fetchVersion() async {
    try {
      final version = await const MethodChannel('neiry_kit/device_locator')
          .invokeMethod<String>('getVersionString');
      setState(() => _sdkVersion = version ?? '(null)');
    } on PlatformException catch (e) {
      setState(() => _sdkVersion = 'Error: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('neiry_kit — SDK Spike')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('SDK version: $_sdkVersion'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchVersion,
              child: const Text('Get Version String'),
            ),
          ],
        ),
      ),
    );
  }
}
