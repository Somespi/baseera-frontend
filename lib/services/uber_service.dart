
import 'dart:convert';
import 'dart:math';

import 'package:basera/services/document.dart';
import 'package:basera/services/help_utilities.dart';
import 'package:basera/services/tfidf.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';

class UberService {

  // ignore: constant_identifier_names
  static const String SECRET = "V4pLaiZjvK1u5XN-yA5itLJbTNlnM_4Qil_gA6TS";

  // static dynamic requestRide(Map<String, double> pickup, Map<String, double> dropoff, String firstName, String lastName, String phoneNumber) async {
  //   String url = "$UBER_URL/trips";
  //   Map<String, dynamic> payload = {
  //     "guest": {
  //       "first_name": firstName,
  //       "last_name": lastName,
  //       "phone_number": phoneNumber
  //     },
  //     "end_latitude": dropoff['latitude'],
  //     "end_longitude":  dropoff['longitude'],
  //     "start_latitude": pickup['latitude'],
  //     "start_longitude": pickup['longitude'],
  //     "product_id": "a1c650ab-1a1e-4f35-ad16-2c38c7bb5b2a",
  //     "server_token": SECRET
  //   };

  //   Map<String, String> headers = {
  //     "Content-Type": "application/json",
  //     "Accept": "application/json",
  //     "x-uber-sandbox-runuuid": "1234567890",
  //     'Authorization': 'Bearer $SECRET'
  //   };
    
  //   var response = await post(Uri(scheme: url), body: json.encode(payload));
  //   return json.decode(response.body);
  // }


/// Function to create a sandbox run
Future<String> createSandboxRun({
  required Map<String, double> pickupLocation,
  required Map<String, double> dropoffLocation,
  required String parentProductTypeId,
}) async {
  const String endpoint = 'https://sandbox-api.uber.com/v1/guests/sandbox/run';

  final Map<String, dynamic> requestBody = {
    "driver_locations": [{}],
    "pickup_location": {
      "latitude": pickupLocation["latitude"],
      "longitude": pickupLocation["longitude"]
    },
    "dropoff_location": {
      "latitude": dropoffLocation["latitude"],
      "longitude": dropoffLocation["longitude"]
    },
    "parent_product_type_id": parentProductTypeId,
  };

  try {
    final response = await post(
      Uri.parse(endpoint),
      headers: {
        'Authorization': 'Bearer V4pLaiZjvK1u5XN-yA5itLJbTNlnM_4Qil_gA6TS',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      return responseBody['run_id'];
    } else {
      throw Exception('Failed to create sandbox run: ${response.body}');
    }
  } catch (e) {
    throw Exception('Error creating sandbox run: $e');
  }
}

Future<void> updateDriverState({
  required String runId,
  required String driverId,
  required String driverState,
}) async {
  const String endpoint = 'https://sandbox-api.uber.com/v1/guests/sandbox/driver-state';

  final Map<String, dynamic> requestBody = {
    "run_id": runId,
    "driver_id": driverId,
    "driver_state": driverState,
  };

  try {

    final response = await post(
      Uri.parse(endpoint),
      headers: {
        'Authorization': 'Bearer $SECRET',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      printDebug('Driver state updated successfully.');
    } else {
      final responseBody = jsonDecode(response.body);
      throw Exception(
          'Failed to update driver state: ${responseBody['message'] ?? response.body}');
    }
  } catch (e) {
    throw Exception('Error updating driver state: $e');
  }
}

  static Future<List<String>> loadTerms() async {
    return (await rootBundle.loadString("assets/taxi_phrases.txt"))
        .split('\n');
  }

  static double isRequestingTaxi(String phrase, List<String> terms) {
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

}