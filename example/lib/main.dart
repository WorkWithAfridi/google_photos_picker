import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_photos_picker/google_photos_picker.dart';

const String _clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const String _serverClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GooglePhotosPicker.instance.initialize(
    clientId: (Platform.isIOS || Platform.isMacOS) && _clientId.isNotEmpty
        ? _clientId
        : null,
    serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Google Photos Picker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> _files = const <File>[];
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Photos Picker'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sign out',
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(
            'Select from Google Photos',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Google’s hosted picker opens outside this app. Your explicit '
            'selection is then downloaded to temporary storage.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : () => _pick(single: true),
            icon: const Icon(Icons.photo_outlined),
            label: const Text('Pick one item'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pick(single: false),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Pick up to 10 items'),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_message case final String message) ...<Widget>[
            const SizedBox(height: 24),
            Text(message),
          ],
          if (_files.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text(
              'Downloaded media',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final File file in _files)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.download_done),
                  title: Text(file.uri.pathSegments.last),
                  subtitle: Text(file.path),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _pick({required bool single}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final List<File>? files;
      if (single) {
        final File? file = await GooglePhotosPicker.instance.pickFile(
          context: context,
        );
        files = file == null ? null : <File>[file];
      } else {
        files = await GooglePhotosPicker.instance.pickFiles(
          context: context,
          maxItems: 10,
        );
      }
      if (!mounted) return;
      setState(() {
        _files = files ?? const <File>[];
        _message = files == null || files.isEmpty
            ? 'No media was selected.'
            : '${files.length} item${files.length == 1 ? '' : 's'} downloaded.';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = 'Picker failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await GooglePhotosPicker.instance.signOut();
      if (mounted) {
        setState(() {
          _files = const <File>[];
          _message = 'Signed out.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
