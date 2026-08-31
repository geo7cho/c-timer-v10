import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';

import '../models/recording_item.dart';
import '../services/recorder_service.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<RecordingItem> _items = [];
  String _folderPath = '';
  bool _loading = true;
  final AudioPlayer _player = AudioPlayer();
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dir = await RecorderService.recordingsDirectory();
    _folderPath = dir.path;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.mp3'))
        .toList();

    final items = await Future.wait(files.map(RecordingItem.fromFile));
    // 요구사항: 최근 녹음 파일이 제일 위로 오도록 최신순 정렬
    items.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));

    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _togglePlay(RecordingItem item) async {
    if (_playingPath == item.file.path) {
      await _player.stop();
      setState(() => _playingPath = null);
    } else {
      await _player.play(DeviceFileSource(item.file.path));
      setState(() => _playingPath = item.file.path);
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playingPath = null);
      });
    }
  }

  Future<void> _delete(RecordingItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: Text('${item.fileName} 파일을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await item.file.delete();
      _load();
    }
  }

  Future<void> _share(RecordingItem item) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(item.file.path)], text: item.fileName),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('저장된 녹음'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _folderPath,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('저장된 녹음이 없습니다'))
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final isPlaying = _playingPath == item.file.path;
                          return ListTile(
                            leading: IconButton(
                              icon: Icon(isPlaying
                                  ? Icons.stop_circle
                                  : Icons.play_circle),
                              onPressed: () => _togglePlay(item),
                            ),
                            title: Text(item.fileName),
                            subtitle: Text(
                              '${DateFormat('yyyy-MM-dd HH:mm').format(item.modifiedAt)} · ${item.sizeLabel}',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'share') _share(item);
                                if (v == 'delete') _delete(item);
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(value: 'share', child: Text('공유')),
                                PopupMenuItem(value: 'delete', child: Text('삭제')),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
