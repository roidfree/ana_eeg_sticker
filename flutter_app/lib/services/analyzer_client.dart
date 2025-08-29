import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class MinuteAnalysis {
  MinuteAnalysis({
    required this.windowStartUtc,
    required this.windowEndUtc,
    required this.focused,
    required this.stressed,
  });

  final DateTime windowStartUtc;
  final DateTime windowEndUtc;
  final bool focused;
  final bool stressed;

  factory MinuteAnalysis.fromJson(Map<String, dynamic> j) => MinuteAnalysis(
        windowStartUtc: DateTime.parse(j['window_start_utc'] as String).toUtc(),
        windowEndUtc: DateTime.parse(j['window_end_utc'] as String).toUtc(),
        focused: j['focused'] as bool,
        stressed: j['stressed'] as bool,
      );
}

class AnalyzerClient {
  AnalyzerClient(this.baseUrl);
  final String baseUrl; // e.g., http://192.168.1.50:8000

  Future<MinuteAnalysis> analyzeCsv(File csv) async {
    final uri = Uri.parse("$baseUrl/analyze");
    final req = http.MultipartRequest("POST", uri)
      ..files.add(await http.MultipartFile.fromPath("file", csv.path));

    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 200) {
      throw Exception("Analyzer error ${resp.statusCode}: $body");
    }
    return MinuteAnalysis.fromJson(jsonDecode(body));
  }
}
