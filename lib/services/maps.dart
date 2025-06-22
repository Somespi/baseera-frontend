import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:basera/services/document.dart';
import 'package:basera/services/help_utilities.dart';
import 'package:basera/services/tfidf.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class Maps {
  static double   isRequestingDirections(String phrase, List<String> terms) {
    int i = 0;
    final sims = TfIdf(terms.map((e) => Document("${i++}", e)).toList()
      ..add(Document("$i", phrase)));
    var similarity = 0.0;
    for (int j = 0; j < terms.length; j++) {
      similarity = max(similarity, sims.calculateCosineSimilarity("$j", "$i"));
    }
    similarity = similarity;
    printDebug("Mean similarity: $similarity");
    return similarity;
  }
    // Create a list of documents, each with a word from the terms list.
    // The last document is the phrase we're trying to determine if it's asking
    // for directions.

  static Future<Position?> getCurrentPosition() async {
    await Geolocator.getCurrentPosition()

    // Calculate the cosine similarity between the phrase and each of the terms
    // in the list.
        .then((Position position) {
      return position;
      // Calculate the cosine similarity between the jth term and the phrase.
    });
    return null;

    // Print the mean similarity to the console.
  }


    // If the mean similarity is greater than 0.6, then the phrase is asking
    // for directions.
  static Future<dynamic> getDirections(
      Position origin, Position destination) async {
    final directionsSegments = await fetchSegmentsfromAPI(
        [origin.latitude, origin.longitude],
        [destination.latitude, destination.longitude]);
    printDebug(
      'Directions: $directionsSegments',
    );
    return;
  }

  static Future<dynamic> fetchSegmentsfromAPI(
      List<double> origin, List<double> destination) async {
    final url =
        Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car');
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Accept':
          'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8',
      'Authorization':
          '5b3ce3597851110001cf6248f04ad47b90f04844bbf81c5ee3fd7011',
    };
    final body = jsonEncode({
      "coordinates": [origin, destination]
    });

    printDebug('Origin: $origin, Destination: $destination');

    try {
      final response = await http.post(url, headers: headers, body: body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final segments = data['routes'][0]['segments'];
        final polyline = data['routes'][0]['geometry'];

        printDebug('Segments: $segments');
        return [segments, polyline];
      } else {
        printDebug('Failed to fetch directions: ${response.statusCode}');
      }
    } catch (e) {
      printDebug('Error: $e');
    }
    return null;
  }

  static double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3; // Earth's radius in meters
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final deltaPhi = (lat2 - lat1) * pi / 180;
    final deltaLambda = (lon2 - lon1) * pi / 180;

    final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // Distance in meters
  }

  static int? findCurrentStep(
      String polyline, List<dynamic> steps, double userLat, double userLon) {
    // Decode the polyline to get all route points
    final coordinates = decodePolyline(polyline);

    for (int i = 0; i < steps.length; i++) {
      // Get the start and end indices for this step
      int startIndex = steps[i]['way_points'][0];
      int endIndex = steps[i]['way_points'][1];

      // Get the coordinates for these indices
      List<double> startCoord = coordinates[startIndex];
      List<double> endCoord = coordinates[endIndex];

      // Calculate distances
      double distanceToLine = calculatePointToLineDistance(
        userLat,
        userLon,
        startCoord[0],
        startCoord[1],
        endCoord[0],
        endCoord[1],
      );

      if (distanceToLine < 50) {
        printDebug('User is on Step $i: ${steps[i]['instruction']}');
        return i;
      }
    }

    printDebug('User is not on any specific step');
    return null;
  }

// Point-to-Line Distance Formula
  static double calculatePointToLineDistance(
      double px, double py, double x1, double y1, double x2, double y2) {
    final A = px - x1;
    final B = py - y1;
    final C = x2 - x1;
    final D = y2 - y1;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    final param = lenSq != 0 ? dot / lenSq : -1;

    double xx, yy;

    if (param < 0) {
      xx = x1;
      yy = y1;
    } else if (param > 1) {
      xx = x2;
      yy = y2;
    } else {
      xx = x1 + param * C;
      yy = y1 + param * D;
    }

    final dx = px - xx;
    final dy = py - yy;

    return sqrt(dx * dx + dy * dy) * 111320;
  }

  static List<List<double>> decodePolyline(String polyline) {
    int index = 0;
    int len = polyline.length;
    int lat = 0;
    int lng = 0;
    List<List<double>> path = [];

    while (index < len) {
      int b, shift = 0, result = 0;

      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;

      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      path.add([lat / 1E5, lng / 1E5]);
    }

    return path;
  }

  static void directionService(List<double> destination) async {
    var origin = await getCurrentPosition();
    if (origin == null) {
      return;
    }
    final directionsSegments = await fetchSegmentsfromAPI(
        [origin.longitude, origin.latitude], destination);
    for (var i = 0; i < directionsSegments.length; i++) {
      final segment = directionsSegments[i];
      final steps = segment['steps'];
      final polyline = segment['geometry'];
      int? segmentIndex = Maps.findCurrentStep(
          polyline, steps, origin.latitude, origin.longitude);
      i = segmentIndex ?? i;
    }

    printDebug(
      'Directions: $directionsSegments',
    );
  }

  static Future<List<String>> loadTerms() async {
    return (await rootBundle.loadString("assets/maps/maps_phrases.txt"))
        .split('\n');
  }

  static List<String> instructionType = [
    'إتجّه يسارََا',
    'إتجّه يمينََا',
    'إنعطِف يسارََا',
    'إنعطِف يمينََا',
    'إنحدِر يسارََا',
    'إنحدِر يمينََا',
    '',
    '',
    '',
    '',
    'وصَلتَ إلى وِجهَتِكَ',
    'إمش في طريق مستقيم',
    '',
    'إستمر يمينا',
    'إستمر يسارا',
  ];

  static Future<Map<String, dynamic>?> getPositionOf(String location) async {
    final locations = await getSavedLocationsJSON();
    printDebug("getting position of $location");
    if (locations is List) {
      for (var loc in locations) {
        List<String> acronyms =
            (loc['acronyms'] as List<dynamic>).cast<String>();
        printDebug(acronyms);
        for (var acr in acronyms) {
          if (acr.contains(location)) {
            return loc;
          }
        }
      }
    }
    return null;
  }

  static Future<List> addLocation(
      String locationName, List<String> acronyms) async {
    final locations = await getSavedLocationsJSON();
    Position? origin;
    await Geolocator.getCurrentPosition()
        .then((Position position) {
      origin = position;
    });
    if (locations is List) {
      locations.add({
        'name': locationName,
        'acronyms': [locationName, ...acronyms],
        'position': origin
      });
      await File(
              '${(await getApplicationDocumentsDirectory()).path}/config_maps.json')
          .writeAsString(jsonEncode(locations));
    }
    return locations;
  }

  static Future<dynamic> getSavedLocationsJSON() async {
    final file = File(
        '${(await getApplicationDocumentsDirectory()).path}/config_maps.json');
    if (!file.existsSync()) {
      await file.create();
      await file.writeAsString('[]');
    }

    return await jsonDecode(await file.readAsString());
  }

  static deleteLocation(index) async {
    final locations = await getSavedLocationsJSON();
    if (locations is List) {
      locations.removeAt(index);
      File('${(await getApplicationDocumentsDirectory()).path}/config_maps.json')
          .writeAsString(jsonEncode(locations));
    }
  }

  static Future<Map<String, dynamic>?> getClosestLocation({
    required double latitude,
    required double longitude,
    required String placeName,
  }) async {
    final String url = "https://api.openrouteservice.org/geocode/search";

    try {
      final response = await http.get(
        Uri.parse(
          "$url?api_key=5b3ce3597851110001cf6248f04ad47b90f04844bbf81c5ee3fd7011&text=$placeName&focus.point.lon=$longitude&focus.point.lat=$latitude&size=1",
        ),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          return data['features'][0]['properties'];
        } else {
          printDebug("No matching locations found.");
          return null;
        }
      } else {
        printDebug("Failed to fetch data: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      printDebug("Error occurred: $e");
      return null;
    }
  }
}
