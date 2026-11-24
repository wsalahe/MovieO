import 'dart:convert';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'account.dart';

const catalogUrl =
    'https://raw.githubusercontent.com/wsalahe/MovieO/main/catalog.json';

void main() => runApp(const MovieOApp());

class MovieOApp extends StatelessWidget {
  const MovieOApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MovieO',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0B0B0F),
          colorScheme: const ColorScheme.dark(primary: Color(0xFFE50914)),
        ),
        home: const Gate(),
      );
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool? ok;
  @override
  void initState() {
    super.initState();
    Account.restore().then((v) => setState(() => ok = v));
  }

  @override
  Widget build(BuildContext context) {
    if (ok == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!ok!) {
      return AuthPage(onDone: () => setState(() => ok = true));
    }
    return HomePage(onSignedOut: () => setState(() => ok = false));
  }
}

class Episode {
  final int season, number;
  final String title, url;
  Episode(this.season, this.number, this.title, this.url);
}

class Item {
  final String id, title, type, poster, description, genre, videoUrl;
  final int year;
  final List<Episode> episodes;
  Item(this.id, this.title, this.type, this.poster, this.description,
      this.genre, this.videoUrl, this.year, this.episodes);
  factory Item.fromJson(Map<String, dynamic> j) => Item(
        '${j['id'] ?? j['title']}',
        '${j['title'] ?? ''}',
        '${j['type'] ?? 'movie'}',
        '${j['poster'] ?? ''}',
        '${j['description'] ?? ''}',
        '${j['genre'] ?? ''}',
        '${j['videoUrl'] ?? ''}',
        (j['year'] is num) ? (j['year'] as num).toInt() : 0,
        ((j['episodes'] ?? []) as List)
            .map((e) => Episode(
                (e['season'] is num) ? (e['season'] as num).toInt() : 1,
                (e['number'] is num) ? (e['number'] as num).toInt() : 1,
                '${e['title'] ?? ''}',
                '${e['videoUrl'] ?? ''}'))
            .toList(),
      );
}

Future<List<Item>> loadCatalog() async {
  final r = await http.get(Uri.parse(
      '$catalogUrl?t=${DateTime.now().millisecondsSinceEpoch}'));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  return ((j['titles'] ?? []) as List)
      .map((e) => Item.fromJson(e as Map<String, dynamic>))
      .toList();
}

class HomePage extends StatefulWidget {
  final VoidCallback onSignedOut;
  const HomePage({super.key, required this.onSignedOut});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Item>> _f = loadCatalog();
  String _q = '';
  String _t = 'all';

  Widget _poster(Item i) => i.poster.isEmpty
      ? Container(
          color: const Color(0xFF1C1C24),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          child: Text(i.title, textAlign: TextAlign.center))
      : Image.network(i.poster,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFF1C1C24),
              alignment: Alignment.center,
              child: Text(i.title, textAlign: TextAlign.center)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('MovieO',
            style: TextStyle(
                color: Color(0xFFE50914),
                fontWeight: FontWeight.w900,
                letterSpacing: 2)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _f = loadCatalog())),
          IconButton(
              icon: const Icon(Icons.account_circle),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          SettingsPage(onSignedOut: widget.onSignedOut)))),
        ],
      ),
      body: FutureBuilder<List<Item>>(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Could not load the catalog'),
              TextButton(
                  onPressed: () => setState(() => _f = loadCatalog()),
                  child: const Text('Retry'))
            ]));
          }
          final all = s.data!;
          final items = all
              .where((i) =>
                  (_t == 'all' || i.type == _t) &&
                  i.title.toLowerCase().contains(_q.toLowerCase()))
              .toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Search'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final t in const ['all', 'movie', 'series'])
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: ChoiceChip(
                    label: Text(t == 'all'
                        ? 'All'
                        : t == 'movie'
                            ? 'Movies'
                            : 'Series'),
                    selected: _t == t,
                    onSelected: (_) => setState(() => _t = t),
                  ),
                )
            ]),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Nothing here yet'))
                  : RefreshIndicator(
                      onRefresh: () async {
                        setState(() => _f = loadCatalog());
                        await _f;
                      },
                      child: GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.67,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8),
                        itemCount: items.length,
                        itemBuilder: (c, k) => GestureDetector(
                          onTap: () => Navigator.push(
                              c,
                              MaterialPageRoute(
                                  builder: (_) => DetailPage(items[k]))),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _poster(items[k])),
                        ),
                      ),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class DetailPage extends StatelessWidget {
  final Item item;
  const DetailPage(this.item, {super.key});

  void _play(BuildContext c, String url, String title) {
    Navigator.push(c,
        MaterialPageRoute(builder: (_) => PlayerPage(url: url, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    final eps = [...item.episodes]..sort((a, b) =>
        a.season != b.season ? a.season - b.season : a.number - b.number);
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        if (item.poster.isNotEmpty)
          SizedBox(
              height: 220,
              child: Image.network(item.poster,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox())),
        const SizedBox(height: 10),
        Text(
            [
              if (item.year > 0) '${item.year}',
              if (item.genre.isNotEmpty) item.genre
            ].join('  •  '),
            style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 8),
        Text(item.description),
        const SizedBox(height: 14),
        if (item.type == 'movie' && item.videoUrl.isNotEmpty)
          FilledButton.icon(
              onPressed: () => _play(context, item.videoUrl, item.title),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play')),
        for (final e in eps)
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(
                'S${e.season} E${e.number}${e.title.isEmpty ? '' : '  ${e.title}'}'),
            onTap: () => _play(context, e.url, '${item.title} S${e.season}E${e.number}'),
          ),
      ]),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final String url, title;
  const PlayerPage({super.key, required this.url, required this.title});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _v;
  ChewieController? _c;
  String? _err;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _init();
  }

  Future<void> _init() async {
    try {
      final v = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await v.initialize();
      _v = v;
      _c = ChewieController(
          videoPlayerController: v,
          autoPlay: Account.profile['autoplay'] != false,
          allowFullScreen: false);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _err = 'Could not play this video');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    _v?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
            child: _err != null
                ? Text(_err!)
                : _c == null
                    ? const CircularProgressIndicator()
                    : Chewie(controller: _c!)),
      );
}
