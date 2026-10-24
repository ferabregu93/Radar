import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart'
    show
        FlutterMap,
        MapOptions,
        MapController,
        TileLayer,
        PolylineLayer,
        Polyline,
        CircleLayer,
        CircleMarker,
        MarkerLayer,
        Marker,
        NetworkTileProvider;
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart'
    show AndroidSettings, ForegroundNotificationConfig;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

const kAppName = 'Radar';
const kNick = 'Fernolo';
const kVersion = '1.6';

/// Declinación magnética local en grados (este positivo). En el noroeste argentino
/// es de unos 5° al oeste (aprox. -5). Con 0 los rumbos quedan en norte magnético.
const kDeclinationDeg = 0.0;

void main() => runApp(const RadarApp());

class RadarApp extends StatelessWidget {
  const RadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kAppName,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF070A11),
      ),
      home: const HomePage(),
    );
  }
}

// ═══════════════════════ TABLAS DE REFERENCIA ═══════════════════════

const kCompaniesFallback = <int, String>{
  0x0006: 'Microsoft',
  0x004C: 'Apple, Inc.',
  0x0075: 'Samsung Electronics Co. Ltd.',
  0x00E0: 'Google',
  0x01AB: 'Meta Platforms, Inc.',
  0x058E: 'Meta Platforms Technologies, LLC',
  0x0D53: 'Luxottica Group S.p.A.',
  0x03C2: 'Snap Inc.',
  0x0171: 'Amazon.com Services LLC',
  0x02E5: 'Espressif Incorporated',
  0x0059: 'Nordic Semiconductor ASA',
  0x038F: 'Xiaomi Inc.',
  0x027D: 'Huawei Technologies Co., Ltd.',
  0x012D: 'Sony Corporation',
  0x0087: 'Garmin International, Inc.',
  0x009E: 'Bose Corporation',
  0x0157: 'Anhui Huami Information Technology Co., Ltd.',
};

const kServicesFallback = <String, String>{
  '1800': 'Generic Access',
  '1801': 'Generic Attribute',
  '180a': 'Device Information',
  '180d': 'Heart Rate',
  '180f': 'Battery',
  '1812': 'Human Interface Device',
  '1809': 'Health Thermometer',
  '1810': 'Blood Pressure',
  '1816': 'Cycling Speed and Cadence',
  '1818': 'Cycling Power',
  '181a': 'Environmental Sensing',
  '1826': 'Fitness Machine',
  '184e': 'Audio Stream Control',
  '1850': 'Published Audio Capabilities',
  'fe2c': 'Google Fast Pair',
  'feaa': 'Eddystone',
  'feed': 'Tile',
  'fd5a': 'Samsung SmartTag',
  'fd6f': 'Exposure Notification',
  'fd5f': 'Meta',
  'fe95': 'Xiaomi',
  'fee0': 'Huami (Mi Band / Amazfit)',
};

const kAppleTypes = <int, String>{
  0x02: 'iBeacon',
  0x03: 'AirPrint',
  0x05: 'AirDrop',
  0x06: 'HomeKit',
  0x07: 'Proximity Pairing (AirPods/Beats)',
  0x08: 'Hey Siri',
  0x09: 'AirPlay Target',
  0x0A: 'AirPlay Source',
  0x0B: 'Magic Switch',
  0x0C: 'Handoff',
  0x0D: 'Tethering Target',
  0x0E: 'Tethering Source',
  0x0F: 'Nearby Action',
  0x10: 'Nearby Info',
  0x12: 'Find My',
};

const kAirPods = <int, String>{
  0x2002: 'AirPods (1.ª gen)',
  0x200F: 'AirPods (2.ª gen)',
  0x2013: 'AirPods (3.ª gen)',
  0x200E: 'AirPods Pro',
  0x2014: 'AirPods Pro (2.ª gen)',
  0x200A: 'AirPods Max',
  0x2003: 'Powerbeats3',
  0x2005: 'BeatsX',
  0x2006: 'Beats Solo3',
  0x2009: 'Beats Studio3',
  0x200B: 'Powerbeats Pro',
  0x2010: 'Beats Flex',
  0x2011: 'Beats Studio Buds',
  0x2016: 'Beats Studio Buds+',
  0x2012: 'Beats Fit Pro',
};

const kMsDevices = <int, String>{
  1: 'Xbox One',
  6: 'iPhone (vía Microsoft CDP)',
  7: 'iPad (vía Microsoft CDP)',
  8: 'Dispositivo Android (vía Microsoft CDP)',
  9: 'PC con Windows 10',
  11: 'Teléfono con Windows',
  12: 'Equipo Linux',
  13: 'Windows IoT',
  14: 'Surface Hub',
  15: 'Laptop con Windows',
  16: 'Tablet con Windows',
};

const kAppearance = <int, String>{
  1: 'Teléfono',
  2: 'Computadora',
  3: 'Reloj / pulsera',
  4: 'Reloj de pared',
  5: 'Pantalla',
  6: 'Control remoto',
  7: 'Gafas',
  8: 'Etiqueta (tag / rastreador)',
  9: 'Llavero (rastreador)',
  10: 'Reproductor multimedia',
  11: 'Lector de códigos',
  12: 'Termómetro',
  13: 'Pulsómetro',
  14: 'Tensiómetro',
  15: 'Periférico HID (teclado/mouse)',
  16: 'Glucómetro',
  17: 'Sensor de carrera',
  18: 'Sensor de ciclismo',
  21: 'Dispositivo de control',
  22: 'Dispositivo de red',
  23: 'Sensor',
  24: 'Luminaria',
  25: 'Ventilador',
  26: 'HVAC',
  27: 'Aire acondicionado',
  28: 'Humidificador',
  29: 'Calefacción',
  30: 'Control de acceso',
  31: 'Dispositivo motorizado',
  32: 'Fuente de energía',
  33: 'Fuente de luz',
  34: 'Cortina / persiana',
  35: 'Parlante / receptor de audio',
  36: 'Fuente de audio',
  37: 'Vehículo',
  38: 'Electrodoméstico',
  39: 'Auricular / audio vestible',
  40: 'Aeronave',
  41: 'Equipo AV',
  42: 'Equipo de pantalla',
  43: 'Audífono médico',
  44: 'Videojuegos',
  45: 'Cartelería',
  49: 'Oxímetro',
  50: 'Balanza',
  51: 'Movilidad personal',
  52: 'Monitor continuo de glucosa',
  53: 'Bomba de insulina',
  54: 'Dispensador de medicación',
  81: 'Deporte al aire libre',
};

class Rule {
  final RegExp re;
  final String type;
  final int conf;
  final String? tag;
  Rule(String pattern, this.type, this.conf, [this.tag])
      : re = RegExp(pattern, caseSensitive: false);
}

class SvcRule {
  final String uuid, type;
  final int conf;
  final String? brand;
  const SvcRule(this.uuid, this.type, this.conf, [this.brand]);
}

const kSvcRules = <SvcRule>[
  SvcRule('180d', 'Pulsómetro / banda deportiva', 65),
  SvcRule('1812', 'Periférico HID (teclado, mouse, control)', 60),
  SvcRule('184e', 'Audio Bluetooth LE (auricular/parlante)', 60),
  SvcRule('1850', 'Audio Bluetooth LE (auricular/parlante)', 60),
  SvcRule('1851', 'Audio Bluetooth LE (auricular/parlante)', 60),
  SvcRule('1852', 'Audio Bluetooth LE (auricular/parlante)', 60),
  SvcRule('1853', 'Audio Bluetooth LE (auricular/parlante)', 60),
  SvcRule('1844', 'Audio Bluetooth LE (auricular/parlante)', 55),
  SvcRule('fe2c', 'Accesorio Google Fast Pair (auricular/parlante)', 55),
  SvcRule('1826', 'Equipo de fitness', 60),
  SvcRule('181a', 'Sensor ambiental', 55),
  SvcRule('1822', 'Oxímetro', 60),
  SvcRule('181d', 'Balanza', 60),
  SvcRule('1810', 'Tensiómetro', 60),
  SvcRule('1809', 'Termómetro', 60),
  SvcRule('1808', 'Glucómetro', 60),
  SvcRule('1816', 'Sensor de ciclismo', 60),
  SvcRule('1818', 'Sensor de ciclismo', 60),
  SvcRule('fee0', 'Pulsera Xiaomi / Amazfit', 70, 'Huami (Xiaomi/Amazfit)'),
  SvcRule('fee1', 'Pulsera Xiaomi / Amazfit', 70, 'Huami (Xiaomi/Amazfit)'),
  SvcRule('fe95', 'Dispositivo Xiaomi (MiBeacon)', 50, 'Xiaomi'),
  SvcRule('fd6f', 'Teléfono (Notificación de exposición)', 50),
  SvcRule('1827', 'Dispositivo Bluetooth Mesh', 55),
  SvcRule('1828', 'Dispositivo Bluetooth Mesh', 55),
  SvcRule('feaa', 'Beacon Eddystone', 70),
  SvcRule('fe59', 'Dispositivo en modo actualización (DFU Nordic)', 50),
];

final List<Rule> kBleNameRules = [
  Rule(
      r'airpods|buds|earbud|headphone|headset|auricular|jabra|wh-1000|wf-|jbl|beats|soundcore|freebuds|\btws\b|haylou',
      'Auricular / audio',
      45),
  Rule(r'speaker|soundbar|boombox|echo|homepod|sonos|bocina|parlante|megaboom',
      'Parlante', 40),
  Rule(r'watch|band|amazfit|garmin|fenix|forerunner|fitbit|galaxy fit',
      'Reloj / pulsera', 45),
  Rule(r'bravia|roku|chromecast|fire ?tv|\[tv\]|webos|tizen|\btv\b',
      'TV / streaming', 40),
  Rule(r'airtag|smarttag|\btile\b|chipolo|tracker|keyfinder', 'Rastreador', 50),
  Rule(r'glass|ray-?ban|spectacles|oakley', 'Gafas', 45),
  Rule(r'\bcam\b|ipc|camera|spy|\bdvr\b|doorbell|wyze|eufy', 'Cámara', 35),
  Rule(
      r'keyboard|mouse|\bmx |teclado|gamepad|controller|joy-?con|dualsense|xbox',
      'Periférico / control',
      40),
  Rule(r'printer|laserjet|deskjet|epson|brother', 'Impresora', 40),
  Rule(
      r'iphone|ipad|macbook|galaxy s|galaxy a|pixel|redmi|poco|moto g|xiaomi|oneplus|oppo|realme|android',
      'Teléfono / tablet',
      45),
  Rule(r'laptop|notebook|thinkpad|surface', 'Computadora', 35),
  Rule(r'obd|elm327|tesla', 'Vehículo / OBD', 35),
  Rule(r'govee|hue|bulb|bombilla|lamp', 'Iluminación inteligente', 35),
];

final List<Rule> kWifiVendorRules = [
  Rule(r'space exploration|starlink', 'Router Starlink', 92),
  Rule(
      r'hikvision|dahua|ezviz|reolink|amcrest|uniview|annke|lorex|foscam|vivotek|axis comm|wyze|eufy|arlo|\bring\b|xiongmai|tiandy|hanwha|geovision|mobotix|swann|imou|\bblink\b',
      'Cámara IP / videovigilancia',
      75,
      'cam'),
  Rule(r'espressif', 'Dispositivo IoT (ESP32/ESP8266)', 50, 'iot'),
  Rule(r'raspberry', 'Computadora (Raspberry Pi)', 65),
  Rule(
      r'tp-?link|d-?link|netgear|asustek|asus|linksys|ubiquiti|mikrotik|routerboard|zyxel|tenda|cisco|arris|technicolor|sagemcom|zte|huawei|fiberhome|ruijie|eero|netis|totolink|mercusys|belkin|actiontec|calix|sercomm|askey|compal|ubee|commscope|plume|avm|draytek|aruba|ruckus|cambium|engenius|edgecore',
      'Router / punto de acceso',
      60),
  Rule(r'roku|vizio|hisense|\btcl\b', 'TV / streaming', 55),
  Rule(r'hewlett|\bhp\b|canon|epson|brother|xerox|lexmark|ricoh|kyocera|konica',
      'Impresora', 45),
  Rule(r'sonos|bose|harman|denon|marantz|yamaha', 'Parlante / audio', 50),
  Rule(r'amazon', 'Dispositivo Amazon (Echo/Fire/Ring)', 45),
  Rule(r'nintendo|sony interactive', 'Consola de videojuegos', 55),
  Rule(
      r'apple|samsung|xiaomi|oppo|vivo|oneplus|realme|motorola|google|nothing|honor|lg electronics|sony',
      'Teléfono / dispositivo móvil',
      35),
  Rule(
      r'shenzhen|dongguan|guangdong|zhejiang|hangzhou|huizhou|hui zhou|tuya|realtek|mediatek|ralink|azurewave|liteon|murata|ampak|foxconn|hon hai|universal global',
      'Equipo genérico (chipset/ODM)',
      25,
      'odm'),
];

final List<Rule> kWifiSsidRules = [
  Rule(r'^starlink', 'Router Starlink', 92),
  Rule(r'^direct-', 'Wi-Fi Direct (impresora, TV o celular)', 60),
  Rule(
      r'iphone|ipad|androidap|android_|galaxy|redmi|poco |xiaomi|moto g|pixel|oppo|realme|oneplus|hotspot|mobile ?ap',
      'Punto de acceso de celular (hotspot)',
      65),
  Rule(
      r'^(ipc|ipcam|ip-?cam|hdwificam|hdcam|mv\d|a9[-_]|v380|ycc365|yi[-_]|cam[-_]|camera|wificam|icsee|xm[-_]?\d|bc[-_]|pnp[-_]|spy|minicam|dvr|nvr|ezviz|tapo[-_]c|imou|hikvision)',
      'Cámara WiFi (SSID típico)',
      70,
      'cam'),
  Rule(r'bravia|roku|chromecast|vizio|\[tv\]|smart ?tv|^lg[-_ ]?tv|webos',
      'TV / streaming', 50),
  Rule(r'printer|hp-?print|epson|canon|brother|laserjet|deskjet', 'Impresora',
      55),
  Rule(r'tesla|obd|vgate|elm327', 'Vehículo / OBD', 50),
  Rule(
      r'fritz|movistar|claro|telecentro|arnet|fibertel|flow|iplan|speedy|cablevision|tp-?link|netgear|d-?link|asus|linksys|huawei|zte|mikrotik|ubnt|eero|orbi',
      'Router doméstico / ISP',
      45),
];

// ═══════════════════════ UTILIDADES ═══════════════════════

String hx(List<int> b, [int max = 40]) {
  final s =
      b.take(max).map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
  return b.length > max ? '$s …(+${b.length - max} B)' : s;
}

String asciiOf(List<int> b) =>
    String.fromCharCodes(b.where((c) => c >= 32 && c < 127));

String h4(int v) => '0x${v.toRadixString(16).padLeft(4, '0')}';

String shortErr(String s) => s.length > 110 ? '${s.substring(0, 110)}…' : s;

String shortBrand(String v) {
  final w = v
      .replaceAll(RegExp(r'[,.]'), '')
      .split(' ')
      .where((x) => x.isNotEmpty)
      .toList();
  if (w.isEmpty) return v;
  final s = w.take(2).join(' ');
  return s.length > 22 ? s.substring(0, 22) : s;
}

String shortUuid(String u) {
  u = u.toLowerCase();
  if (u.length == 36 &&
      u.startsWith('0000') &&
      u.endsWith('-0000-1000-8000-00805f9b34fb')) {
    return u.substring(4, 8);
  }
  return u;
}

String uuidOf(dynamic x) {
  try {
    return shortUuid(x.uuid.toString());
  } catch (_) {}
  try {
    return shortUuid(x.characteristicUuid.toString());
  } catch (_) {}
  try {
    return shortUuid(x.serviceUuid.toString());
  } catch (_) {}
  return '?';
}

int? channelFromFreq(int f) {
  if (f == 2484) return 14;
  if (f >= 2412 && f <= 2472) return (f - 2407) ~/ 5;
  if (f >= 5160 && f <= 5885) return (f - 5000) ~/ 5;
  if (f >= 5955 && f <= 7115) return (f - 5950) ~/ 5;
  return null;
}

String bandOf(int f) => f < 3000 ? '2.4 GHz' : (f < 5900 ? '5 GHz' : '6 GHz');

String cardinal(double bearing) {
  const d = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  return d[(((bearing % 360) + 360) % 360 / 45 + 0.5).floor() % 8];
}

String fmtDur(Duration x) => x.inMinutes >= 1
    ? '${x.inMinutes} min ${x.inSeconds % 60} s'
    : '${x.inSeconds} s';

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String t(int x) => x.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)} ${t(d.hour)}:${t(d.minute)}';
}

/// Clave de "familia" de un BSSID: ignora el bit local/multicast del primer byte
/// y el último byte. Las radios de un mismo equipo suelen compartirla.
String? familyKey(String bssid) {
  final o = bssid.toLowerCase().split(':');
  if (o.length != 6) return null;
  final b0 = int.tryParse(o[0], radix: 16);
  if (b0 == null) return null;
  return '${(b0 & 0xFC).toRadixString(16).padLeft(2, '0')}:${o[1]}:${o[2]}:${o[3]}:${o[4]}';
}

/// Quita el bit "administrada localmente" para intentar recuperar el OUI real.
String unLocal(String bssid) {
  if (bssid.length < 2) return bssid;
  final b0 = int.tryParse(bssid.substring(0, 2), radix: 16);
  if (b0 == null) return bssid;
  return '${(b0 & ~0x02).toRadixString(16).padLeft(2, '0')}${bssid.substring(2)}';
}

final RegExp _secRe = RegExp(r'WPA|RSN|WEP|SAE|OWE|EAP');
bool isOpenWifi(Dev d) => !_secRe.hasMatch(d.caps ?? '');

String wifiGen(String? s) {
  switch (s) {
    case 'be':
      return 'Wi-Fi 7';
    case 'ax':
      return 'Wi-Fi 6';
    case 'ac':
      return 'Wi-Fi 5';
    case 'n':
      return 'Wi-Fi 4';
    case 'legacy':
      return 'Wi-Fi antiguo';
    default:
      return 'Wi-Fi';
  }
}

const kLevelLabels = ['LEJOS', 'MEDIA DISTANCIA', 'CERCA', 'MUY CERCA'];
const kLevelColors = [
  Colors.redAccent,
  Colors.orangeAccent,
  Colors.amberAccent,
  Colors.greenAccent
];
const kRiskColors = [Colors.greenAccent, Colors.amberAccent, Colors.redAccent];

class Pt {
  final double latitude, longitude, accuracy, speed, heading;
  const Pt(
      this.latitude, this.longitude, this.accuracy, this.speed, this.heading);
}

/// Rumbo medido con el barrido de brújula, desde un punto conocido.
class Bearing {
  final double lat, lon, deg, contrast;
  const Bearing(this.lat, this.lon, this.deg, this.contrast);
}

/// Filtro de Kalman simple para suavizar el GPS (no corrige sesgo, solo ruido).
/// Con el celular quieto, casi ignora las mediciones nuevas (elimina la deriva).
class GpsFilter {
  double? _la, _lo;
  double _v = 0;
  int? _t;

  Pt update(Position p, {bool still = false}) {
    final acc = max(p.accuracy, 3.0);
    final r = still ? acc * acc * 25 : acc * acc;
    final t = (p.timestamp ?? DateTime.now()).millisecondsSinceEpoch;
    if (_la == null || _lo == null || _t == null) {
      _la = p.latitude;
      _lo = p.longitude;
      _v = acc * acc;
    } else {
      final dt = max(0.0, (t - _t!) / 1000.0);
      final q = still ? 0.3 : max(p.speed * 1.5, 2.5);
      _v += dt * q * q;
      final k = _v / (_v + r);
      _la = _la! + k * (p.latitude - _la!);
      _lo = _lo! + k * (p.longitude - _lo!);
      _v = (1 - k) * _v;
    }
    _t = t;
    return Pt(_la!, _lo!, max(sqrt(_v), 1.0), p.speed, p.heading);
  }

  /// Al empezar a moverse: vuelve a confiar en las mediciones nuevas.
  void inflate() {
    _v = max(_v, 30.0);
  }
}

class MapStyle {
  final String name, url, credit;
  final int maxNative;
  const MapStyle(this.name, this.url, this.credit, this.maxNative);
}

const kMapStyles = <MapStyle>[
  MapStyle('Calles (OSM)', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      '© OpenStreetMap contributors', 19),
  MapStyle(
      'Claro (CARTO)',
      'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
      '© OpenStreetMap contributors © CARTO',
      20),
  MapStyle(
      'Satélite (Esri)',
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'Tiles © Esri',
      19),
  MapStyle(
      'Relieve (OpenTopoMap)',
      'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
      '© OpenTopoMap (CC-BY-SA)',
      17),
];

const kTileAgent = 'ar.fernolo.signalhunter';

(int, int) tileXY(double lat, double lon, int z) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor();
  final r = lat * pi / 180;
  final y = ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n).floor();
  return (x.clamp(0, n - 1).toInt(), y.clamp(0, n - 1).toInt());
}

/// Cliente HTTP que guarda cada tesela en disco y la reutiliza (mapa sin conexión).
class CachedClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  Directory? dir;

  Future<Directory> _dir() async {
    final c = dir;
    if (c != null) return c;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/tiles');
    if (!await d.exists()) await d.create(recursive: true);
    dir = d;
    return d;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET') return _inner.send(request);
    File? f;
    try {
      final d = await _dir();
      f = File(
          '${d.path}/${request.url.toString().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        return http.StreamedResponse(Stream.value(bytes), 200,
            contentLength: bytes.length,
            request: request,
            headers: {'content-type': 'image/png'});
      }
    } catch (_) {}
    final res = await _inner.send(request);
    if (res.statusCode == 200 && f != null) {
      final bytes = await res.stream.toBytes();
      try {
        await f.writeAsBytes(bytes);
      } catch (_) {}
      return http.StreamedResponse(Stream.value(bytes), 200,
          contentLength: bytes.length, request: request, headers: res.headers);
    }
    return res;
  }
}

// ═══════════════════════ BASE DE DATOS (descargable) ═══════════════════════

/// Corre en un isolate: convierte el CSV de la IEEE en {OUI: fabricante}.
Map<String, String> parseOuiCsv(String text) {
  final out = <String, String>{};
  final n = text.length;
  final row = <String>[];
  final sb = StringBuffer();
  var inQ = false;
  var first = true;
  void endField() {
    row.add(sb.toString());
    sb.clear();
  }

  void endRow() {
    endField();
    if (!first && row.length >= 3) {
      final k = row[1].trim().toUpperCase();
      if (k.isNotEmpty) out[k] = row[2].trim();
    }
    first = false;
    row.clear();
  }

  var i = 0;
  while (i < n) {
    final ch = text[i];
    if (inQ) {
      if (ch == '"') {
        if (i + 1 < n && text[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        sb.write(ch);
      }
    } else {
      if (ch == '"') {
        inQ = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else if (ch != '\r') {
        sb.write(ch);
      }
    }
    i++;
  }
  if (sb.isNotEmpty || row.isNotEmpty) endRow();
  return out;
}

class Db {
  Map<int, String> companies = Map.of(kCompaniesFallback);
  Map<String, String> services = Map.of(kServicesFallback);
  Map<String, String> chars = {};
  Map<String, String> oui = {};
  String status =
      'Base básica integrada. Menú ⋮ → "Actualizar bases" (requiere internet).';
  bool loading = false;

  static const _base =
      'https://raw.githubusercontent.com/NordicSemiconductor/bluetooth-numbers-database/master/v1/';
  static const _ouiUrl = 'https://standards-oui.ieee.org/oui/oui.csv';

  String? serviceName(String s) => services[s.toLowerCase()];
  String? charName(String s) => chars[s.toLowerCase()];

  String? vendorOf(String mac) {
    final h = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (h.length < 6) return null;
    for (final len in [9, 7, 6]) {
      if (h.length >= len) {
        final v = oui[h.substring(0, len)];
        if (v != null) return v;
      }
    }
    return null;
  }

  Future<String?> _download(String url) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'Mozilla/5.0 SignalHunter');
      final res = await req.close().timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) return null;
      return await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  Future<String?> _get(String name, String url, bool force) async {
    File? f;
    try {
      f = File('${Directory.systemTemp.path}/sh_$name');
    } catch (_) {}
    String? stale;
    if (f != null && !force) {
      try {
        if (await f.exists()) {
          final txt = await f.readAsString();
          final age = DateTime.now().difference(await f.lastModified());
          if (age.inDays < 30) return txt;
          stale = txt;
        }
      } catch (_) {}
    }
    final txt = await _download(url);
    if (txt != null && txt.length > 100) {
      try {
        await f?.writeAsString(txt);
      } catch (_) {}
      return txt;
    }
    if (stale == null && f != null) {
      try {
        if (await f.exists()) stale = await f.readAsString();
      } catch (_) {}
    }
    return stale;
  }

  Map<String, String> _uuidMap(String json) {
    final m = <String, String>{};
    for (final e in jsonDecode(json) as List) {
      m[e['uuid'].toString().toLowerCase()] = e['name'].toString();
    }
    return m;
  }

  Future<void> load({bool force = false}) async {
    loading = true;
    final parts = <String>[];

    final c = await _get('company_ids.json', '${_base}company_ids.json', force);
    if (c != null) {
      try {
        final m = <int, String>{};
        for (final e in jsonDecode(c) as List) {
          m[(e['code'] as num).toInt()] = e['name'].toString();
        }
        if (m.length > 100) {
          companies = {...kCompaniesFallback, ...m};
          parts.add('${m.length} compañías');
        }
      } catch (_) {}
    }

    final s =
        await _get('service_uuids.json', '${_base}service_uuids.json', force);
    if (s != null) {
      try {
        final m = _uuidMap(s);
        if (m.length > 20) {
          services = {...kServicesFallback, ...m};
          parts.add('${m.length} servicios');
        }
      } catch (_) {}
    }

    final ch = await _get('characteristic_uuids.json',
        '${_base}characteristic_uuids.json', force);
    if (ch != null) {
      try {
        final m = _uuidMap(ch);
        if (m.length > 20) {
          chars = m;
          parts.add('${m.length} características');
        }
      } catch (_) {}
    }

    final o = await _get('oui.csv', _ouiUrl, force);
    if (o != null) {
      try {
        final m = await compute(parseOuiCsv, o);
        if (m.length > 1000) {
          oui = m;
          parts.add('${m.length} OUI');
        }
      } catch (_) {}
    }

    status = parts.isEmpty
        ? 'Sin descarga ni caché: usando tabla básica. Revisa el permiso INTERNET y la conexión.'
        : 'Bases: ${parts.join(' · ')}';
    loading = false;
  }
}

// ═══════════════════════ IDENTIFICACIÓN ═══════════════════════

class Ident {
  String type = 'Desconocido';
  String? brand, model;
  int conf = 0;
  final List<String> why = [];
  final List<String> alerts = [];
  final Map<String, String> facts = {};

  void p(String t, int c, String w, {String? brand, String? model}) {
    why.add('$w → $t ($c%)');
    final best = c >= conf;
    if (best) {
      type = t;
      conf = c;
    }
    if (brand != null && (best || this.brand == null)) this.brand = brand;
    if (model != null && (best || this.model == null)) this.model = model;
  }

  void alert(String a) {
    if (!alerts.contains(a)) alerts.add(a);
  }
}

class AppleTlv {
  final int type;
  final List<int> data;
  AppleTlv(this.type, this.data);
}

List<AppleTlv> parseApple(List<int> b) {
  final out = <AppleTlv>[];
  var i = 0;
  while (i + 1 < b.length) {
    final t = b[i];
    final l = b[i + 1];
    if (i + 2 + l > b.length) {
      out.add(AppleTlv(t, b.sublist(i + 2)));
      break;
    }
    out.add(AppleTlv(t, b.sublist(i + 2, i + 2 + l)));
    i += 2 + l;
  }
  return out;
}

Ident identifyBle(Dev d, Db db) {
  final id = Ident();
  final f = id.facts;
  final name = d.rawName;
  final svc = d.svcUuids;

  final b0 =
      d.id.length >= 2 ? int.tryParse(d.id.substring(0, 2), radix: 16) : null;
  if (b0 != null && d.id.contains(':')) {
    final top = b0 >> 6;
    f['Tipo de dirección (probable)'] = top == 3
        ? 'aleatoria estática'
        : (top == 1
            ? 'privada resolvible (rota cada ~15 min: típico de celulares, AirTag, auriculares)'
            : 'pública o privada no resolvible');
  }
  if (name.isNotEmpty) f['Nombre anunciado'] = name;
  if (d.txPower != null) f['TX power anunciado'] = '${d.txPower} dBm';
  if (d.connectable != null) f['Conectable'] = d.connectable! ? 'sí' : 'no';

  d.mfrData.forEach((k, v) {
    final nm = db.companies[k];
    f['Fabricante ${h4(k)}'] = '${nm ?? 'ID no registrado'} · ${hx(v)}';
    if (nm != null) id.brand ??= nm;
  });
  d.svcData.forEach((k, v) => f['Service data $k'] = hx(v));

  if (svc.isNotEmpty) {
    f['Servicios anunciados'] = svc.map((s) {
      final n = db.serviceName(s);
      return n == null ? s : '$s ($n)';
    }).join(', ');
  }

  final apple = d.mfrData[0x004C];
  if (apple != null) {
    id.brand ??= 'Apple';
    for (final t in parseApple(apple)) {
      final tn = kAppleTypes[t.type] ?? 'tipo 0x${t.type.toRadixString(16)}';
      f['Apple · $tn'] = hx(t.data);
      if (t.type == 0x07 && t.data.length >= 6) {
        final mid = (t.data[2] << 8) | t.data[1];
        final model = kAirPods[mid];
        final flipped = (((t.data[3] >> 4) >> 1) & 1) == 0;
        final bb = t.data[4];
        final hi = bb >> 4, lo = bb & 0xF;
        final left = flipped ? hi : lo;
        final right = flipped ? lo : hi;
        final cs = t.data[5];
        final flags = cs >> 4;
        final caseB = cs & 0xF;
        final chL = (flags & (flipped ? 2 : 1)) != 0;
        final chR = (flags & (flipped ? 1 : 2)) != 0;
        final chC = (flags & 4) != 0;
        String bt(int n, bool ch) =>
            n <= 10 ? '${n * 10}%${ch ? '⚡' : ''}' : 'n/d';
        f['Batería (aprox.)'] =
            'izq ${bt(left, chL)} · der ${bt(right, chR)} · estuche ${bt(caseB, chC)}';
        id.p('Auricular / audio', 90,
            'Apple Proximity Pairing${model != null ? ' ($model)' : ''}',
            brand: 'Apple',
            model:
                model ?? 'AirPods/Beats (modelo 0x${mid.toRadixString(16)})');
      } else if (t.type == 0x02 && t.data.length >= 21) {
        final u = t.data
            .sublist(0, 16)
            .map((x) => x.toRadixString(16).padLeft(2, '0'))
            .join();
        final uuid =
            '${u.substring(0, 8)}-${u.substring(8, 12)}-${u.substring(12, 16)}-${u.substring(16, 20)}-${u.substring(20)}';
        final major = (t.data[16] << 8) | t.data[17];
        final minor = (t.data[18] << 8) | t.data[19];
        final tx = t.data[20] > 127 ? t.data[20] - 256 : t.data[20];
        d.calTx = tx;
        f['iBeacon'] =
            'UUID $uuid · major $major · minor $minor · potencia a 1 m: $tx dBm';
        id.p('Beacon iBeacon', 85, 'Apple iBeacon', brand: 'Apple');
      } else if (t.type == 0x12) {
        id.p('Rastreador (Find My)', 80, 'Apple Find My (tipo 0x12)',
            brand: 'Apple', model: 'AirTag u otro accesorio Find My');
        id.alert('Rastreador');
      } else if (const [0x10, 0x0F, 0x0C, 0x05, 0x0B].contains(t.type)) {
        id.p('Dispositivo Apple (iPhone/iPad/Mac/Watch)', 55, 'Apple $tn',
            brand: 'Apple');
      } else if (t.type == 0x09 || t.type == 0x0A) {
        id.p('Apple TV / HomePod / receptor AirPlay', 50, 'Apple $tn',
            brand: 'Apple');
      } else if (t.type == 0x06) {
        id.p('Accesorio HomeKit', 60, 'Apple HomeKit', brand: 'Apple');
      }
    }
  }

  final ms = d.mfrData[0x0006];
  if (ms != null && ms.length >= 2 && ms[0] == 0x01) {
    final dt = ms[1] & 0x3F;
    final nm = kMsDevices[dt];
    f['Microsoft CDP'] = 'tipo de dispositivo $dt${nm != null ? ' ($nm)' : ''}';
    if (nm != null) id.p(nm, 60, 'Microsoft CDP tipo $dt', brand: 'Microsoft');
  }

  if (d.mfrData.containsKey(0x0D53)) {
    id.p('Gafas inteligentes', 90,
        'Company ID 0x0D53 (Luxottica: Ray-Ban/Oakley)',
        brand: 'Luxottica (Ray-Ban / Oakley Meta)');
    id.alert('Gafas inteligentes');
  }
  for (final k in [0x058E, 0x01AB]) {
    final m = d.mfrData[k];
    if (m == null) continue;
    if (asciiOf(m).contains('META_RB_GLASS')) {
      id.p('Gafas inteligentes', 95, 'Payload "META_RB_GLASS" (${h4(k)})',
          brand: 'Meta', model: 'Ray-Ban Meta');
      id.alert('Gafas inteligentes');
    } else {
      id.p('Producto Meta (gafas, Quest u otro)', 55,
          'Company ID ${h4(k)} (Meta)',
          brand: 'Meta');
    }
  }
  if (svc.contains('fd5f')) {
    id.p('Producto Meta (posibles gafas)', 70, 'Service UUID 0xFD5F (Meta)',
        brand: 'Meta');
    id.alert('Posibles gafas Meta');
  }
  if (d.mfrData.containsKey(0x03C2)) {
    id.p('Gafas inteligentes', 85, 'Company ID 0x03C2 (Snap)',
        brand: 'Snap (Spectacles)');
    id.alert('Gafas inteligentes');
  }

  if (svc.contains('feed') || svc.contains('feec')) {
    id.p('Rastreador Tile', 85, 'Service UUID 0xFEED/0xFEEC (Tile)',
        brand: 'Tile');
    id.alert('Rastreador');
  }
  if (svc.contains('fd5a')) {
    id.p('Rastreador Samsung SmartTag', 85, 'Service UUID 0xFD5A (Samsung)',
        brand: 'Samsung');
    id.alert('Rastreador');
  }
  if (svc.contains('fe33')) {
    id.p('Rastreador (Chipolo, probable)', 60, 'Service UUID 0xFE33',
        brand: 'Chipolo');
    id.alert('Rastreador');
  }
  final edd = d.svcData['feaa'];
  if (edd != null && edd.isNotEmpty) {
    final ft = edd[0];
    const frames = {0x00: 'UID', 0x10: 'URL', 0x20: 'TLM', 0x30: 'EID'};
    f['Eddystone'] = 'frame ${frames[ft] ?? '0x${ft.toRadixString(16)}'}';
    if (ft == 0x40 || ft == 0x41) {
      id.p('Rastreador (Find Hub de Google, probable)', 60,
          'Eddystone frame 0x${ft.toRadixString(16)}');
      id.alert('Rastreador');
    }
  }

  for (final r in kSvcRules) {
    if (svc.contains(r.uuid))
      id.p(r.type, r.conf, 'Servicio 0x${r.uuid}', brand: r.brand);
  }

  if (d.appearance != null && d.appearance != 0) {
    final cat = d.appearance! >> 6;
    final nm = kAppearance[cat];
    f['Apariencia GAP'] = '${nm ?? 'categoría $cat'} (${h4(d.appearance!)})';
    if (nm != null) id.p(nm, 70, 'Apariencia GAP "$nm"');
  }

  if (name.isNotEmpty) {
    for (final r in kBleNameRules) {
      if (r.re.hasMatch(name)) {
        id.p(r.type, r.conf, 'Nombre "$name"');
        break;
      }
    }
  }

  if (id.conf == 0 && id.brand != null) {
    id.type = 'Dispositivo ${id.brand}';
    id.conf = 20;
  }
  return id;
}

Ident identifyWifi(Dev d, Db db, int sameSsid) {
  final id = Ident();
  final f = id.facts;
  final ssid = d.rawName;

  String? vendor;
  var vendorNote = '';
  if (!d.localAdmin) {
    vendor = db.vendorOf(d.id);
  } else {
    vendor = db.vendorOf(unLocal(d.id));
    if (vendor != null) {
      vendorNote =
          ' (deducido: OUI real al quitar el bit de administración local)';
    } else {
      for (final s in d.sibs) {
        if (s.localAdmin) continue;
        final v = db.vendorOf(s.id);
        if (v != null) {
          vendor = v;
          vendorNote = ' (heredado de otra radio del mismo equipo)';
          break;
        }
      }
    }
  }
  f['Fabricante (OUI)'] = vendor != null
      ? '$vendor$vendorNote'
      : (d.localAdmin
          ? 'BSSID administrado localmente: sin OUI real (SSID virtual/mesh, hotspot de celular o MAC aleatoria)'
          : (db.oui.isEmpty
              ? 'sin base OUI (menú ⋮ → Actualizar bases)'
              : 'OUI no registrado'));
  if (vendor != null) id.brand = vendor;

  var cam = 0;
  final camWhy = <String>[];
  var vendorCam = false, ssidCam = false;

  if (vendor != null) {
    for (final r in kWifiVendorRules) {
      if (r.re.hasMatch(vendor)) {
        id.p(r.type, r.conf, 'Fabricante "$vendor"', brand: vendor);
        if (r.tag == 'cam') {
          cam += 3;
          vendorCam = true;
          camWhy.add('fabricante de cámaras');
        } else if (r.tag == 'iot') {
          cam += 1;
          camWhy.add('chip IoT genérico (ESP)');
        } else if (r.tag == 'odm') {
          cam += 1;
          camWhy.add('fabricante ODM genérico');
        }
        break;
      }
    }
  }

  if (ssid.isNotEmpty) {
    f['SSID'] = ssid;
    for (final r in kWifiSsidRules) {
      if (r.re.hasMatch(ssid)) {
        id.p(r.type, r.conf, 'SSID "$ssid"');
        if (r.tag == 'cam') {
          cam += 3;
          ssidCam = true;
          camWhy.add('SSID típico de cámara');
        }
        break;
      }
    }
  } else {
    f['SSID'] = d.knownSsid != null
        ? '"${d.knownSsid}" (recordado de un escaneo anterior; hoy se anuncia oculta)'
        : '(oculto) — el nombre real no viaja en la señal: solo se ve en el router o en un equipo conectado';
    if (d.nearSsid != null) f['Mismo equipo que la red'] = '"${d.nearSsid}"';
    if (cam > 0) {
      cam += 1;
      camWhy.add('red oculta');
    }
  }

  final c = d.caps ?? '';
  final isOpen = !_secRe.hasMatch(c);
  final sec = <String>[];
  if (c.contains('SAE')) sec.add('WPA3');
  if (c.contains('WPA2') || c.contains('RSN')) sec.add('WPA2');
  if (RegExp(r'\[WPA-').hasMatch(c)) sec.add('WPA');
  if (c.contains('WEP')) sec.add('WEP (insegura)');
  if (c.contains('OWE')) sec.add('OWE (abierta cifrada)');
  if (c.contains('EAP')) sec.add('empresarial 802.1X');
  f['Seguridad'] = isOpen ? 'ABIERTA (sin contraseña)' : sec.join(' + ');
  if (c.contains('WPS')) f['WPS'] = 'activo (riesgo: PIN WPS)';
  if (c.contains('IBSS')) f['Modo'] = 'ad-hoc (IBSS)';
  if (c.isNotEmpty) f['Capacidades crudas'] = c;

  if (isOpen && cam > 0) {
    cam += 1;
    camWhy.add('red abierta');
  }
  if (cam > 0) f['Sospecha de cámara'] = '$cam/8 (${camWhy.join(', ')})';
  if (vendorCam || ssidCam) id.alert('Posible cámara');

  if (d.freq != null) {
    f['Banda / canal'] =
        '${bandOf(d.freq!)} · canal ${d.channel ?? '?'} · ${d.freq} MHz';
  }
  if (d.standard != null) f['Estándar'] = '802.11 ${d.standard}';
  if (d.width != null) f['Ancho de canal'] = d.width!;
  if (d.center0 != null) {
    f['Frecuencia central'] =
        '${d.center0} MHz${d.center1 != null && d.center1 != 0 ? ' / ${d.center1} MHz' : ''}';
  }
  if (d.mcResponder == true)
    f['802.11mc (RTT)'] = 'sí (AP con medición de distancia)';
  if (d.passpoint == true) f['Passpoint / Hotspot 2.0'] = 'sí';
  if (d.operatorName != null && d.operatorName!.isNotEmpty)
    f['Operador'] = d.operatorName!;
  if (d.venueName != null && d.venueName!.isNotEmpty) f['Sede'] = d.venueName!;
  if (sameSsid > 1)
    f['Otras redes con el mismo SSID'] =
        '${sameSsid - 1} (mesh, repetidor o doble banda)';

  if (id.conf == 0) {
    id.type = vendor != null ? 'Red Wi-Fi ($vendor)' : 'Red Wi-Fi';
    id.conf = 10;
  }
  return id;
}

IconData iconForType(String type, bool wifi) {
  final t = type.toLowerCase();
  bool has(String s) => t.contains(s);
  if (has('gafas')) return Icons.visibility;
  if (has('rastreador') || has('etiqueta') || has('llavero'))
    return Icons.location_searching;
  if (has('cámara')) return Icons.videocam;
  if (has('auricular') || has('audio')) return Icons.headphones;
  if (has('parlante') || has('altavoz')) return Icons.speaker;
  if (has('reloj') || has('pulsera') || has('pulsómetro')) return Icons.watch;
  if (has('teléfono') ||
      has('celular') ||
      has('iphone') ||
      has('android') ||
      has('tablet') ||
      has('ipad')) {
    return Icons.smartphone;
  }
  if (has('computadora') ||
      has('windows') ||
      has('linux') ||
      has('laptop') ||
      has('raspberry')) {
    return Icons.computer;
  }
  if (has('tv') || has('pantalla') || has('airplay')) return Icons.tv;
  if (has('router') || has('punto de acceso') || has('starlink'))
    return Icons.router;
  if (has('impresora')) return Icons.print;
  if (has('periférico') || has('teclado')) return Icons.keyboard;
  if (has('beacon')) return Icons.sensors;
  if (has('iot')) return Icons.memory;
  if (has('apple')) return Icons.devices;
  return wifi ? Icons.wifi : Icons.bluetooth;
}

IconData iconFor(Dev d) => iconForType(d.ident.type, d.type == DevType.wifi);

// ═══════════════════════ MODELOS ═══════════════════════

enum DevType { wifi, ble }

class Sample {
  final double lat, lon, rssi;
  final DateTime t;
  Sample(this.lat, this.lon, this.rssi, this.t);
}

class TP {
  final double lat, lon;
  final int t;
  TP(this.lat, this.lon, this.t);
}

class Dev {
  final String id;
  final DevType type;
  String rawName = '';
  int rssi = -100;
  double smooth = -100;
  int updates = 0;
  int minRssi = 0, maxRssi = -200;
  double rssiSum = 0;
  final List<double> history = [];
  DateTime firstSeen;
  DateTime lastSeen;
  DateTime? lastAdv, identAt, lastLogAt;
  int? lastStamp;
  double? intervalMs;
  double? bestRssi, bestLat, bestLon;
  Ident ident = Ident();
  bool mine = false, follows = false;
  List<Dev> sibs = [];
  int merged = 0; // direcciones BLE anteriores unificadas (rotación de MAC)
  String? knownSsid,
      nearSsid; // nombre recordado / de otra radio del mismo equipo (redes ocultas)
  String? gattName; // nombre leído por GATT (BLE)
  double? stMin, stMax; // rango de señal mientras yo estaba quieto

  // calibración de pérdida (log-distancia), a partir de un ancla manual
  double? fitP0, fitN, fitSd;
  int fitNum = 0;
  final List<(double, double)> calSamples = [];

  // Wi-Fi
  int? freq, channel, center0, center1;
  String? width, caps, standard, operatorName, venueName;
  bool? mcResponder, passpoint;

  // BLE
  BluetoothDevice? device;
  int? txPower, appearance, calTx;
  bool? connectable;
  Map<int, List<int>> mfrData = {};
  Map<String, List<int>> svcData = {};
  List<String> svcUuids = [];
  String? gatt;
  bool gattBusy = false;

  Dev(this.id, this.type, DateTime now)
      : firstSeen = now,
        lastSeen = now;

  /// Dirección BLE privada resolvible: cambia cada ~15 min, no sirve para seguir por ID.
  bool get rotating {
    if (type != DevType.ble || !id.contains(':')) return false;
    final b = int.tryParse(id.substring(0, 2), radix: 16);
    return b != null && (b >> 6) == 1;
  }

  List<String> get alerts =>
      mine ? const [] : [...ident.alerts, if (follows) 'Te sigue'];

  String get title {
    if (rawName.isNotEmpty) return rawName;
    if (type == DevType.wifi) {
      if (knownSsid != null) return '$knownSsid (oculta)';
      final tail = id.length >= 5 ? id.substring(id.length - 5) : id;
      if (nearSsid != null) return '(oculta) junto a "$nearSsid" · $tail';
      final label = ident.conf >= 50
          ? ident.type
          : (ident.brand != null ? shortBrand(ident.brand!) : null);
      return label != null ? '(oculta) $label · $tail' : '(oculta) · $tail';
    }
    if (gattName != null && gattName!.isNotEmpty) return gattName!;
    if (ident.model != null) return ident.model!;
    if (ident.brand != null) return '${ident.brand} (sin nombre)';
    return 'BLE sin nombre';
  }

  void addReading(int r, DateTime now) {
    rssi = r;
    smooth = updates == 0 ? r.toDouble() : smooth * 0.7 + r * 0.3;
    if (updates == 0) {
      minRssi = r;
      maxRssi = r;
    } else {
      minRssi = min(minRssi, r);
      maxRssi = max(maxRssi, r);
    }
    rssiSum += r;
    updates++;
    lastSeen = now;
    history.add(smooth);
    if (history.length > 60) history.removeAt(0);
  }

  int get level =>
      smooth > -50 ? 3 : (smooth > -65 ? 2 : (smooth > -80 ? 1 : 0));

  double get distance {
    if (fitP0 != null && fitN != null) {
      return pow(10, (fitP0! - smooth) / (10 * fitN!))
          .toDouble()
          .clamp(0.1, 300.0)
          .toDouble();
    }
    double d;
    if (type == DevType.wifi && freq != null) {
      final f = 27.55 - 20 * (log(freq!) / ln10) - smooth;
      d = pow(10, f / 20).toDouble();
    } else {
      final int ref = calTx ?? (txPower != null ? txPower! - 41 : -59);
      d = pow(10, (ref - smooth) / (10 * 2.5)).toDouble();
    }
    return d.clamp(0.1, 200.0).toDouble();
  }

  double? get trend {
    final n = history.length;
    if (n < 8) return null;
    final recent = history.sublist(n - 4).reduce((a, b) => a + b) / 4;
    final prev = history.sublist(n - 8, n - 4).reduce((a, b) => a + b) / 4;
    return recent - prev;
  }

  bool get localAdmin {
    if (id.length < 2) return false;
    final b = int.tryParse(id.substring(0, 2), radix: 16);
    return b != null && (b & 0x02) != 0;
  }
}

// ───── historial persistente ─────

/// Una "visita": período continuo en que escuché al dispositivo.
class Visit {
  int t0, t1;
  int n = 0;
  double best = -200, sw = 0, sla = 0, slo = 0;
  double? mnLa, mxLa, mnLo, mxLo;

  Visit(this.t0) : t1 = t0;

  double get cLat => sw > 0 ? sla / sw : 0.0;
  double get cLon => sw > 0 ? slo / sw : 0.0;

  /// Distancia máxima entre posiciones mías desde las que lo oí fuerte (>= -75 dBm).
  double get span => mnLa == null
      ? 0.0
      : Geolocator.distanceBetween(mnLa!, mnLo!, mxLa!, mxLo!);

  void add(double lat, double lon, double rssi, int t) {
    t1 = t;
    n++;
    if (rssi > best) best = rssi;
    final w = pow(10, rssi / 10).toDouble();
    sw += w;
    sla += lat * w;
    slo += lon * w;
    if (rssi >= -75) {
      mnLa = mnLa == null ? lat : min(mnLa!, lat);
      mxLa = mxLa == null ? lat : max(mxLa!, lat);
      mnLo = mnLo == null ? lon : min(mnLo!, lon);
      mxLo = mxLo == null ? lon : max(mxLo!, lon);
    }
  }

  Map<String, dynamic> toJson() => {
        'a': t0,
        'b': t1,
        'n': n,
        'r': best,
        'w': sw,
        'x': sla,
        'y': slo,
        'p': mnLa,
        'q': mxLa,
        'u': mnLo,
        'v': mxLo,
      };

  factory Visit.fromJson(Map<String, dynamic> j) {
    final v = Visit((j['a'] as num).toInt());
    v.t1 = (j['b'] as num).toInt();
    v.n = (j['n'] as num).toInt();
    v.best = (j['r'] as num).toDouble();
    v.sw = (j['w'] as num).toDouble();
    v.sla = (j['x'] as num).toDouble();
    v.slo = (j['y'] as num).toDouble();
    v.mnLa = (j['p'] as num?)?.toDouble();
    v.mxLa = (j['q'] as num?)?.toDouble();
    v.mnLo = (j['u'] as num?)?.toDouble();
    v.mxLo = (j['v'] as num?)?.toDouble();
    return v;
  }
}

class Known {
  final String id, kind; // kind: 'wifi' | 'ble'
  String title = '', cls = '';
  String? brand;
  bool mine = false, alert = false;
  int first, last, seen = 0;
  List<Visit> visits = [];
  double? ax, ay; // ancla manual (posición real fijada por vos)
  double? p0, pn, psd; // modelo de pérdida calibrado
  int pnum = 0;

  Known(this.id, this.kind, this.first) : last = first;

  Map<String, dynamic> toJson() => {
        'id': id,
        'k': kind,
        't': title,
        'c': cls,
        'b': brand,
        'm': mine ? 1 : 0,
        'al': alert ? 1 : 0,
        'f': first,
        'l': last,
        's': seen,
        'ax': ax,
        'ay': ay,
        'p0': p0,
        'pn': pn,
        'ps': psd,
        'pk': pnum,
        'v': visits.map((v) => v.toJson()).toList(),
      };

  factory Known.fromJson(Map<String, dynamic> j) {
    final k =
        Known(j['id'] as String, j['k'] as String, (j['f'] as num).toInt());
    k.title = (j['t'] as String?) ?? '';
    k.cls = (j['c'] as String?) ?? '';
    k.brand = j['b'] as String?;
    k.mine = j['m'] == 1;
    k.alert = j['al'] == 1;
    k.last = (j['l'] as num).toInt();
    k.seen = (j['s'] as num).toInt();
    k.ax = (j['ax'] as num?)?.toDouble();
    k.ay = (j['ay'] as num?)?.toDouble();
    k.p0 = (j['p0'] as num?)?.toDouble();
    k.pn = (j['pn'] as num?)?.toDouble();
    k.psd = (j['ps'] as num?)?.toDouble();
    k.pnum = (j['pk'] as num?)?.toInt() ?? 0;
    k.visits = [
      for (final v in (j['v'] as List))
        Visit.fromJson(v as Map<String, dynamic>)
    ];
    return k;
  }
}

class Est {
  final double lat, lon, radius;
  final String status; // fijo | sin confirmar | móvil | incierto
  final int visits;
  final bool anchor;
  const Est(this.lat, this.lon, this.radius, this.status, this.visits,
      [this.anchor = false]);
}

/// Posición estimada + estado (fijo / móvil) a partir de las visitas.
Est? estimateOf(Known k) {
  if (k.ax != null && k.ay != null) {
    return Est(k.ax!, k.ay!, 3.0, 'fijo', max(1, k.visits.length), true);
  }
  final vs = k.visits.where((v) => v.n >= 2 && v.sw > 0).toList();
  if (vs.isEmpty) return null;
  double sn = 0, la = 0, lo = 0;
  for (final v in vs) {
    sn += v.n;
    la += v.cLat * v.n;
    lo += v.cLon * v.n;
  }
  final mLa = la / sn, mLo = lo / sn;
  var spread = 0.0;
  var r1 = 0.0;
  for (final v in vs) {
    spread = max(spread, Geolocator.distanceBetween(mLa, mLo, v.cLat, v.cLon));
    r1 += pow(10, (-50 - v.best) / 25).toDouble().clamp(4.0, 60.0).toDouble();
  }
  r1 /= vs.length;
  final radius = max(6.0, r1 / sqrt(vs.length)) + spread;
  String status;
  if (vs.length >= 2) {
    status = spread <= 25 ? 'fijo' : (spread > 60 ? 'móvil' : 'incierto');
  } else {
    status = vs.first.span >= 60 ? 'móvil' : 'sin confirmar';
  }
  return Est(mLa, mLo, radius, status, vs.length);
}

String statusText(Est e) {
  if (e.anchor)
    return 'Posición fijada por vos (ancla manual, ±${e.radius.round()} m).';
  switch (e.status) {
    case 'fijo':
      return 'Lo viste en ${e.visits} visitas y siempre en el mismo lugar (±${e.radius.round()} m): es un equipo fijo.';
    case 'sin confirmar':
      return 'Lo viste una sola vez en esa zona; pasá otra vez más tarde para confirmar si es fijo.';
    case 'móvil':
      return 'Aparece en lugares distintos o viaja con vos: se mueve.';
    default:
      return 'Aparece en lugares algo distintos (GPS impreciso o equipo que cambió de lugar).';
  }
}

/// (0 verde, 1 ámbar, 2 rojo, motivo)
(int, String) riskOf(Dev d) {
  if (d.alerts.isNotEmpty) return (2, d.alerts.join(', '));
  if (d.type == DevType.wifi) {
    final c = d.caps ?? '';
    if (c.contains('WEP')) return (1, 'cifrado WEP, inseguro');
    if (isOpenWifi(d)) return (1, 'red abierta, sin contraseña');
    if (c.contains('WPS')) return (1, 'WPS activo');
  }
  return (0, 'sin hallazgos');
}

/// Resumen en lenguaje natural, generado con reglas (sin internet).
String summarize(Dev d, Est? est) {
  final i = d.ident;
  final parts = <String>[];
  final dist = d.distance;
  final prox = dist < 2
      ? 'a tu lado'
      : (dist < 6
          ? 'muy cerca'
          : (dist < 15
              ? 'cerca'
              : (dist < 40 ? 'a media distancia' : 'lejos')));

  if (d.type == DevType.wifi) {
    final hidden = d.rawName.isEmpty;
    final band = d.freq != null ? ', ${bandOf(d.freq!)}' : '';
    final head = hidden
        ? (d.knownSsid != null
            ? 'Red Wi-Fi oculta (antes vista como "${d.knownSsid}")'
            : 'Red Wi-Fi oculta')
        : 'Red "${d.rawName}"';
    parts.add('$head (${wifiGen(d.standard)}$band).');
    if (hidden && d.nearSsid != null) {
      parts.add('Está en el mismo equipo que la red "${d.nearSsid}".');
    }
    if (i.conf >= 50) {
      parts.add(
          'Parece ser: ${i.type}${i.brand != null ? ' de ${i.brand}' : ''}.');
    } else if (i.brand != null) {
      parts.add('Fabricante: ${i.brand}.');
    }
    if (d.localAdmin) {
      parts.add(i.brand == null
          ? 'Usa una MAC virtual o aleatoria: típico de la red secundaria de un router o mesh, un repetidor o el hotspot de un celular.'
          : 'Usa una MAC virtual derivada de un equipo ${i.brand}.');
    }
    if (d.sibs.isNotEmpty) {
      final l = d.sibs
          .take(4)
          .map((s) => '${bandOf(s.freq ?? 2412)} ch${s.channel ?? '?'}')
          .join(', ');
      parts.add('Comparte equipo con ${d.sibs.length} radio(s) más: $l.');
    }
    final c = d.caps ?? '';
    if (isOpenWifi(d)) {
      parts.add('Es una red ABIERTA (sin contraseña).');
    } else if (c.contains('WEP')) {
      parts.add('Usa cifrado WEP, que es inseguro.');
    } else if (c.contains('SAE')) {
      parts.add('Seguridad moderna (WPA3).');
    }
    if (c.contains('WPS')) parts.add('Tiene WPS activo.');
  } else {
    parts.add(
        '${i.type}${i.brand != null && !i.type.contains(i.brand!) ? ' de ${i.brand}' : ''}${i.model != null ? ' (${i.model})' : ''}.');
    parts.add(i.conf >= 70
        ? 'Identificación con buena confianza.'
        : (i.conf >= 40
            ? 'Identificación probable, no segura.'
            : 'No pude identificarlo con certeza: anuncia poca información.'));
    if (d.rotating) {
      parts.add(
          'Cambia de dirección cada ~15 min (privacidad): no se puede seguir por ID, típico de celulares, relojes y accesorios.');
    } else if (d.id.contains(':')) {
      parts.add('Dirección estable: se puede ubicar en el mapa.');
    }
    final bat = i.facts['Batería (aprox.)'];
    if (bat != null) parts.add('Batería: $bat.');
    if (i.alerts.contains('Rastreador')) {
      parts.add(
          'Es un rastreador: si no es tuyo y aparece contigo en distintos lugares, revísalo.');
    }
  }

  parts.add(
      'Está $prox (~${dist.toStringAsFixed(0)} m, señal ${d.smooth.round()} dBm).');
  if (d.updates >= 4) {
    final range = d.maxRssi - d.minRssi;
    parts.add(range <= 4
        ? 'La señal casi no varía: tú o el equipo están quietos.'
        : 'La señal varía $range dB: te estás moviendo o hay obstáculos.');
  }
  if (d.stMin != null && d.stMax != null) {
    final rg = d.stMax! - d.stMin!;
    if (rg >= 8) {
      parts.add(
          'Con vos quieto la señal varió ${rg.round()} dB: el equipo o algo entre ustedes se mueve.');
    } else if (rg <= 3 && d.updates >= 10) {
      parts.add('Con vos quieto la señal fue estable: equipo fijo.');
    }
  }
  if (est != null) parts.add(statusText(est));
  if (d.alerts.isNotEmpty) parts.add('⚠ ${d.alerts.join(', ')}.');
  if (d.mine) parts.add('Lo marcaste como tuyo.');
  return parts.join(' ');
}

// ═══════════════════════ PANTALLA ═══════════════════════

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final Map<String, Dev> _devs = {};
  final Map<String, String> _warnings = {};
  final List<Sample> _samples = [];
  final Set<String> _alerted = {};
  final Db db = Db();

  // anclas, mapa y avisos
  final GpsFilter _gps = GpsFilter();
  final CachedClient _tileClient = CachedClient();
  int _mapStyle = 0;
  bool _dlBusy = false, _dlCancel = false;
  int _dlDone = 0, _dlTotal = 0, _dlOk = 0, _dlFail = 0;
  String? _dlErr;
  String? _anchorFor;
  final Set<String> _dismissed = {};
  final Set<String> _alertsHidden = {};
  bool _showWarn = true, _showAlertBanner = true;

  // GPS y memoria de nombres
  String _gpsMsg = 'buscando…';
  bool _bgBroken = false;
  bool _autoCentered = false;
  final Map<String, String> _ssidMem = {};
  DateTime _lastMerge = DateTime.fromMillisecondsSinceEpoch(0);

  // sensores de movimiento y brújula
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  final List<double> _accWin = [];
  double _grav = 9.8, _prevDyn = 0;
  DateTime _lastStep = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMove = DateTime.now();
  DateTime? _stillSince;
  bool _still = false;
  int _steps = 0;
  double? _heading;
  double _hx = 0, _hy = 0;
  bool _hInit = false;
  double _gyroRate = 0;
  DateTime _lastGyro = DateTime.now();
  DateTime _lastRadar = DateTime.fromMillisecondsSinceEpoch(0);
  final ValueNotifier<int> _radarTick = ValueNotifier<int>(0);
  bool _sweep = false;
  double _rotAcc = 0;
  final List<double> _binSum = List<double>.filled(36, 0.0);
  final List<int> _binN = List<int>.filled(36, 0);
  double? _bestBearing;
  double _contrast = 0;
  String? _sweepMsg;
  final List<Bearing> _bearings = [];

  // segundo plano y notificaciones
  bool _bg = true;
  bool _appActive = true;
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  bool _notifReady = false;
  DateTime _lastNotif = DateTime.fromMillisecondsSinceEpoch(0);

  // historial y mapa
  final Map<String, Known> _known = {};
  final List<TP> _track = [];
  bool _logDirty = false, _saving = false;
  DateTime _lastSave = DateTime.now();
  DateTime _lastFixedCalc = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _mapAt = DateTime.fromMillisecondsSinceEpoch(0);
  final DateTime _startedAt = DateTime.now();
  int _fixedNear = 0;
  final MapController _mapCtl = MapController();
  bool _mapReady = false;
  String? _mapSel;
  bool _showFixed = true,
      _showUnconf = true,
      _showMobile = false,
      _showTrack = true;
  List<Known> _mapItems = [];
  Map<String, Est> _mapEst = {};

  Pt? _pos;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<List<ScanResult>>? _bleSub;
  StreamSubscription<List<WiFiAccessPoint>>? _wifiSub;
  Timer? _uiTimer, _wifiTimer, _geigerTimer;

  bool _scanning = false;
  bool _dirty = false;
  bool _hasLoc = false;
  int _tab = 0;

  String _filter = 'todos'; // todos | wifi | ble | alert
  String _query = '';
  bool _sortSignal = true;

  String? _targetId;
  bool _geiger = false;
  bool _sound = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uiTimer = Timer.periodic(const Duration(milliseconds: 500), _tickUi);
    _startAccel();
    _loadLog();
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveLog();
    _uiTimer?.cancel();
    _wifiTimer?.cancel();
    _geigerTimer?.cancel();
    _posSub?.cancel();
    _bleSub?.cancel();
    _wifiSub?.cancel();
    _accSub?.cancel();
    _compassSub?.cancel();
    _gyroSub?.cancel();
    _radarTick.dispose();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) _dirty = true;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) _saveLog();
  }

  void _snack(String m) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ───── notificaciones ─────

  Future<void> _initNotifications() async {
    try {
      await _notif.initialize(
        const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      _notifReady = true;
    } catch (_) {}
  }

  Future<void> _notify(String title, String body) async {
    if (!_notifReady) return;
    try {
      final id = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 100000 + 10;
      await _notif.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'radar_alerts',
            'Alertas de Radar',
            channelDescription:
                'Rastreadores, gafas, posibles cámaras y dispositivos que te siguen',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }

  // ───── sensores: movimiento, brújula y barrido de rumbo ─────

  void _startAccel() {
    try {
      _accSub = accelerometerEventStream(
              samplingPeriod: const Duration(milliseconds: 50))
          .listen(_onAccel, onError: (Object _) {});
    } catch (_) {}
  }

  void _onAccel(AccelerometerEvent e) {
    final m = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _accWin.add(m);
    if (_accWin.length > 30) _accWin.removeAt(0);
    _grav = _grav * 0.95 + m * 0.05;
    final dyn = m - _grav;
    final now = DateTime.now();
    if (dyn > 1.4 &&
        _prevDyn <= 1.4 &&
        now.difference(_lastStep).inMilliseconds > 300) {
      _steps++;
      _lastStep = now;
    }
    _prevDyn = dyn;
    if (_accWin.length < 20) return;
    final mean = _accWin.reduce((a, b) => a + b) / _accWin.length;
    var v = 0.0;
    for (final x in _accWin) {
      v += (x - mean) * (x - mean);
    }
    final sd = sqrt(v / _accWin.length);
    if (sd > 0.5) _lastMove = now;
    final still = sd < 0.25 && now.difference(_lastMove).inSeconds >= 2;
    if (still != _still) {
      _still = still;
      _stillSince = still ? now : null;
      if (!still) {
        _gps.inflate();
        for (final d in _devs.values) {
          d.stMin = null;
          d.stMax = null;
        }
      }
      _dirty = true;
    }
  }

  /// La brújula y el giroscopio solo corren mientras estás en el Cazador con un objetivo.
  void _syncSensors() {
    final need = _tab == 1 && _targetId != null;
    if (need) {
      if (_compassSub == null) {
        try {
          final ev = FlutterCompass.events;
          if (ev == null) {
            _sweepMsg = 'Este equipo no tiene brújula';
          } else {
            _compassSub = ev.listen(_onCompass, onError: (Object _) {});
          }
        } catch (_) {}
      }
      if (_gyroSub == null) {
        try {
          _gyroSub = gyroscopeEventStream(
                  samplingPeriod: const Duration(milliseconds: 50))
              .listen(_onGyro, onError: (Object _) {});
        } catch (_) {}
      }
    } else {
      _compassSub?.cancel();
      _compassSub = null;
      _gyroSub?.cancel();
      _gyroSub = null;
      _heading = null;
      _hInit = false;
      _sweep = false;
    }
  }

  void _onCompass(CompassEvent e) {
    final h = e.heading;
    if (h == null) return;
    final r = h * pi / 180;
    if (!_hInit) {
      _hx = cos(r);
      _hy = sin(r);
      _hInit = true;
    } else {
      _hx = _hx * 0.75 + cos(r) * 0.25;
      _hy = _hy * 0.75 + sin(r) * 0.25;
    }
    _heading = (atan2(_hy, _hx) * 180 / pi + 360) % 360;
    final now = DateTime.now();
    if (now.difference(_lastRadar).inMilliseconds > 66) {
      _lastRadar = now;
      _radarTick.value++;
    }
  }

  void _onGyro(GyroscopeEvent e) {
    final w = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _gyroRate = _gyroRate * 0.7 + w * 0.3;
    final now = DateTime.now();
    final dt = (now.difference(_lastGyro).inMilliseconds / 1000.0)
        .clamp(0.0, 0.2)
        .toDouble();
    _lastGyro = now;
    if (_sweep) {
      _rotAcc += w * dt * 180 / pi;
      if (_rotAcc >= 400) _finishSweep();
    }
  }

  void _startSweep() {
    final t = _target;
    if (t == null) return;
    if (t.type == DevType.wifi) {
      _snack(
          'Wi-Fi se actualiza cada ~35 s: para el barrido elegí un objetivo BLE');
      return;
    }
    if (_heading == null) {
      _snack(
          'Todavía no hay brújula: movela dibujando un ocho para calibrarla');
      return;
    }
    setState(() {
      _sweep = true;
      _rotAcc = 0;
      for (var i = 0; i < 36; i++) {
        _binSum[i] = 0;
        _binN[i] = 0;
      }
      _bestBearing = null;
      _contrast = 0;
      _sweepMsg = null;
    });
  }

  void _sweepSample(Dev d) {
    final h = _heading;
    if (!_sweep || h == null || _gyroRate > 1.0) return;
    final b = ((((h % 360) + 360) % 360) / 10).floor().clamp(0, 35).toInt();
    _binSum[b] += d.rssi;
    _binN[b]++;
  }

  void _finishSweep() {
    _sweep = false;
    final avg = List<double?>.generate(
        36, (i) => _binN[i] == 0 ? null : _binSum[i] / _binN[i]);
    final sm = List<double?>.filled(36, null);
    for (var i = 0; i < 36; i++) {
      var s = 0.0;
      var n = 0;
      for (final o in const [-1, 0, 1]) {
        final v = avg[(i + o + 36) % 36];
        if (v != null) {
          s += v;
          n++;
        }
      }
      sm[i] = n == 0 ? null : s / n;
    }
    final vals = sm.whereType<double>().toList();
    if (vals.length < 12) {
      _sweepMsg =
          'Muy pocos datos (${vals.length} de 36 sectores). Girá más lento y repetí; el objetivo debe ser BLE y estar anunciando.';
      _bestBearing = null;
      if (mounted) setState(() {});
      return;
    }
    var bi = 0;
    var bv = -999.0;
    for (var i = 0; i < 36; i++) {
      final v = sm[i];
      if (v != null && v > bv) {
        bv = v;
        bi = i;
      }
    }
    final sorted = [...vals]..sort();
    final median = sorted[sorted.length ~/ 2];
    _contrast = bv - median;
    // refinamiento: promedio vectorial ponderado por potencia alrededor del pico (±40°)
    var ex = 0.0, ny = 0.0;
    for (var i = 0; i < 36; i++) {
      final v = sm[i];
      if (v == null) continue;
      var diff = ((i - bi).abs() * 10).toDouble();
      if (diff > 180) diff = 360 - diff;
      if (diff > 40) continue;
      final w = pow(10, (v - bv) / 10).toDouble();
      final a = (i * 10 + 5) * pi / 180;
      ex += w * sin(a);
      ny += w * cos(a);
    }
    final best = (atan2(ex, ny) * 180 / pi + 360) % 360;
    _bestBearing = best;
    if (_contrast < 4) {
      _sweepMsg =
          'Sin dirección clara (contraste ${_contrast.toStringAsFixed(0)} dB): estás muy cerca, hay rebotes o el aparato está tapado. Alejate un poco y repetí.';
    } else {
      _sweepMsg = null;
      final p = _pos;
      if (p != null) {
        _bearings.add(Bearing(p.latitude, p.longitude,
            (best + kDeclinationDeg + 360) % 360, _contrast));
        if (_bearings.length > 6) _bearings.removeAt(0);
      }
    }
    if (mounted) setState(() {});
  }

  /// Punto que minimiza la distancia a todos los rayos (mínimos cuadrados).
  (double, double)? _triangulate() {
    final bs = _bearings;
    if (bs.length < 2) return null;
    final lat0 = bs.first.lat, lon0 = bs.first.lon;
    final k = cos(lat0 * pi / 180);
    double xo(Bearing b) => (b.lon - lon0) * 111320 * k;
    double yo(Bearing b) => (b.lat - lat0) * 110540;
    double a11 = 0, a12 = 0, a22 = 0, b1 = 0, b2 = 0;
    for (final b in bs) {
      final th = b.deg * pi / 180;
      final dx = sin(th), dy = cos(th);
      final m11 = 1 - dx * dx, m12 = -dx * dy, m22 = 1 - dy * dy;
      final px = xo(b), py = yo(b);
      a11 += m11;
      a12 += m12;
      a22 += m22;
      b1 += m11 * px + m12 * py;
      b2 += m12 * px + m22 * py;
    }
    final det = a11 * a22 - a12 * a12;
    if (det.abs() < 0.1) return null; // rayos casi paralelos
    final x = (a22 * b1 - a12 * b2) / det;
    final y = (a11 * b2 - a12 * b1) / det;
    for (final b in bs) {
      final th = b.deg * pi / 180;
      final t = (x - xo(b)) * sin(th) + (y - yo(b)) * cos(th);
      if (t < 0) return null; // el punto quedaría detrás de algún rumbo
    }
    return (lat0 + y / 110540, lon0 + x / (111320 * k));
  }

  Widget _radarView() {
    final bins = List<double?>.generate(
        36, (i) => _binN[i] == 0 ? null : _binSum[i] / _binN[i]);
    final h = _heading;
    final best = _bestBearing;
    return Column(children: [
      SizedBox(
          width: 260,
          height: 260,
          child: CustomPaint(painter: RadarPainter(bins, h, best))),
      const SizedBox(height: 6),
      if (_sweep)
        Text(
          'Barriendo… ${_rotAcc.round()}° girados · ${bins.whereType<double>().length}/36 sectores${_gyroRate > 1.0 ? ' · MÁS LENTO' : ''}',
          style: TextStyle(
              color: _gyroRate > 1.0 ? Colors.redAccent : Colors.cyanAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold),
        )
      else if (best != null && h != null)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Transform.rotate(
            angle: (best - h) * pi / 180,
            child: const Icon(Icons.navigation,
                size: 44, color: Colors.amberAccent),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Mejor rumbo ${best.round()}° ${cardinal(best)} · contraste ${_contrast.toStringAsFixed(0)} dB\nGirá hasta que la flecha apunte arriba',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
            ),
          ),
        ])
      else
        Text(
          h == null
              ? 'Brújula: sin datos (movela dibujando un ocho)'
              : 'Rumbo actual ${h.round()}° ${cardinal(h)}',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
    ]);
  }

  // ───── historial: guardar / cargar ─────

  Future<File?> _logFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/signal_hunter_log.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadLog() async {
    try {
      final f = await _logFile();
      if (f == null || !await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      for (final e in (m['known'] as List)) {
        final k = Known.fromJson(e as Map<String, dynamic>);
        _known[k.id] = k;
      }
      for (final t in (m['track'] as List)) {
        _track.add(TP((t[0] as num).toDouble(), (t[1] as num).toDouble(),
            (t[2] as num).toInt()));
      }
      final sm = m['ssid'];
      if (sm is Map) {
        sm.forEach((k, v) => _ssidMem[k.toString()] = v.toString());
      }
      final savedBg = (m['bg'] ?? 1) == 1;
      _showWarn = (m['hw'] ?? 1) == 1;
      _showAlertBanner = (m['hb'] ?? 1) == 1;
      _mapStyle = ((m['ms'] ?? 0) as num)
          .toInt()
          .clamp(0, kMapStyles.length - 1)
          .toInt();
      if (savedBg != _bg) {
        _bg = savedBg;
        unawaited(_initLocation());
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _pruneKnown() {
    final cut =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    _known.removeWhere((id, k) =>
        !k.mine && k.ax == null && k.visits.length <= 1 && k.last < cut);
    if (_known.length > 3000) {
      final l = _known.values.where((k) => !k.mine && k.ax == null).toList()
        ..sort((a, b) => a.last.compareTo(b.last));
      for (final k in l.take(_known.length - 3000)) {
        _known.remove(k.id);
      }
    }
  }

  Future<void> _saveLog() async {
    if (_saving) return;
    _saving = true;
    try {
      _pruneKnown();
      final f = await _logFile();
      if (f == null) return;
      final data = {
        'v': 1,
        'bg': _bg ? 1 : 0,
        'hw': _showWarn ? 1 : 0,
        'hb': _showAlertBanner ? 1 : 0,
        'ms': _mapStyle,
        'ssid': _ssidMem,
        'known': _known.values.map((k) => k.toJson()).toList(),
        'track': _track.map((t) => [t.lat, t.lon, t.t]).toList(),
      };
      await f.writeAsString(jsonEncode(data));
      _logDirty = false;
      _lastSave = DateTime.now();
    } catch (_) {
    } finally {
      _saving = false;
    }
  }

  void _addTrack(Pt p) {
    if (p.accuracy > 40) return;
    if (_track.isNotEmpty) {
      final l = _track.last;
      if (Geolocator.distanceBetween(l.lat, l.lon, p.latitude, p.longitude) < 5)
        return;
    }
    _track.add(
        TP(p.latitude, p.longitude, DateTime.now().millisecondsSinceEpoch));
    if (_track.length > 4000) _track.removeRange(0, 1000);
    _logDirty = true;
  }

  /// Registra una observación del dispositivo con mi posición (para el mapa y "te sigue").
  void _log(Dev d, DateTime now) {
    final p = _pos;
    if (p == null || p.accuracy > 40 || d.rssi < -90) return;
    if (d.type == DevType.ble && d.rotating && d.ident.alerts.isEmpty) return;
    if (d.lastLogAt != null &&
        now.difference(d.lastLogAt!).inMilliseconds < (_still ? 10000 : 2000))
      return;
    d.lastLogAt = now;
    final nowMs = now.millisecondsSinceEpoch;
    final k = _known.putIfAbsent(d.id,
        () => Known(d.id, d.type == DevType.wifi ? 'wifi' : 'ble', nowMs));
    k.title = d.title;
    k.cls = d.ident.type;
    k.brand = d.ident.brand;
    k.alert = d.ident.alerts.isNotEmpty;
    k.last = nowMs;
    k.seen++;
    final gapMs = (d.type == DevType.wifi ? 15 : 10) * 60000;
    Visit v;
    if (k.visits.isEmpty || nowMs - k.visits.last.t1 > gapMs) {
      v = Visit(nowMs);
      k.visits.add(v);
      if (k.visits.length > 12) k.visits.removeAt(0);
    } else {
      v = k.visits.last;
    }
    v.add(p.latitude, p.longitude, d.rssi.toDouble(), nowMs);
    if (k.p0 != null && d.fitP0 == null) {
      d.fitP0 = k.p0;
      d.fitN = k.pn;
      d.fitSd = k.psd;
      d.fitNum = k.pnum;
    }
    _calibSample(d, k, p);
    d.mine = k.mine;
    d.follows = d.type == DevType.ble &&
        !k.mine &&
        v.span >= 150 &&
        (v.t1 - v.t0) >= 8 * 60000;
    _logDirty = true;
  }

  // ───── arranque ─────

  void _setWarn(String key, String? msg) {
    if (msg == null) {
      _warnings.remove(key);
      _dismissed.remove(key);
    } else {
      _warnings[key] = msg;
    }
    _dirty = true;
  }

  Future<bool> _ensurePermissions() async {
    final res = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
      Permission.notification,
    ].request();
    final loc = res[Permission.locationWhenInUse]?.isGranted ?? false;
    _setWarn(
      'perm',
      loc
          ? null
          : 'Falta el permiso de ubicación: sin él Android no entrega resultados de Wi-Fi ni BLE. Toca aquí para abrir Ajustes.',
    );
    _setWarn(
      'notif',
      (res[Permission.notification]?.isGranted ?? true)
          ? null
          : 'Sin permiso de notificaciones: las alertas no se verán con la pantalla apagada (Ajustes → Apps → Notificaciones).',
    );
    return loc;
  }

  Future<void> _initLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _gpsMsg = 'la ubicación del teléfono está apagada';
        _setWarn('gps',
            'La ubicación del teléfono está apagada. Actívala: sin ella no hay escaneos ni GPS.');
      } else {
        _setWarn('gps', null);
        _gpsMsg = 'buscando satélites…';
      }
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _gpsMsg = 'sin permiso de ubicación';
        _dirty = true;
        return;
      }
      await _posSub?.cancel();
      // Con segundo plano activo, geolocator levanta un servicio en primer plano (notificación fija)
      // que mantiene viva la app con la pantalla apagada. Si Android lo rechaza, seguimos sin él.
      final useBg = _bg && !_bgBroken;
      final LocationSettings ls = useBg
          ? AndroidSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 1,
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: kAppName,
                notificationText: 'Escaneando señales en segundo plano',
                enableWakeLock: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.best, distanceFilter: 1);
      _posSub = Geolocator.getPositionStream(locationSettings: ls).listen(
        (p) {
          final f = _gps.update(p, still: _still);
          _pos = f;
          _gpsMsg = 'ok';
          if (_warnings.containsKey('gps')) _setWarn('gps', null);
          _dirty = true;
          _addTrack(f);
        },
        onError: (Object e) {
          final s = shortErr(e.toString());
          if (useBg) {
            _bgBroken = true;
            _gpsMsg = 'reintentando sin segundo plano…';
            _setWarn(
              'gps',
              'No pude iniciar el servicio en segundo plano ($s). Sigo sin él: revisá en el manifest FOREGROUND_SERVICE_LOCATION y los permisos de notificaciones.',
            );
            unawaited(_initLocation());
          } else {
            _gpsMsg = s;
            _setWarn('gps', 'GPS: $s');
          }
        },
      );
      unawaited(_gpsFallback());
    } catch (e) {
      _gpsMsg = shortErr(e.toString());
      _setWarn('gps', 'GPS: ${shortErr(e.toString())}');
    }
  }

  /// Si el stream tarda en dar posición: última conocida y, a los 15 s, una lectura puntual.
  Future<void> _gpsFallback() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _pos == null) {
        _pos = _gps.update(last);
        _gpsMsg = 'última posición conocida (±${last.accuracy.round()} m)';
        _dirty = true;
      }
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 15));
    if (!mounted || _gpsMsg == 'ok') return;
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      _pos = _gps.update(p);
      _gpsMsg = 'ok';
      _setWarn('gps', null);
      _dirty = true;
    } catch (_) {
      if (_gpsMsg != 'ok') {
        _gpsMsg = 'sin señal GPS';
        _setWarn(
          'gps',
          'Sin posición GPS tras 35 s. Salí a cielo abierto, activá la ubicación de "alta precisión" y revisá que la app tenga permiso "mientras se usa".',
        );
      }
    }
  }

  Future<void> _retryGps() async {
    setState(() => _gpsMsg = 'reintentando…');
    _hasLoc = await _ensurePermissions();
    await _initLocation();
    if (mounted) setState(() {});
  }

  /// Comprueba que haya internet (mapas y bases). Distingue la falta del permiso INTERNET.
  Future<void> _checkNet({bool verbose = false}) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req =
          await c.getUrl(Uri.parse('https://tile.openstreetmap.org/0/0/0.png'));
      req.headers.set('User-Agent', 'flutter_map ($kTileAgent)');
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain();
      if (res.statusCode == 200) {
        _setWarn('net', null);
        if (verbose) _snack('Internet OK: mapas y bases disponibles');
      } else {
        _setWarn('net', 'Mapas: el servidor respondió ${res.statusCode}.');
        if (verbose) _snack('El servidor de mapas respondió ${res.statusCode}');
      }
    } catch (e) {
      final s = shortErr(e.toString());
      _setWarn(
        'net',
        'Sin internet para mapas y bases: $s. Si dice "Operation not permitted", falta el permiso INTERNET en AndroidManifest.xml.',
      );
      if (verbose) _snack('Sin internet: $s');
    } finally {
      c.close(force: true);
    }
  }

  Future<void> _loadDb({bool force = false}) async {
    db.loading = true;
    db.status = 'Descargando bases de datos…';
    if (mounted) setState(() {});
    await db.load(force: force);
    _reidentifyWifi();
    for (final d in _devs.values) {
      d.identAt = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    unawaited(_initNotifications());
    unawaited(_checkNet());
    unawaited(_loadDb());
    _hasLoc = await _ensurePermissions();
    await _initLocation();
    if (!mounted) return;
    if (_hasLoc) await _startScanning();
    setState(() {});
  }

  // ───── escaneo ─────

  Future<void> _startScanning() async {
    if (_scanning) return;
    if (_posSub == null) await _initLocation();
    setState(() => _scanning = true);
    _wifiSub ??= WiFiScan.instance.onScannedResultsAvailable.listen(
      _ingestWifi,
      onError: (Object e) => _setWarn('wifi', 'Wi-Fi: $e'),
    );
    await _wifiScan();
    _wifiTimer?.cancel();
    _wifiTimer =
        Timer.periodic(const Duration(seconds: 35), (_) => _wifiScan());
    await _startBle();
  }

  Future<void> _stopScanning() async {
    _wifiTimer?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    // Al detener, también se apaga el GPS y con él el servicio en primer plano.
    await _posSub?.cancel();
    _posSub = null;
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await _stopScanning();
    } else if (!_hasLoc) {
      await _bootstrap();
    } else {
      await _startScanning();
    }
  }

  Future<void> _wifiScan() async {
    try {
      final can = await WiFiScan.instance.canStartScan();
      if (can == CanStartScan.yes) {
        final ok = await WiFiScan.instance.startScan();
        _setWarn(
          'wifithr',
          ok
              ? null
              : 'Android limitó el escaneo Wi-Fi (máx. ~4 cada 2 min). Se muestran los últimos resultados.',
        );
      }
      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet == CanGetScannedResults.yes) {
        _ingestWifi(await WiFiScan.instance.getScannedResults());
        _setWarn('wifi', null);
      } else {
        _setWarn('wifi', 'Wi-Fi: no se pueden leer resultados ($canGet).');
      }
    } catch (e) {
      _setWarn('wifi', 'Wi-Fi: $e');
    }
  }

  Future<void> _startBle() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        _setWarn('ble', 'Este equipo no soporta Bluetooth LE.');
        return;
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 800));
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        _setWarn(
            'ble', 'Bluetooth apagado: enciéndelo para ver dispositivos BLE.');
        return;
      }
      _setWarn('ble', null);
      _bleSub ??= FlutterBluePlus.scanResults.listen(
        _ingestBle,
        onError: (Object e) => _setWarn('ble', 'BLE: $e'),
      );
      await FlutterBluePlus.startScan(
          androidUsesFineLocation: true, continuousUpdates: true);
    } catch (e) {
      _setWarn('ble', 'BLE: $e');
    }
  }

  // ───── ingesta ─────

  void _ingestWifi(List<WiFiAccessPoint> list) {
    final now = DateTime.now();
    final touched = <Dev>[];
    for (final ap in list) {
      if (ap.bssid.isEmpty) continue;
      var d = _devs[ap.bssid];
      if (d != null && ap.timestamp != null && d.lastStamp == ap.timestamp)
        continue;
      if (d == null) {
        d = Dev(ap.bssid, DevType.wifi, now);
        d.mine = _known[ap.bssid]?.mine ?? false;
        _devs[ap.bssid] = d;
      }
      d.lastStamp = ap.timestamp;
      d.rawName = ap.ssid;
      if (ap.ssid.isNotEmpty) {
        if (_ssidMem[ap.bssid] != ap.ssid) _logDirty = true;
        _ssidMem[ap.bssid] = ap.ssid;
        if (_ssidMem.length > 3000) _ssidMem.remove(_ssidMem.keys.first);
      }
      d.freq = ap.frequency;
      d.channel = channelFromFreq(ap.frequency);
      d.center0 = ap.centerFrequency0;
      d.center1 = ap.centerFrequency1;
      d.caps = ap.capabilities;
      d.standard = ap.standard?.name;
      d.passpoint = ap.isPasspoint;
      d.operatorName = ap.operatorFriendlyName;
      d.venueName = ap.venueName;
      d.mcResponder = ap.is80211mcResponder;
      final w = ap.channelWidth?.name;
      d.width = w == null
          ? null
          : '${w.replaceFirst('mhz', '').replaceFirst('Plus', '+')} MHz';
      d.addReading(ap.level, now);
      _onReading(d);
      touched.add(d);
    }
    _reidentifyWifi();
    for (final t in touched) {
      _log(t, now);
    }
  }

  /// Agrupa BSSID hermanos (mismo equipo físico), resuelve nombres de redes ocultas
  /// y recalcula la identidad Wi-Fi.
  void _reidentifyWifi() {
    final counts = <String, int>{};
    final fam = <String, List<Dev>>{};
    final wifi = _devs.values.where((d) => d.type == DevType.wifi).toList();
    for (final d in wifi) {
      if (d.rawName.isNotEmpty)
        counts[d.rawName] = (counts[d.rawName] ?? 0) + 1;
      final key = familyKey(d.id);
      if (key != null) fam.putIfAbsent(key, () => []).add(d);
    }
    for (final d in wifi) {
      final key = familyKey(d.id);
      d.sibs = key == null
          ? []
          : fam[key]!
              .where((o) => o != d && (o.smooth - d.smooth).abs() <= 25)
              .toList();
    }
    for (final d in wifi) {
      d.knownSsid = null;
      d.nearSsid = null;
      if (d.rawName.isEmpty) {
        d.knownSsid = _ssidMem[d.id];
        if (d.knownSsid == null) {
          final named = d.sibs.where((s) => s.rawName.isNotEmpty).toList()
            ..sort((a, b) => b.smooth.compareTo(a.smooth));
          if (named.isNotEmpty) d.nearSsid = named.first.rawName;
        }
      }
      d.ident = identifyWifi(d, db, counts[d.rawName] ?? 1);
    }
    _dirty = true;
  }

  void _ingestBle(List<ScanResult> results) {
    final now = DateTime.now();
    for (final r in results) {
      final id = r.device.remoteId.str;
      var d = _devs[id];
      if (d != null && d.lastAdv != null && !r.timeStamp.isAfter(d.lastAdv!))
        continue;
      if (d == null) {
        d = Dev(id, DevType.ble, now);
        final k = _known[id];
        d.mine = k?.mine ?? false;
        if (k != null &&
            k.title.isNotEmpty &&
            !k.title.startsWith('BLE sin nombre') &&
            !k.title.endsWith('(sin nombre)')) {
          d.gattName = k.title;
        }
        _devs[id] = d;
      }
      if (d.lastAdv != null) {
        final dt = r.timeStamp.difference(d.lastAdv!).inMilliseconds.toDouble();
        d.intervalMs =
            d.intervalMs == null ? dt : d.intervalMs! * 0.9 + dt * 0.1;
      }
      d.lastAdv = r.timeStamp;
      d.addReading(r.rssi, now);

      if (d.identAt == null ||
          now.difference(d.identAt!).inMilliseconds > 1500) {
        final adv = r.advertisementData;
        d.device = r.device;
        d.rawName =
            adv.advName.isNotEmpty ? adv.advName : r.device.platformName;
        d.txPower = adv.txPowerLevel;
        d.appearance = adv.appearance;
        d.connectable = adv.connectable;
        d.mfrData = adv.manufacturerData;
        d.svcUuids =
            adv.serviceUuids.map((g) => shortUuid(g.toString())).toList();
        d.svcData = {
          for (final e in adv.serviceData.entries)
            shortUuid(e.key.toString()): e.value
        };
        d.ident = identifyBle(d, db);
        d.identAt = now;
      }
      _onReading(d);
      _log(d, now);
    }
    _dirty = true;
  }

  // ───── duplicados BLE por rotación de dirección ─────

  String _fp(Dev d) {
    final b = StringBuffer();
    b.write(d.rawName);
    b.write('|');
    final keys = d.mfrData.keys.toList()..sort();
    b.write(keys.join(','));
    final apple = d.mfrData[0x004C];
    if (apple != null) {
      final ts = parseApple(apple).map((t) => t.type).toSet().toList()..sort();
      b.write('|a${ts.join(',')}');
    }
    final sv = [...d.svcUuids]..sort();
    b.write('|${sv.join(',')}|${d.appearance ?? ''}');
    return b.toString();
  }

  /// Un aparato que cambia de dirección aparece unos segundos duplicado:
  /// si hay una única coincidencia clara, se unifica en una sola entrada.
  void _mergeRotating(DateTime now) {
    final rot =
        _devs.values.where((d) => d.type == DevType.ble && d.rotating).toList();
    if (rot.length < 2) return;
    final groups = <String, List<Dev>>{};
    for (final d in rot) {
      final s = _fp(d);
      if (s.replaceAll('|', '').replaceAll(',', '').isEmpty) continue;
      groups.putIfAbsent(s, () => []).add(d);
    }
    for (final g in groups.values) {
      if (g.length < 2) continue;
      g.sort((a, b) => a.firstSeen.compareTo(b.firstSeen));
      for (var i = 1; i < g.length; i++) {
        final nw = g[i];
        if (!_devs.containsKey(nw.id)) continue;
        final cands = g.sublist(0, i).where((o) {
          if (!_devs.containsKey(o.id) || o.id == _targetId) return false;
          final silent = now.difference(o.lastSeen).inSeconds;
          final gap = nw.firstSeen.difference(o.lastSeen).inSeconds;
          return silent >= 2 &&
              gap >= -3 &&
              gap <= 45 &&
              (o.smooth - nw.smooth).abs() <= 18;
        }).toList();
        if (cands.length != 1) continue;
        final old = cands.first;
        nw.firstSeen = old.firstSeen;
        nw.merged += 1 + old.merged;
        nw.updates += old.updates;
        nw.rssiSum += old.rssiSum;
        nw.minRssi = min(nw.minRssi, old.minRssi);
        nw.maxRssi = max(nw.maxRssi, old.maxRssi);
        nw.history.insertAll(0, old.history);
        while (nw.history.length > 60) {
          nw.history.removeAt(0);
        }
        _devs.remove(old.id);
        _dirty = true;
      }
    }
  }

  void _onReading(Dev d) {
    if (d.id == _targetId) _sweepSample(d);
    if (_still &&
        _stillSince != null &&
        DateTime.now().difference(_stillSince!).inSeconds >= 8) {
      d.stMin = d.stMin == null ? d.smooth : min(d.stMin!, d.smooth);
      d.stMax = d.stMax == null ? d.smooth : max(d.stMax!, d.smooth);
    }
    final p = _pos;
    if (p != null && (d.bestRssi == null || d.rssi > d.bestRssi!)) {
      d.bestRssi = d.rssi.toDouble();
      d.bestLat = p.latitude;
      d.bestLon = p.longitude;
    }
    if (d.id != _targetId || p == null || p.accuracy > 30) return;
    final last = _samples.isEmpty ? null : _samples.last;
    final now = DateTime.now();
    if (last != null) {
      final moved = Geolocator.distanceBetween(
          last.lat, last.lon, p.latitude, p.longitude);
      if (moved < 1.5 && now.difference(last.t).inSeconds < 5) return;
    }
    _samples.add(Sample(p.latitude, p.longitude, d.smooth, now));
    if (_samples.length > 600) _samples.removeAt(0);
  }

  void _calcFixedNear() {
    final p = _pos;
    if (p == null) {
      _fixedNear = 0;
      return;
    }
    var n = 0;
    for (final k in _known.values) {
      final e = estimateOf(k);
      if (e != null &&
          e.status == 'fijo' &&
          Geolocator.distanceBetween(p.latitude, p.longitude, e.lat, e.lon) <
              50) {
        n++;
      }
    }
    _fixedNear = n;
  }

  void _tickUi(Timer _) {
    final now = DateTime.now();
    final before = _devs.length;
    _devs.removeWhere((id, d) {
      if (id == _targetId) return false;
      return now.difference(d.lastSeen).inSeconds >
          (d.type == DevType.wifi ? 90 : 20);
    });
    if (now.difference(_lastMerge).inSeconds >= 3) {
      _lastMerge = now;
      _mergeRotating(now);
    }
    if (now.difference(_lastFixedCalc).inSeconds >= 10) {
      _lastFixedCalc = now;
      _calcFixedNear();
      _dirty = true;
    }
    if (_appActive && _tab == 3 && now.difference(_mapAt).inSeconds >= 3) {
      _refreshMap();
      _dirty = true;
    }
    final p = _pos;
    if (_appActive && _tab == 3 && _mapReady && !_autoCentered && p != null) {
      _autoCentered = true;
      try {
        _mapCtl.move(LatLng(p.latitude, p.longitude), 18);
      } catch (_) {}
    }
    if (_logDirty && now.difference(_lastSave).inSeconds >= 30) _saveLog();
    if ((_dirty || before != _devs.length) && mounted) {
      _dirty = false;
      _checkAlerts();
      if (_appActive) setState(() {});
    }
  }

  void _checkAlerts() {
    final now = DateTime.now();
    if (now.difference(_lastNotif).inSeconds < 8) return;
    for (final d in _devs.values) {
      final al = d.alerts;
      if (al.isEmpty || d.smooth < -85) continue;
      final key = '${d.id}|${al.join(',')}';
      if (_alerted.contains(key)) continue;
      _alerted.add(key);
      _lastNotif = now;
      final msg =
          '${al.join(', ')}: ${d.title} (${d.smooth.round()} dBm, ~${d.distance.toStringAsFixed(0)} m)';
      _notify('⚠ $kAppName', msg);
      if (_appActive && mounted) {
        HapticFeedback.vibrate();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('⚠ $msg'),
        ));
      }
      break;
    }
  }

  // ───── anclas manuales y calibración ─────

  void _setAnchor(String id, double lat, double lon) {
    final d = _devs[id];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final k = _known.putIfAbsent(
      id,
      () => Known(
          id, (d != null && d.type == DevType.wifi) ? 'wifi' : 'ble', nowMs),
    );
    if (d != null) {
      k.title = d.title;
      k.cls = d.ident.type;
      k.brand = d.ident.brand;
    }
    k.ax = lat;
    k.ay = lon;
    k.p0 = null;
    k.pn = null;
    k.psd = null;
    k.pnum = 0;
    if (d != null) {
      d.calSamples.clear();
      d.fitP0 = null;
      d.fitN = null;
      d.fitSd = null;
      d.fitNum = 0;
    }
    _anchorFor = null;
    _logDirty = true;
    _refreshMap();
  }

  void _clearAnchor(Known k) {
    k.ax = null;
    k.ay = null;
    k.p0 = null;
    k.pn = null;
    k.psd = null;
    k.pnum = 0;
    final d = _devs[k.id];
    if (d != null) {
      d.calSamples.clear();
      d.fitP0 = null;
      d.fitN = null;
      d.fitSd = null;
      d.fitNum = 0;
    }
    _logDirty = true;
    _refreshMap();
  }

  void _anchorHere(String id) {
    final p = _pos;
    String? msg;
    if (p == null) {
      msg = 'Todavía no hay GPS';
    } else if (p.accuracy > 20) {
      msg =
          'GPS impreciso (±${p.accuracy.round()} m). Salí a cielo abierto o usá "tocar mapa" con la vista satélite.';
    }
    if (msg != null) {
      _snack(msg);
      return;
    }
    setState(() => _setAnchor(id, p!.latitude, p.longitude));
  }

  /// Toma una muestra (distancia al ancla, RSSI) y reajusta el modelo de pérdida.
  void _calibSample(Dev d, Known k, Pt p) {
    if (k.ax == null || k.ay == null || p.accuracy > 12) return;
    final dist =
        Geolocator.distanceBetween(p.latitude, p.longitude, k.ax!, k.ay!);
    if (dist < 5 || dist > 150) return;
    d.calSamples.add((10 * log(dist) / ln10, d.rssi.toDouble()));
    if (d.calSamples.length > 300) d.calSamples.removeAt(0);
    if (d.calSamples.length >= 12 && d.calSamples.length % 5 == 0)
      _fitModel(d, k);
  }

  void _fitModel(Dev d, Known k) {
    final s = d.calSamples;
    final n = s.length;
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    var mn = double.infinity, mx = -double.infinity;
    for (final e in s) {
      sx += e.$1;
      sy += e.$2;
      sxx += e.$1 * e.$1;
      sxy += e.$1 * e.$2;
      mn = min(mn, e.$1);
      mx = max(mx, e.$1);
    }
    if (mx - mn < 6) return; // hace falta un rango de distancias de al menos 4×
    final den = n * sxx - sx * sx;
    if (den.abs() < 1e-9) return;
    final slope = (n * sxy - sx * sy) / den;
    final nExp = (-slope).clamp(1.2, 5.0).toDouble();
    final p0 = (sy + nExp * sx) / n; // RSSI a 1 m
    var ss = 0.0;
    for (final e in s) {
      final r = e.$2 - (p0 - nExp * e.$1);
      ss += r * r;
    }
    final sd = sqrt(ss / n);
    d.fitP0 = p0;
    d.fitN = nExp;
    d.fitSd = sd;
    d.fitNum = n;
    k.p0 = p0;
    k.pn = nExp;
    k.psd = sd;
    k.pnum = n;
    _logDirty = true;
  }

  // ───── mapa descargable ─────

  Future<void> _downloadArea(double radiusM,
      {bool useMapCenter = false}) async {
    if (_dlBusy) {
      _snack('Ya hay una descarga en curso');
      return;
    }
    double? lat, lon;
    if (useMapCenter || _pos == null) {
      if (_tab == 3 && _mapReady) {
        try {
          final c = _mapCtl.camera.center;
          lat = c.latitude;
          lon = c.longitude;
        } catch (_) {}
      } else if (useMapCenter) {
        _snack('Abrí la pestaña Mapa, mové el mapa a tu zona y repetí');
        return;
      }
    }
    final p = _pos;
    if (lat == null && p != null) {
      lat = p.latitude;
      lon = p.longitude;
    }
    if (lat == null || lon == null) {
      _snack(
          'Sin GPS: abrí la pestaña Mapa, mové el mapa a tu zona y elegí "Descargar zona visible"');
      return;
    }
    final st = kMapStyles[_mapStyle];
    final urls = <String>[];
    final dLat = radiusM / 110540;
    final dLon = radiusM / (111320 * cos(lat * pi / 180));
    for (var z = 15; z <= min(18, st.maxNative); z++) {
      final a = tileXY(lat + dLat, lon - dLon, z);
      final b = tileXY(lat - dLat, lon + dLon, z);
      for (var x = a.$1; x <= b.$1; x++) {
        for (var y = a.$2; y <= b.$2; y++) {
          urls.add(st.url
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y'));
        }
      }
    }
    if (urls.length > 700) urls.removeRange(700, urls.length);
    setState(() {
      _dlBusy = true;
      _dlCancel = false;
      _dlDone = 0;
      _dlOk = 0;
      _dlFail = 0;
      _dlErr = null;
      _dlTotal = urls.length;
    });
    for (final u in urls) {
      if (_dlCancel || !mounted) break;
      try {
        final r = await _tileClient.get(Uri.parse(u), headers: {
          'User-Agent': 'flutter_map ($kTileAgent)'
        }).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          _dlOk++;
        } else {
          _dlFail++;
          _dlErr ??= 'HTTP ${r.statusCode}';
        }
      } catch (e) {
        _dlFail++;
        _dlErr ??= shortErr(e.toString());
      }
      _dlDone++;
      if (_dlDone % 5 == 0 && mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    setState(() => _dlBusy = false);
    if (_dlCancel) {
      _snack('Descarga cancelada: $_dlOk teselas guardadas');
    } else if (_dlOk == 0) {
      _snack('No se descargó nada. Error: ${_dlErr ?? '?'}');
      unawaited(_checkNet());
    } else {
      _snack(
          'Mapa listo: $_dlOk teselas${_dlFail > 0 ? ' ($_dlFail fallaron)' : ''}');
    }
  }

  Future<void> _clearTiles() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/tiles');
      if (await d.exists()) await d.delete(recursive: true);
      _tileClient.dir = null;
    } catch (_) {}
    _snack('Mapas descargados borrados');
  }

  // ───── mapa ─────

  void _refreshMap() {
    final items = <Known>[];
    final est = <String, Est>{};
    for (final k in _known.values) {
      final e = estimateOf(k);
      if (e == null) continue;
      final show = (e.status == 'fijo' && _showFixed) ||
          (e.status == 'sin confirmar' && _showUnconf) ||
          ((e.status == 'móvil' || e.status == 'incierto') && _showMobile);
      if (!show) continue;
      items.add(k);
      est[k.id] = e;
    }
    final p = _pos;
    if (items.length > 500 && p != null) {
      double dist(Known k) {
        final e = est[k.id]!;
        return Geolocator.distanceBetween(
            p.latitude, p.longitude, e.lat, e.lon);
      }

      items.sort((a, b) => dist(a).compareTo(dist(b)));
      items.removeRange(500, items.length);
    }
    _mapItems = items;
    _mapEst = est;
    _mapAt = DateTime.now();
  }

  Widget _mapChip(String label, bool sel, void Function(bool) apply) =>
      FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: sel,
        backgroundColor: const Color(0xCC0F172A),
        onSelected: (v) => setState(() {
          apply(v);
          _refreshMap();
        }),
      );

  Marker _marker(Known k) {
    final e = _mapEst[k.id]!;
    final Color c = k.ax != null
        ? Colors.tealAccent
        : k.mine
            ? Colors.lightBlueAccent
            : (k.alert
                ? Colors.redAccent
                : (e.status == 'fijo'
                    ? Colors.greenAccent
                    : (e.status == 'sin confirmar'
                        ? Colors.grey
                        : Colors.orangeAccent)));
    return Marker(
      point: LatLng(e.lat, e.lon),
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: () {
          setState(() => _mapSel = k.id);
          _showKnownSheet(k, e);
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: 0.25),
            border: Border.all(color: c, width: 2),
          ),
          child: Icon(iconForType(k.cls, k.kind == 'wifi'), size: 16, color: c),
        ),
      ),
    );
  }

  void _showKnownSheet(Known k, Est e) {
    final p = _pos;
    var rel = '';
    if (p != null) {
      final dist =
          Geolocator.distanceBetween(p.latitude, p.longitude, e.lat, e.lon);
      final brg =
          Geolocator.bearingBetween(p.latitude, p.longitude, e.lat, e.lon);
      rel = 'Desde vos: ~${dist.round()} m hacia el ${cardinal(brg)}';
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k.title.isEmpty ? k.id : k.title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              Text('${k.cls}${k.brand != null ? ' · ${k.brand}' : ''}',
                  style:
                      const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                  'Estado: ${e.status.toUpperCase()} · radio ±${e.radius.round()} m'),
              Text(
                  'Visitas: ${e.visits} · primera vez ${fmtDate(k.first)} · última ${fmtDate(k.last)}'),
              if (rel.isNotEmpty) Text(rel),
              const SizedBox(height: 4),
              Text(statusText(e),
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (k.ax != null)
                Text(
                    '📌 Ancla manual: ${k.ax!.toStringAsFixed(5)}, ${k.ay!.toStringAsFixed(5)}',
                    style: const TextStyle(
                        color: Colors.tealAccent, fontSize: 12)),
              if (k.p0 != null)
                Text(
                    'Modelo calibrado: ${k.p0!.toStringAsFixed(0)} dBm a 1 m · n=${k.pn!.toStringAsFixed(1)} · ±${k.psd!.toStringAsFixed(1)} dB (${k.pnum} muestras)',
                    style: const TextStyle(
                        color: Colors.tealAccent, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.push_pin, size: 16),
                  label: const Text('Ancla: tocar mapa'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => _anchorFor = k.id);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Ancla donde estoy'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _anchorHere(k.id);
                  },
                ),
                if (k.ax != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.location_off, size: 16),
                    label: const Text('Quitar ancla'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _clearAnchor(k));
                    },
                  ),
              ]),
              Text(k.id,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.gps_fixed, size: 16),
                  label: const Text('Rastrear'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final d = _devs[k.id];
                    if (d != null) {
                      _setTarget(d);
                    } else {
                      _snack('No está al alcance ahora mismo');
                    }
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.verified_user, size: 16),
                  label: Text(k.mine ? 'Quitar "mío"' : 'Es mío'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      k.mine = !k.mine;
                      _devs[k.id]?.mine = k.mine;
                      _logDirty = true;
                      _refreshMap();
                    });
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Olvidar'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _known.remove(k.id);
                      _mapSel = null;
                      _logDirty = true;
                      _refreshMap();
                    });
                  },
                ),
              ]),
            ]),
      ),
    );
  }

  Widget _mapTab() {
    final p = _pos;
    LatLng center;
    var zoom = 18.0;
    if (p != null) {
      center = LatLng(p.latitude, p.longitude);
    } else if (_track.isNotEmpty) {
      center = LatLng(_track.last.lat, _track.last.lon);
    } else if (_mapEst.isNotEmpty) {
      final e = _mapEst.values.first;
      center = LatLng(e.lat, e.lon);
    } else {
      center = LatLng(0, 0);
      zoom = 2;
    }
    final sel = _mapSel == null ? null : _mapEst[_mapSel];
    return Stack(children: [
      FlutterMap(
        mapController: _mapCtl,
        options: MapOptions(
          initialCenter: center,
          initialZoom: zoom,
          minZoom: 2,
          maxZoom: 22,
          onMapReady: () => _mapReady = true,
          onTap: (_, pt) {
            final aid = _anchorFor;
            if (aid != null) {
              setState(() => _setAnchor(aid, pt.latitude, pt.longitude));
              return;
            }
            setState(() => _mapSel = null);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: kMapStyles[_mapStyle].url,
            userAgentPackageName: kTileAgent,
            maxNativeZoom: kMapStyles[_mapStyle].maxNative,
            tileProvider: NetworkTileProvider(httpClient: _tileClient),
          ),
          if (_showTrack && _track.length > 1)
            PolylineLayer(polylines: [
              Polyline(
                points: [for (final t in _track) LatLng(t.lat, t.lon)],
                strokeWidth: 3,
                color: Colors.cyanAccent.withValues(alpha: 0.55),
              ),
            ]),
          CircleLayer(circles: [
            if (sel != null)
              CircleMarker(
                point: LatLng(sel.lat, sel.lon),
                radius: sel.radius,
                useRadiusInMeter: true,
                color: Colors.amberAccent.withValues(alpha: 0.15),
                borderColor: Colors.amberAccent,
                borderStrokeWidth: 2,
              ),
            if (p != null)
              CircleMarker(
                point: LatLng(p.latitude, p.longitude),
                radius: max(p.accuracy, 3.0),
                useRadiusInMeter: true,
                color: Colors.cyanAccent.withValues(alpha: 0.10),
                borderColor: Colors.cyanAccent.withValues(alpha: 0.5),
                borderStrokeWidth: 1,
              ),
            if (p != null)
              CircleMarker(
                point: LatLng(p.latitude, p.longitude),
                radius: 7,
                color: Colors.cyanAccent,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
          ]),
          MarkerLayer(markers: [for (final k in _mapItems) _marker(k)]),
        ],
      ),
      Positioned(
        top: 8,
        left: 8,
        right: 8,
        child: Wrap(spacing: 6, runSpacing: 0, children: [
          _mapChip('Fijos', _showFixed, (v) => _showFixed = v),
          _mapChip('Sin confirmar', _showUnconf, (v) => _showUnconf = v),
          _mapChip('Móviles', _showMobile, (v) => _showMobile = v),
          _mapChip('Recorrido', _showTrack, (v) => _showTrack = v),
        ]),
      ),
      Positioned(
        right: 12,
        bottom: 36,
        child: FloatingActionButton.small(
          heroTag: 'ctr',
          onPressed: () {
            if (p != null && _mapReady) {
              try {
                _mapCtl.move(LatLng(p.latitude, p.longitude), 18);
              } catch (_) {}
            }
          },
          child: const Icon(Icons.my_location),
        ),
      ),
      Positioned(
        right: 12,
        bottom: 84,
        child: PopupMenuButton<int>(
          tooltip: 'Estilo de mapa',
          onSelected: (i) => setState(() => _mapStyle = i),
          itemBuilder: (_) => [
            for (var i = 0; i < kMapStyles.length; i++)
              CheckedPopupMenuItem(
                  value: i,
                  checked: i == _mapStyle,
                  child: Text(kMapStyles[i].name)),
          ],
          child: const CircleAvatar(
            backgroundColor: Color(0xFF0F172A),
            child: Icon(Icons.layers, color: Colors.white),
          ),
        ),
      ),
      Positioned(
        left: 8,
        bottom: 8,
        child: Text(
            '${_mapItems.length} en el mapa · ${kMapStyles[_mapStyle].credit}',
            style: const TextStyle(
                fontSize: 10,
                color: Colors.black87,
                backgroundColor: Color(0xAAFFFFFF))),
      ),
      if (p == null)
        Positioned(
          left: 8,
          right: 8,
          bottom: 30,
          child: Card(
            color: const Color(0xEE0F172A),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Sin GPS: $_gpsMsg. Igual podés mover el mapa a tu zona y bajarla con ⋮ → "Descargar zona visible".',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      if (_anchorFor != null)
        Positioned(
          top: 96,
          left: 8,
          right: 8,
          child: Card(
            color: const Color(0xEE0F172A),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    'Tocá el mapa para fijar dónde está "${_devs[_anchorFor!]?.title ?? _known[_anchorFor!]?.title ?? _anchorFor}"',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                    onPressed: () => setState(() => _anchorFor = null),
                    child: const Text('Cancelar')),
              ]),
            ),
          ),
        ),
    ]);
  }

  // ───── GATT (conexión) ─────

  static const _readable = {
    '2a00',
    '2a01',
    '2a19',
    '2a23',
    '2a24',
    '2a25',
    '2a26',
    '2a27',
    '2a28',
    '2a29',
    '2a50'
  };

  String _decodeChar(String u, List<int> v) {
    if (v.isEmpty) return '(vacío)';
    switch (u) {
      case '2a00':
      case '2a24':
      case '2a25':
      case '2a26':
      case '2a27':
      case '2a28':
      case '2a29':
        return utf8
            .decode(v, allowMalformed: true)
            .replaceAll('\u0000', '')
            .trim();
      case '2a19':
        return '${v[0]}%';
      case '2a01':
        {
          final a = v.length >= 2 ? (v[0] | (v[1] << 8)) : v[0];
          return '${h4(a)} (${kAppearance[a >> 6] ?? 'categoría ${a >> 6}'})';
        }
      case '2a50':
        {
          if (v.length >= 7) {
            final src = v[0];
            final vid = v[1] | (v[2] << 8);
            final pid = v[3] | (v[4] << 8);
            final ver = v[5] | (v[6] << 8);
            final vn = src == 1
                ? (db.companies[vid] ?? 'desconocido')
                : (src == 2 ? 'vendor USB' : '?');
            return 'fuente $src · vendor ${h4(vid)} ($vn) · producto ${h4(pid)} · versión ${h4(ver)}';
          }
          return hx(v);
        }
      default:
        return hx(v);
    }
  }

  Future<void> _readGatt(Dev d) async {
    final dev = d.device;
    if (dev == null || d.gattBusy) return;
    setState(() {
      d.gattBusy = true;
      d.gatt = 'Conectando…';
    });
    final out = StringBuffer();
    try {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await dev.connect(timeout: const Duration(seconds: 15));
      final services = await dev.discoverServices();
      for (final s in services) {
        final su = uuidOf(s);
        final sn = db.serviceName(su);
        out.writeln('SERVICIO $su${sn != null ? ' · $sn' : ''}');
        for (final c in s.characteristics) {
          final cu = uuidOf(c);
          final cn = db.charName(cu);
          final pr = c.properties;
          final flags = [
            if (pr.read) 'R',
            if (pr.write) 'W',
            if (pr.writeWithoutResponse) 'Wn',
            if (pr.notify) 'N',
            if (pr.indicate) 'I',
          ].join('');
          var line = '  $cu${cn != null ? ' · $cn' : ''} [$flags]';
          if (pr.read && _readable.contains(cu)) {
            try {
              final v = await c.read();
              final txt = _decodeChar(cu, v);
              line += ' = $txt';
              if (cu == '2a00' && txt.isNotEmpty) d.gattName = txt;
            } catch (_) {
              line += ' (no se pudo leer)';
            }
          }
          out.writeln(line);
        }
      }
    } catch (e) {
      out.writeln('No se pudo conectar/leer: $e');
    } finally {
      try {
        await dev.disconnect();
      } catch (_) {}
      if (_scanning) unawaited(_startBle());
    }
    if (!mounted) return;
    setState(() {
      d.gattBusy = false;
      d.gatt = out.toString().trimRight();
    });
  }

  // ───── cazador ─────

  Dev? get _target => _targetId == null ? null : _devs[_targetId];

  void _setTarget(Dev d) {
    setState(() {
      _targetId = d.id;
      _samples.clear();
      _bearings.clear();
      _bestBearing = null;
      _sweep = false;
      _sweepMsg = null;
      _tab = 1;
      _mapReady = false;
    });
    _syncSensors();
  }

  void _clearTarget() {
    _geigerTimer?.cancel();
    setState(() {
      _targetId = null;
      _geiger = false;
      _samples.clear();
      _bearings.clear();
      _bestBearing = null;
      _sweep = false;
      _sweepMsg = null;
    });
    _syncSensors();
  }

  void _setGeiger(bool v) {
    setState(() => _geiger = v);
    _geigerTimer?.cancel();
    if (v) _geigerTick();
  }

  void _geigerTick() {
    _geigerTimer?.cancel();
    if (!_geiger || !mounted) return;
    final t = _target;
    var delay = 1000;
    if (t != null && DateTime.now().difference(t.lastSeen).inSeconds < 15) {
      final x = ((t.smooth + 95) / 60).clamp(0.0, 1.0).toDouble();
      delay = (1400 - 1280 * x).round();
      if (_sound) SystemSound.play(SystemSoundType.click);
      if (x > 0.6) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
    _geigerTimer = Timer(Duration(milliseconds: delay), _geigerTick);
  }

  (double, double)? _estimate() {
    if (_samples.length < 5) return null;
    final sorted = [..._samples]..sort((a, b) => b.rssi.compareTo(a.rssi));
    final n = max(3, (sorted.length * 0.3).ceil());
    double w = 0, la = 0, lo = 0;
    for (final s in sorted.take(n)) {
      final wi = pow(10, s.rssi / 10).toDouble();
      w += wi;
      la += s.lat * wi;
      lo += s.lon * wi;
    }
    return (la / w, lo / w);
  }

  // ───── fichas y exportación ─────

  void _toggleMine(Dev d) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final k = _known.putIfAbsent(d.id,
        () => Known(d.id, d.type == DevType.wifi ? 'wifi' : 'ble', nowMs));
    k.title = d.title;
    k.cls = d.ident.type;
    k.brand = d.ident.brand;
    k.mine = !k.mine;
    d.mine = k.mine;
    _logDirty = true;
    setState(() {});
  }

  String _dossier(Dev d) {
    final i = d.ident;
    final k = _known[d.id];
    final est = k == null ? null : estimateOf(k);
    final r = riskOf(d);
    final now = DateTime.now();
    final b = StringBuffer();
    b.writeln('RESUMEN');
    b.writeln(summarize(d, est));
    b.writeln('Nivel: ${const ['VERDE', 'ÁMBAR', 'ROJO'][r.$1]} — ${r.$2}');
    b.writeln('\nIDENTIDAD');
    b.writeln('Tipo: ${i.type} (confianza ${i.conf}%)');
    if (i.brand != null) b.writeln('Marca: ${i.brand}');
    if (i.model != null) b.writeln('Modelo: ${i.model}');
    if (d.alerts.isNotEmpty) b.writeln('⚠ ALERTAS: ${d.alerts.join(', ')}');
    if (i.why.isNotEmpty) {
      b.writeln('\nEVIDENCIA');
      for (final w in i.why) {
        b.writeln('• $w');
      }
    }
    if (d.sibs.isNotEmpty) {
      b.writeln('\nEQUIPO FÍSICO (${d.sibs.length + 1} radios)');
      for (final s in d.sibs) {
        b.writeln(
            '• ${s.id} · ${bandOf(s.freq ?? 2412)} ch${s.channel ?? '?'} · ${s.rawName.isEmpty ? '(oculta)' : s.rawName} · ${s.smooth.round()} dBm');
      }
    }
    b.writeln('\nDATOS');
    b.writeln(d.type == DevType.wifi ? 'BSSID: ${d.id}' : 'ID/MAC: ${d.id}');
    i.facts.forEach((key, v) => b.writeln('$key: $v'));
    b.writeln('\nSEÑAL');
    b.writeln(
        'RSSI ${d.rssi} dBm · suavizado ${d.smooth.toStringAsFixed(1)} · mín ${d.minRssi} · máx ${d.maxRssi} · prom ${(d.rssiSum / max(1, d.updates)).toStringAsFixed(1)}');
    b.writeln(
        'Distancia aprox.: ${d.distance.toStringAsFixed(1)} m (muy orientativa)');
    b.writeln(
        'Lecturas: ${d.updates}${d.intervalMs != null ? ' · intervalo prom. ${d.intervalMs!.round()} ms' : ''}');
    b.writeln(
        'En rango desde hace ${fmtDur(now.difference(d.firstSeen))} · última lectura hace ${fmtDur(now.difference(d.lastSeen))}');
    if (d.merged > 0)
      b.writeln(
          'Direcciones anteriores unificadas: ${d.merged} (rotación de MAC)');
    if (d.stMin != null && d.stMax != null) {
      b.writeln(
          'Con vos quieto: señal entre ${d.stMin!.toStringAsFixed(0)} y ${d.stMax!.toStringAsFixed(0)} dBm (${(d.stMax! - d.stMin!).toStringAsFixed(0)} dB de variación)');
    }
    if (d.bestRssi != null && d.bestLat != null) {
      b.writeln(
          'Mejor señal (${d.bestRssi!.toStringAsFixed(0)} dBm) en ${d.bestLat!.toStringAsFixed(5)}, ${d.bestLon!.toStringAsFixed(5)}');
    }
    if (k != null) {
      b.writeln('\nHISTORIAL');
      b.writeln(
          'Visitas: ${k.visits.length} · primera vez ${fmtDate(k.first)} · lecturas guardadas: ${k.seen}');
      if (est != null) {
        b.writeln(
            'Estado: ${est.status.toUpperCase()} · posición estimada ${est.lat.toStringAsFixed(5)}, ${est.lon.toStringAsFixed(5)} (±${est.radius.round()} m)');
      }
      if (k.mine) b.writeln('Marcado como: MÍO');
      if (k.ax != null)
        b.writeln(
            'Ancla manual: ${k.ax!.toStringAsFixed(5)}, ${k.ay!.toStringAsFixed(5)}');
      if (d.fitP0 != null) {
        b.writeln(
            'Modelo calibrado: ${d.fitP0!.toStringAsFixed(0)} dBm a 1 m · exponente ${d.fitN!.toStringAsFixed(1)} · error ±${d.fitSd!.toStringAsFixed(1)} dB (${d.fitNum} muestras)');
      }
    }
    if (d.gatt != null) {
      b.writeln('\nGATT');
      b.writeln(d.gatt);
    }
    return b.toString().trimRight();
  }

  String _q(String s) => '"${s.replaceAll('"', '""')}"';

  Future<void> _copy(String text, String msg) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack(msg);
  }

  String _devicesCsv() {
    final b = StringBuffer(
        'tipo,nombre,id,categoria,marca,modelo,confianza,alertas,rssi,rssi_suav,banda,canal,freq_mhz,ancho,mejor_rssi,lat,lon\n');
    for (final d in _devs.values) {
      b.writeln([
        d.type.name,
        _q(d.title),
        d.id,
        _q(d.ident.type),
        _q(d.ident.brand ?? ''),
        _q(d.ident.model ?? ''),
        d.ident.conf,
        _q(d.alerts.join(' | ')),
        d.rssi,
        d.smooth.toStringAsFixed(1),
        d.freq != null ? bandOf(d.freq!) : '',
        d.channel ?? '',
        d.freq ?? '',
        d.width ?? '',
        d.bestRssi?.toStringAsFixed(0) ?? '',
        d.bestLat?.toStringAsFixed(6) ?? '',
        d.bestLon?.toStringAsFixed(6) ?? '',
      ].join(','));
    }
    return b.toString();
  }

  String _samplesCsv() {
    final b = StringBuffer('lat,lon,rssi,hora\n');
    for (final s in _samples) {
      b.writeln(
          '${s.lat.toStringAsFixed(6)},${s.lon.toStringAsFixed(6)},${s.rssi.toStringAsFixed(1)},${s.t.toIso8601String()}');
    }
    return b.toString();
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.greenAccent, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              kNick.toUpperCase(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: Colors.greenAccent,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('$kAppName · v$kVersion',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Radar de señales Wi-Fi y Bluetooth con mapa, historial, sensores y alertas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text('Mapa: ${kMapStyles[_mapStyle].credit}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))
        ],
      ),
    );
  }

  // ───── build ─────

  List<Dev> get _visible {
    final l = _devs.values.where((d) {
      if (_filter == 'wifi' && d.type != DevType.wifi) return false;
      if (_filter == 'ble' && d.type != DevType.ble) return false;
      if (_filter == 'alert' && d.alerts.isEmpty) return false;
      if (_query.isNotEmpty) {
        final hay =
            '${d.title} ${d.id} ${d.ident.type} ${d.ident.brand ?? ''} ${d.ident.model ?? ''}'
                .toLowerCase();
        if (!hay.contains(_query)) return false;
      }
      return true;
    }).toList();
    if (_sortSignal) {
      l.sort((a, b) => b.smooth.compareTo(a.smooth));
    } else {
      l.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return l;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Row(children: [
          Icon(Icons.radar, color: Colors.greenAccent),
          SizedBox(width: 8),
          Text(kAppName,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Escanear Wi-Fi ahora',
            icon: const Icon(Icons.wifi_find, color: Colors.greenAccent),
            onPressed: _wifiScan,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'fichas') {
                _copy(
                  '${_visible.map(_dossier).join('\n\n────────────────\n\n')}\n\n— $kAppName · $kNick —',
                  'Fichas completas copiadas',
                );
              } else if (v == 'csv') {
                _copy(_devicesCsv(), 'CSV de ${_devs.length} señales copiado');
              } else if (v == 'db') {
                _loadDb(force: true);
              } else if (v == 'net') {
                _checkNet(verbose: true);
              } else if (v == 'bg') {
                setState(() => _bg = !_bg);
                _logDirty = true;
                if (_posSub != null) _initLocation();
              } else if (v == 'batt') {
                Permission.ignoreBatteryOptimizations.request();
              } else if (v == 'warn') {
                setState(() => _showWarn = !_showWarn);
                _logDirty = true;
              } else if (v == 'banner') {
                setState(() => _showAlertBanner = !_showAlertBanner);
                _logDirty = true;
              } else if (v == 'dl500') {
                _downloadArea(500);
              } else if (v == 'dl1000') {
                _downloadArea(1000);
              } else if (v == 'dlview') {
                _downloadArea(500, useMapCenter: true);
              } else if (v == 'dlclear') {
                _clearTiles();
              } else if (v == 'about') {
                _showAbout();
              } else if (v == 'clear') {
                setState(() {
                  _devs.clear();
                  _samples.clear();
                  _alerted.clear();
                  _targetId = null;
                  _geiger = false;
                  _geigerTimer?.cancel();
                });
                _syncSensors();
              } else if (v == 'forget') {
                setState(() {
                  _known.clear();
                  _track.clear();
                  _mapItems = [];
                  _mapEst = {};
                  _mapSel = null;
                  _logDirty = true;
                });
                _saveLog();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'fichas', child: Text('Copiar fichas completas')),
              const PopupMenuItem(value: 'csv', child: Text('Copiar CSV')),
              CheckedPopupMenuItem(
                  value: 'bg',
                  checked: _bg,
                  child: const Text('Escanear en segundo plano')),
              const PopupMenuItem(
                  value: 'batt', child: Text('Excluir del ahorro de batería')),
              CheckedPopupMenuItem(
                  value: 'warn',
                  checked: _showWarn,
                  child: const Text('Mostrar avisos')),
              CheckedPopupMenuItem(
                  value: 'banner',
                  checked: _showAlertBanner,
                  child: const Text('Mostrar banner de alertas')),
              const PopupMenuItem(
                  value: 'dl500', child: Text('Descargar mapa: radio 500 m')),
              const PopupMenuItem(
                  value: 'dl1000', child: Text('Descargar mapa: radio 1 km')),
              const PopupMenuItem(
                  value: 'dlview',
                  child: Text('Descargar zona visible del mapa')),
              const PopupMenuItem(
                  value: 'dlclear', child: Text('Borrar mapas descargados')),
              const PopupMenuItem(value: 'net', child: Text('Probar internet')),
              const PopupMenuItem(
                  value: 'db', child: Text('Actualizar bases (internet)')),
              const PopupMenuItem(
                  value: 'clear', child: Text('Limpiar lista actual')),
              const PopupMenuItem(
                  value: 'forget', child: Text('Borrar historial y mapa')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'about',
                child: Row(children: [
                  Text(kNick,
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3)),
                  SizedBox(width: 8),
                  Text('· Acerca de',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(children: [
        _statusBar(),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _devicesTab(),
              _hunterTab(),
              _channelsTab(),
              _tab == 3 ? _mapTab() : const SizedBox.shrink(),
            ],
          ),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        backgroundColor: const Color(0xFF0F172A),
        onDestinationSelected: (i) {
          setState(() {
            _tab = i;
            _mapReady = false;
            if (i == 3) {
              _autoCentered = false;
              _refreshMap();
            }
          });
          _syncSensors();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Señales'),
          NavigationDestination(icon: Icon(Icons.gps_fixed), label: 'Cazador'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Canales'),
          NavigationDestination(icon: Icon(Icons.map), label: 'Mapa'),
        ],
      ),
      floatingActionButton: (_tab == 1 || _tab == 3)
          ? null
          : FloatingActionButton.extended(
              onPressed: _toggleScan,
              backgroundColor: _scanning ? Colors.redAccent : Colors.green,
              icon: Icon(_scanning ? Icons.stop : Icons.search,
                  color: Colors.black),
              label: Text(
                _scanning ? 'Detener' : 'Escanear',
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
    );
  }

  Widget _statusBar() {
    final p = _pos;
    return Container(
      width: double.infinity,
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: InkWell(
              onTap: p == null ? _retryGps : null,
              child: Text(
                p == null
                    ? 'GPS: $_gpsMsg · tocá para reintentar'
                    : 'GPS ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}  ±${p.accuracy.toStringAsFixed(0)} m',
                style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ),
          ),
          Text(
              '${_devs.length} señales${_bg && _scanning && !_bgBroken ? ' · 2.º plano' : ''} · ${_still ? 'quieto' : 'mov.'}',
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ]),
        Text('${db.status} · Historial: ${_known.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        if (_dlBusy)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LinearProgressIndicator(
                  value: _dlTotal == 0 ? null : _dlDone / _dlTotal,
                  minHeight: 4),
              Row(children: [
                Expanded(
                  child: Text(
                    'Descargando mapa: $_dlDone/$_dlTotal · ok $_dlOk · fallos $_dlFail',
                    style: const TextStyle(
                        color: Colors.lightBlueAccent, fontSize: 11),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _dlCancel = true),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text('Cancelar',
                        style: TextStyle(
                            color: Colors.lightBlueAccent, fontSize: 11)),
                  ),
                ),
              ]),
            ]),
          ),
        if (_showWarn)
          for (final e in _warnings.entries)
            if (!_dismissed.contains(e.key))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  const Icon(Icons.warning_amber,
                      size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: (e.key == 'perm' || e.key == 'notif')
                          ? () => openAppSettings()
                          : null,
                      child: Text(e.value,
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 11)),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _dismissed.add(e.key)),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14, color: Colors.amber),
                    ),
                  ),
                ]),
              ),
      ]),
    );
  }

  // ───── pestaña 1: señales ─────

  Widget _chip(String key, String label) => ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: _filter == key,
        onSelected: (_) => setState(() => _filter = key),
      );

  Widget _envCard() {
    if (_devs.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final wifi = _devs.values.where((d) => d.type == DevType.wifi).toList();
    final ble = _devs.values.where((d) => d.type == DevType.ble).toList();
    final open = wifi.where(isOpenWifi).length;
    final hidden = wifi.where((d) => d.rawName.isEmpty).length;
    final g5 = wifi.where((d) => (d.freq ?? 0) >= 5000).length;
    final cats = <String, int>{};
    for (final d in ble) {
      final t = d.ident.conf >= 40 ? d.ident.type : 'sin identificar';
      cats[t] = (cats[t] ?? 0) + 1;
    }
    final top = cats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topTxt = top
        .take(4)
        .map((e) =>
            '${e.value} ${e.key.length > 26 ? '${e.key.substring(0, 26)}…' : e.key}')
        .join(' · ');
    final sessionOld = now.difference(_startedAt).inMinutes >= 5;
    final fresh = _devs.values
        .where((d) => now.difference(d.firstSeen).inMinutes < 5)
        .length;
    const s = TextStyle(fontSize: 12);
    return Card(
      color: const Color(0xFF0F172A),
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('RESUMEN DEL ENTORNO',
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(
              '📡 Wi-Fi: ${wifi.length} redes ($open abiertas, $hidden ocultas, $g5 en 5 GHz)',
              style: s),
          Text('🔵 BLE: ${ble.length}${topTxt.isEmpty ? '' : ' → $topTxt'}',
              style: s),
          Text(
              '🕒 Nuevos en 5 min: ${sessionOld ? '$fresh' : '—'} · 📍 Fijos conocidos a <50 m: $_fixedNear',
              style: s),
        ]),
      ),
    );
  }

  Widget _alertsBanner() {
    if (!_showAlertBanner) return const SizedBox.shrink();
    final list = _devs.values
        .where((d) =>
            d.alerts.isNotEmpty &&
            !_alertsHidden.contains('${d.id}|${d.alerts.join(',')}'))
        .toList()
      ..sort((a, b) => b.smooth.compareTo(a.smooth));
    if (list.isEmpty) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFF3B0D0D),
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _filter = 'alert'),
                child: Text('⚠ ${list.length} alerta(s) cerca',
                    style: const TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                for (final d in list) {
                  _alertsHidden.add('${d.id}|${d.alerts.join(',')}');
                }
              }),
              child: const Text('Descartar'),
            ),
          ]),
          for (final d in list.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Text(
                '${d.alerts.join(' · ')} — ${d.title} (${d.smooth.round()} dBm, ~${d.distance.toStringAsFixed(0)} m)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _devicesTab() {
    final list = _visible;
    final nW = _devs.values.where((d) => d.type == DevType.wifi).length;
    final nB = _devs.values.where((d) => d.type == DevType.ble).length;
    final nA = _devs.values.where((d) => d.alerts.isNotEmpty).length;
    return Column(children: [
      _envCard(),
      _alertsBanner(),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Wrap(spacing: 6, children: [
          _chip('todos', 'Todos ${_devs.length}'),
          _chip('wifi', 'Wi-Fi $nW'),
          _chip('ble', 'BLE $nB'),
          _chip('alert', 'Alertas $nA'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar nombre, MAC, marca o tipo',
                prefixIcon: const Icon(Icons.search, size: 18),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          IconButton(
            tooltip: _sortSignal ? 'Orden: señal' : 'Orden: nombre',
            icon: Icon(
                _sortSignal ? Icons.signal_cellular_alt : Icons.sort_by_alpha),
            onPressed: () => setState(() => _sortSignal = !_sortSignal),
          ),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Sin señales todavía.\nToca "Escanear" y revisa los avisos amarillos de arriba.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 90),
                itemCount: list.length,
                itemBuilder: (_, i) => _devTile(list[i]),
              ),
      ),
    ]);
  }

  Widget _devTile(Dev d) {
    final i = d.ident;
    final isT = d.id == _targetId;
    final al = d.alerts;
    final hasAlert = al.isNotEmpty;
    final risk = riskOf(d);
    final Color color = hasAlert
        ? Colors.redAccent
        : (d.type == DevType.wifi ? Colors.cyanAccent : Colors.purpleAccent);
    final where = d.type == DevType.wifi
        ? ' · ${bandOf(d.freq ?? 2412)} ch ${d.channel ?? '?'}'
        : '';
    final head = '${i.type}${i.brand != null ? ' · ${i.brand}' : ''}';
    return Card(
      key: ValueKey(d.id),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isT
            ? const BorderSide(color: Colors.amberAccent, width: 2)
            : BorderSide.none,
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: Icon(iconFor(d), color: color, size: 20),
        ),
        title: Text(d.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 9, color: kRiskColors[risk.$1]),
            const SizedBox(width: 4),
            Expanded(
              child: Text(head,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          Text(
              '${d.smooth.round()} dBm · ~${d.distance.toStringAsFixed(1)} m$where${d.mine ? ' · mío' : ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
          if (hasAlert)
            Text('⚠ ${al.join(' · ')}',
                style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
        ]),
        trailing: IconButton(
          tooltip: 'Rastrear',
          icon: Icon(isT ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: isT ? Colors.amberAccent : Colors.white54),
          onPressed: () => _setTarget(d),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(_dossier(d),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'monospace')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  onPressed: () => _setTarget(d),
                  icon: const Icon(Icons.gps_fixed, size: 16),
                  label: const Text('Rastrear'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _toggleMine(d),
                  icon: const Icon(Icons.verified_user, size: 16),
                  label: Text(d.mine ? 'Quitar "mío"' : 'Es mío'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _anchorFor = d.id;
                      _tab = 3;
                      _mapReady = false;
                      _autoCentered = false;
                      _refreshMap();
                    });
                    _syncSensors();
                  },
                  icon: const Icon(Icons.push_pin, size: 16),
                  label: const Text('Fijar posición en mapa'),
                ),
                if (d.type == DevType.ble && d.device != null)
                  OutlinedButton.icon(
                    onPressed: d.gattBusy ? null : () => _readGatt(d),
                    icon: const Icon(Icons.bluetooth_connected, size: 16),
                    label: Text(d.gattBusy ? 'Leyendo…' : 'Leer GATT (nombre)'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _copy(_dossier(d), 'Ficha copiada'),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copiar ficha'),
                ),
              ]),
              if (d.type == DevType.ble)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                      '"Leer GATT" se conecta al dispositivo y trae su nombre real: úsalo solo con equipos tuyos.',
                      style: TextStyle(color: Colors.grey, fontSize: 10)),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  // ───── pestaña 2: cazador ─────

  Widget _hunterTab() {
    final t = _target;
    if (t == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.track_changes, size: 72, color: Colors.amberAccent),
            SizedBox(height: 16),
            Text('Elige un objetivo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              'En "Señales" toca el icono de mira (⌖) junto al dispositivo que quieres encontrar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ]),
        ),
      );
    }

    final age = DateTime.now().difference(t.lastSeen).inSeconds;
    final stale = age > (t.type == DevType.wifi ? 90 : 15);
    final Color color = stale ? Colors.grey : kLevelColors[t.level];
    final tr = t.trend;
    String trText = 'Calibrando tendencia…';
    if (tr != null) {
      trText = tr > 1.5
          ? '▲ Señal subiendo: te acercas'
          : (tr < -1.5 ? '▼ Señal bajando: te alejas' : '■ Señal estable');
    }
    final est = _estimate();
    final tri = _triangulate();
    final p = _pos;

    return ListView(padding: const EdgeInsets.all(14), children: [
      Card(
        color: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: color, width: 2)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(t.ident.type,
                        style: TextStyle(color: color, fontSize: 12)),
                    Text(t.id,
                        style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ]),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: _clearTarget),
          ]),
        ),
      ),
      if (t.type == DevType.wifi)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Wi-Fi se actualiza cada ~35 s (límite de Android). Para buscar caminando conviene un objetivo BLE.',
            style: TextStyle(color: Colors.amber, fontSize: 11),
          ),
        ),
      const SizedBox(height: 14),
      Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
            border: Border.all(color: color, width: 6),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 28,
                  spreadRadius: 3)
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(stale ? 'SIN SEÑAL' : kLevelLabels[t.level],
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${t.smooth.round()} dBm',
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            Text('≈ ${t.distance.toStringAsFixed(1)} m (muy aprox.)',
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Center(
          child: Text(trText,
              style: TextStyle(color: color, fontWeight: FontWeight.bold))),
      Center(
        child: Text('Crudo ${t.rssi} dBm · última lectura hace ${age}s',
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ),
      Center(
        child: Text(
          '${_still ? '🧍 quieto' : '🚶 en movimiento'} · $_steps pasos (≈ ${(_steps * 0.7).round()} m)',
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        height: 90,
        decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(
              painter: SparkPainter(t.history, color), size: Size.infinite),
        ),
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Modo Geiger'),
        subtitle: const Text('Vibra y suena más rápido cuanto más cerca',
            style: TextStyle(fontSize: 11)),
        value: _geiger,
        onChanged: _setGeiger,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Sonido'),
        value: _sound,
        onChanged: (v) => setState(() => _sound = v),
      ),
      const Divider(),
      const Text('Barrido de rumbo (brújula)',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(
        _sweepMsg ??
            'Sostené el celular horizontal, con la parte de arriba hacia adelante, y girá despacio sobre tu eje (~30 s por vuelta). La señal más fuerte marca hacia dónde está. Repetilo desde otro punto para triangular.',
        style: TextStyle(
            color: _sweepMsg != null ? Colors.amber : Colors.grey,
            fontSize: 11),
      ),
      const SizedBox(height: 8),
      Center(
        child: ValueListenableBuilder<int>(
          valueListenable: _radarTick,
          builder: (_, __, ___) => _radarView(),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _sweep ? _finishSweep : _startSweep,
          icon: Icon(_sweep ? Icons.stop : Icons.radar, size: 16),
          label: Text(_sweep ? 'Terminar barrido' : 'Iniciar barrido'),
        ),
        TextButton.icon(
          onPressed: _bearings.isEmpty
              ? null
              : () => setState(() {
                    _bearings.clear();
                    _bestBearing = null;
                  }),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: Text('Borrar rumbos (${_bearings.length})'),
        ),
      ]),
      if (tri != null && p != null)
        _triText(p, tri)
      else if (_bearings.length == 1)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Un rumbo guardado: repetí el barrido desde otro punto (a más de 5 m y en otro ángulo) para triangular.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
      const Divider(),
      const Text('Localización por recorrido',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text(
        'Camina alrededor del objetivo en distintas direcciones. Cada lectura se guarda con su posición GPS y se estima el punto donde la señal fue más fuerte. Con GPS pobre (interiores) el resultado sale desplazado.',
        style: TextStyle(color: Colors.grey, fontSize: 11),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Text('${_samples.length} muestras',
            style: const TextStyle(fontSize: 12)),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text('Reiniciar'),
          onPressed: () => setState(_samples.clear),
        ),
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('CSV'),
          onPressed: _samples.isEmpty
              ? null
              : () => _copy(_samplesCsv(), 'CSV de muestras copiado'),
        ),
      ]),
      SizedBox(
        height: 280,
        width: double.infinity,
        child: CustomPaint(
            painter:
                MapPainter(List.of(_samples), est, p, List.of(_bearings), tri)),
      ),
      const SizedBox(height: 8),
      if (est != null && p != null)
        _estimateText(p, est)
      else
        const Text('Hacen falta al menos 5 muestras para estimar.',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 60),
    ]);
  }

  Widget _estimateText(Pt p, (double, double) est) {
    final dist =
        Geolocator.distanceBetween(p.latitude, p.longitude, est.$1, est.$2);
    final brg =
        Geolocator.bearingBetween(p.latitude, p.longitude, est.$1, est.$2);
    final txt = dist < 3
        ? '¡Estás encima! Busca en un radio de ~3 m.'
        : 'Posible ubicación: a ~${dist.toStringAsFixed(0)} m hacia el ${cardinal(brg)} (${((brg + 360) % 360).toStringAsFixed(0)}°)';
    return Text(txt,
        style: const TextStyle(
            color: Colors.amberAccent, fontWeight: FontWeight.bold));
  }

  Widget _triText(Pt p, (double, double) tri) {
    final dist =
        Geolocator.distanceBetween(p.latitude, p.longitude, tri.$1, tri.$2);
    final brg =
        Geolocator.bearingBetween(p.latitude, p.longitude, tri.$1, tri.$2);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Triangulación (${_bearings.length} rumbos): a ~${dist.toStringAsFixed(0)} m hacia el ${cardinal(brg)}',
        style: const TextStyle(
            color: Colors.pinkAccent, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ───── pestaña 3: canales ─────

  Widget _channelsTab() {
    final c24 = <int, int>{};
    final c5 = <int, int>{};
    for (final d in _devs.values) {
      if (d.type != DevType.wifi ||
          d.channel == null ||
          d.freq == null ||
          d.freq! >= 5900) continue;
      final m = d.freq! < 3000 ? c24 : c5;
      m[d.channel!] = (m[d.channel!] ?? 0) + 1;
    }
    var best = 1, bestScore = 1 << 30;
    for (final c in [1, 6, 11]) {
      var s = 0;
      c24.forEach((ch, n) {
        if ((ch - c).abs() <= 4) s += n;
      });
      if (s < bestScore) {
        bestScore = s;
        best = c;
      }
    }
    return ListView(padding: const EdgeInsets.all(14), children: [
      const Text('Redes por canal',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      _bars('2.4 GHz', List.generate(13, (i) => i + 1), c24),
      if (c24.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              'Menos saturado entre 1/6/11: canal $best ($bestScore redes solapadas)',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
        ),
      const SizedBox(height: 20),
      _bars('5 GHz', c5.keys.toList()..sort(), c5),
      const SizedBox(height: 12),
      const Text(
        'Fórmula: 2.4 GHz → f = 2407 + 5·canal. 5 GHz → f = 5000 + 5·canal. Redes de 6 GHz no se cuentan aquí.',
        style: TextStyle(color: Colors.grey, fontSize: 11),
      ),
    ]);
  }

  Widget _bars(String title, List<int> channels, Map<int, int> counts) {
    if (channels.isEmpty) {
      return Text('$title: sin redes detectadas',
          style: const TextStyle(color: Colors.grey));
    }
    final maxC = counts.values.fold<int>(1, (a, b) => a > b ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final ch in channels)
            SizedBox(
              width: 30,
              height: 130,
              child:
                  Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${counts[ch] ?? 0}',
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 2),
                Container(
                  width: 18,
                  height: max(2.0, (counts[ch] ?? 0) * 85.0 / maxC),
                  decoration: BoxDecoration(
                    color: (counts[ch] ?? 0) == 0
                        ? Colors.white12
                        : Colors.cyanAccent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                Text('$ch',
                    style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ═══════════════════════ PAINTERS ═══════════════════════

void _drawText(Canvas c, String s, Offset o, Color color, double size) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 400);
  tp.paint(c, o);
}

class SparkPainter extends CustomPainter {
  final List<double> v;
  final Color color;
  SparkPainter(this.v, this.color);

  double _y(double r, double h) =>
      h - ((r.clamp(-100.0, -30.0).toDouble() + 100) / 70) * h;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;
    for (final r in [-40.0, -60.0, -80.0]) {
      final y = _y(r, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      _drawText(canvas, '${r.toInt()}', Offset(4, y - 12), Colors.white24, 9);
    }
    if (v.length < 2) return;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = _y(v[i], size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
        Offset(size.width, _y(v.last, size.height)), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant SparkPainter old) => true;
}

/// Radar polar: RSSI promedio por sector de 10° (norte arriba), rumbo actual y mejor rumbo.
class RadarPainter extends CustomPainter {
  final List<double?> bins;
  final double? heading;
  final double? best;
  RadarPainter(this.bins, this.heading, this.best);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = min(size.width, size.height) / 2 - 18;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0B1220));
    final ring = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, r, ring);
    canvas.drawCircle(c, r * 0.66, ring);
    canvas.drawCircle(c, r * 0.33, ring);
    _drawText(canvas, 'N', Offset(c.dx - 4, c.dy - r - 16), Colors.white70, 12);
    _drawText(canvas, 'S', Offset(c.dx - 4, c.dy + r + 2), Colors.white54, 12);
    _drawText(canvas, 'E', Offset(c.dx + r + 4, c.dy - 7), Colors.white54, 12);
    _drawText(canvas, 'O', Offset(c.dx - r - 14, c.dy - 7), Colors.white54, 12);

    final vals = bins.whereType<double>().toList();
    if (vals.isNotEmpty) {
      final lo = vals.reduce(min);
      final hi = vals.reduce(max);
      final span = max(hi - lo, 6.0);
      for (var i = 0; i < 36; i++) {
        final v = bins[i];
        if (v == null) continue;
        final t = ((v - lo) / span).clamp(0.0, 1.0).toDouble();
        final a = (i * 10 + 5) * pi / 180;
        final len = r * (0.15 + 0.85 * t);
        canvas.drawLine(
          c,
          c + Offset(sin(a) * len, -cos(a) * len),
          Paint()
            ..color = Color.lerp(Colors.redAccent, Colors.greenAccent, t)!
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    if (best != null) {
      final a = best! * pi / 180;
      canvas.drawLine(
        c,
        c + Offset(sin(a) * r, -cos(a) * r),
        Paint()
          ..color = Colors.amberAccent
          ..strokeWidth = 3,
      );
    }
    if (heading != null) {
      final a = heading! * pi / 180;
      final tip = c + Offset(sin(a) * r, -cos(a) * r);
      canvas.drawLine(
        c,
        tip,
        Paint()
          ..color = Colors.cyanAccent
          ..strokeWidth = 2,
      );
      canvas.drawCircle(tip, 6, Paint()..color = Colors.cyanAccent);
    }
    canvas.drawCircle(c, 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant RadarPainter old) => true;
}

class MapPainter extends CustomPainter {
  final List<Sample> samples;
  final (double, double)? est;
  final Pt? me;
  final List<Bearing> bearings;
  final (double, double)? tri;
  MapPainter(this.samples, this.est, this.me,
      [this.bearings = const [], this.tri]);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = const Color(0xFF0B1220),
    );

    final pts = <(double, double)>[
      for (final s in samples) (s.lat, s.lon),
      if (est != null) est!,
      if (me != null) (me!.latitude, me!.longitude),
    ];
    for (final b in bearings) {
      pts.add((b.lat, b.lon));
      final th = b.deg * pi / 180;
      pts.add((
        b.lat + 25 * cos(th) / 110540,
        b.lon + 25 * sin(th) / (111320 * cos(b.lat * pi / 180))
      ));
    }
    if (tri != null) pts.add(tri!);
    if (pts.isEmpty) {
      _drawText(canvas, 'Sin muestras todavía', Offset(14, size.height / 2 - 8),
          Colors.white38, 12);
      return;
    }

    final lat0 = pts.map((p) => p.$1).reduce((a, b) => a + b) / pts.length;
    final lon0 = pts.map((p) => p.$2).reduce((a, b) => a + b) / pts.length;
    final k = cos(lat0 * pi / 180);
    (double, double) toM(double lat, double lon) =>
        ((lon - lon0) * 111320 * k, (lat - lat0) * 110540);

    double minX = double.infinity,
        maxX = -double.infinity,
        minY = double.infinity,
        maxY = -double.infinity;
    for (final p in pts) {
      final m = toM(p.$1, p.$2);
      minX = min(minX, m.$1);
      maxX = max(maxX, m.$1);
      minY = min(minY, m.$2);
      maxY = max(maxY, m.$2);
    }
    final spanX = max(maxX - minX, 12.0);
    final spanY = max(maxY - minY, 12.0);
    const pad = 28.0;
    final scale =
        min((size.width - 2 * pad) / spanX, (size.height - 2 * pad) / spanY);
    final midX = (minX + maxX) / 2, midY = (minY + maxY) / 2;
    Offset toS(double lat, double lon) {
      final m = toM(lat, lon);
      return Offset(size.width / 2 + (m.$1 - midX) * scale,
          size.height / 2 - (m.$2 - midY) * scale);
    }

    if (samples.isNotEmpty) {
      final lo = samples.map((s) => s.rssi).reduce(min);
      final hi = samples.map((s) => s.rssi).reduce(max);
      final span = max(hi - lo, 6.0);
      for (final s in samples) {
        final t = ((s.rssi - lo) / span).clamp(0.0, 1.0).toDouble();
        canvas.drawCircle(
          toS(s.lat, s.lon),
          4.5,
          Paint()
            ..color = Color.lerp(Colors.redAccent, Colors.greenAccent, t)!
                .withValues(alpha: 0.9),
        );
      }
    }

    // rumbos del barrido de brújula
    final ray = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    for (final b in bearings) {
      final o = toS(b.lat, b.lon);
      final th = b.deg * pi / 180;
      canvas.drawLine(o, o.translate(sin(th) * 600, -cos(th) * 600), ray);
      canvas.drawCircle(o, 4, Paint()..color = Colors.cyanAccent);
    }
    if (tri != null) {
      final t = toS(tri!.$1, tri!.$2);
      final ring = Paint()
        ..color = Colors.pinkAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(t, 12, ring);
      canvas.drawCircle(t, 4, Paint()..color = Colors.pinkAccent);
    }

    if (est != null) {
      final o = toS(est!.$1, est!.$2);
      final ring = Paint()
        ..color = Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(o, 14, ring);
      canvas.drawCircle(o, 5, Paint()..color = Colors.amberAccent);
      canvas.drawLine(o.translate(-20, 0), o.translate(20, 0), ring);
      canvas.drawLine(o.translate(0, -20), o.translate(0, 20), ring);
    }

    if (me != null) {
      final o = toS(me!.latitude, me!.longitude);
      if (me!.speed > 0.6) {
        final h = me!.heading * pi / 180;
        canvas.drawLine(
          o,
          o.translate(sin(h) * 22, -cos(h) * 22),
          Paint()
            ..color = Colors.cyanAccent
            ..strokeWidth = 3,
        );
      }
      canvas.drawCircle(o, 7, Paint()..color = Colors.cyanAccent);
      canvas.drawCircle(
        o,
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    _drawText(canvas, 'N ↑', const Offset(10, 8), Colors.white54, 12);
    final nice = [1, 2, 5, 10, 20, 50, 100, 200, 500]
        .firstWhere((n) => n * scale >= 40, orElse: () => 500);
    final len = nice * scale;
    final y = size.height - 14;
    final bar = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2;
    canvas.drawLine(Offset(12, y), Offset(12 + len, y), bar);
    _drawText(canvas, '$nice m', Offset(16 + len, y - 7), Colors.white54, 11);
  }

  @override
  bool shouldRepaint(covariant MapPainter old) => true;
}
