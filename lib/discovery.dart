import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// En Vacuula-server som hittades på nätverket.
class FoundServer {
  FoundServer(this.url, this.version);
  final String url;
  final String version;
}

bool _isPrivate(InternetAddress a) {
  final b = a.rawAddress;
  if (b.length != 4) return false;
  return b[0] == 10 ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31);
}

/// Söker igenom telefonens lokala nät (x.x.x.1–254) efter en Vacuula-server på port 80.
///
/// Vacuulas egen mDNS-annonsering fungerar inte alltid (t.ex. Docker på Mac),
/// så vi frågar helt enkelt varje adress efter GET /api/server.
Future<List<FoundServer>> findVacuulaServers({
  int port = 80,
  void Function(double progress)? onProgress,
}) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  final targets = <String>{};
  final own = <String>{};
  for (final iface in interfaces) {
    for (final addr in iface.addresses) {
      if (!_isPrivate(addr)) continue;
      own.add(addr.address);
      final p = addr.rawAddress;
      for (var i = 1; i < 255; i++) {
        targets.add('${p[0]}.${p[1]}.${p[2]}.$i');
      }
    }
  }
  // Telefonen själv kör knappast servern; sök den sist.
  final list = targets.where((t) => !own.contains(t)).toList()..addAll(own);
  if (list.isEmpty) return [];

  final client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 800);
  final found = <FoundServer>[];
  var done = 0;
  var next = 0;

  Future<void> probe(String ip) async {
    final url = port == 80 ? 'http://$ip' : 'http://$ip:$port';
    try {
      final req = await client
          .getUrl(Uri.parse('$url/api/server'))
          .timeout(const Duration(milliseconds: 900));
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 2));
        final j = jsonDecode(body);
        if (j is Map && j['version'] is String && j.containsKey('gen4_port')) {
          found.add(FoundServer(url, j['version'] as String));
        }
      } else {
        await res.drain<void>();
      }
    } catch (_) {
      // ingen server här
    }
  }

  Future<void> worker() async {
    while (next < list.length) {
      final ip = list[next++];
      await probe(ip);
      done++;
      onProgress?.call(done / list.length);
    }
  }

  await Future.wait(List.generate(48, (_) => worker()));
  client.close(force: true);
  return found;
}
