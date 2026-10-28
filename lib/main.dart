import 'dart:async';
import 'dart:convert';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const CinemaApp());

// O'zingizning TMDB kalitingizni themoviedb.org dan olib shu yerga qo'ying.
const tmdbKey = '1c8c6544bd1c3dcc994c8219e1220561';

// ───────────────────────── RANGLAR ─────────────────────────
const kBg = Color(0xFF0B0B10);
const kCard = Color(0xFF16161F);
const kCard2 = Color(0xFF1A1A24);
const kAccent = Color(0xFF7F5AF0);
const kPink = Color(0xFFFF4D8D);
const kGrad = LinearGradient(colors: [kAccent, kPink]);

// ───────────────────────── SOZLAMALAR ─────────────────────────
class Lang {
  final String code, name, tmdb;
  final List<String> ia; // Internet Archive'dagi til nomlari
  const Lang(this.code, this.name, this.tmdb, this.ia);
}

const langs = <Lang>[
  Lang('', '🌍 Hamma tillar', 'en-US', []),
  Lang('uz', "O'zbekcha", 'uz-UZ', ['Uzbek', 'uzb']),
  Lang('ru', 'Русский', 'ru-RU', ['Russian', 'rus']),
  Lang('en', 'English', 'en-US', ['English', 'eng']),
  Lang('tr', 'Türkçe', 'tr-TR', ['Turkish', 'tur']),
  Lang('ko', '한국어', 'ko-KR', ['Korean', 'kor']),
  Lang('hi', 'हिन्दी', 'hi-IN', ['Hindi', 'hin']),
  Lang('es', 'Español', 'es-ES', ['Spanish', 'spa']),
  Lang('fr', 'Français', 'fr-FR', ['French', 'fre', 'fra']),
  Lang('de', 'Deutsch', 'de-DE', ['German', 'ger', 'deu']),
  Lang('it', 'Italiano', 'it-IT', ['Italian', 'ita']),
  Lang('ja', '日本語', 'ja-JP', ['Japanese', 'jpn']),
  Lang('zh', '中文', 'zh-CN', ['Chinese', 'chi', 'zho']),
  Lang('ar', 'العربية', 'ar-SA', ['Arabic', 'ara']),
  Lang('fa', 'فارسی', 'fa-IR', ['Persian', 'per', 'fas']),
  Lang('pt', 'Português', 'pt-BR', ['Portuguese', 'por']),
];

const regions = <String, String>{
  'US': 'AQSh', 'GB': 'Buyuk Britaniya', 'CA': 'Kanada', 'AU': 'Avstraliya',
  'UZ': "O'zbekiston", 'RU': 'Rossiya', 'TR': 'Turkiya', 'IN': 'Hindiston',
  'DE': 'Germaniya', 'FR': 'Fransiya', 'ES': 'Ispaniya', 'BR': 'Braziliya',
  'KR': 'Koreya', 'JP': 'Yaponiya',
};

const kinds = <String, String>{
  'free': '🆓 Bepul',
  'archive': '🏛 Arxiv',
  'popular': '🔥 Mashhur',
  'cartoons': '🎨 Multfilmlar',
};

const genres = <int, String>{
  28: 'Jangari', 35: 'Komediya', 18: 'Drama', 27: "Qo'rqinchli",
  10749: 'Romantika', 878: 'Fantastika', 10751: 'Oilaviy', 12: 'Sarguzasht',
  53: 'Triller', 99: 'Hujjatli', 36: 'Tarixiy', 10402: 'Musiqiy',
};

class Cfg extends ChangeNotifier {
  Lang lang = langs[0];
  String region = 'US';
  void setLang(Lang l) { lang = l; notifyListeners(); }
  void setRegion(String r) { region = r; notifyListeners(); }
}
final cfg = Cfg();

// ───────────────────────── MODEL ─────────────────────────
class Film {
  final String id, title, year, desc;
  final String? poster, backdrop;
  final double? rating;
  final int? tmdbId;
  final String? iaId;
  const Film({required this.id, required this.title, this.year = '', this.desc = '',
    this.poster, this.backdrop, this.rating, this.tmdbId, this.iaId});

  String get sub => [
    if (year.isNotEmpty) year,
    if (rating != null && rating! > 0) '⭐ ${rating!.toStringAsFixed(1)}',
    if (iaId != null) 'Bepul',
  ].join('  •  ');

  factory Film.tmdb(Map j) {
    final date = (j['release_date'] ?? '').toString();
    final p = j['poster_path'];
    final b = j['backdrop_path'];
    return Film(
      id: '${j['id']}', tmdbId: j['id'] as int,
      title: (j['title'] ?? '').toString(),
      year: date.isEmpty ? '' : date.split('-').first,
      desc: (j['overview'] ?? '').toString(),
      rating: ((j['vote_average'] ?? 0) as num).toDouble(),
      poster: p == null ? null : 'https://image.tmdb.org/t/p/w342$p',
      backdrop: b == null ? null : 'https://image.tmdb.org/t/p/w780$b',
    );
  }
}

// ───────────────────────── TMDB ─────────────────────────
class Tmdb {
  static const host = 'api.themoviedb.org';

  static Future<Map<String, dynamic>> get(String path, Map<String, String> q) async {
    final r = await http.get(Uri.https(host, '/3$path', {'api_key': tmdbKey, ...q}));
    if (r.statusCode != 200) throw Exception('TMDB ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<List<Film>> list(String kind, int page, String q, int? genre) async {
    final l = cfg.lang;
    final p = <String, String>{
      'language': l.tmdb, 'page': '$page', 'include_adult': 'false',
    };
    String path;
    if (q.trim().isNotEmpty) {
      path = '/search/movie';
      p['query'] = q.trim();
    } else {
      path = '/discover/movie';
      p['sort_by'] = 'popularity.desc';
      p['vote_count.gte'] = '5';
      if (l.code.isNotEmpty) p['with_original_language'] = l.code;
      if (kind == 'cartoons') {
        p['with_genres'] = genre == null ? '16' : '16,$genre';
      } else if (genre != null) {
        p['with_genres'] = '$genre';
      }
      if (kind == 'free') {
        p['watch_region'] = cfg.region;
        p['with_watch_monetization_types'] = 'free|ads';
      }
    }
    final d = await get(path, p);
    return (d['results'] as List).map((e) => Film.tmdb(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> detail(int id) {
    final l = cfg.lang;
    return get('/movie/$id', {
      'language': l.tmdb,
      'append_to_response': 'videos,watch/providers',
      'include_video_language': l.code.isEmpty ? 'en,null' : '${l.code},en,null',
    });
  }

  static String? pickTrailer(List vids, String lc) {
    final yt = vids.where((v) => v['site'] == 'YouTube').toList();
    if (yt.isEmpty) return null;
    int score(dynamic v) =>
        (v['type'] == 'Trailer' ? 4 : v['type'] == 'Teaser' ? 2 : 0) +
            (v['iso_639_1'] == lc ? 2 : 0) + (v['official'] == true ? 1 : 0);
    yt.sort((a, b) => score(b).compareTo(score(a)));
    return yt.first['key'] as String?;
  }
}

// ───────────────────────── INTERNET ARCHIVE (public domain) ─────────────────────────
class Archive {
  static const host = 'archive.org';
  static const fullMinSeconds = 2400.0; // 40 daqiqa

  static String s(dynamic v) =>
      v is List ? (v.isEmpty ? '' : v.first.toString()) : (v?.toString() ?? '');

  static double parseLen(dynamic v) {
    final t = s(v).trim();
    if (t.isEmpty) return 0.0;
    if (t.contains(':')) {
      var sec = 0.0;
      for (final p in t.split(':')) { sec = sec * 60 + (double.tryParse(p) ?? 0.0); }
      return sec;
    }
    return double.tryParse(t) ?? 0.0;
  }

  static bool isBad(String title) =>
      RegExp(r'\b(trailer|trailers|teaser|clip|clips|promo|sample)\b', caseSensitive: false)
          .hasMatch(title);

  static String clean(String t) =>
      t.replaceAll(RegExp(r'[^\w\s]', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static Future<List<Film>> load(int page, Lang lang, String q) async {
    var query = '(collection:feature_films OR collection:animationandcartoons) AND mediatype:movies';
    if (lang.ia.isNotEmpty) query += ' AND language:(${lang.ia.join(' OR ')})';
    final c = clean(q);
    if (c.isNotEmpty) query += ' AND title:($c)';
    final uri = Uri.https(host, '/advancedsearch.php', {
      'q': query,
      'fl[]': ['identifier', 'title', 'year', 'description'],
      'sort[]': 'downloads desc',
      'rows': '24',
      'page': '$page',
      'output': 'json',
    });
    final r = await http.get(uri);
    if (r.statusCode != 200) throw Exception('Archive ${r.statusCode}');
    final docs = jsonDecode(r.body)['response']['docs'] as List;
    return docs.where((d) => !isBad(s(d['title']))).map<Film>((d) {
      final id = s(d['identifier']);
      return Film(
        id: id, iaId: id, title: s(d['title']), year: s(d['year']),
        desc: s(d['description']).replaceAll(RegExp(r'<[^>]*>'), ' ').trim(),
        poster: 'https://archive.org/services/img/$id',
      );
    }).toList();
  }

  // Itemdagi eng uzun video faylni tanlaydi: (url, davomiylik soniyada)
  static Future<(String, double)?> bestStream(String id) async {
    final r = await http.get(Uri.https(host, '/metadata/$id'));
    if (r.statusCode != 200) return null;
    final files = (jsonDecode(r.body)['files'] as List?) ?? [];
    String? bestName;
    double bestLen = -1.0;
    int bestSize = -1;
    for (final f in files) {
      final m = f as Map;
      final name = (m['name'] ?? '').toString();
      final n = name.toLowerCase();
      if (!(n.endsWith('.mp4') || n.endsWith('.m4v'))) continue;
      if (n.contains('_thumb') || n.contains('trailer') || n.contains('sample')) continue;
      final len = parseLen(m['length']);
      final size = int.tryParse(s(m['size'])) ?? 0;
      if (len > bestLen || (len == bestLen && size > bestSize)) {
        bestName = name; bestLen = len; bestSize = size;
      }
    }
    if (bestName == null) return null;
    final url = 'https://$host/download/$id/${Uri.encodeFull(bestName)}';
    final double len = bestLen < 0 ? 0.0 : bestLen;
    return (url, len);
  }

  static Future<String?> streamUrl(String id) async => (await bestStream(id))?.$1;

  // Nom va yil bo'yicha bepul TO'LIQ versiyani qidiradi
  static Future<String?> findFull(String title, String year) async {
    final c = clean(title);
    if (c.isEmpty) return null;
    final uri = Uri.https(host, '/advancedsearch.php', {
      'q': 'title:($c) AND mediatype:movies',
      'fl[]': ['identifier', 'title', 'year'],
      'sort[]': 'downloads desc',
      'rows': '8',
      'output': 'json',
    });
    final r = await http.get(uri);
    if (r.statusCode != 200) return null;
    final docs = jsonDecode(r.body)['response']['docs'] as List;
    final want = c.toLowerCase();
    final wy = int.tryParse(year);
    for (final d in docs) {
      final t = s(d['title']);
      if (isBad(t) || !clean(t).toLowerCase().contains(want)) continue;
      final dy = int.tryParse(s(d['year']));
      if (wy != null && dy != null && (wy - dy).abs() > 1) continue;
      try {
        final b = await bestStream(s(d['identifier']));
        if (b != null && b.$2 >= fullMinSeconds) return b.$1;
      } catch (_) {}
    }
    return null;
  }
}

// ───────────────────────── UMUMIY WIDGETLAR ─────────────────────────
// Rasm: yuklanganda silliq paydo bo'ladi, xato bo'lsa chiroyli belgi ko'rsatadi
Widget posterImg(String? url, String label, {double? w, double? h}) {
  Widget ph() => Container(
    width: w, height: h, alignment: Alignment.center,
    decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF2A1B54), Color(0xFF14323A)],
            begin: Alignment.topLeft, end: Alignment.bottomRight)),
    child: Text(label.isEmpty ? '🎞️' : label.characters.first.toUpperCase(),
        style: const TextStyle(fontSize: 32, color: Colors.white54, fontWeight: FontWeight.w900)),
  );
  if (url == null) return ph();
  return Image.network(
    url, width: w, height: h, fit: BoxFit.cover,
    frameBuilder: (c, child, frame, sync) => Container(
      width: w, height: h, color: kCard2,
      child: sync
          ? child
          : AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 450),
          child: child),
    ),
    errorBuilder: (_, __, ___) => ph(),
  );
}

void snack(BuildContext c, String t) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

Future<void> openUrl(String u) =>
    launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);

// Bosganda biroz kichrayadigan o'ram
class Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Tap({super.key, required this.child, this.onTap});
  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onTapDown: (_) => setState(() => down = true),
    onTapUp: (_) => setState(() => down = false),
    onTapCancel: () => setState(() => down = false),
    child: AnimatedScale(
        scale: down ? .95 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child),
  );
}

// Yuklanish paytidagi pulsatsiyalanuvchi joy
class Skeleton extends StatefulWidget {
  final double? w, h;
  final double r;
  const Skeleton({super.key, this.w, this.h, this.r = 14});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() { c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (_, __) => Container(
      width: widget.w, height: widget.h,
      decoration: BoxDecoration(
        color: Color.lerp(kCard2, const Color(0xFF2A2A38), c.value),
        borderRadius: BorderRadius.circular(widget.r),
      ),
    ),
  );
}

class Chip2 extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const Chip2({super.key, required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: on ? kGrad : null,
        color: on ? null : kCard2,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: on ? Colors.transparent : Colors.white12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: on ? Colors.white : Colors.white70)),
    ),
  );
}

Widget pillBtn(String text, VoidCallback onTap) => Tap(
  onTap: onTap,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: kCard, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(children: [
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700))),
      const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.white54),
    ]),
  ),
);

// Gradient asosiy tugma
class GradBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  const GradBtn({super.key, required this.icon, required this.label, this.onTap, this.busy = false});
  @override
  Widget build(BuildContext context) => Tap(
    onTap: busy ? null : onTap,
    child: Container(
      height: 54, alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: kGrad, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: kAccent.withOpacity(.4), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: busy
          ? const SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
      ]),
    ),
  );
}

class SoftBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  const SoftBtn({super.key, required this.icon, required this.label, this.onTap, this.busy = false});
  @override
  Widget build(BuildContext context) => Tap(
    onTap: busy ? null : onTap,
    child: Container(
      height: 54, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kCard2, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 8),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
      ]),
    ),
  );
}

Widget ratingBadge(double r) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
  decoration: BoxDecoration(
      color: Colors.black.withOpacity(.65), borderRadius: BorderRadius.circular(10)),
  child: Row(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFC107)),
    const SizedBox(width: 3),
    Text(r.toStringAsFixed(1),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
  ]),
);

Widget metaChip(String t) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
  decoration: BoxDecoration(
      color: Colors.white.withOpacity(.08), borderRadius: BorderRadius.circular(20)),
  child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
);

Future<String?> pickSheet(BuildContext c, String title, List<(String, String)> opts, String cur) =>
    showModalBottomSheet<String>(
      context: c,
      backgroundColor: kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(width: 42, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: opts.map((o) => ListTile(
                title: Text(o.$2, style: TextStyle(
                    fontWeight: o.$1 == cur ? FontWeight.w800 : FontWeight.w500)),
                trailing: o.$1 == cur
                    ? const Icon(Icons.check_circle_rounded, color: kAccent)
                    : null,
                onTap: () => Navigator.pop(ctx, o.$1),
              )).toList()),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );

// ───────────────────────── APP ─────────────────────────
class CinemaApp extends StatelessWidget {
  const CinemaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Free Cinema',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: kAccent,
      scaffoldBackgroundColor: kBg,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kCard2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    home: const HomePage(),
  );
}

// ───────────────────────── BANNER ─────────────────────────
class HeroBanner extends StatefulWidget {
  final List<Film> films;
  final void Function(Film) onTap;
  const HeroBanner({super.key, required this.films, required this.onTap});
  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final pc = PageController(viewportFraction: .92);
  int i = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!pc.hasClients || widget.films.isEmpty) return;
      pc.animateToPage((i + 1) % widget.films.length,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fs = widget.films;
    return Column(children: [
      SizedBox(
        height: 230,
        child: PageView.builder(
          controller: pc,
          itemCount: fs.length,
          onPageChanged: (v) => setState(() => i = v),
          itemBuilder: (_, k) {
            final f = fs[k];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Tap(
                onTap: () => widget.onTap(f),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(
                        color: kAccent.withOpacity(.25), blurRadius: 24, offset: const Offset(0, 10))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(fit: StackFit.expand, children: [
                      posterImg(f.backdrop ?? f.poster, f.title),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xE6000000)],
                            stops: [.35, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18, right: 18, bottom: 16,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(f.sub, style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                    gradient: kGrad, borderRadius: BorderRadius.circular(20)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text("Ko'rish", style: TextStyle(
                                      fontWeight: FontWeight.w800, color: Colors.white)),
                                ]),
                              ),
                            ]),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var k = 0; k < fs.length; k++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: k == i ? 20 : 6, height: 6,
            decoration: BoxDecoration(
              gradient: k == i ? kGrad : null,
              color: k == i ? null : Colors.white24,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    ]);
  }
}

// ───────────────────────── BOSH SAHIFA ─────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  final scroll = ScrollController();
  final search = TextEditingController();
  final List<Film> items = [];
  String kind = 'free';
  String query = '';
  int? genre;
  int page = 1;
  int gen = 0;
  bool loading = false, more = true;
  String? error;

  @override
  void initState() {
    super.initState();
    cfg.addListener(reset);
    scroll.addListener(() {
      if (scroll.hasClients &&
          scroll.position.pixels > scroll.position.maxScrollExtent - 600) load();
    });
    load();
  }

  @override
  void dispose() {
    cfg.removeListener(reset);
    scroll.dispose();
    search.dispose();
    super.dispose();
  }

  void reset() {
    if (!mounted) return;
    setState(() {
      gen++;
      items.clear();
      page = 1;
      more = true;
      error = null;
      loading = false;
    });
    load();
  }

  Future<void> load() async {
    if (loading || !more) return;
    final g = gen;
    setState(() { loading = true; error = null; });
    try {
      final List<Film> r = kind == 'archive'
          ? await Archive.load(page, cfg.lang, query)
          : await Tmdb.list(kind, page, query, genre);
      if (!mounted || g != gen) return;
      setState(() {
        items.addAll(r);
        if (r.isEmpty) { more = false; } else { page++; }
      });
    } catch (_) {
      if (mounted && g == gen) setState(() => error = "Yuklab bo'lmadi. Internetni tekshiring.");
    } finally {
      if (mounted && g == gen) setState(() => loading = false);
    }
  }

  void open(Film f) {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => f.iaId != null ? ArchiveDetail(film: f) : TmdbDetail(film: f)));
  }

  Widget gridCard(Film f) => Tap(
    onTap: () => open(f),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(
                color: Colors.black54, blurRadius: 14, offset: Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(fit: StackFit.expand, children: [
              posterImg(f.poster, f.title),
              if (f.rating != null && f.rating! > 0)
                Positioned(top: 8, left: 8, child: ratingBadge(f.rating!)),
              if (f.iaId != null)
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        gradient: kGrad, borderRadius: BorderRadius.circular(10)),
                    child: const Text('BEPUL', style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .6)),
                  ),
                ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.2)),
      const SizedBox(height: 2),
      Text(f.year.isEmpty ? ' ' : f.year,
          style: const TextStyle(fontSize: 12, color: Colors.white54)),
    ]),
  );

  Widget skeletonCard() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Skeleton(r: 18, w: double.infinity)),
      SizedBox(height: 8),
      Skeleton(h: 12, w: 110, r: 6),
      SizedBox(height: 6),
      Skeleton(h: 10, w: 50, r: 6),
    ],
  );

  static const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 180, childAspectRatio: .52,
    crossAxisSpacing: 14, mainAxisSpacing: 16,
  );

  @override
  Widget build(BuildContext context) {
    final showHero = kind != 'archive' && query.isEmpty && items.length >= 3;
    final sectionTitle = [
      kinds[kind]!,
      if (genre != null) genres[genre]!,
    ].join('  ·  ');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.center,
            colors: [Color(0xFF1B1038), kBg],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverAppBar(
                floating: true, snap: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                title: Row(children: [
                  const Text('🎬 ', style: TextStyle(fontSize: 22)),
                  ShaderMask(
                    shaderCallback: (r) => kGrad.createShader(r),
                    child: const Text('FREE CINEMA',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, letterSpacing: 1.4, color: Colors.white)),
                  ),
                ]),
              ),
              // Qidiruv
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Film qidirish...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () { search.clear(); query = ''; reset(); },
                      ),
                      filled: true,
                      fillColor: kCard,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (v) { query = v; reset(); },
                  ),
                ),
              ),
              // Til va mintaqa
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(children: [
                    Expanded(
                      child: pillBtn('🗣 ${cfg.lang.name}', () async {
                        final v = await pickSheet(context, 'Tilni tanlang',
                            langs.map((l) => (l.code, l.name)).toList(), cfg.lang.code);
                        if (v != null) cfg.setLang(langs.firstWhere((l) => l.code == v));
                      }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: pillBtn('📍 ${regions[cfg.region]}', () async {
                        final v = await pickSheet(context, 'Mintaqani tanlang',
                            regions.entries.map((e) => (e.key, e.value)).toList(), cfg.region);
                        if (v != null) cfg.setRegion(v);
                      }),
                    ),
                  ]),
                ),
              ),
              // Bo'limlar
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: kinds.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Chip2(
                        label: e.value, on: kind == e.key,
                        onTap: () {
                          kind = e.key;
                          if (kind == 'archive') genre = null;
                          reset();
                        },
                      ),
                    )).toList(),
                  ),
                ),
              ),
              // Janrlar
              if (kind != 'archive')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Chip2(
                                label: 'Hamma janr', on: genre == null,
                                onTap: () { genre = null; reset(); }),
                          ),
                          ...genres.entries.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Chip2(
                                label: e.value, on: genre == e.key,
                                onTap: () { genre = e.key; reset(); }),
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
              // Banner
              if (showHero)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: HeroBanner(films: items.take(6).toList(), onTap: open),
                  ),
                ),
              // Sarlavha
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                  child: Row(children: [
                    Container(
                        width: 5, height: 20,
                        decoration: BoxDecoration(
                            gradient: kGrad, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(query.isEmpty ? sectionTitle : '🔎 "$query"',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ),
              // Setka
              if (items.isEmpty && loading)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: gridDelegate,
                    delegate: SliverChildBuilderDelegate((_, __) => skeletonCard(), childCount: 9),
                  ),
                )
              else if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(error != null ? '📡' : '🎞️', style: const TextStyle(fontSize: 54)),
                        const SizedBox(height: 10),
                        Text(error ?? 'Hech narsa topilmadi',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70)),
                        if (error != null) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: 200,
                            child: GradBtn(
                                icon: Icons.refresh_rounded, label: 'Qayta urinish',
                                onTap: () { error = null; load(); }),
                          ),
                        ],
                      ]),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: gridDelegate,
                    delegate: SliverChildBuilderDelegate(
                          (_, i) => gridCard(items[i]),
                      childCount: items.length,
                    ),
                  ),
                ),
              // Pastki yuklovchi
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: loading && items.isNotEmpty
                        ? const SizedBox(width: 26, height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.6))
                        : error != null && items.isNotEmpty
                        ? TextButton(
                        onPressed: () { error = null; load(); },
                        child: const Text('Qayta urinish'))
                        : const SizedBox(height: 26),
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

// ───────────────────────── DETAL SAHIFA UCHUN UMUMIY QISMLAR ─────────────────────────
Widget backBtn(BuildContext c) => Padding(
  padding: const EdgeInsets.all(8),
  child: CircleAvatar(
    backgroundColor: Colors.black54,
    child: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(c)),
  ),
);

Widget heroImage(String? url, String title) => Stack(fit: StackFit.expand, children: [
  posterImg(url, title),
  const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.black38, Colors.transparent, kBg],
        stops: [0, .45, 1],
      ),
    ),
  ),
]);

// ───────────────────────── TMDB FILM TAFSILOTI ─────────────────────────
class TmdbDetail extends StatefulWidget {
  final Film film;
  const TmdbDetail({super.key, required this.film});
  @override
  State<TmdbDetail> createState() => _TmdbDetailState();
}

class _TmdbDetailState extends State<TmdbDetail> {
  Map<String, dynamic>? d;
  String? err;
  bool busyIa = false;

  @override
  void initState() {
    super.initState();
    Tmdb.detail(widget.film.tmdbId!).then((v) {
      if (mounted) setState(() => d = v);
    }).catchError((_) {
      if (mounted) setState(() => err = "Ma'lumot yuklanmadi.");
    });
  }

  String get year {
    final date = (d?['release_date'] ?? '').toString();
    return date.isEmpty ? '' : date.split('-').first;
  }

  Future<void> trailer() async {
    final vids = ((d?['videos']?['results']) as List?) ?? [];
    final key = Tmdb.pickTrailer(vids, cfg.lang.code);
    if (key == null) { snack(context, 'Bu film uchun treyler topilmadi'); return; }
    await openUrl('https://www.youtube.com/watch?v=$key');
  }

  Future<void> playIa() async {
    setState(() => busyIa = true);
    String? url;
    try { url = await Archive.findFull(widget.film.title, year); } catch (_) {}
    if (!mounted) return;
    setState(() => busyIa = false);
    if (url == null) {
      snack(context, "Arxivda bepul to'liq versiya topilmadi. Pastdagi servislarni ko'ring.");
      return;
    }
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => PlayerPage(title: widget.film.title, url: url!)));
  }

  Widget ratingRing(double r) {
    final col = r >= 7 ? const Color(0xFF2ECC71) : r >= 5 ? const Color(0xFFFFC107) : const Color(0xFFE74C3C);
    return SizedBox(
      width: 54, height: 54,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 54, height: 54,
          child: CircularProgressIndicator(
              value: (r / 10).clamp(0.0, 1.0), strokeWidth: 5,
              backgroundColor: Colors.white12, color: col, strokeCap: StrokeCap.round),
        ),
        Text(r.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      ]),
    );
  }

  Widget providers() {
    final res = ((d?['watch/providers']?['results']) as Map?) ?? {};
    final reg = res[cfg.region] as Map?;
    if (reg == null) {
      return Text("📍 ${regions[cfg.region]} mintaqasida servis topilmadi. "
          "Bosh sahifadan boshqa mintaqani tanlab ko'ring.",
          style: const TextStyle(color: Colors.white60));
    }
    const labels = {
      'free': '🆓 Bepul',
      'ads': '📺 Reklama bilan bepul',
      'flatrate': '💳 Obuna bilan',
      'rent': '🎟 Ijaraga',
      'buy': '🛒 Sotib olish',
    };
    final link = reg['link']?.toString();
    final rows = <Widget>[];
    for (final e in labels.entries) {
      final list = (reg[e.key] as List?) ?? [];
      if (list.isEmpty) continue;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.value, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: list.map((p) {
              final logo = p['logo_path'];
              final name = p['provider_name'].toString();
              return Tooltip(
                message: name,
                child: Tap(
                  onTap: link == null ? null : () => openUrl(link),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: posterImg(
                        logo == null ? null : 'https://image.tmdb.org/t/p/w92$logo',
                        name, w: 50, h: 50),
                  ),
                ),
              );
            }).toList(),
          ),
        ]),
      ));
    }
    if (rows.isEmpty) {
      rows.add(const Text('Hozircha rasmiy servislar topilmadi.',
          style: TextStyle(color: Colors.white60)));
    }
    if (link != null) {
      rows.add(const SizedBox(height: 14));
      rows.add(SoftBtn(
          icon: Icons.open_in_new_rounded,
          label: "Ko'rish sahifasini ochish",
          onTap: () => openUrl(link)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.film;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false, leading: backBtn(context)),
        body: Center(
          child: err != null
              ? Text(err!)
              : const CircularProgressIndicator(),
        ),
      );
    }
    final data = d!;
    final back = data['backdrop_path'] != null
        ? 'https://image.tmdb.org/t/p/w780${data['backdrop_path']}'
        : f.poster;
    final rating = ((data['vote_average'] ?? 0) as num).toDouble();
    final runtime = (data['runtime'] ?? 0) as int;
    final gl = ((data['genres'] as List?) ?? []).map((g) => g['name'].toString()).toList();
    final overview = (data['overview'] ?? '').toString();
    final tagline = (data['tagline'] ?? '').toString();

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 300, pinned: true,
          backgroundColor: kBg, surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false, leading: backBtn(context),
          flexibleSpace: FlexibleSpaceBar(background: heroImage(back, f.title)),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (f.poster != null) ...[
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(
                          color: Colors.black87, blurRadius: 16, offset: Offset(0, 8))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: posterImg(f.poster, f.title, w: 105, h: 155),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((data['title'] ?? f.title).toString(),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w900, height: 1.15)),
                    if (tagline.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(tagline, style: const TextStyle(
                          color: Colors.white54, fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      ratingRing(rating),
                      const SizedBox(width: 10),
                      const Text('Reyting', style: TextStyle(color: Colors.white54)),
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (year.isNotEmpty) metaChip('📅 $year'),
                if (runtime > 0) metaChip('⏱ $runtime daq'),
                ...gl.map(metaChip),
              ]),
              const SizedBox(height: 16),
              Text(overview.isEmpty ? 'Tavsif mavjud emas.' : overview,
                  style: const TextStyle(height: 1.5, color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 22),
              GradBtn(icon: Icons.play_circle_fill_rounded, label: "Treylerni ko'rish", onTap: trailer),
              const SizedBox(height: 10),
              SoftBtn(
                  icon: Icons.movie_filter_rounded,
                  label: "Arxivdan bepul to'liq versiya",
                  busy: busyIa, onTap: playIa),
              const SizedBox(height: 26),
              Row(children: [
                Container(
                    width: 5, height: 20,
                    decoration: BoxDecoration(
                        gradient: kGrad, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 10),
                const Text("Qayerda ko'rish mumkin",
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ]),
              providers(),
              const SizedBox(height: 28),
              const Text('This product uses the TMDB API but is not endorsed or certified by TMDB.',
                  style: TextStyle(fontSize: 11, color: Colors.white30)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── ARXIV FILMI ─────────────────────────
class ArchiveDetail extends StatefulWidget {
  final Film film;
  const ArchiveDetail({super.key, required this.film});
  @override
  State<ArchiveDetail> createState() => _ArchiveDetailState();
}

class _ArchiveDetailState extends State<ArchiveDetail> {
  bool busy = false;

  Future<void> play() async {
    setState(() => busy = true);
    String? url;
    try { url = await Archive.streamUrl(widget.film.iaId!); } catch (_) {}
    if (!mounted) return;
    setState(() => busy = false);
    if (url == null) { snack(context, 'Bu film uchun video topilmadi'); return; }
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => PlayerPage(title: widget.film.title, url: url!)));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.film;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 300, pinned: true,
          backgroundColor: kBg, surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false, leading: backBtn(context),
          flexibleSpace: FlexibleSpaceBar(background: heroImage(f.poster, f.title)),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.title, style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w900, height: 1.15)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (f.year.isNotEmpty) metaChip('📅 ${f.year}'),
                metaChip('🏛 Public domain'),
                metaChip('🆓 Bepul'),
              ]),
              const SizedBox(height: 16),
              Text(f.desc.isEmpty ? 'Tavsif mavjud emas.' : f.desc,
                  maxLines: 14, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.5, color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 22),
              GradBtn(
                  icon: Icons.play_arrow_rounded, label: "Butun filmni ko'rish",
                  busy: busy, onTap: play),
              const SizedBox(height: 10),
              SoftBtn(
                  icon: Icons.open_in_new_rounded, label: 'Archive.org sahifasi',
                  onTap: () => openUrl('https://archive.org/details/${f.iaId}')),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── PLEYER ─────────────────────────
class PlayerPage extends StatefulWidget {
  final String title, url;
  const PlayerPage({super.key, required this.title, required this.url});
  @override
  State<PlayerPage> createState() => _PlayerState();
}

class _PlayerState extends State<PlayerPage> {
  late final VideoPlayerController vc;
  ChewieController? cc;
  String? err;

  @override
  void initState() {
    super.initState();
    vc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    vc.initialize().then((_) {
      if (!mounted) return;
      setState(() => cc = ChewieController(
        videoPlayerController: vc, autoPlay: true,
        aspectRatio: vc.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: kPink, handleColor: kAccent,
          bufferedColor: Colors.white30, backgroundColor: Colors.white12,
        ),
      ));
    }).catchError((_) {
      if (mounted) setState(() => err = "Videoni ochib bo'lmadi.");
    });
  }

  @override
  void dispose() {
    cc?.dispose();
    vc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: Center(
      child: err != null
          ? Text(err!)
          : cc == null
          ? const CircularProgressIndicator()
          : Chewie(controller: cc!),
    ),
  );
}
